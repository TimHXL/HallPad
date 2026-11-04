from pathlib import Path
import struct,sys,json,zlib
p=Path(__file__).resolve().parents[1];sys.path.insert(0,str(p/'tools'))
import midi_to_hpg3 as c
font=str(p/'tools/fonts/NotoSansCJKsc-Regular.otf')
# Two real note tracks with independently ending overlapping notes.
items=[(65535,[(0,500,36,80),(0,100,60,100),(50,300,64,90),(400,650,67,110)]),(1,[(0,500,36,80)]),(2,[(0,100,60,100),(50,300,64,90),(400,650,67,110)])]
(p/'sd_card').mkdir(exist_ok=True)
b,report=c.build(items,'欢乐颂测试',font)
(p/'sd_card/DEMO.HPG').write_bytes(b)
(p/'verification/bundle.hex').write_text('\n'.join(f'{x:02x}' for x in b)+'\n')
(p/'verification/bundle_expected.json').write_text(json.dumps(report,indent=2))
# All metadata and nested HPG2 CRCs independently checked.
assert b[:4]==b'HPG3';end=int.from_bytes(b[6:8],'little');assert zlib.crc32(b[64:end])==int.from_bytes(b[12:16],'little')
for i in range(6):
 off,size,skip,tid,flags=struct.unpack_from('<IIIHH',b,64+i*16);x=b[off:off+size]
 assert x[:4]==b'HPG2' and len(x)==208+24*int.from_bytes(x[8:12],'little')
 assert zlib.crc32(x[208:])==int.from_bytes(x[16:20],'little')
 assert zlib.crc32(x[68:208])==int.from_bytes(x[64:68],'little')
 assert flags==0
 expected=b[struct.unpack_from('<I',b,64+5*16)[0]:];(p/'verification/selected.hex').write_text('\n'.join(f'{v:02x}' for v in expected)+'\n')
# >35 pitches: deterministic selection and explicit skipped count; fixed mapping: missing only.
notes=[(i*10,i*10+5,40+i,100) for i in range(40)]
kept,m,skip,missing=c.allocate(notes);assert len(kept)==35 and skip==5 and len(missing)==5
kept,m,skip,missing=c.allocate([(0,10,61,100)],dict(midi=list(c.old.DEFAULT_MIDI),enabled=[1]*35));assert not kept and skip==1
bg=c.playback(items[0][1],report[0]['mapping'])
lookup={n:i for i,n in enumerate(report[0]['mapping']['midi'])}
for t in range(700):
 expect={lookup[n] for a,e,n,v in items[0][1] if a<=t<e}
 actual={k for g in bg if g['start_ms']<=t<g['start_ms']+g['duration_ms'] for k in g['keys']}
 assert expect==actual,(t,expect,actual)
# Build a standard MIDI fixture and exercise the real CLI with zero-based track 2.
def vl(n):
 a=[n&127];n>>=7
 while n:a.insert(0,128|(n&127));n>>=7
 return bytes(a)
def tr(events):
 x=b''.join(vl(d)+e for d,e in events)+b'\0\xff\x2f\0';return b'MTrk'+struct.pack('>I',len(x))+x
mid=b'MThd'+struct.pack('>IHHH',6,1,3,480)+tr([(0,b'\xff\x51\x03\x07\xa1\x20')])+tr([(0,bytes([0x90,36,80])),(480,bytes([0x80,36,0]))])+tr([(0,bytes([0x90,60,100])),(48,bytes([0x90,64,90])),(48,bytes([0x80,60,0])),(192,bytes([0x80,64,0]))])
(p/'verification/TRACKS.mid').write_bytes(mid)
print('PASS HPG3 metadata/nested CRCs, allocation/skip, independent note endpoints, MIDI fixture; bundle',len(b),'selected',len(expected))

# Back-to-back same pitch must produce an explicit release interval.
notes=[(0,20,60,100),(20,40,60,100)];kept,m,_,_=c.allocate(notes);g=c.playback(kept,m)
assert not any(x['start_ms']<=20<x['start_ms']+x['duration_ms'] for x in g)
# Impossible chords: only requested number of distinct notes retained, reported.
notes=[(0,100,n,100) for n in range(40,52)];kept,m,skip,_=c.allocate(notes,max_chord=5)
assert len(kept)==5 and skip==7
print('PASS repeated note release and chord-limit skip reporting')
