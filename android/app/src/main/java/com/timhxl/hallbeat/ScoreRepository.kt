package com.timhxl.hallbeat

import android.content.Context
import java.io.File
import java.util.UUID

internal data class StoredScore(val id: String, val title: String)
internal data class ScoreKeyBackup(val scoreId: String?, val notes: List<Int>, val instruments: List<String>?, val velocities: List<Int>?, val modes: List<Int>?, val enabled: List<Boolean>?, val presetId: String?, val transpose: Int?, val customKey: ScoreKey?, val scoreKeys: List<ScoreKey>?, val spellings: List<Boolean>? = null)
internal class ScoreRepository(private val context: Context) {
    private val folder = File(context.filesDir, "scores").apply { mkdirs() }
    private val prefs = context.getSharedPreferences("score_library_v1", Context.MODE_PRIVATE)
    init {
        // 首次内置，用户删除后不再重复添加。
        if (!prefs.getBoolean("builtin_twinkle_v1", false)) {
            val bytes = context.assets.open("midi/Twinkle_Twinkle_C_major.mid").use { it.readBytes() }
            MidiScoreParser.parse(bytes)
            File(folder, "builtin_twinkle.mid").writeBytes(bytes)
            prefs.edit().putString("builtin_twinkle", "小星星").putBoolean("builtin_twinkle_v1", true).apply()
        }
    }
    init {
        if (!prefs.getBoolean("builtin_joy_v1", false)) {
            val bytes = context.assets.open("midi/Ode_to_Joy_B_flat_major.mid").use { it.readBytes() }
            MidiScoreParser.parse(bytes)
            File(folder, "builtin_joy.mid").writeBytes(bytes)
            prefs.edit().putString("builtin_joy", "欢乐颂 · B♭大调").putBoolean("builtin_joy_v1", true).apply()
        }
    }
    fun rename(id: String, title: String): StoredScore { val clean = title.trim(); require(clean.isNotEmpty() && clean.length <= 100); prefs.edit().putString(id, clean).apply(); return StoredScore(id, clean) }
    fun transpose(id: String): Int = prefs.getInt("transpose_$id", 0).coerceIn(-12, 12)
    fun transpose(id: String, value: Int) { prefs.edit().putInt("transpose_$id", value).apply() }
    fun list(): List<StoredScore> {
        val saved = prefs.getString("library_order", "")!!.split(',').filter { it.isNotBlank() }
        val files = folder.listFiles()?.filter { it.extension == "mid" }?.sortedByDescending { it.lastModified() } ?: emptyList()
        val fileIds = files.map { it.nameWithoutExtension }
        val available = fileIds.toHashSet()
        val savedSet = saved.toHashSet()
        val order = saved.filter { it in available }.distinct() + fileIds.filter { it !in savedSet }
        return order.map { StoredScore(it, prefs.getString(it, "未命名曲目") ?: "未命名曲目") }
    }
    fun order(ids: List<String>) { prefs.edit().putString("library_order", ids.distinct().joinToString(",")).apply() }
    fun rawMidi(id: String): ByteArray = File(folder, "$id.mid").readBytes()
    fun read(id: String): MidiScore {
        val parsed = MidiScoreParser.parse(File(folder, "$id.mid").readBytes())
        val filtered = parsed.copy(tracks = parsed.tracks.map { track ->
            val removed = prefs.getStringSet("removed_${id}_${track.index}", emptySet()) ?: emptySet()
            track.copy(notes = track.notes.filterNot { it.tick.toString() in removed })
        })
        val custom = keySignature(id); return if (custom == null) filtered else filtered.copy(keys = listOf(custom))
    }
    fun deleteGroup(id: String, track: Int, tick: Long) {
        val key = "removed_${id}_$track"
        val removed = (prefs.getStringSet(key, emptySet()) ?: emptySet()).toMutableSet()
        removed.add(tick.toString()); prefs.edit().putStringSet(key, removed).apply()
    }
    fun keySignature(id: String): ScoreKey? = if (prefs.contains("key_sharps_$id")) ScoreKey(0, prefs.getInt("key_sharps_$id", 0).coerceIn(-7, 7), prefs.getBoolean("key_minor_$id", false)) else null
    fun keySignature(id: String, key: ScoreKey) { prefs.edit().putInt("key_sharps_$id", key.sharps).putBoolean("key_minor_$id", key.minor).apply() }
    fun add(bytes: ByteArray, title: String): StoredScore { val id = UUID.randomUUID().toString(); File(folder, "$id.mid").writeBytes(bytes); prefs.edit().putString(id, title.take(100)).apply(); return StoredScore(id, title) }
    fun delete(id: String) { File(folder, "$id.mid").delete(); prefs.edit().remove(id).remove("track_$id").remove("position_$id").remove("transpose_$id").remove("key_sharps_$id").remove("key_minor_$id").apply() }
    fun track(id: String): Int = prefs.getInt("track_$id", -1)
    fun position(id: String): Double = prefs.getFloat("position_$id", 0f).toDouble()
    fun save(id: String, track: Int, position: Double) { prefs.edit().putInt("track_$id", track).putFloat("position_$id", position.toFloat()).putString("last", id).apply() }
    // 快照独立保存，兼容旧版本只备份了音高的记录。
    fun backup(): ScoreKeyBackup? {
        val raw = prefs.getString("key_backup_v2", null)
        if (raw != null) return runCatching {
            val obj = org.json.JSONObject(raw); val keys = obj.getJSONArray("keys"); require(keys.length() == 35)
            val notes = List(35) { keys.getJSONObject(it).getInt("note").also { n -> require(n in 0..127) } }
            val instruments = List(35) { keys.getJSONObject(it).getString("instrument").also { name -> require(name in HallPadInstruments || name == "跟随全局") } }
            val velocities = List(35) { keys.getJSONObject(it).getInt("velocity").also { n -> require(n in 1..127) } }
            val modes = List(35) { keys.getJSONObject(it).getInt("mode").also { n -> require(n in 0..1) } }
            val enabled = List(35) { keys.getJSONObject(it).getBoolean("enabled") }
            val scoreKeys = obj.getJSONArray("scoreKeys").let { array -> List(array.length()) { i -> val item = array.getJSONObject(i); ScoreKey(item.getLong("tick"), item.getInt("sharps"), item.getBoolean("minor")) } }
            val customKey = if (obj.isNull("customKey")) null else obj.getJSONObject("customKey").let { ScoreKey(0, it.getInt("sharps"), it.getBoolean("minor")) }
            ScoreKeyBackup(obj.getString("scoreId"), notes, instruments, velocities, modes, enabled, obj.optString("presetId").takeIf { it.isNotEmpty() }, obj.getInt("transpose"), customKey, scoreKeys, if (keys.getJSONObject(0).has("flatName")) List(35) { keys.getJSONObject(it).optBoolean("flatName", false) } else null)
        }.getOrNull()
        val legacy = prefs.getString("pitch_backup", null)?.split(',')?.mapNotNull { it.toIntOrNull() }?.takeIf { it.size == 35 && it.all { n -> n in 0..127 } } ?: return null
        return ScoreKeyBackup(null, legacy, null, null, null, null, null, null, null, null)
    }
    fun saveBackup(value: ScoreKeyBackup): Boolean {
        require(value.scoreId != null && value.instruments != null && value.velocities != null && value.modes != null && value.enabled != null && value.transpose != null && value.scoreKeys != null)
        val keys = org.json.JSONArray(); repeat(35) { i -> keys.put(org.json.JSONObject().put("note", value.notes[i]).put("instrument", value.instruments[i]).put("velocity", value.velocities[i]).put("mode", value.modes[i]).put("enabled", value.enabled[i]).put("flatName", value.spellings?.getOrNull(i) ?: false)) }
        val scoreKeys = org.json.JSONArray(); value.scoreKeys.forEach { key -> scoreKeys.put(org.json.JSONObject().put("tick", key.tick).put("sharps", key.sharps).put("minor", key.minor)) }
        val custom = value.customKey?.let { org.json.JSONObject().put("sharps", it.sharps).put("minor", it.minor) } ?: org.json.JSONObject.NULL
        val obj = org.json.JSONObject().put("scoreId", value.scoreId).put("keys", keys).put("scoreKeys", scoreKeys).put("customKey", custom).put("transpose", value.transpose).put("presetId", value.presetId ?: "")
        return prefs.edit().putString("key_backup_v2", obj.toString()).putBoolean("keep_applied_keys", false).commit()
    }
    fun keepAppliedKeys(): Boolean = prefs.getBoolean("keep_applied_keys", false)
    fun keepAppliedKeys(value: Boolean) { prefs.edit().putBoolean("keep_applied_keys", value).apply() }
    fun clearBackup() { prefs.edit().remove("key_backup_v2").remove("pitch_backup").remove("keep_applied_keys").apply() }
    fun restoreScoreSettings(value: ScoreKeyBackup) {
        val id = value.scoreId ?: return
        val editor = prefs.edit().putInt("transpose_$id", value.transpose ?: 0)
        if (value.customKey == null) editor.remove("key_sharps_$id").remove("key_minor_$id") else editor.putInt("key_sharps_$id", value.customKey.sharps).putBoolean("key_minor_$id", value.customKey.minor)
        editor.apply()
    }
    fun last(): String? = prefs.getString("last", null)
}

