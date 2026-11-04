package com.timhxl.hallbeat

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.res.painterResource
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.DialogWindowProvider


/** 独立设置页面：顶栏与完成操作固定，内容按分区浏览。 */
@Suppress("DEPRECATION")
@Composable
internal fun PracticeSettingsPage(onClose: () -> Unit, leadingAction: @Composable () -> Unit = {}, content: @Composable (Boolean, androidx.compose.ui.unit.Dp) -> Unit) {
    val palette = MaterialTheme.colorScheme
    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        val view = LocalView.current
        SideEffect {
            (view.parent as? DialogWindowProvider)?.window?.let { window ->
                androidx.core.view.WindowCompat.setDecorFitsSystemWindows(window, false)
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
        Surface(Modifier.fillMaxSize(), color = palette.background) {
            Column(Modifier.fillMaxSize().safeDrawingPadding().imePadding().padding(horizontal = 20.dp)) {
                Row(Modifier.fillMaxWidth().heightIn(min = 60.dp), verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onClick = onClose) { Icon(painterResource(R.drawable.ic_back), contentDescription = "返回") }
                    Text("练习设置", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                    leadingAction()
                    TextButton(onClick = onClose) { Text("完成") }
                }
                BoxWithConstraints(Modifier.weight(1f).fillMaxWidth().padding(top = 4.dp, bottom = 8.dp)) {
                    val contentWidth = maxWidth
                    val contentHeight = maxHeight
                    content(contentWidth >= 560.dp, contentHeight)
                }
            }
        }
    }
}

@Composable
internal fun PracticeSettingsSection(title: String, content: @Composable ColumnScope.() -> Unit) {
    Surface(Modifier.fillMaxWidth(), shape = RoundedCornerShape(24.dp), color = MaterialTheme.colorScheme.surfaceContainerLow) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary)
            content()
        }
    }
}
