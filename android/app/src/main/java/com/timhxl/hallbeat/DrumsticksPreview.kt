package com.timhxl.hallbeat

import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.semantics
import android.content.Context
import java.nio.ByteBuffer
import java.nio.ByteOrder
import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.roundToInt
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalFocusManager

/** 演示状态保存在手机；真实设备配置使用蓝牙读回。 */
internal class DrumsticksPreviewState(context: Context) {
    private val preferences = context.getSharedPreferences("drumsticks_preview", Context.MODE_PRIVATE)
    val padHits = mutableStateMapOf<Int, Int>()
    val sticks = List(2) { index ->
        val defaults = if (index == 0) listOf("军鼓", "踩镲", "通鼓") else listOf("通鼓", "吊镲", "叮叮镲")
        DrumstickPreviewState(index, List(3) { direction -> preferences.getString("voice_${index}_$direction", defaults[direction]) ?: defaults[direction] }, preferences.getInt("velocity_$index", 100).coerceIn(0, 127)).also { it.threshold = preferences.getInt("threshold_$index", 160).coerceIn(30, 1600); it.cooldown = preferences.getInt("cooldown_$index", 130).coerceIn(20, 500) }
    }
    private var lastDeviceEffect: DrumEffectConfig? = if (!preferences.getBoolean("effect_cached", false)) null else DrumEffectConfig(
        preferences.getInt("effect_mode", 0).coerceIn(0, 2), preferences.getInt("effect_brightness", 10).coerceIn(0, 100),
        preferences.getInt("effect_speed", 80000).coerceIn(40000, 200000), preferences.getInt("effect_decay", 1200).coerceIn(200, 5000),
        preferences.getInt("effect_r", 32).coerceIn(0, 255), preferences.getInt("effect_g", 112).coerceIn(0, 255), preferences.getInt("effect_b", 255).coerceIn(0, 255))
    var effectSupported by mutableStateOf(false)
    var effectConfig by mutableStateOf<DrumEffectConfig?>(null)
    var effectPending by mutableStateOf(false)
    var effectMessage by mutableStateOf("")
    fun refreshEffect() { if (!demo && effectSupported) protocol?.readDrumEffect() }
    var effectDraft by mutableStateOf<DrumEffectConfig?>(null)
    private var sentEffect: DrumEffectConfig? = null
    private var effectSetAccepted = false
    private var effectDirty = false
    fun stageEffect(config: DrumEffectConfig) {
        val normalized = config.copy(speed = (config.speed.coerceIn(40000, 200000) / 1000f).roundToInt() * 1000)
        effectDraft = normalized; effectDirty = normalized != (if (effectPending) sentEffect else effectConfig)
        if (demo) { effectConfig = normalized; effectDirty = false }
    }
    fun flushEffect() {
        val config = effectDraft ?: return
        if (!effectPending && config == effectConfig) { effectDirty = false; return }
        if (!effectDirty || effectPending || !effectSupported || effectConfig == null || demo) return
        sentEffect = config; effectSetAccepted = false; effectDirty = false; effectPending = true
        protocol?.setDrumEffect(config.encode())
    }
    fun readEffect(data: ByteArray) {
        val config = DrumEffectConfig.decode(data) ?: return
        if (!demo) {
            lastDeviceEffect = config
            preferences.edit().putBoolean("effect_cached", true).putInt("effect_mode", config.mode)
                .putInt("effect_brightness", config.brightness).putInt("effect_speed", config.speed)
                .putInt("effect_decay", config.decayMs).putInt("effect_r", config.red).putInt("effect_g", config.green)
                .putInt("effect_b", config.blue).apply()
        }
        // An older GET may complete before our queued SET. Do not let it acknowledge that SET.
        if (effectPending && sentEffect != null && !effectSetAccepted) { effectConfig = config; return }
        val mismatched = effectPending && sentEffect != null && config != sentEffect
        effectSetAccepted = false
        effectConfig = config; effectPending = false
        if (!effectDirty) effectDraft = config
        sentEffect = null; effectMessage = if (mismatched) "设备读回与提交不一致，请检查固件范围后重试" else "已读回设备灯光设置"
        flushEffect()
    }
    var demo by mutableStateOf(false)
    var supported by mutableStateOf(false)
    var colorSupported by mutableStateOf(false)
    var color by mutableStateOf<DrumColorConfig?>(null)
    var colorPending by mutableStateOf(false)
    var colorMessage by mutableStateOf("")
    fun refreshColor() { if (!demo && colorSupported) protocol?.readDrumColor() }
    fun readColor(data: ByteArray) {
        val actual = DrumColorConfig.decode(data) ?: return
        color = actual; colorPending = false; colorMessage = "已读回设备配色"
    }
    fun applyColor(config: DrumColorConfig) {
        if (demo) { color = config; return }
        if (!colorSupported || color == null || colorPending) return
        colorPending = true; protocol?.setDrumColor(config.encode())
    }
    private var calibrationStatusReceived = false
    var calibrationSupported by mutableStateOf(false)
    var lightSupported by mutableStateOf(false)
    var calibrationState by mutableIntStateOf(-1)
    var calibrationReason by mutableIntStateOf(0)
    var calibrationPending by mutableStateOf(false)
    var controlMessage by mutableStateOf("")
    var light by mutableStateOf<DrumLightConfig?>(null)
    var lightPending by mutableStateOf(false)
    var lightMessage by mutableStateOf("")
    var attemptId by mutableIntStateOf(-1)
        private set
    private var requestedAttempt = -1
    private var protocol: HallPadSession? = null
    fun refreshCalibration() { if (!demo && calibrationSupported) protocol?.readDrumCalibration() }
    fun startCalibration() {
        if (demo || !calibrationSupported || calibrationPending || calibrationState in 1..2) return
        requestedAttempt = attemptId; calibrationPending = true; controlMessage = "正在请求校准…"; protocol?.startDrumCalibration()
    }
    fun receiveControlAck(type: Int, result: Int) {
        if (type == 0x83) { effectSetAccepted = result == 0; effectPending = result == 0; if (result != 0) { effectDirty = false; effectDraft = effectConfig; sentEffect = null }; effectMessage = if (result == 0) "正在读回…" else "灯光设置失败，请检查设备范围；100 灯/秒以上需 V5 固件" }
        if (type == 0x84 && result != 0) { effectPending = false; effectDirty = false; effectDraft = effectConfig; sentEffect = null; effectMessage = "读取灯光失败，请重试" }
        if (type == 0x7D) { colorPending = result == 0; colorMessage = if (result == 0) "正在读回配色…" else "配色设置失败，请重试" }
        if (type == 0x7E && result != 0) { colorPending = false; colorMessage = "读取配色失败，请重新读取" }
        if (type == 0x77) { calibrationPending = result == 0; controlMessage = if (result == 0) "校准请求已接受，等待设备状态" else "无法启动校准，请检查两根鼓棒连接与设备状态" }
        if (type == 0x78 && result != 0) { calibrationPending = false; controlMessage = "无法读取校准状态，请检查设备" }
        if (type == 0x7B && result != 0) { lightPending = false; lightMessage = "读取灯光失败，请点击重新读取" }
        if (type == 0x7A) { lightPending = result == 0; lightMessage = if (result == 0) "正在读回灯光设置…" else "灯光设置失败，请重新读取后重试" }
    }
    fun readCalibration(data: ByteArray) {
        val values = data.map { it.toInt() and 255 }
        if (values.size != 12 || listOf(0, 1, 2, 3, 8, 9).any { values[it] > 3 } || values[6] !in 0..4 || values[7] !in 0..4) return
        calibrationStatusReceived = true
        attemptId = values[10] or (values[11] shl 8)
        if (calibrationPending && attemptId != requestedAttempt) calibrationPending = false
        calibrationState = values[6]; calibrationReason = values[7]
        sticks.forEachIndexed { i, stick ->
            stick.inserted = values[0] and (1 shl i) != 0
            stick.online = values[1] and (1 shl i) != 0
            stick.calibrated = values[2] and (1 shl i) != 0
            stick.calibrating = values[3] and (1 shl i) != 0
            stick.poseFault = values[8] and (1 shl i) != 0
            stick.overflow = values[9] and (1 shl i) != 0
            stick.progress = if (stick.calibrating) values[4 + i] * 100 / 255 else if (stick.calibrated) 100 else 0
        }
        if (calibrationState == 3 && values[0] == 3 && values[1] == 3 && values[2] == 3 && values[8] == 0 && values[3] == 0) controlMessage = "两根鼓棒已就绪"
        else if (calibrationState == 4) controlMessage = "需要重新校准：" + listOf("未知原因", "拔出或通信掉线", "静止采集超时", "姿态故障", "采样溢出")[calibrationReason]
    }
    fun readLight(data: ByteArray) {
        val config = DrumLightConfig.decode(data) ?: return
        light = config; lightPending = false; lightMessage = "已读回设备灯光设置"
    }
    fun applyLight(config: DrumLightConfig) {
        if (demo) { light = config; return }
        if (!lightSupported || lightPending) return
        lightPending = true; protocol?.setDrumLight(config.encode())
    }
    fun refreshLight() { if (!demo && lightSupported) protocol?.readDrumLight() }

    fun configure(isDemo: Boolean, isSupported: Boolean, session: HallPadSession) {
        demo = isDemo; supported = isSupported; protocol = session
        effectSupported = isDemo || (isSupported && session.has(25))
        effectPending = false; effectSetAccepted = false; effectDirty = false; sentEffect = null; effectMessage = ""; effectConfig = if (isDemo) DrumEffectConfig() else if (!isSupported) lastDeviceEffect else null; effectDraft = effectConfig
        if (!isDemo && effectSupported) session.readDrumEffect()
        colorSupported = isDemo || (isSupported && session.has(24))
        colorPending = false; colorMessage = ""; color = if (isDemo) DrumColorConfig() else null
        if (!isDemo && colorSupported) session.readDrumColor()
        calibrationSupported = !isDemo && isSupported && session.has(22)
        lightSupported = isDemo || (isSupported && session.has(23))
        calibrationStatusReceived = false
        calibrationState = -1; attemptId = -1; requestedAttempt = -1; calibrationPending = false; lightPending = false; controlMessage = ""; lightMessage = ""
        light = if (isDemo) DrumLightConfig() else null
        if (calibrationSupported) session.readDrumCalibration()
        if (!isDemo && lightSupported) session.readDrumLight()
        sticks.forEach { it.loaded = isDemo; it.online = false; it.inserted = false; it.calibrated = false; it.calibrating = false; it.poseFault = false; it.overflow = false; it.progress = 0 }
        if (!isDemo && isSupported) { session.readDrum(0); session.readDrum(1) }
    }
    fun readConfig(data: ByteArray) {
        if (data.size != 9) return
        val index = data[0].toInt() and 255
        if (index !in 0..1) return
        val b = ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN)
        val ids = (1..3).map { data[it].toInt() and 255 }
        val velocity = data[4].toInt() and 255
        val threshold = b.getShort(5).toInt() and 65535
        val cooldown = b.getShort(7).toInt() and 65535
        if (ids.any { it !in 0..5 && it != 255 } || velocity !in 0..127 || threshold !in 30..1600 || cooldown !in 20..1000) return
        val stick = sticks[index]
        ids.forEachIndexed { i, id -> stick.voices[i] = if (id == 255) "无" else drumVoices[id] }
        stick.velocity = velocity; stick.threshold = threshold; stick.cooldown = cooldown; stick.loaded = true
    }
    fun receiveHit(data: ByteArray) {
        if (data.size != 12 || demo) return
        val index = data[4].toInt() and 255; val direction = data[5].toInt() and 255; val velocity = data[6].toInt() and 255; val source = data[7].toInt() and 255
        if (index !in 0..1 || direction !in 0..2 || velocity !in 1..127 || source !in 0..1) return
        val stick = sticks[index]; stick.direction = direction; stick.hits++; val pad = index * 3 + direction; padHits[pad] = (padHits[pad] ?: 0) + 1
    }
    fun receiveStatus(flags: Int) {
        if (demo) return
        sticks.forEachIndexed { i, stick -> stick.online = flags and (1 shl (8 + i)) != 0; if (!calibrationStatusReceived) stick.calibrated = flags and (1 shl (10 + i)) != 0; stick.inserted = flags and (1 shl (12 + i)) != 0; if (!stick.inserted) { stick.calibrated = false; stick.calibrating = false; stick.progress = 0 } }
    }
    fun strike(stick: DrumstickPreviewState, direction: Int) {
        if (direction !in 0..2 || stick.voices[direction] == "无" || stick.velocity == 0) return
        if (demo) { stick.direction = direction; stick.hits++; val pad = stick.index * 3 + direction; padHits[pad] = (padHits[pad] ?: 0) + 1 }
        else if (supported && stick.loaded) protocol?.strikeDrum(stick.index, direction, stick.velocity)
    }
    fun apply(stick: DrumstickPreviewState, voices: List<String>, velocity: Int, threshold: Int, cooldown: Int) {
        if (demo) { voices.forEachIndexed { index, voice -> stick.voices[index] = voice }; stick.velocity = velocity; stick.threshold = threshold; stick.cooldown = cooldown; save(stick); return }
        if (!supported || !stick.loaded) return
        val b = ByteBuffer.allocate(9).order(ByteOrder.LITTLE_ENDIAN).put(stick.index.toByte())
        voices.forEach { b.put((if (it == "无") 255 else drumVoices.indexOf(it)).toByte()) }
        b.put(velocity.toByte()).putShort(threshold.toShort()).putShort(cooldown.toShort())
        protocol?.setDrum(b.array())
    }
    fun save(stick: DrumstickPreviewState) {
        val editor = preferences.edit().putInt("velocity_${stick.index}", stick.velocity).putInt("threshold_${stick.index}", stick.threshold).putInt("cooldown_${stick.index}", stick.cooldown)
        stick.voices.forEachIndexed { direction, voice -> editor.putString("voice_${stick.index}_$direction", voice) }
        editor.apply()
    }
}

internal class DrumstickPreviewState(val index: Int, voices: List<String>, velocity: Int) {
    val voices = voices.toMutableStateList()
    var velocity by mutableIntStateOf(velocity)
    var hits by mutableIntStateOf(0)
    var direction by mutableIntStateOf(-1)
    var threshold by mutableIntStateOf(160)
    var cooldown by mutableIntStateOf(130)
    var loaded by mutableStateOf(false)
    var online by mutableStateOf(false)
    var poseFault by mutableStateOf(false)
    var overflow by mutableStateOf(false)
    var calibrated by mutableStateOf(false)
    var inserted by mutableStateOf(false)
    var calibrating by mutableStateOf(false)
    var progress by mutableIntStateOf(0)
}

private val drumVoices = listOf("军鼓", "底鼓", "踩镲", "通鼓", "吊镲", "叮叮镲", "无")
private val drumDirections = listOf("侧击", "下击", "上击")

@Composable
internal fun DrumsticksPreview(state: DrumsticksPreviewState, modifier: Modifier = Modifier, stacked: Boolean = false) {
    var editing by remember { mutableStateOf<DrumstickPreviewState?>(null) }
    LaunchedEffect(state, state.calibrationSupported) {
        if (state.calibrationSupported) while (true) { state.refreshCalibration(); delay(250) }
    }
    LaunchedEffect(state.demo, state.supported) { if (!state.demo && !state.supported) editing = null }
    val padBounds = remember { mutableMapOf<Int, Rect>() }
    val coordinates = remember { arrayOfNulls<LayoutCoordinates>(1) }
    val touchArea = modifier.onGloballyPositioned { coordinates[0] = it }.pointerInput(state) {
        val tracker = DrumTouchTracker()
        try {
            awaitPointerEventScope {
                while (true) {
                    val event = awaitPointerEvent(PointerEventPass.Initial)
                    for (change in event.changes) {
                        val root = coordinates[0]?.takeIf { it.isAttached } ?: continue
                        val point = root.localToRoot(change.position)
                        val pad = padBounds.entries.firstOrNull { it.value.contains(point) && state.sticks[it.key / 3].loaded }?.key
                        val owned = tracker.owns(change.id.value)
                        val hit = tracker.update(change.id.value, change.pressed, change.previousPressed, pad)
                        if (owned || tracker.owns(change.id.value)) change.consume()
                        if (hit != null) state.strike(state.sticks[hit / 3], hit % 3)
                    }
                }
            }
        } finally { tracker.clear() }
    }
    if (stacked) {
        Column(touchArea, verticalArrangement = Arrangement.spacedBy(4.dp)) {
            state.sticks.forEach { stick -> DrumstickPreviewTile(state, stick, Modifier.fillMaxWidth().weight(1f),
                { editing = stick }, { direction, bounds -> padBounds[stick.index * 3 + direction] = bounds }) }
        }
    } else {
        Row(touchArea, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            state.sticks.forEach { stick -> DrumstickPreviewTile(state, stick, Modifier.weight(1f).fillMaxHeight(),
                { editing = stick }, { direction, bounds -> padBounds[stick.index * 3 + direction] = bounds }) }
        }
    }
    editing?.let { stick -> DrumstickPreviewSettings(state, stick, { editing = null }) }
}

@Composable
private fun DrumstickPreviewTile(state: DrumsticksPreviewState, stick: DrumstickPreviewState, modifier: Modifier, onSettings: () -> Unit, onPadBounds: (Int, Rect) -> Unit) {
    val palette = MaterialTheme.colorScheme
    Column(modifier.background(palette.surfaceContainerHigh, RoundedCornerShape(16.dp)).padding(start = 6.dp, end = 6.dp, top = 3.dp, bottom = 8.dp)) {
        Row(Modifier.fillMaxWidth().height(24.dp).padding(start = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(if (stick.index == 0) "左棒" else "右棒", color = palette.onSurface, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
            Text(if (state.demo) " · 演示" else if (!state.supported) " · 未连接" else if (!stick.inserted) " · 未插入" else if (!stick.online) { if (stick.calibrated) " · 通信恢复中（已校准）" else " · 通信恢复中" } else if (stick.calibrating) " · 校准中" else if (stick.poseFault) " · 姿态故障" else if (!stick.calibrated) " · 未校准" else " · 已就绪", modifier = Modifier.weight(1f), color = palette.onSurfaceVariant, fontSize = 10.sp, maxLines = 1)
            Box(Modifier.size(24.dp).clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, enabled = stick.loaded, onClick = onSettings), contentAlignment = Alignment.Center) {
                Icon(painterResource(R.drawable.ic_key_settings), contentDescription = if (stick.index == 0) "设置左鼓棒" else "设置右鼓棒", tint = if (stick.loaded) palette.primary else palette.onSurface.copy(alpha = 0.38f), modifier = Modifier.size(16.dp))
            }
        }
        Row(Modifier.fillMaxWidth().weight(1f), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            drumDirections.forEachIndexed { direction, label ->
                var active by remember(stick.index, direction) { mutableStateOf(false) }
                val hits = state.padHits[stick.index * 3 + direction] ?: 0
                LaunchedEffect(hits) { if (hits > 0) { active = true; delay(180); active = false } }
                val background by animateColorAsState(if (active) palette.primary else palette.background.copy(alpha = 0.6f), label = "directionHit")
                val foreground = if (active) palette.onPrimary else palette.onSurface
                Column(Modifier.weight(1f).fillMaxHeight().background(background, RoundedCornerShape(10.dp)).onGloballyPositioned { onPadBounds(direction, it.boundsInRoot()) }.semantics {
                    role = Role.Button
                    if (stick.loaded) onClick { state.strike(stick, direction); true }
                }, verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(label, color = foreground, fontSize = 9.sp, lineHeight = 11.sp, maxLines = 1, softWrap = false)
                    Text(stick.voices[direction], color = foreground, fontSize = 10.sp, lineHeight = 12.sp, fontWeight = FontWeight.Medium, maxLines = 1, softWrap = false)
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun DrumstickPreviewSettings(state: DrumsticksPreviewState, stick: DrumstickPreviewState, onClose: () -> Unit) {
    val voices = remember(stick) { stick.voices.toMutableStateList() }
    var direction by remember(stick) { mutableIntStateOf(0) }
    var velocity by remember(stick) { mutableFloatStateOf(drumVelocityPercent(stick.velocity).toFloat()) }
    var threshold by remember(stick) { mutableFloatStateOf(stick.threshold.toFloat()) }
    var cooldown by remember(stick) { mutableFloatStateOf(stick.cooldown.coerceIn(20, 500).toFloat()) }
    val palette = MaterialTheme.colorScheme
    var showCalibration by remember { mutableStateOf(false) }
    var calibrationLocked by remember { mutableStateOf(false) }
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true,
        confirmValueChange = { !calibrationLocked })
    val scope = rememberCoroutineScope()
    val focus = LocalFocusManager.current
    var closing by remember { mutableStateOf(false) }
    val close: () -> Unit = {
        if (!closing && !calibrationLocked) {
            closing = true; focus.clearFocus()
            scope.launch { try { sheetState.hide(); onClose() } finally { closing = false } }
        }
    }
    val compact = LocalConfiguration.current.screenHeightDp < 500
    ModalBottomSheet(onDismissRequest = close, sheetState = sheetState,
        containerColor = palette.surface, contentColor = palette.onSurface,
        dragHandle = { Box(Modifier.fillMaxWidth().padding(vertical = if (compact) 8.dp else 16.dp), contentAlignment = Alignment.Center) {
            Box(Modifier.size(32.dp, 4.dp).background(palette.onSurfaceVariant.copy(alpha = 0.4f), RoundedCornerShape(2.dp)))
        } }) {
        Column(Modifier.fillMaxWidth().widthIn(max = 840.dp).align(Alignment.CenterHorizontally).padding(horizontal = 24.dp).padding(bottom = 12.dp), verticalArrangement = Arrangement.spacedBy(if (compact) 4.dp else 10.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                Text(if (stick.index == 0) "左鼓棒设置" else "右鼓棒设置", modifier = Modifier.weight(1f), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                TextButton(onClick = { focus.clearFocus(); showCalibration = true }) { Text("校准") }
                TextButton(onClick = {
                    val defaults = if (stick.index == 0) listOf("军鼓", "踩镲", "通鼓") else listOf("通鼓", "吊镲", "叮叮镲")
                    defaults.forEachIndexed { i, voice -> voices[i] = voice }
                    velocity = 100f; threshold = 160f; cooldown = 130f
                }) { Text("恢复默认") }
            }
            if (compact) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(20.dp)) {
                    Column(Modifier.weight(1f)) { DrumVoiceChoices(voices, direction) { direction = it } }
                    Column(Modifier.weight(1f)) { DrumResponseSliders(velocity, threshold, cooldown, { velocity = it }, { threshold = it }, { cooldown = it }) }
                }
            } else {
                DrumVoiceChoices(voices, direction) { direction = it }
                DrumResponseSliders(velocity, threshold, cooldown, { velocity = it }, { threshold = it }, { cooldown = it })
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedButton(enabled = !closing, onClick = close, modifier = Modifier.weight(1f)) { Text("取消") }
                Button(enabled = !closing && stick.loaded && (state.demo || state.supported), onClick = {
                    focus.clearFocus()
                    state.apply(stick, voices.toList(), drumVelocityWire(velocity.toInt()), threshold.toInt(), cooldown.toInt()); close()
                }, modifier = Modifier.weight(1f)) { Text("应用设置") }
            }
        }
    }
    if (showCalibration) DrumCalibrationDialog(state,
        onBusyChange = { calibrationLocked = it },
        onClose = { calibrationLocked = false; showCalibration = false })
}

@Composable
private fun DrumVoiceChoices(voices: MutableList<String>, direction: Int, onDirection: (Int) -> Unit) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        drumDirections.forEachIndexed { index, label ->
            HallPadChoiceChip(selected = direction == index, onClick = { onDirection(index) }, label = { Text(label) }, modifier = Modifier.weight(1f))
        }
    }
    // The summary occupies one line instead of repeating all directions above the selector.
    Text("${drumDirections[direction]} · ${voices[direction]}", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
    listOf(listOf("军鼓", "底鼓", "踩镲", "通鼓"), listOf("吊镲", "叮叮镲", "无")).forEach { row ->
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            row.forEach { item -> HallPadChoiceChip(selected = voices[direction] == item,
                onClick = { voices[direction] = item }, label = { Text(item, fontSize = 12.sp, maxLines = 1, softWrap = false) }, modifier = Modifier.weight(1f)) }
        }
    }
}

@Composable
private fun DrumResponseSliders(velocity: Float, threshold: Float, cooldown: Float,
    onVelocity: (Float) -> Unit, onThreshold: (Float) -> Unit, onCooldown: (Float) -> Unit) {
    SoundSlider("力度系数", "${velocity.toInt()}%", velocity, 0f..100f, displayScale = 1f, onChange = onVelocity)
    SoundSlider("触发阈值", "${threshold.toInt()}", threshold, 30f..1600f, displayScale = 1f, onChange = onThreshold)
    SoundSlider("间隔", "${cooldown.toInt()} ms", cooldown, 20f..500f, displayScale = 1f, onChange = onCooldown)
    Text("阈值越低越灵敏", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
}

internal fun drumVelocityWire(percent: Int): Int = (percent.coerceIn(0, 100) * 127 + 50) / 100
internal fun drumVelocityPercent(wire: Int): Int = (wire.coerceIn(0, 127) * 100 + 63) / 127
