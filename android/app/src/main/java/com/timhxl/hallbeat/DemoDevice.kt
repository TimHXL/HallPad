package com.timhxl.hallbeat

import androidx.compose.runtime.*

/** 手机内的虚拟设备，不使用蓝牙连接，也不向实机发送指令。 */
internal class DemoDevice {
    val parameters = mutableStateMapOf<Int, Int>()
    val keyConfigurations = mutableStateMapOf<Int, HallPadSession.KeyConfig>()
    val heldKeys = mutableStateMapOf<Int, Int>()
    var muted by mutableStateOf(false)
        private set
    var pitch by mutableIntStateOf(0)
        private set
    var modulation by mutableIntStateOf(0)
        private set
    var revision by mutableIntStateOf(0)
        private set
    fun setParameter(id: Int, value: Int) { if (parameters[id] != value) { parameters[id] = value; revision++ } }
    fun configure(id: Int, value: HallPadSession.KeyConfig) { if (keyConfigurations[id] != value) { keyConfigurations[id] = value; revision++ } }
    fun key(id: Int, down: Boolean, velocity: Int) { if (!down) heldKeys.remove(id) else if (!muted) heldKeys[id] = velocity }
    fun release() { heldKeys.clear(); pitch = 0; modulation = 0 }
    fun panic(value: Boolean) { muted = value; if (value) release() }
    fun performance(bend: Int, mod: Int) { pitch = if (muted) 0 else bend; modulation = if (muted) 0 else mod }
}

@androidx.compose.runtime.Composable
internal fun DemoDeviceStatus(device: DemoDevice) {
    androidx.compose.material3.Text("虚拟设备 · ${device.heldKeys.size} 个按键按下 · " + if (device.muted) "已静音" else "运行中")
    androidx.compose.material3.Text("弯音 ${device.pitch} · 调制 ${device.modulation}", style = androidx.compose.material3.MaterialTheme.typography.bodySmall)
}
