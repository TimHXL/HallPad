package com.timhxl.hallbeat

import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.TextStyle
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.text.input.rememberTextFieldState
import androidx.compose.foundation.text.input.InputTransformation
import androidx.compose.foundation.text.input.TextFieldLineLimits
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.animation.animateContentSize
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.dp
import org.json.JSONObject
import kotlin.math.*

/** 配置可保存；实时摇杆位置和踏板状态只保留在本次会话。 */
@Stable
internal class PerformanceSettings {
    var onParameter: ((Int, Int) -> Unit)? = null
    fun send(id: Int, value: Int) { onParameter?.invoke(id, value) }
    fun sendRgb() { send(0x62, (red shl 16) or (green shl 8) or blue) }
    var audioSource by mutableStateOf("FPGA")
    var fpgaAudioEnabled by mutableStateOf(true)
    var auxAudioEnabled by mutableStateOf(false)
    var audioMixAvailable by mutableStateOf(false)
    var red by mutableIntStateOf(0)
    var green by mutableIntStateOf(220)
    var blue by mutableIntStateOf(120)
    val lightColor: Color get() = Color(red, green, blue)
    var remoteBendRangeCent by mutableIntStateOf(1200)
    var joystickEnabled by mutableStateOf(true)
    var joystickSensitivity by mutableFloatStateOf(0.5f)
    var reverbEnabled by mutableStateOf(false)
    var reverbAmount by mutableFloatStateOf(0.25f)
    var rippleSpeed by mutableFloatStateOf(5f)
    var rippleDecay by mutableFloatStateOf(1.2f)
    var randomColor by mutableStateOf(true)
    var hue by mutableFloatStateOf(145f)
    var x by mutableFloatStateOf(0f)
    var y by mutableFloatStateOf(0f)
    fun center() { x = 0f; y = 0f }
    fun encode(): JSONObject = JSONObject().apply {
        put("audioSource", audioSource); put("red", red); put("green", green); put("blue", blue)
        put("joystickEnabled", joystickEnabled); put("joystickSensitivity", joystickSensitivity.toDouble())
        put("rippleSpeed", rippleSpeed.toDouble()); put("rippleDecay", rippleDecay.toDouble())
        put("randomColor", randomColor); put("hue", hue.toDouble())
        put("reverbEnabled", reverbEnabled); put("reverbAmount", reverbAmount.toDouble())
    }
    fun load(json: JSONObject?) {
        fun number(key: String, default: Double, range: ClosedFloatingPointRange<Float>): Float = (json?.optDouble(key, default) ?: default).let { if (it.isFinite()) it.toFloat().coerceIn(range) else default.toFloat() }
        audioSource = json?.optString("audioSource", "FPGA")?.takeIf { it in listOf("FPGA", "AUX") } ?: "FPGA"
        // 旧版色相转换为 RGB，已有灯光配色可继续使用。
        val oldColor = Color.hsv(number("hue", 145.0, 0f..360f), 0.85f, 1f)
        red = json?.optInt("red", (oldColor.red * 255).roundToInt())?.coerceIn(0, 255) ?: 0
        green = json?.optInt("green", (oldColor.green * 255).roundToInt())?.coerceIn(0, 255) ?: 220
        blue = json?.optInt("blue", (oldColor.blue * 255).roundToInt())?.coerceIn(0, 255) ?: 120
        joystickEnabled = json?.optBoolean("joystickEnabled", true) ?: true
        joystickSensitivity = number("joystickSensitivity", 0.5, 0f..1f)
        reverbEnabled = json?.optBoolean("reverbEnabled", false) ?: false
        reverbAmount = number("reverbAmount", 0.25, 0f..1f)
        rippleSpeed = number("rippleSpeed", 5.0, 0.5f..30f); rippleDecay = number("rippleDecay", 1.2, 0.2f..5f)
        randomColor = json?.optBoolean("randomColor", true) ?: true; hue = number("hue", 145.0, 0f..360f)
        center()
    }
}

@Composable
internal fun JoystickCard(settings: PerformanceSettings) {
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerHigh)) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) { Text("摇杆", style = MaterialTheme.typography.titleMedium); Text("上下弯音 / 左右调制", color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.labelSmall) }
            JoystickPad(settings, Modifier.fillMaxWidth().height(200.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text("滑音 ${"%+.1f".format(if (settings.joystickEnabled) settings.y * abs(settings.y) * (settings.remoteBendRangeCent / 100f) * settings.joystickSensitivity else 0f)} 半音")
                Text("调制 " + (if (settings.joystickEnabled) (joystickModulation(settings.x, settings.joystickSensitivity) * 100 / 127) else 0) + "%")
            }
            Spacer(Modifier.height(8.dp))
        }
    }
}

@Composable
internal fun JoystickPad(settings: PerformanceSettings, modifier: Modifier = Modifier) {
    val palette = MaterialTheme.colorScheme
    DisposableEffect(settings) { onDispose { settings.center() } }
    Canvas(modifier.pointerInput(settings.joystickEnabled) {
        try {
            if (!settings.joystickEnabled) return@pointerInput
            awaitEachGesture {
                val down = awaitFirstDown(requireUnconsumed = false)
                val pointer = down.id
                val center = Offset(size.width / 2f, size.height / 2f)
                val outerRadius = min(size.width, size.height) * 0.46f
                val radius = (outerRadius - min(20.dp.toPx(), outerRadius * 0.42f)).coerceAtLeast(1f)
                fun update(position: Offset) {
                    val offset = (position - center) / radius
                    val length = offset.getDistance()
                    val scale = if (length > 1f) 1f / length else 1f
                    // 控制方向顺时针旋转90度，触点绘制使用逆变换保持跟手
                    settings.x = -offset.y * scale
                    settings.y = -offset.x * scale
                }
                update(down.position); down.consume()
                do {
                    val event = awaitPointerEvent()
                    val change = event.changes.firstOrNull { it.id == pointer }
                    if (change == null || !change.pressed) break
                    update(change.position); change.consume()
                } while (true)
                settings.center()
            }
        } finally { settings.center() }
    }) {
        val radius = min(size.width, size.height) * 0.46f
        drawCircle(palette.primary.copy(alpha = 0.08f), radius)
        drawCircle(palette.outlineVariant, radius, style = Stroke(1.dp.toPx()))
        drawLine(palette.outlineVariant, center - Offset(radius, 0f), center + Offset(radius, 0f))
        drawLine(palette.outlineVariant, center - Offset(0f, radius), center + Offset(0f, radius))
        // 反向映射控制坐标，触点仍位于手指实际位置
        val thumbRadius = min(20.dp.toPx(), radius * 0.42f)
        val position = center + Offset(-settings.y, -settings.x) * (radius - thumbRadius)
        drawCircle(if (settings.joystickEnabled) palette.primary else palette.onSurface.copy(alpha = 0.3f), thumbRadius, position)
    }
}

@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
internal fun PerformanceSettingsCards(settings: PerformanceSettings, onParameter: (Int, Int) -> Unit = { _, _ -> }, supported: (Int) -> Boolean = { true }) {
    val amount = if (settings.reverbEnabled) settings.reverbAmount else 0f
    SoundSlider("混响量", "${(amount * 100).roundToInt()}%", amount, 0f..1f,
        supported(0x40) && supported(0x42)) { value ->
        val percent = (value.coerceIn(0f, 1f) * 100).roundToInt()
        val enabled = percent > 0
        val wasEnabled = settings.reverbEnabled
        settings.reverbAmount = percent / 100f
        settings.reverbEnabled = enabled
        if (!enabled && wasEnabled) onParameter(0x40, 0)
        onParameter(0x42, percent * 10)
        if (enabled && !wasEnabled) onParameter(0x40, 1)
    }
    Text("模拟空间中的密集反射与尾音", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)

}

/** 声音参数默认收起，标题同时显示摘要，开关独立于展开操作。 */
@Composable
internal fun MixerSection(title: String, summary: String, initiallyExpanded: Boolean = false, modifier: Modifier = Modifier, expandRequest: Int = 0, action: (@Composable () -> Unit)? = null, content: @Composable ColumnScope.() -> Unit) {
    var expanded by rememberSaveable(title) { mutableStateOf(initiallyExpanded) }
    LaunchedEffect(expandRequest) { if (expandRequest > 0) expanded = true }
    Card(modifier.fillMaxWidth().animateContentSize(), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerHigh)) {
        Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.CenterVertically) {
                Row(Modifier.weight(1f).clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { expanded = !expanded }.padding(vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) { Text(title, style = MaterialTheme.typography.titleMedium); if (summary.isNotEmpty()) Text(summary, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.labelSmall) }
                    Text(if (expanded) "⌃" else "⌄", color = MaterialTheme.colorScheme.primary)
                }
                action?.invoke()
            }
            if (expanded) Column(Modifier.fillMaxWidth().padding(bottom = 4.dp), verticalArrangement = Arrangement.spacedBy(2.dp), content = content)
        }
    }
}

@Composable
internal fun SoundSlider(label: String, valueLabel: String, value: Float, range: ClosedFloatingPointRange<Float>, enabled: Boolean = true, displayScale: Float? = null, onChange: (Float) -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, modifier = Modifier.width(52.dp), style = MaterialTheme.typography.labelMedium, maxLines = 1, softWrap = false)
        StableParameterSlider(value, onChange, enabled, Modifier.weight(1f), range)
        EditableParameter(value, valueLabel, range, enabled, Modifier.width(72.dp), displayScale = displayScale, onChange = onChange)
    }
}

@Composable
internal fun JoystickInputSettings(settings: PerformanceSettings, enabled: Boolean = true) {
    SettingsCard("摇杆输入") {
        Text("上推升音、下拉降音；左推大幅调制，右推小幅调制，松手恢复。", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        SettingSwitch("启用摇杆", settings.joystickEnabled, { settings.joystickEnabled = it; settings.center(); settings.send(0x71, if (it) 1 else 0) }, enabled = enabled)
    }
}

@Composable
internal fun SettingsCard(title: String, content: @Composable ColumnScope.() -> Unit) {
    Card(Modifier.fillMaxWidth(), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerHigh)) {
        Column(Modifier.fillMaxWidth().padding(20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) { Text(title, style = MaterialTheme.typography.titleLarge); content() }
    }
}

@Composable
internal fun SettingSwitch(label: String, checked: Boolean, onChange: (Boolean) -> Unit, enabled: Boolean = true) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) { Text(label, Modifier.weight(1f)); Switch(checked = checked, onCheckedChange = onChange, enabled = enabled) }
}

@Composable
internal fun SettingSlider(label: String, valueLabel: String, value: Float, range: ClosedFloatingPointRange<Float>, enabled: Boolean = true, onChange: (Float) -> Unit) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) { Text(label, Modifier.weight(1f)); EditableParameter(value, valueLabel, range, enabled, Modifier.widthIn(min = 64.dp), onChange = onChange) }
    StableParameterSlider(value, onChange, enabled, range = range)
}

/** 数值本身就是编辑入口；未激活时只显示文字，不绘制输入框。 */
@Composable
internal fun EditableParameter(value: Float, label: String, range: ClosedFloatingPointRange<Float>, enabled: Boolean = true, modifier: Modifier = Modifier, displayScale: Float? = null, textStyle: TextStyle = MaterialTheme.typography.labelMedium, onChange: (Float) -> Unit) {
    var editing by remember { mutableStateOf(false) }
    val draft = rememberTextFieldState()
    var hadFocus by remember { mutableStateOf(false) }
    val scale = displayScale ?: if (label.contains("ms")) 1000f else if (label.contains("%")) 100f else 1f
    val focus = LocalFocusManager.current
    val requester = remember { FocusRequester() }
    val keyboard = LocalSoftwareKeyboardController.current
    val latestValue by rememberUpdatedState(value)
    val latestOnChange by rememberUpdatedState(onChange)
    fun commit() {
        val next = draft.text.toString().toFloatOrNull()?.takeIf { it.isFinite() }?.div(scale)?.coerceIn(range) ?: latestValue
        latestOnChange(next)
        editing = false
    }
    LaunchedEffect(editing) { if (editing) { requester.requestFocus(); keyboard?.show() } }
    val style = textStyle.copy(textAlign = TextAlign.End, color = if (enabled) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f))
    if (editing) {
        BasicTextField(state = draft, inputTransformation = InputTransformation {
            val normalized = asCharSequence().toString().replace(',', '.')
            if (normalized.length > 9 || normalized.any { it !in '0'..'9' && it != '.' } || normalized.count { it == '.' } > 1) revertAllChanges()
            else for (index in 0 until length) { if (charAt(index) == ',') replace(index, index + 1, ".") }
        }, modifier = modifier.heightIn(min = 40.dp).wrapContentHeight(Alignment.CenterVertically).numericFocusTarget().focusRequester(requester).onFocusChanged { if (it.isFocused) hadFocus = true else if (hadFocus && editing) { commit(); hadFocus = false } }, lineLimits = TextFieldLineLimits.SingleLine, textStyle = style, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal, imeAction = ImeAction.Done), onKeyboardAction = { commit(); focus.clearFocus(); keyboard?.hide() })
    } else {
        Text(label, modifier = modifier.heightIn(min = 40.dp).wrapContentHeight(Alignment.CenterVertically).clickable(enabled = enabled, interactionSource = remember { MutableInteractionSource() }, indication = null) {
            val displayed = Regex("[0-9]+(?:[.,][0-9]+)?").find(label)?.value?.replace(',', '.') ?: value.toString()
            draft.edit { replace(0, length, displayed); selection = TextRange(0, displayed.length) }
            hadFocus = false
            editing = true
        }, style = style)
    }
}

/** 静音时保留同一套滑块几何尺寸，只更改颜色并拦截输入。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun StableParameterSlider(value: Float, onChange: (Float) -> Unit, enabled: Boolean, modifier: Modifier = Modifier, range: ClosedFloatingPointRange<Float> = 0f..1f, onFinished: (() -> Unit)? = null) {
    val palette = MaterialTheme.colorScheme
    val interaction = remember { MutableInteractionSource() }
    val sliderState = remember(range) { SliderState(value = value, trackRange = range) }
    SideEffect { sliderState.value = value }
    val locked = if (enabled) Modifier else Modifier.pointerInput(Unit) {
        awaitEachGesture {
            do {
                val event = awaitPointerEvent(androidx.compose.ui.input.pointer.PointerEventPass.Initial)
                event.changes.forEach { it.consume() }
            } while (event.changes.any { it.pressed })
        }
    }.semantics { disabled() }
    Slider(state = sliderState, onValueChange = { if (enabled) { sliderState.value = it; onChange(it) } }, onValueChangeFinished = { if (enabled) onFinished?.invoke() }, enabled = true, interactionSource = interaction, modifier = modifier.height(48.dp).then(locked), colors = if (enabled) SliderDefaults.colors(inactiveTrackColor = palette.secondaryContainer.copy(alpha = 0.45f)) else SliderDefaults.colors(thumbColor = palette.onSurface.copy(alpha = 0.38f), activeTrackColor = palette.onSurface.copy(alpha = 0.38f), inactiveTrackColor = palette.onSurface.copy(alpha = 0.12f)))
}

/** 选中项采用主题色实心填充，避免深色下与禁用状态混淆。 */
@Composable
internal fun HallPadChoiceChip(selected: Boolean, onClick: () -> Unit, label: @Composable () -> Unit, modifier: Modifier = Modifier, colors: SelectableChipColors = FilterChipDefaults.filterChipColors(containerColor = MaterialTheme.colorScheme.surface, labelColor = MaterialTheme.colorScheme.onSurface, selectedContainerColor = MaterialTheme.colorScheme.primary, selectedLabelColor = MaterialTheme.colorScheme.onPrimary, selectedLeadingIconColor = MaterialTheme.colorScheme.onPrimary), leadingIcon: (@Composable () -> Unit)? = null, enabled: Boolean = true) {
    FilterChip(selected = selected, onClick = onClick, label = label, modifier = modifier.heightIn(min = 44.dp), colors = colors, leadingIcon = leadingIcon, enabled = enabled)
}


/** 保持 ID2 的无符号协议；左右采用不同深度，中心始终为零。 */
internal fun joystickModulation(x: Float, sensitivity: Float): Int = (abs(x.coerceIn(-1f, 1f)) * (if (x < 0f) 127f else 32f) * sensitivity.coerceIn(0f, 1f)).roundToInt().coerceIn(0, 127)
