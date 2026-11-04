package com.timhxl.hallbeat

/** 将页面依赖集中传入，减少 Compose 入口的参数与变更标记，规避出现 VerifyError 的旧入口。 */
internal class ScorePageEnvironment(val state: HallPadState, val deviceReady: Boolean, val keyConfigSupported: Boolean, val active: Boolean, val practice: PracticeController, val demo: Boolean, val practiceSupported: Boolean, val sensorMap: IntArray, val metronome: MetronomeUiState, val recording: FpgaRecording, val physicalMask: Long, val metronomeSupported: Boolean, val onPlayerOpen: (Boolean) -> Unit, val directMidi: DirectMidiController? = null, val sdCard: SdCardController? = null, val temporaryKeyMapping: Boolean = false)
