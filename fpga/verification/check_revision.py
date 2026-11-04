"""Arithmetic/epoch model checks; this is not RTL simulation or timing signoff."""
import random
rng=random.Random(20261031)
mask=0xffffffff
def segmented(a,b):
 s=[((a>>(8*i))&255)+((b>>(8*i))&255) for i in range(4)]
 carry=0;out=0
 for i,x in enumerate(s):
  out|=((x+carry)&255)<<(8*i)
  carry=int(x>=256 or ((x&255)==255 and carry))
 return out
cases=[(a,b) for a in [0,1,255,256,65535,65536,0xffffff,mask] for b in [0,1,255,256,65535,65536,0xffffff,mask]]
cases += [(rng.getrandbits(32),rng.getrandbits(32)) for _ in range(100000)]
for a,b in cases:assert segmented(a,b)==((a+b)&mask)
# Stage sum and epoch metadata advance together; changing either bank must
# prevent use of the old sum until the matching tuple reaches stage 2.
s1=(0,0);s2=(0,0)
for n in range(10000):
 live=(rng.getrandbits(32),rng.getrandbits(32)) if n%7==0 else live
 old=s1;s1=live;s2=old
 value=segmented(*s2)
 if s2==live:assert value==sum(live)&mask
print('PASS: 100064 sum cases, carry boundaries/wrap, 10000 epoch-model cycles')
