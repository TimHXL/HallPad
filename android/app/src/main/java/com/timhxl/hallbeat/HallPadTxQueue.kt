package com.timhxl.hallbeat

/** 有界整帧调度；拥塞时用最新完整快照替换尚未发出的键事件，不断开链路。 */
internal class HallPadTxQueue(private val snapshot: () -> ByteArray) {
    private data class Entry(val bytes: ByteArray, val priority: Int)
    private val entries = mutableListOf<Entry>()
    var coalesced = 0; private set
    val size: Int get() = entries.size
    fun discardPractice(): Unit { entries.removeAll { type(it.bytes) in 0x60..0x67 } }
    fun discardMidi(): Unit { entries.removeAll { type(it.bytes) == 0x15 || type(it.bytes) == 0x19 } }
    fun clear() { entries.clear(); coalesced = 0 }
    private fun type(bytes: ByteArray): Int = bytes[3].toInt() and 255
    private fun transientKey(bytes: ByteArray): Boolean = type(bytes) == 0x10 || (type(bytes) == 0x13 && bytes[4].toInt() and 1 == 0)
    fun offer(bytes: ByteArray, urgent: Boolean = false): Boolean {
        val type = type(bytes)
        if (type == 0x46) entries.removeAll { type(it.bytes) == 0x47 }
        // A queued click is transient: do not replay a burst of stale beats.
        if (type == 0x47) entries.removeAll { type(it.bytes) == 0x47 }
        val release = type == 0x11 || type == 0x14 || (type == 0x13 && urgent)
        if (release) entries.removeAll { transientKey(it.bytes) || type(it.bytes) == 0x12 || type(it.bytes) == 0x47 }
        if (type == 0x10 && entries.count { type(it.bytes) == 0x10 } >= 8) {
            entries.removeAll { transientKey(it.bytes) }
            entries.add(Entry(snapshot(), 0)); coalesced++; return true
        }
        var inheritUrgency = false
        if (type == 0x13 && bytes[4].toInt() and 1 == 0) {
            inheritUrgency = entries.any { type(it.bytes) == 0x13 && it.priority == 0 }
            if (inheritUrgency) entries.removeAll { type(it.bytes) == 0x10 }
            entries.removeAll { type(it.bytes) == 0x13 && transientKey(it.bytes) }
        }
        if (type == 2) entries.removeAll { type(it.bytes) == 2 }
        if (type == 0x12) entries.removeAll { type(it.bytes) == 0x12 && it.bytes[13] == bytes[13] }
        if (entries.size >= 96) return false
        val priority = when { release || inheritUrgency || type == 0x67 || type == 0x16 -> 0; type == 2 || type in listOf(0x10, 0x12, 0x13, 0x15, 0x19, 0x47) -> 1; type == 0x62 -> 4; bytes[4].toInt() and 1 != 0 -> 2; else -> 3 }
        entries.add(Entry(bytes, priority)); return true
    }
    private fun nextIndex(): Int = entries.indices.minByOrNull { entries[it].priority } ?: -1
    fun bundle(maxBytes: Int): List<ByteArray> {
        val first = nextIndex()
        if (first < 0) return emptyList()
        val result = mutableListOf(entries.removeAt(first).bytes)
        var bytes = result.first().size
        while (bytes < maxBytes) {
            val index = nextIndex()
            if (index < 0 || bytes + entries[index].bytes.size > maxBytes) break
            val frame = entries.removeAt(index).bytes
            result.add(frame); bytes += frame.size
        }
        return result
    }
}
