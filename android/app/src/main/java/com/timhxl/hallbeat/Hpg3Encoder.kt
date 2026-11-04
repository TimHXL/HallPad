package com.timhxl.hallbeat

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.zip.CRC32

/** Canonical HPG3 v4 encoder. Integer timing and shared HGA1 glyphs match tools/midi_to_hpg3.py. */
internal object Hpg3Encoder {
    data class Note(val start: Int, val end: Int, val pitch: Int, val velocity: Int)
    private data class Event(val tick: Long, val rank: Int, val track: Int, val order: Int, val kind: Int, val channel: Int, val note: Int, val velocity: Int)
    private data class Group(val start: Int, val duration: Int, val keys: List<Int>, val velocity: Int)
    data class Output(val bytes: ByteArray, val skipped: Int, val tracks: Int, val title: String)
    fun codePoints(text: String): IntArray { val values=ArrayList<Int>();var i=0;while(i<text.length){val cp=Character.codePointAt(text,i);values.add(cp);i+=Character.charCount(cp)};return values.toIntArray() }
    private fun le(n: Int) = ByteBuffer.allocate(n).order(ByteOrder.LITTLE_ENDIAN)
    private fun crc(b: ByteArray) = CRC32().apply { update(b) }.value.toInt()
    private fun even(n: Long, d: Long): Int { val q=n/d;val r=n%d;return (q + if(r*2>d || (r*2==d && q%2!=0L)) 1 else 0).toInt() }
    private val defaults = IntArray(35) { i -> val n=34-i;36+n/7*12+intArrayOf(0,2,4,5,7,9,11)[n%7] }
    private fun parse(bytes: ByteArray, transpose: Int): List<Pair<Int,List<Note>>> {
        require(bytes.size in 14..8*1024*1024) { "MIDI 文件大小无效" }
        val b=ByteBuffer.wrap(bytes).order(ByteOrder.BIG_ENDIAN)
        fun tag()=b.int
        require(tag()==0x4d546864)
        val hlen=b.int;val format=b.short.toInt() and 65535;val tracks=b.short.toInt() and 65535;val division=b.short.toInt() and 65535
        require(hlen>=6 && format in 0..1 && tracks in 1..256 && division in 1..32767) { "仅支持 MIDI 0/1、PPQ 时基" };b.position(8+hlen)
        val events=ArrayList<Event>();var total=0
        repeat(tracks) { track ->
            require(tag()==0x4d54726b);val size=b.int;require(size>=0 && size<=b.remaining());val end=b.position()+size;var tick=0L;var running=0;var order=0
            fun byte(): Int { require(b.position()<end) { "MIDI 数据被截断" };return b.get().toInt() and 255 }
            fun vlq(): Int { var value=0;repeat(4) { val x=byte();value=(value shl 7) or (x and 127);if(x<128)return value };error("MIDI VLQ 过长") }
            while(b.position()<end) {
                tick=Math.addExact(tick,vlq().toLong());require(tick<=1_000_000_000L);var status=byte()
                if(status<128) { require(running!=0);b.position(b.position()-1);status=running }
                when {
                    status==255 -> { running=0;val meta=byte();val len=vlq();require(len<=end-b.position());val stop=b.position()+len
                        if(meta==81 && len==3) { val tempo=(byte() shl 16) or (byte() shl 8) or byte();require(tempo>0);events.add(Event(tick,0,track,order,0,0,0,tempo)) }
                        b.position(stop);if(meta==47)break
                    }
                    status==240 || status==247 -> { running=0;val len=vlq();require(len<=end-b.position());b.position(b.position()+len) }
                    status in 128..239 -> { running=status;val n=byte();val v=if(status shr 4 in 12..13) 0 else byte();require(n<128 && v<128)
                        if(status and 15!=9 && status shr 4 in 8..9)events.add(Event(tick,1,track,order,if(status shr 4==9 && v!=0) 1 else 2,status and 15,n+transpose,v))
                    }
                    else -> error("不支持的 MIDI 系统事件")
                }
                order++;total++;require(total<=500_000)
            }
            b.position(end)
        }
        events.sortWith(compareBy<Event>({it.tick},{it.rank},{it.track},{it.order}))
        var tempo=500000;var last=0L;var numerator=0L
        val active=HashMap<Triple<Int,Int,Int>,Pair<Int,Int>>();val notes=List(tracks) { ArrayList<Note>() }
        for(e in events) {
            numerator=Math.addExact(numerator,Math.multiplyExact(e.tick-last,tempo.toLong()));last=e.tick
            val ms=even(numerator,division.toLong()*1000);require(ms in 0..86400000) { "曲目最长 24 小时" }
            if(e.kind==0) { tempo=e.velocity;continue }
            val key=Triple(e.track,e.channel,e.note)
            if(e.kind==1) { require(!active.containsKey(key)) { "同音重叠，请先清理 MIDI" };active[key]=Pair(ms,e.velocity) }
            else active.remove(key)?.let { notes[e.track].add(Note(it.first,maxOf(it.first+1,ms),e.note,it.second)) }
        }
        require(active.isEmpty()) { "存在缺少 Note Off 的音符" }
        val result=notes.mapIndexedNotNull { i,n -> if(n.isEmpty()) null else i to n.toList() }.toMutableList()
        require(result.isNotEmpty()) { "没有可演奏音轨（不含第10通道打击乐）" }
        if(result.size>1)result.add(0,65535 to result.flatMap { it.second }.sortedWith(compareBy({it.start},{it.end},{it.pitch},{it.velocity})))
        return result
    }
    private fun allocate(notes: List<Note>): Pair<List<Note>,IntArray> {
        val filtered=notes.groupBy { it.start }.values.flatMap { chord ->
            val allowed=chord.sortedWith(compareBy({-it.velocity},{-it.pitch})).map { it.pitch }.distinct().take(10).toSet()
            chord.filter { it.pitch in allowed }
        }
        require(filtered.all { it.pitch in 0..127 }) { "移调后超出 MIDI 音高范围" }
        val counts=filtered.groupingBy { it.pitch }.eachCount();val keep=counts.keys.sortedWith(compareBy({-(counts[it]?:0)},{it})).take(35)
        val midi=defaults.copyOf();val used=keep.filter { it in midi }.map { midi.indexOf(it) }.toSet();val free=(0..34).filter { it !in used }.toMutableList()
        for(n in keep.filter { it !in midi }.sorted()) { val k=free.minWith(compareBy({kotlin.math.abs(midi[it]-n)},{it}));free.remove(k);midi[k]=n }
        return filtered.filter { it.pitch in midi } to midi
    }
    private fun practice(notes: List<Note>, midi: IntArray): List<Group> {
        val onsets=notes.groupBy { it.start }.toSortedMap();val starts=onsets.keys.toList()
        return starts.mapIndexed { i,a -> val chord=onsets.getValue(a);val end=minOf(chord.minOf { it.end },starts.getOrElse(i+1) { Int.MAX_VALUE });Group(a,maxOf(1,end-a),chord.map { midi.indexOf(it.pitch) },even(chord.sumOf { it.velocity.toLong() },chord.size.toLong())) }
    }
    private fun playback(notes: List<Note>,midi: IntArray): List<Group> {
        data class Edge(val on: Int,val key: Int,val velocity: Int)
        val previous=HashMap<Int,Int>();val edges=java.util.TreeMap<Int,MutableList<Edge>>()
        for(n in notes.sortedWith(compareBy({it.pitch},{it.start},{it.end}))) {
            var a=n.start;var end=n.end;if(previous[n.pitch]==a) { a++;end=maxOf(end,a+1) };previous[n.pitch]=maxOf(previous[n.pitch]?:0,end)
            val k=midi.indexOf(n.pitch);edges.getOrPut(a){ArrayList()}.add(Edge(1,k,n.velocity));edges.getOrPut(end){ArrayList()}.add(Edge(-1,k,n.velocity))
        }
        val active=HashMap<Int,MutableList<Int>>();val result=ArrayList<Group>();val times=edges.keys.toList()
        for((i,t) in times.withIndex()) {
            for(e in edges.getValue(t).sortedWith(compareBy({it.on},{it.key},{it.velocity}))) {
                if(e.on<0) { active[e.key]?.remove(e.velocity);if(active[e.key]?.isEmpty()==true)active.remove(e.key) }
                else active.getOrPut(e.key){ArrayList()}.add(e.velocity)
            }
            if(active.isNotEmpty() && i+1<times.size) { val vs=active.values.map { it.max() };result.add(Group(t,times[i+1]-t,active.keys.sorted(),even(vs.sumOf { it.toLong() },vs.size.toLong()))) }
        }
        return result
    }
    private fun hpg2(groups: List<Group>,midi: IntArray,title: IntArray): ByteArray {
        require(groups.size in 1..4096) { "单音轨事件数超过 4096，请分段转换" }
        val body=le(groups.size*24)
        groups.forEachIndexed { i,g -> val keys=g.keys.distinct().sorted();require(g.start>=0 && g.duration>0 && g.start.toLong()+g.duration<=86400000);val mask=keys.fold(0L){m,k->m or (1L shl k)}
            body.putInt(i).putInt(g.start).putInt(g.duration).putLong(mask).put(keys.size.toByte()).put(g.velocity.toByte()).putShort(if(keys.size>1)1 else 0) }
        val mapping=ByteArray(140);val binding=ByteArray(70)
        repeat(35){i -> mapping[i*4]=1;mapping[i*4+1]=midi[i].toByte();mapping[i*4+3]=100;binding[i*2]=1;binding[i*2+1]=midi[i].toByte() }
        val out=le(208+body.capacity());out.put("HPG2".toByteArray()).putShort(2).putShort(208).putInt(groups.size).putInt(groups.maxOf { it.start+it.duration }).putInt(crc(body.array())).putInt(crc(binding))
        val ascii=ByteArray(32);title.take(32).forEachIndexed { i,c -> ascii[i]=(if(c<=127)c else 63).toByte() };out.put(ascii).putLong(0).putInt(crc(mapping)).put(mapping).put(body.array());return out.array()
    }
    fun encode(midiBytes: ByteArray,title: String,atlas: ByteArray,transpose: Int=0): Output {
        val chars=codePoints(title);require(chars.size in 1..32) { "曲名限 1–32 字" }
        require(atlas.size>=8 && String(atlas,0,4,Charsets.US_ASCII)=="HGA1")
        val a=ByteBuffer.wrap(atlas).order(ByteOrder.LITTLE_ENDIAN);val count=a.getInt(4);require(atlas.size==8+count*70)
        fun glyph(cp: Int): ByteArray { var lo=0;var hi=count-1;while(lo<=hi){val mid=(lo+hi) ushr 1;val c=a.getInt(8+mid*70);if(c==cp)return atlas.copyOfRange(12+mid*70,78+mid*70);if(c<cp)lo=mid+1 else hi=mid-1};error("曲名字库缺字：${String(Character.toChars(cp))}") }
        val unique=chars.distinct();val bits=unique.flatMap { glyph(it).toList() }.toByteArray();val indices=ByteArray(32);chars.forEachIndexed { i,c -> indices[i]=unique.indexOf(c).toByte() }
        val items=parse(midiBytes,transpose);val base=96+items.size*32+bits.size;val directory=le(items.size*32);val objects=ArrayList<ByteArray>();var offset=base;var skippedTotal=0
        for((tid,notes) in items) { val (kept,mapping)=allocate(notes);require(kept.isNotEmpty());val skipped=notes.size-kept.size;if(tid==65535 || items.size==1)skippedTotal=skipped
            for(groups in listOf(practice(kept,mapping),playback(kept,mapping))) { val blob=hpg2(groups,mapping,chars);directory.putInt(offset).putInt(blob.size).putInt(skipped).putShort(tid.toShort()).putShort(0);objects.add(blob);offset+=blob.size }
        }
        require(offset<=64*1024*1024)
        val metadata=directory.array()+indices+bits;val out=le(offset);out.put("HPG3".toByteArray()).putShort(4).putShort(base.toShort()).put(0).put(chars.size.toByte()).put(unique.size.toByte()).put(1).putInt(crc(metadata)).putShort(items.size.toShort());out.position(64);out.put(metadata);objects.forEach { out.put(it) }
        return Output(out.array(),skippedTotal,items.size,title)
    }
}
