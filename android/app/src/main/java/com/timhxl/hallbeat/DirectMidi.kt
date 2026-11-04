package com.timhxl.hallbeat

import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeout

internal data class DirectMidiVoice(val id: Int, val midi: Int, val velocity: Int)

/** Uses existing KEY_CONFIG (0x23), KEY_EVENT (0x10), KEY_STATE (0x13). */
internal class DirectMidiController(private val session: HallPadSession) {
    val scoreBeat = ScoreBeatTransport(session)
    private val barrier = Mutex()
    private val held = linkedMapOf<Int, Pair<DirectMidiVoice, Int>>()
    private var mapping = emptyMap<Int, Int>()
    private var pendingHidden: DirectMidiVoice? = null
    private var hiddenRequest: HallPadSession.KeyConfig? = null
    private var hiddenRequestAt = 0L
    private fun ensureHiddenPitch(voice: DirectMidiVoice): Boolean {
        val config = HallPadSession.KeyConfig(true, voice.midi, 65535, 0, 100)
        if (session.keyConfigurationsConfirmed(mapOf(35 to config))) {
            hiddenRequest = null
            return true
        }
        if (hiddenRequest != config) {
            hiddenRequest = config; hiddenRequestAt = android.os.SystemClock.elapsedRealtime()

            session.setKeyConfigurations(mapOf(35 to config))
        }
        check(android.os.SystemClock.elapsedRealtime() - hiddenRequestAt < 12000) { "第36键音高配置未确认，播放已停止" }
        return false
    }
    /** Look ahead without waiting for ACK/readback or disturbing a held voice. */
    fun needsHidden(voice: DirectMidiVoice): Boolean = voice.midi !in mapping
    suspend fun preload(voice: DirectMidiVoice) = barrier.withLock {
        checkHealthy()
        if (voice.midi !in mapping && held.values.none { it.second == 35 }) ensureHiddenPitch(voice)
        Unit
    }
    suspend fun flushPending() = barrier.withLock {
        checkHealthy()
        val voice = pendingHidden
        if (voice != null && held[voice.id] == (voice to 35) && ensureHiddenPitch(voice)) {
            session.playbackKey(35, true, voice.velocity); pendingHidden = null
        }
    }
    var cleanupError: String? = null; private set
    fun reset() { scoreBeat.reset(); held.clear(); mapping = emptyMap(); pendingHidden = null; hiddenRequest = null; cleanupError = null }
    fun rejected(reason: String) { cleanupError = reason }
    suspend fun prepare(): Unit = barrier.withLock {
        check(session.ready && session.has(0) && session.has(16)) { "设备不支持远程按键或单键音高设置" }
        session.readHiddenKey()
        withTimeout(12000) {
            while (session.appliedKeys[35] == null) { checkHealthy(); kotlinx.coroutines.delay(20) }
        }
        val expected = (0..34).associateWith { session.displayKey(it) ?: error("设备键位尚未读回") }
        withTimeout(12000) {
            while (!session.keyConfigurationsConfirmed(expected)) { checkHealthy(); kotlinx.coroutines.delay(20) }
        }
        mapping = (0..34).filter { session.displayKey(it)?.enabled == true }
            .groupBy { session.displayKey(it)!!.midi }.mapValues { it.value.first() }

        Unit
    }
    suspend fun clear(): Unit = withContext(NonCancellable) { barrier.withLock {
        cleanupError = "播放按键释放尚未确认"
        try { session.clearPlaybackConfirmed(); held.clear(); pendingHidden = null; cleanupError = null }
        catch (error: Exception) { cleanupError = "播放按键释放失败：${error.message}"; throw error }
    } }
    fun checkHealthy() { check(session.ready) { "蓝牙连接已断开" }; cleanupError?.let { error(it) } }
    suspend fun note(voice: DirectMidiVoice, down: Boolean) = barrier.withLock {
        checkHealthy()

        if (!down) {
            val old = held[voice.id]
            if (old?.first != voice) return@withLock
            held.remove(voice.id)
            if (pendingHidden == voice) pendingHidden = null
            if (old != null && old.second >= 0 && held.values.none { it.second == old.second }) session.playbackKey(old.second, false, 0)
        } else {
            if (held[voice.id]?.first == voice) return@withLock
            var key = mapping[voice.midi]
            if (key == null) {
                if (held.values.any { it.second == 35 }) { held[voice.id] = voice to -1; return@withLock }
                key = 35
                if (!ensureHiddenPitch(voice)) {
                    held[voice.id] = voice to 35
                    pendingHidden = voice
                    return@withLock
                }
            }
            held[voice.id] = voice to key
            session.playbackKey(key, true, voice.velocity)
        }
    }
    suspend fun state(voices: Collection<DirectMidiVoice>) {
        val desired = voices.associateBy { it.id }
        held.values.map { it.first }.filter { desired[it.id] != it }.forEach { note(it, false) }
        voices.filter { held[it.id]?.first != it }.forEach { note(it, true) }
    }
}

internal data class DirectMidiEvent(val seconds: Double, val voice: DirectMidiVoice, val down: Boolean)
internal data class DirectMidiTimeline(val events: List<DirectMidiEvent>, val peak: Int) {
    companion object {
        /** Allocate one ID per overlapping instance, including overlapping identical pitches. */
        fun compile(score: MidiScore, notes: List<ScoreNote>): DirectMidiTimeline {
            require(notes.none { it.channel == 9 }) { "打击乐音轨不支持直接旋律播放，请选择其他音轨" }
            var nextId = 0
            val free = java.util.PriorityQueue<Int>()
            val active = java.util.PriorityQueue<Pair<Long, Int>>(compareBy<Pair<Long, Int>> { it.first }.thenBy { it.second })
            val events = mutableListOf<DirectMidiEvent>(); var peak = 0
            notes.sortedBy { it.tick }.forEach { note ->
                while (active.isNotEmpty() && active.peek().first <= note.tick) free.add(active.remove().second)
                require(free.isNotEmpty() || nextId <= 65535) { "曲谱同时发声实例超过 65536 个" }
                require(note.midi in 0..127 && note.velocity in 1..127)
                val id = if (free.isEmpty()) nextId++ else free.remove(); val end = note.tick + note.duration.coerceAtLeast(1)
                val voice = DirectMidiVoice(id, note.midi, note.velocity)
                active.add(end to id); peak = maxOf(peak, active.size)
                events.add(DirectMidiEvent(score.seconds(note.tick), voice, true))
                events.add(DirectMidiEvent(score.seconds(end), voice, false))
            }
            return DirectMidiTimeline(events.sortedWith(compareBy<DirectMidiEvent> { it.seconds }.thenBy { if (it.down) 1 else 0 }), peak)
        }
    }
}
