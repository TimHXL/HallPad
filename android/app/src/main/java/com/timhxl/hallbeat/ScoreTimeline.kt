package com.timhxl.hallbeat

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.focusable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.*
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.IntOffset
import kotlin.math.roundToInt

/** 细轨时间轴：触摸区域保持 48dp，A/B 直接以竖线标在实际时间位置。 */
@Composable
internal fun ScoreTimeline(position: Double, duration: Double, loopStart: Double?, loopEnd: Double?, onSeek: (Double) -> Unit, onSeekFinished: () -> Unit) {
    val palette = MaterialTheme.colorScheme
    val latestSeek by rememberUpdatedState(onSeek)
    val latestFinished by rememberUpdatedState(onSeekFinished)
    val safeDuration = duration.coerceAtLeast(0.001)
    val fraction = (position / safeDuration).toFloat().coerceIn(0f, 1f)
    val aColor = palette.primary
    val bColor = Color(0xFFD99A13)
    Column(Modifier.fillMaxWidth()) {
        BoxWithConstraints(Modifier.fillMaxWidth().height(48.dp).semantics {
            contentDescription = "演奏进度"
            progressBarRangeInfo = ProgressBarRangeInfo(fraction, 0f..1f)
            stateDescription = "${timelineTime(position)} / ${timelineTime(duration)}"
            setProgress { value -> latestSeek(value.coerceIn(0f, 1f) * duration); latestFinished(); true }
        }.focusable().pointerInput(duration) {
            awaitEachGesture {
                val down = awaitFirstDown(requireUnconsumed = false)
                val padding = 12.dp.toPx()
                fun seek(x: Float) { latestSeek(((x - padding) / (size.width - padding * 2).coerceAtLeast(1f)).coerceIn(0f, 1f) * duration) }
                seek(down.position.x); down.consume()
                try {
                    var pressed = true
                    while (pressed) {
                        val event = awaitPointerEvent()
                        val change = event.changes.firstOrNull { it.id == down.id } ?: break
                        seek(change.position.x); pressed = change.pressed; change.consume()
                    }
                } finally { latestFinished() }
            }
        }) {
            Canvas(Modifier.fillMaxSize()) {
                val pad = 12.dp.toPx(); val width = (size.width - pad * 2).coerceAtLeast(1f); val y = size.height / 2
                fun x(time: Double): Float = pad + width * (time / safeDuration).toFloat().coerceIn(0f, 1f)
                drawLine(palette.outlineVariant, Offset(pad, y), Offset(size.width - pad, y), 3.dp.toPx())
                if (loopStart != null && loopEnd != null) drawLine(palette.primary.copy(alpha = 0.3f), Offset(x(loopStart), y), Offset(x(loopEnd), y), 9.dp.toPx())
                drawLine(palette.primary, Offset(pad, y), Offset(pad + fraction * width, y), 3.dp.toPx())
                loopStart?.let { drawLine(aColor, Offset(x(it), y - 12.dp.toPx()), Offset(x(it), y + 12.dp.toPx()), 3.dp.toPx()) }
                loopEnd?.let { drawLine(bColor, Offset(x(it), y - 12.dp.toPx()), Offset(x(it), y + 12.dp.toPx()), 3.dp.toPx()) }
                drawCircle(palette.background, 8.dp.toPx(), Offset(pad + fraction * width, y))
                drawCircle(palette.primary, 5.dp.toPx(), Offset(pad + fraction * width, y))
            }
            loopStart?.let { time -> Text("A", modifier = Modifier.offset { IntOffset((12.dp.toPx() + (maxWidth - 24.dp).toPx() * (time / safeDuration).toFloat().coerceIn(0f, 1f) - 5.dp.toPx()).roundToInt(), 0) }, style = MaterialTheme.typography.labelSmall, color = aColor) }
            loopEnd?.let { time -> Text("B", modifier = Modifier.offset { IntOffset((12.dp.toPx() + (maxWidth - 24.dp).toPx() * (time / safeDuration).toFloat().coerceIn(0f, 1f) - 5.dp.toPx()).roundToInt(), 32.dp.roundToPx()) }, style = MaterialTheme.typography.labelSmall, color = bColor) }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(timelineTime(position), style = MaterialTheme.typography.labelMedium, fontFamily = HallPadMono, color = palette.onSurfaceVariant)
            Text(timelineTime(duration), style = MaterialTheme.typography.labelMedium, fontFamily = HallPadMono, color = palette.onSurfaceVariant)
        }
    }
}

private fun timelineTime(seconds: Double): String { val value = seconds.toInt().coerceAtLeast(0); return "%d:%02d".format(value / 60, value % 60) }
