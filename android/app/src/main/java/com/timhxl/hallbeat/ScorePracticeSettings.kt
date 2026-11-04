package com.timhxl.hallbeat

import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.foundation.basicMarquee
import androidx.compose.foundation.clickable
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

internal data class ScorePracticeSettingsModel(val tracks: List<ScoreTrack>, val trackIndex: Int, val transpose: Int, val following: Boolean, val canLower: Boolean, val canRaise: Boolean, val keyLabel: String, val mappedNotes: List<String>, val hasBackup: Boolean, val canApply: Boolean, val keySignature: ScoreKey)

/** 设置界面独立编译，不在演奏页的大方法中嵌套声明局部可组合函数。 */
@Composable
internal fun ScorePracticeSettings(model: ScorePracticeSettingsModel, onTrack: (Int) -> Unit, onRenameTrack: (Int, String) -> Unit, onTranspose: (Int) -> Unit, onApply: () -> Unit, onRestore: () -> Unit, onKey: (ScoreKey) -> Unit, onClose: () -> Unit, downloadEnabled: Boolean = false, onDownload: (() -> Unit)? = null) {
    PracticeSettingsPage(onClose = onClose, leadingAction = {
        onDownload?.let { action ->
            TextButton(enabled = downloadEnabled, onClick = action) { Text("下载到 SD", maxLines = 1) }
        }
    }) { wide, availableHeight ->
        val rowHeight = ((availableHeight - if (wide) 208.dp else 398.dp) / 5).coerceIn(18.dp, 36.dp)
        if (wide) {
            Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(10.dp)) { ScoreTrackSettings(model, onTrack, onRenameTrack); ScoreTransposeSettings(model, onTranspose, onKey) }
                Box(Modifier.weight(1f)) { ScoreKeySettings(model, rowHeight, onApply, onRestore) }
            }
        } else {
            Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(10.dp)) { ScoreTrackSettings(model, onTrack, onRenameTrack); ScoreTransposeSettings(model, onTranspose, onKey); ScoreKeySettings(model, rowHeight, onApply, onRestore) }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ScoreTrackSettings(model: ScorePracticeSettingsModel, onTrack: (Int) -> Unit, onRenameTrack: (Int, String) -> Unit) {
    val selected = model.tracks.indexOfFirst { it.index == model.trackIndex }.coerceAtLeast(0)
    PracticeSettingsSection("练习音轨") {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            TextButton(enabled = !model.following && selected > 0, onClick = { model.tracks.getOrNull(selected - 1)?.let { onTrack(it.index) } }, contentPadding = PaddingValues(0.dp), modifier = Modifier.width(48.dp)) { Text("上一轨", maxLines = 1) }
            Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                val track = model.tracks.getOrNull(selected)
                if (track != null) EditableTrackName(track.index, track.name, !model.following) { onRenameTrack(track.index, it) }
                Text("${selected + 1} / ${model.tracks.size}", fontFamily = HallPadMono, style = MaterialTheme.typography.labelSmall)
            }
            TextButton(enabled = !model.following && selected < model.tracks.lastIndex, onClick = { model.tracks.getOrNull(selected + 1)?.let { onTrack(it.index) } }, contentPadding = PaddingValues(0.dp), modifier = Modifier.width(48.dp)) { Text("下一轨", maxLines = 1) }
        }
    }
}

@Composable
private fun ScoreTransposeSettings(model: ScorePracticeSettingsModel, onTranspose: (Int) -> Unit, onKey: (ScoreKey) -> Unit) {
    PracticeSettingsSection("调号与移调") {
        ScoreKeySelector(model.keySignature, onKey, enabled = !model.following)
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            OutlinedButton(enabled = !model.following && model.canLower, onClick = { onTranspose(-1) }) { Text("−") }
            Text(if (model.transpose == 0) "原始音高" else if (model.transpose > 0) "升高 ${model.transpose} 个半音" else "降低 ${-model.transpose} 个半音", modifier = Modifier.weight(1f), textAlign = TextAlign.Center)
            OutlinedButton(enabled = !model.following && model.canRaise, onClick = { onTranspose(1) }) { Text("+") }
        }
    }
}

@Composable
private fun ScoreKeySettings(model: ScorePracticeSettingsModel, rowHeight: androidx.compose.ui.unit.Dp, onApply: () -> Unit, onRestore: () -> Unit) {
    PracticeSettingsSection("键位方案") {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("${model.keyLabel} · 35 键", modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
            TextButton(enabled = !model.following && model.canApply, onClick = onApply) { Text("应用键位") }
        }
        Column(Modifier.fillMaxWidth().border(1.dp, MaterialTheme.colorScheme.outlineVariant)) {
            repeat(5) { row -> Row(Modifier.fillMaxWidth()) { repeat(7) { column -> Box(Modifier.weight(1f).height(rowHeight).border(0.5.dp, MaterialTheme.colorScheme.outlineVariant), contentAlignment = Alignment.Center) { Text(model.mappedNotes.getOrElse(row * 7 + column) { "" }, fontFamily = HallPadMono, fontSize = 12.sp, maxLines = 1) } } } }
        }
        if (model.hasBackup) TextButton(enabled = !model.following && model.canApply, onClick = onRestore) { Text("恢复原键位") }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun EditableTrackName(id: Int, name: String, enabled: Boolean, onSave: (String) -> Unit) {
    var editing by remember(id) { mutableStateOf(false) }
    var hadFocus by remember(id) { mutableStateOf(false) }
    var value by remember(id) { mutableStateOf(TextFieldValue(name)) }
    val requester = remember { FocusRequester() }
    val focus = LocalFocusManager.current
    val keyboard = LocalSoftwareKeyboardController.current
    fun finish() {
        if (!editing) return
        editing = false
        val clean = value.text.trim().take(100)
        if (clean.isNotEmpty() && clean != name) onSave(clean)
        focus.clearFocus(); keyboard?.hide()
    }
    androidx.activity.compose.BackHandler(editing) { finish() }
    LaunchedEffect(editing) { if (editing) { requester.requestFocus(); keyboard?.show() } }
    if (editing) AlertDialog(onDismissRequest = { finish() }, title = { Text("重命名练习音轨") }, text = { OutlinedTextField(value = value, onValueChange = { if (it.text.length <= 100) value = it }, singleLine = true,
        modifier = Modifier.fillMaxWidth().focusRequester(requester).onFocusChanged { if (it.isFocused) hadFocus = true else if (hadFocus) finish() },
        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done), keyboardActions = KeyboardActions(onDone = { finish() })) }, confirmButton = { TextButton(onClick = { finish() }) { Text("完成") } })
    Text(name, maxLines = 1, modifier = Modifier.fillMaxWidth().basicMarquee(iterations = Int.MAX_VALUE).clickable(enabled = enabled) {
        hadFocus = false; value = TextFieldValue(name, TextRange(0, name.length)); editing = true
    })
}

@Composable
internal fun SendKeyPreviewDialog(scheme: Boolean, label: String, notes: List<String>, missingNotes: List<String>, onCancel: () -> Unit, onConfirm: () -> Unit, onContinue: () -> Unit) {
    AlertDialog(onDismissRequest = onCancel, title = { Text(if (scheme) "存在未分配音高，是否应用键位？" else "确定使用这个键位吗？") }, text = {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            if (!scheme) Text("缺少的音高：" + missingNotes.joinToString("、"), style = MaterialTheme.typography.bodyLarge)
            Text(if (scheme) "$label · 键位方案" else "保留原有音高，缺少的音高从右上角借用空闲键", style = MaterialTheme.typography.bodyLarge)
            Column(Modifier.fillMaxWidth()) {
                repeat(5) { row -> Row(Modifier.fillMaxWidth()) {
                    repeat(7) { column -> Box(Modifier.weight(1f).height(34.dp).border(0.5.dp, MaterialTheme.colorScheme.outlineVariant), contentAlignment = Alignment.Center) {
                        Text(notes[row * 7 + column], fontFamily = HallPadMono, fontSize = 10.sp, maxLines = 1)
                    } }
                } }
            }
        }
    }, confirmButton = { TextButton(onClick = onConfirm) { Text(if (scheme) "是" else "确认") } }, dismissButton = {
        Row { TextButton(onClick = onCancel) { Text("取消") }
            if (scheme) TextButton(onClick = onContinue) { Text("否") }
        }
    })
}
