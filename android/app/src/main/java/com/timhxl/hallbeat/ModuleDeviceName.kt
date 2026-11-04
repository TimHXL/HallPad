package com.timhxl.hallbeat

/** 使用手册允许范围内的保守 ASCII 子集，避免字节长度与 AT 分隔符歧义。 */
internal object ModuleDeviceName {
    fun isValid(name: String): Boolean = name.matches(Regex("[A-Za-z0-9_-]{1,16}"))
    fun command(name: String): ByteArray { require(isValid(name)); return "AT+NAME=$name\r\n".toByteArray(Charsets.US_ASCII) }
    fun reportedName(line: String): String? {
        val match = Regex("^\\+?NAME\\s*[:=]\\s*([A-Za-z0-9_-]{1,16})$").matchEntire(line.trim())
        return match?.groupValues?.get(1)
    }
}
