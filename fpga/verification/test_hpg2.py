import unittest,sys,struct,zlib
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from midi_to_hpg import encode,DEFAULT_MIDI,binding
class HPG2Test(unittest.TestCase):
 def test_full_mapping(self):
  midi=[n+1 for n in DEFAULT_MIDI];b=encode([dict(start_ms=0,duration_ms=400,keys=[20])],midi=midi,timbre=[3]*35,fixed_mode=[1]*35,fixed_velocity=[87]*35)
  self.assertEqual(struct.unpack_from('<4sHH',b),(b'HPG2',2,208));self.assertEqual(len(b),232)
  self.assertEqual(struct.unpack_from('<I',b,64)[0],zlib.crc32(b[68:208]));self.assertEqual(struct.unpack_from('<I',b,16)[0],zlib.crc32(b[208:]));self.assertEqual(struct.unpack_from('<I',b,20)[0],binding(midi,[1]*35))
  self.assertEqual(b[68+20*4:72+20*4],bytes([3,61,3,87]))
 def test_max_size(self):
  b=encode([dict(start_ms=i*10,duration_ms=5,keys=[20])for i in range(4096)])
  self.assertEqual(len(b),98512)
 def test_legacy(self):
  b=encode([dict(start_ms=0,duration_ms=100,keys=[20])],legacy=True);self.assertEqual(b[:4],b'HPG1');self.assertEqual(len(b),88)
 def test_invalid_mapping(self):
  g=[dict(start_ms=0,duration_ms=100,keys=[20])]
  for field,value in [('timbre',[10]*35),('fixed_mode',[2]*35),('fixed_velocity',[0]*35),('timbre',[0]*34)]:
   with self.subTest(field=field,value=value[0]):
    with self.assertRaises(ValueError):encode(g,**{field:value})
if __name__=='__main__':unittest.main()
