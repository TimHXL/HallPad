package com.timhxl.hallbeat

import org.junit.Assert.*
import org.junit.Test
import kotlin.random.Random

class ScoreTimingRegressionTest {
    private fun reference(resolution: Int, tempos: List<ScoreTempo>, tick: Long): Double {
        var previous = 0L
        var tempo = 500000
        var seconds = 0.0
        for (event in tempos) {
            if (event.tick > tick) break
            seconds += (event.tick - previous).toDouble() * tempo / resolution / 1000000.0
            previous = event.tick
            tempo = event.micros
        }
        return seconds + (tick - previous).toDouble() * tempo / resolution / 1000000.0
    }

    @Test fun defaultTempoAndNegativeSeek() {
        val timing = ScoreTiming(480, emptyList())
        assertEquals(0.5, timing.seconds(480), 1e-10)
        assertEquals(480.0, timing.tick(0.5), 1e-8)
        assertEquals(0.0, timing.tick(-1.0), 0.0)
    }

    @Test fun duplicateTempoAtBoundaryUsesLastEvent() {
        val timing = ScoreTiming(480, listOf(ScoreTempo(480, 1000000), ScoreTempo(480, 250000)))
        assertEquals(0.5, timing.seconds(480), 1e-10)
        assertEquals(0.75, timing.seconds(960), 1e-10)
        assertEquals(480.0, timing.tick(0.5), 1e-8)
    }

    @Test fun randomizedLookupMatchesPreviousIntegrationAndRoundTrips() {
        val random = Random(20261101)
        repeat(30) {
            val resolution = random.nextInt(24, 960)
            val tempos = List(80) { ScoreTempo(random.nextLong(0, 50000), random.nextInt(100000, 1500000)) }.sortedBy { it.tick }
            val timing = ScoreTiming(resolution, tempos)
            repeat(200) {
                val tick = random.nextLong(0, 80000)
                val seconds = timing.seconds(tick)
                assertEquals(reference(resolution, tempos, tick), seconds, 1e-8)
                assertEquals(tick.toDouble(), timing.tick(seconds), 1e-6)
            }
        }
    }

    @Test fun copiedScoreRebuildsTempoIndex() {
        val score = MidiScore(480, emptyList(), listOf(ScoreTempo(0, 500000)), emptyList(), emptyList())
        assertEquals(0.5, score.seconds(480), 1e-10)
        assertEquals(1.0, score.copy(tempos = listOf(ScoreTempo(0, 1000000))).seconds(480), 1e-10)
    }
}
