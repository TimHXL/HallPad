> 本工程已实现第23节0x46/0x47，仿真结果见README_FIRST.md；本版尚未进行Gowin布局布线/实板验收。下文保留输入协议原文，原有“FPGA待实现”等交付说明是文档编写时状态，不作为本工程功能完成证明。其他章节是否支持以本工程基线和CAPS为准。

> 2026-11-01：新增第23节曲谱同步逐拍触发。FPGA待实现；不改0x45方向，新增0x46/47、能力bit27。

> 三模式修订：第22节定义鼓棒水波/常亮/关闭，优先于旧灯光说明。本次仅安卓及协议更新，FPGA尚需配套实现。

> 2026-10-31 RGB 修订：第21节新增鼓棒自定义配色规范与安卓接入。第1–20节保留供兼容参考；冲突以第21节为准。本次未修改 FPGA，0x7D–0x7F 与能力 bit24 是待 FPGA 配套实现的接口，不能当作现有 DrumControl 固件已经支持。

> V1.2 修订：2026-10-30。第18节为新增规范；保留第1–17节完整定义。与第18节冲突的旧自动播放说明以第18节为准。本文不是固件或App实现完成证明。

# HallPad 完整蓝牙通信协议 V1.2（含 MIDI 直接演奏扩展）

更新日期：2026-10-31。整数均为小端。本文件以旧 Integration_Guide(3) 的帧、会话、参数和遥测定义为基础，定义曲谱跟随、鼓棒与音源混合接口，不改变线上帧 VERSION=1；接口定义正式，设备是否实现以能力位和验收为准。

**交付边界：配套压缩包实现安卓端及纯手机演示，不包含 FPGA 工程改动。0x60–0x69 与能力 bit18 是正式接口规范，FPGA 需按本文实现后才能用于真实练习。不可把新 UI 当作旧固件已经支持。bit17 原为诊断遥测，保持不变。**

## 1. 工作流程与实现范围

手机导入/内置 MIDI → 选旋律音轨及移调 → 明示应用所需键位 → 将当前曲谱编译为物理目标键序列 → 分块上传并校验 → 开始跟随 → FPGA 点灯、等待真实按键、逐组推进 → FPGA 回传最终评分 → App 展示结果。

第一版只实现整首曲目的 WAIT 模式：弹对才继续，不因等待时间自动跳过音符。手机本地预览和 A/B 循环保留，但跟随期间由设备推进，禁止本地拖动/跳音，开始跟随时清除本地 A/B。跳转、设备循环、严格节奏模式不是本版已实现功能，不能自行套用预留字段。

按键声音仍由已有 FPGA 引擎产生。曲谱数据用于指导和评估，不是自动播放音频，也不是发送原 MIDI 文件。演示练习不写蓝牙，模拟按对每组，最终 100 分并显示“演示练习”。

## 2. RC3526A BLE 传输

- 服务：`6E400001-B5A3-F393-E0A9-E50E24DCCA9E`。
- App 写入 RX：`6E400002-B5A3-F393-E0A9-E50E24DCCA9E`；按特征实际属性选择 Write/Write Without Response，所有 GATT 操作串行等待回调。
- FPGA/UART 到 App Notify TX：`6E400003-B5A3-F393-E0A9-E50E24DCCA9E`；先开启 CCCD。
- UART 默认 115200、8N1，具体硬件设置需两端一致；应用二进制协议与模块 AT 指令不是同一种业务。
- ATT 有效片长 min(MTU−3,244)；协商失败用 20 字节。应用帧最大 244 字节。模块不是无限缓存，现有 App 发送按约 4 KB/s 排序限速。
- 设备更名沿用独立 AT+NAME 链路，暂停二进制写入后串行执行，不得把 AT 文本送到 HallPad 二进制解码器冒充业务帧。名称保守子集为 1–16 位 ASCII 字母、数字、_、-；原有 App 不把未确认的更名当作成功。

## 3. 身份与音高

key_id/sensor_id 固定为物理 0–34，mask 的 bit0 对应 sensor0，高于 bit34 必须为 0。UI 是五行七列，不等于物理线路顺序。App 使用 uiToSensor 显式转换；真实设备沿用当前镜像映射，演示使用恒等映射。MIDI 音高为 0–127，键编号不能当音高。

曲谱映射选择每个音高的第一个已启用 UI 键，再映射到物理 mask。重复音高的其他键不是当前目标。按同一组 tick 聚合和弦、重复音高去重。缺少任何目标音高、包含 channel9 打击乐、空旋律或过密事件时，安卓拒绝上传并给出原因。不会把缺失音高偷偷降级成别的音。

## 4. 兼容性与优先级

只有旧 CAPABILITIES 中 bit18=1 才允许查询/上传/控制练习；再用 SCORE_CAPS 确认扩展版本 1 和容量。bit16 继续表示每键配置，bit17 继续表示诊断。旧固件 bit18=0 时保留连接、键盘与本地曲谱预览，不向其发送新命令。

发送优先级为 PANIC/释放 > 心跳/实时键 > 普通控制 > 曲谱块 > ADC/频谱。安卓同一时刻只保留一个可靠请求在途，每个曲谱块 ACK 后才提交下一块；不能预排整首曲谱阻塞实时命令。FPGA 必须保留与音频扫描独立的 UART 缓冲和曲谱处理状态机。

以下第 5–10 节为继承并保留的基础协议。其“第一版/第二阶段”表示旧协议的兼容等级，不代表当前 FPGA 已实现全部能力；设备只能通告真实支持的位。本次跟随扩展的规范在第 11 节之后。

## 5. 帧格式与解析

### 5.1 通用格式

全部多字节整数为小端，带符号数为补码，字符串 UTF-8，不传浮点/JSON。

| 偏移 | 字段 | 长度 | 定义 |
|---:|---|---:|---|
| 0 | SOF | 2 | A5 5A |
| 2 | VERSION | 1 | 01 |
| 3 | TYPE | 1 | 命令 ID |
| 4 | FLAGS | 1 | 见下表 |
| 5 | SEQ | 2 | 请求或上报序号 |
| 7 | SESSION_ID | 4 | 0 仅用于 HELLO |
| 11 | LENGTH | 2 | PAYLOAD 长度，0～229 |
| 13 | PAYLOAD | N | 命令数据 |
| 13+N | CRC16 | 2 | 低字节先发 |

最大逻辑帧 244 字节。固定开销 15 字节。KEY_EVENT 的 3 字节载荷形成 18 字节帧。

FLAGS：bit0 ACK_REQUIRED；bit1 IS_RESPONSE；bit2 IS_ERROR；bit3～7 必须为 0。请求不得设置 IS_RESPONSE/IS_ERROR。响应成功清 IS_ERROR；失败置 IS_ERROR。成功的实时事件不回 ACK。

CRC-16/CCITT-FALSE：poly=0x1021，init=0xFFFF，refin/refout=false，xorout=0。覆盖 VERSION 到 PAYLOAD 末尾，不含 SOF 和 CRC。ASCII `123456789` 应得 0x29B1。

### 5.2 帧接收状态机

SEARCH_A5 → SEARCH_5A → READ_FIXED_HEADER → CHECK_LENGTH → READ_PAYLOAD → READ_CRC → VALIDATE → DISPATCH。

- 收到 A5 A5 5A 应能从第二个 A5 找到帧头。
- 先检查长度上界，不能用不可信 LENGTH 越界写 RAM。
- 用完整帧缓冲保存到 CRC 成功；不得边收参数边写实际配置。
- 长度或 CRC 失败，从候选起点后一字节重新扫描已缓冲内容，避免错过后续真帧。
- 连续 500 ms 没收到候选帧的后续字节则丢弃半帧；这是字节间超时，不是整帧总时长上限。
- CRC 失败不发 ACK（SEQ 也可能已损坏），只计数。
- 成功完成一帧后，清 CRC 和计数，继续解析同批剩余字节。
- FIFO 满时不能静默覆盖数据；计数并丢弃不完整候选，远程键由独立失联计时保护。

GATT 写、Notify、UART DMA/字节回调的边界均不是应用帧边界。一帧可以被拆开，多帧也可以粘在一起。SOF 出现在载荷内部合法。

### 5.3 BLE 分片与发送调度

单次有效写长度为 min(actual_mtu-3,244)。默认 MTU 23 时按 20 字节分片。请求更大 MTU 失败仍必须可用。

一帧分片不可与另一帧交错。只在完整帧边界切换优先级。手机不要一次排入几百个低优先级块；模块内部队列不可被 PANIC 抢占。

## 6. 连接、会话与可靠性

### 6.1 会话建立

HELLO 为唯一 SESSION_ID=0 的命令。请求携带随机 client_nonce；设备返回相同 nonce 和新非零 SESSION_ID。

没有真随机源时，SESSION_ID 可由设备唯一标识、会话计数和启动计数产生，但这只用于隔离旧数据，不是认证或加密。BOOT_ID 也必须反映真实重启；不能每次启动都固定为 1 并假装可识别重启。

HELLO 重试：同 nonce/同 SEQ 在短时间重复时返回同一响应，不新建会话；新 nonce 才替换旧会话并释放旧远程状态。设备初版只允许一个手机控制会话。

应用会话超时设 3000 ms；远程演奏租约超时设 1000 ms。两者分开：前者失效整个会话，后者只清远程键/弯音/踏板。

### 6.2 序号与重复请求

SEQ 每方向从任意值开始，u16 回绕。普通新帧递增；重试保留原 SEQ 和全部内容。专用响应和 ACK 复制请求 SEQ；异步帧使用设备独立序号，IS_RESPONSE=0。

初版 Android 同时仅保留一个普通可靠请求在途。缓存最近 16 个可靠请求结果，保留 5 s；去重键为 SESSION_ID+TYPE+SEQ，并校验请求完整内容一致（可缓存原请求或足够强的摘要；不能只依赖 CRC16 抵抗内容冲突）。重复请求只重发结果，不再应用、不增加 CONFIG_REVISION。

为避免高速事件令全局 u16 很快回绕撞上缓存，可靠控制与实时事件在命令类别内独立去重；实时事件不进入可靠缓存。相同 TYPE 下回绕前应确保旧缓存已过期，或提前重建会话。

普通请求 500 ms 超时，最多 2 次重试；忙状态用新 SEQ 重新提交，建议退避 100 ms。实时按下/压力/弯音不做过时补发。

### 6.3 ACK 的完成含义

ACK OK 表示参数已提交到唯一运行仓库；平滑增益等 DSP 可随后渐变到目标值。音色切换有现有淡出/清上下文过程，ACK 是“目标已接受”，STATUS 的 target/active 字段说明是否仍切换中。

初版未实现的保存/上传一律返回 UNSUPPORTED。将来耗时操作需返回 operation_id，并以完成事件或查询状态报告结果；禁止用普通 ACK OK 表示尚未完成的 Flash 写入。

### 6.4 失联处理

- HEARTBEAT 每 250 ms；若未请求响应，设备只更新 session_liveness，不逐帧回包。
- 手机每 100 ms 发 REMOTE_KEY_STATE（即使空 mask），该快照独立更新 remote_lease。
- 普通查询/心跳不能续租远程键，否则“UI 已清空但心跳仍在”会卡音。
- 1000 ms 未收到合法实时控制或快照，释放远程 gate，清远程弯音/踏板，保留物理状态。
- 会话 3000 ms 无合法同会话流量则失效；后续必须 HELLO。
- 模块连接脚/可信帧外断线通知可提前触发清远程状态，但不能替代看门狗。
- 重新连接先清 App 旧 TX 队列，再 HELLO、拉状态、订阅；不重放旧按下。

## 7. 命令字典

记号 u8/u16/u32/u64 为无符号，i16/i32 为有符号；数组均按给出的固定顺序紧密排列，无结构体对齐填充。

### 7.1 命令总表

| TYPE | 名称 | 方向 | 第一版处理 |
|---|---|---|---|
| 01 | HELLO | App→FPGA，原 TYPE 响应 | 必须 |
| 02 | HEARTBEAT | App→FPGA，按需原 TYPE 响应 | 必须 |
| 03 | ACK | FPGA→App | 必须 |
| 04 | GET_STATUS | App→FPGA | 必须 |
| 05 | STATUS | FPGA→App | 必须 |
| 06 | GET_CAPABILITIES | App→FPGA | 必须 |
| 07 | CAPABILITIES | FPGA→App | 必须 |
| 08 | TIME_SYNC | App→FPGA，原 TYPE 响应 | 第二阶段 |
| 10 | KEY_EVENT | App→FPGA | 按下/松开必须 |
| 11 | ALL_NOTES_OFF | App→FPGA | 必须 |
| 12 | PERFORMANCE_CONTROL | App→FPGA | 第二阶段，未实现返回不支持 |
| 13 | REMOTE_KEY_STATE | App→FPGA | 必须 |
| 14 | PANIC | App→FPGA | 必须 |
| 20 | SET_PARAMETERS | App→FPGA | 必须，按支持项 |
| 21 | GET_PARAMETERS | App→FPGA | 必须 |
| 22 | PARAMETER_VALUES | FPGA→App | 必须 |
| 23 | SET_KEY_CONFIG | App→FPGA | 第二阶段 |
| 24 | GET_KEY_CONFIG | App→FPGA | 第二阶段 |
| 25 | KEY_CONFIG | FPGA→App | 第二阶段 |
| 26 | GET_CATALOG | App→FPGA | 第二阶段 |
| 27 | CATALOG | FPGA→App | 第二阶段 |
| 28 | CONFIG_ACTION | App→FPGA | 预留，不虚报持久保存 |
| 30 | SET_LIGHT | App→FPGA | 预留；初版灯光走 SET_PARAMETERS |
| 40 | SET_TELEMETRY | App→FPGA，原 TYPE 响应 | 第二阶段 |
| 41 | ADC_DATA | FPGA→App | 第二阶段 |
| 42 | SPECTRUM_DATA | FPGA→App | 第二阶段 |
| 43 | KEY_ACTIVITY | FPGA→App | 第二阶段 |
| 44 | DIAGNOSTICS | FPGA→App | 第二阶段 |
| 45 | BEAT_EVENT | FPGA→App | 第二阶段 |
| 50～53 | 文件开始/数据/完成/取消 | 双向 | 扩展未冻结，默认不支持 |

预留命令有编号但无冻结载荷，不得据此前聊天的示意字段自行交付不兼容实现。

### 7.2 通用错误 ACK（TYPE=03）

载荷固定 8 字节：original_type:u8、result:u8、config_revision:u32、detail:u16。

| result | 名称 | detail |
|---|---|---|
| 00 | OK | 0 |
| 01 | UNKNOWN_COMMAND | TYPE |
| 02 | BAD_LENGTH | 期望长度；变长结构错误填 0 |
| 03 | OUT_OF_RANGE | 错误 param_id 或 key_id |
| 04 | BUSY | 建议等待毫秒 |
| 05 | INVALID_STATE | 状态码 |
| 06 | STORAGE_ERROR | 存储错误码 |
| 07 | UNSUPPORTED | 能力编号或 param_id |
| 08 | REVISION_CONFLICT | 0；真实 revision 在字段中 |
| 09 | BAD_SESSION | 0 |
| 0A | INTEGRITY_ERROR | 数据对象错误码 |
| 0B | SEQUENCE_CONFLICT | 0 |

CRC/长度上界等帧层失败静默丢弃；CRC 正确的非法命令可以返回错误 ACK，即使未置 ACK_REQUIRED，仍需限制错误回包速率（建议最多 10/s）。对错误 ACK 不再回 ACK。未知会话错误头复制收到的 SESSION_ID，手机不应把它当作新会话。

### 7.3 HELLO（01）

请求 8 字节：min_version:u8、max_version:u8、client_nonce:u32、client_rx_max_payload:u16。

成功响应 24 字节：result:u8=0、selected_version:u8、client_nonce:u32、device_id:u64、boot_id:u32、device_rx_max_payload:u16、heartbeat_ms:u16、remote_timeout_ms:u16。响应头使用新 session_id。

设备 RX 上限固定不大于 229；TX 上限取 min(229,client_rx_max_payload)，初版要求客户端至少能接收 64 字节，否则错误 ACK。版本不支持返回错误 ACK，不能分配半可用会话。

### 7.4 HEARTBEAT（02）

请求 4 字节：client_uptime_ms:u32。若 ACK_REQUIRED=1，响应同 TYPE，载荷 client_uptime_ms:u32、device_uptime_ms:u32；否则无响应。不是远程按键续租快照。

### 7.5 GET_STATUS / STATUS（04/05）

GET_STATUS 无载荷。STATUS 固定 40 字节：

| 载荷偏移 | 字段 | 类型 |
|---:|---|---|
| 0 | uptime_ms | u32 |
| 4 | config_revision | u32 |
| 8 | state_flags | u32 |
| 12 | active_voices | u8 |
| 13 | source | u8 |
| 14 | target_timbre | u16 |
| 16 | volume_permille | u16 |
| 18 | physical_key_mask | u64 |
| 26 | remote_key_mask | u64 |
| 34 | error_bits | u32 |
| 38 | active_timbre | u16 |

state_flags 位：0 panic、1 codec_configured、2 codec_playing、3 audio_clock_good、4 calibration_done、5 recovery_active、6 engine_ready、7 timbre_switching、8 storage_busy；其余 0。

error_bits 位：0 codec、1 audio_clock、2 map/tag、3 event_input、4 event_fifo_overflow、5 frame_overrun、6 uart_rx_overflow、7 protocol_queue_overflow、8 telemetry_drop；其余 0。错误计数与当前错误不能混用；累计计数见 DIAGNOSTICS。

source：0 合成器、1 外部输入、2 编译测试音。若编译 AUDIO_TEST_MODE 非 0，状态显示 2；不等于允许运行切换。

请求响应的 STATUS 置 IS_RESPONSE，复制 SEQ；定时 STATUS 使用独立 SEQ，不置 IS_RESPONSE。

### 7.6 GET_CAPABILITIES / CAPABILITIES（06/07）

查询无载荷。响应固定 22 字节：key_count:u8、rows:u8、cols:u8、adc_bits:u8、max_voices:u8、capability_bits:u64、config_revision:u32、max_payload:u16、timbre_count:u8、light_ceiling:u8、spectrum_formats:u8。

初版 key_count=35、rows=5、cols=7、adc_bits=12、max_voices=35、max_payload=229、light_ceiling=32。

能力位沿用此前顺序：0 remote_keys；1 pressure_update；2 remote_pitch；3 sustain_pedal；4 independent_echo；5 reverb；6 metronome；7 light；8 adc_stream；9 spectrum_stream；10 full_midi_mapping；11 per_key_timbre；12 external_audio；13 sample_upload；14 persistent_config；15 parameter_notifications；16 key_config；17 telemetry_diagnostics；18 score_follow_v1；19 drumsticks_v1；20 audio_mix_control。未实现的能力位为 0。

仅当完整实现并通过测试后置 1。修改编译配置或连接不同音频路径时，能力位也必须真实变化。

### 7.7 TIME_SYNC（08，第二阶段）

请求 client_send_ms:u32。响应 client_send_ms:u32、device_receive_ms:u32、device_send_ms:u32。用单调毫秒计时；回绕按 u32 差值处理。用于估计时差和往返时间，不保证两端时钟完全一致，也不把手机收到通知的时间当作发声时间。

### 7.8 KEY_EVENT（10）

固定 3 字节：key_id:u8、action:u8、value:u8。action 0=松开/value=0；1=按下/value=1～127；2=压力更新/value=0～127。

key_id 是 FPGA 物理 sensor 身份，不是 App 显示数组序号，也不是 note_sel。

初版 action=2 返回 UNSUPPORTED，不能将其转换为 NOTE_ON。重复的按下若键已在 remote_pressed 中，更新状态不重新起音；要重触发必须先松后按。遥测/显示和音频状态不能反向合成按键事件。

### 7.9 ALL_NOTES_OFF（11）

载荷 scope:u8：0=只释放手机来源并清手机踏板/弯音；1=释放全部声部并禁止仍按住的物理键重新触发，直到它们释放。scope=1 需要引入物理 rearm mask；未实现前返回不支持，不复用硬复位假装正常尾音释放。

ALL_NOTES_OFF 是一次动作，不保持静音；音色 release 和混响可按正常机制衰减。PANIC 则另有保持语义。

### 7.10 PERFORMANCE_CONTROL（12）

载荷 control_id:u8、value:i16。ID1=远程弯音 -8192～8191；ID2=调制 0～127；ID3=延音踏板 0/1；ID4=表情 0～127。每项按能力逐步开放。

手机 x/y UI 不等于实体摇杆原始 ADC。远程弯音为归一化音高偏移，经 bend_range_cent 转换到 Q20 增益。不要把 x/y 乘一个常数后当 Q20 gain。

### 7.11 REMOTE_KEY_STATE（13）

固定头 10 字节：state_counter:u16、pressed_mask:u64，后接 key_count 个 u8 velocity。35 键载荷共 45 字节。

mask 为 0 的键 velocity 必须为 0；mask 为 1 的键 velocity 为 1～127；超出 key_count 的 mask 位为 0。state_counter 在同会话递增，u16 回绕；只接受新 counter，判新条件为无符号差值 1～32767，重复/旧快照丢弃且不续租。

快照纠正远程状态，不对仍按住的键重复起音；新加入的键触发一次，消失的键松开。快照更改很多键时进入内部 pending 队列，逐个派发，不能一拍只处理第一个后丢掉其余。

### 7.12 PANIC（14）

载荷 enabled:u8，0/1；需要 ACK。1=保持静音、清远程键/踏板/弯音，停止声部并清效果尾音；0=解除保持但不恢复旧音。

实现时单独 mute latch 进入最终输出门控，明确清混响状态的时序。音频时钟和 CODEC 初始化不应因每次静音重启。解除后物理键须释放再按，以避免突然恢复大声。校准/硬件故障静音优先于手机解除静音。

### 7.13 SET_PARAMETERS（20）

载荷 expected_revision:u32、count:u8、count 个 `{param_id:u16,value:i32}`。长度必须等于 5+6×count，count=1～37。

expected_revision=FFFFFFFF 表示不检查；否则须匹配。重复 param_id 在同批请求中视为 OUT_OF_RANGE。预校验全部通过后整体提交、revision 加 1。参数值与当前值完全相同的事务可以 ACK OK，但不增加 revision。

参数发生量化时响应 PARAMETER_VALUES 给出实际采用值，再 ACK 会产生双响应歧义，因此统一：SET_PARAMETERS 只回 ACK；客户端随后 GET_PARAMETERS，或者接收异步 PARAMETER_VALUES 获取实际值。不得把异步上报当第二个请求响应。

### 7.14 GET_PARAMETERS / PARAMETER_VALUES（21/22）

请求 count:u8、param_ids:u16[count]，count=1～37。成功响应 config_revision:u32、count:u8、items `{param_id:u16,value:i32}`，顺序与查询相同；未知或不支持参数整批错误 ACK。

异步参数变化帧使用相同载荷，IS_RESPONSE=0。一次本地修改只生成一次 revision；高频旋钮变化可合并上报，但最终值必须发出。

### 7.15 SET_KEY_CONFIG / GET_KEY_CONFIG / KEY_CONFIG（23/24/25）

SET 请求 expected_revision:u32、key_mask:u64、field_mask:u16，后接按 field 位升序的字段，供全部选中键统一应用。

field 位：0 enabled:u8；1 midi_note:u8；2 timbre_id:u16；3 velocity_mode:u8（0实时/1固定）；4 fixed_velocity:u8；5 curve_id:u8；6 RGB 三字节。timbre_id=FFFF 继承全局。

空 key_mask、越界位、空 field_mask、未知位、字段长度不符均拒绝。某字段未实现时整批 UNSUPPORTED，不能部分成功。颜色未支持时 bit6 不开放。

GET 请求 start_key:u8、count:u8，count=1～16。KEY_CONFIG 响应 config_revision:u32、start_key:u8、count:u8，后接每键 10 字节 `{enabled:u8,midi_note:u8,timbre_id:u16,velocity_mode:u8,fixed_velocity:u8,curve_id:u8,r:u8,g:u8,b:u8}`。

返回的是配置，不是当前发声槽快照。字段不支持时能力须说明；初版可只开放 enabled/自然音可映射 MIDI/跟随全局，不能谎称任意 MIDI 和独立音色。

### 7.16 GET_CATALOG / CATALOG（26/27）

GET 请求 kind:u8、start_index:u16、max_items:u8（1～8）。kind=0音色、1参数描述、2频带描述；本版仅冻结 kind=0，其余返回 UNSUPPORTED。

音色响应 kind:u8、total:u16、start_index:u16、count:u8，后接变长记录 `{id:u16,flags:u8,name_length:u8,name_utf8:bytes}`；单名最多 24 字节，不拆 UTF-8 字符。返回能放进协商 max_payload 的完整记录，至少一条，count 可以小于请求数。flags bit0=可选，bit1=测试性质，其余 0。

后续参数/频带目录须另写布局规范，不能沿用音色记录结构猜测解析。

### 7.17 SET_TELEMETRY（40）

请求 stream_id:u8、enable:u8、period_ms:u16、format:u8，共 5 字节。成功原 TYPE 响应同样 5 字节，返回实际周期。enable=0 时 period/format 必须填 0。

stream：0 STATUS；1 ADC；2 SPECTRUM；3 KEY_ACTIVITY；4 DIAGNOSTICS；5 BEAT_EVENT。STATUS format=0；ADC format=0原始/1滤波/2行程；SPECTRUM format=0现有显示高度。其他 stream format=0。

周期建议 STATUS/DIAGNOSTICS≥1000 ms，ADC≥50 ms，SPECTRUM≥50 ms。KEY_ACTIVITY/BEAT_EVENT 是事件流，enable=1 时 period=0。不支持的 stream/format 返回错误。每次新会话清订阅，默认只开 STATUS 1000 ms。

## 8. 参数、音色和键位

### 8.1 参数表（稳定 ID）

值统一 i32；本表范围为本工程第一版的实际可接受范围。扩展范围需要能力/描述更新。

| ID | 名称 | 单位/范围 | 当前硬件映射 | 阶段 |
|---|---|---|---|---|
| 0001 | MASTER_VOLUME | 0～1000 | round(value/10)→volume_percent 0～100 | P0 |
| 0002 | GLOBAL_TIMBRE | 稀疏 ID | timbre_sel，见目录 | P0 |
| 0003 | AUDIO_SOURCE | 0/1/2 | 现状只查询；设置 1/2 不支持 | 扩展 |
| 0004 | TRANSPOSE | 半音 -24～24 | 尚无独立接口 | 扩展 |
| 0005 | REMOTE_BEND_RANGE | cent 0～2400 | 新增远程弯音，不改实体 JOY 参数 | P1 |
| 0010 | VELOCITY_MODE | 0实时/1固定 | 事件后处理新增 | P1 |
| 0011 | FIXED_VELOCITY | 1～127 | 事件后处理新增 | P1 |
| 0012 | VELOCITY_CURVE | 0线性/1柔和/2强响应 | 新增 LUT；不得直接发 Float curve | 扩展 |
| 0013 | ATTACK_MS | 0～5000 ms | 各合成器尚无统一入口 | 扩展 |
| 0020 | SUSTAIN_ENABLE | 0/1 | 增加来源延音管理 | 扩展 |
| 0021 | RELEASE_MS | 0～10000 ms | 各合成器尚无统一入口 | 扩展 |
| 0022 | SUSTAIN_DELAY_MS | 0～3000 ms | 语义需补设计，不映射混响 | 预留 |
| 0030 | ECHO_ENABLE | 0/1 | 独立回声尚无 | 扩展 |
| 0031 | ECHO_DELAY_MS | 50～1500 ms | 同上 | 扩展 |
| 0032 | ECHO_FEEDBACK | 0～850 千分比 | 同上 | 扩展 |
| 0033 | ECHO_MIX | 0～1000 | 同上 | 扩展 |
| 0040 | REVERB_ENABLE | 0/1 | 新增 enable，关闭时 target wet=0 | P0 |
| 0041 | REVERB_PRESET | 0当前固定房间 | 只支持 0，不冒充多预设 | P0 |
| 0042 | REVERB_MIX | 0～1000 | round(value/10)→echo_percent | P0 |
| 0050 | METRO_ENABLE | 0/1 | metro_enable | P0 |
| 0051 | METRO_BPM_X10 | 300～2400 | 仅接受 10 的整数倍，除10→u8 | P0 |
| 0052 | METRO_BEATS | 1～12 | metro_beats | P0 |
| 0053 | METRO_UNIT | 2/4/8 | metro_unit | P0 |
| 0054 | METRO_VOLUME | 0～1000 | 当前固定 click 增益 | 扩展 |
| 0060 | LIGHT_MODE | 0水波/1常亮/2关闭 | light_mode | P0 |
| 0061 | LIGHT_BRIGHTNESS | 0～1000 | round(value×32/1000)→brightness | P0 |
| 0062 | LIGHT_RGB | 0～FFFFFF，0xRRGGBB | 固定色参数改成运行寄存器 | P1 |
| 0063 | RIPPLE_SPEED | milli-key/s | 无运行时入口 | 扩展 |
| 0064 | RIPPLE_WIDTH | milli-key | 无运行时入口 | 扩展 |
| 0065 | RIPPLE_DECAY_MS | ms | 无运行时入口 | 扩展 |
| 0070 | PHYSICAL_JOY_DEPTH | 0～1000 | round(value/10)→joy_percent | P0 |
| 0071 | REMOTE_JOY_ENABLE | 0/1 | 新增远程控制门控 | P1 |
| 0080 | UI_LANGUAGE | 0英语/1中文 | language_cn | P0 |

P0=核心蓝牙接入；P1=下一阶段。对预留字段本版必须 UNSUPPORTED。协议 ID 不等于现有代码寄存器地址。

读回量化值：volume/mix/depth 返回实际百分比×10；亮度返回 round(brightness×1000/32)。例如发送亮度500→raw16→读回500，发送1000→raw32→读回1000。不要让手机显示硬件实际达不到的未量化值。

本地混响旋钮改为0时 disable；改为非0时 enable 并更新 mix。远程 disable 保留最后 mix 配置，但 target wet 为0。须把“记住的 mix”和“实际 target wet”分开，避免开关丢失强度。

### 8.2 当前音色 ID

| ID | 显示名 | FPGA 标签 |
|---:|---|---|
| 1 | 钢琴 | PIANO |
| 2 | 风琴 | ORGAN |
| 3 | 钟声 | BELL |
| 4 | 木琴 | XYLO |
| 5 | 马林巴 | MARIMBR |
| 6 | 电钢琴 | EPIANO |
| 7 | 拨弦 | PLUCK |
| 8 | 长笛 | FLUTE |
| 9 | 贝斯 | BASS |
| 11 | 小军鼓 | SNARE |
| 13 | 弦乐 | STRINGS |
| 14 | 小提琴 | VIOLIN |

10、12 未出现在当前菜单选择序列，不对 App 暴露为可选项。部分合成器属于测试音色，音色目录 flags 应按实际音质定位标注。Android 当前“弦乐”映射13，不是3。

### 8.3 身份、布局和音高必须分离

当前 FPGA 的 `key_id` 是零起始 sensor 身份。`KEY_NOTE_MAP` 使用 packed 拼接，左侧是 key34，右侧是key0。当前 `{1,2,...,35}` 使 key0 对应 note_sel35、key34 对应1。

App 当前 defaultNote(id) 把第三行左侧设 MIDI60，并向上每行高八度、从左到右自然音递增。App UI id 不能直接当 sensor key_id。必须建立 `ui_to_sensor[35]` 和逆表，并用逐键上板点亮验证方向。当前实板与源码注释存在机械朝向待确认提示，不能从屏幕截图推断最终镜像。

建议先以设备 GET_KEY_CONFIG 返回的实际映射渲染显示；若需要保持 App 固定视觉布局，用显式 ui_to_sensor 转换后发命令，且所有按下、松开、ADC、灯光、多选统一应用此表。

修改键位时正在按住的键先维持旧 voice note/timbre，直到释放；下一次按下采用新配置。松键使用 held_note 记录，不能从已经改过的配置表反查，否则 voice_ctrl_bridge 会因 note 不一致忽略 OFF。

## 9. 事件合并、延音与紧急静音

### 9.1 为什么不能简单二选一

现有 key_event 输出单拍脉冲，而远程命令可能同拍到来。组合 `remote_valid ? remote : physical` 会丢掉实体事件。把两个 valid OR 在一起却只选一份 payload 也错误。

两种推荐实现：分别来源 FIFO 再仲裁；或者 pending 状态+每槽 dirty/revision 派发。必须保留短按 ON→OFF 顺序，不能只记最终 mask 把短促触发吞掉。

### 9.2 固定35槽的来源仲裁规则

本版保留35槽：每槽物理拥有优先级高于手机，两个来源不能同时发两个独立声部。

- remote only按下：触发远程音。
- physical only按下：触发实体音。
- remote持有时physical按下：实体接管，按实体力度重触发一次。
- physical持有时remote按下：记录remote_pressed，但不改变实体声音。
- physical释放而remote仍按住：保留当前gate，不重触发；后续新按采用新来源配置。
- 一个来源释放而另一个仍按住：不能发有效OFF。
- 两来源均释放且无对应踏板保持：发OFF，note使用该槽held_note。

若未来要两来源同键独立发声，必须增加声部或动态分配，不可声称当前35槽已经做到。

同槽全局配置变化不能把一个源的释放误作用到另一个源的新revision。仲裁后的事件是唯一进入音频 FIFO 的事件源。

### 9.3 ready/valid

合并器 out_valid 在 out_ready 前保持 payload 稳定。physical脉冲先入本地缓冲。当前 key_event_fifo 的输入没有 ready，需要先检查 full 或改成标准ready/valid；不能按“模块总是能收”假设设计。

超时清除远程来源可能需要连续35个槽检查；每周期处理一槽即可，不对全系统复位。事件拥塞要优先确保OFF/完整空快照最终被处理。

### 9.4 灯效触发策略

当前 keyboard_ripple 位于物理事件 FIFO 前，独立及时触发。接入远程后新增有界远程 NOTE_ON tap，去重后进入灯效触发仲裁。不要把所有灯光触发迁移到可能被音频 FIFO 阻塞的下游，导致实体灯效变慢。

### 9.5 远程弯音仲裁

第一版远程弯音可暂不支持。实现时建议显式控制模式：remote_joy_enable=1 时手机弯音覆盖实体pitch；关闭/超时平滑回实体pitch。这个模式会使全局所有声部一起弯音，状态/UI必须明确。

若改为增益相乘，至少使用足够宽乘积、Q20舍入和限幅；当前pitch_gain为22位，±24半音上端4.0已接近/超出现有无符号Q20的可表示边界，不能直接截断。需要限制范围或扩位并检查所有乘法链。实体颤音与手机调制含义不同，不允许简单互换。

### 9.6 历史保留能力

bit3 延音、bit4 独立回声是历史协议编号，本版 App 已删除对应功能，不提供控件，也不因曲谱练习重新开放。保留编号只为兼容旧帧，禁止复用；本版远程快照中相关标志保持 0。新固件未实现时能力位置 0。

## 10. ADC、频谱和诊断

### 10.1 ADC_DATA（41）

载荷：frame_id:u16、timestamp_ms:u32、format:u8、start_key:u8、count:u8，后接 count 个 u16。35键一帧载荷79、总帧94字节。

format0原始值（key_raw_data），1滤波值（key_data），2校准行程（key_travel）。12位右对齐，高4位0；未就绪应停止该格式流或通过STATUS表明无效，不填伪造实时值。

采集位置：key_channel_map 后得到sensor id与原始/滤波；key_calibrate 后得到行程。先写shadow[35]，在扫描完成边界发布完整快照；不要直接一边发UART一边读不断变化的寄存器造成跨扫描混帧。

若要同时发送多个格式，分别增加独立订阅实例的协议版本；本版一个ADC stream一次只选一种format。

### 10.2 SPECTRUM_DATA（42）

本版使用现有192列显示高度，载荷：frame_id:u16、timestamp_ms:u32、format:u8=0、start_band:u8=0、band_count:u8=192、heights:u8[192]。载荷201、整帧216字节。

height合法0～127，仅用于显示归一化 height/127。当前函数level是对近似幅度的对数压缩，不是校准dBFS，因此不标注绝对声压或dBFS。频率上限约3kHz（内部6kHz采样），不能拿手机麦克风32带的8kHz标签套用。

若双方协商TX载荷小于201，则按start_band分段，同frame_id组装；接收端收到新frame前未集齐旧frame则丢弃旧frame。每段COUNT不得越过192。

### 10.3 LCD 与遥测共享频谱的正确办法

现有audio_visualizer只有一个spectrum_address/lock读接口，LCD已经占用。不能把蓝牙地址直接OR/mux进去且不处理lock。

优先方案：频谱发布后快速复制192字节到telemetry_snapshot RAM。复制仅在系统clk域进行，保持对应bank稳定；按模块同步读延迟延后一拍采样，必要时再加输出寄存器。复制完成再释放资源；UART慢发期间只读快照，不占LCD bank锁。

若共用读口，必须实现明确仲裁、请求/完成握手和多读者bank租约；不能靠OR两个lock让一位锁表达两个独立读者。不要因等待UART将显示bank锁住几十毫秒。

frame_id在新FFT发布时递增，重复发送同一frame时不增加。当前FFT帧号u8扩到u16时要处理回绕。时间戳为快照生成时刻，不是UART发送完毕时刻。

### 10.4 KEY_ACTIVITY（43）

载荷 timestamp_ms:u32、physical_mask:u64、remote_mask:u64，共20字节。实体mask从key_event.key_down_mask引出（当前顶层未连接），远程mask来自remote manager；不根据voice_active倒推按键，因为尾音还活跃。

### 10.5 DIAGNOSTICS（44）

载荷 timestamp_ms:u32，后接以下9个u32累计计数，顺序固定：uart_framing_errors、uart_rx_overflows、crc_errors、length_errors、session_errors、command_queue_overflows、telemetry_drops、audio_frame_overruns、key_fifo_drops。共40字节。

采用饱和累计，清零暂不提供远程命令。计数来自实际事件；未接通的诊断能力不得宣称支持，也不能固定发0假装无错误。

### 10.6 BEAT_EVENT（45）

载荷 timestamp_ms:u32、beat_index:u8、beats:u8、unit:u8、accent:u8。beat_index零起始。现有beat_pulse/beat_accent在顶层未用，接出后增加beat计数或在effects内暴露。

FPGA是实际发声节拍主时钟。手机视觉可插值，但每次收到事件纠正相位；不能让手机LaunchedEffect独立运行数分钟后仍声称与FPGA对齐。

### 10.7 带宽预算

8N1理论单方向吞吐：115200→11520 B/s，250000→25000 B/s。

35键单格式ADC20Hz：94×20=1880 B/s；192带频谱20Hz：216×20=4320 B/s；合计6200 B/s，尚未计状态、错误、BLE限制和编码膨胀。

默认建议ADC10Hz+频谱10Hz，约3100 B/s，再按实测升到20Hz。频谱只能发布真实新帧，不伪造比内部FFT更快的新数据。拥塞时丢旧遥测保最新，不丢可靠应答；遥测队列设容量和计数。

## 11. 曲谱跟随扩展命令总表

本表 TYPE 全为十六进制，与参数 ID 的 0x60 等不是同一命名空间。

| TYPE | 名称 | 请求载荷 | 成功响应 |
|---|---|---:|---|
| 60 | SCORE_CAPS | 0 | 同 TYPE，16 字节 |
| 61 | SCORE_BEGIN | 28 | 通用 ACK |
| 62 | SCORE_DATA | 8+N | 通用 ACK |
| 63 | SCORE_COMMIT | 12 | 通用 ACK；之后 GET_STATE 验证 |
| 64 | PRACTICE_CONTROL | 20 | 通用 ACK；之后 GET_STATE 验证 |
| 65 | GET_PRACTICE_STATE | 8 | TYPE 68，48 字节 |
| 66 | GET_PRACTICE_RESULT | 8 | TYPE 69，48 字节 |
| 67 | SCORE_CANCEL | 4 | 通用 ACK |
| 68 | PRACTICE_STATE | 设备→手机 | 异步通知或 65 的专用响应 |
| 69 | PRACTICE_RESULT | 设备→手机 | 异步通知或 66 的专用响应 |

请求置 ACK_REQUIRED。成功专用响应置 IS_RESPONSE、复制请求 SEQ；命令错误用 TYPE03、IS_RESPONSE+IS_ERROR。异步 68/69 不置 RESPONSE，使用设备独立 SEQ。所有帧都带正确会话。手机按 session、upload_id、run_id 和 CRC 过滤旧数据。

### 11.1 SCORE_CAPS（60）

| 偏移 | 字段 | 类型 | 定义 |
|---:|---|---|---|
| 0 | extension_version | u16 | 固定 1 |
| 2 | flags | u16 | bit0 WAIT 跟随；其余预留 0 |
| 4 | max_groups | u32 | 实际可容纳的组数，App 上限 4096 |
| 8 | max_score_bytes | u32 | 实际 RAM 字节容量 |
| 12 | max_chunk_bytes | u16 | DATA 中 N 上限，1–192 |
| 14 | record_size | u16 | 固定 24 |

容量必须与综合后的实际 RAM 对应；不得固定宣称 4096 组而只分配少量存储。App 取设备和自身上限较小值。

### 11.2 曲谱二进制记录

按 index 顺序连续存储，每组固定 24 字节，无文件头：

| 偏移 | 字段 | 类型 | 约束 |
|---:|---|---|---|
| 0 | index | u32 | 从 0 连续递增 |
| 4 | start_ms | u32 | 原始曲谱时基下开始时间 |
| 8 | duration_ms | u32 | 组内最长时值，至少 1 |
| 12 | expected_mask | u64 | 物理目标键集合，非空且仅低35位 |
| 20 | note_count | u8 | 去重后的音高数，等于 mask 位数，1–35 |
| 21 | velocity | u8 | 原曲该组力度均值，1–127，仅参考 |
| 22 | flags | u16 | bit0=和弦，即 note_count>1；其余0 |

start_ms 由 MIDI tempo map 积分后四舍五入得到，须严格递增；曲谱总时间不超过 86400000 ms。duration_ms 是最大音符结束时刻减去本组起点，不是下一组间隔。乐器、曲谱原始音高/调号和标题仍保留手机；FPGA 依靠已确认键位与目标 mask 指导练习。velocity 不覆盖实际霍尔力度，也不主动合成声音。

### 11.3 CRC32 与键位绑定

曲谱 CRC 为上述记录拼接后的 CRC-32/ISO-HDLC：多项式 0x04C11DB7、反射实现 0xEDB88320、初值/终异或 0xFFFFFFFF。`123456789` 的结果为 0xCBF43926。线上用 u32 小端传输。

binding_crc 使用相同算法，输入按物理 sensor0…34 排列的70字节，每键为 enabled:u8(0/1)、midi:u8。必须对当前真实键位计算；不包含音色、力度、ADC、亮度。App 计算时先进行 UI→sensor 转换。

设备 BEGIN、COMMIT 和 START 都检查绑定；不匹配返回 REVISION_CONFLICT，不能静默套用旧曲谱。修改键位音高/启用状态时应使已上传练习失效，并停止/暂停正在执行的练习；全局音色或音量变化不使音高绑定失效。

### 11.4 SCORE_BEGIN（61）

| 偏移 | 字段 | 类型 |
|---:|---|---|
| 0 | upload_id | u32，非零，本会话内递增 |
| 4 | group_count | u32 |
| 8 | total_bytes | u32，必须 group_count×24 |
| 12 | score_crc | u32 |
| 16 | binding_crc | u32 |
| 20 | duration_ms | u32，最大 start+duration |
| 24 | record_size | u16=24 |
| 26 | format_version | u16=1 |

必须先验证容量、长度和键位绑定，再建立临时对象。RUNNING/PAUSED 状态返回 INVALID_STATE，不覆盖正在执行的曲谱。同 ID 同元数据幂等返回 OK；同 ID 不同内容返回 SEQUENCE_CONFLICT。新对象仅 RAM 存储，本版没有 Flash 持久化承诺。

### 11.5 SCORE_DATA（62）

upload_id:u32、offset:u32、data:u8[N]，总长 8+N，N≤双方协商上限且≤192。offset 是整个对象的字节偏移，允许记录跨块。

设备只接受连续前缀追加。对已接收区间的重复块，字节完全相同才返回 OK，不重复推进；内容冲突返回 INTEGRITY_ERROR。向前越过已接收前缀、越过对象大小或错误 ID 返回错误。ACK OK 表示此块已复制到自己的 RAM；不能借用 UART RX 活动缓冲，不能在 DMA 覆盖后才读取。

手机每次仅发一块，收到 OK 才推进 offset。BUSY 使用旧协议退避机制，不能把 BUSY 当成功。上传失败不显示已完成。

### 11.6 SCORE_COMMIT（63）

upload_id:u32、total_bytes:u32、score_crc:u32。设备核对完整长度、CRC、每条记录及 binding_crc 后原子置 READY，再返回 OK。失败保持不可启动，不允许部分可用。App 收 ACK 后查询状态，只有 READY、匹配 ID/组数/CRC 才开放开始。

### 11.7 PRACTICE_CONTROL（64）

| 偏移 | 字段 | 类型 |
|---:|---|---|
| 0 | upload_id | u32 |
| 4 | run_id | u32，非零 |
| 8 | action | u8：0 START、1 PAUSE、2 RESUME、3 STOP |
| 9 | mode | u8=0，WAIT 模式 |
| 10 | speed_permille | u16，START 为 500–2000 |
| 12 | start_index | u32=0 |
| 16 | flags | u32=0 |

START 只允许 READY/STOPPED/FINISHED，必须给新的 run_id，清统计、从第0组开始；不沿用上次进度伪装新一轮。App 速度选项为500/750/1000/1500/2000。PAUSE/RESUME/STOP 的 index/flags/mode 为0，speed字段忽略，App目前写1000。重复请求必须幂等。

PAUSE 冻结推进，清除目标灯光/判定中的临时匹配；RESUME 恢复当前组，必须重新取得有效按键沿。STOP 中止且清目标，保留曲谱以便新 run_id 重练；不会为未弹完的练习伪造完整结果。ACK只表示控制已接受，App随后用65取得真实状态。

当前扩展不提供 SEEK 或 LOOP。跟随开始时手机清除本地 A/B；跟随时本地预览拖动和点选不改变设备进度。

### 11.8 GET_PRACTICE_STATE（65）与 PRACTICE_STATE（68）

查询为 upload_id:u32、run_id:u32；上传后验证 READY 时 run_id=0。响应与异步状态统一使用48字节：

| 偏移 | 字段 | 类型 |
|---:|---|---|
| 0 | upload_id | u32 |
| 4 | run_id | u32，READY验证阶段0 |
| 8 | event_counter | u32 |
| 12 | phase | u8：0 READY、1 RUNNING、2 PAUSED、3 FINISHED、4 STOPPED、5 ERROR |
| 13 | mode | u8=0 |
| 14 | reserved | u16=0 |
| 16 | current_group | u32，0…total；FINISHED为total |
| 20 | total_groups | u32 |
| 24 | correct_groups | u32 |
| 28 | wrong_presses | u32 |
| 32 | elapsed_ms | u32，START以来单调时间，含暂停 |
| 36 | target_mask | u64，只有低35位 |
| 44 | score_crc | u32 |

每次推进、暂停/恢复、停止、错误、完成均发状态，运行时建议每500ms补发。READY/STOPPED/FINISHED/ERROR 的 target_mask=0；RUNNING 为当前组目标，PAUSED=0。event_counter 单调回绕，手机拒绝旧通知；专用查询响应允许与最后通知同 counter，不能因此丢弃查询的完成确认。

App运行中超过1500ms没收到状态时查询，最多约每秒一次；响应丢失沿用可靠重试。业务等待超过20秒进入明确失败状态。不能靠手机时钟自行推进真实跟随进度。

### 11.9 实体键判定与灯光

1. START/RESUME 时先等待目标键全部释放，防止上一组长按直接命中下一组相同音。
2. 只使用去抖后的 physical_mask 及其新按下沿；remote_mask、手机 KEY_EVENT/REMOTE_KEY_STATE、演示触摸都不能算真实成绩。
3. 目标是整个和弦集合。至少所有目标键在本组激活后产生新按下沿，且当前已启用键的物理按下集合与 expected_mask 相同，才计一组正确。
4. 已启用的非目标键的每个有效新按下沿计 wrong_presses 一次（禁用键不参与判定）；按住不按扫描周期重复计错。错误键松开后仍可继续完成本组。
5. 命中后 correct_groups 加一，推进到下一组并发状态。最后一组完成后关闭指示，发 FINISHED 状态及最终结果。
6. WAIT 模式不自动判漏音；自然完成时 correct=total、missed=0。错按仍会扣分。
7. 指示灯优先于背景水波/常亮，但只覆盖实际目标键；暂停/停止/失联后恢复用户原灯效，不永久改写颜色、亮度和灯效参数。
8. 练习不能接管现有按键声音或覆盖用户音色。用户自行选择哪个音色演奏。

### 11.10 GET_PRACTICE_RESULT（66）与 PRACTICE_RESULT（69）

查询 upload_id:u32、run_id:u32。只有完整完成的 run 才有结果；提前 STOP 返回 INVALID_STATE。设备在本会话内至少保留最后一次完整结果，查询必须可重放。

| 偏移 | 字段 | 类型 |
|---:|---|---|
| 0 | upload_id | u32 |
| 4 | run_id | u32 |
| 8 | total_groups | u32 |
| 12 | correct_groups | u32 |
| 16 | missed_groups | u32 |
| 20 | wrong_presses | u32 |
| 24 | timing_count | u32，0…correct |
| 28 | absolute_timing_sum_ms | u32 |
| 32 | elapsed_ms | u32 |
| 36 | score | u8，0…100 |
| 37 | reason | u8=0，完整完成 |
| 38 | reserved | u16=0 |
| 40 | score_crc | u32 |
| 44 | score_formula_version | u32=1 |

冻结评分公式：`score = floor(100 × correct_groups / (total_groups + wrong_presses))`，限定0–100；`correct + missed = total`。第一版 WAIT 不因慢弹扣分，不能把“等我弹对”暗中按严格节拍评分。timing_count=0 时平均时差显示“—”；如提供诊断时差，不参与V1评分，定义为相对本组激活时刻的命中延迟绝对值之和。平均值为 sum/count 向下取整。

手机验证 ID、CRC、长度、计数和公式后才展示真实成绩；不接收分数100但计数不匹配的报文。设备不得使用 remote_mask 产生假成绩。演示模式采用同样结果模型，但显式标记 demo，模拟全部命中、错按/漏音为0、评分100，不写入真实成绩。

### 11.11 SCORE_CANCEL（67）

upload_id:u32。取消传输或释放此对象及当前练习、清除临时判定和目标灯，返回OK。重复取消相同ID幂等成功；不能清空别的ID对象。手机退出当前曲目时取消；断线/新会话必须使旧上传和旧run失效，本版不支持跨连接断点续传。

## 12. 安全状态、重试与资源约束

- 新 HELLO、连接断开、3000ms会话失效：停止旧练习、清指示及目标、丢弃未提交上传，不能继续等待旧会话控制。保留的结果也必须与原会话绑定，不能串到新连接。
- App退到后台或离开演奏页：请求PAUSE；恢复页面后由用户继续，不自行启动实机练习。
- PANIC：全局静音并暂停练习、清目标；解除静音后由用户恢复。不能清除用户的原音量或曲谱绑定。
- UART溢出/CRC错：不推进上传偏移，不计练习命中；优先保留安全控制及按键事件。
- 音频实时路径与传输/CRC路径分离。上传记录在影子RAM内验证，COMMIT后切换有效指针，不能边传边当活动曲谱读取。
- 计数推荐至少32位，计数溢出应报ERROR，不回绕成看似更好的成绩。
- 无能力位、参数/记录无支持、容量不够：明确拒绝，不做部分成功，不宣称已保存或已评分。

## 13. App 实现位置

| 文件 | 作用 |
|---|---|
| PracticeProtocol.kt | 曲谱编译、CRC32/绑定、分块上传、控制、状态/结果校验、演示练习 |
| HallPadProtocol.kt | 复用可靠队列，新增60/65/66响应及68/69异步路由，ACK与业务状态衔接 |
| PracticeUi.kt | 发送、开始跟随、演示自动/手动模拟、实时统计与结果 |
| ScorePage.kt | 音轨/移调/键位与练习衔接，真实进度由设备状态驱动，输入改TextFieldState |
| MainActivity.kt | bit18能力门控，真实/演示控制器分开，键位总览按钮顺序 |

本地曲谱预览不会自动下发音符。真实设备无bit18时仍可正常使用旧功能。应用键位后要等待设备读回再发送；BEGIN/START绑定检查是最终防线，不能靠手机本地状态假定已应用。

## 14. 验收矩阵

| 场景 | 预期 |
|---|---|
| 旧固件bit18=0 | 不发送60–69，旧键盘和本地曲谱可用 |
| 小星星/欢乐颂不同调号 | 缺音先提示，应用对应键位后可编译并发送 |
| 20字节ATT分片、粘包、截断、坏CRC | 仅完整有效帧被分发 |
| DATA重复/重排/内容冲突 | 幂等或明确拒绝，偏移不误推进 |
| COMMIT CRC/绑定错 | 无法进入可启动READY |
| 正确完整演奏，无错按 | FPGA回100分；App验证后显示 |
| 正确10组、错按1次 | floor(1000/11)=90分 |
| 重复音/和弦/额外键 | 新沿、释放及整组规则正确，按住不刷分 |
| remote_mask模拟实体输入 | 不得推进真实练习 |
| 旧run/旧session/错误score_crc结果 | App拒收 |
| 暂停、后台、PANIC、断开 | 停止推进，清指示，不自动复启 |
| 演示自动/手动模拟 | 不发蓝牙，完整结束100分，显示演示标记 |
| 提前STOP | 不是完整成绩，不伪造100分 |

配套 tests/PracticeProtocolTest.kt 覆盖编译、物理映射、上传逐块ACK、BUSY、暂停恢复、旧状态/旧结果/坏分数拒收、超时及演示100分；tests/SessionPracticeTest.kt 验证真实帧编解码/会话/可靠队列与练习层联动。FPGA还必须增加对应RTL仿真和实板验收，这些软件测试不能代替硬件实现。

数值边界补充：当前安卓统计字段按非负有符号32位处理，计数及elapsed/timing字段须≤0x7FFFFFFF，超限设备报ERROR，不得回绕。成功查询只能返回指定专用响应，不能以通用OK ACK代替查询数据。

实现补充：HallPadTxQueue 将 SCORE_DATA 放在较低优先级，避免曲谱传输挡住释放、心跳和实时键。PerformanceControls 的通用数值输入与 MetronomeUi 的 BPM 输入也迁移为 TextFieldState；共享滑条增加结束提交回调，使节拍器仍在拖动结束时提交，而不是每个采样点发送。

## App 摇杆映射修正（2026-10-27）

- 控制台摇杆百分比通过既有参数 0x0070 写入，0%、25%、75%、100% 对应 0、250、750、1000；读回除以1000后同步到滑块。使用现有版本化 desired/applied 流程，避免旧读回覆盖较新操作。
- 0x0070 是实体摇杆深度参数；手机虚拟摇杆仍由 App 本地百分比缩放后发送 PERFORMANCE，不要求 FPGA 再次应用该深度，避免重复缩放。
- 远程 ID2 保持 0–127，无新增负数值或协议字段。
- 当前 App 的左右深度策略：左满推上限127，右满推上限32，再乘手机百分比并四舍五入。50% 时分别为64和16，100%时分别为127和32；这是 App 映射策略，不代表 FPGA 规定的音分幅度。
- 中心、禁用、后台按现有链路归零；演示模式与真实连接使用相同水平映射。
- 默认50%仍会减弱远程效果；本补丁不擅自调整 FPGA 调制振幅。

## App 端接收录制（2026-10-27）

不新增命令。App沿用订阅stream3 KEY_ACTIVITY以及STATUS掩码，录制回调只处理按键状态，绝不回发KEY命令。UI键位与物理sensor通过既有uiToSensor映射。

开始时保存键位配置与初始持键掩码，排除开始前持键；上升沿开始音符，下降沿结束音符。手机接收单调时钟用于时长，不承诺蓝牙接收时序等于物理触发时序。录制不使用ADC数值推测按键。

断连或进入后台停止并关闭未结束音符，保留本地内容；用户停止并保存后生成标准MIDI格式0文件并加入曲库。本版力度取键位配置，不能宣称录下真实动态力度。固件必须完整上报按下和松开，只有低频STATUS快照时可能漏掉短音。

## 15. 音源混合正式协议（接口 V1）

本节规定正式接口，KeyboardPercussion(10) 尚未实现。芯片为 TLV320DAC3100，I²S 为数字 DAC 路径，耳机孔外部音源须先确认实际连接到 AIN1/AIN2。仅在 FPGA 报告 capability bit 20 `audio_mix_control` 时开放设置；旧固件 bit 20 必须为 0。bit 19 用于鼓棒，不得复用。

新增参数 ID `0x0090`：`u32` 位图，bit 0 表示 FPGA I²S/DAC 声音开启，bit 1 表示 AIN 外部输入开启，其他位必须为 0。值 0、1、2、3 依次表示全部关闭、仅 FPGA、仅外部、同时开启。默认与复位值建议为 1，设备读回以实际生效状态为准。输入开关不等于主音量或紧急静音，静音优先关闭输出，解除后恢复路由。混音在芯片模拟输出混合器进行，不表示模拟输入被数字化或可录音。

沿用第 7 节 `SET_PARAMS`（TYPE 0x20）、`GET_PARAMS`（TYPE 0x21 / 0x22）及 ACK 格式：0x0090 的值为普通参数，不新增帧类型；写入应原子生效并更新配置版本，读回报告实际路由。无能力位时客户端不得写入，设备对未知参数返回既有 UNSUPPORTED；保留旧 `0x0003` 只读含义。I²C 配置失败应返回失败且保持已确认状态，不得虚报生效。单独比例/输入增益的寄存器能力、约束、范围及控制 ID 尚未冻结，不得擅自实现或复用其他参数。

设备端需实现：核实线路及 AIN 偏置/耦合，配置 Page 1 Register 35 的 DAC 与 AIN 路由、扬声器/耳机输出及防爆音顺序；独立 I²S 数字音量和模拟旁路的可调性应以芯片手册和实际接线确认；混合时预留电平余量防止削顶。两路同时关闭时输出静音；有音源打开时遵循现有主音量、静音与放大器电源策略。FPGA 应验证复位、连接、断线、同时开关和读回一致性。

## 16. 正式演奏协议与实现边界

第 11 节详细定义的 `TYPE 0x60–0x69` 与能力 bit 18 是正式演奏/练习接口：0x60 能力，0x61 开始上传，0x62 数据块，0x63 完成校验，0x64 开始/暂停/恢复/停止，0x65 查询状态，0x66 查询结果，0x67 取消，0x68 状态，0x69 结果。TYPE 与参数 ID 是不同命名空间。支持码、载荷、记录大小、CRC、错误与评分均以第 11 节及安卓 PracticeProtocol.kt 为准。不要假定本次提交修改了 FPGA；老设备没有相应能力位 时不应暴露真实设备跟随或混音控制。用户本地播放及演示练习不向硬件声称已完成。


## 17. 鼓棒正式协议（KeyboardPercussion(10) 实现）

能力 bit 19。设备支持两根鼓棒，索引0和1；方位0、1、2分别代表左前、正前、右前。所有多字节数小端，命令沿用原帧、会话与 ACK 机制。鼓棒配置保存在 FPGA 易失寄存器，复位恢复固件默认值；不要假定断电保存。

| TYPE | 方向 | 数据 | 说明 |
|---|---|---|---|
| 0x72 | 手机→设备 | 9字节 | 设置单棒配置，可靠请求；成功 ACK 后用0x73读回确认 |
| 0x73 | 手机→设备 | 1字节 stick_id | 查询指定鼓棒配置 |
| 0x74 | 设备→手机 | 9字节 | 0x73的响应，复制请求序号 |
| 0x75 | 设备→手机 | 12字节 | 异步敲击事件 |
| 0x76 | 手机→设备 | 3字节 | 可靠请求，试敲；成功 ACK 表示设备接收，实际事件以0x75为准 |

0x72 与 0x74 的 9 字节：偏移0 stick_id:u8；1..3 三个方位音色:u8；4 力度系数:u8（0..127，127为100%）；5 threshold:u16（30..1600）；7 cooldown_ms:u16（20..500）。配置必须完整写入，任何字段越界返回错误。音色编号：0军鼓、1底鼓、2闭合踩镲、3通鼓、4吊镲、5叮叮镲。两棒独立配置。0x76：stick_id:u8、direction:u8、velocity:u8（1..127），静音或设备未就绪会拒绝。

0x75：offset0 uptime_ms:u32；offset4 stick_id:u8；offset5 direction:u8；offset6 velocity:u8；offset7 source:u8（0真实，1模拟）；offset8 count:u32（每棒累计，允许回绕）。设备忙或缓冲溢出时遥测可能丢失，累计数不保证等于手机看到的事件数。状态帧 flags bit8/9 为两棒在线，bit10/11 为两棒校准状态；插拔检测 bit12/13 按实际固件极性解释。持续姿态上报尚未实现；DrumControl工程新增远程校准与灯效接口，详见第20节。设备不支持鼓棒时不得发送0x72–0x76。

### 验收要求

1. 连接后两棒读回配置；修改音色、力度、阈值、间隔后以读回为准，断线与设备复位后重新查询。
2. 左右棒分别试敲三个方位；检查0x76 ACK、0x75来源与响声；真实敲击检查方位、力度及事件。
3. 同时验证旧设备无能力位时按键、声音和既有协议可用，不能发鼓棒命令。
4. 曲谱接口 bit18、音源混合 bit20 与参数0x0090 是正式协议定义，但 KeyboardPercussion(10) 尚未实现；设备端实现、仿真和真机联调通过前不能宣布支持。
5. 验证 MIDI 编译、分块、CRC、断线取消、运行中暂停和准确计分；检查音源开关读回及静音优先级。

## 18. MIDI 直接演奏扩展 V1（新增规范，尚非已实现功能）

本节是 V1.2 新增要求；现有帧 VERSION 仍为 1。不得将本文视为 FPGA 或 App 已完成实现。自动播放采用本节，实体键和手机键盘仍采用 0x10/0x13；下载与跟随练习仍采用第11节。第1、13、16节中“本地预览不下发”的旧描述，在支持本扩展的设备上由本节覆盖。缺少实体键位不得过滤直接演奏的 MIDI 音符。

### 18.1 能力与命令分配

CAPS 新增 bit21（从0计数）DIRECT_MIDI_V1。仅在命令解析、音源接入、租约和清理均实现后置1。旧固件 bit21=0；App 不得发新命令或伪装已播放，可提示升级固件，旧键盘控制照常工作。

| TYPE（十六进制） | 名称 | 方向 | 载荷长度 | 可靠性 |
|---|---|---|---|---|
| 0x15 | MIDI_NOTE | 手机→设备 | 6 | 实时，不要求ACK，不自动重发 |
| 0x16 | MIDI_CLEAR | 手机→设备 | 1 | 可靠，按既有ACK规则重试 |
| 0x17 | MIDI_CAPS_GET | 手机→设备 | 0 | 可靠查询 |
| 0x18 | MIDI_CAPS | 设备→手机 | 8 | 0x17专用响应，同SEQ |
| 0x19 | MIDI_STATE | 手机→设备 | 7+4N | 实时完整状态，N可为0 |

TYPE 与参数ID不同命名空间；0x0013起音、0x0021淡出等参数不受影响。上述TYPE在本次参考基线未分配，合入其它分支前仍须检查冲突。

### 18.2 MIDI_NOTE（0x15）

| 偏移 | 类型 | 字段 | 规则 |
|---|---|---|---|
| 0 | u8 | source | 本版固定0：曲谱自动播放 |
| 1 | u8 | action | 0=松开；1=按下 |
| 2 | u16 | note_id | 本来源内活动音符唯一，允许0 |
| 4 | u8 | midi | 0–127，音高，不是物理键编号 |
| 5 | u8 | velocity | 按下1–127；松开固定0 |

多字节字段小端。必须先校验整帧CRC、会话、长度、字段和门控，再更新发声状态。note_id是声音实例标识，不是MIDI通道或键编号。C♯4与D♭4均发送61；MIDI60约定显示C4。

新note_id的按下创建一个声音实例；重复的相同note_id/音高按下只更新力度，不重新起音。仍活动的note_id携带不同音高时拒绝该事件，不隐式换音。不同note_id可同时演奏同一MIDI音高，松开其中一个不得影响另一个。未知note_id的松开是无操作；已知note_id但音高不匹配则拒绝，不释放其它声音。重新触发同音必须先松开旧实例再按下新实例。ID只在旧实例已释放后复用；跳转前先确认MIDI_CLEAR完成。

按下示例（仅载荷）：00 01 01 00 3D 64，表示来源0、note_id1、MIDI61、力度100。松开：00 00 01 00 3D 00。完整帧仍须附SOF、版本、TYPE、flags、SEQ、session、length和CRC，不能把载荷直接写UART。

### 18.3 MIDI_CAPS（0x18）

| 偏移 | 类型 | 字段 | 规则 |
|---|---|---|---|
| 0 | u8 | interface_version | 1 |
| 1 | u8 | midi_min | 0 |
| 2 | u8 | midi_max | 127 |
| 3 | u8 | max_active | 本扩展保证的同时活动实例数，1–35 |
| 4 | u16 | lease_ms | 本版1000 |
| 6 | u8 | max_state_notes | min(max_active, floor((协商最大负载-7)/4))，至少1 |
| 7 | u8 | reserved | 0 |

bit21表示支持当前全局旋律音色的0–127音高；若合成器只支持部分音域，不得置该位。协议范围不意味着超声或极低音可被喇叭清晰听到。打击乐通道9不得按旋律音色误播；本版App应明确提示该轨不支持直接旋律播放。每音符独立音色、MIDI通道和踏板不属于本扩展。

设备可共享原有音源，但必须保证上报max_active在实体键并行时也可兑现；不能保证时需减少声明上限或划分固定资源。达到上限的新按下拒绝，不能静默抢占实体键。错误按既有实时错误ACK格式上报并限速，成功不逐音确认。App播放前按重叠声音实例数检查上限；不可仅统计不同音高数。

### 18.4 MIDI_STATE（0x19）与租约

头：offset0 source:u8=0；offset1 state_counter:u16；offset3 count:u8=N；offset4 reserved:u8=0；offset5 reserved:u16=0。后续N条，每条note_id:u16、midi:u8、velocity:u8，共4字节。长度必须严格等于7+4N。计数不得超出已协商上限，ID不得重复，所有音高0–127，力度1–127。

这是本来源的完整活动状态：缺失ID释放；新增ID起音；已有相同ID/音高保持包络并更新力度；同ID不同音高整帧拒绝。全包校验通过后原子提交，不得半更新。N=0释放该来源全部活动音符。

独立state_counter初始任意；新计数的u16差值在1–32767接受，重复/旧计数丢弃且不续租。新会话、成功MIDI_CLEAR清除计数历史；App清理前必须丢弃本地尚未发送的旧NOTE/STATE帧，已交给BLE模块的字节只能按顺序排空，不可插入帧中。

App在播放中每200ms发送一次快照；参数、ADC和曲谱上传不得阻塞该快照。合法新NOTE或新STATE续租；普通心跳、参数设置不续MIDI租约。1000ms未收到续租帧则释放本来源，保留实体键。长音必须靠快照续租，不能反复发NOTE_ON重新起音。若下一快照仍列出超时释放的ID，视为新实例重新起音。

### 18.5 MIDI_CLEAR（0x16）与生命周期

载荷source:u8，本版仅0。成功响应既有ACK，效果幂等：停止该来源所有声音（允许音源正常淡出）、清租约和快照计数。重复请求只回放ACK。PANIC优先于一切来源，并释放MIDI及原有远程按键；清除PANIC不能复活旧音符。旧会话、未就绪、静音时拒绝新增音符，释放操作仍必须可执行。

暂停、开始跟随、换曲、跳转、循环回跳：先停止旧事件调度并丢弃未发送旧帧，发送CLEAR并等待成功，再创建新时间线；恢复时重建跨越当前播放位置的活动长音。播放自然结束也发送CLEAR。CLEAR失败不得继续新播放，应显示错误并等待租约释放。

App内切页、返回列表、进入后台或锁屏不代表暂停。前台服务承担调度和连接，通知栏可暂停；UI只观察状态。系统强停、进程死亡或真实断连不能保证继续，设备租约负责防卡音；重连后不得自动复活旧队列，用户显式恢复后重新同步。切页时释放触摸键不得同时清除曲谱来源。

### 18.6 调度、资源与兼容

复用既有UART、帧CRC、会话和错误码，不另建一套传输协议。实时NOTE/STATE不进入16项可靠响应缓存；CLEAR和能力查询沿用可靠机制。优先级：安全释放/停止 > 实时音符和续租 > 普通设置/查询 > ADC/频谱/文件块，只能在完整帧边界仲裁。必须按应用事件顺序发送；不允许“优先松开”导致同一实例的松开超越尚未发送的按下。

本版不提供未来时间戳调度：音符收到后尽快执行，BLE延迟仍存在；不得宣称达到硬件同步。和弦逐帧会有到达差，后续可另行定义批量边沿命令，不擅自扩展本版长度。先复用原有声部与音高查表，避免建立128路振荡器；MIDI范围128不等于128复音。

第11节下载/跟随仍依赖实体键映射，因为需要点灯并判定实体演奏。直接MIDI自动播放不应用或覆盖实体键位，不再使用“找不到键则跳过”的路径。对旧固件保留原协议，但不能将缺失音高替换成邻近音。节拍器实时拍点0x45仍按原文属于需设备实现的接口，本次未改变其实现状态。

### 18.7 双端验收

1. MIDI0、60、61、127都能收到并按音高查表，越界字段不产生声音。
2. 两个不同ID的MIDI61同时按下，释放一个后另一个继续；重复NOTE不重新起音。
3. 长音10秒，快照持续时不中断；停止快照和NOTE后1000ms内触发租约清理。
4. 丢失NOTE_OFF后快照纠正；重复/旧快照不得复活声音或续租。
5. 暂停、换曲、跳转、循环、开始跟随后旧实例全部释放，无旧包复活。
6. 切页、返回列表、后台、锁屏继续播放；通知暂停和页面暂停状态一致。
7. 实体键、手机触摸键和MIDI来源互不误释放；PANIC和断连清理有效。
8. 旧设备bit21=0时不发送新TYPE；新设备0x17响应字段与实际资源一致。
9. 同时压力测试ADC10Hz、参数设置、和弦及心跳，无FIFO覆盖和长期排队。
10. App、FPGA均完成以上检查前，发布说明必须标为“协议已定义，功能待实现/待验收”。


## 鼓棒与音量配套修订（2026-10-31）

本次鼓棒范围及行为以随工程DRUM_VOLUME_UPDATE.md为准，替代第17节旧范围。音色255=无；系数0..127，127=100%；间隔20..500ms。原有帧长度及命令编号不变。STATUS bit8/9为左/右在线、10/11为校准完成、12/13为已插入（1=插入），与第7.5节storage_busy旧bit8定义冲突处以本修订为准，不再把bit8解析为storage_busy。

## 20. 鼓棒手动校准与独立灯光（2026-10-31，DrumControl 工程已实现）

本节是本次新增命令的正式定义，替代第17节“没有远程校准命令”的旧限制。线上帧 VERSION 仍为1，沿用帧头、CRC、会话、可靠请求、ACK与重复包缓存。整数均小端。以下 TYPE 不属于 SET_PARAMETERS 的参数 ID 空间。

### 20.1 能力与兼容

CAPS capability_bits 新增 bit22 `DRUM_CAL_CONTROL_V1`、bit23 `DRUM_HIT_LIGHT_V1`；原 bit19 鼓棒能力保留，bit21 仍专属于 DIRECT_MIDI，不得复用。本工程置 bit19/22/23，新增命令以 CAPS 为准。bit21 不因本次更新而置位。

旧手机可以继续使用0x72–0x76，但不会出现新增按钮。新版手机遇到无相应能力位的设备应隐藏/禁用新功能，不发送新命令。本次交付包含FPGA与接口文档，不包含安卓实现。

| TYPE | 名称 | 方向 | PAYLOAD |
|---|---|---|---|
| 0x77 | DRUM_CAL_START | App→FPGA | 1字节，必须为0x03 |
| 0x78 | DRUM_CAL_GET | App→FPGA | 0字节 |
| 0x79 | DRUM_CAL_STATUS | FPGA→App | 12字节 |
| 0x7A | DRUM_LIGHT_SET | App→FPGA | 6字节 |
| 0x7B | DRUM_LIGHT_GET | App→FPGA | 0字节 |
| 0x7C | DRUM_LIGHT_VALUES | FPGA→App | 6字节 |

0x77/0x7A 必须设置 ACK_REQUIRED（flags bit0=1）。写入仅返回现有 ACK；查询分别返回0x79/0x7C，不再附加成功ACK。所有请求均要求有效会话。错误沿用现有 ACK：UNSUPPORTED=7、BAD_LENGTH=2、INVALID_ARGUMENT=3、INVALID_STATE=5。现有错误限流仍适用。

### 20.2 校准启动与一次性自动校准

- 上电只做插入检测、MPU通信初始化和采样，不启动校准。
- 本次上电首次切换FPGA屏幕到鼓棒页（main_view=3）时，登记一次自动尝试；两根鼓棒都已插入且通信在线、稳定约100 ms后开始。缺棒时显示等待。等待期间离开该页不会开始，返回该页后继续等待。
- 一旦尝试开始，本次上电不再自动重试。再次切换页面、掉线重连、姿态故障、采样溢出均不会自动重启。有效校准在切换页面时保留；拔出或通信掉线会使对应校准失效。
- 菜单鼓棒页新增第7项 `RECAL / PRESS`，选中后短按旋钮启动，与手机共用同一控制入口。
- 手机发0x77，payload=03（bit0左、bit1右），本版只支持两棒一起校准；01、02、00及其他值均拒绝。两棒未插齐/不在线、等待自动校准或正在校准时返回INVALID_STATE。
- ACK成功只表示请求已接受。开始后 attempt_id递增，手机必须查询到READY才显示成功；重复发送同一会话、TYPE、SEQ和payload，命中现有缓存时只重放原回复，不会再次校准。真正重新校准须使用新SEQ。
- 手动启动过校准也视为已使用本次上电的一次自动机会，防止之后进入鼓棒页又自动启动。
- 校准采集原有256个连续静止有效样本，运动会重新累计。10秒仍未完成则停止，报告超时。校准中拔出/掉线立即停止，不会等重连后偷偷恢复；后续必须手动重试。
- 本版两棒都就绪才允许实际挥棒发声。重新校准期间抑制实际挥棒触发；既有BLE模拟鼓点命令仍遵循原音频可用条件。

### 20.3 校准状态0x79

0x78查询无payload，响应0x79固定12字节。**本版不推送0x79异步通知**。建议校准页每200 ms使用新SEQ查询一次，离开页面可降低频率。不要重复利用同一SEQ轮询，否则可能读到缓存状态。查询同时刷新会话活跃时间。

| offset | 字段 | 类型 | 含义 |
|---|---|---|---|
| 0 | inserted_mask | u8 | bit0左、bit1右，1=已插入；来自PLG低有效检测 |
| 1 | online_mask | u8 | bit0左、bit1右，1=MPU通信在线 |
| 2 | calibrated_mask | u8 | bit0左、bit1右，1=已有校准结果 |
| 3 | active_mask | u8 | bit0左、bit1右，1=正在采集校准样本 |
| 4 | progress_left | u8 | 已累计静止样本进度0..255 |
| 5 | progress_right | u8 | 同上 |
| 6 | state | u8 | 0未校准、1等待连接/进入页、2校准中、3就绪、4失败/需重校准 |
| 7 | reason | u8 | 0无、1拔出/掉线、2校准超时、3姿态故障、4采样溢出 |
| 8 | pose_fault_mask | u8 | bit0左、bit1右 |
| 9 | sample_overflow_mask | u8 | bit0左、bit1右 |
| 10 | attempt_id | u16 | 每次实际启动+1，复位归零，允许回绕 |

mask高6位均为0。进度不是固定倒计时，运动时可归零；仅calibrated对应位为1才可显示该棒100%。整体可用必须state=3且两棒inserted/online/calibrated均为3，不能只看calibrated_mask。STATUS原有bit8/9在线、10/11校准结果、12/13已插入继续保留，精确校准流程读取0x79。

状态示例（payload HEX）：
- 两棒连接但尚未进入鼓棒页：`03 03 00 00 00 00 00 00 00 00 00 00`。
- 首次校准成功且无故障：`03 03 03 00 FF FF 03 00 00 00 01 00`。

### 20.4 鼓棒灯光0x7A/0x7C

0x7A设置与0x7C读回采用相同6字节结构；0x7B查询无payload。整组验证后原子写入，错误不得部分生效。独立于键盘灯光设置，不写键盘亮度、速度或衰减；不增加键盘config_revision。仅RAM保存，复位恢复默认。

| offset | 字段 | 类型 | 范围 | 默认 |
|---|---|---|---|---|
| 0 | enabled | u8 | 0关闭，1开启 | 1 |
| 1 | brightness_percent | u8 | 0..100 | 10 |
| 2 | attack_ms | u16 | 1..1000 ms，数值越小亮起越快 | 40 |
| 4 | decay_ms | u16 | 0保持；1..5000 ms，峰值后淡出时长 | 1200 |

手机“速度”控件可直接显示“亮起时间(ms)”，或将快→慢映射到attack_ms；不能沿用键盘空间扩散速度的数值单位，因为每支鼓棒当前只有一个独立像素。默认payload：`01 0A 28 00 B0 04`。最大亮度、快速亮起、常亮保持示例：`01 64 01 00 00 00`。关闭后尽快发送黑帧；0亮度也不发光。参数变更作用于当前包络后续更新，读回以实际值为准。

### 20.5 换色、触发及硬件映射

- 与键盘一致：八色顺序循环，首个新组触发将色号+1，20 ms固定窗口内的后续鼓点使用同色，后续鼓点不延长窗口。窗口边界时的新鼓点开启下一组。左右棒共享鼓棒色号/窗口，与键盘的色号/窗口独立。
- 左右灯分别响应各自被合成器接受的鼓点，重击重新从0亮起并覆盖旧包络。真实挥棒与0x76模拟鼓点均可触发灯光。音色“无”、系数0、被拒绝/未送入合成器的事件不会亮灯或推进鼓棒色号。灯光关闭时不推进色号。
- 鼓棒独立全亮色表：`2070FF、20FFC0、80FF20、FFC020、FF5020、FF2070、C020FF、6020C0`。
- 键盘原八色为`0000FF、00FFFF、00FF00、FFFF00、FF8000、FF0000、8000FF、FF0080`，两套预设RGB无重复。此约束针对预设色表；黑色表示熄灭，亮度/淡出会改变实际RGB。键盘自由自定义RGB仍可人为选成鼓棒色，本版不禁止用户自定义颜色。
- 一个WS2812像素/每路，GRB发送格式，复用已存在的keyboard_rgb_chain；物理左DRUM1_RGB=F19、物理右DRUM0_RGB=D19。灯亮独立于手机连接，不占用音频事件握手、不等待蓝牙遥测。

### 20.6 手机联调步骤

1. HELLO建会话→CAPS检查bit22/23。
2. 校准按钮：发可靠0x77(03)，收ACK后用新SEQ轮询0x78；状态3才显示就绪，状态4显示原因并允许重试。
3. 灯光页：先0x7B读回；用户调整后合并/节流发送可靠0x7A；收ACK后用新SEQ读回确认。相同请求重试保持原SEQ，新的设置使用新SEQ。
4. 无bit22/23时隐藏新入口，既有鼓棒音色设置和模拟鼓点功能继续按bit19工作。
5. 实板验收：上电无CAL→首次进鼓棒页校准→离开再进不重校准；拔插后不自动校准；菜单/手机可重试；左右模拟鼓点检查D19/F19对应、共色窗口、0/100%亮度、衰减与常亮。


## 21. 鼓棒自定义 RGB 与设置入口修订（2026-10-31）

### 21.1 本次交付范围与兼容

本修订配套安卓补丁已增加设置入口、RGB 编辑、能力判断、可靠请求和读回处理；未编译 APK 或完成实板验收。本次不包含 FPGA 修改。第20节现有 0x7A/0x7B/0x7C 仍保持原有长度和含义，不向六字节包追加 RGB，不改变线上 VERSION=1。

新增能力 `capability_bits` 的 bit24：`DRUM_RGB_CONTROL_V1`。它是第7.6节现有 u64 能力字段的一位，不是新参数 ID。设备仅在实现本节全部配色命令后声明；该能力要求同时支持 bit19 鼓棒与 bit23 鼓棒灯光。不得借用 bit21（DIRECT_MIDI）、bit22（校准）或 bit23 冒充 RGB 能力。

新版 App 始终显示鼓棒设置入口，无能力时显示说明并禁用相应操作，不发送不支持的新命令。此规则替代第20节“隐藏新入口”的 UI 建议；命令仍须按能力位隔离。

- 设备设置 → 灯光：顶部“鼓棒设置 · 校准 / 灯光 / RGB”快捷入口；完整鼓棒灯光与配色控件仍排在键盘灯光所有设置下面。
- 演奏页：列表与曲谱详情均显示“鼓棒设置 · 校准 / 灯光”，进入后可校准两棒、分别设置左右棒，或进入灯光与 RGB。
- 演示模式支持本地配色预览与修改，不发送蓝牙；不能把演示校准当作真实校准。

### 21.2 新增命令

以下命令编号经本次输入文档核对未占用，作为本次扩展分配；FPGA 实现前仍须核对其实际命令分发表。

| TYPE | 名称 | 方向 | PAYLOAD |
|---|---|---|---|
| 0x7D | DRUM_COLOR_SET | App→FPGA | 4字节：mode、red、green、blue |
| 0x7E | DRUM_COLOR_GET | App→FPGA | 无载荷 |
| 0x7F | DRUM_COLOR_VALUES | FPGA→App | 4字节，结构与 SET 相同 |

0x7D 必须置 ACK_REQUIRED=1，仅回复既有 0x03 ACK，不同时返回成功的 0x7F。0x7E 由 App 使用既有可靠请求机制发送；成功只回复 0x7F，置 IS_RESPONSE=1，复制请求 SEQ 与 SESSION_ID，不再附加成功 ACK。本版不推送异步 0x7F。

所有请求要求有效会话。重复包缓存、CRC、超时重试、会话隔离与既有协议一致；新查询用新 SEQ，超时重试保留原 SEQ 和完整内容。不得因查询读取旧缓存而显示旧配色。

| offset | 字段 | 类型 | 范围 | 上电默认 |
|---|---|---|---|---|
| 0 | mode | u8 | 0=原八色循环；1=固定自定义 RGB 的击打灯光 | 0 |
| 1 | red | u8 | 0..255 | 32（0x20） |
| 2 | green | u8 | 0..255 | 112（0x70） |
| 3 | blue | u8 | 0..255 | 255（0xFF） |

按 mode/R/G/B 紧密排列，不是 GRB 顺序；GRB 转换由灯珠驱动执行。mode=0 时 RGB 仍需保存并原样读回，只在固定配色模式使用。四字节必须整体校验后原子提交。

### 21.3 灯光行为

- 默认 mode=0，沿用第20.5节八色顺序、20ms固定共色窗口及左右棒共享色号。
- mode=1，两棒共用用户 RGB，各自仅在对应鼓点被合成器接受后起亮；不新增“无需击打就常亮”模式。
- 自定义模式不推进八色序号；切回循环模式后，下一有效新组从保留的序号继续。切换模式本身不推进序号，也不重启包络。
- 亮度、attack_ms 与 decay_ms 继续由 0x7A 控制；颜色全量值先按亮度和包络缩放后送灯，不得把亮度预乘值保存为用户 RGB。
- 参数提交后，当前仍活动的左右灯在下一次正常灯光更新使用新模式/颜色及既有包络进度，熄灭的灯保持熄灭；不触发音频、不伪造击打。自定义模式切回循环时，当前活动像素使用各自保留的循环组色号。
- decay_ms=0 保持的是已触发灯光的峰值；关闭 enabled 或亮度0应熄灭。RGB=000000 是合法黑色；在 enabled=1 的自定义模式仍视为接受了有效击打包络，但显示为黑色，不推进循环序号。
- 配色独立于键盘，不修改键盘 RGB、亮度或配置 revision；仅 RAM 保存，复位恢复默认。断开手机不会清除配色。
- “不与键盘预设色重复”仍约束默认鼓棒循环色表；用户自定义 RGB 可以与键盘任意颜色相同，不做禁止或偷偷替换。

### 21.4 错误与回读

| 情况 | 结果 |
|---|---|
| 不支持 bit24 或命令未实现 | UNSUPPORTED=0x07 |
| SET 长度不等于4或GET长度不等于0 | BAD_LENGTH=0x02 |
| mode非0/1 | OUT_OF_RANGE=0x03，detail=0（mode偏移） |
| 会话无效 | BAD_SESSION=0x09，按既有会话规则处理 |

错误不得部分修改任何颜色或模式。ACK OK 表示四字节目标配置已提交，不表示已收到真实击打，也不保证灯立即点亮。

App：CAPS bit24=1 → GET(0x7E) → 校验0x7F长度及mode → 编辑本地草稿 → 显式“应用鼓棒配色” → SET(0x7D) → ACK OK → 使用新SEQ GET → 仅将读回值视为设备实际值。调整中的输入不逐字发包，避免堵塞实时演奏。HEX必须六位；点击全选，失焦或完成输入时不完整内容恢复到最近合法草稿，取消不发送。

若仅 bit23=1：0x7A–0x7C 可继续使用，RGB编辑禁用并说明需新版FPGA。若 bit23=0：灯光整组保留可见，禁用控制并提示能力缺失。不得为探测支持而盲发新命令。

### 21.5 载荷示例（仅 PAYLOAD，不含帧头及 CRC）

| 场景 | HEX |
|---|---|
| 上电默认循环色，保留蓝色自定义值 | `00 20 70 FF` |
| 固定红色 | `01 FF 00 00` |
| 固定绿色 | `01 00 FF 00` |
| 固定蓝色 | `01 00 00 FF` |
| 固定黑色（合法） | `01 00 00 00` |
| 固定白色 | `01 FF FF FF` |
| 切回循环，同时保留自定义白色 | `00 FF FF FF` |

### 21.6 FPGA 配套实现与验收清单

1. 增加0x7D/0x7E分发表和0x7F响应、长度/模式校验；沿用可靠请求缓存，重复SET不重复应用动作。
2. 新增RAM寄存器mode/R/G/B与复位默认值；在鼓棒灯光取色阶段增加模式选择，不改变音频合成及击打握手。
3. GET按实际寄存器返回，ACK不增加键盘revision；实现完成后才置bit24，保持其他能力位不变。
4. 验证循环→固定红/绿/蓝/黑/白→循环；左右像素各自击打生效，20ms窗口规则保留。
5. 验证0/100%亮度、起亮/衰减、decay=0、关闭熄灭，RGB变化不重启包络、不触发音频；校准、音色“无”、力度0沿用原行为。
6. 验证旧App仍可使用六字节灯光命令，新App遇旧FPGA不发0x7D/0x7E；非法mode/长度不部分提交。
7. 完成布局布线时序检查和实板测试后，才能宣称FPGA支持本节；本次文档和安卓补丁不构成FPGA实现完成证明。


## 22. 鼓棒三模式灯光（安卓已接入，FPGA待实现）

本节替代第21节旧的鼓棒灯光UI规则。删除灯光页顶部鼓棒设置快捷按钮及八色预览，键盘灯光全部设置下直接排列鼓棒灯光。保留演奏页鼓棒设置与校准。灯效不显示预览；水波显示亮度、速度和衰减；常亮显示亮度、HEX与RGB；关闭隐藏这些参数。修改草稿后点击应用，ACK成功再查询读回。

### 22.1 能力与命令

新增CAPS u64 bit25 `DRUM_LIGHT_MODES_V1`，要求支持bit19。设备实现本节全部功能后才能声明。本次输入协议中未定义0x83–0x85，分配如下；实际FPGA集成须检查命令表冲突。旧0x7A–0x7F保持原有字节格式，不擅自扩长。新App的三模式页面只按bit25发送本节命令；无bit25显示说明并禁用控制，演示模式仅本地生效。

| TYPE | 名称 | 方向 | 长度 |
|---|---|---|---|
| 0x83 | DRUM_EFFECT_SET | App→FPGA | 9 |
| 0x84 | DRUM_EFFECT_GET | App→FPGA | 0 |
| 0x85 | DRUM_EFFECT_VALUES | FPGA→App | 9 |

SET必须ACK_REQUIRED，仅返回0x03 ACK。GET沿用可靠请求机制，成功仅返回0x85（IS_RESPONSE=1，同SEQ/SESSION），本版不异步推送。有效会话、CRC、重复请求去重、500ms超时及最多2次重试遵循原协议。新查询新SEQ，重试相同SEQ。

### 22.2 配置结构（SET和VALUES相同，全部小端）

| offset | 字段 | 类型 | 范围 | 默认 |
|---|---|---|---|---|
| 0 | mode | u8 | 0水波、1常亮、2关闭 | 0 |
| 1 | brightness_percent | u8 | 0..100 | 10 |
| 2 | speed_milli_pixels_per_second | u16 | 500..30000，对应0.5..30格/s | 5000 |
| 4 | decay_ms | u16 | 200..5000 | 1200 |
| 6 | red | u8 | 0..255 | 32 |
| 7 | green | u8 | 0..255 | 112 |
| 8 | blue | u8 | 0..255 | 255 |

默认载荷：`00 0A 88 13 B0 04 20 70 FF`。常亮红色100%：`01 64 88 13 B0 04 FF 00 00`。关闭且保留其他默认参数：`02 0A 88 13 B0 04 20 70 FF`。

九字节整体校验和原子提交；非当前模式的参数也必须合法，并保存读回。长度错误BAD_LENGTH=2；字段越界OUT_OF_RANGE=3，detail填字段起始偏移；未实现UNSUPPORTED=7；会话错误按既有BAD_SESSION=9。错误不部分修改，ACK表示已提交；后续GET返回实际值。设置仅RAM保存，不改变键盘配置、不增加键盘revision。

### 22.3 灯效定义及硬件边界

- 水波：每根棒的有效击打从像素0向棒前端传播，像素i延时为 `i * 1000000 / speed_milli_pixels_per_second` 毫秒。像素前沿到达后按decay_ms从峰值线性衰减到0。默认八色顺序及20ms固定共色窗口沿用第20.5节；两棒共享鼓棒窗口，与键盘独立。新击打覆盖对应棒旧波，不影响另一棒。音色无、系数0或被音频拒绝的击打不启动波、不推进色号。
- 常亮：无需击打，两棒所有已配置灯珠持续显示自定义RGB乘亮度；切入后下一正常灯光刷新生效，速度和衰减只保留不参与效果。黑色合法。
- 关闭：两棒全部像素送黑，清除旧水波，保持配置供下一次启用；不推进循环色号。亮度0同样不发光。
- 切换模式清除旧水波，切回水波后等待新的有效击打，不复活旧波。修改水波速度/衰减/亮度影响现有波后续更新，不凭空产生击打。
- 左右棒实际像素数量由FPGA工程参数分别确定，本命令不配置数量。像素0必须接近棒尾、序号朝棒前端递增。上一版工程每棒仅一个像素，只有逐棒击打淡出，无法呈现空间前向传播；不得虚报已经实现多灯扩散。FPGA与硬件需配置真实串联数量后验收。
- 旧SET灯光或配色命令被旧App调用时，可进入兼容击打模式并查询原格式；0x84返回所保存三模式配置。三模式App不混发旧SET与新SET。再次0x83显式切回三模式。FPGA应在实现说明中明确其兼容调度，不能让旧模式和新模式同时驱动灯珠。

### 22.4 验收

验证水波按真实像素数量前向传播、速度端点、每棒重击覆盖、共色窗口；常亮无需击打、全部像素及RGB正确；关闭和亮度0全灭。验证旧协议长度不变、能力隔离、SET失败不部分生效、ACK后读回及断连RAM保留。需重新进行FPGA综合、布局布线及实板验收；本次安卓源码和协议定义不构成FPGA完成证明。


## 23. 曲谱同步逐拍触发 V1（2026-11-01，FPGA待实现）

### 23.1 实现核查与交付范围

核查附件KeyboardPercussion_Stable2(1).zip：hallpad_protocol_ctrl.v无0x45/46/47分发；未知命令走UNKNOWN_COMMAND。keyboard_top.v的audio_effects实例将beat_pulse/beat_accent悬空。test_audio_effects.v的audio_effects模块由metro_enable/BPM/拍号驱动独立累加器，参数改变会立即重置并重发强拍。因此不存在手机触发指定拍点的入口。

更正此前建议：0x45 BEAT_EVENT已定义为FPGA→App遥测，不改变其方向或载荷。本节新增0x46/0x47。所查工程CAPS常量0x7C80000已使用bit26（连同19/22/23/24/25），本功能分配bit27 `SCORE_BEAT_TRIGGER_V1`。bit27要求同时支持既有会话、节拍音源与基本参数控制。仅实现并验收后置位。

本次交付安卓源码和协议、FPGA修改说明，不改FPGA。手机自动播放通过同一单调时钟调度音符和拍点，支持MIDI变速/拍号、播放倍率和AB回跳。采用收到即执行，未实现未来时间戳队列，仍存在BLE排队及到达抖动，不宣称硬件级同步。跟随WAIT模式没有连续推进时钟，本版不启用此节拍按钮；未来若需跟随节拍需单独定义等待/恢复语义。

### 23.2 命令

| TYPE | 名称 | 方向 | 长度 | 可靠性 |
|---|---|---|---|---|
| 0x46 | SCORE_BEAT_CONTROL | App→FPGA | 5 | ACK_REQUIRED=1，既有0x03 ACK |
| 0x47 | SCORE_BEAT_TRIGGER | App→FPGA | 10 | flags=0，成功不ACK，不补发过期拍点 |

0x46字段：offset0 action:u8（0停止、1开启）；offset1 run_token:u32，非零。所有多字节小端。与曲谱上传run_id无关，是本手机播放轮次的隔离令牌；新会话重置历史。

开启：登记token、清该token拍点counter历史，进入外部逐拍模式。不同token的新开启替换旧token；同一可靠请求重复只回放ACK，不重新清counter。若同token用新SEQ再次开启，作为显式重新开启处理。本次App每次开启递增token，0跳过。开始ACK OK后才允许手机发拍点。

停止：token必须匹配当前token；无活动token可幂等成功，旧token不得停止新token。停止后清待发click及click包络并使旧token失效，不恢复旧拍点。控制请求有效会话；失败沿用BAD_LENGTH=2、OUT_OF_RANGE=3、INVALID_STATE=5、UNSUPPORTED=7、BAD_SESSION=9。错误detail为字段起始偏移或现有状态原因。

外部模式与自由节拍必须互斥：START压制独立beat_acc，不让BPM设置变化产生额外click；STOP后保持节拍静音。下一次显式写0x50参数才重新选择原自由节拍启停。用独立运行门控实现，不改变持久/参数仓库revision；0x46 ACK revision仅报告当前值，不递增。切页不等于停止播放，不能单凭UI销毁关闭外部节拍。

0x47载荷：

| offset | 字段 | 类型 | 约束 |
|---|---|---|---|
| 0 | run_token | u32 | 当前有效外部模式token |
| 4 | beat_counter | u16 | 独立递增，首帧任意 |
| 6 | beat_index | u8 | 0..beats-1 |
| 7 | beats | u8 | 1..12 |
| 8 | unit | u8 | 2/4/8/16 |
| 9 | accent | u8 | 0普通、1强拍；本App小节第0拍为1 |

每帧完整校验通过后触发一次既有click合成器。counter用u16差值1..32767判断新帧，重复/旧counter静默丢弃且不续租。新token清counter历史；有效拍点独立续租1000ms。租约到期只清当前click与外部触发许可，不自动恢复自由节拍；下一有效同token新counter可重新起音，直到STOP/会话失效撤销token。该规则允许极慢拍间隔超过1秒，同时避免无限尾音。不得把心跳、参数查询当作拍点，不得对0x47进入可靠请求缓存。

PANIC、音频不可用、会话失效优先，清外部token、click与待触发状态。PANIC解除不得恢复旧token；如需继续由用户恢复播放并新START。按原实时错误限流报告非法命令，成功无ACK；手机实时错误不得造成ACK风暴。0x46开启可在音频不可用时INVALID_STATE，停止必须仍可执行。

### 23.3 手机调度与生命周期

拍点在MIDI拍号段起点开始，间隔tick=resolution*4/unit，重音每beats拍循环；MIDI tempo表将tick映射成秒，播放倍率只作用于同一播放时钟。拍号切换开启新段首拍。只在曲谱真实拍点触发，不把每个音符当作一拍。

播放中开启：异步可靠START，不阻塞音符循环；ACK前跨过的拍点不追补。关闭：异步STOP。暂停、换曲、跳转、播放自然结束、紧急静音：取消旧调度，并提交STOP；恢复播放使用新token。AB回跳将拍点游标重建到A，不重置小节编号，A不在拍点上时等待区间内下一拍，不在A凭空加一个强拍。B采用右开边界，B上的拍点不属于本轮循环。

手机每5ms左右检查统一时间线；若调度落后，超过80ms现实时间的拍点丢弃，不连发补拍。TX队列最多保留一个尚未发送的0x47，新拍覆盖旧拍；与音符同实时优先级，不能截断应用帧。0x46入队清未发送0x47；STOP前已交给模块的旧帧按序排空，FPGA还须校验token/counter。新START成功之前不发新token拍点。

无bit27不发送0x46/47，不回退成“看似同步”的独立BPM；App按钮禁用。演示模式只同步视觉，没有FPGA声响。旧控制台自由节拍器继续使用0x20参数接口，用户显式开启自由节拍应撤销外部模式。

### 23.4 示例与验收

START token=1 payload：`01 01 00 00 00`；4/4首拍counter=0：`01 00 00 00 00 00 00 04 04 01`；次拍counter=1：`01 00 00 00 01 00 01 04 04 00`；STOP：`00 01 00 00 00`。

验收：默认4/4、3/4与6/8；变速点与播放倍率0.5/1/2；中途开启不补拍；暂停恢复无旧click；AB起点在拍点及非拍点；B拍点不重复；重复counter与旧token无声；PANIC后旧token不复活；参数BPM变化不额外click；旧固件无新命令；蓝牙拥塞丢旧拍不连发。需量测音符与click到达差及抖动，本次未实板验收。
