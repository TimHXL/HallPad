package com.timhxl.hallbeat

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

/** 应用本地显示设置，不依赖设备连接状态。 */
@Composable
internal fun DisplaySettingsPage(themeMode: String, systemDark: Boolean, onThemeModeChange: (String) -> Unit, hdrRequested: Boolean, onHdrChange: (Boolean) -> Unit, onBack: () -> Unit) {
    val colors = MaterialTheme.colorScheme
    Surface(Modifier.fillMaxSize(), color = colors.background) {
        Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().padding(horizontal = 24.dp, vertical = 12.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = onBack) { Icon(painterResource(R.drawable.ic_back), contentDescription = "返回") }
                Text("显示", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            }
            Column(Modifier.fillMaxWidth().weight(1f).verticalScroll(rememberScrollState()).padding(top = 24.dp, bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("外观", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    Text("选择应用的显示主题", style = MaterialTheme.typography.bodyMedium, color = colors.onSurfaceVariant)
                }
                Card(colors = CardDefaults.cardColors(containerColor = colors.surfaceContainerHigh)) {
                    Column(Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
                        listOf("light" to "明亮", "dark" to "深色", "system" to "跟随系统（${if (systemDark) "深色" else "明亮"}）").forEachIndexed { index, option ->
                            Surface(onClick = { onThemeModeChange(option.first) }, color = if (themeMode == option.first) colors.primaryContainer else colors.surfaceContainerHigh) {
                                Row(Modifier.fillMaxWidth().heightIn(min = 64.dp).padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                                    Text(option.second, modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge, color = if (themeMode == option.first) colors.onPrimaryContainer else colors.onSurface)
                                    RadioButton(selected = themeMode == option.first, onClick = null)
                                }
                            }
                            if (index < 2) HorizontalDivider(Modifier.padding(horizontal = 16.dp), color = colors.outlineVariant.copy(alpha = 0.5f))
                        }
                    }
                }
                HorizontalDivider(color = colors.outlineVariant.copy(alpha = 0.6f))
                Row(Modifier.fillMaxWidth().heightIn(min = 64.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text("HDR 请求", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                        Text("向系统请求 HDR 显示", style = MaterialTheme.typography.bodyMedium, color = colors.onSurfaceVariant)
                    }
                    Switch(checked = hdrRequested, onCheckedChange = onHdrChange)
                }
            }
        }
    }
}
