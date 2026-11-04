package com.timhxl.hallbeat

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.SecureRandom

/** 小端整数；CRC16/CCITT-FALSE；不依赖 BLE 通知分包边界。 */
internal object HallPadProtocol {
    data class Frame(val type: Int, val flags: Int, val seq: Int, val session: Long, val payload: ByteArray)
    fun buffer(size: Int): ByteBuffer = ByteBuffer.allocate(size).order(ByteOrder.LITTLE_ENDIAN)
    fun read(bytes: ByteArray): ByteBuffer = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
    fun crc(bytes: ByteArray, start: Int = 0, end: Int = bytes.size): Int {
        var value = 0xFFFF
        for (i in start until end) { value = value xor ((bytes[i].toInt() and 255) shl 8); repeat(8) { value = (if (value and 0x8000 != 0) (value shl 1) xor 0x1021 else value shl 1) and 0xFFFF } }
        return value
    }
    fun encode(frame: Frame): ByteArray {
        require(frame.payload.size <= 229)
        val b = buffer(frame.payload.size + 15)
        b.put(0xA5.toByte()).put(0x5A).put(1).put(frame.type.toByte()).put(frame.flags.toByte()).putShort(frame.seq.toShort()).putInt(frame.session.toInt()).putShort(frame.payload.size.toShort()).put(frame.payload)
        b.putShort(crc(b.array(), 2, b.position()).toShort()); return b.array()
    }
    class Decoder {
        private val bytes = ArrayList<Byte>(244)
        private var last = 0L
        fun clear() { bytes.clear(); last = 0 }
        fun feed(data: ByteArray, now: Long): List<Frame> {
            if (now - last > 500) bytes.clear()
            val frames = mutableListOf<Frame>()
            for (byte in data) {
                bytes.add(byte); last = now
                while (bytes.size >= 2) {
                    if (bytes[0] != 0xA5.toByte() || bytes[1] != 0x5A.toByte()) { bytes.removeAt(0); continue }
                    if (bytes.size < 13) break
                    val header = read(bytes.toByteArray()); val length = header.getShort(11).toInt() and 65535
                    if (length > 229) { bytes.removeAt(0); continue }
                    if (bytes.size < length + 15) break
                    val raw = bytes.take(length + 15).toByteArray()
                    if (crc(raw, 2, raw.size - 2) != (read(raw).getShort(raw.size - 2).toInt() and 65535)) { bytes.removeAt(0); continue }
                    repeat(raw.size) { bytes.removeAt(0) }
                    if (raw[2].toInt() != 1 || raw[4].toInt() and 0xF8 != 0) continue
                    frames.add(Frame(raw[3].toInt() and 255, raw[4].toInt(), header.getShort(5).toInt() and 65535, header.getInt(7).toLong() and 0xFFFFFFFFL, raw.copyOfRange(13, raw.size - 2)))
                }
            }
            return frames
        }
    }
}

/** 单一可靠请求；applied 仅由设备读回更新，连接不写手机预设。 */
internal class HallPadSession(private val send: (ByteArray) -> Boolean, private val changed: () -> Unit, private val report: (String) -> Unit, private val fatal: (String) -> Unit, private val deliveryTracking: Boolean = false, private val onTelemetry: (Boolean) -> Unit = { changed() }, private val discardPracticeFrames: () -> Unit = {}, private val discardMidiFrames: () -> Unit = {}) {
    private data class Request(val type: Int, val payload: ByteArray, val versions: Map<Int, Long> = emptyMap())
    private data class Pending(val frame: HallPadProtocol.Frame, var sent: Long, var retries: Int = 0, var queuedAt: Long = 0L, val versions: Map<Int, Long> = emptyMap())
    private val decoder = HallPadProtocol.Decoder()
    private val requests = ArrayDeque<Request>()
    private var pending: Pending? = null
    private var seq = 0
    private var nonce = 0
    private var heartbeat = 0L
    private var snapshot = 0L
    private var backoff = 0L
    private var lastRx = 0L
    private var nextParameter = 0L
    private var stateCounter = 0
    private var mask = 0L
    private data class Edit(val value: Int, val version: Long)
    private val desired = mutableMapOf<Int, Edit>()
    private val localFallback = mutableMapOf<Int, Int>()
    fun seedLocalFallback(values: Map<Int, Int>) { values.forEach { (id, value) -> if (canSetParameter(id)) localFallback.putIfAbsent(id, value) } }
    private var editVersion = 0L
    data class KeyConfig(val enabled: Boolean, val midi: Int, val timbre: Int, val mode: Int, val velocity: Int)
    val appliedKeys = mutableMapOf<Int, KeyConfig>()
    var temporaryKeysActive = false; private set
    var keyReadbackVersion = 0L; private set
    private val desiredKeys = mutableMapOf<Int, KeyConfig>()
    fun displayKey(sensor: Int): KeyConfig? = desiredKeys[sensor] ?: appliedKeys[sensor]
    fun keyConfigurationsConfirmed(values: Map<Int, KeyConfig>): Boolean = ready && has(16) && values.all { (id, expected) -> id !in desiredKeys && appliedKeys[id] == expected }
    fun setKeyConfigurations(values: Map<Int, KeyConfig>) {
        if (!ready || !has(16)) { report("按键设置已保存在手机；设备未就绪或不支持按键配置"); return }
        if (values.isEmpty()) return
        require(values.keys.all { it in 0..35 })
        require(values.values.all { it.midi in 0..127 && it.velocity in 1..127 && it.mode in 0..1 && (it.timbre == 65535 || it.timbre in HallPadInstrumentIds.values) })
        desiredKeys.putAll(values)
        if (values.keys.any { it < 35 }) releaseRemote()
        values.entries.groupBy { it.value }.forEach { (config, entries) ->
            val mask = entries.fold(0L) { value, entry -> value or (1L shl entry.key) }
            val payload = HallPadProtocol.buffer(20).putInt(-1).putLong(mask).putShort(0x1F).put(if (config.enabled) 1.toByte() else 0.toByte()).put(config.midi.toByte()).putShort(config.timbre.toShort()).put(config.mode.toByte()).put(config.velocity.toByte()).array()
            request(0x23, payload)
        }
        // Device readback follows every queued write, rather than showing local
        // edits as confirmed hardware state. Up to 16 records fit one response.
        if (values.keys.any { it < 35 }) { request(0x24, byteArrayOf(0, 16)); request(0x24, byteArrayOf(16, 16)); request(0x24, byteArrayOf(32, 3)) }
        if (35 in values) request(0x24, byteArrayOf(35, 1))
    }
    val sdCard = SdCardController(::sdExchange)
    private var sdWaitPayload: ByteArray? = null
    private var sdWait: kotlinx.coroutines.CompletableDeferred<ByteArray>? = null
    private suspend fun sdExchange(payload: ByteArray): ByteArray {
        check(ready) { "蓝牙尚未连接就绪" };check(sdWait==null) { "SD 请求正在进行" }
        val waiter=kotlinx.coroutines.CompletableDeferred<ByteArray>();sdWait=waiter;sdWaitPayload=payload.copyOf()
        try { request(0x90,payload);return kotlinx.coroutines.withTimeout(12000){waiter.await()} }
        finally { if(sdWait===waiter){sdWait=null;sdWaitPayload=null} }
    }
    private val velocities = IntArray(36)
    private val playbackVelocities = IntArray(36)
    private var playbackClear: kotlinx.coroutines.CompletableDeferred<Unit>? = null
    private var latestAudioFlags: Int? = null
    private var latestAudioErrors = 0
    private fun playbackBlockReason(): String {
        val flags = latestAudioFlags ?: return "设备尚未提供音频状态"
        val reasons = mutableListOf<String>()
        if (flags and 1 != 0) reasons.add("紧急静音锁定")
        if (flags and 2 == 0) reasons.add("音频芯片未配置完成")
        if (flags and 8 == 0) reasons.add("音频时钟未就绪")
        if (flags and 16 == 0) reasons.add("磁轴校准未完成")
        if (flags and 32 != 0) reasons.add("音源正在恢复")
        if (latestAudioErrors != 0) reasons.add("错误位=%X".format(latestAudioErrors))
        return reasons.joinToString("，").ifEmpty { "设备处于设置保持或瞬时保护状态" }
    }
    val playbackKeys = kotlinx.coroutines.flow.MutableStateFlow<Map<Int, Int>>(emptyMap())
    private var playbackMask = 0L
    fun readHiddenKey() { request(0x24, byteArrayOf(35, 1)) }
    fun playbackKey(sensor: Int, down: Boolean, velocity: Int) {
        check(ready && has(0) && (!down || (!muted && !mutePending))) { "设备未就绪或静音" }
        require(sensor in 0..35)

        val bit = 1L shl sensor
        playbackMask = if (down) playbackMask or bit else playbackMask and bit.inv()
        playbackVelocities[sensor] = if (down) velocity.coerceIn(1, 127) else 0
        playbackKeys.value = (0 until 35).filter { playbackMask and (1L shl it) != 0L }.associateWith { playbackVelocities[it] }
        val held = (mask or playbackMask) and bit != 0L
        write(next(0x10, byteArrayOf(sensor.toByte(), if (held) 1.toByte() else 0.toByte(), maxOf(velocities[sensor], playbackVelocities[sensor]).toByte())))
    }
    suspend fun clearPlaybackConfirmed() {
        clearPlayback()
        val waiter = kotlinx.coroutines.CompletableDeferred<Unit>()
        playbackClear = waiter
        try {
            check(ready) { "蓝牙连接已断开" }
            request(0x13, snapshotFrame().payload)
            kotlinx.coroutines.withTimeout(12000) { waiter.await() }
        } finally { playbackClear = null }
    }
    fun clearPlayback() { playbackKeys.value = emptyMap(); playbackMask = 0; playbackVelocities.fill(0); if (ready) sendSnapshot() }
    private var muteTarget: Boolean? = null
    private val deniedControls = mutableSetOf<Int>()
    private val unsupportedParameters = mutableSetOf<Int>()
    private val initialReadQueue = ArrayDeque<List<Int>>()
    private var initialReadInProgress = false
    fun unsupportedParameterIds(): Set<Int> = unsupportedParameters.toSet()
    fun canSetParameter(id: Int): Boolean = id !in unsupportedParameters
    private fun markUnsupported(id: Int) {
        if (unsupportedParameters.add(id)) report("设备不支持参数 0x%04X，已禁用对应控制".format(id))
        applied.remove(id)
        localFallback.remove(id)
    }
    private fun readParameterIds(payload: ByteArray): List<Int> {
        if (payload.isEmpty() || payload.size != 1 + (payload[0].toInt() and 255) * 2) return emptyList()
        val b = HallPadProtocol.read(payload)
        return List(payload[0].toInt() and 255) { b.getShort(1 + it * 2).toInt() and 65535 }
    }
    private fun queueRejectedRead(payload: ByteArray, detail: Int) {
        val ids = readParameterIds(payload).filter { canSetParameter(it) }
        val batches = when {
            ids.isEmpty() -> emptyList()
            detail in ids -> {
                markUnsupported(detail)
                listOf(ids.filterNot { it == detail })
            }
            ids.size == 1 -> { markUnsupported(ids.single()); emptyList() }
            else -> { // Firmware did not identify the rejected field; isolate it by splitting the batch.
                val midpoint = ids.size / 2
                listOf(ids.subList(0, midpoint), ids.subList(midpoint, ids.size))
            }
        }.filter { it.isNotEmpty() }
        if (initialReadInProgress) {
            for (batch in batches.asReversed()) initialReadQueue.addFirst(batch)
            nextInitialRead()
        } else {
            for (batch in batches.asReversed()) readParameters(batch, emptyMap())
        }
    }
    private fun nextInitialRead() {
        if (!initialReadInProgress) return
        while (initialReadQueue.isNotEmpty()) {
            val ids = initialReadQueue.removeFirst().filter { canSetParameter(it) }
            if (ids.isNotEmpty()) { readParameters(ids, emptyMap()); return }
        }
        initialReadInProgress = false
        ready = true; phase = "READY"
        report("READY · 未实现的可选参数已跳过，不自动覆盖设备参数")
        listOf(0x13, 0x21).forEach { readParameters(listOf(it), emptyMap()) }
        if (has(7)) listOf(0x62, 0x63, 0x65).forEach { readParameters(listOf(it), emptyMap()) }
        if (has(16)) {
            request(0x24, byteArrayOf(0, 16)); request(0x24, byteArrayOf(16, 16)); request(0x24, byteArrayOf(32, 3))
        }
        request(0x40, byteArrayOf(0, 1, 100, 0, 0))
        request(0x40, byteArrayOf(3, 1, 0, 0, 0))
        if (has(8)) request(0x40, byteArrayOf(1, 1, 100, 0, 0))
    }
    fun displayValue(id: Int): Int? = desired[id]?.value ?: applied[id] ?: localFallback[id]
    val displayMuted: Boolean get() = muteTarget ?: muted
    fun parameterPending(id: Int): Boolean = id in desired
    private fun parameterIds(payload: ByteArray): List<Int> = (0 until (payload[4].toInt() and 255)).map { HallPadProtocol.read(payload).getShort(5 + it * 6).toInt() and 65535 }
    private fun readParameters(ids: List<Int>, versions: Map<Int, Long>) {
        val supported = ids.distinct().filter { canSetParameter(it) }
        if (supported.isEmpty()) return
        val query = HallPadProtocol.buffer(1 + supported.size * 2).put(supported.size.toByte())
        supported.forEach { query.putShort(it.toShort()) }
        request(0x21, query.array(), versions, true)
    }
    var session = 0L; private set
    var ready = false; private set
    val practice: PracticeController = PracticeController({ type, payload -> request(type, payload, priority = type == 0x67) }, ::now, ::abortPracticeRequests)
    private fun abortPracticeRequests() {
        requests.removeAll { it.type in 0x60..0x67 }
        if (pending?.frame?.type?.let { it in 0x60..0x67 } == true) pending = null
        discardPracticeFrames()
    }
    private var negotiatedPayload: Int = 229
    val directMidi: DirectMidiController = DirectMidiController(this)
    val telemetry = KeyTelemetry()
    var adcReceivedAt = -1L; private set
    private var scoreBeatWait: kotlinx.coroutines.CompletableDeferred<Unit>? = null
    suspend fun scoreBeatControl(enabled: Boolean, token: Int) {
        check(ready && has(27)) { "设备不支持曲谱拍点" }
        check(scoreBeatWait == null) { "节拍控制尚未完成" }
        val wait = kotlinx.coroutines.CompletableDeferred<Unit>(); scoreBeatWait = wait
        try {
            request(0x46, HallPadProtocol.buffer(5).put(if (enabled) 1.toByte() else 0.toByte()).putInt(token).array())
            kotlinx.coroutines.withTimeout(5000) { wait.await() }
        } finally { if (scoreBeatWait === wait) scoreBeatWait = null }
    }
    fun scoreBeatEvent(payload: ByteArray) { if (ready && has(27) && payload.size == 10) write(next(0x47, payload)) }
    var onDrumConfig: ((ByteArray) -> Unit)? = null
    var onDrumHit: ((ByteArray) -> Unit)? = null
    var onDrumStatus: ((Int) -> Unit)? = null
    var onDrumCalibration: ((ByteArray) -> Unit)? = null
    var onDrumLight: ((ByteArray) -> Unit)? = null
    var onDrumControlAck: ((Int, Int) -> Unit)? = null
    var onDrumEffect: ((ByteArray) -> Unit)? = null
    fun readDrumEffect() { if (ready && has(25)) request(0x84) }
    fun setDrumEffect(payload: ByteArray) { if (ready && has(25) && payload.size == 11) request(0x83, payload) }
    var onDrumColor: ((ByteArray) -> Unit)? = null
    fun readDrumColor() { if (ready && has(24)) request(0x7E) }
    fun setDrumColor(payload: ByteArray) { if (ready && has(24) && payload.size == 4) request(0x7D, payload) }
    fun readDrumCalibration() { if (ready && has(22)) request(0x78) }
    fun startDrumCalibration() { if (ready && has(22)) request(0x77, byteArrayOf(3)) }
    fun readDrumLight() { if (ready && has(23)) request(0x7B) }
    fun setDrumLight(payload: ByteArray) { if (ready && has(23) && payload.size == 6) request(0x7A, payload) }
    fun readDrum(stick: Int) { if (ready && has(19) && stick in 0..1) request(0x73, byteArrayOf(stick.toByte())) }
    fun setDrum(payload: ByteArray) { if (ready && has(19) && payload.size == 9) request(0x72, payload) }
    fun strikeDrum(stick: Int, direction: Int, velocity: Int) { if (ready && has(19) && stick in 0..1 && direction in 0..2 && velocity in 1..127) request(0x76, byteArrayOf(stick.toByte(), direction.toByte(), velocity.toByte())) }
    var capabilities = 0L; private set
    var revision = 0L; private set
    private var lastStatusRevision: Long? = null
    private var deviceRefreshNeeded = false
    var muted = false; private set
    var mutePending = false; private set
    var phase = "DISCONNECTED"; private set
    val applied = mutableMapOf<Int, Int>()
    fun has(bit: Int): Boolean = capabilities and (1L shl bit) != 0L
    private fun now(): Long = android.os.SystemClock.elapsedRealtime()
    fun reset() { temporaryKeysActive=false; sdWait?.completeExceptionally(IllegalStateException("蓝牙已断开；重新连接后可继续同名下载"));sdWait=null; scoreBeatWait?.completeExceptionally(IllegalStateException("蓝牙已断开")); scoreBeatWait = null; playbackKeys.value = emptyMap(); latestAudioFlags = null; latestAudioErrors = 0; playbackClear?.completeExceptionally(IllegalStateException("蓝牙会话已断开")); playbackClear = null; directMidi.reset(); negotiatedPayload = 229; lastStatusRevision = null; deviceRefreshNeeded = false; practice.reset(); telemetry.reset(); adcReceivedAt = -1; decoder.clear(); requests.clear(); pending = null; session = 0; seq = 0; ready = false; capabilities = 0; mask = 0; playbackMask = 0; playbackVelocities.fill(0); stateCounter = 0; applied.clear(); appliedKeys.clear(); desiredKeys.clear(); keyReadbackVersion = 0; desired.clear(); localFallback.clear(); velocities.fill(0); muteTarget = null; deniedControls.clear(); unsupportedParameters.clear(); initialReadQueue.clear(); initialReadInProgress = false; mutePending = false; muted = false; phase = "DISCONNECTED"; changed() }
    fun start() { reset(); nonce = SecureRandom().nextInt(); lastRx = now(); phase = "HANDSHAKING"; request(1, HallPadProtocol.buffer(8).put(1).put(1).putInt(nonce).putShort(229).array()); changed() }
    private fun next(type: Int, payload: ByteArray, reliable: Boolean = false): HallPadProtocol.Frame { seq = (seq + 1) and 65535; return HallPadProtocol.Frame(type, if (reliable) 1 else 0, seq, if (type == 1) 0L else session, payload) }
    private fun write(frame: HallPadProtocol.Frame) {  if (!send(HallPadProtocol.encode(frame))) fatal("发送队列拥塞；停止会话，设备租约将释放按键") }
    fun request(type: Int, payload: ByteArray = byteArrayOf(), versions: Map<Int, Long> = emptyMap(), priority: Boolean = false) {
        if (type != 1 && session == 0L) return
        if (type in listOf(0x78, 0x7B, 0x7E, 0x84) && (pending?.frame?.type == type || requests.any { it.type == type })) return
        if (type == 0x11 && (pending?.frame?.type == 0x11 || requests.any { it.type == 0x11 })) return
        if (type == 0x20) requests.removeAll { it.type == type && parameterIds(it.payload).toSet() == parameterIds(payload).toSet() }
        if (requests.size >= (if (type == 0x23 || type == 0x24) 96 else 32)) {
            versions.forEach { (id, version) -> if (desired[id]?.version == version) desired.remove(id) }
            if (type in listOf(0x77, 0x7A, 0x7D, 0x83)) onDrumControlAck?.invoke(type, 255)
            report("操作失败：控制队列繁忙，本次设置未提交；连接保持"); changed(); return
        }
        if (type == 0x20 && payload.size == 11) requests.removeAll { it.type == type && it.payload.size == 11 && it.payload[5] == payload[5] && it.payload[6] == payload[6] }
        val request = Request(type, payload, versions); if (priority) requests.addFirst(request) else requests.addLast(request); pump()
    }
    private fun pump() { if (pending != null || requests.isEmpty() || now() < backoff) return; if (requests.first().type == 0x20 && now() < nextParameter) return; val req = requests.removeFirst(); if (req.type == 0x20) nextParameter = now() + 100; val frame = next(req.type, req.payload, true); pending = Pending(frame, if (deliveryTracking) -1 else now(), queuedAt = now(), versions = req.versions); write(frame) }
    fun transmitted(bytes: ByteArray) {
        if (!deliveryTracking || bytes.size < 15) return
        val active = pending ?: return
        val header = HallPadProtocol.read(bytes)
        if (active.frame.type == (bytes[3].toInt() and 255) && active.frame.seq == (header.getShort(5).toInt() and 65535) && active.sent < 0) active.sent = now()
    }
    fun receive(bytes: ByteArray) { decoder.feed(bytes, now()).forEach { receive(it) } }
    private fun receive(frame: HallPadProtocol.Frame) {

        if (frame.flags and 2 == 0) { if (frame.session == session && session != 0L) { lastRx = now(); when (frame.type) {
                    5 -> status(frame.payload)
                    0x68, 0x69 -> practice.packet(frame.type, frame.payload)
                    0x74 -> if (has(19) && frame.payload.size == 9) onDrumConfig?.invoke(frame.payload)
                    0x75 -> if (has(19) && frame.payload.size == 12) onDrumHit?.invoke(frame.payload)
                    0x41 -> if (telemetry.adcData(frame.payload)) { adcReceivedAt = now(); onTelemetry(true) }
                    0x43 -> if (telemetry.activity(frame.payload)) onTelemetry(false)
                } }; return }
        if (frame.type == 3 && frame.session == session && frame.payload.size == 8 && frame.flags and 4 != 0 && (pending?.frame?.seq != frame.seq)) {
            val type = frame.payload[0].toInt() and 255
            val result = frame.payload[1].toInt() and 255

            val reason = if (type in listOf(0x10, 0x13) && result == 5) "设备暂不允许演奏：${playbackBlockReason()}" else "设备拒绝实时命令%02X，错误%02X".format(type, result)
            if (type in listOf(0x10, 0x13) && playbackMask != 0L) {
                directMidi.rejected(reason)
                clearPlayback()
            }
            if (deniedControls.add(0x100 + type)) report("操作失败：$reason")
            return
        }
        val operation = pending ?: return
        val req = operation.frame
        if (frame.seq != req.seq || (req.type != 1 && frame.session != session)) return
        if (frame.type == 3) {
            if (frame.payload.size != 8 || (frame.payload[0].toInt() and 255) != req.type) return
            val b = HallPadProtocol.read(frame.payload); val result = frame.payload[1].toInt() and 255; val detail = b.getShort(6).toInt() and 65535
            if (req.type !in listOf(0x46, 0x77, 0x7A, 0x7D, 0x83)) revision = b.getInt(2).toLong() and 0xFFFFFFFFL; pending = null; lastRx = now()
            report("ACK type=%02X result=%02X revision=%d detail=%d".format(req.type, result, revision, detail))
            if (req.type == 0x46 && result != 4) {
                if (result == 0) scoreBeatWait?.complete(Unit)
                else scoreBeatWait?.completeExceptionally(IllegalStateException("设备拒绝节拍控制：$result"))
            }
            if(req.type==0x90 && req.payload.contentEquals(sdWaitPayload) && result!=0 && result!=4)sdWait?.completeExceptionally(IllegalStateException("设备拒绝 SD 操作：$result"))
            if (req.type in 0x60..0x67) practice.ack(req.type, result, detail)
            if (req.type == 0x13 && result != 4) {
                if (result == 0) playbackClear?.complete(Unit)
                else playbackClear?.completeExceptionally(IllegalStateException("播放释放未确认：$result"))
            }
            if ((req.type in listOf(0x77, 0x7A, 0x7D, 0x83) && result != 4) || (req.type in listOf(0x78, 0x7B, 0x7E, 0x84) && result !in listOf(0, 4))) onDrumControlAck?.invoke(req.type, result)
            if (result == 4) { backoff = now() + maxOf(100, detail).toLong(); requests.addFirst(Request(req.type, req.payload, operation.versions)) }
            else if (result != 0) {
                operation.versions.forEach { (id, version) -> if (desired[id]?.version == version) desired.remove(id) }
                if (result == 7 && req.type == 0x20) { val ids = parameterIds(req.payload); if (detail in ids) markUnsupported(detail) else if (ids.size == 1) markUnsupported(ids.first()) }
                if (req.type == 0x23 && req.payload.size == 20) {
                    val keyMask = HallPadProtocol.read(req.payload).getLong(4)
                    val sentKey = KeyConfig(req.payload[14].toInt() != 0, req.payload[15].toInt() and 255, HallPadProtocol.read(req.payload).getShort(16).toInt() and 65535, req.payload[18].toInt() and 255, req.payload[19].toInt() and 255)
                    repeat(36) { if (keyMask and (1L shl it) != 0L && desiredKeys[it] == sentKey) desiredKeys.remove(it) }
                }
                if (req.type == 0x14) { mutePending = false; muteTarget = null }
                val reason = when (result) { 7 -> "设备未实现此功能"; 3 -> "参数超出设备范围"; 8 -> "设备配置版本冲突"; else -> "设备拒绝请求" }
                if (req.type == 0x21 && result in listOf(3, 7)) {
                    // A missing optional parameter must never make the entire device unusable.
                    queueRejectedRead(req.payload, detail)
                } else {
                    if (req.type != 0x40) report("操作失败：" + reason + "（命令%02X，字段%04X）".format(req.type, detail))
                    if (!ready || result == 9) { fatal("握手/请求失败 result=$result detail=$detail"); return }
                }
            }
            else if (req.type == 0x77) readDrumCalibration()
            else if (req.type == 0x7A) readDrumLight()
            else if (req.type == 0x7D) readDrumColor()
            else if (req.type == 0x83) readDrumEffect()
            else if (req.type == 0x72 && req.payload.size == 9) readDrum(req.payload[0].toInt() and 255)
            else if (req.type == 0x20) readParameters(parameterIds(req.payload), operation.versions)
            else if (req.type == 0x14) { mask = 0; velocities.fill(0); request(4, priority = true) }

        } else {
            val expected = when (req.type) { 1 -> 1; 2 -> 2; 4 -> 5; 6 -> 7; 0x21 -> 0x22; 0x24 -> 0x25; 0x26 -> 0x27; 0x73 -> 0x74; 0x78 -> 0x79; 0x7B -> 0x7C; 0x7E -> 0x7F; 0x84 -> 0x85; 0x40 -> 0x40; 0x90 -> 0x91; 0x60 -> 0x60; 0x65 -> 0x68; 0x66 -> 0x69; else -> -1 }
            if (frame.type != expected || frame.flags and 4 != 0) return
            val p = frame.payload; val b = HallPadProtocol.read(p)
            when (req.type) {
                0x90 -> { if(p.size!=36)return;if(req.payload.contentEquals(sdWaitPayload))sdWait?.complete(p) }
                0x84 -> { if (p.size != 11 && p.size != 9) return; onDrumEffect?.invoke(p) }
                0x7E -> { if (p.size != 4) return; onDrumColor?.invoke(p) }
                0x78 -> { if (p.size != 12) return; onDrumCalibration?.invoke(p) }
                0x7B -> { if (p.size != 6) return; onDrumLight?.invoke(p) }
                0x60, 0x65, 0x66 -> practice.packet(frame.type, p, response = true)
                0x73 -> { if (p.size != 9 || req.payload.size != 1 || p[0] != req.payload[0]) return; onDrumConfig?.invoke(p) }
                1 -> {
                    if (p.size != 24 || p[0].toInt() != 0 || p[1].toInt() != 1 || b.getInt(2) != nonce || frame.session == 0L || (b.getShort(18).toInt() and 65535) !in 64..229) return
                    negotiatedPayload = b.getShort(18).toInt() and 65535
                    session = frame.session; phase = "SYNCING"; report("HELLO session=%08X boot=%08X".format(session, b.getInt(14)))
                }
                6 -> { if (p.size != 22 || p[0].toInt() != 35) return; capabilities = b.getLong(5); revision = b.getInt(13).toLong() and 0xFFFFFFFFL; report("CAPS=%X".format(capabilities)) }
                4 -> { if (p.size != 40) return; if (muteTarget != null) { muteTarget = null; mutePending = false }; status(p) }
                0x24 -> {
                    if (p.size < 6) return
                    val start = p[4].toInt() and 255; val count = p[5].toInt() and 255
                    if (start != (req.payload[0].toInt() and 255) || count != (req.payload[1].toInt() and 255) || count !in 1..16 || start + count > 36 || p.size != 6 + count * 10) return
                    revision = b.getInt(0).toLong() and 0xFFFFFFFFL
                    repeat(count) { i -> val offset = 6 + i * 10; appliedKeys[start + i] = KeyConfig(p[offset].toInt() != 0, p[offset + 1].toInt() and 255, b.getShort(offset + 2).toInt() and 65535, p[offset + 4].toInt() and 255, p[offset + 5].toInt() and 255) }
                    repeat(count) { i -> val id = start + i; if (desiredKeys[id] == appliedKeys[id]) desiredKeys.remove(id) }
                    keyReadbackVersion++
                    report("已读回设备按键配置 $start–${start + count - 1}")
                }
                0x21 -> {
                    if (p.size < 5 || p.size != 5 + 6 * (p[4].toInt() and 255) || p[4] != req.payload[0]) return
                    repeat(p[4].toInt() and 255) { if (b.getShort(5 + it * 6) != HallPadProtocol.read(req.payload).getShort(1 + it * 2)) return }
                    revision = b.getInt(0).toLong() and 0xFFFFFFFFL
                    repeat(p[4].toInt() and 255) { applied[b.getShort(5 + it * 6).toInt() and 65535] = b.getInt(7 + it * 6) }
                    operation.versions.forEach { (id, version) -> if (desired[id]?.version == version) desired.remove(id) }
                    report("PARAMETERS $applied")
                }
            }
            lastRx = now(); pending = null
            when (req.type) { 1 -> request(6); 6 -> request(4); 4 -> if (!ready) {
                    val ids = mutableListOf(1, 2, 3, 0x70, 0x80)
                    if (has(2)) ids.addAll(listOf(0x05, 0x71))
                    if (has(5)) ids.addAll(listOf(0x40, 0x41, 0x42))
                    if (has(6)) ids.addAll(listOf(0x50, 0x51, 0x52, 0x53))
                    if (has(7)) ids.addAll(listOf(0x60, 0x61))
                    if (has(20)) ids.add(0x90)
                    initialReadQueue.clear()
                    initialReadInProgress = true
                    initialReadQueue.addLast(ids)
                    nextInitialRead()
                }; 0x21 -> if (initialReadInProgress) nextInitialRead() }
        }
        changed(); pump()
    }
    private fun status(p: ByteArray) { if (p.size != 40) return; val b = HallPadProtocol.read(p); latestAudioFlags = b.getInt(8); temporaryKeysActive=b.getInt(8) and 0x4000!=0; latestAudioErrors = b.getInt(34);  onDrumStatus?.invoke(b.getInt(8)); telemetry.applyMask(b.getInt(0).toLong() and 0xFFFFFFFFL, b.getLong(18)); val observedRevision = b.getInt(4).toLong() and 0xFFFFFFFFL; if (ready && lastStatusRevision != null && observedRevision != lastStatusRevision) deviceRefreshNeeded = true; lastStatusRevision = observedRevision; revision = observedRevision; if (muteTarget == null) muted = b.getInt(8) and 1 != 0; applied[1] = b.getShort(16).toInt() and 65535; applied[2] = b.getShort(14).toInt() and 65535; report("STATUS remote=%X flags=%X".format(b.getLong(26), b.getInt(8))); changed() }
    fun setParameter(id: Int, value: Int) { setParameters(mapOf(id to value)) }
    fun setParameters(values: Map<Int, Int>) {
        if (!ready) { report("操作失败：请先连接并等待设备就绪"); changed(); return }
        require(values.size in 1..37)
        if (values.keys.any { !canSetParameter(it) }) { report("操作失败：设备已明确不支持此参数，重新连接后可再次探测"); changed(); return }
        val version = ++editVersion
        val versions = values.keys.associateWith { version }
        val payload = HallPadProtocol.buffer(5 + values.size * 6).putInt(-1).put(values.size.toByte())
        values.forEach { (id, value) -> desired[id] = Edit(value, version); payload.putShort(id.toShort()).putInt(value) }
        request(0x20, payload.array(), versions)
        changed()
    }
    fun performance(control: Int, value: Int) {
        if (!ready || muted || mutePending) return
        if (!has(2)) { if (deniedControls.add(control)) report("操作失败：设备未提供远程摇杆能力，未发送虚假控制"); return }
        write(next(0x12, HallPadProtocol.buffer(3).put(control.toByte()).putShort(value.toShort()).array()))
    }
    fun key(sensor: Int, down: Boolean, velocity: Int = 100) {
        if (!ready || !has(0) || sensor !in 0..34 || muted || mutePending) return
        val bit = 1L shl sensor
        if ((mask and bit != 0L) == down) return
        mask = if (down) mask or bit else mask and bit.inv()
        velocities[sensor] = if (down) velocity.coerceIn(1, 127) else 0
        write(next(0x10, byteArrayOf(sensor.toByte(), if ((mask or playbackMask) and bit != 0L) 1.toByte() else 0.toByte(), maxOf(velocities[sensor], playbackVelocities[sensor]).toByte())))
    }
    private fun snapshotFrame(): HallPadProtocol.Frame {
        stateCounter = (stateCounter + 1) and 65535
        val hidden = appliedKeys.containsKey(35)
        val count = if (hidden) 36 else 35
        val combined = mask or playbackMask
        val b = HallPadProtocol.buffer(10 + count).putShort(stateCounter.toShort()).putLong(combined)
        repeat(count) { b.put(if (combined and (1L shl it) != 0L) maxOf(velocities[it], playbackVelocities[it]).toByte() else 0.toByte()) }
        return next(0x13, b.array())
    }
    fun snapshotBytes(): ByteArray = HallPadProtocol.encode(snapshotFrame())
    private fun sendSnapshot() { if (has(0)) write(snapshotFrame()) }
    fun releaseRemote() { mask = 0; velocities.fill(0); if (ready) { sendSnapshot(); if (playbackMask == 0L) request(0x11, byteArrayOf(0)) } }
    fun panic(on: Boolean) { if (ready && !mutePending) { clearPlayback(); mask = 0; velocities.fill(0); muteTarget = on; mutePending = true; request(0x14, byteArrayOf(if (on) 1 else 0)); changed() } }
    fun tick() {
        practice.tick()
        // 状态版本独立跟踪，避免写入 ACK 提前更新 revision 而漏掉设备端变化。
        if (ready && deviceRefreshNeeded && pending == null && requests.isEmpty()) {
            deviceRefreshNeeded = false
            val ids = mutableListOf(1, 2, 3, 0x70, 0x80)
            if (has(2)) ids.addAll(listOf(0x05, 0x71))
            if (has(5)) ids.addAll(listOf(0x40, 0x41, 0x42))
            if (has(6)) ids.addAll(listOf(0x50, 0x51, 0x52, 0x53))
            if (has(7)) ids.addAll(listOf(0x60, 0x61))
            if (has(20)) ids.add(0x90)
            readParameters(ids, emptyMap())
            if(has(16)) { request(0x24,byteArrayOf(0,16));request(0x24,byteArrayOf(16,16));request(0x24,byteArrayOf(32,3)) }
        }
        val time = now(); val active = pending
        if (active != null && active.sent >= 0 && time - active.sent >= (if(active.frame.type==0x90) 10000 else 500)) { if (active.retries >= 2) { fatal("协议请求超时，需重新连接"); return }; active.sent = if (deliveryTracking) -1 else time; active.queuedAt = time; active.retries++; write(active.frame) }
        if (active != null && active.sent < 0 && time - active.queuedAt > 10000) { fatal("蓝牙发送持续阻塞，请重新连接"); return }
        if (session != 0L && time - lastRx > (if(active?.frame?.type==0x90) 12000 else 3000)) { fatal("设备应答超时"); return }
        if (session != 0L && time >= heartbeat) { heartbeat = time + 250; write(next(2, HallPadProtocol.buffer(4).putInt(time.toInt()).array())) }
        if (ready && time >= snapshot) { snapshot = time + 100; sendSnapshot() }
        pump()
    }
}
