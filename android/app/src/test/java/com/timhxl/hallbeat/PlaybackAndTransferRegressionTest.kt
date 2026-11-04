package com.timhxl.hallbeat

import org.junit.Assert.*
import org.junit.Test

class PlaybackAndTransferRegressionTest {
    @Test fun touchOnAnotherKeyDoesNotReleasePlayback() {
        val edges = mutableListOf<Pair<Int, Boolean>>()
        val holds = KeyHoldOwners { id, down, _ -> edges.add(id to down) }
        holds.set(0, true, true)
        holds.setManual(setOf(3)); holds.setManual(emptySet())
        assertEquals(listOf(0 to true, 3 to true, 3 to false), edges)
        holds.set(0, false, true)
        assertEquals(0 to false, edges.last())
    }
    @Test fun overlappingManualHoldDoesNotCutLongNote() {
        val edges = mutableListOf<Boolean>()
        val holds = KeyHoldOwners { _, down, _ -> edges.add(down) }
        holds.set(0, true, true)
        holds.setManual(setOf(0)); holds.setManual(emptySet())
        assertEquals(listOf(true), edges)
        holds.set(0, false, true)
        assertEquals(listOf(true, false), edges)
    }
    @Test fun playbackReleasePreservesManualHold() {
        val edges = mutableListOf<Boolean>()
        val holds = KeyHoldOwners { _, down, _ -> edges.add(down) }
        holds.setManual(setOf(0)); holds.set(0, true, true)
        holds.set(0, false, true)
        assertEquals(listOf(true), edges)
        holds.setManual(emptySet())
        assertEquals(listOf(true, false), edges)
    }
    private fun song() = PracticeSong(listOf(PracticeGroup(0, 0, 100, 1L, 1, 100)), ByteArray(24), 1, 2, 100)
    @Test fun cancelUploadIgnoresLateCapabilitiesAndAcknowledgements() {
        val sent = mutableListOf<Int>(); var discarded = 0
        val controller = PracticeController({ type, _ -> sent.add(type) }, { 0L }, { discarded++ })
        controller.upload(song(), false)
        controller.cancel()
        val cap = PracticeWire.buffer(16).putShort(1).putShort(1).putInt(4096).putInt(100000).putShort(192).putShort(24).array()
        controller.packet(0x60, cap)
        controller.ack(0x62, 0, 0)
        controller.tick()
        assertEquals("IDLE", controller.state.value.phase)
        assertEquals(listOf(0x60, 0x67), sent)
        assertEquals(1, discarded)
    }
    @Test fun cancelVerificationDoesNotReenterReady() {
        val controller = PracticeController({ _, _ -> }, { 0L })
        controller.upload(song(), false)
        val cap = PracticeWire.buffer(16).putShort(1).putShort(1).putInt(4096).putInt(100000).putShort(192).putShort(24).array()
        controller.packet(0x60, cap); controller.ack(0x61, 0, 0)
        controller.ack(0x62, 0, 0); controller.ack(0x63, 0, 0)
        assertEquals("VERIFYING", controller.state.value.phase)
        controller.cancel()
        controller.ack(0x63, 0, 0)
        assertEquals("IDLE", controller.state.value.phase)
    }
    @Test fun discardUploadFramesPreservesKeyAndHeartbeatFrames() {
        fun frame(type: Int) = HallPadProtocol.encode(HallPadProtocol.Frame(type, 0, 0, 1, byteArrayOf()))
        val queue = HallPadTxQueue { frame(0x13) }
        queue.offer(frame(0x62)); queue.offer(frame(2)); queue.offer(frame(0x10))
        queue.discardPractice(); queue.offer(frame(0x67))
        val types = queue.bundle(244).map { it[3].toInt() and 255 }
        assertEquals(0x67, types.first())
        assertFalse(0x62 in types)
        assertTrue(2 in types); assertTrue(0x10 in types)
    }
}
