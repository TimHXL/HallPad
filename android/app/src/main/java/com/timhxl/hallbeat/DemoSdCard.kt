package com.timhxl.hallbeat

import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Sparse FAT32 card behind the same block commands as the FPGA. */
internal class DemoSdCard {
    private val sectors = mutableMapOf<Int, ByteArray>()
    private val buffer = ByteArray(512)
    private var locked = false

    init {
        val boot = ByteBuffer.allocate(512).order(ByteOrder.LITTLE_ENDIAN)
        boot.putShort(11, 512)
        boot.put(13, 1)
        boot.putShort(14, 32)
        boot.put(16, 1)
        boot.putInt(32, 70000)
        boot.putInt(36, 600)
        boot.putInt(44, 2)
        boot.putShort(510, 0xaa55.toShort())
        sectors[0] = boot.array()
        val fat = ByteBuffer.allocate(512).order(ByteOrder.LITTLE_ENDIAN)
        fat.putInt(0x0ffffff8).putInt(0x0fffffff).putInt(0x0fffffff)
        sectors[32] = fat.array()
    }

    fun exchange(request: ByteArray): ByteArray {
        val operation = request[0].toInt()
        val reply = ByteArray(36)
        reply[0] = request[0]
        val args = ByteBuffer.wrap(request).order(ByteOrder.LITTLE_ENDIAN)
        if (!locked && operation != 0) {
            reply[1] = 5
            return reply
        }
        when (operation) {
            0 -> locked = true
            1 -> locked = false
            2 -> {
                val sector = sectors[args.getInt(1)]
                if (sector == null) buffer.fill(0) else sector.copyInto(buffer)
            }
            3 -> request.copyInto(buffer, args.getShort(1).toInt(), 3)
            4 -> sectors[args.getInt(1)] = buffer.copyOf()
            5 -> {
                val offset = args.getShort(1).toInt()
                buffer.copyInto(reply, 4, offset, offset + 32)
            }
            else -> reply[1] = 7
        }
        return reply
    }
}
