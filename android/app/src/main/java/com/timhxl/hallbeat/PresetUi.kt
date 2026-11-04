package com.timhxl.hallbeat

import androidx.compose.foundation.background
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.focusable
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.foundation.horizontalScroll
import androidx.compose.ui.graphics.Color
import kotlinx.coroutines.launch
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import android.content.res.Configuration
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.PlatformTextStyle
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.platform.LocalFocusManager
import kotlin.math.roundToInt
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun KeyEditor(state: HallPadState, id: Int, onClose: () -> Unit) {
    if (LocalConfiguration.current.orientation == Configuration.ORIENTATION_LANDSCAPE) { LandscapeKeyEditor(state, id, onClose); return }
    var note by rememberSaveable(id) { mutableIntStateOf(state.notes[id]) }
    var flats by rememberSaveable(id) { mutableStateOf(state.keyUsesFlats(id)) }
    var instrument by rememberSaveable(id) { mutableStateOf(state.keyInstruments[id]) }
    var velocity by rememberSaveable(id) { mutableIntStateOf(state.velocities[id]) }
    var velocityText by rememberSaveable(id) { mutableStateOf(state.velocities[id].toString()) }
    val velocityValid = velocityText.toIntOrNull()?.let { it in 1..127 } == true
    val focusManager = LocalFocusManager.current
    val palette = MaterialTheme.colorScheme
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val scope = rememberCoroutineScope()
    var closing by remember { mutableStateOf(false) }
    var choosingInstrument by rememberSaveable(id) { mutableStateOf(false) }
    val closeSheet: () -> Unit = {
        if (!closing) {
            closing = true
            focusManager.clearFocus()
            scope.launch {
                try { sheetState.hide(); if (!sheetState.isVisible) onClose() } finally { closing = false }
            }
        }
    }
    if (choosingInstrument) InstrumentPicker(instrument, { instrument = it; choosingInstrument = false }) { choosingInstrument = false }
    ModalBottomSheet(onDismissRequest = closeSheet, sheetState = sheetState, dragHandle = { Box(Modifier.fillMaxWidth().padding(vertical = 20.dp), contentAlignment = Alignment.Center) { Box(Modifier.size(width = 32.dp, height = 4.dp).background(palette.onSurfaceVariant.copy(alpha = 0.4f), RoundedCornerShape(2.dp))) } }, containerColor = palette.surface, contentColor = palette.onSurface) {
        Column(Modifier.fillMaxWidth().widthIn(max = 560.dp).align(Alignment.CenterHorizontally).imePadding().padding(horizontal = 24.dp).weight(1f, fill = false).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                Column {
                    Text("键位设置", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                    Text("K${(id + 1).toString().padStart(2, '0')}", color = palette.onSurfaceVariant, style = MaterialTheme.typography.labelLarge)
                }
                TextButton(onClick = { note = defaultNote(id); flats = false; instrument = "跟随全局"; velocity = 100; velocityText = "100" }) { Text("恢复默认") }
            }
            Surface(modifier = Modifier.fillMaxWidth(), shape = MaterialTheme.shapes.medium, color = palette.secondaryContainer, contentColor = palette.onSecondaryContainer) {
                Row(Modifier.fillMaxWidth().height(76.dp).padding(horizontal = 20.dp), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                    StableNotePreview(note, Modifier.weight(1f), flats)
                    Text("MIDI $note", color = palette.onSecondaryContainer, style = MaterialTheme.typography.labelLarge, maxLines = 1, softWrap = false)
                }
            }
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                    Text("音符", fontWeight = FontWeight.SemiBold)
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        TextButton(onClick = { note -= 12 }, enabled = note >= 12) { Text("−") }
                        Text("八度 ${note / 12 - 1}", style = MaterialTheme.typography.labelLarge)
                        TextButton(onClick = { note += 12 }, enabled = note <= 115) { Text("＋") }
                    }
                }
                keyNoteChoices.chunked(6).forEach { choices ->
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        choices.forEach { (pitch, label, choiceFlats) ->
                            val next = note / 12 * 12 + pitch
                            val available = next in 0..127
                            val selected = available && note % 12 == pitch && (pitch !in listOf(1, 3, 6, 8, 10) || flats == choiceFlats)
                            val fill = if (!available) palette.onSurface.copy(alpha = 0.08f) else if (selected) palette.primaryContainer else palette.surfaceContainerHigh
                            val foreground = if (!available) palette.onSurface.copy(alpha = 0.38f) else if (selected) palette.onPrimaryContainer else palette.onSurfaceVariant
                            Surface(onClick = { if (available) { note = next; flats = choiceFlats } }, enabled = available, shape = MaterialTheme.shapes.small, color = fill, contentColor = foreground, modifier = Modifier.weight(1f).height(42.dp)) {
                                Box(contentAlignment = Alignment.Center) { Text(label, style = MaterialTheme.typography.labelMedium.copy(fontSize = 13.sp, lineHeight = 20.sp, platformStyle = PlatformTextStyle(includeFontPadding = false)), fontWeight = if (selected) FontWeight.Bold else FontWeight.Normal, maxLines = 1, softWrap = false) }
                            }
                        }
                        repeat(6 - choices.size) { Spacer(Modifier.weight(1f).height(42.dp)) }
                    }
                }
            }
            Surface(onClick = { focusManager.clearFocus(); choosingInstrument = true }, shape = MaterialTheme.shapes.medium, color = palette.surfaceContainerHigh, modifier = Modifier.fillMaxWidth()) {
                Row(Modifier.fillMaxWidth().heightIn(min = 64.dp).padding(horizontal = 16.dp, vertical = 10.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text("音色", color = palette.onSurfaceVariant)
                    Text(instrument, modifier = Modifier.weight(1f), fontWeight = FontWeight.SemiBold, maxLines = 1)
                    InstrumentIcon(if (instrument == "跟随全局") state.instrument else instrument)
                    Text("›", color = palette.primary, fontSize = 24.sp)
                }
            }
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                    Text("默认力度", fontWeight = FontWeight.SemiBold)
                    Text("1–127", color = palette.onSurfaceVariant, style = MaterialTheme.typography.labelMedium)
                }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Slider(value = velocity.toFloat(), onValueChange = { velocity = it.roundToInt().coerceIn(1, 127); velocityText = velocity.toString() }, valueRange = 1f..127f, modifier = Modifier.weight(1f))
                    OutlinedTextField(value = velocityText, onValueChange = { text ->
                        if (text.length <= 3 && text.all { it in '0'..'9' }) {
                            velocityText = text
                            text.toIntOrNull()?.takeIf { it in 1..127 }?.let { velocity = it }
                        }
                    }, modifier = Modifier.width(80.dp), singleLine = true, isError = !velocityValid, textStyle = MaterialTheme.typography.bodyLarge.copy(textAlign = TextAlign.Center), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number, imeAction = ImeAction.Done), keyboardActions = KeyboardActions(onDone = {
                        velocity = (velocityText.toIntOrNull() ?: velocity).coerceIn(1, 127)
                        velocityText = velocity.toString()
                        focusManager.clearFocus()
                    }))
                }
                Box(Modifier.fillMaxWidth().height(20.dp)) {
                    if (!velocityValid) Text("请输入 1–127", color = palette.error, style = MaterialTheme.typography.labelSmall, modifier = Modifier.align(Alignment.CenterEnd), maxLines = 1)
                }
            }
        }
        Row(Modifier.fillMaxWidth().widthIn(max = 560.dp).align(Alignment.CenterHorizontally).padding(horizontal = 24.dp, vertical = 12.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            OutlinedButton(onClick = closeSheet, enabled = !closing, modifier = Modifier.weight(1f)) { Text("取消") }
            Button(onClick = { state.releaseAll(); state.notes[id] = note; state.setKeySpelling(id, flats); state.keyInstruments[id] = instrument; state.velocities[id] = velocity; state.velocityModes[id] = 1; state.persist(); closeSheet() }, enabled = velocityValid && !closing, modifier = Modifier.weight(1f)) { Text("应用设置") }
        }
    }
}

/** 横屏独立双栏布局，避免竖屏抽屉裁掉下半部分。 */
@Composable
private fun LandscapeKeyEditor(state: HallPadState, id: Int, onClose: () -> Unit) {
    var note by rememberSaveable(id) { mutableIntStateOf(state.notes[id]) }
    var flats by rememberSaveable(id) { mutableStateOf(state.keyUsesFlats(id)) }
    var instrument by rememberSaveable(id) { mutableStateOf(state.keyInstruments[id]) }
    var velocity by rememberSaveable(id) { mutableIntStateOf(state.velocities[id]) }
    var picking by remember { mutableStateOf(false) }
    val palette = MaterialTheme.colorScheme
    if (picking) InstrumentPicker(instrument, { instrument = it; picking = false }) { picking = false }
    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxWidth(0.90f).heightIn(max = 340.dp), shape = MaterialTheme.shapes.large, color = palette.surface, contentColor = palette.onSurface) {
            Column(Modifier.imePadding().padding(horizontal = 20.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                    Text("键位设置 · K${(id + 1).toString().padStart(2, '0')}", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                    TextButton(onClick = { note = defaultNote(id); flats = false; instrument = "跟随全局"; velocity = 100 }) { Text("恢复默认") }
                }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(20.dp)) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                            Text(noteName(note, flats), style = MaterialTheme.typography.titleLarge, color = palette.primary, fontWeight = FontWeight.Bold)
                            Text("MIDI $note", style = MaterialTheme.typography.labelMedium, color = palette.onSurfaceVariant)
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                TextButton(onClick = { note -= 12 }, enabled = note >= 12, contentPadding = PaddingValues(0.dp), modifier = Modifier.width(36.dp)) { Text("−") }
                                Text("八度 ${note / 12 - 1}", style = MaterialTheme.typography.labelMedium)
                                TextButton(onClick = { note += 12 }, enabled = note <= 115, contentPadding = PaddingValues(0.dp), modifier = Modifier.width(36.dp)) { Text("＋") }
                            }
                        }
                        keyNoteChoices.chunked(6).forEach { choices ->
                            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                choices.forEach { (pitch, label, choiceFlats) ->
                                    val next = note / 12 * 12 + pitch
                                    val enabled = next in 0..127
                                    val selected = enabled && note % 12 == pitch && (pitch !in listOf(1, 3, 6, 8, 10) || flats == choiceFlats)
                                    Surface(onClick = { note = next; flats = choiceFlats }, enabled = enabled, shape = MaterialTheme.shapes.small, color = if (!enabled) palette.onSurface.copy(alpha = 0.06f) else if (selected) palette.primaryContainer else palette.surfaceContainerHigh, contentColor = if (!enabled) palette.onSurface.copy(alpha = 0.38f) else if (selected) palette.onPrimaryContainer else palette.onSurface, modifier = Modifier.weight(1f).height(36.dp)) {
                                        Box(contentAlignment = Alignment.Center) { Text(label, fontSize = 12.sp) }
                                    }
                                }
                                repeat(6 - choices.size) { Spacer(Modifier.weight(1f).height(36.dp)) }
                            }
                        }
                    }
                    Column(Modifier.weight(0.85f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Surface(onClick = { picking = true }, shape = MaterialTheme.shapes.medium, color = palette.surfaceContainerHigh) {
                            Row(Modifier.fillMaxWidth().padding(12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) { Text("音色", modifier = Modifier.weight(1f), style = MaterialTheme.typography.labelMedium); Text(instrument, style = MaterialTheme.typography.labelMedium, maxLines = 1); InstrumentIcon(if (instrument == "跟随全局") state.instrument else instrument); Text("›") }
                        }
                        SoundSlider("力度", velocity.toString(), velocity.toFloat(), 1f..127f) { velocity = it.roundToInt().coerceIn(1, 127) }
                    }
                }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End, verticalAlignment = Alignment.CenterVertically) {
                    TextButton(onClick = onClose) { Text("取消") }
                    Spacer(Modifier.width(16.dp))
                    Button(onClick = { state.releaseAll(); state.notes[id] = note; state.setKeySpelling(id, flats); state.keyInstruments[id] = instrument; state.velocities[id] = velocity; state.velocityModes[id] = 1; state.persist(); onClose() }) { Text("应用设置") }
                }
            }
        }
    }
}

/** 音名、变音记号与八度独立排版，升号不参与字母的字体度量。 */
@Composable
private fun StableNotePreview(note: Int, modifier: Modifier = Modifier, preferFlats: Boolean = false) {
    val pitch = notePitchNames(preferFlats)[note % 12].take(1)
    val sharp = note % 12 in listOf(1, 3, 6, 8, 10)
    val style = MaterialTheme.typography.headlineLarge.copy(fontSize = 36.sp, lineHeight = 48.sp, fontWeight = FontWeight.Bold, platformStyle = PlatformTextStyle(includeFontPadding = false))
    Row(modifier.height(56.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.width(27.dp).fillMaxHeight(), contentAlignment = Alignment.CenterStart) { Text(pitch, style = style, maxLines = 1, softWrap = false) }
        // 始终保留升号槽，透明时仍使用相同文字与尺寸。
        Box(Modifier.width(17.dp).fillMaxHeight(), contentAlignment = Alignment.CenterStart) { Text(if (preferFlats) "♭" else "♯", style = style.copy(fontSize = 26.sp), color = if (sharp) LocalContentColor.current else Color.Transparent, maxLines = 1, softWrap = false) }
        Box(Modifier.width(64.dp).fillMaxHeight(), contentAlignment = Alignment.CenterStart) { Text((note / 12 - 1).toString(), style = style.copy(fontSize = 28.sp), maxLines = 1, softWrap = false) }
    }
}

@Composable
internal fun InstrumentPicker(selected: String, onSelect: (String) -> Unit, allowFollowGlobal: Boolean = true, onClose: () -> Unit) {
    var query by rememberSaveable { mutableStateOf("") }
    var category by rememberSaveable { mutableStateOf("全部") }
    // 添加音色时扩展目录，编辑面板保持固定为一个入口。
    val categories = HallPadInstruments.associateWith { name -> when (name) { "钢琴", "风琴", "电钢琴" -> "键盘"; "弦乐", "小提琴", "拨弦", "贝斯" -> "弦乐"; "钟琴", "木琴", "马林巴", "小军鼓" -> "打击乐"; "长笛" -> "管乐"; else -> "其他" } }
    val results = HallPadInstruments.filter { name -> (category == "全部" || categories[name] == category) && name.contains(query.trim(), ignoreCase = true) }
    val initialFocus = remember { FocusRequester() }
    val landscape = LocalConfiguration.current.orientation == Configuration.ORIENTATION_LANDSCAPE
    val palette = MaterialTheme.colorScheme
    // 单一滚动列表适配横竖屏，搜索框不会自动获取焦点。
    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxWidth(if (landscape) 0.92f else 0.92f).fillMaxHeight(if (landscape) 0.94f else 0.82f), shape = MaterialTheme.shapes.large, color = palette.surface, contentColor = palette.onSurface) {
            Column(Modifier.fillMaxSize().imePadding().padding(12.dp).focusRequester(initialFocus).focusable(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                LaunchedEffect(Unit) { initialFocus.requestFocus() }
                Row(Modifier.fillMaxWidth().height(40.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
                    Text("选择音色", style = MaterialTheme.typography.titleMedium)
                    TextButton(onClick = onClose) { Text("返回") }
                }
                Row(Modifier.fillMaxWidth().weight(1f), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    if (landscape) Column(Modifier.width(164.dp).fillMaxHeight().verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        OutlinedTextField(value = query, onValueChange = { query = it }, modifier = Modifier.fillMaxWidth(), singleLine = true, placeholder = { Text("搜索音色") })
                        (listOf("全部") + categories.values.distinct()).forEach { name -> HallPadChoiceChip(selected = category == name, onClick = { category = name }, label = { Text(name) }, modifier = Modifier.fillMaxWidth()) }
                    }
                    Column(Modifier.weight(1f).fillMaxHeight(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        if (!landscape) {
                            OutlinedTextField(value = query, onValueChange = { query = it }, modifier = Modifier.fillMaxWidth(), singleLine = true, placeholder = { Text("搜索音色") })
                            Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                (listOf("全部") + categories.values.distinct()).forEach { name -> HallPadChoiceChip(selected = category == name, onClick = { category = name }, label = { Text(name) }) }
                            }
                        }
                        LazyColumn(Modifier.fillMaxWidth().weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            items((if (allowFollowGlobal) listOf("跟随全局") else emptyList()) + results, key = { it }) { name ->
                                Surface(onClick = { onSelect(name) }, shape = MaterialTheme.shapes.small, color = if (selected == name) palette.primaryContainer else Color.Transparent, modifier = Modifier.fillMaxWidth()) {
                                    Row(Modifier.fillMaxWidth().heightIn(min = 42.dp).padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
                                        InstrumentIcon(name); Spacer(Modifier.width(10.dp)); Text(name, modifier = Modifier.weight(1f)); if (selected == name) Text("✓", color = palette.primary)
                                    }
                                }
                            }
                            if (results.isEmpty()) item { Text("未找到音色", color = palette.onSurfaceVariant) }
                        }
                    }
                }
            }
        }
    }
}

@Composable
internal fun PresetSummary(state: HallPadState, onOpen: () -> Unit, enabled: Boolean = true) {
    val active = state.presets.firstOrNull { it.id == state.activePresetId }
    val modified = active != null && active.configuration != state.encode()
    OutlinedCard(Modifier.fillMaxWidth()) {
        Row(Modifier.fillMaxWidth().padding(16.dp), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(active?.name ?: "当前配置", fontWeight = FontWeight.SemiBold)
                Text(if (modified) "已修改 · 自动保留当前配置" else "本地配置", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            TextButton(onClick = onOpen, enabled = enabled) { Text("管理预设") }
        }
    }
}

@Composable
internal fun PresetManager(state: HallPadState, onClose: () -> Unit) {
    var nameTarget by remember { mutableStateOf<HallPadPreset?>(null) }
    var naming by remember { mutableStateOf(false) }
    var name by rememberSaveable { mutableStateOf("") }
    var operation by remember { mutableStateOf("") }
    var target by remember { mutableStateOf<HallPadPreset?>(null) }
    if (naming) {
        val valid = state.validName(name, nameTarget?.id)
        AlertDialog(onDismissRequest = { naming = false }, title = { Text(if (nameTarget == null) "另存预设" else "重命名预设") }, text = {
            OutlinedTextField(value = name, onValueChange = { name = it.take(24) }, label = { Text("名称") }, singleLine = true, isError = name.isNotBlank() && !valid, supportingText = { Text(if (name.isNotBlank() && !valid) "名称已存在" else "最多 24 个字符") })
        }, confirmButton = {
            TextButton(onClick = { if (nameTarget == null) state.savePreset(name) else state.renamePreset(nameTarget!!.id, name); naming = false }, enabled = valid) { Text("保存") }
        }, dismissButton = { TextButton(onClick = { naming = false }) { Text("取消") } })
    } else if (operation.isNotEmpty()) {
        val title = when (operation) { "switch" -> "切换预设？"; "update" -> "覆盖预设？"; "delete" -> "删除预设？"; else -> "恢复默认键位？" }
        val message = when (operation) {
            "switch" -> "当前修改尚未保存为预设，切换将替换这些修改。"
            "update" -> "用当前配置覆盖「${target?.name}」。"
            "delete" -> "删除「${target?.name}」，当前配置会保留。"
            else -> "全部 35 个键恢复默认音符、跟随全局音色和力度 100。"
        }
        AlertDialog(onDismissRequest = { operation = "" }, title = { Text(title) }, text = { Text(message) }, confirmButton = {
            TextButton(onClick = {
                when (operation) {
                    "switch" -> target?.let { state.selectPreset(it.id) }
                    "update" -> target?.let { state.updatePreset(it.id) }
                    "delete" -> target?.let { state.deletePreset(it.id) }
                    "reset" -> { state.resetKeys(); onClose() }
                }
                operation = ""
            }) { Text("确认") }
        }, dismissButton = { TextButton(onClick = { operation = "" }) { Text("取消") } })
    } else {
        val palette = MaterialTheme.colorScheme
        var menuId by remember { mutableStateOf<String?>(null) }
        val maxHeight = (LocalConfiguration.current.screenHeightDp * 0.82f).dp
        Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false)) {
            Surface(Modifier.widthIn(max = 560.dp).fillMaxWidth(0.94f).heightIn(max = maxHeight), shape = RoundedCornerShape(28.dp), color = palette.surface, contentColor = palette.onSurface) {
                Column(Modifier.imePadding().padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text("预设库", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                            Text("${state.presets.size} 个预设 · 保存在本机", style = MaterialTheme.typography.bodySmall, color = palette.onSurfaceVariant)
                        }
                        TextButton(onClick = onClose) { Text("完成") }
                    }
                    Button(onClick = { nameTarget = null; name = ""; naming = true }, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)) { Text("＋ 保存当前配置") }
                    LazyColumn(Modifier.fillMaxWidth().weight(1f, fill = false), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        if (state.presets.isEmpty()) item {
                            Column(Modifier.fillMaxWidth().padding(vertical = 32.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text("还没有预设", style = MaterialTheme.typography.titleMedium)
                                Text("保存喜欢的音色与键位，下次一键调用。", style = MaterialTheme.typography.bodySmall, color = palette.onSurfaceVariant)
                            }
                        }
                        items(state.presets, key = { it.id }) { preset ->
                            val selected = preset.id == state.activePresetId
                            val modified = selected && preset.configuration != state.encode()
                            Surface(modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(18.dp), color = if (selected) palette.primaryContainer else palette.surfaceContainerHigh, border = if (selected) androidx.compose.foundation.BorderStroke(1.dp, palette.primary) else null) {
                                Row(Modifier.fillMaxWidth().padding(12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                    Surface(shape = RoundedCornerShape(12.dp), color = if (selected) palette.primary else palette.surface, modifier = Modifier.size(42.dp)) {
                                        Box(contentAlignment = Alignment.Center) { Text(if (selected) "✓" else "♫", color = if (selected) palette.onPrimary else palette.primary) }
                                    }
                                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                        Text(preset.name, fontWeight = FontWeight.SemiBold, maxLines = 2)
                                        Text(if (modified) "当前预设 · 有未覆盖的修改" else if (selected) "当前使用" else "已保存", style = MaterialTheme.typography.bodySmall, color = palette.onSurfaceVariant)
                                    }
                                    if (!selected || modified) TextButton(onClick = {
                                        state.releaseAll()
                                        val current = state.encode()
                                        val active = state.presets.firstOrNull { it.id == state.activePresetId }
                                        if (preset.configuration != current && (active == null || active.configuration != current)) { target = preset; operation = "switch" } else state.selectPreset(preset.id)
                                    }) { Text("应用") }
                                    Box {
                                        TextButton(onClick = { menuId = preset.id }, contentPadding = PaddingValues(8.dp), modifier = Modifier.widthIn(min = 40.dp)) { Text("⋮", fontSize = 24.sp) }
                                        DropdownMenu(expanded = menuId == preset.id, onDismissRequest = { menuId = null }) {
                                            DropdownMenuItem(text = { Text("用当前配置覆盖") }, onClick = { menuId = null; target = preset; operation = "update" })
                                            DropdownMenuItem(text = { Text("重命名") }, onClick = { menuId = null; nameTarget = preset; name = preset.name; naming = true })
                                            DropdownMenuItem(text = { Text("删除", color = palette.error) }, onClick = { menuId = null; target = preset; operation = "delete" })
                                        }
                                    }
                                }
                            }
                        }
                    }
                    HorizontalDivider(color = palette.outlineVariant)
                    TextButton(onClick = { target = null; operation = "reset" }, modifier = Modifier.fillMaxWidth()) { Text("恢复默认键位") }
                }
            }
        }
    }
}

