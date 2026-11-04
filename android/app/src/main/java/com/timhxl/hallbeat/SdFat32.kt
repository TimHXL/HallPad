package com.timhxl.hallbeat

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.zip.CRC32
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive

/** FAT32 allocator over exclusive 512-byte block transport; no preallocated files required. */
internal class SdFat32(private val readBlock: suspend (Long)->ByteArray,private val writeBlock: suspend (Long,ByteArray)->Unit) {
    data class Entry(val name: String,val cluster: Long,val size: Long,val lba: Long,val offset: Int)
    private var volume=0L;private var fat=0L;private var fatSize=0L;private var data=0L;private var root=0L;private var maxCluster=0L
    private var spc=0;private var copies=0;private var activeFat=0;private var mirrored=true;private var fsInfo=0L;private var backupInfo=0L;private var endLba=0L
    private val cache=object: LinkedHashMap<Long,ByteArray>(8,0.75f,true){override fun removeEldestEntry(e: MutableMap.MutableEntry<Long,ByteArray>?)=size>8}
    private fun u16(b:ByteArray,o:Int)=((b[o].toInt() and 255) or ((b[o+1].toInt() and 255) shl 8))
    private fun u32(b:ByteArray,o:Int)=ByteBuffer.wrap(b).order(ByteOrder.LITTLE_ENDIAN).getInt(o).toLong() and 0xffffffffL
    private fun put32(b:ByteArray,o:Int,n:Long){ByteBuffer.wrap(b).order(ByteOrder.LITTLE_ENDIAN).putInt(o,n.toInt())}
    private suspend fun read(lba:Long):ByteArray { currentCoroutineContext().ensureActive();return cache[lba]?.copyOf()?:readBlock(lba).also { require(it.size==512);cache[lba]=it.copyOf() } }
    private suspend fun write(lba:Long,b:ByteArray){require(lba in volume until endLba && b.size==512);currentCoroutineContext().ensureActive();writeBlock(lba,b);cache[lba]=b.copyOf()}
    private fun clusterLba(c:Long):Long { require(c in 2..maxCluster);return data+(c-2)*spc }
    suspend fun mount() {
        cache.clear();var boot=read(0)
        if(u16(boot,11)!=512){require(u16(boot,510)==0xaa55);require(boot[450].toInt() and 255 in listOf(11,12)){"需要 FAT32 主分区"};volume=u32(boot,454);require(volume>0);boot=read(volume)}else volume=0
        require(u16(boot,510)==0xaa55 && u16(boot,11)==512 && u16(boot,17)==0 && u16(boot,22)==0){"仅支持 512 字节扇区 FAT32"}
        spc=boot[13].toInt() and 255;val reserved=u16(boot,14);copies=boot[16].toInt() and 255;fatSize=u32(boot,36);root=u32(boot,44)
        val total=u32(boot,32);val flags=u16(boot,40);mirrored=flags and 128==0;activeFat=if(mirrored)0 else flags and 15
        require(spc in 1..128 && spc and (spc-1)==0 && copies in 1..2 && reserved>0 && activeFat<copies && fatSize>0 && u16(boot,42)==0)
        fat=volume+reserved;data=fat+copies*fatSize;endLba=volume+total;maxCluster=(endLba-data)/spc+1
        require(endLba<=0xffffffffL && maxCluster>=2 && maxCluster<fatSize*128 && root in 2..maxCluster)
        val info=u16(boot,48);val backup=u16(boot,50);fsInfo=if(info in 1 until reserved) volume+info else 0;backupInfo=if(backup>0 && backup+info<reserved && info>0)volume+backup+info else 0
        val entries=list();val published=entries.filter{it.name.endsWith(".HPG")}.map{it.cluster}.toSet()
        for(e in entries)if(e.name.endsWith(".TMP") && e.cluster in published){val sector=read(e.lba);sector[e.offset]=0xe5.toByte();write(e.lba,sector)}
    }
    private suspend fun next(c:Long):Long { val n=u32(read(fat+activeFat*fatSize+c/128),(c%128).toInt()*4) and 0x0fffffff;require(n>=0x0ffffff8 || n in 2..maxCluster){"FAT 链损坏"};return n }
    private suspend fun chain(start:Long):List<Long> { val out=ArrayList<Long>();val seen=HashSet<Long>();var c=start
        while(c<0x0ffffff8){require(c in 2..maxCluster && seen.add(c) && out.size<131072){"FAT 链循环或过长"};out.add(c);c=next(c)};return out }
    private suspend fun fatSet(c:Long,value:Long){require(c in 2..maxCluster);for(i in 0 until copies)if(mirrored || i==activeFat){val lba=fat+i*fatSize+c/128;val b=read(lba);val o=(c%128).toInt()*4;put32(b,o,(u32(b,o) and 0xf0000000L) or value);write(lba,b)}}
    private suspend fun invalidateInfo(){for(lba in listOf(fsInfo,backupInfo).filter{it!=0L}.distinct()){val b=read(lba);if(u32(b,0)==0x41615252L && u32(b,484)==0x61417272L){put32(b,488,0xffffffffL);put32(b,492,0xffffffffL);write(lba,b)}}}
    private suspend fun allocate():Long { for(sector in 0 until fatSize){val b=read(fat+activeFat*fatSize+sector);for(i in 0..127){val c=sector*128+i;if(c in 2..maxCluster && u32(b,i*4) and 0x0fffffff==0L){fatSet(c,0x0fffffff);return c}}};error("SD 卡空间不足") }
    private suspend fun rootSectors():List<Long> = chain(root).flatMap { c -> (0 until spc).map { clusterLba(c)+it } }
    private fun parse(b:ByteArray,lba:Long,o:Int):Entry? { val attr=b[o+11].toInt() and 255;val lead=b[o].toInt() and 255;if(lead==0 || lead==229 || attr and 0x18!=0 || attr==15)return null
        val stem=String(b,o,8,Charsets.US_ASCII).trimEnd();val ext=String(b,o+8,3,Charsets.US_ASCII).trimEnd();return Entry(if(ext.isEmpty())stem else "$stem.$ext",(u16(b,o+20).toLong() shl 16) or u16(b,o+26).toLong(),u32(b,o+28),lba,o) }
    suspend fun list():List<Entry> { val out=ArrayList<Entry>();for(lba in rootSectors()){val b=read(lba);for(o in 0..480 step 32){if(b[o]==0.toByte())return out;parse(b,lba,o)?.let{out.add(it)}}};return out }
    private suspend fun free(start:Long){if(start<2)return;val clusters=chain(start);for(c in clusters)fatSet(c,0)}
    suspend fun delete(entry:Entry){val b=read(entry.lba);val now=parse(b,entry.lba,entry.offset);require(now==entry){"目录已变化，请刷新"};b[entry.offset]=0xe5.toByte();write(entry.lba,b);free(entry.cluster);invalidateInfo()}
    private fun shortName(name:String):ByteArray { require(Regex("[A-Z0-9_]{1,8}\\.[A-Z0-9_]{1,3}").matches(name));val p=name.split('.');return (p[0].padEnd(8,' ')+p[1].padEnd(3,' ')).toByteArray(Charsets.US_ASCII) }
    private suspend fun slot():Pair<Long,Int> { for(lba in rootSectors()){val b=read(lba);for(o in 0..480 step 32)if(b[o]==0.toByte() || b[o]==0xe5.toByte())return lba to o}
        val last=chain(root).last();val added=allocate();for(i in 0 until spc)write(clusterLba(added)+i,ByteArray(512));fatSet(last,added);return clusterLba(added) to 0 }
    private suspend fun publish(lba:Long,o:Int,name:String,c:Long,size:Long){val b=read(lba);val wasEnd=b[o]==0.toByte();java.util.Arrays.fill(b,o,o+32,0.toByte());if(wasEnd && o<480)b[o+32]=0;
        if(wasEnd && o==480){val sectors=rootSectors();val at=sectors.indexOf(lba);if(at>=0 && at+1<sectors.size){val following=read(sectors[at+1]);following[0]=0;write(sectors[at+1],following)}};shortName(name).copyInto(b,o);b[o+11]=0x20;b[o+20]=(c shr 16).toByte();b[o+21]=(c shr 24).toByte();b[o+26]=c.toByte();b[o+27]=(c shr 8).toByte();put32(b,o+28,size);write(lba,b)}
    /** TEMP file is visible only as .TMP until whole-file readback CRC matches.
     * Interrupted attempts may be resumed using the same name and identical bytes.
     * Existing .HPG is retained until the replacement .TMP has passed verification. */
    suspend fun upload(name:String,bytes:ByteArray,replace:Boolean=false,progress:(Int,Int)->Unit={_,_->}) {
        require(name.endsWith(".HPG") && bytes.size in 88..64*1024*1024);shortName(name)
        var files=list();val old=files.find{it.name==name};require(old==null || replace){"同名文件已存在"};require(old!=null || files.count{it.name.endsWith(".HPG")}<256){"曲库已满 256 首"}
        val tempName=name.substringBefore('.')+".TMP";var temp=files.find{it.name==tempName}
        if(temp!=null && temp.size!=bytes.size.toLong()){delete(temp);temp=null}
        if(temp==null){invalidateInfo();val (lba,o)=slot();val first=allocate();publish(lba,o,tempName,first,bytes.size.toLong());temp=Entry(tempName,first,bytes.size.toLong(),lba,o)}
        val target=temp;val clusters=chain(target.cluster).toMutableList();val need=(bytes.size+512*spc-1)/(512*spc)
        while(clusters.size<need){val c=allocate();fatSet(clusters.last(),c);clusters.add(c)}
        // Compare sectors while resuming; matching sectors are not rewritten.
        for(s in 0 until (bytes.size+511)/512){val lba=clusterLba(clusters[s/spc])+s%spc;val want=ByteArray(512);bytes.copyInto(want,0,s*512,minOf(bytes.size,(s+1)*512));if(!read(lba).contentEquals(want))write(lba,want);progress(minOf(bytes.size,(s+1)*512),bytes.size)}
        cache.clear();val check=CRC32();for(s in 0 until (bytes.size+511)/512){val b=read(clusterLba(clusters[s/spc])+s%spc);check.update(b,0,minOf(512,bytes.size-s*512))};require(check.value==CRC32().apply{update(bytes)}.value){"写入校验失败，保留 TMP 供重试"}
        // Commit the new complete file before retiring the previous directory entry.
        if(old==null){publish(target.lba,target.offset,name,target.cluster,bytes.size.toLong())}
        else {
            // Update the existing name in one directory-sector commit; retain TMP
            // until that sector succeeds so a failed write never frees old data.
            publish(old.lba,old.offset,name,target.cluster,bytes.size.toLong())
            val b=read(target.lba);b[target.offset]=0xe5.toByte();write(target.lba,b);free(old.cluster)
        }
        invalidateInfo()
    }
}
