package com.timhxl.hallbeat

import org.junit.Assert.*
import org.junit.Test

class DrumTouchTrackerTest {
    @Test fun pressSlideHoldGapAndReenter() {
        val tracker = DrumTouchTracker()
        assertEquals(0, tracker.update(1, true, false, 0))
        assertNull(tracker.update(1, true, true, 0))
        assertEquals(1, tracker.update(1, true, true, 1))
        assertNull(tracker.update(1, true, true, null))
        assertEquals(1, tracker.update(1, true, true, 1))
        assertNull(tracker.update(1, false, true, 1))
        assertFalse(tracker.owns(1))
    }
    @Test fun multipleFingersAndCrossStickSlidesAreIndependent() {
        val tracker = DrumTouchTracker()
        assertEquals(0, tracker.update(1, true, false, 0))
        assertEquals(3, tracker.update(2, true, false, 3))
        assertEquals(2, tracker.update(3, true, false, 2))
        assertEquals(4, tracker.update(1, true, true, 4))
        assertNull(tracker.update(2, true, true, 3))
        assertTrue(tracker.owns(3))
        tracker.clear()
        assertFalse(tracker.owns(1))
    }
    @Test fun settingsGestureThatStartedOutsidePadsDoesNotPlay() {
        val tracker = DrumTouchTracker()
        assertNull(tracker.update(1, true, false, null))
        assertNull(tracker.update(1, true, true, 0))
        assertFalse(tracker.owns(1))
    }
}
