package com.timhxl.hallbeat

import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** One-shot beats share the score scheduler; no independent BPM oscillator. */
internal data class ScoreBeat(val seconds: Double, val index: Int, val beats: Int, val unit: Int)
internal fun scoreBeatTimeline(score: MidiScore, endSeconds: Double): List<ScoreBeat> {
    val meters = (listOf(ScoreMeter(0, 4, 4)) + score.meters).groupBy { it.tick }.values.map { it.last() }.sortedBy { it.tick }
    val result = ArrayList<ScoreBeat>()
    for ((i, meter) in meters.withIndex()) {
        require(meter.numerator in 1..12 && meter.denominator in listOf(2, 4, 8, 16)) { "节拍器暂不支持此拍号" }
        val stopTick = meters.getOrNull(i + 1)?.tick ?: Long.MAX_VALUE
        val step = score.resolution * 4.0 / meter.denominator
        var beat = 0L
        while (true) {
            val tick = meter.tick + kotlin.math.round(beat * step).toLong()
            if (tick >= stopTick) break
            val time = score.seconds(tick)
            if (time >= endSeconds) break
            require(result.size < 100000) { "节拍数量过多" }
            result.add(ScoreBeat(time, (beat % meter.numerator).toInt(), meter.numerator, meter.denominator))
            beat++
        }
    }
    return result
}

internal class ScoreBeatTransport(private val session: HallPadSession) {
    val supported: Boolean get() = session.ready && session.has(27)
    private var token = 0
    private var counter = 0
    private var active = false
    private var transition: Job? = null
    private val shutdownLock = Mutex()
    private var shuttingDown = false
    fun reset() {
        transition?.cancel()
        transition = null
        active = false
        token = 0
        counter = 0
    }
    fun update(enabled: Boolean, scope: CoroutineScope) {
        if (shuttingDown || !supported || transition?.isActive == true || enabled == active) return
        transition = scope.launch {
            if (enabled) { start(); active = true } else { stop(); active = false }
        }
    }
    suspend fun shutdown() {
        shutdownLock.withLock {
            shuttingDown = true
            try {
                transition?.cancelAndJoin(); transition = null
                stop()
            } finally { active = false; shuttingDown = false }
        }
    }
    private suspend fun start() {
        check(supported) { "设备未实现曲谱同步节拍器" }
        token = (token + 1).let { if (it == 0) 1 else it }; counter = 0
        session.scoreBeatControl(true, token)
    }
    fun beat(value: ScoreBeat) {
        if (!supported || token == 0 || !active) return
        session.scoreBeatEvent(HallPadProtocol.buffer(10).putInt(token).putShort(counter.toShort())
            .put(value.index.toByte()).put(value.beats.toByte()).put(value.unit.toByte()).put(if (value.index == 0) 1.toByte() else 0.toByte()).array())
        counter = (counter + 1) and 65535
    }
    private suspend fun stop() { if (token != 0 && supported) session.scoreBeatControl(false, token) }
}
