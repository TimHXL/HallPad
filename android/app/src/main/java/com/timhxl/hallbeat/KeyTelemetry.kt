package com.timhxl.hallbeat

/** 遥测只更新显示，绝不生成发往设备的按键命令。 */
internal class KeyTelemetry {
    var onMask: ((Long) -> Unit)? = null
    var physicalMask = 0L
        private set
    val adc = IntArray(35) { -1 }
    private var recentPresses = 0L
    fun consumePresses(): Long { val result = recentPresses; recentPresses = 0; return result }
    private var keyTime = -1L
    private var adcFrame = -1
    fun reset() { recentPresses = 0; physicalMask = 0; adc.fill(-1); keyTime = -1; adcFrame = -1 }
    fun applyMask(timestamp: Long, mask: Long): Boolean {
        val delta = (timestamp - keyTime) and 0xFFFFFFFFL
        if (keyTime >= 0 && delta >= 0x80000000L) return false
        recentPresses = recentPresses or (mask and physicalMask.inv() and 0x7FFFFFFFFL)
        keyTime = timestamp; physicalMask = mask and 0x7FFFFFFFFL; onMask?.invoke(physicalMask); return true
    }
    fun activity(payload: ByteArray): Boolean {
        if (payload.size != 20) return false
        val b = HallPadProtocol.read(payload)
        return applyMask(b.getInt(0).toLong() and 0xFFFFFFFFL, b.getLong(4))
    }
    fun adcData(payload: ByteArray): Boolean {
        if (payload.size < 9) return false
        val b = HallPadProtocol.read(payload); val frame = b.getShort(0).toInt() and 65535
        val format = payload[6].toInt() and 255; val start = payload[7].toInt() and 255; val count = payload[8].toInt() and 255
        if (format != 0 || count !in 1..35 || start + count > 35 || payload.size != 9 + count * 2) return false
        val values = IntArray(count) { b.getShort(9 + it * 2).toInt() and 65535 }
        if (values.any { it > 4095 }) return false
        val delta = (frame - adcFrame) and 65535
        if (adcFrame >= 0 && delta >= 32768) return false
        adcFrame = frame
        values.forEachIndexed { i, value -> adc[start + i] = value }
        return true
    }
}
