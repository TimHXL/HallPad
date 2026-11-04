package com.timhxl.hallbeat

import androidx.compose.foundation.layout.*
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** 音名与采集值参与同一个纵向布局，横屏矮琴键也不会因上下绝对定位而重叠。 */
@Composable
internal fun KeyboardKeyLabels(note: String, adc: Int?, foreground: Color, expanded: Boolean) {
    BoxWithConstraints(Modifier.fillMaxSize().padding(horizontal = 4.dp, vertical = 2.dp)) {
        val contentHeight = maxHeight
        val compact = contentHeight < 38.dp
        val noteSize = if (expanded && !compact) 16.sp else if (contentHeight < 26.dp) 11.sp else 13.sp
        val adcSize = if (expanded && !compact) 11.sp else 9.sp
        Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(if (compact) 1.dp else 3.dp)) {
            Text(note, color = foreground, fontSize = noteSize, lineHeight = if (expanded && !compact) 19.sp else if (contentHeight < 26.dp) 13.sp else 15.sp, fontWeight = FontWeight.Medium, fontFamily = HallPadMono, maxLines = 1, softWrap = false)
            if (adc != null) Text(adc.toString().padStart(4, '0'), color = foreground, fontSize = adcSize, lineHeight = if (expanded && !compact) 12.sp else 10.sp, fontFamily = HallPadMono, maxLines = 1, softWrap = false)
        }
    }
}
