package com.timhxl.hallbeat

/** Prefix times plus binary search: O(log tempoCount) per playback/UI lookup. */
internal class ScoreTiming(private val resolution: Int, tempos: List<ScoreTempo>) {
    private val ticks: LongArray
    private val times: DoubleArray
    private val micros: IntArray

    init {
        require(resolution > 0)
        val events = (listOf(ScoreTempo(0, 500000)) + tempos).sortedBy { it.tick }
            .fold(ArrayList<ScoreTempo>()) { result, event ->
                require(event.tick >= 0 && event.micros > 0)
                if (result.lastOrNull()?.tick == event.tick) result[result.lastIndex] = event
                else result.add(event)
                result
            }
        ticks = LongArray(events.size) { events[it].tick }
        micros = IntArray(events.size) { events[it].micros }
        times = DoubleArray(events.size)
        for (i in 1 until events.size) {
            times[i] = times[i - 1] + (ticks[i] - ticks[i - 1]).toDouble() * micros[i - 1] / resolution / 1000000.0
        }
    }

    fun seconds(tick: Long): Double {
        val found = ticks.binarySearch(tick)
        val i = if (found >= 0) found else (-found - 2).coerceAtLeast(0)
        return times[i] + (tick - ticks[i]).toDouble() * micros[i] / resolution / 1000000.0
    }

    fun tick(seconds: Double): Double {
        val time = seconds.coerceAtLeast(0.0)
        val found = times.binarySearch(time)
        val i = if (found >= 0) found else (-found - 2).coerceAtLeast(0)
        return ticks[i] + (time - times[i]) * resolution * 1000000.0 / micros[i]
    }
}
