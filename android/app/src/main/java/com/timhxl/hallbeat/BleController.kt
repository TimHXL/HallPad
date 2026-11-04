package com.timhxl.hallbeat

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.*
import android.bluetooth.le.*
import android.content.Context
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.*
import java.util.UUID

internal data class NearbyDevice(val address: String, val name: String, val rssi: Int)

/** HallPad 蓝牙通信链路；所有 GATT 操作在主线程串行执行。 */
@SuppressLint("MissingPermission")
internal class BleController(context: Context) {
    private val context = context.applicationContext
    private val handler = Handler(Looper.getMainLooper())
    private val adapter get() = context.getSystemService(BluetoothManager::class.java)?.adapter
    private var gatt: BluetoothGatt? = null
    private var rx: BluetoothGattCharacteristic? = null
    private val namePrefs = this.context.getSharedPreferences("bluetooth_names", Context.MODE_PRIVATE)
    private var lastSavedAddress = namePrefs.getString("last_connected_address", null)
    var deviceAddress by mutableStateOf("")
        private set
    var deviceName by mutableStateOf("HallPad")
        private set
    var renaming by mutableStateOf(false)
        private set
    private var renameTarget = ""
    private var renameCallback: ((String?) -> Unit)? = null
    private var modulePending: ByteArray? = null
    private var moduleStarted = false
    private val moduleReply = StringBuilder()
    private val renameTimeout = Runnable { finishRename("更名未获确认，请重新连接后检查设备名称") }
    // 改名引起的短暂断开只恢复原地址，手动断开或切换设备会取消恢复。
    private var renameRecoveryUntil = 0L
    private var renameRecoveryAttempts = 0
    private var renameReconnect: Runnable? = null
    private var recoveryScanner: BluetoothLeScanner? = null
    private var recoveryScanCallback: ScanCallback? = null
    private var recoveryScanTimeout: Runnable? = null
    private var recoveryRenameCallback: ((String?) -> Unit)? = null
    private var generation = 0
    private var scanGeneration = 0
    private var scannerCallback: ScanCallback? = null
    private var scanner: BluetoothLeScanner? = null
    private val pending = linkedMapOf<String, NearbyDevice>()
    private var startupAddress: String? = null
    private var startupAttemptPending = true
    private val queue: HallPadTxQueue = HallPadTxQueue(::currentKeySnapshot)
    private var writing = false
    private var activeFrame: ByteArray? = null
    private var activeBatch: List<ByteArray> = emptyList()
    private var progressAt = 0L
    private var frameOffset = 0
    private var submittedBytes = 0
    private var urgentRelease = false
    private var resyncRequested = false
    private var recoveries = 0
    // 临时自然音布局：必须逐键验证后由用户启用，不把它当作实板定论。
    val uiToSensor = IntArray(35) { (it / 7) * 7 + 6 - it % 7 }
    var keyboardMappingConfirmed by mutableStateOf(true)
    private var transportReady = false
    private var mtuChunk = 20
    val protocol: HallPadSession = HallPadSession(::sendFrame, ::protocolChanged, ::record, ::recoverProtocol, deliveryTracking = true, onTelemetry = ::telemetryChanged, discardPracticeFrames = ::discardQueuedPracticeFrames, discardMidiFrames = ::discardQueuedMidiFrames)
    // Explicit boundaries prevent queue -> protocol -> queue type inference recursion.
    private fun currentKeySnapshot(): ByteArray = protocol.snapshotBytes()
    private fun discardQueuedPracticeFrames(): Unit { queue.discardPractice() }
    private fun discardQueuedMidiFrames(): Unit { queue.discardMidi() }
    private fun protocolChanged() { ready = protocol.ready && !renaming; if (ready && deviceAddress.isNotEmpty() && deviceAddress != lastSavedAddress) { namePrefs.edit().putString("last_connected_address", deviceAddress).apply(); lastSavedAddress = deviceAddress }; if (transportReady && !renaming) status = if (protocol.ready) "已连接" else "连接中..."; scheduleProtocolRefresh()
        if (ready && recoveryRenameCallback != null) {
            val completed = recoveryRenameCallback; recoveryRenameCallback = null
            completed?.invoke("连接已恢复，名称尚未确认，请重新扫描检查")
        }
    }
    // 合并同一短时间内的读回响应，只减少界面刷新，不延迟协议处理。
    private var protocolRefreshPending = false
    private fun scheduleProtocolRefresh() {
        if (protocolRefreshPending) return
        protocolRefreshPending = true
        handler.postDelayed({ protocolRefreshPending = false; refresh++ }, 32L)
    }
    var keyTelemetryRefresh by mutableStateOf(0)
        private set
    var adcTelemetryRefresh by mutableStateOf(0)
        private set
    private var adcUpdatePending = false
    private fun telemetryChanged(adc: Boolean) {
        if (!adc) { keyTelemetryRefresh++; return }
        if (!adcUpdatePending) {
            adcUpdatePending = true
            handler.postDelayed({ adcUpdatePending = false; adcTelemetryRefresh++ }, 100L)
        }
    }
    var refresh by mutableStateOf(0)
        private set
    private val protocolTimer = object : Runnable { override fun run() { if (transportReady) { protocol.tick(); handler.postDelayed(this, 20) } } }
    fun releaseRemote() { urgentRelease = true; try { protocol.releaseRemote() } finally { urgentRelease = false } }
    fun setParameter(id: Int, value: Int) { protocol.setParameter(id, value) }
    fun key(sensor: Int, down: Boolean, velocity: Int = 100) { protocol.key(sensor, down, velocity) }
    fun panic(on: Boolean) { protocol.panic(on) }
    private var operationDeadline: Runnable? = null
    var devices: List<NearbyDevice> by mutableStateOf(emptyList())
        private set
    var status by mutableStateOf("未连接")
        private set
    var scanning by mutableStateOf(false)
        private set
    var connected by mutableStateOf(false)
        private set
    var ready by mutableStateOf(false)
        private set
    var feedback by mutableStateOf("")
        private set
    private var lastNotice = 0L
    fun notice(text: String) {
        feedback = text
        val time = android.os.SystemClock.elapsedRealtime()
        if (time - lastNotice > 1800) { lastNotice = time; android.widget.Toast.makeText(context, text, android.widget.Toast.LENGTH_SHORT).show() }
    }
    private fun record(text: String) {  android.util.Log.i("HallPadBLE", text); if (text.startsWith("操作失败")) notice(text) }
    private fun isCurrent(client: BluetoothGatt, token: Int): Boolean = token == generation && gatt === client
    fun hasPermissions(): Boolean = listOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT).all { context.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }
    private val publish = object : Runnable {
        override fun run() { if (scanning) { devices = pending.values.sortedByDescending { it.rssi }; handler.postDelayed(this, 500) } }
    }
    private val scanTimeout = Runnable { stopScan(); status = if (devices.isEmpty()) "未找到设备，请确认设备已开启并处于可连接状态" else "请选择设备" }
    fun startScan() {
        cancelRenameRecovery()
        stopScan()
        if (!hasPermissions()) { status = "需要附近设备权限"; return }
        if (adapter?.isEnabled != true) { status = "请开启手机蓝牙"; return }
        if (connected) { status = "请先断开当前设备"; return }
        val currentScanner = adapter?.bluetoothLeScanner ?: run { status = "BLE 扫描不可用"; return }
        val token = scanGeneration
        val savedAddress = if (startupAttemptPending) namePrefs.getString("last_connected_address", null) else null
        startupAttemptPending = false
        startupAddress = savedAddress
        pending.clear(); devices = emptyList(); scanning = true
        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                val name = result.scanRecord?.deviceName ?: "未命名"
                val candidate = namePrefs.contains(result.device.address) || name.contains("HallPad", true) || name.contains("RF-CRAZY", true) || name.contains("RC3526", true) || result.scanRecord?.serviceUuids?.any { it.uuid == SERVICE } == true
                handler.post {
                    if (token == scanGeneration && scanning && candidate) {
                        val device = NearbyDevice(result.device.address, name, result.rssi)
                        pending[result.device.address] = device
                        if (startupAddress == device.address) { startupAddress = null; connect(device) }
                    }
                }
            }
            override fun onScanFailed(errorCode: Int) { handler.post { if (token == scanGeneration) { stopScan(); status = "扫描失败 code=$errorCode"; record(status) } } }
        }
        scanner = currentScanner; scannerCallback = callback
        try {
            // 不使用精确广播名过滤，兼容出厂名称、改名和仅广播 UUID 的模块。
            currentScanner.startScan(null, ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).setReportDelay(0).build(), callback)
            status = if (startupAddress != null) "连接中..." else "正在搜索设备…"; handler.post(publish); handler.postDelayed(scanTimeout, 15000)
        } catch (error: Exception) { stopScan(); status = "扫描失败：${error.message}" }
    }
    fun stopScan() {
        startupAddress = null
        scanGeneration++; handler.removeCallbacks(publish); handler.removeCallbacks(scanTimeout)
        try { scannerCallback?.let { scanner?.stopScan(it) } } catch (_: Exception) { }
        if (scanning) devices = pending.values.sortedByDescending { it.rssi }
        scanning = false; scannerCallback = null; scanner = null
    }
    private fun armDeadline(client: BluetoothGatt, token: Int, label: String) {
        cancelDeadline()
        val task = Runnable { if (isCurrent(client, token)) fail("$label 超时") }
        operationDeadline = task; handler.postDelayed(task, 10000)
    }
    private fun cancelDeadline() { operationDeadline?.let { handler.removeCallbacks(it) }; operationDeadline = null }
    private fun recoverProtocol(reason: String) {
        if (!transportReady || !connected || recoveries >= 2) { fail(reason); return }
        recoveries++; queue.clear(); resyncRequested = true; protocol.reset()
        status = "连接中..."; record(status + " " + reason)
        pump()
    }
    private fun fail(reason: String) {
        val recover = deviceAddress.isNotEmpty() && android.os.SystemClock.elapsedRealtime() < renameRecoveryUntil && renameRecoveryAttempts < 3
        if (recover) {
            record("RENAME_RECOVERY attempt=${renameRecoveryAttempts + 1} reason=$reason")
            if (renaming) { recoveryRenameCallback = renameCallback; renameCallback = null }
            clearConnection(preserveRenameRecovery = true)
            status = "连接中..."
            val token = generation
            renameRecoveryAttempts++
            val task = Runnable {
                renameReconnect = null
                if (token == generation && android.os.SystemClock.elapsedRealtime() < renameRecoveryUntil) scanRenameDevice(token)
                else if (token == generation) { cancelRenameRecovery(); status = "未连接" }
            }
            renameReconnect = task
            handler.postDelayed(task, 1000L * renameRecoveryAttempts)
            return
        }
        disconnect(); status = reason; record(reason)
    }
    private fun cancelRenameRecovery() {
        renameReconnect?.let { handler.removeCallbacks(it) }; renameReconnect = null
        stopRecoveryScan()
        renameRecoveryUntil = 0L; renameRecoveryAttempts = 0
        val callback = recoveryRenameCallback; recoveryRenameCallback = null
        callback?.invoke("名称确认中断，请重新连接后检查")
    }
    private fun stopRecoveryScan() {
        recoveryScanTimeout?.let { handler.removeCallbacks(it) }; recoveryScanTimeout = null
        try { recoveryScanCallback?.let { recoveryScanner?.stopScan(it) } } catch (_: Exception) { }
        recoveryScanCallback = null; recoveryScanner = null
    }
    /** 等到同地址重新广播再建新 GATT，避免模块改名重启期间盲目连接。 */
    private fun scanRenameDevice(token: Int) {
        if (token != generation) return
        if (!hasPermissions() || adapter?.isEnabled != true) { fail("蓝牙不可用，无法恢复连接"); return }
        stopRecoveryScan()
        val current = adapter?.bluetoothLeScanner ?: run { fail("BLE 扫描不可用"); return }
        val expectedAddress = deviceAddress
        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                if (result.device.address != expectedAddress) return
                val name = result.scanRecord?.deviceName
                handler.post {
                    if (token != generation || recoveryScanCallback !== this) return@post
                    stopRecoveryScan()
                    val actualName = name ?: deviceName
                    if (name != null && name == renameTarget) {
                        deviceName = name
                        namePrefs.edit().putString(expectedAddress, name).apply()
                        val completed = recoveryRenameCallback; recoveryRenameCallback = null
                        completed?.invoke(null)
                    }
                    record("RENAME_ADVERTISEMENT address=$expectedAddress name=$actualName")
                    connectInternal(NearbyDevice(expectedAddress, actualName, result.rssi), recoveringRename = true)
                }
            }
            override fun onScanFailed(errorCode: Int) { handler.post { if (token == generation && recoveryScanCallback === this) { stopRecoveryScan(); fail("恢复扫描失败 code=$errorCode") } } }
        }
        recoveryScanner = current; recoveryScanCallback = callback
        val timeout = Runnable { if (token == generation && recoveryScanCallback === callback) { stopRecoveryScan(); fail("等待设备重新广播超时") } }
        recoveryScanTimeout = timeout
        try {
            current.startScan(listOf(ScanFilter.Builder().setDeviceAddress(expectedAddress).build()), ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build(), callback)
            handler.postDelayed(timeout, 8000)
        } catch (error: Exception) { stopRecoveryScan(); fail("恢复扫描失败：${error.message}") }
    }
    fun connect(device: NearbyDevice) { connectInternal(device, recoveringRename = false) }
    private fun connectInternal(device: NearbyDevice, recoveringRename: Boolean) {
        if (!hasPermissions()) { status = "需要附近设备权限"; return }
        stopScan(); clearConnection(preserveRenameRecovery = recoveringRename); recoveries = 0; val token = generation
        deviceAddress = device.address; deviceName = device.name; namePrefs.edit().putString(deviceAddress, deviceName).apply()
        status = "连接中..."; record("CONNECT ${device.address} ${device.name}")
        try {
            val remote = adapter?.getRemoteDevice(device.address) ?: run { status = "蓝牙不可用"; return }
            val callback = object : BluetoothGattCallback() {
                override fun onConnectionStateChange(client: BluetoothGatt, code: Int, newState: Int) {  handler.post {
                    if (!isCurrent(client, token)) { client.close(); return@post }
                    if (code != BluetoothGatt.GATT_SUCCESS || newState == BluetoothProfile.STATE_DISCONNECTED) { fail("断开连接 status=$code"); return@post }
                    if (newState == BluetoothProfile.STATE_CONNECTED) {
                        connected = true; client.requestConnectionPriority(BluetoothGatt.CONNECTION_PRIORITY_HIGH); status = "连接中..."; armDeadline(client, token, "服务发现")
                        if (!client.discoverServices()) fail("无法启动服务发现")
                    }
                } }
                override fun onServicesDiscovered(client: BluetoothGatt, code: Int) { handler.post {
                    if (!isCurrent(client, token)) return@post
                    cancelDeadline()
                    if (code != BluetoothGatt.GATT_SUCCESS) { fail("服务发现失败 $code"); return@post }
                    client.services.forEach { service -> record("SERVICE ${service.uuid}"); service.characteristics.forEach { record(" CHAR ${it.uuid} props=${it.properties}") } }
                    val service = client.getService(SERVICE)
                    val input = service?.getCharacteristic(RX)
                    val output = service?.getCharacteristic(TX)
                    if (input == null || output == null) { fail("设备缺少所需的蓝牙通信服务"); return@post }
                    if (input.properties and (BluetoothGattCharacteristic.PROPERTY_WRITE or BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE) == 0 || output.properties and BluetoothGattCharacteristic.PROPERTY_NOTIFY == 0) { fail("设备蓝牙通信接口不兼容"); return@post }
                    rx = input
                    val cccd = output.getDescriptor(CCCD)
                    if (cccd == null || !client.setCharacteristicNotification(output, true)) { fail("无法启用通知"); return@post }
                    armDeadline(client, token, "通知订阅")
                    if (client.writeDescriptor(cccd, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE) != BluetoothStatusCodes.SUCCESS) fail("CCCD 提交失败")
                } }
                override fun onDescriptorWrite(client: BluetoothGatt, descriptor: BluetoothGattDescriptor, code: Int) { handler.post {
                    if (!isCurrent(client, token)) return@post
                    cancelDeadline()
                    if (code != BluetoothGatt.GATT_SUCCESS) { fail("通知订阅失败 $code"); return@post }
                    transportReady = true; status = "连接中..."; armDeadline(client, token, "MTU 协商")
                    if (!client.requestMtu(247)) { cancelDeadline(); startProtocol() }
                } }
                override fun onMtuChanged(client: BluetoothGatt, mtu: Int, code: Int) { handler.post {
                    if (!isCurrent(client, token)) return@post
                    cancelDeadline(); mtuChunk = if (code == BluetoothGatt.GATT_SUCCESS) (mtu - 3).coerceIn(20, 244) else 20
                    startProtocol()
                } }
                override fun onCharacteristicChanged(client: BluetoothGatt, characteristic: BluetoothGattCharacteristic, value: ByteArray) {
                    val copy = value.copyOf()

                    handler.post { if (isCurrent(client, token)) { if (renaming && moduleStarted) receiveModule(copy) else protocol.receive(copy) } }
                }
                override fun onCharacteristicWrite(client: BluetoothGatt, characteristic: BluetoothGattCharacteristic, code: Int) {  handler.post {
                    if (!isCurrent(client, token) || !writing) return@post
                    cancelDeadline(); writing = false
                    if (code != BluetoothGatt.GATT_SUCCESS) {
                        if (code == BluetoothGatt.GATT_CONNECTION_CONGESTED && android.os.SystemClock.elapsedRealtime() - progressAt < 3000) {
                            handler.postDelayed({ if (isCurrent(client, token)) pump() }, 20)
                        } else fail("写入失败 $code")
                        return@post
                    }
                    frameOffset += submittedBytes; progressAt = android.os.SystemClock.elapsedRealtime()
                    if (frameOffset >= (activeFrame?.size ?: 0)) {
                        val finished = activeBatch; activeFrame = null; activeBatch = emptyList(); frameOffset = 0
                        finished.forEach { protocol.transmitted(it) }
                        if (renaming && moduleStarted && finished.isEmpty()) scheduleRenameScan()

                    }
                    // 根据UART吞吐限速；仍等待每次GATT回调，绝不并行提交分片。
                    val pace = if (queue.size == 0 && activeFrame == null) 0L else maxOf(1L, (submittedBytes * 1000L + 3999) / 4000)
                    handler.postDelayed({ if (isCurrent(client, token)) pump() }, pace)
                } }
            }
            gatt = remote.connectGatt(context, false, callback, BluetoothDevice.TRANSPORT_LE)
            gatt?.let { armDeadline(it, token, "连接") }
        } catch (error: Exception) { fail("连接失败：${error.message}") }
    }
    private var protocolStart: Runnable? = null
    private fun startProtocol() {
        protocolStart?.let { handler.removeCallbacks(it) }
        val token = generation
        val task = Runnable {
            protocolStart = null
            if (transportReady && token == generation && !renaming) {
                record("TRANSPORT mtuChunk=$mtuChunk")
                protocol.start(); handler.removeCallbacks(protocolTimer); handler.post(protocolTimer)
            }
        }
        protocolStart = task; handler.postDelayed(task, 800)
    }
    private fun sendFrame(bytes: ByteArray): Boolean {
        if (!transportReady || renaming || bytes.size > 244) return false
        val previous = queue.coalesced
        if (!queue.offer(bytes, urgentRelease)) return false
        if (queue.coalesced != previous) record("发送繁忙：已合并未发送的划键事件，保持最新完整按键状态")
        pump(); return true
    }
    private fun pump() {
        if (writing || !transportReady) return
        if (activeFrame == null) {
            if (resyncRequested) { resyncRequested = false; startProtocol(); return }
            activeBatch = queue.bundle(mtuChunk)
            if (activeBatch.isEmpty()) {
                val command = modulePending ?: return
                modulePending = null; moduleStarted = true; activeFrame = command
            } else activeFrame = activeBatch.fold(byteArrayOf()) { result, frame -> result + frame }
            frameOffset = 0; progressAt = android.os.SystemClock.elapsedRealtime()
        }
        val frame = activeFrame ?: return
        val client = gatt ?: return; val characteristic = rx ?: return
        val chunk = frame.copyOfRange(frameOffset, minOf(frame.size, frameOffset + mtuChunk))
        val noResponse = characteristic.properties and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE != 0
        val mode = if (noResponse) BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE else BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
        submittedBytes = chunk.size; writing = true
        val result = client.writeCharacteristic(characteristic, chunk, mode)
        if (result == BluetoothStatusCodes.SUCCESS) armDeadline(client, generation, "GATT 写入")
        else {
            writing = false
            if (result == BluetoothStatusCodes.ERROR_GATT_WRITE_REQUEST_BUSY && android.os.SystemClock.elapsedRealtime() - progressAt < 3000) {
                val token = generation
                handler.postDelayed({ if (isCurrent(client, token)) pump() }, 12)
            } else fail("GATT 写入提交失败 code=$result")
        }
    }
    /** 暂停业务心跳，排空串行写队列，再通过模块的透传特征发送 AT。 */
    fun renameDevice(name: String, completed: (String?) -> Unit) {
        if (!ModuleDeviceName.isValid(name)) { completed("名称格式不正确"); return }
        if (!ready || renaming) { completed("请等待设备就绪"); return }
        releaseRemote()
        cancelRenameRecovery()
        renameRecoveryUntil = android.os.SystemClock.elapsedRealtime() + 90000L
        renaming = true; ready = false; status = "连接中..."; renameTarget = name; renameCallback = completed
        moduleStarted = false; moduleReply.clear()
        handler.removeCallbacks(protocolTimer)
        modulePending = ModuleDeviceName.command(name)
        handler.postDelayed(renameTimeout, 8000)
        pump()
    }
    /** 完整改名命令的最后一个分片写完后，等待100ms，再按连接时记录的MAC恢复。 */
    private fun scheduleRenameScan() {
        val token = generation
        renameReconnect?.let { handler.removeCallbacks(it) }
        val task = Runnable {
            renameReconnect = null
            if (token != generation || !renaming) return@Runnable
            recoveryRenameCallback = renameCallback; renameCallback = null
            clearConnection(preserveRenameRecovery = true)
            status = "连接中..."
            renameRecoveryAttempts = 1
            record("RENAME_SCAN_AFTER_WRITE delay=100ms address=$deviceAddress")
            scanRenameDevice(generation)
        }
        renameReconnect = task
        handler.postDelayed(task, 100)
    }
    private fun receiveModule(bytes: ByteArray) {
        // 二进制设备事件与 AT 文本分开处理，且限制未终止行的内存占用。
        bytes.forEach { byte ->
            val value = byte.toInt() and 255
            if (value == 10 || value == 13) {
                val line = moduleReply.toString().trim(); moduleReply.clear()
                if (line.isNotEmpty()) record("RENAME_REPLY $line")
                if (line == "ERROR" || line == "FAIL" || line == "BUSY") finishRename("设备未接受更名，请稍后重试")

            } else if (value in 32..126 && moduleReply.length < 128) moduleReply.append(value.toChar()) else moduleReply.clear()
        }
    }
    private fun finishRename(error: String?) {
        if (!renaming) return
        handler.removeCallbacks(renameTimeout)
        if (error == null) { renameRecoveryUntil = android.os.SystemClock.elapsedRealtime() + 90000L; deviceName = renameTarget; namePrefs.edit().putString(deviceAddress, deviceName).apply() }
        val callback = renameCallback; renameCallback = null; renaming = false; modulePending = null; moduleStarted = false; moduleReply.clear()
        // 等待正在发送的 GATT 分片完成后重新握手，不打断半帧写入。
        if (transportReady) { queue.clear(); protocol.reset(); resyncRequested = true; pump() }
        callback?.invoke(error)
    }
    fun disconnect() { clearConnection(preserveRenameRecovery = false) }
    private fun clearConnection(preserveRenameRecovery: Boolean) {
        stopRecoveryScan()
        if (!preserveRenameRecovery) cancelRenameRecovery()
        handler.removeCallbacks(renameTimeout)
        protocolStart?.let { handler.removeCallbacks(it) }; protocolStart = null
        val callback = renameCallback; renameCallback = null; renaming = false; modulePending = null; moduleStarted = false; moduleReply.clear()
        callback?.invoke(if (preserveRenameRecovery) "设备正在重新连接，名称请在重连后确认" else "设备连接已断开")
        generation++; cancelDeadline(); handler.removeCallbacks(protocolTimer); transportReady = false; resyncRequested = false; keyboardMappingConfirmed = true; mtuChunk = 20; protocol.reset(); queue.clear(); activeFrame = null; activeBatch = emptyList(); frameOffset = 0; submittedBytes = 0; writing = false; rx = null; ready = false; connected = false
        val old = gatt; gatt = null
        try { old?.disconnect(); old?.close() } catch (_: Exception) { }
        status = "未连接"
    }
    fun close() { stopScan(); disconnect(); handler.removeCallbacksAndMessages(null) }
    companion object {
        private val SERVICE = UUID.fromString("6e400001-b5a3-f393-e0a9-e50e24dcca9e")
        private val RX = UUID.fromString("6e400002-b5a3-f393-e0a9-e50e24dcca9e")
        private val TX = UUID.fromString("6e400003-b5a3-f393-e0a9-e50e24dcca9e")
        private val CCCD = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
    }
}
