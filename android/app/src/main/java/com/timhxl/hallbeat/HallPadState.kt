package com.timhxl.hallbeat

import android.content.Context
import androidx.compose.runtime.*
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/** FPGA 音色编号，保留硬件编号空位，禁止按列表下标发送。 */
internal val HallPadInstrumentIds = linkedMapOf("钢琴" to 1, "风琴" to 2, "钟琴" to 3, "木琴" to 4, "马林巴" to 5, "电钢琴" to 6, "拨弦" to 7, "长笛" to 8, "贝斯" to 9, "小军鼓" to 11, "弦乐" to 13, "小提琴" to 14)
internal val HallPadInstruments = HallPadInstrumentIds.keys.toList()
internal val KeyInstruments = listOf("跟随全局") + HallPadInstruments
internal fun defaultNote(id: Int): Int = 60 + (2 - id / 7) * 12 + listOf(0, 2, 4, 5, 7, 9, 11)[id % 7]
internal data class HallPadPreset(val id: String, val name: String, val configuration: String)

/** 本地配置与设备连接状态分开保存，不把演示数据写入配置。 */
internal class HallPadState(context: Context) {
    private val preferences = HallPadStorage.get(context).configuration
    var preferFlats by mutableStateOf(preferences.getBoolean("prefer_flat_names", false))
        private set
    fun setNoteSpelling(flats: Boolean) {
        preferFlats = flats
        preferences.edit().putBoolean("prefer_flat_names", flats).apply()
    }
    private val flatKeyNames = mutableStateListOf<Boolean>().apply {
        addAll(List(35) { preferences.getBoolean("flat_key_name_$it", preferFlats) })
    }
    fun keyUsesFlats(id: Int): Boolean = flatKeyNames[id]
    fun setKeySpelling(id: Int, flats: Boolean) {
        flatKeyNames[id] = flats
        preferences.edit().putBoolean("flat_key_name_$id", flats).apply()
    }
    val performance = PerformanceSettings()
    var volume by mutableFloatStateOf(0.5f)
    var muted by mutableStateOf(false)
        private set
    val effectiveVolume: Float get() = if (muted) 0f else volume
    var onKeyConfigRemote: ((List<Int>) -> Unit)? = null
    var keyConfigurationConfirmed: ((List<HallPadSession.KeyConfig>) -> Boolean)? = null
    private var lastKeyConfiguration: List<String> = emptyList()
    private fun keyConfiguration(): List<String> = List(35) { "$it:${keyEnabled[it]}:${notes[it]}:${keyInstruments[it]}:${velocities[it]}:${velocityModes[it]}" }
    var onKeyRemote: ((Int, Boolean) -> Unit)? = null
    var deviceMessage by mutableStateOf("")
    var unsupportedParameterIds by mutableStateOf<Set<Int>>(emptySet())
    fun canControlParameter(id: Int): Boolean = id !in unsupportedParameterIds
    var onPlaybackKeyRemote: ((Int, Boolean) -> Unit)? = null
    private val keyHolds = KeyHoldOwners { id, down, playback ->
        if (down) {
            pressed[id] = true
            touchVelocities[id] = (Math.pow(velocities[id] / 127.0, curve.toDouble()) * 127).toInt().coerceIn(1, 127)
        } else { pressed.remove(id); touchVelocities.remove(id) }
        if (playback) onPlaybackKeyRemote?.invoke(id, down) else onKeyRemote?.invoke(id, down)
    }
    fun setKeyPressed(id: Int, down: Boolean) = keyHolds.set(id, down, false)
    fun setPlaybackKeyPressed(id: Int, down: Boolean) = keyHolds.set(id, down, true)
    fun setManualKeys(keys: Set<Int>) = keyHolds.setManual(keys)
    fun releaseManualKeys() = keyHolds.setManual(emptySet())
    var onReleaseRemote: (() -> Unit)? = null
    var onMuteRemote: ((Boolean) -> Unit)? = null
    var onParameterRemote: ((Int, Int) -> Unit)? = null
    var mutePending by mutableStateOf(false)
    fun sendParameter(id: Int, value: Int) { if (canControlParameter(id)) onParameterRemote?.invoke(id, value) }
    fun applyDeviceMute(value: Boolean) { muted = value }
    fun toggleMute() { releaseAll(); performance.center(); onMuteRemote?.let { it(!muted) } ?: run { muted = !muted } }
    var instrument by mutableStateOf("钢琴")
    var attack by mutableFloatStateOf(0.02f)
    var release by mutableFloatStateOf(0.2f)
    var brightness by mutableFloatStateOf(1f)
    var curve by mutableFloatStateOf(1f)
    var effect by mutableStateOf("水波")
    var selectedKey by mutableIntStateOf(0)
    var selectedKeys by mutableStateOf<Set<Int>>(emptySet())
    var selectionMode by mutableStateOf(false)
    var selectingKeys by mutableStateOf(false)
    val keyEnabled = mutableStateListOf<Boolean>().apply { addAll(List(35) { true }) }
    val notes = mutableStateListOf<Int>().apply { addAll(List(35, ::defaultNote)) }
    val keyInstruments = mutableStateListOf<String>().apply { addAll(List(35) { "跟随全局" }) }
    val velocityModes = mutableStateListOf<Int>().apply { addAll(List(35) { 0 }) }
    val velocities = mutableStateListOf<Int>().apply { addAll(List(35) { 100 }) }
    val pressed = mutableStateMapOf<Int, Boolean>()
    private val touchVelocities = mutableStateMapOf<Int, Int>()
    val playbackPressed = mutableStateMapOf<Int, Int>()
    val physicalPressed = mutableStateMapOf<Int, Boolean>()
    var showAdc by mutableStateOf(false)
    val liveAdc = mutableStateListOf<Int>().apply { addAll(List(35) { -1 }) }
    val physicalPulseUntil = mutableStateListOf<Long>().apply { addAll(List(35) { 0L }) }
    fun displayedPressed(id: Int): Boolean = pressed[id] == true || playbackPressed.containsKey(id) || physicalPressed[id] == true || physicalPulseUntil[id] > android.os.SystemClock.elapsedRealtime()
    fun displayedVelocity(id: Int): Int {
        if (pressed[id] == true) return touchVelocities[id] ?: 0
        playbackPressed[id]?.let { return it }
        if (physicalPressed[id] == true) return if (velocityModes[id] == 1) velocities[id] else -1
        return 0
    }
    fun clearTelemetry() { physicalPressed.clear(); repeat(35) { liveAdc[it] = -1; physicalPulseUntil[it] = 0 } }
    val presets = mutableStateListOf<HallPadPreset>()
    var activePresetId by mutableStateOf<String?>(null)
        private set
    init {
        runCatching {
            val array = JSONArray(preferences.getString("presets", "[]"))
            for (index in 0 until array.length()) {
                val item = array.getJSONObject(index)
                val config = item.getString("configuration")
                if (validConfiguration(config)) {
                    val migrated = JSONObject(config)
                    val defaults = PerformanceSettings().apply { load(migrated.optJSONObject("performance")) }
                    migrated.put("performance", defaults.encode())
                    presets.add(HallPadPreset(item.getString("id"), item.getString("name"), migrated.toString()))
                }
            }
        }
        preferences.getString("current", null)?.let { applyConfiguration(it) }
        activePresetId = preferences.getString("active", null)?.takeIf { id -> presets.any { it.id == id } }
        lastKeyConfiguration = keyConfiguration()
    }
    fun releaseAll() { keyHolds.clear(); pressed.clear(); touchVelocities.clear(); onReleaseRemote?.invoke() }
    fun effectiveInstrument(id: Int): String = keyInstruments[id].let { if (it == "跟随全局") instrument else it }
    fun encode(): String = JSONObject().apply {
        put("version", 1)
        put("volume", volume.toDouble()); put("instrument", instrument)
        put("attack", attack.toDouble()); put("release", release.toDouble())
        put("brightness", brightness.toDouble()); put("curve", curve.toDouble()); put("effect", effect)
        put("keys", JSONArray().apply { repeat(35) { id -> put(JSONObject().put("note", notes[id]).put("instrument", keyInstruments[id]).put("velocity", velocities[id]).put("velocityMode", velocityModes[id]).put("enabled", keyEnabled[id])) } })
        put("performance", performance.encode())
    }.toString()
    private fun validConfiguration(text: String): Boolean = runCatching {
        val json = JSONObject(text)
        require(json.getInt("version") == 1)
        require(json.getString("instrument") in HallPadInstruments)
        require(json.getString("effect") in listOf("水波", "常亮", "关闭"))
        for (name in listOf("volume", "attack", "release", "brightness")) require(json.getDouble(name).let { it.isFinite() && it in 0.0..1.0 })
        require(json.getDouble("curve").let { it.isFinite() && it in 0.3..3.0 })
        val keys = json.getJSONArray("keys")
        require(keys.length() == 35)
        repeat(35) { id ->
            val key = keys.getJSONObject(id)
            require(key.getInt("note") in 0..127 && key.getInt("velocity") in 1..127 && key.getString("instrument") in KeyInstruments)
        }
        true
    }.getOrDefault(false)
    fun applyConfiguration(text: String): Boolean {
        if (!validConfiguration(text)) return false
        val json = JSONObject(text)
        performance.load(json.optJSONObject("performance"))
        releaseAll(); selectedKeys = emptySet()
        volume = json.getDouble("volume").toFloat(); instrument = json.getString("instrument")
        attack = json.getDouble("attack").toFloat(); release = json.getDouble("release").toFloat().coerceIn(0.01f, 0.2f)
        brightness = json.getDouble("brightness").toFloat(); curve = json.getDouble("curve").toFloat(); effect = json.getString("effect")
        repeat(35) { id ->
            val key = json.getJSONArray("keys").getJSONObject(id)
            notes[id] = key.getInt("note"); keyInstruments[id] = key.getString("instrument"); velocities[id] = key.getInt("velocity"); velocityModes[id] = key.optInt("velocityMode", 1).coerceIn(0, 1); keyEnabled[id] = key.optBoolean("enabled", true)
        }
        sendParameter(1, (volume * 1000).toInt())
        HallPadInstrumentIds[instrument]?.let { sendParameter(2, it) }
        sendParameter(0x60, listOf("水波", "常亮", "关闭").indexOf(effect))
        sendParameter(0x61, (brightness * 1000).toInt())
        sendParameter(0x40, if (performance.reverbEnabled) 1 else 0)
        sendParameter(0x42, (performance.reverbAmount * 1000).toInt())
        return true
    }
    fun applyDeviceKeys(values: Map<Int, HallPadSession.KeyConfig>) {
        values.forEach { (id, config) ->
            keyEnabled[id] = config.enabled; notes[id] = config.midi; velocities[id] = config.velocity; velocityModes[id] = config.mode
            keyInstruments[id] = HallPadInstrumentIds.entries.firstOrNull { it.value == config.timbre }?.key ?: "跟随全局"
        }
        lastKeyConfiguration = keyConfiguration()
    }
    fun persist(configuration: String = encode()) {
        val next = keyConfiguration()
        val changed = (0 until 35).filter { lastKeyConfiguration.getOrNull(it) != next[it] }
        lastKeyConfiguration = next
        preferences.edit().putString("current", configuration).putString("active", activePresetId).apply()
        if (changed.isNotEmpty()) onKeyConfigRemote?.invoke(changed)
    }
    private fun persistPresets() {
        val array = JSONArray()
        presets.forEach { array.put(JSONObject().put("id", it.id).put("name", it.name).put("configuration", it.configuration)) }
        preferences.edit().putString("presets", array.toString()).apply()
        persist()
    }
    fun validName(name: String, exceptId: String? = null): Boolean = name.trim().let { candidate -> candidate.isNotEmpty() && candidate.length <= 24 && presets.none { it.id != exceptId && it.name.equals(candidate, ignoreCase = true) } }
    fun savePreset(name: String): Boolean {
        if (!validName(name)) return false
        val preset = HallPadPreset(UUID.randomUUID().toString(), name.trim(), encode())
        presets.add(preset); activePresetId = preset.id; persistPresets()
        return true
    }
    fun restorePresetSelection(id: String?) { activePresetId = id?.takeIf { wanted -> presets.any { it.id == wanted } } }
    fun selectPreset(id: String) {
        val preset = presets.firstOrNull { it.id == id } ?: return
        if (applyConfiguration(preset.configuration)) { activePresetId = id; persist() }
    }
    fun updatePreset(id: String) {
        val index = presets.indexOfFirst { it.id == id }
        if (index < 0) return
        presets[index] = presets[index].copy(configuration = encode()); activePresetId = id; persistPresets()
    }
    fun renamePreset(id: String, name: String): Boolean {
        val index = presets.indexOfFirst { it.id == id }
        if (index < 0 || !validName(name, id)) return false
        presets[index] = presets[index].copy(name = name.trim()); persistPresets()
        return true
    }
    fun deletePreset(id: String) {
        presets.removeAll { it.id == id }
        if (activePresetId == id) activePresetId = null
        persistPresets()
    }
    fun resetKeys() {
        selectedKeys = emptySet()
        releaseAll()
        repeat(35) { id -> notes[id] = defaultNote(id); keyInstruments[id] = "跟随全局"; velocities[id] = 100; velocityModes[id] = 0; keyEnabled[id] = true }
        persist()
    }
}
