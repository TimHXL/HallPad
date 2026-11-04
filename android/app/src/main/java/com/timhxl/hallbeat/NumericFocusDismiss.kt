package com.timhxl.hallbeat

import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController

/** 仅记录当前数字输入控件，坐标使用窗口坐标以兼容录制弹窗。 */
private object NumericFocus {
    var active: Any? = null
    var bounds: Rect? = null
}

internal fun Modifier.numericFocusTarget(): Modifier = composed {
    val identity = remember { Any() }
    var bounds: Rect? = null
    DisposableEffect(identity) { onDispose { if (NumericFocus.active === identity) { NumericFocus.active = null; NumericFocus.bounds = null } } }
    this.onGloballyPositioned { coordinates -> bounds = coordinates.boundsInWindow(); if (NumericFocus.active === identity) NumericFocus.bounds = bounds }.onFocusChanged { focus ->
        if (focus.isFocused) { NumericFocus.active = identity; NumericFocus.bounds = bounds }
        else if (NumericFocus.active === identity) { NumericFocus.active = null; NumericFocus.bounds = null }
    }
}

internal fun Modifier.dismissNumericFocusOutside(): Modifier = composed {
    val focus = LocalFocusManager.current
    val keyboard = LocalSoftwareKeyboardController.current
    var coordinates = remember { arrayOfNulls<LayoutCoordinates>(1) }
    this.onGloballyPositioned { coordinates[0] = it }.pointerInput(focus, keyboard) {
        awaitEachGesture {
            val down = awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
            val active = NumericFocus.active
            val bounds = NumericFocus.bounds
            val point = coordinates[0]?.takeIf { it.isAttached }?.localToWindow(down.position)
            if (active != null && bounds != null && point != null && !bounds.contains(point)) {
                focus.clearFocus()
                keyboard?.hide()
            }
        }
    }
}
