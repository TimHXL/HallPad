package com.timhxl.hallbeat

import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import top.ltfan.m3x.material.LocalMaterialSurfaceRenderer
import top.ltfan.m3x.material.PlainMaterialSurfaceRenderer
import top.ltfan.m3x.material.MaterialSurfaceRole
import top.ltfan.m3x.material.materialSurface
import top.ltfan.m3x.material.rememberSurfaceAppearance

/** 自定义音符格沿用 m3x 的表面渲染，点击与无障碍语义交给基础 Surface。 */
@Composable
internal fun HallPadPanel(modifier: Modifier = Modifier, shape: Shape = MaterialTheme.shapes.medium, color: Color = MaterialTheme.colorScheme.surface, contentColor: Color = LocalContentColor.current, onClick: (() -> Unit)? = null, enabled: Boolean = true, content: @Composable () -> Unit) {
    val interaction = remember { MutableInteractionSource() }
    val appearance = rememberSurfaceAppearance(role = MaterialSurfaceRole.Panel, containerColor = color, contentColor = contentColor, shape = shape)
    // 实色模式只由基础 Surface 绘制一次底色，避免背景与点击表面叠层。
    val plain = LocalMaterialSurfaceRenderer.current === PlainMaterialSurfaceRenderer
    val backing = if (plain) modifier else modifier.materialSurface(appearance = appearance, shape = shape, interactionSource = interaction)
    val surfaceColor = if (plain) color else Color.Transparent
    if (onClick == null) {
        Surface(modifier = backing, shape = shape, color = surfaceColor, contentColor = appearance.contentColor, content = content)
    } else {
        Surface(onClick = onClick, modifier = backing, enabled = enabled, shape = shape, color = surfaceColor, contentColor = appearance.contentColor, interactionSource = interaction, content = content)
    }
}
