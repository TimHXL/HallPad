package com.timhxl.hallbeat

import androidx.compose.foundation.layout.*
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.sp

/** Fixed header/footer, measured chord text. No scrolling and no implicit line breaks. */
@Composable
internal fun CurrentNotePanel(heading: String, counter: String, notes: List<String>, locations: String,
    durations: String, measure: String, tempo: String, compact: Boolean, modifier: Modifier = Modifier) {
    val palette = MaterialTheme.colorScheme
    val label = MaterialTheme.typography.labelSmall.copy(textAlign = TextAlign.Center, color = palette.onSurfaceVariant)
    val chord = if (notes.isEmpty()) "—" else notes.chunked(2).joinToString("\n") { it.joinToString(" + ") }
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        Column(Modifier.weight(0.16f).fillMaxWidth()) {
            FittedNoteText(heading, label.copy(color = palette.primary), 13f, Modifier.weight(1f).fillMaxWidth())
            FittedNoteText(counter, label.copy(fontFamily = HallPadMono), 12f, Modifier.weight(1f).fillMaxWidth())
        }
        Column(Modifier.weight(0.54f).fillMaxWidth()) {
            FittedNoteText(chord, TextStyle(fontFamily = HallPadMono, fontWeight = FontWeight.Bold,
                color = palette.primary, textAlign = TextAlign.Center), if (compact) 32f else 42f,
                Modifier.weight(0.8f).fillMaxWidth())
            FittedNoteText(locations, label, 12f, Modifier.weight(0.2f).fillMaxWidth())
        }
        Column(Modifier.weight(0.30f).fillMaxWidth()) {
            FittedNoteText(durations, label, 12f, Modifier.weight(1f).fillMaxWidth())
            FittedNoteText(measure, label.copy(fontFamily = HallPadMono), 12f, Modifier.weight(1f).fillMaxWidth())
            FittedNoteText(tempo, label, 12f, Modifier.weight(1f).fillMaxWidth())
        }
    }
}

@Composable
private fun FittedNoteText(text: String, style: TextStyle, maximumSp: Float, modifier: Modifier) {
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    BoxWithConstraints(modifier, contentAlignment = Alignment.Center) {
        val width = with(density) { maxWidth.roundToPx() }.coerceAtLeast(1)
        val height = with(density) { maxHeight.roundToPx() }.coerceAtLeast(1)
        val lines = text.count { it == '\n' } + 1
        val fitted = remember(text, style, maximumSp, width, height, density.density, density.fontScale) {
            fun fits(size: Float): Boolean = !measurer.measure(AnnotatedString(text),
                style = style.copy(fontSize = size.sp, lineHeight = (size * 1.15f).sp),
                softWrap = false, maxLines = lines, overflow = TextOverflow.Clip,
                constraints = Constraints(maxWidth = width, maxHeight = height)).hasVisualOverflow
            var low = 0.1f
            var high = maximumSp
            if (fits(high)) high else {
                repeat(12) {
                    val middle = (low + high) / 2f
                    if (fits(middle)) low = middle else high = middle
                }
                low
            }
        }
        Text(text, style = style.copy(fontSize = fitted.sp, lineHeight = (fitted * 1.15f).sp),
            softWrap = false, maxLines = lines, overflow = TextOverflow.Clip)
    }
}
