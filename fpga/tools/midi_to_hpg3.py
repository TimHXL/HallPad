#!/usr/bin/env python3
"""Build HPG3: selectable MIDI tracks, practice/playback objects, embedded 22x22 title."""
import argparse,json,struct,zlib,sys
from pathlib import Path
from collections import Counter,defaultdict
import midi_to_hpg2 as old

def track_count(path):
 data=Path(path).read_bytes()
 if not 14<=len(data)<=8*1024*1024 or data[:4]!=b'MThd':raise ValueError('MIDI size/header invalid (max 8 MiB)')
 if not 1<=struct.unpack_from('>H',data,10)[0]<=256:raise ValueError('MIDI needs 1..256 tracks')
 return struct.unpack_from('>H',data,10)[0]

def allocate(notes,provided=None,max_chord=10):
 original=list(notes)
 bystart=defaultdict(list)
 for note in notes:bystart[note[0]].append(note)
 notes=[]
 for chord in bystart.values():
  allowed=[]
  for note in sorted(chord,key=lambda x:(-x[3],-x[2])):
   if note[2] not in allowed and len(allowed)<max_chord:allowed.append(note[2])
  notes.extend(note for note in chord if note[2] in allowed)
 pitches=Counter(n for _,_,n,_ in notes)
 if provided:
  m=dict(provided);midi=m['midi'];enabled=m.get('enabled',[1]*35)
 else:
  m={};midi=list(old.DEFAULT_MIDI);enabled=[1]*35
  keep=sorted(pitches,key=lambda n:(-pitches[n],n))[:35]
  if any(not 0<=n<=127 for n in pitches):raise ValueError('transposed MIDI pitch outside 0..127')
  used={n:midi.index(n) for n in keep if n in midi}
  free=[i for i in range(35) if i not in used.values()]
  for n in sorted(set(keep)-used.keys()):
   key=min(free,key=lambda i:(abs(midi[i]-n),i));free.remove(key);midi[key]=n
 m['midi']=midi;m['enabled']=enabled
 lookup={n:i for i,n in enumerate(midi) if enabled[i]}
 kept=[x for x in notes if x[2] in lookup]
 return kept,m,len(original)-len(kept),sorted({x[2] for x in original if x not in kept})

def practice(notes,m):
 lookup={n:i for i,n in enumerate(m['midi']) if m['enabled'][i]};onsets=defaultdict(list)
 for a,b,n,v in notes:onsets[a].append((b,lookup[n],v))
 groups=[];starts=sorted(onsets)
 for i,a in enumerate(starts):
  chord=onsets[a];end=min(x[0] for x in chord)
  if i+1<len(starts):end=min(end,starts[i+1])
  groups.append(dict(start_ms=a,duration_ms=max(1,end-a),keys=[x[1] for x in chord],velocity=round(sum(x[2] for x in chord)/len(chord))))
 return groups

def playback(notes,m):
 lookup={n:i for i,n in enumerate(m['midi']) if m['enabled'][i]};edges=defaultdict(list)
 previous_end={}
 for a,b,n,v in sorted(notes,key=lambda x:(x[2],x[0],x[1])):
  original_a=a
  if previous_end.get(n)==a:a+=1;b=max(b,a+1)
  previous_end[n]=max(previous_end.get(n,0),b)
  edges[a].append((1,lookup[n],v));edges[b].append((-1,lookup[n],v))
 active=defaultdict(list);groups=[];times=sorted(edges)
 for i,t in enumerate(times):
  for on,k,v in sorted(edges[t]):
   if on<0:
    if v in active[k]:active[k].remove(v)
    if not active[k]:active.pop(k,None)
   else:active[k].append(v)
  if active and i+1<len(times):
   vs=[max(x) for x in active.values()]
   groups.append(dict(start_ms=t,duration_ms=times[i+1]-t,keys=sorted(active),velocity=round(sum(vs)/len(vs))))
 return groups

def glyphs(title,font_path):
 atlas=Path(__file__).resolve().parent/'fonts/title22.hga'
 if Path(font_path).resolve()==(atlas.parent/'NotoSansCJKsc-Regular.otf').resolve():
  if len(title)>32:raise ValueError('title supports at most 32 characters')
  data=atlas.read_bytes();count=struct.unpack_from('<I',data,4)[0];lookup={struct.unpack_from('<I',data,8+i*70)[0]:data[12+i*70:78+i*70] for i in range(count)}
  unique=list(dict.fromkeys(title))
  missing=[c for c in unique if ord(c) not in lookup]
  if missing:raise ValueError('font lacks title glyphs: '+''.join(missing))
  return bytes(unique.index(c) for c in title).ljust(32,b'\0'),b''.join(lookup[ord(c)] for c in unique),len(unique)
 from PIL import Image,ImageFont,ImageDraw
 from fontTools.ttLib import TTFont
 if len(title)>32:raise ValueError('title supports at most 32 characters (scrolls on FPGA)')
 font=ImageFont.truetype(str(font_path),22)
 tt=TTFont(str(font_path),fontNumber=0);cmap=tt.getBestCmap();tt.close()
 unique=list(dict.fromkeys(title))
 missing=[c for c in unique if ord(c) not in cmap]
 if missing:raise ValueError('font lacks title glyphs: '+''.join(missing))
 bitmap=bytearray()
 for c in unique:
  im=Image.new('L',(22,22));d=ImageDraw.Draw(im);box=font.getbbox(c)
  d.text(((22-box[2]+box[0])//2-box[0],(22-box[3]+box[1])//2-box[1]),c,font=font,fill=255)
  # HPG3 row-major: 22 MSB-first bits in three bytes, bottom two bits zero.
  for y in range(22):bitmap.extend((sum((im.getpixel((x,y))>=128)<<(23-x) for x in range(22))).to_bytes(3,'big'))
 return bytes(unique.index(c) for c in title).ljust(32,b'\0'),bytes(bitmap),len(unique)

def build(items,title,font_path,provided=None,max_chord=10):
 idx,bits,n=glyphs(title,font_path);entries=[];payload=[];report=[]
 base=96+32*len(items)+len(bits);offset=base
 for tid,notes in items:
  kept,m,skipped,missing=allocate(notes,provided,max_chord)
  if not kept:raise ValueError(f'track {tid}: no playable notes')
  pg=practice(kept,m);bg=playback(kept,m)
  for mode,groups in enumerate((pg,bg)):
   blob=old.encode(groups,title=title,**{k:m.get(k) for k in ['midi','enabled','timbre','fixed_mode','fixed_velocity']})
   entries.append(struct.pack('<IIIHH',offset,len(blob),skipped,tid,0));payload.append(blob);offset+=len(blob)
  report.append(dict(track=tid,notes=len(notes),skipped_notes=skipped,skipped_pitches=missing,practice_groups=len(pg),playback_groups=len(bg),mapping=m))
 if not 1<=len(items)<=257:raise ValueError('at most 256 MIDI tracks plus merged track')
 meta=b''.join(entries)+idx+bits
 header=bytearray(64);struct.pack_into('<4sHHBBBBI',header,0,b'HPG3',4,base,0,len(title),n,1,zlib.crc32(meta))
 struct.pack_into('<H',header,16,len(items))
 if offset>64*1024*1024:raise ValueError('HPG exceeds 64 MiB')
 return bytes(header)+meta+b''.join(payload),report

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('input');p.add_argument('output');p.add_argument('--title');p.add_argument('--font');p.add_argument('--track',type=int,action='append',help='zero-based, repeatable; absent keeps all note tracks plus merged');p.add_argument('--transpose',type=int,default=0);p.add_argument('--mapping-json');p.add_argument('--max-chord',type=int,default=10,help='maximum distinct pitches per onset, 1..35; default 10');a=p.parse_args()
 try:
  out=Path(a.output)
  if not 1<=a.max_chord<=35:raise ValueError('--max-chord must be 1..35')
  if out.suffix!='.HPG' or not 1<=len(out.stem)<=8 or any(c not in 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_' for c in out.stem):raise ValueError('use uppercase 8.3 output name')
  font=a.font or str(Path(__file__).resolve().parent/'fonts/NotoSansCJKsc-Regular.otf')
  if not font:raise ValueError('supply --font path/to/font.ttf (Pillow and fonttools required)')
  title=a.title or Path(a.input).stem
  tracks=a.track if a.track is not None else list(range(track_count(a.input)))
  count=track_count(a.input)
  if any(t<0 or t>=count for t in tracks):raise ValueError('track index outside MIDI track range')
  items=[]
  for t in dict.fromkeys(tracks):
   notes=old.read_midi(a.input,[t],a.transpose,old.DEFAULT_MIDI,[1]*35,raw_notes=True)
   if notes:items.append((t,notes))
  if len(items)>1:items.insert(0,(65535,sorted(x for _,ns in items for x in ns)))
  provided=json.loads(Path(a.mapping_json).read_text(encoding='utf-8')) if a.mapping_json else None
  blob,report=build(items,title,font,provided,a.max_chord);out.write_bytes(blob)
  out.with_suffix('.json').write_text(json.dumps(dict(title=title,tracks=report),ensure_ascii=False,indent=2),encoding='utf-8')
  print(f'{out}: HPG3, {len(items)} selections, {len(blob)} bytes')
  for r in report:print(f"track {r['track']}: {r['notes']} notes, skipped {r['skipped_notes']}, missing {r['skipped_pitches']}")
 except (ValueError,OSError,IndexError,KeyError,struct.error) as e:p.error(str(e))
if __name__=='__main__':main()
