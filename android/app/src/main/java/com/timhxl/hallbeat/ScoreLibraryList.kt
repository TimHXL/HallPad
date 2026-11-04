package com.timhxl.hallbeat

import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.gestures.scrollBy
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import kotlinx.coroutines.delay

/** The caller owns scroll state, so opening a score does not lose the library position. */
@Composable
internal fun ScoreLibraryList(entries: List<StoredScore>, modifier: Modifier = Modifier,
    listState: LazyListState, reorderEnabled: Boolean = true, recent: StoredScore? = null,
    onOpen: (StoredScore) -> Unit, onDelete: (StoredScore) -> Unit, onOrder: (List<StoredScore>) -> Unit) {
    val latestEntries by rememberUpdatedState(entries)
    val latestOrder by rememberUpdatedState(onOrder)
    var draggedId by remember { mutableStateOf<String?>(null) }
    var fingerY by remember { mutableFloatStateOf(0f) }
    var touchOffset by remember { mutableFloatStateOf(0f) }
    fun moveDragged() {
        val id = draggedId ?: return
        val visible = listState.layoutInfo.visibleItemsInfo
        val moving = visible.firstOrNull { it.key == id } ?: return
        val center = fingerY - touchOffset + moving.size / 2f
        val target = visible.firstOrNull { center >= it.offset && center < it.offset + it.size } ?: return
        val from = latestEntries.indexOfFirst { it.id == id }
        val to = latestEntries.indexOfFirst { it.id == target.key }
        if (from >= 0 && to >= 0 && from != to) {
            latestOrder(latestEntries.toMutableList().apply { add(to, removeAt(from)) })
        }
    }
    LaunchedEffect(draggedId) {
        while (draggedId != null) {
            val layout = listState.layoutInfo
            val edge = 64f
            val delta = when {
                fingerY < layout.viewportStartOffset + edge -> -12f
                fingerY > layout.viewportEndOffset - edge -> 12f
                else -> 0f
            }
            if (delta != 0f) { listState.scrollBy(delta); moveDragged() }
            delay(16)
        }
    }
    LazyColumn(state = listState, modifier = modifier.pointerInput(listState, reorderEnabled) {
        if (reorderEnabled) detectDragGesturesAfterLongPress(
            onDragStart = { point ->
                if (point.x < size.width - 56.dp.toPx()) {
                    val item = listState.layoutInfo.visibleItemsInfo.firstOrNull { point.y >= it.offset && point.y < it.offset + it.size }
                    if (item != null) { draggedId = item.key as? String; fingerY = point.y; touchOffset = point.y - item.offset }
                }
            },
            onDragEnd = { draggedId = null }, onDragCancel = { draggedId = null },
            onDrag = { change, amount ->
                if (draggedId != null) { change.consume(); fingerY += amount.y; moveDragged() }
            })
    }, verticalArrangement = Arrangement.spacedBy(8.dp), contentPadding = PaddingValues(vertical = 8.dp)) {
        if (recent != null) item(key = "recent:${recent.id}") {
            TextButton(onClick = { onOpen(recent) }, modifier = Modifier.fillMaxWidth()) {
                Text("继续练习 · ${recent.title}", modifier = Modifier.fillMaxWidth(), maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        if (entries.isEmpty()) item { Text(if (reorderEnabled) "导入曲谱以开始练习。" else "没有匹配的曲谱") }
        items(entries, key = { it.id }) { entry ->
            val moving = draggedId == entry.id
            OutlinedCard(onClick = { if (draggedId == null) onOpen(entry) },
                modifier = Modifier.fillMaxWidth().height(64.dp).zIndex(if (moving) 1f else 0f).graphicsLayer {
                    if (moving) {
                        val offset = listState.layoutInfo.visibleItemsInfo.firstOrNull { it.key == entry.id }?.offset ?: 0
                        translationY = fingerY - touchOffset - offset
                    }
                }) {
                Row(Modifier.fillMaxSize().padding(start = 16.dp, end = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(entry.title, Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    IconButton(onClick = { onDelete(entry) }, enabled = draggedId == null, modifier = Modifier.size(48.dp)) {
                        Icon(painterResource(R.drawable.ic_delete), "删除曲谱", tint = Color(0xFFD43B3B), modifier = Modifier.size(24.dp))
                    }
                }
            }
        }
    }
}
