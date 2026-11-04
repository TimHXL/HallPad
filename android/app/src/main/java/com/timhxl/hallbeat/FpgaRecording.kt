package com.timhxl.hallbeat

import androidx.compose.runtime.*
import java.io.ByteArrayOutputStream
import java.io.DataOutputStream

/** 被动接收设备按键边沿，不向 FPGA 回发音符。时长按手机单调时钟记录。 */
internal class FpgaRecording(private val clock: () -> Long = { android.os.SystemClock.elapsedRealtime() }) {
    var recording by mutableStateOf(false)
        private set
    var count by mutableIntStateOf(0)
        private set
    var elapsedMs by mutableLongStateOf(0L)
        private set
    var reason by mutableStateOf("")
        private set
    private data class Note(val start: Long, val end: Long, val midi: Int, val velocity: Int)
    private val notes = mutableListOf<Note>()
    private val active = mutableMapOf<Int, Triple<Long, Int, Int>>()
    private var previous = 0L
    private var ignored = 0L
    private var started = 0L
    private var mapping = IntArray(35) { it }
    private var pitches = IntArray(35)
    private var strengths = IntArray(35) { 100 }
    private var tempo = 120
    private var beats = 4
    var selectedKey by mutableStateOf(ScoreKey(0, 0, false))
    private var denominator = 4
    private var leadInMs = 0.0
    fun start(sensorMap: IntArray, keyNotes: List<Int>, velocities: List<Int>, initialMask: Long, bpm: Int, numerator: Int, unit: Int, phaseMs: Double = 0.0) {
        require(sensorMap.size == 35 && sensorMap.toSet() == (0..34).toSet())
        require(keyNotes.size == 35 && keyNotes.all { it in 0..127 })
        clear()
        mapping = sensorMap.copyOf(); pitches = keyNotes.toIntArray(); strengths = velocities.map { it.coerceIn(0, 127) }.toIntArray()
        tempo = bpm.coerceIn(30, 240); beats = numerator.coerceIn(1, 12); denominator = unit
        leadInMs = phaseMs.takeIf { it.isFinite() && it >= 0.0 } ?: 0.0
        started = clock(); previous = initialMask; ignored = initialMask; recording = true
    }
    fun mask(value: Long) {
        if (!recording) return
        val now = (clock() - started).coerceAtLeast(0)
        if (now >= 300000L || count >= 10000) { stop("已达到录制上限"); return }
        ignored = ignored and value
        mapping.forEachIndexed { ui, sensor ->
            val bit = 1L shl sensor
            val down = value and bit != 0L
            val wasDown = previous and bit != 0L
            if (down && !wasDown && ignored and bit == 0L && strengths[ui] > 0 && count < 10000) { active[ui] = Triple(now, pitches[ui], strengths[ui]); count++ }
            if (!down && wasDown) active.remove(ui)?.let { notes.add(Note(it.first, maxOf(now, it.first + 1), it.second, it.third)) }
        }
        previous = value; elapsedMs = now
    }
    fun tick() {
        if (!recording) return
        elapsedMs = (clock() - started).coerceAtLeast(0)
        if (elapsedMs >= 300000L) stop("已达到5分钟录制上限")
    }
    fun stop(message: String = "") {
        if (!recording) return
        val now = (clock() - started).coerceAtLeast(0).coerceAtMost(300000L)
        active.values.forEach { notes.add(Note(it.first, maxOf(now, it.first + 1), it.second, it.third)) }
        active.clear(); elapsedMs = now; recording = false; reason = message
    }
    fun clear() { recording = false; notes.clear(); active.clear(); count = 0; elapsedMs = 0; reason = "" }
    fun finish(keySignature: ScoreKey = selectedKey): ByteArray {
        stop()
        require(notes.isNotEmpty()) { "尚未录到按键，请在设备上弹奏后保存" }
        val resolution = 480
        val micros = 60000000 / tempo
        fun tick(ms: Long): Int = kotlin.math.round((ms + leadInMs) * resolution * 1000.0 / micros).toInt()
        val events = notes.flatMap { listOf(Triple(tick(it.start), true, it), Triple(maxOf(tick(it.end), tick(it.start) + 1), false, it)) }.sortedWith(compareBy<Triple<Int, Boolean, Note>> { it.first }.thenBy { if (it.second) 1 else 0 })
        val track = ByteArrayOutputStream()
        fun vlq(value: Int) {
            var number = value
            val bytes = mutableListOf(number and 127)
            number = number ushr 7
            while (number > 0) { bytes.add((number and 127) or 128); number = number ushr 7 }
            bytes.asReversed().forEach { track.write(it) }
        }
        track.write(byteArrayOf(0, 0xFF.toByte(), 0x51, 3, (micros shr 16).toByte(), (micros shr 8).toByte(), micros.toByte()))
        val power = when (denominator) { 2 -> 1; 8 -> 3; 16 -> 4; else -> 2 }
        track.write(byteArrayOf(0, 0xFF.toByte(), 0x58, 4, beats.toByte(), power.toByte(), 24, 8))
        require(keySignature.sharps in -7..7)
        track.write(byteArrayOf(0, 0xFF.toByte(), 0x59, 2, keySignature.sharps.toByte(), if (keySignature.minor) 1.toByte() else 0.toByte()))
        var previousTick = 0
        events.forEach { (time, on, note) -> vlq(time - previousTick); track.write(if (on) 0x90 else 0x80); track.write(note.midi); track.write(if (on) note.velocity else 0); previousTick = time }
        track.write(byteArrayOf(0, 0xFF.toByte(), 0x2F, 0))
        val output = ByteArrayOutputStream()
        DataOutputStream(output).use { data -> data.writeInt(0x4D546864); data.writeInt(6); data.writeShort(0); data.writeShort(1); data.writeShort(resolution); data.writeInt(0x4D54726B); data.writeInt(track.size()); data.write(track.toByteArray()) }
        return output.toByteArray()
    }
}
