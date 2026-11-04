package com.timhxl.hallbeat

/** Physical layout: K01..K07 is the top row, left to right. Hidden key is excluded. */
internal object HiddenKeyPlan {
    fun practice(required: List<Int>, notes: List<Int>, enabled: List<Boolean>): Map<Int, Int> {
        require(notes.size == 35 && enabled.size == 35)
        val pitches = required.distinct()
        val present = notes.indices.filter { enabled[it] }.map { notes[it] }.toSet()
        val missing = pitches.filter { it !in present }
        val spare = (0 until 5).flatMap { row -> (6 downTo 0).map { row * 7 + it } }
            .filter { !enabled[it] || notes[it] !in pitches }
        require(missing.size <= spare.size) {
            "无法弹奏：缺少 ${missing.size} 种音高，可用实体键仅 ${spare.size} 个；第36键不能手动弹奏"
        }
        return spare.take(missing.size).zip(missing).toMap()
    }
}
