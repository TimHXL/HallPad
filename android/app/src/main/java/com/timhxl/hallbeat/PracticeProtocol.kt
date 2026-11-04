package com.timhxl.hallbeat

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.zip.CRC32
import kotlinx.coroutines.flow.MutableStateFlow

internal data class PracticeGroup(val index: Int, val startMs: Int, val durationMs: Int, val mask: Long, val notes: Int, val velocity: Int)
internal data class PracticeSong(val groups: List<PracticeGroup>, val bytes: ByteArray, val crc: Int, val bindingCrc: Int, val durationMs: Int)
internal data class PracticeResult(val runId: Int, val total: Int, val correct: Int, val missed: Int, val wrong: Int, val timingCount: Int, val absoluteTimingMs: Int, val elapsedMs: Int, val score: Int, val demo: Boolean, val partial: Boolean = false)
internal data class PracticeStatus(val phase: String = "IDLE", val transferred: Int = 0, val totalBytes: Int = 0, val group: Int = 0, val correct: Int = 0, val wrong: Int = 0, val elapsedMs: Int = 0, val target: Long = 0, val result: PracticeResult? = null, val error: String = "")

internal object PracticeWire {
    const val CAPABILITY = 18
    fun buffer(size: Int): ByteBuffer = ByteBuffer.allocate(size).order(ByteOrder.LITTLE_ENDIAN)
    fun read(bytes: ByteArray): ByteBuffer = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
    fun crc(bytes: ByteArray): Int = CRC32().apply { update(bytes) }.value.toInt()
    fun compile(score: MidiScore, track: Int, notes: List<Int>, enabled: List<Boolean>, sensorMap: IntArray, startSeconds: Double = 0.0, endSeconds: Double? = null): PracticeSong {
        require(notes.size == 35 && notes.all { it in 0..127 } && enabled.size == 35 && sensorMap.size == 35 && sensorMap.toSet() == (0..34).toSet())
        require(startSeconds.isFinite() && startSeconds >= 0 && (endSeconds == null || endSeconds.isFinite() && endSeconds > startSeconds)) { "A–B范围无效" }
        val melody = score.tracks.first { it.index == track }.notes.filter {
            score.seconds(it.tick + it.duration) > startSeconds && (endSeconds == null || score.seconds(it.tick) < endSeconds)
        }
        require(melody.none { it.channel == 9 }) { "请选择不含打击乐的旋律音轨" }
        require(melody.isNotEmpty()) { "请选择旋律音轨" }
        val missing = melody.map { it.midi }.distinct().filter { pitch -> (0..34).none { enabled[it] && notes[it] == pitch } }
        require(missing.isEmpty()) { "请先配置键位：" + missing.joinToString("、") { score.noteName(it, 0) } }
        val events = melody.groupBy { maxOf(score.seconds(it.tick), startSeconds) }.entries.sortedBy { it.key }
        require(events.size in 1..4096) { "曲谱最多支持 4096 组音符" }
        fun milliseconds(seconds: Double): Int { val ms = (seconds - startSeconds) * 1000; require(ms in 0.0..86400000.0) { "曲谱时长超出范围" }; return kotlin.math.round(ms).toInt() }
        val groups = events.mapIndexed { index, group ->
            val pitches = group.value.map { it.midi }.distinct()
            val mask = pitches.fold(0L) { bits, pitch -> val ui = (0..34).first { enabled[it] && notes[it] == pitch }; bits or (1L shl sensorMap[ui]) }
            val start = milliseconds(group.key)
            PracticeGroup(index, start, (group.value.maxOf { milliseconds(minOf(score.seconds(it.tick + it.duration), endSeconds ?: Double.POSITIVE_INFINITY)) } - start).coerceAtLeast(1), mask, pitches.size, group.value.map { it.velocity }.average().toInt().coerceIn(1, 127))
        }
        require(groups.zipWithNext().all { it.first.startMs < it.second.startMs }) { "音符间隔小于 1 ms" }
        val binding = ByteArray(70)
        repeat(35) { ui -> binding[sensorMap[ui] * 2] = if (enabled[ui]) 1 else 0; binding[sensorMap[ui] * 2 + 1] = notes[ui].toByte() }
        val data = buffer(groups.size * 24)
        groups.forEach { data.putInt(it.index).putInt(it.startMs).putInt(it.durationMs).putLong(it.mask).put(it.notes.toByte()).put(it.velocity.toByte()).putShort(if (it.notes > 1) 1 else 0) }
        return PracticeSong(groups, data.array(), crc(data.array()), crc(binding), endSeconds?.let { milliseconds(it) } ?: groups.maxOf { it.startMs + it.durationMs })
    }
    fun score(total: Int, correct: Int, wrong: Int): Int = if (total <= 0) 0 else (100.0 * correct / (total.toDouble() + wrong)).toInt().coerceIn(0, 100)
}

/** 上传逐块确认，真实评分只接受设备结果；演示练习不进入蓝牙发送队列。 */
internal class PracticeController(private val send: (Int, ByteArray) -> Unit, private val clock: () -> Long = { System.nanoTime() / 1000000 }, private val abortRequests: () -> Unit = {}) {
    val state = MutableStateFlow(PracticeStatus())
    private var song: PracticeSong? = null
    private var uploadId = 0
    private var runId = 0
    private var waitingType = 0
    private var maxBytes = 0
    private var maxGroups = 0
    private var chunkSize = 0
    private var offset = 0
    private var sentEnd = 0
    private var demo = false
    private var startedAt = 0L
    private var pendingAt = 0L
    private var lastPacketAt = 0L
    private var lastPollAt = 0L
    private var stopRequested = false
    private var statusSerial = -1L
    private fun emit(value: PracticeStatus) { state.value = value }
    private fun request(type: Int, bytes: ByteArray) { waitingType = type; pendingAt = clock(); send(type, bytes) }
    fun reset() { stopRequested = false; waitingType = 0; song = null; demo = false; statusSerial = -1; emit(PracticeStatus()) }
    fun clearError() { emit(state.value.copy(error = "")) }
    fun fail(message: String) { waitingType = 0; emit(state.value.copy(phase = "ERROR", error = message)) }
    fun upload(value: PracticeSong, simulated: Boolean) {
        if (waitingType != 0 || state.value.phase in listOf("UPLOADING", "RUNNING", "PAUSED", "STARTING", "VERIFYING")) return
        song = value; runId = 0; demo = simulated; uploadId = (uploadId + 1).coerceAtLeast(1); offset = 0; statusSerial = -1
        emit(PracticeStatus(phase = "UPLOADING", totalBytes = value.bytes.size))
        if (demo) { offset = value.bytes.size; emit(state.value.copy(phase = "READY", transferred = offset)); return }
        request(0x60, byteArrayOf())
    }
    private fun begin() {
        val value = song ?: return
        if (value.bytes.size > maxBytes || value.groups.size > maxGroups) { fail("曲谱超过设备容量"); return }
        request(0x61, PracticeWire.buffer(28).putInt(uploadId).putInt(value.groups.size).putInt(value.bytes.size).putInt(value.crc).putInt(value.bindingCrc).putInt(value.durationMs).putShort(24).putShort(1).array())
    }
    private fun nextChunk() {
        val value = song ?: return
        if (offset == value.bytes.size) { request(0x63, PracticeWire.buffer(12).putInt(uploadId).putInt(value.bytes.size).putInt(value.crc).array()); return }
        sentEnd = minOf(offset + chunkSize, value.bytes.size)
        request(0x62, PracticeWire.buffer(8 + sentEnd - offset).putInt(uploadId).putInt(offset).put(value.bytes, offset, sentEnd - offset).array())
    }
    fun ack(type: Int, result: Int, detail: Int) {
        if (waitingType != type) return
        if (result == 4) return
        waitingType = 0
        if (result != 0) { fail(if (result == 8) "键位已变化，请重新发送曲谱" else "设备未完成操作（$result/$detail）"); return }
        if (type in listOf(0x60, 0x65, 0x66)) { fail("设备未返回完整练习数据"); return }
        when (type) {
            0x61 -> nextChunk()
            0x62 -> { offset = sentEnd; emit(state.value.copy(transferred = offset)); nextChunk() }
            0x63 -> { emit(state.value.copy(phase = "VERIFYING")); request(0x65, PracticeWire.buffer(8).putInt(uploadId).putInt(0).array()) }
            0x64 -> request(0x65, PracticeWire.buffer(8).putInt(uploadId).putInt(runId).array())
        }
    }
    fun packet(type: Int, bytes: ByteArray, response: Boolean = false) {
        val b = PracticeWire.read(bytes)
        if (type == 0x60) {
            if (waitingType != type || bytes.size != 16 || b.getShort(0).toInt() != 1) return
            maxGroups = b.getInt(4); maxBytes = b.getInt(8); chunkSize = (b.getShort(12).toInt() and 65535).coerceAtMost(192)
            if (maxGroups <= 0 || maxBytes <= 0 || chunkSize !in 1..192 || b.getShort(14).toInt() != 24 || b.getShort(2).toInt() and 1 == 0) { fail("设备曲谱格式不兼容"); return }
            waitingType = 0; begin(); return
        }
        if (type == 0x68) {
            if (bytes.size != 48 || b.getInt(0) != uploadId || b.getInt(4) != runId || song == null) return
            val serial = b.getInt(8).toLong() and 0xFFFFFFFFL
            if (statusSerial >= 0) { val delta = (serial - statusSerial) and 0xFFFFFFFFL; if (delta == 0L && !response || delta > 0x7FFFFFFFL) return }
            val code = bytes[12].toInt() and 255; val group = b.getInt(16); val total = b.getInt(20); val correct = b.getInt(24); val wrong = b.getInt(28); val elapsed = b.getInt(32); val mask = b.getLong(36)
            if (code !in 0..5 || total != song!!.groups.size || group !in 0..total || correct !in 0..total || wrong < 0 || elapsed < 0 || mask ushr 35 != 0L || b.getInt(44) != song!!.crc) return
            if (waitingType == 0x65) waitingType = 0
            statusSerial = serial; lastPacketAt = clock()
            val phase = listOf("READY", "RUNNING", "PAUSED", "FINISHED", "STOPPED", "ERROR")[code]
            emit(state.value.copy(phase = phase, group = group, correct = correct, wrong = wrong, elapsedMs = elapsed, target = mask, error = if (code == 5) "设备练习中断" else ""))
            if (code == 4 && runId != 0 && state.value.result == null) {
                emit(state.value.copy(target = 0, result = PracticeResult(runId, total, correct, total - correct, wrong, 0, 0, elapsed, PracticeWire.score(total, correct, wrong), false)))
            }
            if (code == 3 && state.value.result == null && waitingType == 0) request(0x66, PracticeWire.buffer(8).putInt(uploadId).putInt(runId).array())
        }
        if (type == 0x69) {
            if (bytes.size != 48 || b.getInt(0) != uploadId || b.getInt(4) != runId || song == null || runId == 0) return
            val total = b.getInt(8); val correct = b.getInt(12); val missed = b.getInt(16); val wrong = b.getInt(20); val samples = b.getInt(24); val timing = b.getInt(28); val elapsed = b.getInt(32); val score = bytes[36].toInt() and 255
            if (total !in 0..song!!.groups.size || correct < 0 || missed < 0 || correct + missed != total || wrong < 0 || samples !in 0..correct || timing < 0 || elapsed < 0 || score != PracticeWire.score(total, correct, wrong) || bytes[37].toInt() != 0 || b.getInt(40) != song!!.crc || b.getInt(44) != 1) return
            if (waitingType == 0x66) waitingType = 0
            emit(state.value.copy(phase = "FINISHED", group = total, correct = correct, wrong = wrong, elapsedMs = elapsed, target = 0, result = PracticeResult(runId, total, correct, missed, wrong, samples, timing, elapsed, score, false, total < song!!.groups.size)))
        }
    }
    fun start(speed: Float) {
        if (waitingType != 0 || state.value.phase !in listOf("READY", "STOPPED", "FINISHED")) return
        if (speed !in 0.5f..2f) { fail("练习速度超出范围"); return }
        stopRequested = false; runId = (runId + 1).coerceAtLeast(1); statusSerial = -1; startedAt = clock(); lastPacketAt = clock()
        emit(state.value.copy(phase = if (demo) "RUNNING" else "STARTING", group = 0, correct = 0, wrong = 0, elapsedMs = 0, target = song?.groups?.firstOrNull()?.mask ?: 0, result = null, error = ""))
        if (!demo) control(0, 0, speed)
    }
    private fun control(action: Int, index: Int = 0, speed: Float = 1f) { if (waitingType != 0) return; request(0x64, PracticeWire.buffer(20).putInt(uploadId).putInt(runId).put(action.toByte()).put(0).putShort((speed * 1000).toInt().toShort()).putInt(index).putInt(0).array()) }
    fun pause() { if (state.value.phase == "RUNNING") { if (demo) emit(state.value.copy(phase = "PAUSED")) else control(1) } }
    fun resume() { if (state.value.phase == "PAUSED") { if (demo) emit(state.value.copy(phase = "RUNNING")) else control(2) } }
    fun stop() { if (state.value.phase in listOf("RUNNING", "PAUSED", "STARTING")) { if (demo) {
            val total = song?.groups?.size ?: 0; val value = state.value
            emit(value.copy(phase = "STOPPED", target = 0, result = PracticeResult(runId, total, value.correct, total - value.correct, value.wrong, 0, 0, (clock() - startedAt).toInt().coerceAtLeast(0), PracticeWire.score(total, value.correct, value.wrong), true)))
        } else { stopRequested = true; if (waitingType == 0) { stopRequested = false; control(3) } } } }
    fun demoStrike() {
        if (!demo || state.value.phase != "RUNNING") return
        val value = song ?: return; val next = state.value.group + 1
        if (next == value.groups.size) {
            val result = PracticeResult(runId, next, next, 0, 0, next, 0, (clock() - startedAt).toInt().coerceAtLeast(0), 100, true)
            emit(state.value.copy(phase = "FINISHED", group = next, correct = next, target = 0, result = result, elapsedMs = result.elapsedMs))
        } else emit(state.value.copy(group = next, correct = next, target = value.groups[next].mask, elapsedMs = (clock() - startedAt).toInt().coerceAtLeast(0)))
    }
    fun cancel() {
        stopRequested = false; val id = uploadId; waitingType = 0; song = null; abortRequests()
        if (!demo && id != 0) send(0x67, PracticeWire.buffer(4).putInt(id).array())
        emit(PracticeStatus())
    }
    fun tick() {
        if (demo) return
        if (stopRequested && waitingType == 0) { stopRequested = false; if (state.value.phase in listOf("RUNNING", "PAUSED", "STARTING")) control(3) }
        if (waitingType != 0 && clock() - pendingAt > 20000) { fail("设备操作超时，请重新发送曲谱"); return }
        if (state.value.phase in listOf("RUNNING", "PAUSED", "STARTING") && waitingType == 0 && clock() - lastPacketAt > 1500 && clock() - lastPollAt > 1000) { lastPollAt = clock(); request(0x65, PracticeWire.buffer(8).putInt(uploadId).putInt(runId).array()) }
    }
}
