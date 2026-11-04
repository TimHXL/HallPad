package com.timhxl.hallbeat

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp

/** 统一线宽的乐器矢量图标，随明暗主题着色。 */
@Composable
internal fun InstrumentIcon(name: String, modifier: Modifier = Modifier) {
    val color = MaterialTheme.colorScheme.primary
    Canvas(modifier.size(28.dp).semantics { contentDescription = name }) {
        scale(size.width / 28f, size.height / 28f, pivot = Offset.Zero) {
            fun line(x: Float, y: Float, xx: Float, yy: Float) { drawLine(color, Offset(x, y), Offset(xx, yy), 1.6f, StrokeCap.Round) }
            fun circle(x: Float, y: Float, radius: Float) { drawCircle(color, radius, Offset(x, y), style = Stroke(1.6f)) }
            when (name) {
                "钢琴", "风琴", "电钢琴" -> {
                    drawRect(color, Offset(3f, 10f), Size(22f, 13f), style = Stroke(1.6f))
                    for (x in listOf(8f, 13f, 18f)) line(x, 11f, x, 22f)
                    for (x in listOf(7f, 12f, 17f, 22f)) drawRect(color, Offset(x, 10f), Size(2f, 6f))
                    if (name == "钢琴") { line(3f, 8f, 23f, 4f); line(23f, 4f, 25f, 8f) }
                    if (name == "风琴") for (i in 0..4) line(5f + i * 4, 7f, 5f + i * 4, 3f + kotlin.math.abs(i - 2))
                    if (name == "电钢琴") { line(15f, 2f, 11f, 6f); line(11f, 6f, 17f, 6f); line(17f, 6f, 14f, 9f) }
                }
                "钟琴" -> {
                    val bell = Path().apply { moveTo(5f, 20f); lineTo(8f, 16f); lineTo(8f, 10f); cubicTo(8f, 2f, 20f, 2f, 20f, 10f); lineTo(20f, 16f); lineTo(23f, 20f); close() }
                    drawPath(bell, color, style = Stroke(1.6f)); circle(14f, 23f, 2f)
                }
                "木琴", "马林巴" -> {
                    for (i in 0..4) drawRect(color, Offset(3f + i * 4.5f, 8f + i), Size(3f, 16f - i * 2), style = Stroke(1.2f))
                    line(5f, 3f, 15f, 12f); circle(4f, 3f, if (name == "马林巴") 2f else 1f)
                    if (name == "马林巴") for (i in 0..3) line(6f + i * 5f, 23f, 6f + i * 5f, 26f)
                }
                "小军鼓" -> {
                    drawOval(color, Offset(4f, 8f), Size(20f, 7f), style = Stroke(1.6f))
                    line(4f, 12f, 4f, 22f); line(24f, 12f, 24f, 22f); line(4f, 22f, 24f, 22f)
                    line(7f, 15f, 11f, 21f); line(11f, 21f, 16f, 15f); line(16f, 15f, 21f, 21f)
                    line(5f, 3f, 18f, 9f); line(23f, 3f, 13f, 9f)
                }
                "长笛" -> {
                    line(4f, 24f, 23f, 5f); line(7f, 26f, 26f, 7f); line(4f, 24f, 7f, 26f); line(23f, 5f, 26f, 7f)
                    for (i in 0..4) circle(10f + i * 2.7f, 20f - i * 2.7f, 0.8f)
                }
                "拨弦", "贝斯", "小提琴", "弦乐" -> {
                    circle(10f, 20f, if (name == "贝斯") 6f else 5f); circle(14f, 14f, 3.5f)
                    line(13f, 16f, 23f, 3f); line(15f, 18f, 25f, 5f); line(23f, 3f, 25f, 5f)
                    if (name == "小提琴" || name == "弦乐") line(4f, 5f, 23f, 24f)
                    if (name == "弦乐") line(2f, 9f, 19f, 26f)
                    if (name == "拨弦") circle(10f, 20f, 1.5f)
                    if (name == "贝斯") line(7f, 23f, 21f, 5f)
                }
                else -> { line(11f, 20f, 11f, 6f); line(11f, 6f, 21f, 4f); circle(8f, 21f, 3f) }
            }
        }
    }
}
