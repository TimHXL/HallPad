#!/usr/bin/env python3
"""Standard-library MIDI/JSON -> HallPad HPG1. No FPGA MIDI parsing needed."""
import argparse,json,struct,zlib
from pathlib import Path
from fractions import Fraction
NATURAL=(0,2,4,5,7,9,11)
DEFAULT_MIDI=[36+((n-1)//7)*12+NATURAL[(n-1)%7] for n in range(35,0,-1)]
def binding(midi,enabled):
    return zlib.crc32(bytes(x for pair in zip(enabled,midi) for x in pair))
def encode(groups,midi=None,enabled=None,title='HALLPAD',timbre=None,fixed_mode=None,fixed_velocity=None,legacy=False):
    midi=DEFAULT_MIDI if midi is None else midi;enabled=[1]*35 if enabled is None else enabled
    if len(midi)!=35 or len(enabled)!=35 or any(not 0<=n<=127 for n in midi) or any(n not in (0,1) for n in enabled):raise ValueError('mapping requires 35 MIDI values and 35 enabled flags')
    records=[];last=-1;maximum=0
    for i,g in enumerate(groups):
        start=int(g['start_ms']);duration=int(g['duration_ms']);velocity=int(g.get('velocity',100));keys=sorted(set(map(int,g['keys'])))
        if start<=last or start<0 or duration<=0 or start+duration>86400000 or not 1<=velocity<=127 or not keys or any(not 0<=k<35 or not enabled[k] for k in keys):raise ValueError('invalid group '+str(i))
        mask=sum(1<<k for k in keys);records.append(struct.pack('<IIIQBBH',i,start,duration,mask,len(keys),velocity,int(len(keys)>1)));last=start;maximum=max(maximum,start+duration)
    if not 1<=len(records)<=4096:raise ValueError('score must contain 1..4096 onset groups')
    body=b''.join(records);name=title.encode('ascii','replace')[:32].ljust(32,b'\0')
    if legacy:return struct.pack('<4sHHIIII32s8s',b'HPG1',1,64,len(records),maximum,zlib.crc32(body),binding(midi,enabled),name,b'\0'*8)+body
    timbre=[0]*35 if timbre is None else timbre
    fixed_mode=[0]*35 if fixed_mode is None else fixed_mode
    fixed_velocity=[100]*35 if fixed_velocity is None else fixed_velocity
    if any(len(x)!=35 for x in (timbre,fixed_mode,fixed_velocity)):raise ValueError('full mapping fields need 35 entries')
    if any(x not in (0,1,2,3,4,5,6,7,8,9,11,13,14) for x in timbre) or any(x not in (0,1) for x in fixed_mode) or any(not 1<=x<=127 for x in fixed_velocity):raise ValueError('invalid full mapping')
    mapping=bytes(v for i in range(35) for v in (enabled[i]|(fixed_mode[i]<<1),midi[i],timbre[i],fixed_velocity[i]))
    return struct.pack('<4sHHIIII32s8s',b'HPG2',2,208,len(records),maximum,zlib.crc32(body),binding(midi,enabled),name,b'\0'*8)+struct.pack('<I',zlib.crc32(mapping))+mapping+body

def vlq(data,pos):
    value=0
    for _ in range(4):
        if pos>=len(data):raise ValueError('truncated MIDI VLQ')
        b=data[pos];pos+=1;value=(value<<7)|(b&127)
        if b<128:return value,pos
    raise ValueError('MIDI VLQ too long')
def read_midi(path,track_filter,transpose,midi,enabled,raw_notes=False):
    data=Path(path).read_bytes()
    if data[:4]!=b'MThd' or len(data)<14:raise ValueError('missing MThd')
    hlen=struct.unpack_from('>I',data,4)[0];fmt,tracks,division=struct.unpack_from('>HHH',data,8)
    if fmt not in (0,1) or division==0 or division&0x8000:raise ValueError('only MIDI format 0/1 with PPQ timing supported')
    pos=8+hlen;events=[]
    for track in range(tracks):
        if data[pos:pos+4]!=b'MTrk':raise ValueError('missing MTrk')
        size=struct.unpack_from('>I',data,pos+4)[0];chunk=data[pos+8:pos+8+size];pos+=8+size
        if len(chunk)!=size:raise ValueError('truncated MTrk')
        tick=0;p=0;running=None;order=0
        while p<len(chunk):
            delta,p=vlq(chunk,p);tick+=delta;status=chunk[p]
            if status&128:p+=1
            elif running is not None:status=running
            else:raise ValueError('invalid running status')
            if status==255:
                running=None;meta=chunk[p];p+=1;ln,p=vlq(chunk,p);value=chunk[p:p+ln];p+=ln
                if meta==81 and ln==3:events.append((tick,0,track,order,'tempo',int.from_bytes(value,'big')))
                if meta==47:break
            elif status in (240,247):
                running=None;ln,p=vlq(chunk,p);p+=ln
            elif 128<=status<240:
                running=status;count=1 if status>>4 in (12,13) else 2;v=chunk[p:p+count];p+=count
                if len(v)!=count:raise ValueError('truncated channel event')
                if status&15!=9 and (track_filter is None or track in track_filter) and status>>4 in (8,9):
                    on=status>>4==9 and v[1]!=0
                    events.append((tick,1,track,order,'on' if on else 'off',(track,status&15,v[0]+transpose,v[1])))
            else:raise ValueError('unsupported MIDI system event')
            order+=1
    events.sort(key=lambda e:e[:4]);tempo=500000;lasttick=0;us=Fraction(0);active={};notes=[]
    for tick,_,track,order,kind,value in events:
        us+=Fraction((tick-lasttick)*tempo,division);lasttick=tick;ms=round(us/1000)
        if kind=='tempo':
            if value<=0:raise ValueError('zero tempo')
            tempo=value;continue
        t,ch,n,vel=value;key=(t,ch,n)
        if kind=='on':
            if key in active:raise ValueError('overlapping same-pitch Note On; clean MIDI first')
            active[key]=(ms,vel)
        elif key in active:
            start,v=active.pop(key);notes.append((start,max(start+1,ms),n,v))
    if active:raise ValueError('MIDI contains notes without Note Off')
    if raw_notes:return notes
    mapping={n:i for i,n in enumerate(midi) if enabled[i]}
    bystart={}
    for start,end,n,vel in notes:
        if n not in mapping:raise ValueError(f'MIDI pitch {n} cannot map to an enabled key; select track/transpose or provide mapping JSON')
        bystart.setdefault(start,[]).append((end,mapping[n],vel))
    starts=sorted(bystart);groups=[]
    for i,start in enumerate(starts):
        chord=bystart[start];end=min(x[0] for x in chord)
        if i+1<len(starts):end=min(end,starts[i+1])
        groups.append(dict(start_ms=start,duration_ms=max(1,end-start),keys=[x[1] for x in chord],velocity=round(sum(x[2] for x in chord)/len(chord))))
    return groups

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('input');p.add_argument('output');p.add_argument('--legacy',action='store_true',help='emit HPG1 without mapping');p.add_argument('--title',default='HALLPAD');p.add_argument('--track',type=int,action='append',help='zero-based track, repeatable');p.add_argument('--transpose',type=int,default=0);p.add_argument('--mapping-json',help='{"midi":[35 values],"enabled":[35 flags]}');args=p.parse_args()
    out=Path(args.output)
    if out.suffix.upper()!='.HPG' or not 1<=len(out.stem)<=8 or any(c not in 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_' for c in out.stem):p.error('output must use uppercase 8.3 name, e.g. STAR.HPG')
    midi=DEFAULT_MIDI;enabled=[1]*35;m={}
    if args.mapping_json:
        m=json.loads(Path(args.mapping_json).read_text());midi=m['midi'];enabled=m.get('enabled',[1]*35)
    try:
        if Path(args.input).suffix.lower()=='.json':groups=json.loads(Path(args.input).read_text())['groups']
        else:groups=read_midi(args.input,args.track,args.transpose,midi,enabled)
        b=encode(groups,midi,enabled,args.title,timbre=m.get('timbre'),fixed_mode=m.get('fixed_mode'),fixed_velocity=m.get('fixed_velocity'),legacy=args.legacy);out.write_bytes(b);print(f'{out}: {len(groups)} groups, {len(b)} bytes, binding {binding(midi,enabled):08X}')
    except (ValueError,IndexError,struct.error,KeyError) as e:p.error(str(e))
if __name__=='__main__':main()
