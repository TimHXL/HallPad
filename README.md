# HallPad

HallPad 是一套基于 FPGA 和 Android 的霍尔磁轴电子乐器系统，包含 35 键键盘、双空气鼓槌、MIDI 演奏及配套控制应用。

## 主要功能

- 35 键霍尔磁轴键盘
- FPGA 实时按键采集与音频处理
- 双 MPU6050 空气鼓槌
- RGB 灯效控制
- BLE 设备通信
- MIDI 乐谱播放与练习
- SD 卡及 HPG 文件支持
- Android 设备设置与演奏界面

## 项目结构

```text
HallPad/
├─ android/    # HallBeat Android 应用源码
├─ fpga/       # FPGA 工程源码
└─ README.md
```

## FPGA 工程

开发环境：Gowin EDA  
目标器件：GW5AST-LV138PG484AC1/I0

使用 Gowin EDA 打开：

```text
fpga/KeyboardPercussion.gprj
```

然后执行综合、布局布线和下载。

## Android 工程

开发环境：Android Studio  
主要技术：Kotlin、Jetpack Compose、BLE

使用 Android Studio 打开：

```text
android/
```

等待 Gradle 同步完成后即可编译和运行。

命令行编译：

```bash
cd android
./gradlew assembleDebug
```

Windows：

```bat
cd android
gradlew.bat assembleDebug
```