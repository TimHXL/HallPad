package com.timhxl.hallbeat

/** A key remains down until both manual input and score playback release it. */
internal class KeyHoldOwners(private val edge: (id: Int, down: Boolean, playback: Boolean) -> Unit) {
    private val manual = mutableSetOf<Int>()
    private val playback = mutableSetOf<Int>()
    fun set(id: Int, down: Boolean, fromPlayback: Boolean) {
        require(id in 0..34)
        val before = id in manual || id in playback
        val owner = if (fromPlayback) playback else manual
        if (down) owner.add(id) else owner.remove(id)
        val after = id in manual || id in playback
        if (before != after) edge(id, after, fromPlayback)
    }
    fun setManual(keys: Set<Int>) {
        require(keys.all { it in 0..34 })
        (manual.toSet() - keys).forEach { set(it, false, false) }
        (keys - manual.toSet()).forEach { set(it, true, false) }
    }
    /** Panic/configuration reset uses a separate all-release command. */
    fun clear() { manual.clear(); playback.clear() }
}
