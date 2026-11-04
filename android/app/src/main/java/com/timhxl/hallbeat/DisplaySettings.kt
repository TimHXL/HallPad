package com.timhxl.hallbeat

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.pm.ActivityInfo
import android.os.Build
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.platform.LocalContext

internal tailrec fun Context.findHallPadActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findHallPadActivity()
    else -> null
}

/** 只提交 HDR 窗口请求，实际动态范围由系统与显示器决定。 */
@Composable
internal fun ApplyHdrRequest(enabled: Boolean) {
    val window = LocalContext.current.findHallPadActivity()?.window
    DisposableEffect(window) {
        val originalMode = window?.colorMode
        val originalHeadroom = if (Build.VERSION.SDK_INT >= 35) window?.desiredHdrHeadroom else null
        onDispose {
            if (Build.VERSION.SDK_INT >= 35 && originalHeadroom != null) window?.setDesiredHdrHeadroom(originalHeadroom)
            if (originalMode != null) window?.colorMode = originalMode
        }
    }
    SideEffect {
        window?.colorMode = if (enabled) ActivityInfo.COLOR_MODE_HDR else ActivityInfo.COLOR_MODE_DEFAULT
        if (Build.VERSION.SDK_INT >= 35) window?.setDesiredHdrHeadroom(if (enabled) 2f else 0f)
    }
}

/** 横屏展开时锁定横屏，关闭后恢复进入前的方向策略。 */
@Composable
internal fun ExpandedKeyboardOrientation(expanded: Boolean) {
    val activity = LocalContext.current.findHallPadActivity()
    DisposableEffect(activity, expanded) {
        val original = activity?.requestedOrientation
        if (expanded) activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        onDispose {
            if (expanded && original != null) activity?.requestedOrientation = original
        }
    }
}
