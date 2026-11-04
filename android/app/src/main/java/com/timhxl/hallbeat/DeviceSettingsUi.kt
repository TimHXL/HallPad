package com.timhxl.hallbeat

import android.os.SystemClock
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.animation.core.tween
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.lerp
import kotlinx.coroutines.launch
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import kotlin.math.*

/** 设备配置独立成页，返回后保留主页与底部导航的位置。 */
@Composable
internal fun DeviceSettingsPage(state: HallPadState, drumsticks: DrumsticksPreviewState, onClose: () -> Unit) {
    val pager = rememberPagerState(pageCount = { 2 })
    val section = pager.currentPage
    val scope = rememberCoroutineScope()
    val palette = MaterialTheme.colorScheme
    Column(Modifier.fillMaxSize().background(palette.background).windowInsetsPadding(WindowInsets.safeDrawing).imePadding().padding(horizontal = 20.dp)) {
        Row(Modifier.fillMaxWidth().heightIn(min = 64.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
            Text("设备设置", style = MaterialTheme.typography.headlineSmall)
            TextButton(onClick = onClose) { Text("返回") }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf("灯光", "输入").forEachIndexed { index, title ->
                HallPadChoiceChip(selected = section == index, onClick = { scope.launch { pager.animateScrollToPage(index, animationSpec = tween(280)) } }, label = { Text(title) }, modifier = Modifier.weight(1f))
            }
        }
        HorizontalPager(state = pager, modifier = Modifier.weight(1f).fillMaxWidth(), beyondViewportPageCount = 1, key = { it }) { page ->
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(top = 16.dp, bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                when (page) {
                    0 -> {
                        LightingSettings(state)
                        DrumLightingSettings(drumsticks)
                    }
                    1 -> {
                        JoystickInputSettings(state.performance, enabled = state.canControlParameter(0x71))
                        Text("手机摇杆需要设备提供远程弯音能力；水波扩展需设备实现对应协议。", style = MaterialTheme.typography.bodySmall)
                        if (state.deviceMessage.isNotBlank()) Text(state.deviceMessage, color = MaterialTheme.colorScheme.error)
                        SettingsCard("手机键盘力度曲线") {
                            Text("作用于手机按键发出的力度，实体键曲线需设备另行支持。", style = MaterialTheme.typography.bodySmall)
                            SettingSlider("响应指数", "${"%.2f".format(state.curve)}", state.curve, 0.3f..3f) { state.curve = it }
                            Text("将按键输入强度映射为音符力度：1 为线性；小于 1 轻触更响；大于 1 需要更强输入。", style = MaterialTheme.typography.bodySmall, color = palette.onSurfaceVariant)
                            val color = palette.primary
                            Canvas(Modifier.fillMaxWidth().height(120.dp)) {
                                val path = Path()
                                for (i in 0..100) {
                                    val x = i / 100f; val y = x.pow(state.curve)
                                    if (i == 0) path.moveTo(0f, size.height) else path.lineTo(x * size.width, (1 - y) * size.height)
                                }
                                drawPath(path, color, style = Stroke(3.dp.toPx()))
                            }
                        }
                    }

                }
            }
        }
    }
}

@Composable
private fun LightingSettings(state: HallPadState) {
    val settings = state.performance
    val palette = MaterialTheme.colorScheme
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
        Text("键盘灯光", style = MaterialTheme.typography.titleLarge)
        TextButton(enabled = listOf(0x60, 0x61, 0x63, 0x65).all(state::canControlParameter), onClick = {
            state.effect = "水波"; state.brightness = 1f
            settings.rippleSpeed = 5f; settings.rippleDecay = 1.2f
            settings.randomColor = true; settings.red = 0; settings.green = 220; settings.blue = 120; settings.hue = 145f
            state.sendParameter(0x60, 0); state.sendParameter(0x61, 1000)
            settings.send(0x63, 5000); settings.send(0x65, 1200)
            state.persist()
        }) { Text("恢复默认") }
    }
    // 用整行模式选项代替拥挤的小标签，参数与模式分组呈现。
    Card(colors = CardDefaults.cardColors(containerColor = palette.surfaceContainerHigh)) {
        Column(Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
            listOf("水波" to "按键触发，向周围扩散", "常亮" to "全部键位持续点亮", "关闭" to "关闭键盘灯光").forEachIndexed { index, mode ->
                Surface(enabled = state.canControlParameter(0x60), onClick = { state.effect = mode.first; if (mode.first == "常亮") settings.send(0x62, (settings.red shl 16) or (settings.green shl 8) or settings.blue); state.sendParameter(0x60, listOf("水波", "常亮", "关闭").indexOf(mode.first)) }, color = if (state.effect == mode.first) palette.primaryContainer else Color.Transparent) {
                    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        RadioButton(selected = state.effect == mode.first, enabled = state.canControlParameter(0x60), onClick = null)
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
    if (state.effect != "关闭") SettingsCard("灯光预览") {
        LightMatrixPreview(state)
        Text(if (state.effect == "水波") "点击琴键查看水波效果" else if (state.effect == "常亮") "常亮" else "灯光已关闭", color = palette.onSurfaceVariant, style = MaterialTheme.typography.labelMedium)
        SettingSlider("亮度", "${(state.brightness * 100).roundToInt()}%", state.brightness, 0f..1f, state.effect != "关闭" && state.canControlParameter(0x61)) { state.brightness = it; state.sendParameter(0x61, (it * 1000).roundToInt()) }
    }
    if (state.effect == "水波") SettingsCard("水波参数") {
        SoundSlider("速度", "${"%.1f".format(settings.rippleSpeed)} 格/s", settings.rippleSpeed, 0.5f..30f, state.canControlParameter(0x63)) { settings.rippleSpeed = it; settings.send(0x63, (it * 1000).roundToInt()) }
        SoundSlider("衰减", "${"%.1f".format(settings.rippleDecay)} s", settings.rippleDecay, 0.2f..5f, state.canControlParameter(0x65)) { settings.rippleDecay = it; settings.send(0x65, (it * 1000).roundToInt()) }
    }
    if (state.effect == "常亮") SettingsCard("常亮颜色") {
        RgbSettings(settings, enabled = state.canControlParameter(0x62))
    }
}

@Composable
private fun RgbSettings(settings: PerformanceSettings, enabled: Boolean = true) {
    RgbHexSettings((settings.red shl 16) or (settings.green shl 8) or settings.blue, enabled) { rgb ->
        settings.red = (rgb shr 16) and 255; settings.green = (rgb shr 8) and 255; settings.blue = rgb and 255
        settings.sendRgb()
    }
}

@Composable
internal fun RgbHexSettings(rgb: Int, enabled: Boolean = true, onChange: (Int) -> Unit) {
    val hex = "%06X".format(rgb and 0xFFFFFF)
    var draft by remember { mutableStateOf(TextFieldValue(hex)) }
    var editing by remember { mutableStateOf(false) }
    val focus = LocalFocusManager.current
    LaunchedEffect(hex) { if (!editing) draft = TextFieldValue(hex) }
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.size(36.dp).background(Color(0xFF000000L or (rgb.toLong() and 0xFFFFFF)), RoundedCornerShape(10.dp)))
        Text("颜色", modifier = Modifier.weight(1f), style = MaterialTheme.typography.titleMedium)
        OutlinedTextField(value = draft, enabled = enabled, onValueChange = { next ->
            val clean = next.text.removePrefix("#").uppercase()
            if (clean.length <= 6 && clean.all { it in '0'..'9' || it in 'A'..'F' }) {
                draft = next.copy(text = clean, selection = TextRange(next.selection.start.coerceAtMost(clean.length), next.selection.end.coerceAtMost(clean.length)))
                if (clean.length == 6) {
                    onChange(clean.toInt(16))
                }
            }
        }, prefix = { Text("#") }, singleLine = true, textStyle = MaterialTheme.typography.titleMedium.copy(color = MaterialTheme.colorScheme.primary), keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done), keyboardActions = KeyboardActions(onDone = { focus.clearFocus() }), modifier = Modifier.width(148.dp).onFocusChanged { state ->
            editing = state.isFocused
            draft = if (state.isFocused) TextFieldValue(hex, TextRange(0, hex.length)) else TextFieldValue(hex)
        })
    }
}

@Composable
private fun LightMatrixPreview(state: HallPadState) {
    val settings = state.performance
    val palette = MaterialTheme.colorScheme
    var trigger by remember { mutableIntStateOf(0) }
    var startedAt by remember { mutableLongStateOf(0L) }
    var frameTime by remember { mutableLongStateOf(0L) }
    var origin by remember { mutableStateOf(Offset(3f, 2f)) }
    var randomHue by remember { mutableFloatStateOf(145f) }
    // 新水波开始时保留每个键的上一帧颜色，避免整块预览突然变灰。
    val renderedColors = remember { Array(35) { palette.background } }
    var previousColors by remember { mutableStateOf(renderedColors.toList()) }
    LaunchedEffect(trigger, state.effect) {
        if (state.effect == "水波" && trigger > 0) {
            while ((frameTime - startedAt).coerceAtLeast(0L) / 1000f < 9f / settings.rippleSpeed + settings.rippleDecay * 7f) { frameTime = SystemClock.elapsedRealtime(); delay(33L) }
        }
    }
    Canvas(Modifier.fillMaxWidth().aspectRatio(1.9f).clip(RoundedCornerShape(14.dp)).background(palette.background).padding(8.dp).pointerInput(state.effect) {
        if (state.effect != "水波") return@pointerInput
        awaitEachGesture {
            val down = awaitFirstDown()
            origin = Offset((down.position.x / size.width * 7).toInt().coerceIn(0, 6).toFloat(), (down.position.y / size.height * 5).toInt().coerceIn(0, 4).toFloat())
            previousColors = renderedColors.toList()
            startedAt = SystemClock.elapsedRealtime()
            frameTime = startedAt
            randomHue = kotlin.random.Random.nextFloat() * 360f
            trigger++; down.consume()
        }
    }) {
        val w = size.width / 7f; val h = size.height / 5f
        val age = (frameTime - startedAt).coerceAtLeast(0L) / 1000f
        val color = if (state.effect == "水波") Color.hsv(randomHue, 0.85f, 1f) else settings.lightColor
        repeat(35) { id ->
            val x = id % 7; val y = id / 7
            val distance = hypot(x - origin.x, y - origin.y)
            // 到达后保持一格传播时间，再按衰减常数降低高亮，宽度固定为一格。
            val arrival = kotlin.math.ceil(distance.toDouble()).toFloat() / settings.rippleSpeed
            val reached = age >= arrival
            val fadeAge = (age - arrival - 1f / settings.rippleSpeed).coerceAtLeast(0f)
            val intensity = if (state.effect == "常亮") state.brightness else if (reached) exp(-fadeAge / settings.rippleDecay) * state.brightness else 0f
            val position = Offset(x * w + 2.dp.toPx(), y * h + 2.dp.toPx())
            val keySize = Size((w - 4.dp.toPx()).coerceAtLeast(1f), (h - 4.dp.toPx()).coerceAtLeast(1f))
            val radius = androidx.compose.ui.geometry.CornerRadius(5.dp.toPx())
            val retained = if (reached) color else previousColors[id]
            val keyColor = if (state.effect == "水波" && trigger == 0) palette.background else if (state.effect == "常亮") lerp(palette.background, color, state.brightness) else if (!reached) previousColors[id] else lerp(lerp(palette.background, retained, state.brightness * 0.22f), color, intensity.coerceIn(0f, 1f))
            renderedColors[id] = keyColor
            drawRoundRect(keyColor, position, keySize, radius)
            drawRoundRect(palette.outlineVariant.copy(alpha = 0.6f), position, keySize, radius, style = Stroke(1.dp.toPx()))
        }
    }
}
