package com.timhxl.hallbeat

import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
internal fun PracticeControls(controller: PracticeController, canSend: Boolean, uploadedMatches: Boolean, busy: Boolean = false, onSend: () -> Unit, onStart: () -> Unit) {
    val ui by controller.state.collectAsState()
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            val sending = ui.phase in listOf("UPLOADING", "VERIFYING")
            val following = ui.phase in listOf("RUNNING", "PAUSED", "STARTING")
            Box(Modifier.weight(1f).height(44.dp), contentAlignment = Alignment.Center) {
                if (ui.phase == "UPLOADING" && ui.totalBytes > 0) {
                    LinearProgressIndicator(progress = { (ui.transferred.toFloat() / ui.totalBytes).coerceIn(0f, 1f) }, modifier = Modifier.fillMaxSize().clip(CircleShape), color = MaterialTheme.colorScheme.primary.copy(alpha = 0.24f), trackColor = androidx.compose.ui.graphics.Color.Transparent)
                }
                OutlinedButton(onClick = { if (sending) controller.cancel() else if (following) controller.stop() else onSend() }, enabled = sending || (canSend && !busy && ui.phase != "STARTING"), modifier = Modifier.fillMaxSize()) {
                    if (ui.phase == "VERIFYING") Text("正在校验 · 取消", maxLines = 1)
                    else Text(if (following) "结束练习" else if (sending) "${(ui.transferred.toFloat() / ui.totalBytes.coerceAtLeast(1) * 100).toInt()}% · 取消" else if (busy) "正在准备发送…" else "发送到 FPGA", maxLines = 1)
                }
            }
            Button(onClick = { if (following) { if (ui.phase == "RUNNING") controller.pause() else controller.resume() } else onStart() }, enabled = canSend && !busy && if (following) ui.phase != "STARTING" else uploadedMatches && ui.phase in listOf("READY", "STOPPED", "FINISHED"), modifier = Modifier.weight(1f).height(44.dp)) { Text(if (following) { if (ui.phase == "PAUSED") "继续练习" else "暂停练习" } else "开始跟随", maxLines = 1) }
        }
        if (ui.error.isNotBlank() && !ui.error.startsWith("请先配置键位")) Text(ui.error, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
        if (!canSend) Text("跟随练习需要已连接的兼容设备", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)

    }
}

@Composable
internal fun PracticeLiveBar(controller: PracticeController, demo: Boolean, onDemoStrike: () -> Unit) {
    val ui by controller.state.collectAsState()
    if (ui.phase == "ERROR") { Text(ui.error, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall); return }
    if (ui.phase !in listOf("STARTING", "RUNNING", "PAUSED", "FINISHED")) return
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(if (ui.phase == "PAUSED") "跟随已暂停" else if (ui.phase == "FINISHED") "练习完成" else "已完成 ${ui.correct} 组 · 错按 ${ui.wrong} 次", modifier = Modifier.weight(1f), style = MaterialTheme.typography.labelMedium, maxLines = 1)
        if (demo && ui.phase == "RUNNING") TextButton(onClick = onDemoStrike) { Text("模拟弹奏") }
        if (ui.phase in listOf("RUNNING", "PAUSED")) TextButton(onClick = { controller.stop() }) { Text("结束") }
    }
}

@Composable
internal fun PracticeResultDialog(result: PracticeResult, onClose: () -> Unit) {
    AlertDialog(onDismissRequest = onClose, title = { Text("练习结果") }, text = {
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("${result.score} 分", fontSize = 40.sp, fontFamily = HallPadMono, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary)
            if (result.demo) Text("演示练习", style = MaterialTheme.typography.labelMedium)
            ResultLine("音符组", result.total.toString())
            ResultLine("正确完成", result.correct.toString())
            ResultLine("未完成", result.missed.toString())
            ResultLine("错按次数", result.wrong.toString())
            ResultLine("平均时差", if (result.timingCount == 0) "—" else "${result.absoluteTimingMs / result.timingCount} ms")
            ResultLine("用时", formatScoreTime(result.elapsedMs / 1000.0))
        }
    }, confirmButton = { TextButton(onClick = onClose) { Text("完成") } })
}

@Composable
private fun ResultLine(label: String, value: String) { Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) { Text(label); Text(value, fontFamily = HallPadMono) } }
