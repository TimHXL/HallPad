package com.timhxl.hallbeat

import androidx.compose.animation.*
import androidx.compose.animation.core.tween
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.time.Instant
import java.util.Properties

private data class AboutDetails(val rows: List<Pair<String, String>>, val licenseFiles: List<String>)

@Composable
internal fun AboutPage(onBack: () -> Unit) {
    val context = LocalContext.current
    var details by remember { mutableStateOf<AboutDetails?>(null) }
    var showLicenses by remember { mutableStateOf(false) }
    var licensePath by remember { mutableStateOf<String?>(null) }
    val licenseTexts = remember { mutableStateMapOf<String, String>() }
    val scroll = rememberScrollState()
    LaunchedEffect(Unit) { details = withContext(Dispatchers.IO) { loadAboutDetails(context) } }
    LaunchedEffect(licensePath) { licensePath?.let { path -> if (path !in licenseTexts) licenseTexts[path] = withContext(Dispatchers.IO) { runCatching { context.assets.open(path).bufferedReader().use { it.readText() } }.getOrDefault("无法读取许可文件") } } }
    fun goBack() { if (licensePath != null) licensePath = null else if (showLicenses) showLicenses = false else onBack() }
    BackHandler { goBack() }
    Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().padding(horizontal = 24.dp, vertical = 12.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = { goBack() }) { Icon(painterResource(R.drawable.ic_back), contentDescription = "返回") }
                Text(if (licensePath != null) licensePath!!.removePrefix("licenses/") else if (showLicenses) "开放源代码许可" else "关于 HallPad", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
            }
            val pageKey = licensePath ?: if (showLicenses) "licenses" else "about"
            AnimatedContent(targetState = pageKey, modifier = Modifier.weight(1f).fillMaxWidth(), transitionSpec = {
                val forward = targetState != "about" && (initialState == "about" || targetState != "licenses")
                (slideInHorizontally(tween(260)) { if (forward) it / 5 else -it / 5 } + fadeIn(tween(180))) togetherWith (slideOutHorizontally(tween(220)) { if (forward) -it / 5 else it / 5 } + fadeOut(tween(160)))
            }, label = "aboutLicensePage") { page ->
            if (page != "about" && page != "licenses") {
                key(page) { SelectionContainer(Modifier.fillMaxSize()) { Text(licenseTexts[page] ?: "正在读取…", modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(vertical = 12.dp), style = MaterialTheme.typography.bodySmall) } }
            } else if (page == "licenses") Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                details?.licenseFiles?.forEach { path ->
                    Text(path.removePrefix("licenses/"), modifier = Modifier.fillMaxWidth().clickable { licensePath = path }.padding(vertical = 16.dp), color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.bodyMedium)
                    HorizontalDivider()
                }
            } else Column(Modifier.fillMaxSize().verticalScroll(scroll), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                val current = details
                if (current == null) LinearProgressIndicator(Modifier.fillMaxWidth())
                else {
                    SelectionContainer {
                        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            current.rows.forEach { (label, value) -> Column { Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary); Text(value, style = MaterialTheme.typography.bodyMedium) } }

                        }
                    }
                    HorizontalDivider()
                    Text("开源组件", style = MaterialTheme.typography.titleMedium)
                    Text("M3X · AndroidX / Compose / DataStore · Kotlin / Coroutines · Material Icons · DejaVu Sans Mono", style = MaterialTheme.typography.bodySmall)
                    Text("开放源代码许可", modifier = Modifier.fillMaxWidth().clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                        onClick = { showLicenses = true }
                    ).padding(vertical = 16.dp), color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.bodyMedium)
                    Spacer(Modifier.height(12.dp))
                }
            }
            }
        }
    }
}

private fun loadAboutDetails(context: Context): AboutDetails {
    val manager = context.packageManager
    val info = manager.getPackageInfo(context.packageName, PackageManager.PackageInfoFlags.of(0))
    val app = context.applicationInfo
    val properties = Properties().apply { runCatching { context.assets.open("build-info.properties").use { load(it) } } }
    fun value(key: String): String = properties.getProperty(key, "—").takeUnless { it == "unavailable" } ?: "—"
    fun listLicenses(path: String): List<String> = (context.assets.list(path) ?: emptyArray()).flatMap { name -> val child = "$path/$name"; if ((context.assets.list(child) ?: emptyArray()).isNotEmpty()) listLicenses(child) else listOf(child) }.sorted()
    val rows = buildList {
        add("应用" to manager.getApplicationLabel(app).toString())
        add("应用 ID" to context.packageName)
        add("版本" to "${info.versionName} (${info.longVersionCode})")
        add("构建时间" to runCatching { java.time.format.DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss XXX").format(Instant.parse(value("build.time.utc")).atZone(java.time.ZoneId.systemDefault())) }.getOrDefault("—"))
        add("目标 SDK" to app.targetSdkVersion.toString())
        add("设备" to "${Build.MANUFACTURER} ${Build.MODEL}")
        add("Android" to "${Build.VERSION.RELEASE} / API ${Build.VERSION.SDK_INT}")
        add("系统构建" to "${Build.DISPLAY}\n${Build.FINGERPRINT}")
        add("支持 ABI" to Build.SUPPORTED_ABIS.joinToString(", "))
        add("屏幕" to "${context.resources.displayMetrics.widthPixels} × ${context.resources.displayMetrics.heightPixels} px / ${context.resources.displayMetrics.densityDpi} dpi")
        add("运行时" to "${System.getProperty("java.vm.name")} ${System.getProperty("java.vm.version")}")
    }
    return AboutDetails(rows, listLicenses("licenses"))
}
