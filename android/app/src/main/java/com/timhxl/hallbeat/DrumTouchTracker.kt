package com.timhxl.hallbeat

/** Per-finger transitions. Null pad means a gap, never a repeated/held strike. */
internal class DrumTouchTracker {
    private val pads = mutableMapOf<Long, Int?>()
    fun owns(id: Long): Boolean = pads.containsKey(id)
    fun update(id: Long, pressed: Boolean, previousPressed: Boolean, pad: Int?): Int? {
        if (!pressed) { pads.remove(id); return null }
        if (!pads.containsKey(id)) {
            if (previousPressed || pad == null) return null
            pads[id] = pad
            return pad
        }
        val previous = pads[id]
        pads[id] = pad
        return pad?.takeIf { it != previous }
    }
    fun clear() { pads.clear() }
}
