package com.timhxl.hallbeat

import org.junit.Assert.*
import org.junit.Test

class DrumV5WireRegressionTest {
    @Test fun speed200UsesAllFourBytesAndPreservesOtherFields() {
        val config = DrumEffectConfig(speed = 200000, red = 255, green = 112, blue = 32)
        val data = config.encode()
        assertArrayEquals(byteArrayOf(0, 10, 0x40, 0x0d, 3, 0, 0xb0.toByte(), 4, 0xff.toByte(), 0x70, 0x20), data)
        assertEquals(config, DrumEffectConfig.decode(data))
    }
    @Test fun endpointsAndDefaultRoundTrip() {
        assertEquals(80000, DrumEffectConfig().speed)
        listOf(40000, 80000, 100000, 200000).forEach { speed ->
            val config = DrumEffectConfig(speed = speed)
            assertEquals(config, DrumEffectConfig.decode(config.encode()))
        }
    }
    @Test fun invalidSpeedsAreRejected() {
        listOf(39999, 200001).forEach { speed ->
            assertTrue(runCatching { DrumEffectConfig(speed = speed).encode() }.isFailure)
        }
    }
}
