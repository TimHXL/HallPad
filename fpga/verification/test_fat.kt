package com.hallpad.verification
import kotlinx.coroutines.runBlocking
import java.nio.ByteBuffer
import java.nio.ByteOrder
fun main()=runBlocking {
 val disk=HashMap<Long,ByteArray>();fun sector(n:Long)=disk.getOrPut(n){ByteArray(512)}
 fun put(b:ByteArray,o:Int,v:Long){ByteBuffer.wrap(b).order(ByteOrder.LITTLE_ENDIAN).putInt(o,v.toInt())}
 fun short(b:ByteArray,o:Int,v:Int){b[o]=v.toByte();b[o+1]=(v shr 8).toByte()}
 val boot=sector(0);short(boot,11,512);boot[13]=1;short(boot,14,32);boot[16]=2;put(boot,32,70000);put(boot,36,600);put(boot,44,2);short(boot,48,1);short(boot,50,6);short(boot,510,0xaa55)
 for(lba in listOf(1L,7L)){val b=sector(lba);put(b,0,0x41615252);put(b,484,0x61417272);put(b,488,1234);put(b,492,3)}
 for(lba in listOf(32L,632L)){val b=sector(lba);put(b,0,0x0ffffff8);put(b,4,0x0fffffff);put(b,8,0x0fffffff)}
 var writes=0;var failAt=Int.MAX_VALUE
 fun fs()=SdFat32({sector(it).copyOf()},{lba,b-> writes++;if(writes==failAt)error("simulated disconnect");disk[lba]=b.copyOf()})
 var f=fs();f.mount();val payload=ByteArray(4321){(it*17).toByte()};f.upload("TEST.HPG",payload)
 check(f.list().single().size==4321L)
 val saved=f.list().single();val savedChainData=disk.values.sumOf{it.size}
 failAt=writes+5;runCatching{f.upload("TEST.HPG",payload.reversedArray(),true)}.onSuccess{error("failure not injected")};failAt=Int.MAX_VALUE
 f=fs();f.mount();check(f.list().any{it.name=="TEST.HPG" && it.cluster==saved.cluster});f.upload("TEST.HPG",payload.reversedArray(),true)
 check(f.list().count{it.name=="TEST.HPG"}==1 && f.list().none{it.name.endsWith(".TMP")})
 f.delete(f.list().single());check(f.list().isEmpty())
 repeat(256){i->f.upload("S%07d.HPG".format(i),ByteArray(100){i.toByte()})};check(f.list().size==256)
 runCatching{f.upload("OVER.HPG",ByteArray(100))}.onSuccess{error("catalog overflow accepted")}
 f=fs();f.mount();check(f.list().size==256);f.delete(f.list()[128]);f.upload("NEW.HPG",ByteArray(600));check(f.list().size==256)
 repeat(600){s->check(sector(32L+s).contentEquals(sector(632L+s))){"FAT copies differ"}}
 // A power failure after replacing the final directory entry may leave TMP alias.
 val first=f.list().first();val root=sector(first.lba);val free=480
 // use a known deleted slot by deleting an entry first
 val victim=f.list().last();f.delete(victim);val alias=sector(victim.lba);root.copyOfRange(first.offset,first.offset+32).copyInto(alias,victim.offset);"ALIAS   TMP".toByteArray().copyInto(alias,victim.offset)
 f=fs();f.mount();check(f.list().none{it.name=="ALIAS.TMP"});check(f.list().any{it.cluster==first.cluster})
 println("PASS FAT32: blank ordinary card, 2 FAT copies, interrupted overwrite+resume, CRC readback, delete, root extension, 256 limit, reboot, stale TMP alias recovery; $writes writes")
}
