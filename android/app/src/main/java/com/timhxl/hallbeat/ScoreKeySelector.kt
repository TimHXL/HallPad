package com.timhxl.hallbeat

import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/** 只设置调号，不更改已录制音符的实际音高。 */
@Composable
internal fun ScoreKeySelector(value: ScoreKey, onChange: (ScoreKey) -> Unit, enabled: Boolean = true) {
    var showPicker by remember { mutableStateOf(false) }
    var minor by remember { mutableStateOf(value.minor) }
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text("调号", modifier = Modifier.weight(1f), style = MaterialTheme.typography.labelLarge)
        TextButton(enabled = enabled, onClick = { minor = value.minor; showPicker = true }) { Text("${scoreKeyName(value)} ▾") }
    }
    if (showPicker) AlertDialog(onDismissRequest = { showPicker = false }, title = { Text("选择调号") }, text = {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilterChip(selected = !minor, onClick = { minor = false }, label = { Text("大调") })
                FilterChip(selected = minor, onClick = { minor = true }, label = { Text("小调") })
            }
            (-7..7).toList().chunked(5).forEach { group ->
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    group.forEach { sharps ->
                        val key = ScoreKey(0, sharps, minor)
                        val selected = value.sharps == sharps && value.minor == minor
                        Surface(Modifier.weight(1f).height(42.dp).clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { onChange(key); showPicker = false }, shape = MaterialTheme.shapes.small, color = if (selected) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceContainerHigh) {
                            Box(contentAlignment = Alignment.Center) { Text(scoreKeyName(key).substringBefore(' '), fontFamily = HallPadMono, maxLines = 1) }
                        }
                    }
                }
            }
            Text("调号用于音符命名；音高可在移调中调整。", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }, confirmButton = { TextButton(onClick = { showPicker = false }) { Text("取消") } })
}
