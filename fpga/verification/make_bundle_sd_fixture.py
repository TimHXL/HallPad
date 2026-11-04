from pathlib import Path
import struct,sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from midi_to_hpg2 import *
r=Path(__file__).resolve().parent
# Standards-sized FAT32 BPB, sparse sector map: MBR partition at LBA2048.
base=2048;reserved=32;spf=600;data=base+reserved+spf
pages={}
def sector(lba):return pages.setdefault(lba,bytearray(512))
def w32(b,o,v):struct.pack_into('<I',b,o,v)
m=sector(0);m[450]=12;w32(m,454,base);w32(m,458,70000);m[510:512]=b'\x55\xaa'
b=sector(base);b[0:3]=b'\xeb\x58\x90';struct.pack_into('<H',b,11,512);b[13]=1;struct.pack_into('<H',b,14,reserved);b[16]=1;w32(b,32,70000);w32(b,36,spf);w32(b,44,2);b[510:512]=b'\x55\xaa'
f=sector(base+reserved)
for c,n in {0:0xffffff8,1:0xfffffff,2:4,4:0xfffffff,5:9,9:7,7:11,11:0xfffffff,12:0xfffffff,13:0xfffffff,14:0xfffffff,15:0xfffffff}.items():w32(f,c*4,n)
for i in range(16):sector(data)[i*32]=0xe5
root=sector(data+2)
groups=[dict(start_ms=i*1000,duration_ms=300 if i%2==0 else 800,keys=[DEFAULT_MIDI.index([60,62,64][i%3])]) for i in range(64)]
main=encode(groups,midi=[n+1 for n in DEFAULT_MIDI],title='FRAGMENT TEST',timbre=[3]*35,fixed_mode=[1]*35,fixed_velocity=[87]*35);bad=bytearray(encode(groups[:1],title='BAD CRC'));bad[-1]^=1
badmap=bytearray(encode(groups[:1],title='BAD MAP'));badmap[20]^=1
badmeta=bytearray(encode(groups[:1]));badmeta[80]^=1
main=(r.parent/'sd_card/DEMO.HPG').read_bytes()
for c,n in {11:16,16:17,17:0xfffffff}.items():w32(f,c*4,n)
files=[('SCALE   HPG',main,[5,9,7,11,16,17]),('BADCRC  HPG',bad,[12]),('BADMAP  HPG',badmap,[13]),('LEGACY  HPG',encode(groups[:1],legacy=True),[14]),('MAPCRC  HPG',badmeta,[15])]
for i,(name,content,chain) in enumerate(files):
 o=i*32;root[o:o+11]=name.encode();root[o+11]=32;struct.pack_into('<H',root,o+26,chain[0]);w32(root,o+28,len(content))
 for j,c in enumerate(chain):
  chunk=content[j*512:(j+1)*512];sector(data+c-2)[:len(chunk)]=chunk
items=sorted(pages.items());(r/'bundle_sd_fixture.hex').write_text('\n'.join(f'{v:02x}' for _,b in items for v in b)+'\n')
(r/'bundle_sd_fixture_map.svh').write_text('function automatic integer page_for(input [31:0] lba);\n begin case(lba)\n'+''.join(f"32'd{lba}:page_for={i};\n" for i,(lba,_) in enumerate(items))+'default:page_for=-1;endcase end\nendfunction\n')
print(len(items),'sparse sectors')
