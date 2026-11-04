import sys,struct,random,subprocess
from pathlib import Path
p=Path(__file__).resolve().parents[1];sys.path.insert(0,str(p/'tools'));import midi_to_hpg3 as c
r=random.Random(1903);work=p/'verification/parity_out';work.mkdir(exist_ok=True)
def vl(n):
 x=[n&127];n>>=7
 while n:x.insert(0,128|(n&127));n>>=7
 return bytes(x)
def tr(events):
 events.sort(key=lambda e:e[0]);last=0;data=b''
 for t,e in events:data+=vl(t-last)+e;last=t
 data+=b'\0\xff\x2f\0';return b'MTrk'+struct.pack('>I',len(data))+data
lines=[]
for test in range(25):
 nt=256 if test==24 else r.randint(1,12);ppq=r.choice([96,480,960,32767]);tracks=[]
 for tid in range(nt):
  ev=[(0,b'\xff\x51\x03'+r.choice([333333,500000,600001]).to_bytes(3,'big'))] if tid==0 else []
  for j in range(2 if nt==256 else 20):
   a=j*ppq+r.randrange(max(1,ppq//3));n=r.randint(36,90);v=r.randint(1,127);dur=r.randint(1,max(1,ppq//3));ev.extend([(a,bytes([0x90,n,v])),(a+dur,bytes([0x80,n,0]))])
  tracks.append(tr(ev))
 mid=work/f'T{test}.mid';mid.write_bytes(b'MThd'+struct.pack('>IHHH',6,1,nt,ppq)+b''.join(tracks));title=('欢乐颂测试Abc123-'*3)[:32] if test%2 else 'Test😀' if False else '混合 Title 123';transpose=r.choice([-2,0,2])
 items=[]
 for t in range(nt):
  ns=c.old.read_midi(mid,[t],transpose,c.old.DEFAULT_MIDI,[1]*35,raw_notes=True)
  if ns:items.append((t,ns))
 if len(items)>1:items.insert(0,(65535,sorted(x for _,ns in items for x in ns)))
 out=work/f'PC{test}.HPG';blob,_=c.build(items,title,p/'tools/fonts/NotoSansCJKsc-Regular.otf');out.write_bytes(blob)
 lines.append(f'{mid.resolve()}\t{title}\t{(work/f"KT{test}.HPG").resolve()}\t{transpose}')
(work/'cases.tsv').write_text('\n'.join(lines))
subprocess.run(['java','-cp','/tmp/parity.jar:/tmp/kotlinc/*','com.hallpad.verification.Parity_mainKt',str(p/'tools/fonts/title22.hga'),str(work/'cases.tsv')],check=True)
for i in range(25):assert(work/f'PC{i}.HPG').read_bytes()==(work/f'KT{i}.HPG').read_bytes(),i
print('PASS 25 byte-identical Python/Kotlin fixtures; variable PPQ/tempo/transpose/chords, 32 mixed characters, 256 tracks + ALL')
