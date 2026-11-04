package com.timhxl.hallbeat

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.res.painterResource
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.DialogWindowProvider

import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.input.rememberTextFieldState
import androidx.compose.foundation.text.input.InputTransformation
import androidx.compose.foundation.text.input.TextFieldLineLimits
import androidx.compose.ui.text.input.ImeAction

@Suppress("DEPRECATION")
@Composable
internal fun RecordingPage(recording: FpgaRecording, metronome: MetronomeUiState, ready: Boolean, metronomeSupported: Boolean, onStart: (Int, Int, Int) -> Unit, onSave: (String, ScoreKey) -> String?, onClose: () -> Unit) {
    val title = rememberTextFieldState("录制 " + java.text.SimpleDateFormat("MM-dd HH:mm", java.util.Locale.getDefault()).format(java.util.Date()))
    val palette = MaterialTheme.colorScheme
    var error by remember { mutableStateOf("") }
    val locked = recording.recording || recording.count > 0
    val unit = metronome.signature.substringAfter('/').toInt()
    DisposableEffect(Unit) { onDispose { if (!recording.recording && metronome.running) { metronome.running = false; metronome.submit() } } }
    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        val view = LocalView.current
        val focus = LocalFocusManager.current
        val keyboard = LocalSoftwareKeyboardController.current
        val typing = WindowInsets.ime.getBottom(LocalDensity.current) > 0
        SideEffect {
            (view.parent as? DialogWindowProvider)?.window?.let { window ->
                androidx.core.view.WindowCompat.setDecorFitsSystemWindows(window, false)
                window.setSoftInputMode(android.view.WindowManager.LayoutParams.SOFT_INPUT_ADJUST_NOTHING)
                window.setBackgroundDrawable(android.graphics.drawable.ColorDrawable(palette.background.toArgb()))
                window.isNavigationBarContrastEnforced = false
                window.isStatusBarContrastEnforced = false
                window.navigationBarColor = android.graphics.Color.TRANSPARENT
                window.statusBarColor = android.graphics.Color.TRANSPARENT
                val controller = androidx.core.view.WindowCompat.getInsetsController(window, view)
                controller.isAppearanceLightNavigationBars = palette.background.luminance() > 0.5f
                controller.isAppearanceLightStatusBars = palette.background.luminance() > 0.5f
            }
        }
        Surface(Modifier.fillMaxSize().dismissNumericFocusOutside(), color = palette.background) {
            Column(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.systemBars.union(WindowInsets.displayCutout)).padding(horizontal = 20.dp, vertical = 8.dp)) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onClick = onClose) { Icon(painterResource(R.drawable.ic_back), contentDescription = "返回") }
                    Text("FPGA 录制", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                    if (typing) TextButton(onClick = { keyboard?.hide(); focus.clearFocus() }) { Text("完成") }
                }
                BoxWithConstraints(Modifier.weight(1f).fillMaxWidth().padding(top = 8.dp)) {
                    val contentWidth = maxWidth
                    val contentHeight = maxHeight
                    val compact = contentHeight < 520.dp
                    if (contentWidth >= 560.dp) {
                        Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(20.dp)) {
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                RecordingTitle(title)
                                RecordingTimer(recording, Modifier.fillMaxWidth().height((contentHeight * 0.32f).coerceIn(64.dp, 112.dp)))
                                ScoreKeySelector(recording.selectedKey, { recording.selectedKey = it })
                            }
                            Surface(Modifier.weight(1f), shape = RoundedCornerShape(24.dp), color = palette.surfaceContainerLow) {
                                Column(Modifier.padding(horizontal = 12.dp)) { MetronomeCard(metronome, settingsEnabled = !locked, playbackEnabled = ready && metronomeSupported, compact = true, onSubmit = { if (ready && metronomeSupported) metronome.submit() }) }
                            }
                        }
                    } else {
                        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(if (compact) 8.dp else 14.dp)) {
                            RecordingTitle(title)
                            RecordingTimer(recording, Modifier.fillMaxWidth().height((contentHeight * 0.18f).coerceIn(64.dp, 112.dp)))
                            Surface(Modifier.fillMaxWidth(), shape = RoundedCornerShape(24.dp), color = palette.surfaceContainerLow) {
                                Column(Modifier.padding(horizontal = 12.dp)) { MetronomeCard(metronome, settingsEnabled = !locked, playbackEnabled = ready && metronomeSupported, compact = compact, onSubmit = { if (ready && metronomeSupported) metronome.submit() }) }
                            }
                            ScoreKeySelector(recording.selectedKey, { recording.selectedKey = it })
                        }
                    }
                }
                Text(error.ifEmpty { recording.reason.ifEmpty { if (ready) "在设备上弹奏，完成后保存。" else "连接设备后可开始录制。" } }, color = if (error.isEmpty()) palette.onSurfaceVariant else palette.error, style = MaterialTheme.typography.bodySmall, maxLines = 1)
                Row(Modifier.fillMaxWidth().padding(top = 8.dp, bottom = 4.dp), horizontalArrangement = Arrangement.spacedBy(12.dp, Alignment.End)) {
                        TextButton(onClick = { recording.clear(); error = ""; onClose() }) { Text("取消") }
                        if (locked) Button(modifier = Modifier.weight(1f).height(48.dp), enabled = title.text.trim().isNotEmpty(), onClick = { error = onSave(title.text.toString().trim(), recording.selectedKey) ?: "" }) { Text(if (recording.recording) "停止并保存" else "保存曲目") }
                        else Button(modifier = Modifier.weight(1f).height(48.dp), enabled = ready && title.text.trim().isNotEmpty(), onClick = { error = ""; onStart(metronome.bpm, metronome.beats, unit) }) { Text("开始录制") }
                }
            }
        }
    }
}

/** 曲名输入保持在布局中，避免键盘切换时丢失焦点。 */
@Composable
private fun RecordingTitle(state: androidx.compose.foundation.text.input.TextFieldState) {
    val focus = LocalFocusManager.current
    val keyboard = LocalSoftwareKeyboardController.current
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text("曲目名称", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        BasicTextField(state = state, inputTransformation = InputTransformation { if (length > 100) revertAllChanges() }, modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp), textStyle = MaterialTheme.typography.titleMedium.copy(color = MaterialTheme.colorScheme.onSurface), lineLimits = TextFieldLineLimits.SingleLine, keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done), onKeyboardAction = { keyboard?.hide(); focus.clearFocus() })
        HorizontalDivider(color = MaterialTheme.colorScheme.outline)
    }
}

@Composable
private fun RecordingTimer(recording: FpgaRecording, modifier: Modifier) {
    Surface(modifier, shape = RoundedCornerShape(20.dp), color = MaterialTheme.colorScheme.surfaceContainerLow) {
        Row(Modifier.fillMaxSize().padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Column(Modifier.weight(1f)) {
                Text(if (recording.recording) "正在录制" else if (recording.count > 0) "录制完成" else "准备录制", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
                Text("${recording.count} 个音符", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            val seconds = recording.elapsedMs / 1000
            Text("%02d:%02d".format(seconds / 60, seconds % 60), fontFamily = HallPadMono, fontSize = 36.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
        }
    }
}
