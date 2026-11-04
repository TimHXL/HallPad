package com.timhxl.hallbeat

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.dp
import kotlin.math.roundToInt

/** Touch-down and opening/cancelling numeric input never commit a configuration. */
@Composable
internal fun DrumEffectValueSlider(label: String, valueLabel: String, value: Float,
    range: ClosedFloatingPointRange<Float>, enabled: Boolean, integer: Boolean, onCommit: (Float) -> Unit) {
    val focus = androidx.compose.ui.platform.LocalFocusManager.current
    val keyboard = androidx.compose.ui.platform.LocalSoftwareKeyboardController.current
    var sliding by remember { mutableStateOf(false) }
    var sliderDraft by remember { mutableFloatStateOf(value.coerceIn(range)) }
    var editing by remember { mutableStateOf(false) }
    var input by remember { mutableStateOf(TextFieldValue("")) }
    fun closeEditor() { focus.clearFocus(); keyboard?.hide(); editing = false }
    val latestCommit by rememberUpdatedState(onCommit)
    fun normalize(v: Float) = if (integer) v.roundToInt().toFloat().coerceIn(range) else v.coerceIn(range)
    LaunchedEffect(value) { if (!sliding) sliderDraft = value.coerceIn(range) }
    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(label, Modifier.width(52.dp), style = MaterialTheme.typography.labelMedium)
        StableParameterSlider(sliderDraft, { sliding = true; sliderDraft = normalize(it) }, enabled,
            Modifier.weight(1f), range, onFinished = {
                sliding = false
                val next = normalize(sliderDraft)
                if (next != value) latestCommit(next)
            })
        TextButton(enabled = enabled, onClick = {
            val text = if (integer) value.roundToInt().toString() else value.toString()
            input = TextFieldValue(text, TextRange(0, text.length)); editing = true
        }, modifier = Modifier.width(80.dp), contentPadding = PaddingValues(0.dp)) { Text(valueLabel, maxLines = 1) }
    }
    if (editing) {
        val parsed = input.text.replace(',', '.').toFloatOrNull()?.takeIf { it.isFinite() && it in range }
        AlertDialog(onDismissRequest = { closeEditor() }, title = { Text(label) }, text = {
            OutlinedTextField(value = input, onValueChange = { input = it.copy(text = it.text.take(12)) }, singleLine = true,
                label = { Text(if (integer) "灯/秒（40–200）" else "秒（0.2–5）") }, isError = parsed == null,
                keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = androidx.compose.ui.text.input.KeyboardType.Decimal))
        }, confirmButton = {
            TextButton(enabled = parsed != null && enabled, onClick = {
                parsed?.let { val next = normalize(it); if (next != value) latestCommit(next) }; closeEditor()
            }) { Text("确认") }
        }, dismissButton = { TextButton(onClick = { closeEditor() }) { Text("取消") } })
    }
}
