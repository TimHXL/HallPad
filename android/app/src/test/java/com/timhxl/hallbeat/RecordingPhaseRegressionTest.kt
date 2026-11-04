package com.timhxl.hallbeat

import org.junit.Assert.assertEquals
import org.junit.Test

class RecordingPhaseRegressionTest {
    @Test fun recordingPreservesMetronomePhaseWithoutQuantizingPerformance() {
        var now = 1000L
        val recording = FpgaRecording { now }
        recording.start(IntArray(35) { it }, List(35) { 60 }, List(35) { 100 }, 0L, 120, 4, 4, 250.0)
        now += 100
        recording.mask(1L)
        now += 200
        recording.mask(0L)
        val score = MidiScoreParser.parse(recording.finish())
        val note = score.tracks.single().notes.single()
        assertEquals(0.35, score.seconds(note.tick), 0.0011)
        assertEquals(0.55, score.seconds(note.tick + note.duration), 0.0011)
        assertEquals(500000, score.tempos.single().micros)
    }

    @Test fun recordingWithoutRunningMetronomeKeepsOriginalOrigin() {
        var now = 0L
        val recording = FpgaRecording { now }
        recording.start(IntArray(35) { it }, List(35) { 60 }, List(35) { 100 }, 0L, 137, 3, 8)
        now = 300
        recording.mask(1L)
        now = 600
        recording.mask(0L)
        val score = MidiScoreParser.parse(recording.finish())
        assertEquals(0.3, score.seconds(score.tracks.single().notes.single().tick), 0.001)
        assertEquals(8, score.meters.single().denominator)
    }
}
