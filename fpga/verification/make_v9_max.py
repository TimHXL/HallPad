from pathlib import Path
import sys,struct
p=Path(__file__).resolve().parents[1];sys.path.insert(0,str(p/'tools'));import midi_to_hpg3 as c
notes=[(0,100,60,100)];items=[(65535,notes*256)]+[(i,notes) for i in range(256)];title='天地玄黄宇宙洪荒日月盈昃辰宿列张ABCDEFGHIJKLMNOPQRSTUVWXYZ'[:32]
b,_=c.build(items,title,p/'tools/fonts/NotoSansCJKsc-Regular.otf');r=p/'verification';(r/'v9_max.hpg').write_bytes(b);(r/'v9_max.hex').write_text('\n'.join(f'{x:02x}' for x in b)+'\n');off,size,*_=struct.unpack_from('<IIIHH',b,64+513*16);(r/'v9_max_selected.hex').write_text('\n'.join(f'{x:02x}' for x in b[off:off+size])+'\n');(r/'v9_max_sizes.svh').write_text(f'localparam SIZE={len(b)},SELECTED_SIZE={size};\n');print(len(b),size,title)
