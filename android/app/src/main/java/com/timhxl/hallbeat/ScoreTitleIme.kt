package com.timhxl.hallbeat

import android.app.Activity
import android.content.ContextWrapper
import android.view.WindowManager
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.platform.LocalView

/** 顶部曲名编辑时让输入法覆盖底部，避免系统平移或缩小整个演奏界面。 */
@Composable
internal fun KeepScoreTitleLayout(enabled: Boolean) {
    val view = LocalView.current
    DisposableEffect(enabled, view) {
        var context = view.context
        while (context is ContextWrapper && context !is Activity) { context = context.baseContext }
        val window = (context as? Activity)?.window
        val previous = window?.attributes?.softInputMode
        if (enabled && window != null && previous != null) window.setSoftInputMode((previous and WindowManager.LayoutParams.SOFT_INPUT_MASK_ADJUST.inv()) or WindowManager.LayoutParams.SOFT_INPUT_ADJUST_NOTHING)
        onDispose { if (enabled && window != null && previous != null) window.setSoftInputMode(previous) }
    }
}
