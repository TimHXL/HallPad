package com.timhxl.hallbeat

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.roundToInt

internal data class DrumLightConfig(
    val enabled: Boolean = true, val brightness: Int = 10,
    val attackMs: Int = 40, val decayMs: Int = 1200
) {
    fun encode(): ByteArray {
        require(brightness in 0..100 && attackMs in 1..1000 && decayMs in 0..5000)
        return ByteBuffer.allocate(6).order(ByteOrder.LITTLE_ENDIAN)
            .put(if (enabled) 1.toByte() else 0.toByte()).put(brightness.toByte())
            .putShort(attackMs.toShort()).putShort(decayMs.toShort()).array()
    }
    companion object {
        fun decode(data: ByteArray): DrumLightConfig? {
            if (data.size != 6) return null
            val b = ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN)
            val enabled = data[0].toInt() and 255
            val brightness = data[1].toInt() and 255
            val attack = b.getShort(2).toInt() and 65535
            val decay = b.getShort(4).toInt() and 65535
            if (enabled !in 0..1 || brightness !in 0..100 || attack !in 1..1000 || decay !in 0..5000) return null
            return DrumLightConfig(enabled == 1, brightness, attack, decay)
        }
    }
}

@Composable
internal fun DrumLightingSettings(state: DrumsticksPreviewState) {
    LaunchedEffect(state.demo, state.effectSupported) { state.refreshEffect() }
    val actual = state.effectConfig
    val draft = state.effectDraft ?: actual ?: DrumEffectConfig()
    LaunchedEffect(state.effectDraft) { delay(150); state.flushEffect() }
    val editable = state.effectSupported && actual != null
    if ((state.effectMessage.contains("失败") || state.effectMessage.contains("不一致"))) Text(state.effectMessage, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
    val palette = MaterialTheme.colorScheme
    Row(Modifier.fillMaxWidth(), verticalAlignment = androidx.compose.ui.Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
        Text("鼓棒灯光", style = MaterialTheme.typography.titleLarge)
        TextButton(enabled = editable, onClick = { state.stageEffect(DrumEffectConfig()) }) { Text("恢复默认") }
    }
    Card(colors = CardDefaults.cardColors(containerColor = palette.surfaceContainerHigh)) {
        Column(Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
            listOf("水波" to "敲击触发，向前扩散", "常亮" to "全部灯持续点亮", "关闭" to "关闭鼓棒灯光").forEachIndexed { index, mode ->
                Surface(enabled = editable, onClick = { state.stageEffect(draft.copy(mode = index)) }, color = if (draft.mode == index) palette.primaryContainer else Color.Transparent) {
                    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                        RadioButton(selected = draft.mode == index, enabled = editable, onClick = null)
                        Column(Modifier.weight(1f)) {
                            Text(mode.first, color = palette.onSurface, style = MaterialTheme.typography.titleMedium)
                            Text(mode.second, color = palette.onSurfaceVariant, style = MaterialTheme.typography.bodySmall)
                        }
                    }
                }
                if (index < 2) HorizontalDivider(Modifier.padding(horizontal = 20.dp), color = palette.outlineVariant.copy(alpha = 0.4f))
            }
        }
    }
    if (draft.mode != 2) Card(Modifier.fillMaxWidth(), colors = CardDefaults.cardColors(containerColor = palette.surfaceContainerHigh)) {
        Column(Modifier.fillMaxWidth().padding(20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            SettingSlider("亮度", "${draft.brightness}%", draft.brightness / 100f, 0f..1f, editable) { state.stageEffect(draft.copy(brightness = (it * 100).roundToInt())) }
        }
    }
    if (draft.mode == 0) SettingsCard("水波参数") {
        DrumEffectValueSlider("速度", "${draft.speed / 1000} 灯/秒", draft.speed / 1000f, 40f..200f, editable, true) {
            state.stageEffect(draft.copy(speed = it.roundToInt() * 1000)); state.flushEffect()
        }
        DrumEffectValueSlider("衰减", "${"%.1f".format(draft.decayMs / 1000f)} s", draft.decayMs / 1000f, 0.2f..5f, editable, false) {
            state.stageEffect(draft.copy(decayMs = (it * 1000).roundToInt())); state.flushEffect()
        }
        Text("100 灯/秒以上需 StateLightV5 或更新固件", style = MaterialTheme.typography.bodySmall)

    }
    if (draft.mode == 1) SettingsCard("常亮颜色") {
        DrumRgbEditor(draft.red, draft.green, draft.blue, editable) { red, green, blue -> state.stageEffect(draft.copy(red = red, green = green, blue = blue)) }
    }
}

@Composable
internal fun DrumCalibrationPanel(state: DrumsticksPreviewState) {
    if (!state.calibrationSupported) {
        Text("鼓棒校准", style = MaterialTheme.typography.titleMedium)
        Text(if (state.demo) "演示模式不执行硬件校准" else if (state.supported) "当前固件未声明手动校准能力" else "请先连接支持校准的设备", style = MaterialTheme.typography.bodySmall)
        Button(onClick = {}, enabled = false, modifier = Modifier.fillMaxWidth()) { Text("校准两根鼓棒") }
        return
    }
    LaunchedEffect(state, state.calibrationSupported) {
        while (true) { state.refreshCalibration(); delay(250) }
    }
    Text("鼓棒校准", style = MaterialTheme.typography.titleMedium)
    Text(when (state.calibrationState) {
        0 -> "尚未校准，请连接两根鼓棒并保持静止"
        1 -> "等待两根鼓棒连接并进入设备鼓棒页"
        2 -> "正在采集静止样本，请勿移动鼓棒"
        3 -> if (state.sticks.all { it.inserted && it.online && it.calibrated && !it.poseFault && !it.calibrating }) "两根鼓棒已就绪" else "连接状态已变化，请检查鼓棒"
        4 -> state.controlMessage
        else -> "正在读取校准状态…"
    }, style = MaterialTheme.typography.bodyMedium)
    state.sticks.forEach { stick ->
        val label = if (stick.index == 0) "左棒" else "右棒"
        val status = when {
            !stick.inserted -> "未插入"
            !stick.online -> if (stick.calibrated) "通信恢复中 · 校准已保留" else "通信恢复中"
            stick.calibrating -> "校准中 ${stick.progress}%"
            stick.poseFault -> "姿态故障"
            stick.calibrated -> "已就绪"
            else -> "未校准"
        }
        Text("$label · $status", style = MaterialTheme.typography.bodySmall)
        if (stick.calibrating) LinearProgressIndicator(progress = { stick.progress / 100f }, modifier = Modifier.fillMaxWidth())
    }
    Button(onClick = state::startCalibration,
        enabled = !state.calibrationPending && state.calibrationState in listOf(0, 3, 4) && state.sticks.all { it.inserted && it.online },
        modifier = Modifier.fillMaxWidth()) { Text(if (state.calibrationPending) "正在请求…" else if (state.calibrationState == 2) "正在校准…" else "校准两根鼓棒") }
    if (state.calibrationPending || state.controlMessage.startsWith("无法")) Text(state.controlMessage, style = MaterialTheme.typography.bodySmall)
}

@Composable
internal fun DrumSettingsDialog(state: DrumsticksPreviewState, onClose: () -> Unit) {
    var editing by remember { mutableStateOf<DrumstickPreviewState?>(null) }
    var lighting by remember { mutableStateOf(false) }
    if (lighting) {
        AlertDialog(onDismissRequest = { lighting = false }, title = { Text("鼓棒灯光与配色") }, text = {
            Column(Modifier.heightIn(max = 480.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) { DrumLightingSettings(state) }
        }, confirmButton = { TextButton(onClick = { lighting = false }) { Text("返回鼓棒设置") } })
        return
    }
    // Only one modal at a time; returning from a stick editor retains this overview.
    if (editing != null) {
        DrumstickPreviewSettings(state, editing!!) { editing = null }
        return
    }
    AlertDialog(onDismissRequest = onClose, title = { Text("鼓棒设置") }, text = {
        Column(Modifier.heightIn(max = 480.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            if (!state.demo && !state.supported) Text("请连接支持鼓棒的设备")
            OutlinedButton(onClick = { lighting = true }, modifier = Modifier.fillMaxWidth()) { Text("灯光设置 · 自定义 RGB") }
            DrumCalibrationPanel(state)
            state.sticks.forEach { stick ->
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(if (stick.index == 0) "左鼓棒" else "右鼓棒", style = MaterialTheme.typography.titleMedium)
                        Text("侧击：${stick.voices[0]}\n下击：${stick.voices[1]}\n上击：${stick.voices[2]}", style = MaterialTheme.typography.bodyMedium)
                        Text("力度 ${drumVelocityPercent(stick.velocity)}% · 间隔 ${stick.cooldown} ms", style = MaterialTheme.typography.bodySmall)
                        OutlinedButton(enabled = stick.loaded, onClick = { editing = stick }) { Text("设置方向与响应") }
                    }
                }
            }
        }
    }, confirmButton = { TextButton(onClick = onClose) { Text("完成") } })
}


/** Independent color command: the original six-byte light envelope stays compatible. */
internal data class DrumColorConfig(val mode: Int = 0, val red: Int = 32, val green: Int = 112, val blue: Int = 255) {
    fun encode(): ByteArray {
        require(mode in 0..1 && red in 0..255 && green in 0..255 && blue in 0..255)
        return byteArrayOf(mode.toByte(), red.toByte(), green.toByte(), blue.toByte())
    }
    companion object {
        fun decode(data: ByteArray): DrumColorConfig? {
            if (data.size != 4) return null
            val values = data.map { it.toInt() and 255 }
            if (values[0] !in 0..1) return null
            return DrumColorConfig(values[0], values[1], values[2], values[3])
        }
    }
}

@Composable
private fun DrumRgbEditor(red: Int, green: Int, blue: Int, enabled: Boolean, onChange: (Int, Int, Int) -> Unit) {
    RgbHexSettings((red shl 16) or (green shl 8) or blue, enabled) { rgb ->
        onChange((rgb shr 16) and 255, (rgb shr 8) and 255, rgb and 255)
    }
}

internal data class DrumEffectConfig(val mode: Int = 0, val brightness: Int = 10, val speed: Int = 80000,
    val decayMs: Int = 1200, val red: Int = 32, val green: Int = 112, val blue: Int = 255) {
    fun encode(): ByteArray {
        require(mode in 0..2 && brightness in 0..100 && speed in 40000..200000 && decayMs in 200..5000)
        require(red in 0..255 && green in 0..255 && blue in 0..255)
        return ByteBuffer.allocate(11).order(ByteOrder.LITTLE_ENDIAN).put(mode.toByte()).put(brightness.toByte())
            .putInt(speed).putShort(decayMs.toShort()).put(red.toByte()).put(green.toByte()).put(blue.toByte()).array()
    }
    companion object {
        fun decode(data: ByteArray): DrumEffectConfig? {
            if (data.size != 11 && data.size != 9) return null
            val b = ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN)
            val wide = data.size == 11
            val config = DrumEffectConfig(data[0].toInt() and 255, data[1].toInt() and 255,
                if (wide) b.getInt(2) else b.getShort(2).toInt() and 65535,
                b.getShort(if (wide) 6 else 4).toInt() and 65535,
                data[if (wide) 8 else 6].toInt() and 255,
                data[if (wide) 9 else 7].toInt() and 255,
                data[if (wide) 10 else 8].toInt() and 255)
            return config.takeIf { it.mode in 0..2 && it.brightness in 0..100 && it.speed in 40000..200000 && it.decayMs in 200..5000 }
        }
    }
}


/** Confirmation and status share one modal; ACK acceptance is not calibration success. */
@Composable
internal fun DrumCalibrationDialog(state: DrumsticksPreviewState, onBusyChange: (Boolean) -> Unit, onClose: () -> Unit) {
    var submitted by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var result by remember { mutableStateOf("") }
    SideEffect { onBusyChange(busy) }
    LaunchedEffect(state, submitted) {
        if (!submitted) {
            state.refreshCalibration()
            return@LaunchedEffect
        }
        val previousAttempt = state.attemptId
        state.startCalibration()
        val started = android.os.SystemClock.elapsedRealtime()
        while (busy) {
            if (!state.supported || !state.calibrationSupported) {
                result = "设备已断开，无法继续读取校准状态"; busy = false
            } else if (state.controlMessage.startsWith("无法")) {
                result = state.controlMessage; busy = false
            } else if (state.attemptId != previousAttempt && state.calibrationState == 4) {
                result = state.controlMessage; busy = false
            } else if (state.attemptId != previousAttempt && state.calibrationState == 3 &&
                state.sticks.all { it.inserted && it.online && it.calibrated && !it.poseFault && !it.calibrating }) {
                result = "校准成功，两根鼓棒已就绪"; busy = false
            } else if (android.os.SystemClock.elapsedRealtime() - started > 15000 &&
                state.calibrationState !in 1..2) {
                result = "未能确认校准结果，请检查连接后重试"; busy = false
            }
            if (busy) { state.refreshCalibration(); delay(250) }
        }
    }
    AlertDialog(
        onDismissRequest = { if (!busy) onClose() },
        properties = androidx.compose.ui.window.DialogProperties(dismissOnBackPress = !busy, dismissOnClickOutside = !busy),
        title = { Text(if (busy) "校准中" else "鼓棒校准") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("将同时校准左右两根鼓棒。请连接两根鼓棒，保持静止，直到校准完成。")
                if (busy) {
                    Text("校准中，请勿移动鼓棒…")
                    state.sticks.forEach { stick ->
                        Text("${if (stick.index == 0) "左棒" else "右棒"} · ${when { !stick.inserted -> "未插入"; !stick.online -> "通信恢复中"; stick.calibrating -> "校准中 ${stick.progress}%"; stick.poseFault -> "姿态故障"; stick.calibrated && !state.calibrationPending -> "已完成"; else -> "等待校准" }}")
                    }
                    LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                } else if (result.isNotEmpty()) Text(result)
                else if (!state.calibrationSupported) Text(if (state.demo) "演示模式不执行硬件校准" else "请连接支持手动校准的设备")
                else if (state.sticks.any { !it.inserted || !it.online }) Text("请先连接两根鼓棒并等待通信就绪")
            }
        },
        confirmButton = {
            if (!busy) {
                if (result.isNotEmpty()) TextButton(onClick = onClose) { Text("关闭") }
                else TextButton(enabled = state.calibrationSupported && !state.calibrationPending &&
                    state.calibrationState in listOf(0, 3, 4) && state.sticks.all { it.inserted && it.online },
                    onClick = { busy = true; submitted = true }) { Text("确认") }
            }
        },
        dismissButton = { if (!busy && result.isEmpty()) TextButton(onClick = onClose) { Text("取消") } }
    )
}
