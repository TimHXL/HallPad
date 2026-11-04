package com.timhxl.hallbeat

import android.content.Context
import android.os.SystemClock
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.foundation.interaction.collectIsDraggedAsState
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.text.input.rememberTextFieldState
import androidx.compose.foundation.text.input.InputTransformation
import androidx.compose.foundation.text.input.TextFieldLineLimits
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.Alignment
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.sp
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
internal fun ScoreWorkspacePage(environment: ScorePageEnvironment, drumsticks: DrumsticksPreviewState) {
    val state = environment.state
    val deviceReady = environment.deviceReady
    val keyConfigSupported = environment.keyConfigSupported
    val active = environment.active
    val practice = environment.practice
    val demo = environment.demo
    val practiceSupported = environment.practiceSupported
    val sensorMap = environment.sensorMap
    val metronome = environment.metronome
    val recording = environment.recording
    val physicalMask = environment.physicalMask
    val metronomeSupported = environment.metronomeSupported
    val practiceUi by practice.state.collectAsState()
    val following = practiceUi.phase in listOf("RUNNING", "PAUSED", "STARTING")
    val sendingScore = practiceUi.phase in listOf("UPLOADING", "VERIFYING")
    var uploadedSignature by remember { mutableStateOf("") }
    var showResult by remember { mutableStateOf(false) }
    var scoreMetronome by remember { mutableStateOf(false) }
    var recordPanel by remember { mutableStateOf(false) }
    var sdDialog by remember { mutableStateOf(false) }
    var options by remember { mutableStateOf(false) }
    val context = LocalContext.current; val repository = remember { ScoreRepository(context) }; val scope = rememberCoroutineScope()
    var entries by remember { mutableStateOf(repository.list()) }; var selected by remember { mutableStateOf<StoredScore?>(null) }; var score by remember { mutableStateOf<MidiScore?>(null) }
    if(sdDialog && selected!=null && environment.sdCard!=null) {
        val raw=remember(selected!!.id){repository.rawMidi(selected!!.id)}
        SdCardDialog(environment.sdCard, raw, selected!!.title, demo) { sdDialog = false }
    }

    SideEffect { environment.onPlayerOpen(selected != null) }
    DisposableEffect(Unit) { onDispose { environment.onPlayerOpen(false) } }
    var libraryVisible by remember { mutableStateOf(false) }
    var librarySearching by androidx.compose.runtime.saveable.rememberSaveable { mutableStateOf(false) }
    var libraryQuery by androidx.compose.runtime.saveable.rememberSaveable { mutableStateOf("") }
    val libraryScroll = rememberLazyListState()
    val searchScroll = rememberLazyListState()
    val filteredEntries = remember(entries, libraryQuery) {
        val query = libraryQuery.trim()
        if (query.isEmpty()) entries else entries.filter { it.title.contains(query, ignoreCase = true) }
    }
    LaunchedEffect(libraryQuery) { if (libraryQuery.isNotBlank()) searchScroll.scrollToItem(0) }
    var closingScore by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }; var message by remember { mutableStateOf("") }; var trackIndex by remember { mutableIntStateOf(0) }
    suspend fun stopScoreMetronome() {
        if (!metronome.scoreOwned || metronome.scoreReleasing) return
        scoreMetronome = false
        metronome.scoreReleasing = true
        withContext(kotlinx.coroutines.NonCancellable) {
            try { environment.directMidi?.scoreBeat?.shutdown() }
            catch (error: Exception) { message = "停止节拍器未确认：${error.message}" }
            finally { metronome.releaseScore() }
        }
    }
    LaunchedEffect(scoreMetronome) { if (!scoreMetronome && metronome.scoreOwned) stopScoreMetronome() }
    LaunchedEffect(message) {
        val notice = message
        if (notice.isNotEmpty()) {
            android.widget.Toast.makeText(context.applicationContext, notice, android.widget.Toast.LENGTH_LONG).show()
            if (message == notice) message = ""
        }
    }

    var changingTransport by remember { mutableStateOf(false) }
    var running by remember { mutableStateOf(false) }; var position by remember { mutableDoubleStateOf(0.0) }; var speed by remember { mutableFloatStateOf(1f) }
    var loopStart by remember { mutableStateOf<Double?>(null) }; var loopEnd by remember { mutableStateOf<Double?>(null) }
    var transpose by remember { mutableIntStateOf(0) }
    var editingTitle by remember { mutableStateOf(false) }
    var titleHadFocus by remember { mutableStateOf(false) }
    val titleValue = rememberTextFieldState()
    val titleFocus = remember { FocusRequester() }
    val keyboard = LocalSoftwareKeyboardController.current
    val focusManager = androidx.compose.ui.platform.LocalFocusManager.current
    LaunchedEffect(active) { if (!active) { focusManager.clearFocus(); keyboard?.hide() } }
    var titleKeyboardWasVisible by remember { mutableStateOf(false) }
    fun finishTitle() {
        if (!editingTitle) return
        val entry = selected
        if (entry != null && titleValue.text.trim().isNotEmpty()) {
            val renamed = repository.rename(entry.id, titleValue.text.toString().trim())
            selected = renamed
            entries = entries.map { if (it.id == renamed.id) renamed else it }
        }
        editingTitle = false; titleKeyboardWasVisible = false; focusManager.clearFocus(); keyboard?.hide()
    }
    androidx.activity.compose.BackHandler(enabled = editingTitle) { finishTitle() }
    LaunchedEffect(editingTitle) { if (editingTitle) { titleFocus.requestFocus(); keyboard?.show() } }
    var backup by remember { mutableStateOf(repository.backup()) }; var restoringBackup by remember { mutableStateOf(false) }; var deleteTarget by remember { mutableStateOf<StoredScore?>(null) }
    suspend fun restorePracticeKeys() {
        val saved = backup ?: return
        if (repository.keepAppliedKeys()) {
            repository.clearBackup(); backup = null; uploadedSignature = ""
            return
        }
        state.releaseAll()
        saved.notes.forEachIndexed { i, value -> state.notes[i] = value; saved.spellings?.getOrNull(i)?.let { state.setKeySpelling(i, it) } }
        saved.instruments?.forEachIndexed { i, value -> state.keyInstruments[i] = value }
        saved.velocities?.forEachIndexed { i, value -> state.velocities[i] = value }
        saved.modes?.forEachIndexed { i, value -> state.velocityModes[i] = value }
        saved.enabled?.forEachIndexed { i, value -> state.keyEnabled[i] = value }
        state.restorePresetSelection(saved.presetId)
        val expected = List(35) { id -> HallPadSession.KeyConfig(state.keyEnabled[id], state.notes[id], HallPadInstrumentIds[state.keyInstruments[id]] ?: 65535, state.velocityModes[id], state.velocities[id]) }
        state.persist()
        kotlinx.coroutines.withTimeout(15000) {
            while (!demo && state.keyConfigurationConfirmed?.invoke(expected) != true) {
                check(deviceReady) { "设备断开，原键位备份已保留，请重连后恢复" }; delay(50)
            }
        }
        repository.clearBackup(); backup = null; uploadedSignature = ""
    }
    fun openScore(entry: StoredScore) { if (closingScore) {
        android.widget.Toast.makeText(context.applicationContext, "正在停止上一首播放并恢复键位，请稍候", android.widget.Toast.LENGTH_SHORT).show()
        return
    }; if (selected?.id == entry.id) { libraryVisible = false; return }; libraryVisible = false; scoreMetronome = false; practice.cancel(); uploadedSignature = ""; scope.launch { busy = true; running = false; runCatching { withContext(Dispatchers.IO) { repository.read(entry.id) } }.onSuccess { parsed -> selected = entry; score = parsed; transpose = repository.transpose(entry.id).takeIf { offset -> parsed.tracks.all { t -> t.notes.all { n -> n.channel == 9 || n.midi + offset in 0..127 } } } ?: 0; trackIndex = repository.track(entry.id).takeIf { i -> parsed.tracks.any { it.index == i && it.notes.isNotEmpty() } } ?: parsed.tracks.firstOrNull { it.notes.isNotEmpty() }?.index ?: parsed.tracks.first().index; position = repository.position(entry.id); loopStart = null; loopEnd = null }.onFailure { message = "读取失败：${it.message}" }; busy = false } }
    val importer = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
        if (uris.isNotEmpty()) scope.launch {
            busy = true
            var first: StoredScore? = null
            val failures = mutableListOf<String>()
            var imported = 0
            try {
                for (uri in uris.distinct()) {
                    runCatching {
                        withContext(Dispatchers.IO) {
                            val title = context.contentResolver.query(uri, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null } ?: "导入曲目.mid"
                            val bytes = context.contentResolver.openInputStream(uri)?.use { input ->
                                val output = java.io.ByteArrayOutputStream(); val buffer = ByteArray(8192); var total = 0
                                while (true) { val size = input.read(buffer); if (size < 0) break; total += size; require(total <= 8 * 1024 * 1024) { "文件不能超过 8 MB" }; output.write(buffer, 0, size) }
                                output.toByteArray()
                            } ?: error("无法打开文件")
                            MidiScoreParser.parse(bytes)
                            repository.add(bytes, title.substringBeforeLast('.'))
                        }
                    }.onSuccess { imported++; if (first == null) first = it }
                     .onFailure { failures.add("${uri.lastPathSegment}: ${it.message ?: "文件损坏"}") }
                }
                entries = repository.list()
                // Batch import stays in the library; never interrupts a playing score.
                if (uris.size == 1 && !running) first?.let { openScore(it) }
                val importResult = "已导入 $imported 首" + if (failures.isEmpty()) "" else "，失败 ${failures.size} 首：${failures.first()}"
                android.widget.Toast.makeText(context.applicationContext, importResult, if (failures.isEmpty()) android.widget.Toast.LENGTH_SHORT else android.widget.Toast.LENGTH_LONG).show()
            } finally { busy = false }
        }
    }
    var exportBytes by remember { mutableStateOf<ByteArray?>(null) }
    val exporter = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("audio/midi")) { uri ->
        val bytes = exportBytes; exportBytes = null
        if (uri != null && bytes != null) scope.launch {
            runCatching { withContext(Dispatchers.IO) { context.contentResolver.openOutputStream(uri, "wt")?.use { it.write(bytes) } ?: error("无法写入文件") } }
                .onSuccess { message = "曲谱已导出" }.onFailure { message = "导出失败：${it.message}" }
        }
    }
    if (recordPanel) RecordingPage(recording, metronome, deviceReady && !demo, metronomeSupported, onStart = { bpm, beats, unit ->
        recording.start(sensorMap, state.notes.toList(), state.velocities.mapIndexed { index, value -> if (state.keyEnabled[index]) value else 0 }, physicalMask, bpm, beats, unit, metronome.recordingLeadInMs())
    }, onSave = { title, key ->
        var failure: String? = null
        runCatching { val bytes = recording.finish(key); MidiScoreParser.parse(bytes); repository.add(bytes, title) }.onSuccess { saved ->
            entries = listOf(saved) + repository.list().filterNot { it.id == saved.id }
            repository.order(entries.map { it.id })
            libraryQuery = ""; librarySearching = false
            scope.launch { libraryScroll.scrollToItem(0); searchScroll.scrollToItem(0) }
            recording.clear(); recordPanel = false; message = ""
        }.onFailure { failure = it.message ?: "保存失败" }
        failure
    }, onClose = {
        recordPanel = false; libraryQuery = ""; librarySearching = false
        scope.launch { libraryScroll.scrollToItem(0); searchScroll.scrollToItem(0) }
    })
    val current = remember(score, transpose) { score?.let { original -> original.copy(tracks = original.tracks.map { t -> t.copy(name = context.getSharedPreferences("score_track_names", Context.MODE_PRIVATE).getString("${selected?.id}:${t.index}", t.name) ?: t.name) }).transposed(transpose) } }
    val track = current?.tracks?.firstOrNull { it.index == trackIndex }
    val notes = track?.notes ?: emptyList()
    val abStart = loopStart?.takeIf { a -> loopEnd?.let { it > a } == true }
    val abEnd = if (abStart != null) loopEnd else null
    val practiceNotes = notes.filter { note ->
        (abStart == null || current!!.seconds(note.tick + note.duration) > abStart) &&
            (abEnd == null || current!!.seconds(note.tick) < abEnd)
    }
    var uploadedGroupTimes by remember { mutableStateOf<List<Double>>(emptyList()) }
    var uploadedEnd by remember { mutableStateOf<Double?>(null) }

    var sendPreview by remember { mutableStateOf<List<Int>?>(null) }
    var sendStage by remember { mutableIntStateOf(0) }
    suspend fun preparePracticeKeys(proposed: List<Int>? = null) {
        // Match the currently applied pitches, including enharmonic aliases.
        message = ""
        val required = practiceNotes.filter { it.channel != 9 }.map { it.midi }.distinct()
        val plan = if (proposed == null) HiddenKeyPlan.practice(required, state.notes.toList(), state.keyEnabled.toList()) else proposed.mapIndexedNotNull { key, midi -> if (state.notes[key] != midi || (!state.keyEnabled[key] && midi in required)) key to midi else null }.toMap()
        if (plan.isEmpty()) return
        val entry = selected ?: error("请先打开曲谱")
        if (backup == null || repository.keepAppliedKeys()) {
            // Any subsequent automatic borrowing restores to the manually applied scheme.
            val saved = ScoreKeyBackup(entry.id, state.notes.toList(), state.keyInstruments.toList(), state.velocities.toList(), state.velocityModes.toList(), state.keyEnabled.toList(), state.activePresetId, transpose, repository.keySignature(entry.id), score!!.keys.toList(), List(35) { state.keyUsesFlats(it) })
            check(repository.saveBackup(saved)) { "无法保存原键位，已取消临时分配" }
            backup = saved
        }
        state.releaseAll()
        plan.forEach { (key, midi) -> state.notes[key] = midi; state.keyEnabled[key] = true; state.setKeySpelling(key, current?.noteName(midi, 0)?.contains("♭") == true) }
        val expected = List(35) { id -> HallPadSession.KeyConfig(state.keyEnabled[id], state.notes[id], HallPadInstrumentIds[state.keyInstruments[id]] ?: 65535, state.velocityModes[id], state.velocities[id]) }
        state.persist()
        kotlinx.coroutines.withTimeout(15000) {
            while (!demo && state.keyConfigurationConfirmed?.invoke(expected) != true) {
                check(deviceReady) { "设备断开，临时分配未确认" }; delay(50)
            }
        }
    }

    fun sendPrepared(proposed: List<Int>? = null) {
        val value = current ?: return
        val rangeStart = abStart ?: 0.0
        val rangeEnd = abEnd
        val rangeSignature = ":${abStart}:${abEnd}"
        sendStage = 0; sendPreview = null
        changingTransport = true; running = false
        practice.clearError()
        scope.launch {
            try {
                ScorePlaybackService.pauseAndJoin(context)
                environment.directMidi?.cleanupError?.let { error(it) }
                preparePracticeKeys(proposed)
                val compiled = PracticeWire.compile(value, trackIndex, state.notes.toList(), state.keyEnabled.toList(), sensorMap, rangeStart, rangeEnd)
                practice.upload(compiled, demo)
                uploadedGroupTimes = compiled.groups.map { rangeStart + it.startMs / 1000.0 }
                uploadedEnd = rangeEnd ?: rangeStart + compiled.durationMs / 1000.0
                uploadedSignature = practiceSignatureValue(selected?.id, trackIndex, transpose, state.notes.toList(), state.keyEnabled.toList()) + rangeSignature
            } catch (error: Exception) { message = "无法准备跟随演奏：${error.message}" }
            finally { changingTransport = false }
        }
    }
    fun requestSend() {
        try {
            val required = practiceNotes.filter { it.channel != 9 }.map { it.midi }.distinct()
            val available = state.notes.indices.filter { state.keyEnabled[it] }.map { state.notes[it] }.toSet()
            if (required.all { it in available }) sendPrepared()
            else {
                val value = current ?: return
                val key = value.keys.lastOrNull { it.tick <= 0L }
                if ((key?.sharps ?: 0) == 0) {
                    // C major, A minor and unspecified signatures use the spare-key preview directly.
                    val plan = HiddenKeyPlan.practice(required, state.notes.toList(), state.keyEnabled.toList())
                    sendPreview = state.notes.toMutableList().also { result -> plan.forEach { (id, midi) -> result[id] = midi } }
                    sendStage = 2
                } else {
                    sendPreview = List(35) { value.mappedNote(defaultNote(it)) }
                    sendStage = 1
                }
            }
        } catch (error: Exception) { message = error.message ?: "无法准备键位" }
    }

    val duration = remember(current, trackIndex) { if (current != null) notes.maxOfOrNull { current.seconds(it.tick + it.duration) } ?: 0.0 else 0.0 }
    val groups = remember(current, trackIndex) { notes.groupBy { it.tick }.entries.toList() }
    val groupTimes = remember(current, trackIndex) { groups.map { current!!.seconds(it.key) }.toDoubleArray() }
    fun practiceSignature() = "${selected?.id}:$trackIndex:$transpose:${state.notes.joinToString(",")}:${state.keyEnabled.joinToString(",")}:${abStart}:${abEnd}"
    val signature = practiceSignature()
    var followSpeed by remember { mutableFloatStateOf(1f) }
    LaunchedEffect(following) { if (following) running = false }
    LaunchedEffect(practiceUi.phase, uploadedEnd, duration) {
        if (practiceUi.phase == "RUNNING") {
            val startPosition = position
            val startTime = SystemClock.elapsedRealtime()
            val end = uploadedEnd ?: duration
            while (position < end) {
                position = (startPosition + (SystemClock.elapsedRealtime() - startTime) / 1000.0 * followSpeed)
                    .coerceAtMost(end)
                delay(16)
            }
        }
    }
    LaunchedEffect(practiceUi.result) { if (practiceUi.result != null) { running = false; position = uploadedEnd ?: duration; showResult = true; options = false } }
    LaunchedEffect(active, practiceUi.phase) { if (!active && practiceUi.phase == "RUNNING") practice.pause() }
    LaunchedEffect(deviceReady) { if (!deviceReady) running = false }
    LaunchedEffect(running) {
        if (!running && metronome.scoreOwned && !ScorePlaybackService.playing) stopScoreMetronome()
    }
    LaunchedEffect(state.muted) { if (state.muted) { running = false; practice.pause() } }
    val playbackClock = remember { doubleArrayOf(0.0, 0.0) }
    val playbackSpeed by rememberUpdatedState(speed)
    val playbackMetronome by rememberUpdatedState(scoreMetronome)
    val searchIndex = groupTimes.binarySearch(position)
    val currentIndex = (if (searchIndex >= 0) searchIndex else -searchIndex - 2).coerceAtLeast(0)
    // Reuse the physical pitches; absent pitches share hidden key36 dynamically.
    LaunchedEffect(running, deviceReady, current, trackIndex, loopStart, loopEnd, following) {
        if (running && !following && current != null) {
            val timeline = try {
                withContext(Dispatchers.Default) { DirectMidiTimeline.compile(current, notes) }
            } catch (cancelled: kotlinx.coroutines.CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                message = error.message ?: "曲谱无法演奏"; running = false
                stopScoreMetronome()
                return@LaunchedEffect
            }
            val direct = environment.directMidi.takeUnless { demo }
            val entry = selected; val playingTrack = trackIndex
            ScorePlaybackService.play(context, entry?.title ?: "HallPad", remote = !demo, onStop = { running = false; scope.launch { stopScoreMetronome() } }, onError = { message = it }) {
                if (!demo) check(direct != null) { "未连接支持 MIDI 直发的设备" }
                val beatTransport = direct?.scoreBeat
                val beats = runCatching { scoreBeatTimeline(current, duration) }.getOrElse {
                    message = it.message ?: "无法创建曲谱拍点"; scoreMetronome = false; emptyList()
                }
                var beatCursor: Int
                val beatScope = kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.currentCoroutineContext())
                var clearRequired = false
                try {
                    if (direct != null) {
                        direct.prepare()
                        clearRequired = true
                        direct.clear()
                    }
                    kotlinx.coroutines.currentCoroutineContext().ensureActive()
                    val voices = linkedMapOf<Int, DirectMidiVoice>()
                    var demoKeysDirty = true
                    fun updateDemoKeys() {
                        if (!demo || !demoKeysDirty) return
                        demoKeysDirty = false
                        state.playbackPressed.clear()
                        voices.values.groupBy { it.midi }.forEach { (midi, activeVoices) ->
                            val id = state.notes.indices.firstOrNull { state.keyEnabled[it] && state.notes[it] == midi }
                            if (id != null) state.playbackPressed[id] = activeVoices.maxOf { it.velocity }
                        }
                    }
                    suspend fun rebuild(time: Double): Int {
                        voices.clear()
                        demoKeysDirty = true
                        var index = 0
                        while (index < timeline.events.size && timeline.events[index].seconds < time) {
                            val event = timeline.events[index++]
                            if (event.down) voices[event.voice.id] = event.voice else voices.remove(event.voice.id)
                        }
                        direct?.state(voices.values)
                        updateDemoKeys()
                        return index
                    }
                    var index = rebuild(position)
                    beatCursor = beats.indexOfFirst { it.seconds >= position - 0.001 }.let { if (it < 0) beats.size else it }
                    playbackClock[0] = position; playbackClock[1] = SystemClock.elapsedRealtime().toDouble()
                    var lastSnapshot = SystemClock.elapsedRealtime()
                    while (running) {
                        direct?.checkHealthy()
                        if (!demo && playbackMetronome && beatTransport?.supported != true) {
                            message = "当前固件未实现曲谱同步节拍器，请更新配套 FPGA 固件"
                            scoreMetronome = false
                        }
                        beatTransport?.update(playbackMetronome, beatScope)
                        val now = SystemClock.elapsedRealtime()
                        val next = playbackClock[0] + (now - playbackClock[1]) / 1000.0 * playbackSpeed
                        val end = loopEnd?.takeIf { loopStart != null && it > loopStart!! } ?: duration
                        val limit = next.coerceAtMost(end)
                        while (beatCursor < beats.size && beats[beatCursor].seconds <= limit && beats[beatCursor].seconds < end) {
                            val beat = beats[beatCursor++]
                            // Drop old clicks after a scheduling stall rather than playing a catch-up burst.
                            if (playbackMetronome && beat.seconds >= limit - 0.08 * playbackSpeed) beatTransport?.beat(beat)
                        }
                        while (index < timeline.events.size && timeline.events[index].seconds <= limit) {
                            val event = timeline.events[index++]
                            direct?.note(event.voice, event.down)
                            demoKeysDirty = true
                            if (event.down) voices[event.voice.id] = event.voice else voices.remove(event.voice.id)
                        }
                        updateDemoKeys()
                        direct?.flushPending()
                        // Prepare the next absent pitch up to 300 ms before its onset.
                        // ACK/readback are asynchronous; normal note events keep running.
                        var lookahead = index
                        while (lookahead < timeline.events.size && timeline.events[lookahead].seconds <= limit + 0.3 * playbackSpeed) {
                            val candidate = timeline.events[lookahead++]
                            if (candidate.down && direct?.needsHidden(candidate.voice) == true) {
                                direct?.preload(candidate.voice)
                                break
                            }
                        }
                        if (now - lastSnapshot >= 200L) { direct?.state(voices.values); lastSnapshot = now }
                        if (next >= end) {
                            if (loopStart != null && loopEnd != null) {
                                direct?.clear()
                                position = loopStart!!; index = rebuild(position)
                                beatCursor = beats.indexOfFirst { it.seconds >= position - 0.001 }.let { if (it < 0) beats.size else it }
                                playbackClock[0] = position; playbackClock[1] = SystemClock.elapsedRealtime().toDouble()
                                lastSnapshot = SystemClock.elapsedRealtime()
                            } else { position = duration; running = false }
                        } else position = next
                        delay(5)
                    }
                } finally {
                    stopScoreMetronome()
                    if (!metronome.scoreOwned && metronome.running) metronome.stopConsole()
                    if (demo) state.playbackPressed.clear()
                    if (clearRequired && direct != null) kotlinx.coroutines.withContext(kotlinx.coroutines.NonCancellable) {
                        runCatching { direct.clear() }.onFailure { message = "停止音符确认失败：${it.message}；等待设备租约释放" }
                    }
                    if (entry != null) repository.save(entry.id, playingTrack, position)
                }
            }
        } else ScorePlaybackService.pause(context)
    }
    LaunchedEffect(active) { if (!active) { finishTitle(); selected?.let { repository.save(it.id, trackIndex, position) } } }
    DisposableEffect(selected?.id, trackIndex) { val entry = selected; val index = trackIndex; onDispose { if (entry != null) repository.save(entry.id, index, position) } }
    fun saveProgress() { selected?.let { repository.save(it.id, trackIndex, position) } }
    var speedMenu by remember { mutableStateOf(false) }
    val pageTransition = remember { androidx.compose.animation.core.Animatable(1f) }
    LaunchedEffect(selected?.id, libraryVisible) { pageTransition.snapTo(0f); pageTransition.animateTo(1f, tween(260)) }
    fun closeScore() {
        if (closingScore || sendingScore) return
        closingScore = true
        running = false
        // Navigation is independent of remote cleanup and directory scans.
        libraryVisible = true
        options = false
        val closingEntry = selected
        val closingTrack = trackIndex
        val closingPosition = position

        ScorePlaybackService.pause(context)
        scope.launch {
            try {
                // Keep the page visible while Bluetooth cleanup is pending.
                finishTitle(); practice.cancel()
                try {
                    ScorePlaybackService.pauseAndJoin(context)
                } catch (error: kotlinx.coroutines.CancellationException) {
                    throw error
                } catch (error: Exception) {
                    message = "停止播放未确认：${error.message}"
                }
                try {
                    restorePracticeKeys()
                } catch (error: kotlinx.coroutines.CancellationException) {
                    throw error
                } catch (error: Exception) {
                    // restorePracticeKeys retains the backup until confirmation.
                    message = "原键位恢复未确认，备份已保留：${error.message}"
                }
                stopScoreMetronome()
                withContext(Dispatchers.IO) {
                    closingEntry?.let { repository.save(it.id, closingTrack, closingPosition) }
                }
                entries = withContext(Dispatchers.IO) { repository.list() }
            } catch (error: kotlinx.coroutines.CancellationException) {
                throw error
            } catch (error: Exception) {
                message = "返回曲库时发生错误：${error.message}"
            } finally {
                closingScore = false

            }
        }
    }

    androidx.activity.compose.BackHandler(enabled = selected != null && !libraryVisible && !editingTitle && !options && !recordPanel) { closeScore() }
    val keyboardVisible = WindowInsets.ime.getBottom(androidx.compose.ui.platform.LocalDensity.current) > 0
    LaunchedEffect(editingTitle, keyboardVisible) {
        if (editingTitle && keyboardVisible) titleKeyboardWasVisible = true
        if (editingTitle && titleKeyboardWasVisible && !keyboardVisible) finishTitle()
    }
    KeepScoreTitleLayout(active && selected != null && (editingTitle || keyboardVisible))
    Column(Modifier.fillMaxSize().graphicsLayer { alpha = 1f; translationX = size.width * (1f - pageTransition.value) * if (selected != null) 0.12f else -0.06f }, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        if (selected == null || libraryVisible) ScoreLibraryHeader(
            searching = librarySearching, query = libraryQuery,
            onSearching = { librarySearching = it }, onQuery = { libraryQuery = it },
            busy = busy, recording = recording.recording,
            onImport = { importer.launch(arrayOf("audio/midi", "audio/x-midi", "application/octet-stream", "*/*")) },
            onRecord = { recordPanel = true })
        else Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            if (selected != null && !libraryVisible) IconButton(enabled = !closingScore && !sendingScore, onClick = { closeScore() }) { Icon(painterResource(R.drawable.ic_back), contentDescription = "返回曲库") }
            if (editingTitle && selected != null && !libraryVisible) BasicTextField(state = titleValue, inputTransformation = InputTransformation { if (length > 100) revertAllChanges() }, modifier = Modifier.weight(1f).focusRequester(titleFocus).numericFocusTarget().onFocusChanged { if (it.isFocused) titleHadFocus = true else if (titleHadFocus && editingTitle) finishTitle() }.padding(vertical = 8.dp), textStyle = MaterialTheme.typography.titleLarge.copy(color = MaterialTheme.colorScheme.onSurface, fontWeight = FontWeight.Bold), lineLimits = TextFieldLineLimits.SingleLine, keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done), onKeyboardAction = { finishTitle() })
            else Text(if (selected == null || libraryVisible) "我的曲谱" else selected!!.title, modifier = Modifier.weight(1f).clickable(enabled = selected != null && !libraryVisible, interactionSource = remember { MutableInteractionSource() }, indication = null) { val name = selected!!.title; titleValue.edit { replace(0, length, name); selection = TextRange(0, length) }; titleHadFocus = false; editingTitle = true }.padding(vertical = 8.dp), style = if (selected == null || libraryVisible) MaterialTheme.typography.headlineSmall else MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (selected != null && !libraryVisible) IconButton(enabled = !busy, onClick = {
                runCatching { MidiScoreWriter.write(current ?: error("曲谱尚未加载")) }.onSuccess { bytes ->
                    exportBytes = bytes
                    exporter.launch(selected!!.title.replace(Regex("[\\\\/:*?\"<>|]"), "_") + ".mid")
                }.onFailure { message = "导出失败：${it.message}" }
            }) { Icon(painterResource(R.drawable.ic_share_arrow), contentDescription = "导出 MIDI", tint = LocalContentColor.current) }
            if (selected != null && !libraryVisible) IconButton(enabled = !sendingScore, onClick = { options = true }) { Icon(painterResource(R.drawable.ic_key_settings), contentDescription = "练习设置") }
        }
        if (current != null && selected != null && !libraryVisible) {
            if(environment.temporaryKeyMapping) Text("设备使用曲目临时键位，结束后自动恢复")
            PracticeControls(practice, deviceReady && practiceSupported, uploadedSignature == signature, busy = changingTransport, onSend = {
                requestSend()
            }, onStart = {
                changingTransport = true; running = false
                scope.launch {
                    try {
                        ScorePlaybackService.pauseAndJoin(context)
                        environment.directMidi?.cleanupError?.let { error(it) }
                        position = uploadedGroupTimes.firstOrNull() ?: 0.0
                        followSpeed = speed
                        practice.start(followSpeed); options = false
                    } catch (error: Exception) { message = "停止自动播放失败：${error.message}" }
                    finally { changingTransport = false }
                }
            })

        }
        if (busy || (libraryVisible && closingScore)) LinearProgressIndicator(Modifier.fillMaxWidth())
        if (current == null || selected == null || libraryVisible) {
            if (running && selected != null) Row(verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = { libraryVisible = false }) { Text("正在演奏 · ${selected!!.title}", maxLines = 1, overflow = TextOverflow.Ellipsis) }
                IconButton(onClick = { running = false; saveProgress() }) { Icon(painterResource(android.R.drawable.ic_media_pause), "暂停演奏") }
            }
            val recent = entries.firstOrNull { it.id == repository.last() }

            ScoreLibraryList(filteredEntries, Modifier.weight(1f).fillMaxWidth(),
                listState = if (libraryQuery.isBlank()) libraryScroll else searchScroll,
                reorderEnabled = libraryQuery.isBlank(), recent = recent.takeIf { libraryQuery.isBlank() }, onOpen = { openScore(it) }, onDelete = { deleteTarget = it },
                onOrder = { ordered -> entries = ordered; repository.order(ordered.map { it.id }) })

        } else {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
                val meter = current.meters.lastOrNull { it.tick <= (groups.getOrNull(currentIndex)?.key ?: 0) } ?: ScoreMeter(0, 4, 4)
                Text("${current.keyLabel(groups.getOrNull(currentIndex)?.key ?: 0)} · ${meter.numerator}/${meter.denominator}", color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.labelLarge, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                if (following) Text("已完成 ${practiceUi.correct}/${uploadedGroupTimes.size} · 按错 ${practiceUi.wrong} 次", style = MaterialTheme.typography.labelSmall, maxLines = 1, modifier = Modifier.clickable(enabled = demo && practiceUi.phase == "RUNNING", interactionSource = remember { MutableInteractionSource() }, indication = null) { practice.demoStrike() }.padding(end = 6.dp))
                Box {
                    TextButton(enabled = !following, onClick = { speedMenu = true }) { Text("${speed.toString().removeSuffix(".0")} x ▾") }
                    DropdownMenu(expanded = speedMenu && !following, onDismissRequest = { speedMenu = false }) {
                        listOf(0.5f, 0.75f, 1f, 1.5f, 2f).forEach { value -> DropdownMenuItem(text = { Text("${value.toString().removeSuffix(".0")} x", fontWeight = if (speed == value) FontWeight.Bold else FontWeight.Normal) }, onClick = { if (running && !following) { val now = SystemClock.elapsedRealtime(); val end = loopEnd?.takeIf { loopStart != null && it > loopStart!! } ?: duration; position = (playbackClock[0] + (now - playbackClock[1]) / 1000.0 * speed).coerceIn(0.0, end); playbackClock[0] = position; playbackClock[1] = now.toDouble() }; speed = value; speedMenu = false }) }
                    }
                }
            }
            val scoreTick = current.tickAtSeconds(position)
            val scoreMeter = current.meters.lastOrNull { it.tick <= scoreTick } ?: ScoreMeter(0, 4, 4)
            val beatTicks = current.resolution * 4.0 / scoreMeter.denominator
            val meterStart = current.meters.filter { it.tick <= scoreTick }.fold(0L to 0L) { previous, event ->
                val old = current.meters.lastOrNull { it.tick <= previous.first } ?: ScoreMeter(0, 4, 4)
                event.tick to (previous.second + ((event.tick - previous.first) / (current.resolution * 4.0 / old.denominator * old.numerator)).toLong())
            }
            val measure = meterStart.second + ((scoreTick - meterStart.first) / (beatTicks * scoreMeter.numerator)).toLong() + 1
            val beatPosition = ((scoreTick - meterStart.first) / beatTicks) % scoreMeter.numerator + 1
            val scoreBpm = (60000000.0 / (current.tempos.lastOrNull { it.tick <= scoreTick }?.micros ?: 500000) * speed).toInt()
            val scorePhase = (scoreTick - meterStart.first) / beatTicks
            SideEffect { if (metronome.scoreOwned) metronome.transportBeat = if (scoreMetronome && (active || running)) scorePhase else null }
            DisposableEffect(selected?.id) { onDispose { metronome.transportBeat = null } }
            LaunchedEffect(scoreBpm, scoreMeter, scoreMetronome, running, practiceUi.phase) {
                if (!metronome.scoreOwned || metronome.scoreReleasing) return@LaunchedEffect
                metronome.bpm = scoreBpm.coerceIn(30, 240)
                metronome.signature = "${scoreMeter.numerator}/${scoreMeter.denominator}"
                metronome.running = scoreMetronome && (running || practiceUi.phase == "RUNNING")
                // Score beats are emitted by the playback transport, never the free-running parameter metronome.
            }
            BoxWithConstraints(Modifier.weight(1f).fillMaxWidth()) {
                val compact = maxHeight < 230.dp
                val palette = MaterialTheme.colorScheme
                Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Box(Modifier.weight(0.66f).fillMaxHeight()) {
                        val index = currentIndex
                        val group = groups.getOrNull(index)
                        Surface(modifier = Modifier.fillMaxSize(), color = palette.surfaceContainerHigh, contentColor = palette.onSurface, shape = RoundedCornerShape(28.dp)) {
                            Box(Modifier.fillMaxSize()) {
                            CurrentNotePanel(
                                heading = if (following) "跟随弹奏" else if (running) "正在演奏" else "当前音符",
                                counter = if (following) "${(practiceUi.group + 1).coerceAtMost(uploadedGroupTimes.size)} / ${uploadedGroupTimes.size}" else "${index + 1} / ${groups.size}",
                                notes = group?.value?.map { current.noteName(it.midi, it.tick) } ?: emptyList(),
                                locations = group?.value?.joinToString("；") { note ->
                                    val id = (0 until 35).firstOrNull { state.keyEnabled[it] && state.notes[it] == note.midi }
                                    if (id == null) { if (following) "需要配置键位" else "MIDI ${note.midi}" }
                                    else "${id / 7 + 1} 行 ${id % 7 + 1} 列"
                                } ?: "",
                                durations = group?.value?.joinToString(" / ") { "持续 ${"%.2f".format(it.duration / beatTicks)} 拍" } ?: "",
                                measure = "第 ${measure} 小节 · 第 ${"%.2f".format(beatPosition)} 拍",
                                tempo = "每分钟 ${scoreBpm} 拍", compact = compact,
                                modifier = Modifier.fillMaxSize().padding(bottom = 10.dp).padding(if (compact) 8.dp else 16.dp))
                            val start = groupTimes.getOrNull(index) ?: 0.0
                            val end = group?.value?.maxOfOrNull { current.seconds(it.tick + it.duration) } ?: start
                            LinearProgressIndicator(progress = { ((position - start) / (end - start).coerceAtLeast(0.001)).toFloat().coerceIn(0f, 1f) }, modifier = Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(5.dp))
                            }
                        }
                    }
                    key(selected?.id, trackIndex) { UpcomingNoteQueue(current, groups, currentIndex, running || practiceUi.phase == "RUNNING", Modifier.weight(0.34f).fillMaxHeight(), onDelete = { tick ->
                        if (!following && !sendingScore) selected?.let { entry ->
                            running = false; practice.cancel(); uploadedSignature = ""
                            repository.deleteGroup(entry.id, trackIndex, tick)
                            score = score?.let { original -> original.copy(tracks = original.tracks.map { t -> if (t.index == trackIndex) t.copy(notes = t.notes.filterNot { it.tick == tick }) else t }) }
                        }
                    }, onSelect = { index -> if (!following) { position = groupTimes[index]; if (loopStart != null && loopEnd != null && (position < loopStart!! || position >= loopEnd!!)) { loopStart = null; loopEnd = null }; running = false; saveProgress() } }) }
                }
            }
            Row(Modifier.fillMaxWidth().padding(top = 10.dp, bottom = 2.dp), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                IconButton(enabled = !following, onClick = { running = false; position = 0.0; saveProgress() }, modifier = Modifier.width(80.dp).height(52.dp)) { Icon(painterResource(R.drawable.ic_restart), contentDescription = "回到开头", modifier = Modifier.size(28.dp)) }
                Spacer(Modifier.width(12.dp))
                FilledIconButton(enabled = !changingTransport && practiceUi.phase != "STARTING" && !sendingScore, onClick = { if (practiceUi.phase == "RUNNING") practice.pause() else if (practiceUi.phase == "PAUSED") practice.resume() else { if (position >= duration) position = 0.0; running = !running; saveProgress() } }, modifier = Modifier.size(64.dp), shape = androidx.compose.foundation.shape.CircleShape) { Icon(painterResource(if (running || practiceUi.phase == "RUNNING") R.drawable.ic_pause else R.drawable.ic_play), contentDescription = if (running || practiceUi.phase == "RUNNING") "暂停演奏" else "开始演奏", modifier = Modifier.size(34.dp)) }
                Spacer(Modifier.width(12.dp))
                TextButton(modifier = Modifier.width(80.dp), contentPadding = PaddingValues(horizontal = 2.dp), enabled = !metronome.scoreReleasing && !following && (demo || environment.directMidi?.scoreBeat?.supported == true) && scoreMeter.numerator in 1..12 && scoreMeter.denominator in listOf(2, 4, 8, 16), onClick = {
                    if (scoreMetronome) {
                        scope.launch { stopScoreMetronome() }
                    } else {
                        // Queue free-running STOP before the score transport's reliable START.
                        metronome.stopConsole()
                        metronome.scoreOwned = true
                        metronome.bpm = scoreBpm
                        metronome.signature = "${scoreMeter.numerator}/${scoreMeter.denominator}"
                        scoreMetronome = true
                        metronome.transportBeat = scorePhase
                    }
                }) { Text(if (scoreMetronome) "节拍器·开" else "节拍器·关", style = MaterialTheme.typography.labelMedium, maxLines = 1) }
            }
            Row(Modifier.fillMaxWidth().offset(y = 4.dp).height(40.dp), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                TextButton(enabled = !following, onClick = { loopStart = position; loopEnd = null }, modifier = Modifier.weight(1f), contentPadding = PaddingValues(horizontal = 4.dp)) { Text("A ${loopStart?.let { formatScoreTime(it) } ?: "起点"}", fontFamily = HallPadMono, maxLines = 1) }
                TextButton(enabled = !following && loopStart != null && position > loopStart!!, onClick = { loopEnd = position }, modifier = Modifier.weight(1f), contentPadding = PaddingValues(horizontal = 4.dp)) { Text("B ${loopEnd?.let { formatScoreTime(it) } ?: "终点"}", fontFamily = HallPadMono, maxLines = 1) }
                TextButton(enabled = !following && (loopStart != null || loopEnd != null), onClick = { loopStart = null; loopEnd = null }, contentPadding = PaddingValues(horizontal = 6.dp)) { Text("清除循环", maxLines = 1) }
            }
            if (practiceUi.phase == "ERROR" && practiceUi.error.startsWith("请先配置键位")) Text(practiceUi.error, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
            ScoreTimeline(position, duration, loopStart, loopEnd, onSeek = { if (!following) { running = false; position = it } }, onSeekFinished = { saveProgress() })


        }
    }
    if (sendStage != 0 && sendPreview != null && current != null) {
        val presentPitches = state.notes.indices.filter { state.keyEnabled[it] }.map { state.notes[it] }.toSet()
        val missingPitches = practiceNotes.filter { it.channel != 9 }.map { it.midi }.distinct().filter { it !in presentPitches }.sorted()
        SendKeyPreviewDialog(sendStage == 1, current.keyLabel(), sendPreview!!.map { current.noteName(it, 0) }, missingPitches.map { current.noteName(it, 0) },
            onCancel = { sendStage = 0; sendPreview = null },
            onConfirm = {
                val proposed = sendPreview!!
                try {
                    val required = practiceNotes.filter { it.channel != 9 }.map { it.midi }.distinct()
                    require(required.all { it in proposed }) { "此键位方案仍有未分配音高，请选择“否”预览借用方案" }
                    sendPrepared(proposed)
                } catch (error: Exception) { message = error.message ?: "键位不可用" }
            }, onContinue = {
                try {
                    val required = practiceNotes.filter { it.channel != 9 }.map { it.midi }.distinct()
                    val plan = HiddenKeyPlan.practice(required, state.notes.toList(), state.keyEnabled.toList())
                    sendPreview = state.notes.toMutableList().also { result -> plan.forEach { (key, midi) -> result[key] = midi } }
                    sendStage = 2
                } catch (error: Exception) { message = error.message ?: "可用键位不足"; sendStage = 0; sendPreview = null }
            })
    }
    if (showResult && practiceUi.result != null) PracticeResultDialog(practiceUi.result!!) { showResult = false }
    if (options && current != null) {
        val settings = ScorePracticeSettingsModel(current.tracks.filter { it.notes.isNotEmpty() }, trackIndex, transpose, following || restoringBackup, transpose > -12 && score!!.tracks.all { t -> t.notes.all { it.channel == 9 || it.midi + transpose - 1 in 0..127 } }, transpose < 12 && score!!.tracks.all { t -> t.notes.all { it.channel == 9 || it.midi + transpose + 1 in 0..127 } }, current.keyLabel(), List(35) { current.noteName(current.mappedNote(defaultNote(it)), 0) }, backup != null, deviceReady && keyConfigSupported, score!!.keys.firstOrNull() ?: ScoreKey(0, 0, false))
        ScorePracticeSettings(settings, onTrack = { index ->
            if (trackIndex != index && !following) { practice.cancel(); uploadedSignature = ""; saveProgress(); running = false; trackIndex = index; position = 0.0; loopStart = null; loopEnd = null }
        }, onRenameTrack = { index, name ->
            selected?.let { entry ->
                context.getSharedPreferences("score_track_names", Context.MODE_PRIVATE).edit().putString("${entry.id}:$index", name).apply()
                score = score?.copy(tracks = score!!.tracks.map { if (it.index == index) it.copy(name = name) else it })
            }
        }, onTranspose = { delta ->
            practice.cancel(); transpose += delta; selected?.let { repository.transpose(it.id, transpose) }
        }, onApply = {
            val entry = selected
            if (entry != null && backup == null) {
                val saved = ScoreKeyBackup(entry.id, state.notes.toList(), state.keyInstruments.toList(), state.velocities.toList(), state.velocityModes.toList(), state.keyEnabled.toList(), state.activePresetId, transpose, repository.keySignature(entry.id), score!!.keys.toList(), List(35) { state.keyUsesFlats(it) })
                if (repository.saveBackup(saved)) backup = saved else message = "无法保存原键位，请重试"
            }
            if (backup != null) { practice.cancel(); uploadedSignature = ""; running = false; state.releaseAll(); repeat(35) { id -> val midi = current.mappedNote(defaultNote(id)); state.notes[id] = midi; state.setKeySpelling(id, current.noteName(midi, 0).contains("♭")) }; state.persist(); repository.keepAppliedKeys(true) }
        }, onRestore = {
            val saved = backup
            if (saved != null && !restoringBackup) {
                practice.cancel(); uploadedSignature = ""; running = false; state.releaseAll()
                saved.notes.forEachIndexed { i, value -> state.notes[i] = value; saved.spellings?.getOrNull(i)?.let { state.setKeySpelling(i, it) } }
                saved.instruments?.forEachIndexed { i, value -> state.keyInstruments[i] = value }
                saved.velocities?.forEachIndexed { i, value -> state.velocities[i] = value }
                saved.modes?.forEachIndexed { i, value -> state.velocityModes[i] = value }
                saved.enabled?.forEachIndexed { i, value -> state.keyEnabled[i] = value }
                if (saved.scoreId != null) {
                    state.restorePresetSelection(saved.presetId)
                    repository.restoreScoreSettings(saved)
                    if (selected?.id == saved.scoreId) { transpose = saved.transpose ?: 0; score = score?.copy(keys = saved.scoreKeys ?: emptyList()) }
                }
                val expected = List(35) { id -> HallPadSession.KeyConfig(state.keyEnabled[id], state.notes[id], HallPadInstrumentIds[state.keyInstruments[id]] ?: 65535, state.velocityModes[id], state.velocities[id]) }
                state.persist()
                restoringBackup = true
                scope.launch {
                    var confirmed = false
                    repeat(150) { if (!confirmed) { confirmed = demo || (deviceReady && state.keyConfigurationConfirmed?.invoke(expected) == true); if (!confirmed) delay(100) } }
                    if (confirmed) { repository.clearBackup(); backup = null } else message = "设备尚未确认原键位，可重新尝试恢复"
                    restoringBackup = false
                }
            }
        }, onKey = { key ->
            practice.cancel(); uploadedSignature = ""; running = false; selected?.let { repository.keySignature(it.id, key) }; score = score?.copy(keys = listOf(key))
        }, onClose = { options = false },
            downloadEnabled = deviceReady && selected != null && !busy && !running && !following && !sendingScore,
            onDownload = if (environment.sdCard == null) null else {
                { options = false; sdDialog = true }
            }
        )
    }

    deleteTarget?.let { entry -> AlertDialog(onDismissRequest = { deleteTarget = null }, title = { Text("删除曲目？") }, text = { Text(entry.title) }, confirmButton = { TextButton(onClick = { repository.delete(entry.id); entries = repository.list(); deleteTarget = null }) { Text("删除") } }, dismissButton = { TextButton(onClick = { deleteTarget = null }) { Text("取消") } }) }
}

internal fun formatScoreTime(seconds: Double): String = "%02d:%02d".format(seconds.toInt().coerceAtLeast(0) / 60, seconds.toInt().coerceAtLeast(0) % 60)

/** 队列独立滚动，手动浏览优先；选中音符或重新开始播放后恢复跟随。 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun UpcomingNoteQueue(score: MidiScore, groups: List<Map.Entry<Long, List<ScoreNote>>>, currentIndex: Int, running: Boolean, modifier: Modifier = Modifier, onDelete: (Long) -> Unit, onSelect: (Int) -> Unit) {
    val palette = MaterialTheme.colorScheme
    val nextIndex = currentIndex.coerceAtMost(groups.lastIndex).coerceAtLeast(0)
    val listState = rememberLazyListState(initialFirstVisibleItemIndex = nextIndex)
    val dragged by listState.interactionSource.collectIsDraggedAsState()
    var browsing by remember { mutableStateOf(false) }
    var deleting by remember { mutableStateOf(false) }
    LaunchedEffect(dragged) { if (dragged) browsing = true }
    LaunchedEffect(running) { if (running) browsing = false }
    LaunchedEffect(currentIndex, browsing, dragged) { if (!browsing && !dragged && groups.isNotEmpty()) listState.animateScrollToItem(nextIndex) }
    Column(modifier.clipToBounds()) {
        TextButton(onClick = { browsing = false }, contentPadding = PaddingValues(horizontal = 4.dp, vertical = 0.dp), modifier = Modifier.fillMaxWidth().height(32.dp)) { Text(if (browsing) "恢复跟随" else "跟随中", style = MaterialTheme.typography.labelSmall, maxLines = 1) }
        BoxWithConstraints(Modifier.weight(1f).fillMaxWidth()) {
            val slotHeight = 44.dp
            LazyColumn(state = listState, modifier = Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(6.dp), contentPadding = PaddingValues(bottom = slotHeight * 4 + 6.dp)) {
                itemsIndexed(groups, key = { _, group -> group.key }) { index, group ->
                    val isCurrent = index == currentIndex
                    val isNext = index == currentIndex + 1
                    Surface(modifier = Modifier.animateItem(placementSpec = spring(dampingRatio = 0.78f, stiffness = 380f)).fillMaxWidth().heightIn(min = slotHeight).combinedClickable(interactionSource = remember { MutableInteractionSource() }, indication = null, onLongClick = { deleting = true }, onClick = { browsing = false; deleting = false; onSelect(index) }), color = when { isCurrent -> androidx.compose.ui.graphics.lerp(palette.primaryContainer, palette.primary, 0.16f); isNext -> androidx.compose.ui.graphics.lerp(palette.secondaryContainer, palette.secondary, 0.12f); else -> androidx.compose.ui.graphics.lerp(palette.surface, palette.primary, 0.12f) }, border = androidx.compose.foundation.BorderStroke(1.dp, palette.primary), shape = RoundedCornerShape(9.dp)) {
                        Row(Modifier.fillMaxWidth().padding(start = 5.dp, end = 1.dp, top = 2.dp, bottom = 2.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text("${index + 1}.", fontFamily = HallPadMono, fontSize = 9.sp, maxLines = 1, color = palette.onSurfaceVariant)
                            Text(group.value.map { score.noteName(it.midi, it.tick) }.chunked(2).joinToString("\n") { it.joinToString("+") }, modifier = Modifier.weight(1f), fontFamily = HallPadMono, fontWeight = FontWeight.SemiBold, fontSize = 13.sp, lineHeight = 17.sp, softWrap = true, color = when { isCurrent -> palette.onPrimaryContainer; isNext -> palette.onSecondaryContainer; index < currentIndex -> palette.onSurfaceVariant; else -> palette.onSurface })
                            if (deleting) Box(Modifier.size(24.dp), contentAlignment = Alignment.CenterEnd) { IconButton(onClick = { onDelete(group.key) }, modifier = Modifier.size(24.dp)) { Icon(painterResource(android.R.drawable.ic_menu_close_clear_cancel), contentDescription = "删除条目", tint = androidx.compose.ui.graphics.Color(0xFFFF0000), modifier = Modifier.size(20.dp)) } }
                        }
                    }
                }
            }
        }
    }
}

private fun practiceSignatureValue(id: String?, track: Int, transpose: Int, notes: List<Int>, enabled: List<Boolean>) = "$id:$track:$transpose:${notes.joinToString(",")}:${enabled.joinToString(",")}"
