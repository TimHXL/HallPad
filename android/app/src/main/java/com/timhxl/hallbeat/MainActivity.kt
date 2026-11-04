package com.timhxl.hallbeat

import kotlin.math.roundToInt

import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch
import android.os.Bundle
import android.os.SystemClock
import android.Manifest
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.*
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.input.pointer.PointerId
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.conflate
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.first
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.material3.*
import androidx.activity.compose.BackHandler
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.core.animate
import androidx.compose.animation.core.tween
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.ui.res.painterResource
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.border
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.sin
import top.ltfan.m3x.backdrop.BackdropHost
import top.ltfan.m3x.backdrop.captureBackdrop
import top.ltfan.m3x.backdrop.rememberBackdropLayer
import top.ltfan.m3x.material.FloatingBottomBar
import top.ltfan.m3x.material.item
import top.ltfan.m3x.material.backdrop.BackdropPresets
import top.ltfan.m3x.material.bundle.M3xMaterialTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // 在创建窗口内容前恢复主题，系统启动屏同步使用应用夜间模式。
        val mode = getSharedPreferences("hallpad_splash", android.content.Context.MODE_PRIVATE).getString("theme_mode", "system") ?: "system"
        val dark = when (mode) { "dark" -> true; "light" -> false; else -> resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK == android.content.res.Configuration.UI_MODE_NIGHT_YES }
        setTheme(if (dark) R.style.Theme_HallBeat_Dark else R.style.Theme_HallBeat_Light)
        super.onCreate(savedInstanceState)

        window.setBackgroundDrawable(android.graphics.drawable.ColorDrawable(android.graphics.Color.parseColor(if (dark) "#141A18" else "#F3F8F2")))
        enableEdgeToEdge()
        window.isNavigationBarContrastEnforced = false
        val storage = HallPadStorage.get(this)
        var storageReady = false
        window.decorView.viewTreeObserver.addOnPreDrawListener(object : android.view.ViewTreeObserver.OnPreDrawListener {
            override fun onPreDraw(): Boolean {
                if (!storageReady) return false
                window.decorView.viewTreeObserver.removeOnPreDrawListener(this)
                return true
            }
        })
        lifecycleScope.launch {
            try {
                storage.awaitInitialized()
                setContent { HallBeatApp() }
            } catch (error: Exception) {
                if (error is kotlinx.coroutines.CancellationException) throw error
                setContent {
                    MaterialTheme {
                        Surface(Modifier.fillMaxSize()) {
                            Column(Modifier.safeDrawingPadding().padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                                Text("无法读取本地设置")
                                Text("设置文件已保留，请重启应用后重试。")
                                Button(onClick = { finish() }) { Text("关闭") }
                            }
                        }
                    }
                }
            } finally { storageReady = true }
        }
    }
}

private val TabLabels = listOf("主页", "键盘", "演奏", "控制台")
// 取自重庆邮电大学官网校徽图片的近似 sRGB 色，不代表官方标准色值。
private val Accent = Color(0xFF007A53)
private val CampusYellow = Color(0xFFFFEDB3)

@Composable
fun HallBeatApp() {
    val context = LocalContext.current
    val displayPrefs = remember(context) { HallPadStorage.get(context).display }
    val storage = remember(context) { HallPadStorage.get(context) }
    val displayStatus by storage.display.store.status.collectAsState()
    val configurationStatus by storage.configuration.store.status.collectAsState()
    if (displayStatus is top.ltfan.m3x.datastore.StoreStatus.WriteFailed || configurationStatus is top.ltfan.m3x.datastore.StoreStatus.WriteFailed) {
        AlertDialog(onDismissRequest = {}, title = { Text("设置尚未保存") }, text = { Text("磁盘写入失败，当前修改仍保留在内存中，请重试保存。") }, confirmButton = { TextButton(onClick = { storage.display.store.retrySave(); storage.configuration.store.retrySave() }) { Text("重试保存") } })
    }
    // 清除旧版本设置的应用级明暗覆盖，让配置始终反映手机系统主题。
    LaunchedEffect(context) {
        context.getSystemService(android.app.UiModeManager::class.java).setApplicationNightMode(android.app.UiModeManager.MODE_NIGHT_AUTO)
    }
    val systemDark = androidx.compose.foundation.isSystemInDarkTheme()
    val themeMode = displayPrefs.getString("theme_mode", "system") ?: "system"
    val dark = when (themeMode) { "dark" -> true; "light" -> false; else -> systemDark }
    val activity = context.findHallPadActivity()
    SideEffect {
        activity?.window?.let { window ->
            window.setBackgroundDrawable(android.graphics.drawable.ColorDrawable(if (dark) 0xFF141A18.toInt() else 0xFFF3F8F2.toInt()))
            window.isNavigationBarContrastEnforced = false
            val controller = androidx.core.view.WindowCompat.getInsetsController(window, window.decorView)
            controller.isAppearanceLightStatusBars = !dark
            controller.isAppearanceLightNavigationBars = !dark
        }
    }
    LaunchedEffect(themeMode, activity) {
        context.getSharedPreferences("hallpad_splash", android.content.Context.MODE_PRIVATE).edit().putString("theme_mode", themeMode).apply()
        activity?.splashScreen?.setSplashScreenTheme(when (themeMode) { "dark" -> R.style.Theme_HallBeat_Dark; "light" -> R.style.Theme_HallBeat_Light; else -> 0 })
    }
    val setThemeMode: (String) -> Unit = { mode ->
        // 手动主题只影响 Compose 界面，不覆盖手机系统的主题配置。
        displayPrefs.edit().putString("theme_mode", mode).apply()
        context.getSharedPreferences("hallpad_splash", android.content.Context.MODE_PRIVATE).edit().putString("theme_mode", mode).apply()
        activity?.splashScreen?.setSplashScreenTheme(when (mode) { "dark" -> R.style.Theme_HallBeat_Dark; "light" -> R.style.Theme_HallBeat_Light; else -> 0 })
    }
    val colors = if (dark) darkColorScheme(primary = Color(0xFF8BCEB2), onPrimary = Color(0xFF103C2B), primaryContainer = Color(0xFF2D4D3E), onPrimaryContainer = Color(0xFFC9EAD8), onBackground = Color(0xFFE0EDE4), onSurface = Color(0xFFE0EDE4), onSurfaceVariant = Color(0xFFBCCBC1), onSecondaryContainer = Color(0xFFD3E5DA), secondary = Color(0xFFB9C9BF), onSecondary = Color(0xFF24372C), secondaryContainer = Color(0xFF303B35), background = Color(0xFF141A18), surface = Color(0xFF1B2320), surfaceContainerHigh = Color(0xFF25302A), outline = Color(0xFF84988B), outlineVariant = Color(0xFF3F5346)) else lightColorScheme(primary = Accent, onPrimary = Color.White, primaryContainer = Color(0xFFB9F0D3), onPrimaryContainer = Color(0xFF003825), onBackground = Color(0xFF15221A), onSurface = Color(0xFF15221A), onSurfaceVariant = Color(0xFF45564B), secondary = Color(0xFF735D00), onSecondary = Color.White, secondaryContainer = CampusYellow, onSecondaryContainer = Color(0xFF302600), background = Color(0xFFF3F8F2), surface = Color(0xFFFAFFF8), surfaceContainerHigh = Color(0xFFE3EEE3), outline = Color(0xFF6A8070), outlineVariant = Color(0xFFBDCEC0))
    val ble = remember { BleController(context) }
    var scorePlayerOpen by remember { mutableStateOf(false) }
    val state = remember { HallPadState(context) }
    val drumsticks = remember { DrumsticksPreviewState(context) }
    DisposableEffect(ble, drumsticks) {
        ble.protocol.onDrumConfig = drumsticks::readConfig
        ble.protocol.onDrumHit = drumsticks::receiveHit
        ble.protocol.onDrumStatus = drumsticks::receiveStatus
        ble.protocol.onDrumCalibration = drumsticks::readCalibration
        ble.protocol.onDrumLight = drumsticks::readLight
        ble.protocol.onDrumColor = drumsticks::readColor
        ble.protocol.onDrumEffect = drumsticks::readEffect
        ble.protocol.onDrumControlAck = drumsticks::receiveControlAck
        onDispose { ble.protocol.onDrumConfig = null; ble.protocol.onDrumHit = null; ble.protocol.onDrumStatus = null; ble.protocol.onDrumCalibration = null; ble.protocol.onDrumLight = null; ble.protocol.onDrumColor = null; ble.protocol.onDrumEffect = null; ble.protocol.onDrumControlAck = null }
    }
    var globalInstrumentRequest by remember { mutableIntStateOf(0) }
    val consoleScroll = rememberScrollState()
    LaunchedEffect(globalInstrumentRequest) { if (globalInstrumentRequest > 0) consoleScroll.scrollTo(0) }
    var showPresets by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(state) { snapshotFlow { state.encode() }.collectLatest { configuration -> delay(250L); state.persist(configuration) } }
    var foreground by remember { mutableStateOf(true) }
    val metronome = remember { MetronomeUiState() }
    // 演示入口每次冷启动关闭，不持久化为已连接设备。
    var demo by remember { mutableStateOf(false) }
    LaunchedEffect(ble.ready, demo) { if (!demo && !ble.ready) state.selectionMode = false }
    LaunchedEffect(ble.ready, demo, ble.protocol.session) {
        drumsticks.configure(demo, ble.ready && ble.protocol.has(19), ble.protocol)
    }
    val recording = remember { FpgaRecording() }
    DisposableEffect(ble, recording) {
        ble.protocol.telemetry.onMask = recording::mask
        onDispose { recording.stop(); ble.protocol.telemetry.onMask = null }
    }
    LaunchedEffect(ble.ready, foreground, demo) {
        if (!ble.ready || !foreground || demo) recording.stop("录制已停止")
    }
    LaunchedEffect(recording.recording) {
        while (recording.recording) { recording.tick(); delay(100) }
    }
    MetronomeClock(metronome)
    var selectedTab by rememberSaveable { mutableIntStateOf(0) }
    var expandedKeyboard by rememberSaveable { mutableStateOf(false) }
    val demoPractice = remember { PracticeController({ _, _ -> }) }
    var showAbout by rememberSaveable { mutableStateOf(false) }
    var showDisplay by rememberSaveable { mutableStateOf(false) }
    var showDeviceSettings by rememberSaveable { mutableStateOf(false) }
    val pagerState = rememberPagerState(initialPage = selectedTab, pageCount = { TabLabels.size })
    LaunchedEffect(selectedTab, expandedKeyboard, showDeviceSettings) {
        state.performance.center()
        if (!expandedKeyboard && !showDeviceSettings) {
            if (!ScorePlaybackService.playing) state.releaseAll()
            snapshotFlow { pagerState.layoutInfo.pageSize }.first { it > 0 }
            // 直接从当前可见位置滚动，避免跨三页时框架先跳到目标附近。
            // 切换途中再次选择时，旧动画取消，新动画接续当前位置。
            pagerState.scroll {
                val pageDistance = selectedTab - pagerState.currentPage - pagerState.currentPageOffsetFraction
                val distance = pageDistance * (pagerState.layoutInfo.pageSize + pagerState.layoutInfo.pageSpacing)
                val duration = (320 + (kotlin.math.abs(pageDistance) - 1f).coerceAtLeast(0f) * 80).toInt().coerceAtMost(480)
                var consumed = 0f
                animate(initialValue = 0f, targetValue = distance, animationSpec = tween(durationMillis = duration)) { value, _ ->
                    consumed += scrollBy(value - consumed)
                }
            }
        }
    }
    var hdrRequested by remember { mutableStateOf(displayPrefs.getBoolean("hdr_requested", false)) }
    ApplyHdrRequest(hdrRequested)
    ExpandedKeyboardOrientation(expandedKeyboard)
    BackHandler(enabled = expandedKeyboard || showDeviceSettings || showAbout || showDisplay) { if (!ScorePlaybackService.playing) state.releaseAll(); if (showDisplay) showDisplay = false else if (showAbout) showAbout = false else if (showDeviceSettings) showDeviceSettings = false else expandedKeyboard = false }
    val demoDevice = remember { DemoDevice() }
    val demoSdCard = remember { SdCardController(DemoSdCard()::exchange) }
    LaunchedEffect(demo) {
        state.performance.center(); state.deviceMessage = ""
        if (demo) { demoDevice.release(); demoDevice.panic(state.muted); state.performance.joystickEnabled = true }
    }
    LaunchedEffect(demo, ble.connected) { state.showAdc = demo || ble.connected }
    LaunchedEffect(demo) {
        state.clearTelemetry()
        if (demo) {
            val start = SystemClock.elapsedRealtime(); var frame = 0L
            while (true) {
                repeat(35) { state.liveAdc[it] = 2100 + kotlin.random.Random.nextInt(-10, 11) }
                frame++; delay((start + frame * 1000 / 10 - SystemClock.elapsedRealtime()).coerceAtLeast(1L))
            }
        }
    }
    LaunchedEffect(ble, demo) {
        state.playbackPressed.clear()
        if (!demo) ble.protocol.playbackKeys.collect { keys ->
            state.playbackPressed.clear()
            repeat(35) { id -> keys[ble.uiToSensor[id]]?.let { state.playbackPressed[id] = it } }
        }
    }
    LaunchedEffect(ble.refresh, ble.keyTelemetryRefresh, demo, ble.ready) {
        if (!demo) {
            if (!ble.ready) state.clearTelemetry()
            else {
            val recentPresses = ble.protocol.telemetry.consumePresses()
            repeat(35) { id ->
                val sensor = ble.uiToSensor[id]
                if (recentPresses and (1L shl sensor) != 0L) { state.physicalPulseUntil[id] = SystemClock.elapsedRealtime() + 100; state.selectedKey = id }
                if (ble.protocol.telemetry.physicalMask and (1L shl sensor) != 0L) state.physicalPressed[id] = true else state.physicalPressed.remove(id)
            }
            }
        }
    }
    LaunchedEffect(ble.adcTelemetryRefresh, demo, ble.ready) {
        if (!demo && ble.ready) {
            val adcFresh = ble.protocol.adcReceivedAt >= 0 && SystemClock.elapsedRealtime() - ble.protocol.adcReceivedAt <= 1000
            repeat(35) { id -> state.liveAdc[id] = if (adcFresh) ble.protocol.telemetry.adc[ble.uiToSensor[id]] else -1 }
        }
    }
    LaunchedEffect(demo, ble.ready) {
        while (!demo && ble.ready) {
            delay(25)
            val now = SystemClock.elapsedRealtime()
            repeat(35) { id -> if (state.physicalPulseUntil[id] in 1..now) state.physicalPulseUntil[id] = 0 }
            if (ble.protocol.adcReceivedAt >= 0 && now - ble.protocol.adcReceivedAt > 1000) repeat(35) { state.liveAdc[it] = -1 }
        }
    }
    DisposableEffect(state, ble, demo) {
        state.onReleaseRemote = { if (demo) demoDevice.release() else ble.releaseRemote() }
        state.onMuteRemote = { on -> if (on) { ScorePlaybackService.pause(context); if (demo) demoPractice.pause() else ble.protocol.practice.pause() }; if (demo) { demoDevice.panic(on); if (on) demoPractice.pause(); state.applyDeviceMute(on) } else if (ble.connected) ble.panic(on) else state.applyDeviceMute(on) }
        state.onParameterRemote = { id, value ->
            if (demo) demoDevice.setParameter(id, value)
            if (!demo) {
                val capability = when (id) { 0x40, 0x41, 0x42 -> 5; in 0x60..0x65 -> 7; 0x71, 0x05 -> 2; else -> -1 }
                if (!ble.ready) { if (!ble.connected && ble.status != "连接中...") ble.notice("请先连接设备") }
                else if (capability >= 0 && !ble.protocol.has(capability)) { if (id == 0x71) { state.performance.joystickEnabled = false; state.performance.center() }; ble.notice("当前设备不支持此功能") }
                else ble.setParameter(id, value)
            }
        }
        state.performance.onParameter = state::sendParameter
        metronome.legacyDevice = !demo
        metronome.onStopConsole = {
            if (demo) demoDevice.setParameter(0x50, 0)
            else if (ble.ready && ble.protocol.has(6)) ble.protocol.setParameters(mapOf(0x50 to 0))
        }
        metronome.onRemoteChange = {
            if (demo) { demoDevice.setParameter(0x51, metronome.bpm * 10); demoDevice.setParameter(0x52, metronome.beats); demoDevice.setParameter(0x53, metronome.signature.substringAfter('/').toInt()); demoDevice.setParameter(0x50, if (metronome.running) 1 else 0) }
            if (!demo) {
                if (ble.ready && ble.protocol.has(6)) {
                    if (!metronome.canRun) {
                        metronome.running = false
                        ble.protocol.setParameters(mapOf(0x50 to 0))
                    } else {
                        val requestedUnit = metronome.signature.substringAfter('/').toInt()
                        metronome.sixteenthEmulated = requestedUnit == 16
                        val deviceBpm = metronome.bpm * if (metronome.sixteenthEmulated) 2 else 1
                        ble.protocol.setParameters(mapOf(0x51 to deviceBpm * 10, 0x52 to metronome.beats, 0x53 to if (metronome.sixteenthEmulated) 8 else requestedUnit, 0x50 to if (metronome.running) 1 else 0))
                    }
                }
                else ble.notice(if (!ble.ready) "请连接设备后设置节拍器" else "当前设备不支持节拍器设置")
            }
        }
        state.onKeyConfigRemote = { ids ->
            if (demo) ids.forEach { id -> demoDevice.configure(id, HallPadSession.KeyConfig(state.keyEnabled[id], state.notes[id], HallPadInstrumentIds[state.keyInstruments[id]] ?: 65535, state.velocityModes[id], state.velocities[id])) }
            else ble.protocol.setKeyConfigurations(ids.associate { id -> ble.uiToSensor[id] to HallPadSession.KeyConfig(state.keyEnabled[id], state.notes[id], HallPadInstrumentIds[state.keyInstruments[id]] ?: 65535, state.velocityModes[id], state.velocities[id]) })
        }
        state.keyConfigurationConfirmed = { expected ->
            demo || (ble.ready && expected.size == 35 && ble.protocol.keyConfigurationsConfirmed((0 until 35).associate { id -> ble.uiToSensor[id] to expected[id] }))
        }
        state.onKeyRemote = { id, down ->
            if (demo) demoDevice.key(id, down, (Math.pow(state.velocities[id] / 127.0, state.curve.toDouble()) * 127).toInt().coerceIn(1, 127))
            if (!demo && (foreground || !down) && !state.selectionMode && ble.ready && ble.keyboardMappingConfirmed) {
                val velocity = (Math.pow(state.velocities[id] / 127.0, state.curve.toDouble()) * 127).toInt().coerceIn(1, 127)
                ble.key(ble.uiToSensor[id], down, velocity)
            }
        }
        // Playback edges have their own route: no UI foreground/selection gating.
        state.onPlaybackKeyRemote = { id, down ->
            val velocity = (Math.pow(state.velocities[id] / 127.0, state.curve.toDouble()) * 127).toInt().coerceIn(1, 127)
            if (demo) demoDevice.key(id, down, velocity)
            else if (ble.ready && ble.keyboardMappingConfirmed) ble.key(ble.uiToSensor[id], down, velocity)
        }
        onDispose { ble.releaseRemote(); state.onPlaybackKeyRemote = null; state.onKeyRemote = null; state.onKeyConfigRemote = null; state.keyConfigurationConfirmed = null; state.performance.onParameter = null; metronome.onRemoteChange = null; metronome.onStopConsole = null; state.onReleaseRemote = null; state.onMuteRemote = null; state.onParameterRemote = null }
    }
    LaunchedEffect(ble.refresh, ble.ready, demo) {
        state.unsupportedParameterIds = if (demo || !ble.ready) emptySet() else ble.protocol.unsupportedParameterIds()
        state.performance.audioMixAvailable = demo || (ble.ready && ble.protocol.has(20) && ble.protocol.canSetParameter(0x90))
    }
    LaunchedEffect(ble.ready, demo) {
        if (!ble.ready && !demo) state.releaseAll()
        if (!demo && ble.ready && !ble.protocol.has(2)) state.performance.joystickEnabled = false
        if (ble.ready) ble.protocol.seedLocalFallback(mapOf(0x13 to (state.attack * 5000).toInt(), 0x21 to (state.release * 10000).toInt(), 0x62 to ((state.performance.red shl 16) or (state.performance.green shl 8) or state.performance.blue), 0x63 to (state.performance.rippleSpeed * 1000).toInt(), 0x65 to (state.performance.rippleDecay * 1000).toInt()))
    }
    var keyReadbackSeen by remember(ble.protocol.session) { mutableLongStateOf(0L) }
    LaunchedEffect(ble.refresh, demo) {
        if (ble.ready && !demo) {
            if (keyReadbackSeen != ble.protocol.keyReadbackVersion) {
                keyReadbackSeen = ble.protocol.keyReadbackVersion
                state.applyDeviceKeys((0 until 35).mapNotNull { id -> ble.protocol.displayKey(ble.uiToSensor[id])?.let { id to it } }.toMap())
            }
            val applied = (ble.protocol.applied.keys + listOf(0x13, 0x21, 0x62, 0x63, 0x65, 0x70, 0x71)).mapNotNull { id -> ble.protocol.displayValue(id)?.let { id to it } }.toMap()
            applied[1]?.let { state.volume = it / 1000f }
            applied[2]?.let { value -> HallPadInstrumentIds.entries.firstOrNull { it.value == value }?.let { state.instrument = it.key } }
            applied[0x90]?.let { state.performance.fpgaAudioEnabled = it and 1 != 0; state.performance.auxAudioEnabled = it and 2 != 0 }
            applied[0x61]?.let { state.brightness = it / 1000f }
            applied[0x60]?.let { state.effect = listOf("水波", "常亮", "关闭").getOrElse(it) { "关闭" } }
            applied[0x40]?.let { state.performance.reverbEnabled = it == 1 }
            applied[0x42]?.let { state.performance.reverbAmount = it / 1000f }
            applied[0x13]?.let { state.attack = (it / 5000f).coerceIn(0f, 1f) }
            applied[0x21]?.let { state.release = (it / 10000f).coerceIn(0.01f, 0.2f) }
            applied[0x62]?.let { state.performance.red = (it shr 16) and 255; state.performance.green = (it shr 8) and 255; state.performance.blue = it and 255 }
            applied[0x63]?.let { state.performance.rippleSpeed = (it / 1000f).coerceIn(0.5f, 30f) }
            applied[0x65]?.let { state.performance.rippleDecay = (it / 1000f).coerceIn(0.2f, 5f) }
            applied[0x05]?.let { state.performance.remoteBendRangeCent = it }
            applied[0x70]?.let { state.performance.joystickSensitivity = (it / 1000f).coerceIn(0f, 1f) }
            applied[0x71]?.let { state.performance.joystickEnabled = it == 1 }
            if (!metronome.scoreOwned) {
                applied[0x50]?.let { metronome.running = it == 1 }
                applied[0x51]?.let { if (metronome.canRun) metronome.bpm = (it / if (metronome.sixteenthEmulated) 20 else 10).coerceIn(30, 240) }
                val beats = applied[0x52] ?: metronome.beats
                val reportedUnit = applied[0x53]
                val unit = if (metronome.signature.endsWith("/16") && (reportedUnit == null || reportedUnit == 8)) 16 else reportedUnit ?: metronome.signature.substringAfter('/').toInt()
                metronome.signature = "$beats/$unit"
            }
            state.applyDeviceMute(ble.protocol.displayMuted)
        }
        state.mutePending = ble.protocol.mutePending
    }
    LaunchedEffect(ble.feedback, demo) { state.deviceMessage = if (demo) "" else ble.feedback }
    LaunchedEffect(ble, state, demo) {
        var lastPitch: Int? = null
        var lastModulation: Int? = null
        var previousSession = 0L
        snapshotFlow { listOf(state.performance.x, state.performance.y, state.performance.joystickSensitivity, if (state.performance.joystickEnabled && foreground && !demo) 1f else 0f, ble.refresh.toFloat()) }.conflate().collect { values ->
            if (demo) {
                val settings = state.performance
                val enabled = settings.joystickEnabled && foreground
                demoDevice.performance(if (enabled) (settings.y * kotlin.math.abs(settings.y) * 8191 * settings.joystickSensitivity).toInt().coerceIn(-8192, 8191) else 0, if (enabled) joystickModulation(settings.x, settings.joystickSensitivity) else 0)
                return@collect
            }
            if (!ble.ready) return@collect
            val enabled = values[3] == 1f
            val x = if (enabled) values[0] else 0f
            val y = if (enabled) values[1] else 0f
            if (x != 0f || y != 0f) delay(8)
            if ((x != 0f || y != 0f) && ble.protocol.has(2) && ble.protocol.displayValue(0x71) != 1) {
                if (!ble.protocol.parameterPending(0x71) && ble.protocol.canSetParameter(0x71)) ble.setParameter(0x71, 1)
                return@collect
            }
            if (x != 0f || y != 0f || (lastPitch != null && lastPitch != 0) || (lastModulation != null && lastModulation != 0)) {
                if (previousSession != ble.protocol.session) { previousSession = ble.protocol.session; lastPitch = null; lastModulation = null }
                val pitch = (y * kotlin.math.abs(y) * values[2] * 8191).toInt().coerceIn(-8192, 8191)
                val modulation = joystickModulation(x, values[2])
                if (lastPitch != pitch) { ble.protocol.performance(1, pitch); lastPitch = pitch }
                if (lastModulation != modulation) { ble.protocol.performance(2, modulation); lastModulation = modulation }
            }
        }
    }
    var taps by remember { mutableIntStateOf(0) }
    var lastTap by remember { mutableLongStateOf(0L) }
    val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { ble.startScan() }
    val beginSearch: () -> Unit = {
        if (ble.hasPermissions()) ble.startScan() else permissionLauncher.launch(arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT))
    }
    LaunchedEffect(Unit) { beginSearch() }
    DisposableEffect(ble) { onDispose { state.persist(); ble.close() } }
    val owner = context.findHallPadActivity() as? androidx.lifecycle.LifecycleOwner
    DisposableEffect(owner, ble) {
        val observer = androidx.lifecycle.LifecycleEventObserver { _, event ->
            if (event == androidx.lifecycle.Lifecycle.Event.ON_START) foreground = true
            if (event == androidx.lifecycle.Lifecycle.Event.ON_STOP) { foreground = false; state.releaseManualKeys(); state.performance.center(); ble.stopScan(); if (!ScorePlaybackService.playing) { val wasRunning = metronome.running; metronome.running = false; if (wasRunning && (demo || (ble.ready && ble.protocol.has(6)))) metronome.submit() }; if (!ScorePlaybackService.playing) state.releaseAll(); state.persist() }
        }
        owner?.lifecycle?.addObserver(observer)
        onDispose { owner?.lifecycle?.removeObserver(observer) }
    }
    M3xMaterialTheme(colorScheme = colors, backdrop = BackdropPresets.GlassClear) {
        if (showPresets) PresetManager(state) { showPresets = false }
        val pageLayer = rememberBackdropLayer()
        // 页面背景自行绘制时，也必须提供相应的默认前景色。
        CompositionLocalProvider(LocalContentColor provides MaterialTheme.colorScheme.onBackground) {
        BackdropHost(pageLayer) {
            Box(Modifier.fillMaxSize().dismissNumericFocusOutside()) {
            BoxWithConstraints(Modifier.fillMaxSize()) {
                val tabWidth = ((maxWidth - 48.dp) / 4).coerceIn(48.dp, 84.dp)
                Box(Modifier.fillMaxSize().captureBackdrop(pageLayer).background(colors.background)) {
                    AmbientBackground(dark)
                    // 只有四个固定页面，提前创建并保留，避免首次翻页时集中布局控件。
                    HorizontalPager(state = pagerState, modifier = Modifier.fillMaxSize(), beyondViewportPageCount = TabLabels.lastIndex, userScrollEnabled = false, key = { it }) { page ->
                        Column(Modifier.fillMaxSize().then(if (page == 3) Modifier.imePadding().verticalScroll(consoleScroll) else Modifier).statusBarsPadding().navigationBarsPadding().padding(horizontal = if (page == 1) 18.dp else 24.dp).padding(top = 8.dp, bottom = if (page == 2 && scorePlayerOpen) 100.dp else 104.dp)) {
                            if (page == 0) {
                            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                                Text("HallPad", modifier = Modifier.defaultMinSize(minWidth = 112.dp, minHeight = 48.dp).clickable(interactionSource = remember { androidx.compose.foundation.interaction.MutableInteractionSource() }, indication = null, onClick = {
                                    val now = SystemClock.elapsedRealtime()
                                    taps = if (now - lastTap <= 800L) taps + 1 else 1
                                    lastTap = now
                                    if (taps >= 5) { ble.stopScan(); ble.disconnect(); state.releaseAll(); demo = true; taps = 0; selectedTab = 0 }
                                }).padding(vertical = 12.dp), fontSize = 22.sp, fontWeight = FontWeight.Bold, color = colors.primary)
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Text(if (demo) "已连接 · 演示模式" else if (ble.ready) "已连接" else if (ble.connected || ble.status == "连接中...") "连接中..." else "未连接", fontSize = 12.sp, color = colors.onSurfaceVariant)
                                }
                            }
                            Spacer(Modifier.height(4.dp))
                            }
                            when (page) {
                                0 -> Box(Modifier.weight(1f)) { ConnectionPage(ble, state, demo, dark, beginSearch, { if (!ScorePlaybackService.playing) state.releaseAll(); state.performance.center(); showDeviceSettings = true }, { selectedTab = 3; globalInstrumentRequest++ }) { state.releaseAll(); demo = false; beginSearch() } }
                                1 -> Box(Modifier.weight(1f)) { KeyboardPage(state, demo, dark, drumsticks, demo || ble.ready, { showPresets = true }) { if (!ScorePlaybackService.playing) state.releaseAll(); expandedKeyboard = true } }
                                2 -> Column(Modifier.weight(1f)) {
                                    ScoreWorkspacePage(ScorePageEnvironment(state, demo || ble.ready, demo || ble.protocol.has(16), foreground && selectedTab == 2 && !expandedKeyboard && !showDeviceSettings && !showAbout, if (demo) demoPractice else ble.protocol.practice, demo, demo || ble.protocol.has(PracticeWire.CAPABILITY), if (demo) IntArray(35) { it } else ble.uiToSensor, metronome, recording, run { ble.keyTelemetryRefresh; ble.protocol.telemetry.physicalMask }, ble.ready && !demo && ble.protocol.has(6), { scorePlayerOpen = it }, if (demo) null else ble.protocol.directMidi, if (demo) demoSdCard else ble.protocol.sdCard, !demo && ble.protocol.temporaryKeysActive), drumsticks)
                                }
                                else -> MixerPage(state, demo, dark, metronome, demo || ble.ready, globalInstrumentRequest, { showDisplay = true }, { showAbout = true }) { showPresets = true }
                            }
                        }
                    }
                }
                FloatingBottomBar(selectedTabIndex = selectedTab, onTabSelected = { if (!ScorePlaybackService.playing) state.releaseAll(); selectedTab = it }, modifier = Modifier.align(Alignment.BottomCenter).navigationBarsPadding().padding(bottom = 20.dp), tabMinWidth = tabWidth) {
                    TabLabels.forEachIndexed { index, label ->
                        item(key = label) { NavigationIcon(index); Text(label, fontSize = 11.sp, fontWeight = FontWeight.Medium) }
                    }
                }
            }
            if (expandedKeyboard) Surface(Modifier.fillMaxSize(), color = colors.background) {
                ExpandedKeyboardPage(state, demo, dark, drumsticks, demo || ble.ready) { if (!ScorePlaybackService.playing) state.releaseAll(); expandedKeyboard = false }
            }
            AnimatedVisibility(visible = showDisplay, modifier = Modifier.fillMaxSize(), enter = slideInHorizontally(animationSpec = tween(280)) { it } + fadeIn(tween(180)), exit = slideOutHorizontally(animationSpec = tween(240)) { it } + fadeOut(tween(180))) {
                DisplaySettingsPage(themeMode, systemDark, setThemeMode, hdrRequested, { hdrRequested = it; displayPrefs.edit().putBoolean("hdr_requested", it).apply() }) { showDisplay = false }
            }
            AnimatedVisibility(visible = showAbout, modifier = Modifier.fillMaxSize(), enter = slideInHorizontally(animationSpec = tween(280)) { it } + fadeIn(tween(180)), exit = slideOutHorizontally(animationSpec = tween(240)) { it } + fadeOut(tween(180))) {
                AboutPage { showAbout = false }
            }
            AnimatedVisibility(visible = showDeviceSettings, modifier = Modifier.fillMaxSize(), enter = slideInHorizontally(animationSpec = tween(280)) { it } + fadeIn(tween(180)), exit = slideOutHorizontally(animationSpec = tween(240)) { it } + fadeOut(tween(180))) {
                Surface(Modifier.fillMaxSize(), color = colors.background) {
                    DeviceSettingsPage(state, drumsticks) { showDeviceSettings = false }
                }
            }
            }
        }
        }
    }
}

@Composable
private fun AmbientBackground(dark: Boolean, showWave: Boolean = true) {
    val primary = MaterialTheme.colorScheme.primary
    val secondary = MaterialTheme.colorScheme.secondaryContainer
    Canvas(Modifier.fillMaxSize()) {
        val alpha = if (dark) 0.10f else 0.32f
        drawCircle(Brush.radialGradient(listOf(primary.copy(alpha = alpha), Color.Transparent), center = Offset(size.width * 0.9f, size.height * 0.18f), radius = size.width * 0.85f), radius = size.width * 0.85f, center = Offset(size.width * 0.9f, size.height * 0.18f))
        drawCircle(Brush.radialGradient(listOf(secondary.copy(alpha = alpha), Color.Transparent), center = Offset(size.width * 0.1f, size.height * 0.88f), radius = size.width * 0.9f), radius = size.width * 0.9f, center = Offset(size.width * 0.1f, size.height * 0.88f))
        if (showWave) {
        val path = Path()
        for (x in 0..120) {
            val px = size.width * x / 120f
            val y = size.height * 0.92f + sin(x * 0.10f) * 36.dp.toPx()
            if (x == 0) path.moveTo(px, y) else path.lineTo(px, y)
        }
        drawPath(path, primary.copy(alpha = 0.25f), style = Stroke(9.dp.toPx(), cap = StrokeCap.Round))
        }
    }
}


@Composable
private fun NavigationIcon(index: Int) {
    val icon = when (index) { 0 -> R.drawable.ic_nav_home; 1 -> R.drawable.ic_nav_piano; 2 -> R.drawable.ic_nav_music_note; else -> R.drawable.ic_nav_console }
    Icon(painter = painterResource(icon), contentDescription = null, modifier = Modifier.size(23.dp), tint = LocalContentColor.current)
}

/**
 * 主页专属的 HallPad 35 键暗纹。
 *
 * 仅绘制背景，不参与布局、不接收触摸、不读取蓝牙状态；
 * 7 列 × 5 行与实体键位一致，第三排左一对应中央 C。
 * 不影响共享背景、其他页面、底部导航及其动画。
 */
@Composable
private fun HallPadHomeKeyWatermark(dark: Boolean, modifier: Modifier = Modifier) {
    val primary = MaterialTheme.colorScheme.primary
    // 暖黄色只点缀几颗键，避免把整体背景变成鲜艳的键盘插图。
    val warmAccent = if (dark) Color(0xFFE5D39B) else Color(0xFFAE9851)
    // 独立离屏图层仅承载主页装饰：既不会染到共享背景，也不会溢出 Pager 页面。
    Canvas(modifier.clipToBounds().graphicsLayer {
        compositingStrategy = CompositingStrategy.Offscreen
        clip = true
    }) {
        if (size.width <= 0f || size.height <= 0f) return@Canvas

        val width = size.width
        val height = size.height
        val keyGap = 7.dp.toPx()
        val gridWidth = minOf(width * 0.98f, 440.dp.toPx())
        val keyWidth = (gridWidth - 6f * keyGap) / 7f
        val keyHeight = keyWidth * 0.92f
        val gridHeight = keyHeight * 5f + keyGap * 4f
        val left = width - gridWidth * 0.80f
        val top = height * 0.135f
        val pivot = Offset(left + gridWidth * 0.52f, top + gridHeight * 0.50f)
        val edgeWidth = 1.05.dp.toPx()
        val radius = CornerRadius(8.dp.toPx(), 8.dp.toPx())
        val darkFactor = if (dark) 0.76f else 1f

        // 与现有全局柔光叠加，但限定在主页，形成轻微的压纹底色。
        val halo = Offset(width * 0.84f, top + gridHeight * 0.52f)
        drawCircle(
            brush = Brush.radialGradient(
                colors = listOf(primary.copy(alpha = if (dark) 0.045f else 0.065f), Color.Transparent),
                center = halo,
                radius = width * 0.70f
            ),
            center = halo,
            radius = width * 0.70f
        )

        rotate(degrees = -10f, pivot = pivot) {
            val outerPadding = 13.dp.toPx()
            drawRoundRect(
                color = primary.copy(alpha = 0.035f * darkFactor),
                topLeft = Offset(left - outerPadding, top - outerPadding),
                size = Size(gridWidth + outerPadding * 2f, gridHeight + outerPadding * 2f),
                cornerRadius = CornerRadius(22.dp.toPx())
            )
            drawRoundRect(
                color = primary.copy(alpha = 0.10f * darkFactor),
                topLeft = Offset(left - outerPadding, top - outerPadding),
                size = Size(gridWidth + outerPadding * 2f, gridHeight + outerPadding * 2f),
                cornerRadius = CornerRadius(22.dp.toPx()),
                style = Stroke(width = edgeWidth)
            )

            for (row in 0 until 5) {
                for (column in 0 until 7) {
                    val x = left + column * (keyWidth + keyGap)
                    val y = top + row * (keyHeight + keyGap)
                    // 左侧有连接文案：图案由左到右逐渐显现，避免降低文字对比度。
                    val horizontalFade = 0.28f + 0.72f * (column / 6f)
                    val edgeAlpha = (0.075f + 0.135f * horizontalFade) * darkFactor
                    val isMiddleC = row == 2 && column == 0
                    val isWarmKey = isMiddleC || (row == 1 && column == 4) || (row == 3 && column == 5)
                    val keyColor = if (isWarmKey) warmAccent else primary
                    val keyAlpha = if (isWarmKey) edgeAlpha * 1.13f else edgeAlpha
                    drawRoundRect(
                        color = keyColor.copy(alpha = keyAlpha * 0.23f),
                        topLeft = Offset(x, y),
                        size = Size(keyWidth, keyHeight),
                        cornerRadius = radius
                    )
                    drawRoundRect(
                        color = keyColor.copy(alpha = keyAlpha),
                        topLeft = Offset(x, y),
                        size = Size(keyWidth, keyHeight),
                        cornerRadius = radius,
                        style = Stroke(width = edgeWidth)
                    )
                    // 上缘细光刻画轻微的实体键帽厚度，保持静态，不产生动画开销。
                    drawLine(
                        color = keyColor.copy(alpha = keyAlpha * 0.38f),
                        start = Offset(x + keyWidth * 0.20f, y + 2.dp.toPx()),
                        end = Offset(x + keyWidth * 0.80f, y + 2.dp.toPx()),
                        strokeWidth = 0.65.dp.toPx(),
                        cap = StrokeCap.Round
                    )
                }
            }
        }

        // 右侧柔和消隐：用目标透明度遮罩仅淡出键盘暗纹，页面背景和控件不受影响。
        // 保留边界裁剪避免相邻页面串图，但右侧轮廓到达边缘前已经自然变透明。
        drawRect(
            brush = Brush.horizontalGradient(
                0.00f to Color.White,
                0.66f to Color.White,
                0.81f to Color.White.copy(alpha = 0.72f),
                0.93f to Color.White.copy(alpha = 0.22f),
                1.00f to Color.Transparent,
                startX = 0f,
                endX = width
            ),
            blendMode = BlendMode.DstIn
        )
    }
}

@Composable
private fun ConnectionPage(ble: BleController, state: HallPadState, demo: Boolean, dark: Boolean, search: () -> Unit, onSettings: () -> Unit, onTimbre: () -> Unit, exitDemo: () -> Unit) {
    val palette = MaterialTheme.colorScheme
    val controlsEnabled = demo || ble.ready
    var devicePage by remember { mutableIntStateOf(0) }
    var renaming by remember { mutableStateOf(false) }
    var nameDraft by remember { mutableStateOf("") }
    var demoName by rememberSaveable { mutableStateOf("HallPad 演示设备") }
    var nameError by remember { mutableStateOf("") }
    if (renaming) AlertDialog(onDismissRequest = { if (!ble.renaming) renaming = false }, title = { Text("设备名称") }, text = {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedTextField(value = nameDraft, onValueChange = { nameDraft = it; nameError = "" }, singleLine = true, enabled = !ble.renaming, isError = !ModuleDeviceName.isValid(nameDraft), supportingText = { Text("仅支持英文字母、数字、下划线和短横线，1–16 位") }, label = { Text("蓝牙名称") })
            if (nameError.isNotEmpty()) Text(nameError, color = palette.error)
        }
    }, confirmButton = { TextButton(enabled = !ble.renaming && ModuleDeviceName.isValid(nameDraft), onClick = {
        if (!ModuleDeviceName.isValid(nameDraft)) nameError = "请检查名称格式"
        else if (demo) { demoName = nameDraft; renaming = false }
        else { renaming = false; ble.renameDevice(nameDraft) { error -> if (error != null) ble.notice(error) } }
    }) { Text(if (ble.renaming) "正在更名…" else "保存") } }, dismissButton = { TextButton(enabled = !ble.renaming, onClick = { renaming = false }) { Text("取消") } })
    BoxWithConstraints(Modifier.fillMaxSize()) {
    val compactHome = maxHeight < 420.dp
    // 纯绘制背景层：不占据空间，下面的设备/声音两区仍使用原来的权重布局。
    if (!compactHome) HallPadHomeKeyWatermark(dark, Modifier.fillMaxSize())
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.weight(if (compactHome) 1f else 1.4f).fillMaxWidth()) {
            val connecting = !demo && (ble.status == "连接中..." || ble.renaming || (ble.connected && !ble.ready))
            val count = ble.devices.size
            val page = devicePage.coerceIn(0, (count - 1).coerceAtLeast(0))
            val candidate = ble.devices.getOrNull(page)
            Row(Modifier.fillMaxWidth().height(48.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("设备", modifier = Modifier.weight(1f), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
                TextButton(onClick = onSettings) { Text("设备设置") }
            }
            Box(Modifier.fillMaxWidth().weight(1f).padding(vertical = 12.dp), contentAlignment = Alignment.CenterStart) {
                Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    val title = when {
                        demo -> demoName
                        ble.connected || connecting -> ble.deviceName
                        candidate != null -> candidate.name
                        ble.scanning -> "正在查找设备"
                        else -> "连接你的 HallPad"
                    }
                    Text(title, color = palette.onBackground, fontSize = 28.sp, lineHeight = 34.sp, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis)
                    when {
                        connecting -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                            Text("连接中...", color = palette.primary, style = MaterialTheme.typography.bodyMedium)
                        }
                        ble.scanning -> Text("正在搜索附近的 HallPad", color = palette.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium)
                        !demo && !ble.connected && candidate != null -> Text("发现 $count 台设备", color = palette.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium)
                        !demo && !ble.connected -> Text(if (ble.status.startsWith("未找到设备")) "未发现设备，请确认设备已开启" else if (ble.status !in setOf("未连接", "请选择设备")) ble.status else "开启设备后，搜索附近的蓝牙设备", color = palette.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium, maxLines = 2)
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        when {
                            demo -> OutlinedButton(onClick = exitDemo) { Text("退出演示") }
                            connecting -> OutlinedButton(onClick = {}, enabled = false) { Text("断开连接") }
                            ble.ready -> OutlinedButton(onClick = { ble.disconnect() }) { Text("断开连接") }
                            candidate != null -> Button(onClick = { ble.connect(candidate) }) { Text("连接设备") }
                            else -> Button(onClick = search, enabled = !ble.scanning) { Text(if (ble.scanning) "正在搜索…" else "搜索设备") }
                        }
                        if (demo || ble.ready) TextButton(onClick = { state.releaseAll(); nameDraft = if (demo) demoName.takeIf { ModuleDeviceName.isValid(it) } ?: "HallPad-Demo" else ble.deviceName; nameError = ""; renaming = true }) { Text("更改名称") }
                        else if (!connecting && candidate != null) TextButton(onClick = search, enabled = !ble.scanning) { Text("重新搜索") }
                    }
                    if (!demo && !ble.connected && !connecting && count > 1) Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                        TextButton(enabled = page > 0, onClick = { devicePage = page - 1 }) { Text("上一台") }
                        Text("${page + 1} / $count", color = palette.onSurfaceVariant, style = MaterialTheme.typography.labelMedium)
                        TextButton(enabled = page + 1 < count, onClick = { devicePage = page + 1 }) { Text("下一台") }
                    }
                }
            }
        }
        // 保留原来的分区高度，仅去掉可见横线，不改变设备区的尺寸与位置。
        Spacer(Modifier.height(25.dp))
        // 只让常规竖屏主页的声音控件下移 20dp；紧凑模式保持原状。
        Column(Modifier.fillMaxWidth().then(if (compactHome) Modifier else Modifier.weight(1f).offset(y = 20.dp)), verticalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterVertically)) {
            Row(Modifier.fillMaxWidth().height(48.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("声音", modifier = Modifier.weight(1f), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold)
                Box(Modifier.width(120.dp).fillMaxHeight(), contentAlignment = Alignment.CenterEnd) {
                    if (state.muted) Text("已静音", modifier = Modifier.clickable(enabled = controlsEnabled && !state.mutePending, interactionSource = remember { androidx.compose.foundation.interaction.MutableInteractionSource() }, indication = null) { state.toggleMute() }.padding(vertical = 12.dp), color = palette.primary, maxLines = 1)
                    else EditableParameter(state.volume, ((state.volume * 100).toInt()).toString() + "%", 0f..1f, controlsEnabled && !state.mutePending && state.canControlParameter(1), Modifier.width(100.dp), textStyle = MaterialTheme.typography.bodyLarge, onChange = { state.volume = it; state.sendParameter(1, (it * 1000).toInt()) })
                }
            }
            StableParameterSlider(state.volume, { state.volume = it; state.sendParameter(1, (it * 1000).toInt()) }, !state.muted && controlsEnabled && !state.mutePending && state.canControlParameter(1), Modifier.fillMaxWidth())
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Row(Modifier.weight(1f).clickable(enabled = controlsEnabled && state.canControlParameter(2), interactionSource = remember { androidx.compose.foundation.interaction.MutableInteractionSource() }, indication = null, onClick = onTimbre).padding(vertical = 12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) { InstrumentIcon(state.instrument); Text(state.instrument, color = if (controlsEnabled) palette.onBackground else palette.onSurface.copy(alpha = 0.38f), fontSize = 23.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis) }
                TextButton(onClick = { state.toggleMute() }, enabled = controlsEnabled && !state.mutePending, modifier = Modifier.width(108.dp).height(48.dp)) { Text(if (state.mutePending) "等待确认" else if (state.muted) "恢复声音" else "紧急静音", maxLines = 1) }
            }
        }
    }
}
}

@Composable
private fun KeyboardPage(state: HallPadState, demo: Boolean, dark: Boolean, drumsticks: DrumsticksPreviewState, controlsEnabled: Boolean, onPresets: () -> Unit, onExpand: () -> Unit) {
    val palette = MaterialTheme.colorScheme
    Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            Text("键位总览", modifier = Modifier.weight(1f), color = palette.onBackground, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold, maxLines = 1)
            if (state.selectionMode) TextButton(onClick = { state.selectedKeys = emptySet() }, enabled = controlsEnabled && !state.selectingKeys && state.selectedKeys.isNotEmpty(), contentPadding = PaddingValues(horizontal = 6.dp)) { Text("重置") }
            TextButton(onClick = onPresets, enabled = controlsEnabled, contentPadding = PaddingValues(horizontal = 8.dp)) { Text("预设", maxLines = 1) }
            KeySelectionToolbar(state, showReset = false, enabled = controlsEnabled)
            IconButton(onClick = onExpand, modifier = Modifier.size(40.dp)) { Icon(painterResource(R.drawable.ic_fullscreen), contentDescription = "进入全屏", modifier = Modifier.size(22.dp)) }
        }
        Row(Modifier.fillMaxWidth().height(88.dp), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.width(88.dp).fillMaxHeight(), horizontalAlignment = Alignment.CenterHorizontally) { JoystickPad(state.performance, Modifier.fillMaxWidth().weight(1f)) }
            Box(Modifier.weight(1f).height(88.dp)) { KeyInformation(state, demo, compact = true, enabled = controlsEnabled) }
        }
        DrumsticksPreview(drumsticks, Modifier.fillMaxWidth().height(88.dp))
        Box(Modifier.fillMaxWidth().weight(1f).background(palette.surfaceContainerHigh.copy(alpha = 0.82f), RoundedCornerShape(22.dp)).padding(12.dp)) {
            KeyboardGrid(state, true, Modifier.fillMaxSize())
        }
    }
}

@Composable
private fun KeyInformation(state: HallPadState, demo: Boolean, compact: Boolean, enabled: Boolean) {
    if (state.selectionMode) { BatchKeyInformation(state, compact, enabled); return }
    val palette = MaterialTheme.colorScheme
    val id = state.selectedKey
    var editing by remember { mutableStateOf(false) }
    LaunchedEffect(enabled) { if (!enabled) editing = false }
    if (editing) KeyEditor(state, id) { editing = false }
    Box(Modifier.clickable(enabled = enabled, interactionSource = remember { androidx.compose.foundation.interaction.MutableInteractionSource() }, indication = null) { state.releaseAll(); editing = true }) {
    KeyInformationFrame(noteName(state.notes[id], state.keyUsesFlats(id)), mono = true, action = {
        IconButton(onClick = { state.releaseAll(); editing = true }, enabled = enabled, modifier = Modifier.size(32.dp)) { Icon(painterResource(R.drawable.ic_key_settings), contentDescription = "自定义键位", modifier = Modifier.size(18.dp)) }
    }, subtitle = {
        InstrumentIcon(state.effectiveInstrument(id))
        Text(state.effectiveInstrument(id), color = palette.onSurfaceVariant, style = MaterialTheme.typography.labelSmall, maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis)
    })
    }

}

/** 在整个网格统一接收多指轨迹，避免子键只接收最初按下的手指。 */
@Composable
private fun KeyboardGrid(state: HallPadState, enabled: Boolean, modifier: Modifier = Modifier, expanded: Boolean = false) {
    val palette = MaterialTheme.colorScheme
    val gap = if (expanded) 8.dp else 6.dp
    val gapPx = with(LocalDensity.current) { gap.toPx() }
    var gridSize by remember { mutableStateOf(IntSize.Zero) }
    val pulses = remember { mutableStateMapOf<Int, Long>() }
    LaunchedEffect(Unit) {
        while (true) {
            snapshotFlow { pulses.isNotEmpty() }.first { it }
            delay(40L)
            val now = SystemClock.uptimeMillis()
            pulses.keys.toList().forEach { if ((pulses[it] ?: 0L) <= now) pulses.remove(it) }
        }
    }
    DisposableEffect(state) { onDispose { state.releaseManualKeys() } }
    Column(modifier.onSizeChanged { gridSize = it }.pointerInput(gridSize, enabled, state.muted, gapPx, state.selectionMode) {
        if (gridSize.width <= 0 || gridSize.height <= 0) return@pointerInput
        val cellW = (gridSize.width - gapPx * 6) / 7f
        val cellH = (gridSize.height - gapPx * 4) / 5f
        if (cellW <= 0 || cellH <= 0) return@pointerInput
        fun keyAt(point: Offset): Int? {
            if (point.x < 0 || point.y < 0 || point.x >= gridSize.width || point.y >= gridSize.height) return null
            // 以相邻琴键间隙的中线划分完整矩形，各键分摊半个间隙。
            // 网格外仍不触发，边缘琴键的范围截止于网格边界。
            val col = ((point.x + gapPx / 2f) / (cellW + gapPx)).toInt().coerceIn(0, 6)
            val row = ((point.y + gapPx / 2f) / (cellH + gapPx)).toInt().coerceIn(0, 4)
            return row * 7 + col
        }
        val positions = mutableMapOf<PointerId, Offset>()
        val held = mutableMapOf<PointerId, Int>()
        fun touch(pointer: PointerId, point: Offset) {
            val previous = positions[pointer] ?: point
            // 对相邻事件间的线段补点，快速横扫、竖扫及斜扫不会跳过中间键。
            val distance = (point - previous).getDistance()
            val steps = kotlin.math.ceil(distance / (minOf(cellW, cellH) / 4f).coerceAtLeast(1f)).toInt().coerceIn(1, 512)
            for (step in 0..steps) {
                val sample = previous + (point - previous) * (step.toFloat() / steps)
                keyAt(sample)?.let { key ->
                    state.selectedKey = key
                    if (enabled && !state.muted && state.keyEnabled[key]) pulses[key] = SystemClock.uptimeMillis() + 90L
                }
            }
            positions[pointer] = point
            val current = keyAt(point)
            if (current == null) held.remove(pointer) else held[pointer] = current
        }
        fun publish() {
            val keys = if (enabled && !state.muted) held.values.filter { state.keyEnabled[it] }.toSet() else emptySet()
            state.setManualKeys(keys)
        }
        try {
            awaitEachGesture {
                val down = awaitFirstDown(requireUnconsumed = false, pass = androidx.compose.ui.input.pointer.PointerEventPass.Initial)
                down.consume()
                val anchor = keyAt(down.position)
                val selecting = state.selectionMode
                val previousSelection = state.selectedKeys
                var dragged = false
                fun selectRectangle(end: Int) {
                    if (anchor == null) return
                    val region = rectangleKeys(anchor, end)
                    state.selectedKeys = if (anchor in previousSelection) previousSelection - region else previousSelection + region
                }
                if (selecting) {
                    state.selectingKeys = true; state.releaseAll(); pulses.clear()
                    // Decide taps on release; the drag mode is fixed by the anchor selection.
                } else { touch(down.id, down.position); publish() }
                while (true) {
                    val event = awaitPointerEvent(androidx.compose.ui.input.pointer.PointerEventPass.Initial)
                    if (selecting) {
                        val change = event.changes.firstOrNull { it.id == down.id }
                        if (change != null && anchor != null) {
                            val point = Offset(change.position.x.coerceIn(0f, (gridSize.width - 1).toFloat()), change.position.y.coerceIn(0f, (gridSize.height - 1).toFloat()))
                            if ((change.position - down.position).getDistance() > viewConfiguration.touchSlop) dragged = true
                            if (dragged) keyAt(point)?.let { selectRectangle(it) }
                        }
                        event.changes.forEach { it.consume() }
                        if (change == null || !change.pressed) {
                            if (change != null && !dragged && anchor != null) state.selectedKeys = toggleSelectedKey(previousSelection, anchor)
                            break
                        }
                    } else {
                        event.changes.forEach { change ->
                            if (change.pressed) touch(change.id, change.position) else { positions.remove(change.id); held.remove(change.id) }
                            change.consume()
                        }
                        publish()
                        if (event.changes.none { it.pressed }) break
                    }
                }
                state.selectingKeys = false
                positions.clear()
                held.clear()
                publish()
            }
        } finally { state.releaseManualKeys(); state.selectingKeys = false; pulses.clear() }
    }, verticalArrangement = Arrangement.spacedBy(gap)) {
        repeat(5) { row ->
            Row(Modifier.fillMaxWidth().weight(1f), horizontalArrangement = Arrangement.spacedBy(gap)) {
                repeat(7) { col ->
                    val id = row * 7 + col
                    var editing by remember { mutableStateOf(false) }
    if (editing) KeyEditor(state, id) { editing = false }
    val active = state.displayedPressed(id) || pulses.containsKey(id)
                    val fill = if (state.selectionMode && id in state.selectedKeys) palette.primaryContainer else if (!state.keyEnabled[id]) palette.onSurface.copy(alpha = 0.06f) else if (active) palette.primary else if (!state.selectionMode && state.selectedKey == id) palette.primaryContainer else palette.primary.copy(alpha = 0.10f)
                    val foreground = if (state.selectionMode && id in state.selectedKeys) palette.onPrimaryContainer else if (!state.keyEnabled[id]) palette.onSurface.copy(alpha = 0.38f) else if (active) palette.onPrimary else if (!state.selectionMode && state.selectedKey == id) palette.onPrimaryContainer else palette.onSurface
                    Box(Modifier.weight(1f).fillMaxHeight().background(fill, RoundedCornerShape(if (expanded) 12.dp else 8.dp)).then(if (state.selectionMode && id in state.selectedKeys) Modifier.border(2.dp, palette.primary, RoundedCornerShape(if (expanded) 12.dp else 8.dp)) else Modifier)) {
                        KeyboardKeyLabels(noteName(state.notes[id], state.keyUsesFlats(id)), state.liveAdc[id].takeIf { state.showAdc && it >= 0 }, foreground, expanded)
                    }
                }
            }
        }
    }
}

@Composable
private fun ExpandedKeyboardPage(state: HallPadState, demo: Boolean, dark: Boolean, drumsticks: DrumsticksPreviewState, controlsEnabled: Boolean, onClose: () -> Unit) {
    Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
        AmbientBackground(dark, showWave = false)
        Column(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing).padding(start = 18.dp, end = 18.dp, top = 0.dp, bottom = 8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                Text("键位总览", color = MaterialTheme.colorScheme.onBackground, fontWeight = FontWeight.Bold, style = MaterialTheme.typography.headlineSmall)
                Box(Modifier.weight(1f).padding(horizontal = 16.dp)) { KeySelectionToolbar(state, enabled = controlsEnabled) }
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    if (demo) Text("演示模式", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 12.sp)
                    TextButton(onClick = onClose) { Text("收起") }
                }
            }
            Row(Modifier.fillMaxWidth().weight(1f), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Column(Modifier.width(188.dp).fillMaxHeight(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    JoystickPad(state.performance, Modifier.fillMaxWidth().weight(1f))
                    DrumsticksPreview(drumsticks, Modifier.fillMaxWidth().height(160.dp), stacked = true)
                    LandscapeKeyInformation(state, demo, controlsEnabled)
                }
                KeyboardGrid(state, true, Modifier.weight(1f).fillMaxHeight(), expanded = true)
            }
        }
    }
}

@Composable
private fun LandscapeKeyInformation(state: HallPadState, demo: Boolean, controlsEnabled: Boolean) {
    if (state.selectionMode) { BatchKeyInformation(state, compact = true, enabled = controlsEnabled); return }
    val id = state.selectedKey
    var editing by remember { mutableStateOf(false) }
    if (editing) KeyEditor(state, id) { editing = false }
    Box(Modifier.height(88.dp).fillMaxWidth()) { KeyInformation(state, demo, compact = true, enabled = controlsEnabled) }
}

internal fun noteName(note: Int, preferFlats: Boolean = false): String = notePitchNames(preferFlats)[note % 12] + (note / 12 - 1)

@Composable
private fun MixerPage(state: HallPadState, demo: Boolean, dark: Boolean, metronome: MetronomeUiState, controlsEnabled: Boolean, instrumentRequest: Int, onDisplay: () -> Unit, onAbout: () -> Unit, onPresets: () -> Unit) {
    var choosingGlobalInstrument by remember { mutableStateOf(false) }
    LaunchedEffect(instrumentRequest) { if (instrumentRequest > 0 && controlsEnabled) choosingGlobalInstrument = true }
    LaunchedEffect(controlsEnabled) { if (!controlsEnabled) choosingGlobalInstrument = false }
    if (choosingGlobalInstrument) InstrumentPicker(state.instrument, { state.instrument = it; HallPadInstrumentIds[it]?.let { id -> state.sendParameter(2, id) }; choosingGlobalInstrument = false }, allowFollowGlobal = false) { choosingGlobalInstrument = false }
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
            Text("控制台", color = MaterialTheme.colorScheme.onBackground, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            TextButton(enabled = controlsEnabled, onClick = {
                state.releaseAll(); state.performance.center()
                state.instrument = "钢琴"; state.volume = 0.5f; state.attack = 0.02f; state.release = 0.2f
                state.performance.audioSource = "FPGA"; state.performance.joystickSensitivity = 0.5f; state.sendParameter(0x70, 500)
                state.performance.reverbEnabled = false; state.performance.reverbAmount = 0.25f
                state.sendParameter(1, 500); state.sendParameter(2, 1); state.sendParameter(0x40, 0); state.sendParameter(0x42, 250)
                state.persist()
            }) { Text("恢复默认") }
        }
        PresetSummary(state, onPresets, enabled = controlsEnabled)
        MixerSection("声音", "", initiallyExpanded = true, expandRequest = instrumentRequest) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                HallPadChoiceChip(selected = state.performance.fpgaAudioEnabled, enabled = controlsEnabled && state.performance.audioMixAvailable, onClick = { val next = !state.performance.fpgaAudioEnabled; if (demo) state.performance.fpgaAudioEnabled = next else state.sendParameter(0x90, (if (next) 1 else 0) or (if (state.performance.auxAudioEnabled) 2 else 0)) }, label = { Text("FPGA 输入") }, modifier = Modifier.weight(1f))
                HallPadChoiceChip(selected = state.performance.auxAudioEnabled, enabled = controlsEnabled && state.performance.audioMixAvailable, onClick = { val next = !state.performance.auxAudioEnabled; if (demo) state.performance.auxAudioEnabled = next else state.sendParameter(0x90, (if (state.performance.fpgaAudioEnabled) 1 else 0) or (if (next) 2 else 0)) }, label = { Text("耳机孔输入") }, modifier = Modifier.weight(1f))
            }
            if (!state.performance.audioMixAvailable) Text(if (!demo && 0x90 in state.unsupportedParameterIds) "设备固件未实现音源混合（0x0090），已禁用" else "连接支持音源混合的设备后可设置", style = MaterialTheme.typography.bodySmall)
            Row(Modifier.fillMaxWidth().height(48.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Row(Modifier.clickable(enabled = controlsEnabled && state.canControlParameter(2), interactionSource = remember { androidx.compose.foundation.interaction.MutableInteractionSource() }, indication = null) { choosingGlobalInstrument = true }.padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) { InstrumentIcon(state.instrument); Text("全局音色", style = MaterialTheme.typography.bodyMedium) }
                Box(Modifier.weight(1f).fillMaxHeight(), contentAlignment = Alignment.CenterEnd) { if (state.muted) Text("已静音", modifier = Modifier.clickable(enabled = controlsEnabled && !state.mutePending, interactionSource = remember { androidx.compose.foundation.interaction.MutableInteractionSource() }, indication = null) { state.toggleMute() }.padding(horizontal = 8.dp, vertical = 12.dp), color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.labelMedium, maxLines = 1, softWrap = false) }
                TextButton(onClick = { choosingGlobalInstrument = true }, enabled = controlsEnabled && state.canControlParameter(2)) { Text("${state.instrument} ›") }
            }
            SoundSlider("音量", "${(state.volume * 100).toInt()}%", state.volume, 0f..1f, controlsEnabled && !state.muted && state.canControlParameter(1)) { state.volume = it; state.sendParameter(1, (it * 1000).toInt()) }
            SoundSlider("淡出", "${"%.1f".format(state.release * 10f)} s", state.release, 0.01f..0.2f, controlsEnabled && state.canControlParameter(0x21), displayScale = 10f) { state.release = it; state.sendParameter(0x21, (it * 10000).toInt()) }
            SoundSlider("摇杆", "${(state.performance.joystickSensitivity * 100).toInt()}%", state.performance.joystickSensitivity, 0f..1f, controlsEnabled && state.performance.joystickEnabled && state.canControlParameter(0x70)) { state.performance.joystickSensitivity = it; state.sendParameter(0x70, (it * 1000).roundToInt().coerceIn(0, 1000)) }
            PerformanceSettingsCards(state.performance, state::sendParameter) { id -> controlsEnabled && state.canControlParameter(id) }
        }
        MixerSection("节拍器", "${metronome.signature} · ${metronome.bpm} BPM", initiallyExpanded = false) { MetronomeCard(metronome, settingsEnabled = controlsEnabled && !metronome.scoreOwned, playbackEnabled = controlsEnabled && !metronome.scoreOwned && state.canControlParameter(0x50), tempoEnabled = !metronome.scoreOwned && state.canControlParameter(0x51), signatureEnabled = !metronome.scoreOwned && state.canControlParameter(0x52) && state.canControlParameter(0x53)) }
        HorizontalDivider(Modifier.padding(top = 12.dp))
        Row(Modifier.fillMaxWidth().clickable(interactionSource = remember { androidx.compose.foundation.interaction.MutableInteractionSource() }, indication = null, onClick = onDisplay).padding(vertical = 20.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) { Text("显示", style = MaterialTheme.typography.titleMedium); Text("外观与 HDR", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            Text("›", style = MaterialTheme.typography.headlineSmall)
        }
        Row(Modifier.fillMaxWidth().clickable(interactionSource = remember { androidx.compose.foundation.interaction.MutableInteractionSource() }, indication = null, onClick = onAbout).padding(vertical = 20.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) { Text("关于", style = MaterialTheme.typography.titleMedium); Text("版本、构建信息与开源许可", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
            Text("›", style = MaterialTheme.typography.headlineSmall)
        }
    }
}


