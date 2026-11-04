"""Arithmetic and ready/valid reference checks; not an RTL simulator."""
import random
from collections import deque

def divide_serial(n):
 q=rem=0
 for _ in range(14):
  trial=(rem<<1)|(n>>13)
  bit=int(trial>=127)
  rem=trial-127 if bit else trial
  q=((q<<1)|bit)&16383
  n=(n<<1)&16383
 return q
for velocity in range(128):
 for strength in range(128):
  result=divide_serial(velocity*strength+63)
  assert result==(velocity*strength+63)//127
  assert result<=127
# Transaction model: one captured transaction remains stable under backpressure;
# NONE and zero-strength transactions are consumed without emitting a hit.
rng=random.Random(31031)
inputs=deque((i,i%2,[0,5,255][i%3],i%128,(i*7)%128) for i in range(2000))
expected=[];got=[];current=None;remaining=0;waiting=False
for cycle in range(200000):
 ready=rng.randrange(4)!=0
 if current is None:
  if not inputs:break
  current=inputs.popleft();i,stick,voice,vel,strength=current
  scaled=divide_serial(vel*strength+63)
  if voice<6 and scaled:expected.append((i,stick,voice,scaled))
  remaining=16;waiting=False
 elif remaining:remaining-=1
 else:
  i,stick,voice,vel,strength=current;scaled=divide_serial(vel*strength+63)
  if voice>=6 or scaled==0:current=None
  elif ready:got.append((i,stick,voice,scaled));current=None
assert got==expected and not inputs and current is None
print('PASS: all 16384 velocity products and 2000 transaction-model cases with backpressure/NONE/zero')
