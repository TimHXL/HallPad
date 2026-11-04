package com.timhxl.hallbeat

import java.io.ByteArrayInputStream
import java.io.DataInputStream

internal data class ScoreNote(val tick: Long, val duration: Long, val midi: Int, val velocity: Int, val channel: Int)
internal data class ScoreTrack(val index: Int, val name: String, val notes: List<ScoreNote>)
internal data class ScoreTempo(val tick: Long, val micros: Int)
internal data class ScoreMeter(val tick: Long, val numerator: Int, val denominator: Int)
internal data class ScoreKey(val tick: Long, val sharps: Int, val minor: Boolean)
internal data class MidiScore(val resolution: Int, val tracks: List<ScoreTrack>, val tempos: List<ScoreTempo>, val meters: List<ScoreMeter>, val keys: List<ScoreKey>) {
    // Built once per immutable score; both conversion directions share the same tempo map.
    internal val timing: ScoreTiming by lazy { ScoreTiming(resolution, tempos) }
    fun seconds(tick: Long): Double = timing.seconds(tick)
    fun keyLabel(tick: Long = 0): String {
        val key = keys.lastOrNull { it.tick <= tick } ?: return "未提供调号"
        return scoreKeyName(key)
    }
    fun noteName(midi: Int, tick: Long): String {
        val flats = (keys.lastOrNull { it.tick <= tick }?.sharps ?: 0) < 0
        val names = if (flats) listOf("C", "D♭", "D", "E♭", "E", "F", "G♭", "G", "A♭", "A", "B♭", "B") else listOf("C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B")
        return names[midi % 12] + (midi / 12 - 1)
    }
    // 按调号配置自然音键位，保留原调；不改用户的音色与力度。
    fun mappedNote(base: Int): Int {
        val key = keys.lastOrNull { it.tick == 0L } ?: return base
        val order = if (key.sharps >= 0) listOf(5, 0, 7, 2, 9, 4, 11) else listOf(11, 4, 9, 2, 7, 0, 5)
        return (base + if (base % 12 in order.take(kotlin.math.abs(key.sharps))) { if (key.sharps > 0) 1 else -1 } else 0).coerceIn(0, 127)
    }
}

internal object MidiScoreParser {
    fun parse(bytes: ByteArray): MidiScore {
        require(bytes.size <= 8 * 1024 * 1024) { "MIDI 文件不能超过 8 MB" }
        val input = DataInputStream(ByteArrayInputStream(bytes))
        require(input.readInt() == 0x4D546864) { "不是标准 MIDI 文件" }
        val header = input.readInt(); require(header in 6..1024 && header <= input.available()) { "MIDI 文件头损坏" }
        val format = input.readUnsignedShort(); require(format in 0..1) { "第一版支持 MIDI 格式 0 和 1" }
        val count = input.readUnsignedShort(); require(count in 1..256 && (format != 0 || count == 1)) { "音轨数量无效" }
        val resolution = input.readUnsignedShort(); require(resolution in 1..32767) { "暂不支持 SMPTE 时间格式" }
        input.skipBytes(header - 6)
        val tempos = mutableListOf<ScoreTempo>(); val meters = mutableListOf<ScoreMeter>(); val keys = mutableListOf<ScoreKey>(); val tracks = mutableListOf<ScoreTrack>()
        var eventCount = 0
        repeat(count) { trackIndex ->
            require(input.readInt() == 0x4D54726B) { "音轨头损坏" }
            val length = input.readInt(); require(length >= 0 && length <= input.available()) { "音轨长度无效" }
            val track = DataInputStream(ByteArrayInputStream(ByteArray(length).also { input.readFully(it) }))
            var tick = 0L; var running = 0; var name = "音轨 ${trackIndex + 1}"
            val notes = mutableListOf<ScoreNote>(); val active = mutableMapOf<Int, java.util.ArrayDeque<Pair<Long, Int>>>()
            fun vlq(): Int { var result = 0; repeat(4) { val b = track.readUnsignedByte(); result = (result shl 7) or (b and 127); if (b < 128) return result }; error("MIDI 变长整数无效") }
            while (track.available() > 0) {
                require(++eventCount <= 500000) { "MIDI 事件过多" }
                tick += vlq(); require(tick <= 1000000000L) { "曲目过长" }
                val first = track.readUnsignedByte(); val status = if (first >= 128) first else running
                require(status >= 128) { "MIDI 运行状态无效" }
                if (status == 255) {
                    running = 0
                    val type = track.readUnsignedByte(); val size = vlq(); require(size <= track.available()) { "元事件不完整" }
                    val data = ByteArray(size).also { track.readFully(it) }
                    when (type) {
                        3 -> name = data.toString(Charsets.UTF_8).take(80)
                        0x51 -> { require(size == 3); val micros = ((data[0].toInt() and 255) shl 16) or ((data[1].toInt() and 255) shl 8) or (data[2].toInt() and 255); require(micros > 0); tempos.add(ScoreTempo(tick, micros)) }
                        0x58 -> { require(size == 4 && data[0].toInt() > 0 && data[1].toInt() in 0..7); meters.add(ScoreMeter(tick, data[0].toInt(), 1 shl data[1].toInt())) }
                        0x59 -> { require(size == 2 && data[0].toInt() in -7..7 && data[1].toInt() in 0..1); keys.add(ScoreKey(tick, data[0].toInt(), data[1].toInt() == 1)) }
                    }
                    if (type == 0x2F) break
                } else if (status == 0xF0 || status == 0xF7) {
                    running = 0; val size = vlq(); require(size <= track.available()); track.skipBytes(size)
                } else {
                    require(status in 0x80..0xEF) { "不支持的 MIDI 事件" }; running = status
                    val a = if (first < 128) first else track.readUnsignedByte(); require(a < 128)
                    val kind = status and 0xF0; val b = if (kind == 0xC0 || kind == 0xD0) 0 else track.readUnsignedByte(); require(b < 128)
                    val channel = status and 15; val id = channel * 128 + a
                    if (kind == 0x90 && b > 0) active.getOrPut(id) { java.util.ArrayDeque() }.addLast(tick to b)
                    if (kind == 0x80 || (kind == 0x90 && b == 0)) active[id]?.pollFirst()?.let { notes.add(ScoreNote(it.first, (tick - it.first).coerceAtLeast(1), a, it.second, channel)) }
                }
            }
            active.forEach { (id, pending) -> pending.forEach { notes.add(ScoreNote(it.first, (tick - it.first).coerceAtLeast(1), id % 128, it.second, id / 128)) } }
            tracks.add(ScoreTrack(trackIndex, name, notes.sortedBy { it.tick }))
        }
        require(tracks.any { it.notes.isNotEmpty() }) { "MIDI 中没有可练习的音符" }
        return MidiScore(resolution, tracks, tempos.sortedBy { it.tick }, meters.sortedBy { it.tick }, keys.sortedBy { it.tick })
    }
}

/** 原始 MIDI 保留不变；打击乐通道保持原音高，调号随旋律移调。 */
internal fun MidiScore.transposed(semitones: Int): MidiScore {
    require(semitones in -12..12)
    if (semitones == 0) return this
    require(tracks.all { track -> track.notes.all { it.channel == 9 || it.midi + semitones in 0..127 } }) { "移调超出 MIDI 音域" }
    return copy(tracks = tracks.map { track -> track.copy(notes = track.notes.map { if (it.channel == 9) it else it.copy(midi = it.midi + semitones) }) }, keys = keys.map { signature ->
        val pitch = Math.floorMod(signature.sharps * 7 + semitones, 12)
        val accidental = (-7..7).filter { Math.floorMod(it * 7, 12) == pitch }.minWith(compareBy<Int> { kotlin.math.abs(it) }.thenBy { if (signature.sharps < 0 && it > 0) 1 else 0 })
        if (semitones % 12 == 0) signature else signature.copy(sharps = accidental)
    })
}


/** 按实际秒数反算曲谱位置；拖动和节奏指示共用，支持变速事件。 */
internal fun MidiScore.tickAtSeconds(seconds: Double): Double = timing.tick(seconds)

/** 调号名称沿用 MIDI 标准的升降号数量与大小调标记。 */
internal fun scoreKeyName(key: ScoreKey): String {
    val major = listOf("C♭", "G♭", "D♭", "A♭", "E♭", "B♭", "F", "C", "G", "D", "A", "E", "B", "F♯", "C♯")
    val minor = listOf("A♭", "E♭", "B♭", "F", "C", "G", "D", "A", "E", "B", "F♯", "C♯", "G♯", "D♯", "A♯")
    return (if (key.minor) minor else major)[key.sharps + 7] + if (key.minor) " 小调" else " 大调"
}
