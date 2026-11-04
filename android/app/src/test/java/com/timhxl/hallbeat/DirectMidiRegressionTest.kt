package com.timhxl.hallbeat

import org.junit.Assert.*
import org.junit.Test

class DirectMidiRegressionTest {
    private fun score(notes: List<ScoreNote>) = MidiScore(480, listOf(ScoreTrack(0, "test", notes)), listOf(ScoreTempo(0, 500000)), emptyList(), emptyList())
    @Test fun overlappingSamePitchHasIndependentIds() {
        val notes = listOf(ScoreNote(0, 960, 61, 90, 0), ScoreNote(480, 960, 61, 110, 0))
        val timeline = DirectMidiTimeline.compile(score(notes), notes)
        assertEquals(2, timeline.peak)
        assertEquals(2, timeline.events.filter { it.down }.map { it.voice.id }.distinct().size)
    }
    @Test fun allMidiPitchesArePreservedWithoutKeyMapping() {
        val notes = listOf(0, 60, 61, 127).mapIndexed { i, midi -> ScoreNote(i * 480L, 240, midi, 100, 0) }
        val timeline = DirectMidiTimeline.compile(score(notes), notes)
        assertEquals(listOf(0, 60, 61, 127), timeline.events.filter { it.down }.map { it.voice.midi })
        assertEquals(1, timeline.peak)
    }
    @Test fun reusedIdIsReleasedBeforeSameTimeNewOnset() {
        val notes = listOf(ScoreNote(0, 480, 60, 100, 0), ScoreNote(480, 480, 61, 100, 0))
        val timeline = DirectMidiTimeline.compile(score(notes), notes)
        val boundary = timeline.events.filter { it.seconds == 0.5 }
        assertFalse(boundary[0].down); assertTrue(boundary[1].down)
        assertEquals(boundary[0].voice.id, boundary[1].voice.id)
    }
    @Test(expected = IllegalArgumentException::class) fun percussionIsRejected() {
        val notes = listOf(ScoreNote(0, 480, 36, 100, 9))
        DirectMidiTimeline.compile(score(notes), notes)
    }
    @Test fun manyMissingInstancesRemainAvailableForFirstNotePolicy() {
        val notes = List(40) { ScoreNote(0, 480, it, 100, 0) }
        assertEquals(40, DirectMidiTimeline.compile(score(notes), notes).peak)
    }
    @Test fun practiceUsesTopRightSpareAndPreservesRequiredKeys() {
        val notes = (40..74).toList()
        val plan = HiddenKeyPlan.practice(listOf(46, 60, 1, 2), notes, List(35) { true })
        // K07 already supplies pitch46; use K06 then K05.
        assertEquals(linkedMapOf(5 to 1, 4 to 2), plan)
        assertTrue(plan.keys.none { notes[it] == 46 || notes[it] == 60 })
    }
    @Test(expected = IllegalArgumentException::class) fun hiddenKeyDoesNotIncreasePracticeCapacity() {
        HiddenKeyPlan.practice((40..74).toList() + 1, (40..74).toList(), List(35) { true })
    }
    @Test fun disabledKeyCanSupplyMissingPitch() {
        val enabled = MutableList(35) { true }.apply { this[6] = false }
        assertEquals(mapOf(6 to 46), HiddenKeyPlan.practice((40..74).toList(), (40..74).toList(), enabled))
    }
    @Test fun reliableReleaseSnapshotSurvivesRealtimeCoalescing() {
        fun frame(type: Int, reliable: Boolean, seq: Int) = HallPadProtocol.encode(HallPadProtocol.Frame(type, if (reliable) 1 else 0, seq, 1, byteArrayOf()))
        val queue = HallPadTxQueue { frame(0x13, false, 99) }
        queue.offer(frame(0x13, true, 1))
        repeat(12) { queue.offer(frame(0x10, false, it + 2)) }
        queue.offer(frame(0x13, false, 30)); queue.offer(frame(0x13, false, 31))
        val frames = queue.bundle(10000)
        assertEquals(1, frames.count { it[3].toInt() == 0x13 && it[4].toInt() and 1 != 0 })
    }
}
