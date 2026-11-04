package com.timhxl.hallbeat

import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay

@Composable
internal fun ScoreLibraryHeader(searching: Boolean, query: String, onSearching: (Boolean) -> Unit,
    onQuery: (String) -> Unit, busy: Boolean, recording: Boolean, onImport: () -> Unit, onRecord: () -> Unit) {
    val expansion by animateFloatAsState(if (searching) 1f else 0f, animationSpec = androidx.compose.animation.core.tween(220), label = "scoreSearchExpansion")
    val requester = remember { FocusRequester() }
    val focus = LocalFocusManager.current
    val keyboard = LocalSoftwareKeyboardController.current
    fun closeSearch() { focus.clearFocus(); keyboard?.hide(); onQuery(""); onSearching(false) }
    BackHandler(enabled = searching) { closeSearch() }
    LaunchedEffect(searching) {
        if (searching) { delay(220); requester.requestFocus(); keyboard?.show() }
    }
    DisposableEffect(Unit) { onDispose { focus.clearFocus(); keyboard?.hide() } }
    // Both text layers are measured at their final width; only opacity and icon position animate.
    // A near-zero animation weight must never be used to measure a text field.
    BoxWithConstraints(Modifier.fillMaxWidth().height(56.dp).clipToBounds()) {
        val iconStart = (maxWidth - 208.dp).coerceAtLeast(0.dp)
        if (expansion < 0.999f) Row(Modifier.fillMaxSize().graphicsLayer { alpha = 1f - expansion },
            verticalAlignment = Alignment.CenterVertically) {
            Text("我的曲谱", modifier = Modifier.weight(1f), style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold, maxLines = 1, softWrap = false, overflow = TextOverflow.Ellipsis)
            Spacer(Modifier.width(48.dp))
            TextButton(enabled = !searching && !busy, onClick = onImport,
                modifier = Modifier.width(80.dp), contentPadding = PaddingValues(0.dp)) { Text("导入", maxLines = 1, softWrap = false) }
            TextButton(enabled = !searching, onClick = onRecord,
                modifier = Modifier.width(80.dp), contentPadding = PaddingValues(0.dp)) { Text(if (recording) "正在录制" else "开始录制", maxLines = 1, softWrap = false) }
        }
        if (searching || expansion > 0.001f) Row(
            Modifier.fillMaxSize().graphicsLayer { alpha = expansion }, verticalAlignment = Alignment.CenterVertically) {
            Spacer(Modifier.width(48.dp))
            OutlinedTextField(value = query, onValueChange = { onQuery(it.take(200)) },
                modifier = Modifier.weight(1f).height(56.dp).focusRequester(requester), enabled = searching, singleLine = true,
                placeholder = { Text("搜索曲谱名称", maxLines = 1, softWrap = false, overflow = TextOverflow.Ellipsis) },
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                keyboardActions = KeyboardActions(onSearch = { focus.clearFocus(); keyboard?.hide() }))
            TextButton(enabled = searching, onClick = { closeSearch() }, modifier = Modifier.width(64.dp),
                contentPadding = PaddingValues(0.dp)) { Text("取消", maxLines = 1, softWrap = false) }
        }
        IconButton(modifier = Modifier.offset(x = iconStart * (1f - expansion)).size(48.dp).align(Alignment.CenterStart),
            onClick = { if (!searching) onSearching(true) else { requester.requestFocus(); keyboard?.show() } }) {
            Icon(painterResource(android.R.drawable.ic_menu_search), "搜索曲谱", tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(24.dp))
        }
    }
}
