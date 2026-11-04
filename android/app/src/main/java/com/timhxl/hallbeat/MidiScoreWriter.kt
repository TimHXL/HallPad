package com.timhxl.hallbeat

import java.io.ByteArrayOutputStream
import java.io.DataOutputStream

/** Standard MIDI format 1; exports all remaining tracks with current transposition and metadata. */
internal object MidiScoreWriter {
    private data class Event(val tick: Long, val priority: Int, val bytes: ByteArray)
    fun write(score: MidiScore): ByteArray {
        fun meta(type: Int, vararg data: Int) = byteArrayOf(0xff.toByte(), type.toByte(), data.size.toByte()) + data.map { it.toByte() }.toByteArray()
        val conductor = mutableListOf<Event>()
        score.tempos.forEach { conductor += Event(it.tick, 0, meta(0x51, it.micros shr 16, it.micros shr 8, it.micros)) }
        score.meters.forEach { meter ->
            require(meter.denominator > 0 && meter.denominator and (meter.denominator - 1) == 0)
            conductor += Event(meter.tick, 0, meta(0x58, meter.numerator, Integer.numberOfTrailingZeros(meter.denominator), 24, 8))
        }
        score.keys.forEach { conductor += Event(it.tick, 0, meta(0x59, it.sharps, if (it.minor) 1 else 0)) }
        fun track(events: List<Event>): ByteArray {
            val output = ByteArrayOutputStream()
            fun vlq(value: Long) {
                require(value in 0..0x0fffffffL) { "MIDI 时间间隔超出范围" }
                var number = value; val bytes = mutableListOf((number and 127).toInt()); number = number ushr 7
                while (number > 0) { bytes.add((number and 127).toInt() or 128); number = number ushr 7 }
                bytes.asReversed().forEach { output.write(it) }
            }
            var previous = 0L
            events.sortedWith(compareBy<Event> { it.tick }.thenBy { it.priority }).forEach {
                vlq(it.tick - previous); output.write(it.bytes); previous = it.tick
            }
            output.write(byteArrayOf(0, 0xff.toByte(), 0x2f, 0))
            return output.toByteArray()
        }
        val tracks = listOf(track(conductor)) + score.tracks.map { source ->
            val events = source.notes.flatMap { note ->
                listOf(Event(note.tick, 1, byteArrayOf((0x90 or note.channel).toByte(), note.midi.toByte(), note.velocity.toByte())),
                    Event(note.tick + note.duration.coerceAtLeast(1), 0, byteArrayOf((0x80 or note.channel).toByte(), note.midi.toByte(), 0)))
            }
            track(events)
        }
        val output = ByteArrayOutputStream()
        DataOutputStream(output).use { data ->
            data.writeInt(0x4d546864); data.writeInt(6); data.writeShort(1); data.writeShort(tracks.size); data.writeShort(score.resolution)
            tracks.forEach { data.writeInt(0x4d54726b); data.writeInt(it.size); data.write(it) }
        }
        return output.toByteArray()
    }
}
