from pathlib import Path
import struct,sys
p=Path(__file__).resolve().parents[1];sys.path.insert(0,str(p/'tools'));from midi_to_hpg2 import encode
pages={}
def sec(n):return pages.setdefault(n,bytearray(512))
def w(b,o,v):struct.pack_into('<I',b,o,v)
b=sec(0);struct.pack_into('<H',b,11,512);b[13]=1;struct.pack_into('<H',b,14,32);b[16]=1;w(b,32,70000);w(b,36,600);w(b,44,2);b[510:512]=b'\x55\xaa'
f=sec(32);w(f,0,0xffffff8);w(f,4,0xfffffff)
for c in range(2,18):w(f,c*4,c+1 if c<17 else 0xfffffff)
w(f,18*4,0xfffffff);blob=encode([dict(start_ms=0,duration_ms=100,keys=[20])]);sec(648)[:len(blob)]=blob
for i in range(256):
 b=sec(632+i//16);o=(i%16)*32;b[o:o+11]=(f'S{i:07d}'+'HPG').encode();b[o+11]=32;struct.pack_into('<H',b,o+26,18);w(b,o+28,len(blob))
items=sorted(pages.items());r=p/'verification';(r/'v9_catalog.hex').write_text('\n'.join(f'{v:02x}' for _,b in items for v in b)+'\n');(r/'v9_catalog_map.svh').write_text('function automatic integer page_for(input[31:0]lba);begin case(lba)\n'+''.join(f"32'd{lba}:page_for={i};\n" for i,(lba,_) in enumerate(items))+'default:page_for=-1;endcase end endfunction\n');print('catalog pages',len(items))
