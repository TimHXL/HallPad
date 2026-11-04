package com.timhxl.hallbeat

import android.content.res.Configuration
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.window.DialogWindowProvider
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties

internal fun toggleSelectedKey(selected: Set<Int>, id: Int): Set<Int> = if (id in selected) selected - id else selected + id

/** 按行优先排列，支持从任意方向框选。 */
internal fun rectangleKeys(start: Int, end: Int): Set<Int> = (minOf(start / 7, end / 7)..maxOf(start / 7, end / 7)).flatMap { row -> (minOf(start % 7, end % 7)..maxOf(start % 7, end % 7)).map { col -> row * 7 + col } }.toSet()

@Composable
internal fun BatchKeyInformation(state: HallPadState, compact: Boolean, enabled: Boolean = true) {
    var editing by remember { mutableStateOf(false) }
    LaunchedEffect(enabled) { if (!enabled) editing = false }
    BackHandler(enabled = !editing) { state.selectionMode = false }
    val ids = state.selectedKeys.sorted()
    if (editing && ids.isNotEmpty()) BatchKeyEditor(state, ids) { editing = false }
    KeyInformationFrame("已选 ${ids.size} 个键", action = {
        TextButton(onClick = { state.releaseAll(); editing = true }, enabled = enabled && !state.selectingKeys && ids.isNotEmpty(), modifier = Modifier.height(32.dp), contentPadding = PaddingValues(horizontal = 4.dp)) { Text("批量设置", maxLines = 1) }
    }, subtitle = {
        Text(if (ids.isEmpty()) "点击或拖动选择" else "点击或拖动继续选择", style = MaterialTheme.typography.labelSmall, maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis)
    })

}

@Composable
internal fun KeySelectionToolbar(state: HallPadState, showReset: Boolean = true, enabled: Boolean = true) {
    Row(Modifier.heightIn(min = 40.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.End) {
        if (state.selectionMode && showReset) TextButton(contentPadding = PaddingValues(horizontal = 6.dp), onClick = { state.selectedKeys = emptySet() }, enabled = enabled && !state.selectingKeys && state.selectedKeys.isNotEmpty()) { Text("重置") }
        TextButton(contentPadding = PaddingValues(horizontal = 6.dp), enabled = enabled, onClick = { state.releaseAll(); state.selectionMode = !state.selectionMode }) { Text(if (state.selectionMode) "完成" else "选择") }
    }
}

/** 未开启修改的项目保持原值，提交时一次应用至整个选区。 */
@Suppress("DEPRECATION")
@Composable
private fun BatchKeyEditor(state: HallPadState, ids: List<Int>, onClose: () -> Unit) {
    var changeInstrument by remember { mutableStateOf(false) }
    var instrument by remember { mutableStateOf(ids.map { state.keyInstruments[it] }.distinct().singleOrNull() ?: "跟随全局") }
    var picking by remember { mutableStateOf(false) }
    var changeVelocity by remember { mutableStateOf(false) }
    var velocity by remember { mutableStateOf((ids.map { state.velocities[it] }.distinct().singleOrNull() ?: 100).toString()) }
    var changeEnabled by remember { mutableStateOf(false) }
    var enabled by remember { mutableStateOf(true) }
    var noteMode by remember { mutableIntStateOf(0) }
    var noteValue by remember { mutableStateOf("0") }
    val landscape = LocalConfiguration.current.orientation == Configuration.ORIENTATION_LANDSCAPE && LocalConfiguration.current.screenWidthDp >= 700
    val palette = MaterialTheme.colorScheme
    val chipColors = FilterChipDefaults.filterChipColors(selectedContainerColor = palette.primary, selectedLabelColor = palette.onPrimary)
    val number = noteValue.toIntOrNull()
    val validNotes = when (noteMode) {
        0 -> true
        1 -> number != null && ids.all { state.notes[it] + number in 0..127 }
        3, 4 -> ids.all { previewKeyNote(state.notes[it], 0, noteMode, 0) in 0..127 }
        else -> number != null && number in 0..127 && naturalSequenceNote(number, ids.size - 1) <= 127
    }
    val valid = validNotes && (!changeVelocity || velocity.toIntOrNull()?.let { it in 1..127 } == true)
    if (picking) InstrumentPicker(instrument, { instrument = it; changeInstrument = true; picking = false }) { picking = false }
    val basicControls: @Composable () -> Unit = {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("音色", modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
                        InstrumentIcon(if (instrument == "跟随全局") state.instrument else instrument)
                        TextButton(onClick = { picking = true }) { Text(if (!changeInstrument && ids.map { state.keyInstruments[it] }.distinct().size > 1) "多种" else instrument) }
                    }
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("力度", modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
                        OutlinedTextField(value = velocity, onValueChange = { velocity = it; changeVelocity = true }, modifier = Modifier.width(100.dp), singleLine = true, label = { Text(if (!changeVelocity && ids.map { state.velocities[it] }.distinct().size > 1) "多种" else "1–127") }, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number))
                    }
                    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text("键位状态", style = MaterialTheme.typography.labelMedium, color = palette.onSurfaceVariant)
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            listOf("保持", "启用", "禁用").forEachIndexed { index, label ->
                                HallPadChoiceChip(selected = if (index == 0) !changeEnabled else changeEnabled && enabled == (index == 1), onClick = { changeEnabled = index != 0; enabled = index == 1 }, label = { Text(label, style = MaterialTheme.typography.labelMedium) }, colors = chipColors)
                            }
                        }
                    }

    }
    val noteControls: @Composable () -> Unit = {
                    Text("移调", style = MaterialTheme.typography.titleSmall)
                    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        val labels = listOf("保持原样", "整组升降", "无升降号排列", "统一升半音 ♯", "统一降半音 ♭")
                        val descriptions = listOf("不修改音高", "例如 C6 → C5，D6 → D5", "只使用 C、D、E、F、G、A、B", "每个选中键升高半音，例如 F2～F6 → F♯2～F♯6", "每个选中键降低半音，例如 B2～B6 → B♭2～B♭6")
                        labels.forEachIndexed { index, label ->
                            Surface(onClick = { noteMode = index; noteValue = if (index == 2) naturalStart(state.notes[ids.first()]).toString() else "0" }, shape = MaterialTheme.shapes.medium, color = if (noteMode == index) palette.primaryContainer else palette.surfaceContainerLow) {
                                Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                                    Column(Modifier.weight(1f)) {
                                        Text(label, style = MaterialTheme.typography.titleSmall)
                                        Text(descriptions[index], style = MaterialTheme.typography.bodySmall, color = palette.onSurfaceVariant)
                                    }
                                    RadioButton(selected = noteMode == index, onClick = null)
                                }
                            }
                        }
                    }
                    if (noteMode == 1) {
                        val shift = number ?: 0
                        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            OutlinedButton(onClick = { noteValue = (shift - 12).toString() }, enabled = ids.all { state.notes[it] + shift - 12 in 0..127 }) { Text("降低") }
                            Text(if (shift == 0) "原音高" else if (shift > 0) "升高 ${shift / 12} 组" else "降低 ${-shift / 12} 组", modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                            OutlinedButton(onClick = { noteValue = (shift + 12).toString() }, enabled = ids.all { state.notes[it] + shift + 12 in 0..127 }) { Text("升高") }
                        }
                        Text("每次移动一整组，例如 C6 降为 C5。已有的升降号会保留。", style = MaterialTheme.typography.bodySmall, color = palette.onSurfaceVariant)
                    }
                    if (noteMode == 2) {
                        val start = number ?: 60
                        Text("起始音", style = MaterialTheme.typography.labelMedium)
                        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            OutlinedButton(onClick = { noteValue = previousNaturalNote(start).toString() }, enabled = start > 0) { Text("降低") }
                            Text(noteName(start), modifier = Modifier.weight(1f), style = MaterialTheme.typography.titleLarge, textAlign = androidx.compose.ui.text.style.TextAlign.Center, fontFamily = HallPadMono, color = palette.primary)
                            OutlinedButton(onClick = { noteValue = nextNaturalNote(start).toString() }, enabled = naturalSequenceNote(nextNaturalNote(start), ids.size - 1) <= 127) { Text("升高") }
                        }
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            TextButton(onClick = { noteValue = (start - 12).toString() }, enabled = start >= 12) { Text("降低一组音") }
                            TextButton(onClick = { noteValue = (start + 12).toString() }, enabled = naturalSequenceNote(start + 12, ids.size - 1) <= 127) { Text("升高一组音") }
                        }
                        Text("从 ${noteName(start)} 开始，按行排列；跳过所有带升降号的音。", style = MaterialTheme.typography.bodySmall, color = palette.onSurfaceVariant)
                    }
                    if (noteMode == 3 || noteMode == 4) Text("按各键原音高调整；E♯显示为 F，F♭显示为 E，B 升半音及 C 降半音会跨八度。", style = MaterialTheme.typography.bodySmall, color = palette.onSurfaceVariant)
                    Text("修改预览", style = MaterialTheme.typography.titleSmall)
                    Text("显示调整后的音，点击琴键查看前后变化。", style = MaterialTheme.typography.bodySmall, color = palette.onSurfaceVariant)
                    KeyNotePreview(state, ids, noteMode, number ?: 0)
                    Text("点击“应用”保存修改。", style = MaterialTheme.typography.labelSmall, color = palette.onSurfaceVariant)
                    if (!valid) Text(if (!validNotes) "所选琴键超出 MIDI 0–127 音域，请调整移调设置。" else "力度请输入 1–127。", color = palette.error)
    }
    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        val dialogView = LocalView.current
        val backgroundColor = palette.background.toArgb()
        val lightBars = palette.background.luminance() > 0.5f
        SideEffect {
            (dialogView.parent as? DialogWindowProvider)?.window?.let { window ->
                androidx.core.view.WindowCompat.setDecorFitsSystemWindows(window, false)
                window.setBackgroundDrawable(android.graphics.drawable.ColorDrawable(backgroundColor))
                window.isNavigationBarContrastEnforced = false
                window.isStatusBarContrastEnforced = false
                window.navigationBarColor = android.graphics.Color.TRANSPARENT
                window.statusBarColor = android.graphics.Color.TRANSPARENT
                val controller = androidx.core.view.WindowCompat.getInsetsController(window, dialogView)
                controller.isAppearanceLightNavigationBars = lightBars
                controller.isAppearanceLightStatusBars = lightBars
            }
        }
        Surface(modifier = Modifier.fillMaxSize(), color = palette.background) {
            Column(Modifier.fillMaxSize().safeDrawingPadding().imePadding().padding(horizontal = 16.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                    TextButton(onClick = onClose) { Text("返回") }
                    Column(Modifier.weight(1f)) {
                        Text("批量设置", style = MaterialTheme.typography.titleMedium)
                        Text("已选 ${ids.size} 个键", style = MaterialTheme.typography.bodySmall, color = palette.onSurfaceVariant)
                    }
                    TextButton(onClick = { changeInstrument = false; changeVelocity = false; changeEnabled = false; noteMode = 0; velocity = (ids.map { state.velocities[it] }.distinct().singleOrNull() ?: 100).toString() }) { Text("撤销修改") }
                }
                if (landscape) {
                    Row(Modifier.fillMaxWidth().weight(1f), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Surface(Modifier.weight(1f), shape = MaterialTheme.shapes.medium, color = palette.surfaceContainerHigh) { Column(Modifier.padding(14.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) { basicControls() } }
                        Surface(Modifier.weight(1f), shape = MaterialTheme.shapes.medium, color = palette.surfaceContainerHigh) { Column(Modifier.padding(14.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) { noteControls() } }
                    }
                } else {
                    Column(Modifier.weight(1f).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) { basicControls(); noteControls() }
                }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                    TextButton(onClick = onClose) { Text("取消") }
                    Button(enabled = valid, onClick = {
                        state.releaseAll()
                        ids.forEachIndexed { index, id ->
                            if (changeInstrument) state.keyInstruments[id] = instrument
                            if (changeVelocity) { state.velocities[id] = velocity.toInt(); state.velocityModes[id] = 1 }
                            if (changeEnabled) state.keyEnabled[id] = enabled
                            if (noteMode != 0) {
                                state.notes[id] = previewKeyNote(state.notes[id], index, noteMode, noteValue.toInt())
                                if (noteMode == 3 || noteMode == 4) state.setKeySpelling(id, noteMode == 4)
                            }
                        }
                        state.persist(); state.selectedKeys = emptySet(); onClose()
                    }) { Text("应用") }
                }
            }
        }
    }
}


/** 预览与保存共用的音高计算；调用方负责音域校验。 */
internal fun previewKeyNote(original: Int, selectionIndex: Int, mode: Int, value: Int): Int = when (mode) {
    1 -> original + value
    2 -> naturalSequenceNote(value, selectionIndex)
    3 -> original + 1
    4 -> original - 1
    else -> original
}

@Composable
private fun KeyNotePreview(state: HallPadState, ids: List<Int>, mode: Int, value: Int) {
    val palette = MaterialTheme.colorScheme
    val selectionIndices = ids.withIndex().associate { it.value to it.index }
    fun displayNote(note: Int, id: Int): String = noteName(note, if (mode == 3) false else if (mode == 4) true else state.keyUsesFlats(id))
    var inspected by remember { mutableIntStateOf(ids.first()) }
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(5.dp)) {
        repeat(5) { row ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                repeat(7) { column ->
                    val id = row * 7 + column
                    val selectedIndex = selectionIndices[id]
                    val original = state.notes[id]
                    val target = if (selectedIndex == null) original else previewKeyNote(original, selectedIndex, mode, value)
                    val changed = selectedIndex != null && target != original
                    Surface(modifier = Modifier.weight(1f).heightIn(min = 48.dp), onClick = { inspected = id }, shape = MaterialTheme.shapes.small, color = if (changed) palette.primaryContainer else palette.surfaceContainerLow, border = if (id == inspected) androidx.compose.foundation.BorderStroke(1.dp, palette.primary) else null) {
                        Box(Modifier.fillMaxSize().padding(vertical = 12.dp), contentAlignment = Alignment.Center) {
                            Text(if (target in 0..127) displayNote(target, id) else "超出", fontFamily = HallPadMono, fontSize = 10.sp, fontWeight = if (changed) FontWeight.Bold else FontWeight.Normal, maxLines = 1, color = if (target !in 0..127) palette.error else if (changed) palette.onPrimaryContainer else palette.onSurfaceVariant)
                        }
                    }
                }
            }
        }
        val original = state.notes[inspected]
        val index = selectionIndices[inspected]
        val target = if (index == null) original else previewKeyNote(original, index, mode, value)
        Text("原来 ${noteName(original, state.keyUsesFlats(inspected))} → 调整后 ${if (target in 0..127) displayNote(target, inspected) else "超出音域"}", style = MaterialTheme.typography.bodyMedium, color = if (target in 0..127) palette.primary else palette.error)
    }
}


/** 自然音排列：跳过升降音，并允许超出 127 供提交校验。 */
internal fun naturalStart(note: Int): Int = if (note % 12 in listOf(1, 3, 6, 8, 10)) note - 1 else note
internal fun nextNaturalNote(note: Int): Int {
    var result = note + 1
    while (result % 12 in listOf(1, 3, 6, 8, 10)) result++
    return result
}
internal fun previousNaturalNote(note: Int): Int {
    var result = note - 1
    while (result >= 0 && result % 12 in listOf(1, 3, 6, 8, 10)) result--
    return result
}
internal fun naturalSequenceNote(start: Int, index: Int): Int {
    var result = naturalStart(start)
    repeat(index) { result = nextNaturalNote(result) }
    return result
}


/** 普通模式与选择模式共用尺寸、圆角及两行基线。 */
@Composable
internal fun KeyInformationFrame(title: String, mono: Boolean = false, action: @Composable () -> Unit, subtitle: @Composable RowScope.() -> Unit) {
    val palette = MaterialTheme.colorScheme
    Surface(modifier = Modifier.fillMaxWidth().height(88.dp), shape = androidx.compose.foundation.shape.RoundedCornerShape(18.dp), color = palette.surfaceContainerHigh.copy(alpha = 0.9f)) {
        Column(Modifier.fillMaxSize().padding(horizontal = 18.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(Modifier.fillMaxWidth().height(32.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(title, modifier = Modifier.weight(1f), style = MaterialTheme.typography.titleMedium, fontFamily = if (mono) HallPadMono else LocalTextStyle.current.fontFamily, maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis)
                action()
            }
            Row(Modifier.fillMaxWidth().height(28.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp), content = subtitle)
        }
    }
}
