package com.timhxl.hallbeat

import android.os.SystemClock
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.graphics.Color
import androidx.compose.foundation.text.input.rememberTextFieldState
import androidx.compose.foundation.text.input.InputTransformation
import androidx.compose.foundation.text.input.TextFieldLineLimits
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import kotlin.math.roundToInt

@Stable
internal class MetronomeUiState {
    var onRemoteChange: (() -> Unit)? = null
    fun submit() { if (!scoreOwned) onRemoteChange?.invoke() }
    var onStopConsole: (() -> Unit)? = null
    var scoreOwned by mutableStateOf(false)
    var scoreReleasing by mutableStateOf(false)
    fun stopConsole() { running = false; beat = -1; transportBeat = null; onStopConsole?.invoke() }
    fun releaseScore() { stopConsole(); scoreOwned = false; scoreReleasing = false }
    var legacyDevice by mutableStateOf(true)
    var sixteenthEmulated = false
    val canRun: Boolean get() = !legacyDevice || signature.substringAfter('/') != "16" || bpm <= 120
    var freeStartedAt: Long? = null
    fun recordingLeadInMs(): Double {
        val origin = freeStartedAt ?: return 0.0
        if (!running || scoreOwned) return 0.0
        val measureMs = 60000.0 / bpm * 4.0 / signature.substringAfter('/').toInt() * beats
        return (SystemClock.elapsedRealtime() - origin).coerceAtLeast(0).toDouble() % measureMs
    }
    var bpm by mutableIntStateOf(120)
    var signature by mutableStateOf("4/4")
    var running by mutableStateOf(false)
    var beat by mutableIntStateOf(-1)
    var transportBeat by mutableStateOf<Double?>(null)
    var restart by mutableIntStateOf(0)
    val beats: Int get() = signature.substringBefore('/').toInt()
}

/** 仅驱动视觉节拍，不创建音频、振动或蓝牙任务。 */
@Composable
internal fun MetronomeClock(state: MetronomeUiState) {
    SideEffect { state.transportBeat?.let { phase -> state.beat = if (state.running) (kotlin.math.floor(phase).toLong() % state.beats).toInt() else -1 } }

    LaunchedEffect(state.running, state.bpm, state.signature, state.transportBeat != null, state.restart) {
        state.beat = -1
        state.freeStartedAt = null
        if (state.running && state.transportBeat == null) {
            val start = SystemClock.elapsedRealtime()
            state.freeStartedAt = start
            // BPM 仍以四分音符计；拍值控制每一次指示的时长。
            val denominator = state.signature.substringAfter('/').toInt()
            val interval = 60000.0 / state.bpm * 4.0 / denominator
            while (true) {
                val elapsed = SystemClock.elapsedRealtime() - start
                val tick = (elapsed / interval).toLong()
                state.beat = (tick % state.beats).toInt()
                delay(((tick + 1) * interval - elapsed).toLong().coerceAtLeast(1L))
            }
        }
    }
}

@Composable
internal fun MetronomeCard(state: MetronomeUiState, settingsEnabled: Boolean = true, playbackEnabled: Boolean = true, compact: Boolean = false, onSubmit: () -> Unit = state::submit, tempoEnabled: Boolean = true, signatureEnabled: Boolean = true) {
    val canEdit = settingsEnabled && !state.scoreOwned
    val palette = MaterialTheme.colorScheme
    val focus = androidx.compose.ui.platform.LocalFocusManager.current
    val bpmField = rememberTextFieldState(state.bpm.toString())
    val beatsField = rememberTextFieldState(state.beats.toString())
    var editingBeats by remember { mutableStateOf(false) }
    var denominatorMenu by remember { mutableStateOf(false) }
    var editingTempo by remember { mutableStateOf(false) }
    LaunchedEffect(state.bpm) { if (!editingTempo) bpmField.edit { replace(0, length, state.bpm.toString()) } }
    LaunchedEffect(state.beats) { if (!editingBeats) beatsField.edit { replace(0, length, state.beats.toString()) } }
    fun commitBeats(submit: Boolean = true) { if (!canEdit || state.scoreOwned) { editingBeats = false; return }; val previous = state.beats; val count = (beatsField.text.toString().toIntOrNull() ?: state.beats).coerceIn(1, 12); state.signature = "$count/${state.signature.substringAfter('/')}"; beatsField.edit { replace(0, length, count.toString()) }; editingBeats = false; if (submit && previous != count) onSubmit() }
    fun commitTempo(submit: Boolean = true, releaseFocus: Boolean = true) { if (!canEdit || state.scoreOwned) { editingTempo = false; return }; state.bpm = (bpmField.text.toString().toIntOrNull() ?: state.bpm).coerceIn(30, 240); bpmField.edit { replace(0, length, state.bpm.toString()) }; editingTempo = false; if (submit) onSubmit(); if (releaseFocus) focus.clearFocus() }
    Column(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Column(Modifier.weight(1f)) {
                Text("速度 · 拍/分钟", style = MaterialTheme.typography.labelLarge, color = palette.onSurfaceVariant)
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                    BasicTextField(state = bpmField, readOnly = !(canEdit && tempoEnabled), inputTransformation = InputTransformation { if (length > 3 || asCharSequence().any { it !in '0'..'9' }) revertAllChanges() }, modifier = Modifier.width(78.dp).numericFocusTarget().onFocusChanged { if (it.isFocused) editingTempo = true else if (editingTempo) commitTempo(releaseFocus = false) }, textStyle = MaterialTheme.typography.displaySmall.copy(fontSize = 40.sp, fontFamily = HallPadMono, fontWeight = FontWeight.Bold, color = if (canEdit && tempoEnabled) palette.onSurface else palette.onSurface.copy(alpha = 0.38f)), lineLimits = TextFieldLineLimits.SingleLine, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number, imeAction = ImeAction.Done), onKeyboardAction = { commitTempo() })
                    Text("BPM", style = MaterialTheme.typography.labelLarge, color = palette.primary)
                }
            }
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text("拍号", style = MaterialTheme.typography.labelMedium, color = palette.onSurfaceVariant)
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    BasicTextField(state = beatsField, readOnly = !(canEdit && signatureEnabled), inputTransformation = InputTransformation { if (length > 2 || asCharSequence().any { it !in '0'..'9' }) revertAllChanges() }, modifier = Modifier.width(36.dp).numericFocusTarget().border(1.dp, palette.outlineVariant, RoundedCornerShape(10.dp)).padding(vertical = 10.dp).onFocusChanged { if (it.isFocused) editingBeats = true else if (editingBeats) commitBeats() }, textStyle = MaterialTheme.typography.titleMedium.copy(fontFamily = HallPadMono, color = if (canEdit && signatureEnabled) palette.onSurface else palette.onSurface.copy(alpha = 0.38f), textAlign = androidx.compose.ui.text.style.TextAlign.Center), lineLimits = TextFieldLineLimits.SingleLine, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number, imeAction = ImeAction.Done), onKeyboardAction = { commitBeats(); focus.clearFocus() })
                    Text("/", color = palette.onSurfaceVariant)
                    Box {
                        TextButton(enabled = canEdit && signatureEnabled, onClick = { commitBeats(); denominatorMenu = true }, contentPadding = PaddingValues(horizontal = 6.dp), modifier = Modifier.width(48.dp)) { Text("${state.signature.substringAfter('/')} ▾", fontFamily = HallPadMono, maxLines = 1) }
                        DropdownMenu(expanded = denominatorMenu && canEdit && !state.scoreOwned, onDismissRequest = { denominatorMenu = false }) { listOf(2, 4, 8, 16).forEach { denominator -> DropdownMenuItem(text = { Text("$denominator 分音符") }, onClick = { state.signature = "${state.beats}/$denominator"; denominatorMenu = false; onSubmit() }) } }
                    }
                }
            }
            FilledIconButton(enabled = playbackEnabled && !state.scoreOwned && (state.canRun || state.running), onClick = { commitBeats(false); commitTempo(false); state.running = !state.running; onSubmit() }, modifier = Modifier.size(52.dp), shape = CircleShape) { Icon(painterResource(if (state.running) R.drawable.ic_pause else R.drawable.ic_play), contentDescription = if (state.running) "停止节拍" else "开始节拍", modifier = Modifier.size(32.dp)) }
        }
        if (!state.canRun) Text("设备播放 16 分音符时，速度最高 120 BPM", style = MaterialTheme.typography.bodySmall, color = palette.onSurfaceVariant)
        PendulumDisplay(state, compact)
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = { state.bpm = (state.bpm - 1).coerceAtLeast(30); bpmField.edit { replace(0, length, state.bpm.toString()) }; onSubmit() }, enabled = canEdit && tempoEnabled && state.bpm > 30, modifier = Modifier.size(44.dp), contentPadding = PaddingValues(0.dp), shape = CircleShape) { Text("−", fontSize = 24.sp) }
            StableParameterSlider(state.bpm.toFloat(), { state.bpm = it.roundToInt(); bpmField.edit { replace(0, length, state.bpm.toString()) }; editingTempo = false }, canEdit && tempoEnabled, Modifier.weight(1f), range = 30f..240f, onFinished = onSubmit)
            OutlinedButton(onClick = { state.bpm = (state.bpm + 1).coerceAtMost(240); bpmField.edit { replace(0, length, state.bpm.toString()) }; onSubmit() }, enabled = canEdit && tempoEnabled && state.bpm < 240, modifier = Modifier.size(44.dp), contentPadding = PaddingValues(0.dp), shape = CircleShape) { Text("+", fontSize = 24.sp) }
        }

    }
}

/** 固定拍点位置，当前拍使用高对比色与大号数字，避免快速播放时来回移动。 */
@Composable
private fun PendulumDisplay(state: MetronomeUiState, compact: Boolean = false) {
    val palette = MaterialTheme.colorScheme
    Surface(color = palette.surfaceContainerHigh, shape = RoundedCornerShape(24.dp)) {
        Column(Modifier.fillMaxWidth().padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (!compact) Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(if (state.running) "当前拍" else "准备开始", modifier = Modifier.weight(1f), style = MaterialTheme.typography.labelLarge, color = palette.onSurfaceVariant)
                Text(if (state.running && state.beat >= 0) "${state.beat + 1} / ${state.beats}" else "— / ${state.beats}", fontFamily = HallPadMono, fontSize = 26.sp, fontWeight = FontWeight.Bold, color = palette.primary)
            }
            (0 until state.beats).chunked(6).forEach { group ->
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    group.forEach { index ->
                        val active = state.running && state.beat == index
                        val fill = if (active) { if (index == 0) Color(0xFFFFD65A) else Color(0xFF69EDB2) } else palette.surface
                        Surface(Modifier.weight(1f).height(32.dp), color = fill, shape = RoundedCornerShape(12.dp), border = androidx.compose.foundation.BorderStroke(if (active) 2.dp else 1.dp, if (active) palette.onSurface else palette.outlineVariant)) {
                            Box(contentAlignment = Alignment.Center) { Text("${index + 1}", fontFamily = HallPadMono, fontWeight = FontWeight.Bold, color = if (active) Color(0xFF17251C) else palette.onSurfaceVariant) }
                        }
                    }
                }
            }
        }
    }
}
