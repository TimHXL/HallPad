import sys,struct,zlib,tempfile,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from midi_to_hpg import encode,read_midi,DEFAULT_MIDI,binding
class ConverterTests(unittest.TestCase):
 def midi(self,track):
  return struct.pack('>4sIHHH',b'MThd',6,0,1,480)+struct.pack('>4sI',b'MTrk',len(track))+track
 def parse(self,data):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d)/'test.mid';p.write_bytes(data);return read_midi(p,None,0,DEFAULT_MIDI,[1]*35)
 def test_tempo_and_crc(self):
  track=b'\0\xff\x51\x03\x07\xa1\x20\0\x90\x3c\x64\x83\x60\xff\x51\x03\x03\xd0\x90\x83\x60\x80\x3c\0\0\xff\x2f\0'
  g=self.parse(self.midi(track));self.assertEqual(g[0]['duration_ms'],750)
  b=encode(g,legacy=True);self.assertEqual(len(b),88);self.assertEqual(struct.unpack_from('<I',b,16)[0],zlib.crc32(b[64:]));self.assertEqual(struct.unpack_from('<I',b,20)[0],binding(DEFAULT_MIDI,[1]*35))
 def test_running_status_chord(self):
  track=b'\0\x90\x3c\x64\0\x40\x64\x83\x60\x3c\0\0\x40\0\0\xff\x2f\0'
  g=self.parse(self.midi(track));self.assertEqual(len(g[0]['keys']),2);self.assertEqual(g[0]['duration_ms'],500)
 def test_unmappable_pitch_rejected(self):
  with self.assertRaises(ValueError):self.parse(self.midi(b'\0\x90\x3d\x64\x83\x60\x80\x3d\0\0\xff\x2f\0'))
 def test_truncated_and_empty(self):
  with self.assertRaises(ValueError):self.parse(b'')
  with self.assertRaises(ValueError):encode([])
if __name__=='__main__':unittest.main()
