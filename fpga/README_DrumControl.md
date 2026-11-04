> 此为上一阶段说明。本次请优先阅读README_OfflineGuide.md；已加入SD卡与鼓棒RGB驱动。

# KeyboardPercussion_DrumControl

基于 KeyboardPercussion_FollowHold（包含TimingOpt3鼓点流水线）增加鼓棒手动校准与独立灯效。

## 打开及烧录

Gowin打开 `KeyboardPercussion.gprj`，顶层保持 `keyboard_top`；主时钟50 MHz。工程包含全部77个工程引用文件，不需要SD卡新增文件。不要将鼓棒子模块设置为综合顶层。运行综合、布局布线并检查布线后的50 MHz建立/保持时序，再生成及烧录位流。本包为源码，未包含预编译位流。

## 新功能

- 上电不校准；首次进入设备鼓棒页、两棒插入且在线稳定100 ms后自动尝试一次。页面切换不重复校准。
- 鼓棒页旋钮顺序选到第7项 `RECAL / PRESS`，短按启动两棒重校准；校准中忽略本地重复点击。
- 手机可通过0x77手动重校准、0x78/79查询精确状态；10秒超时、掉线后停止，不自动重试。
- 真实/模拟鼓点被合成器接受后，对应左右灯换色。音色NONE、力度0不亮灯。两棒共享独立八色循环，20 ms固定和弦窗口共色。与键盘预设色表不重复。
- 手机0x7A设置独立灯效：开启、亮度0..100%、亮起时间1..1000 ms、衰减0..5000 ms（0保持）；0x7B/7C读回。默认开、10%、40 ms、1200 ms。
- 无手机连接时，自动校准、菜单重校准、击打灯光仍可工作。手机App需要按新协议另行接入，本包不包含安卓代码。

保留新版接线、双音源0 dB、鼓棒参数范围、NONE、TimingOpt3与跟随长音行为。此版未新增其他时序优化，不表示上次36.625 MHz报告已达到50 MHz。

## 接线

| 功能 | 左棒 DRUM1 | 右棒 DRUM0 |
|---|---|---|
| SDA | D20 | C18 |
| SCL | C20 | C19 |
| PLG，低有效 | F15 | E19 |
| 单像素WS2812数据 | F19 | D19 |

BLE TX E17、RX F16；本次未改CST及SDC。每路按一个WS2812像素发送，复用keyboard_rgb_chain的GRB与复位时序。

## 协议

完整文档 `HallPad_Bluetooth_Protocol_Updated.md`，新功能在第20节。新增CAPS bit22/23，保留bit19鼓棒、bit21直接MIDI各自含义。0x79仅查询回复，手机校准中建议每200 ms使用新SEQ查询。灯效参数易失、不修改键盘config_revision。

键盘自由自定义RGB仍可人为选中鼓棒颜色，“不重复”针对两套固定预设色表，熄灭及亮度/衰减后的瞬时RGB不属于色表限制。

## 验证与限制

- 全部RTL经过pyslang语法/展开比较，无新增错误；基线遗留18条MissingTimeScale与1条audio_engine_top的UsedBeforeDeclared仍存在。
- Verilator实际RTL仿真覆盖首次进入、再次进入、拔插、故障、超时中止、菜单共用请求入口的手动重试；覆盖共色窗口、亮起/衰减、常亮、0亮度及关闭。
- 协议仿真覆盖HELLO、0x77控制/重复包/忙/非法参数、0x78状态及0x7A设置/非法参数/0x7B读回。结果见verification/RESULTS.md。
- 未运行Gowin综合、布局布线或实板测试；不能由RTL仿真宣称资源、时序及3米I2C链路已验收。

verification中提供SV测试台及运行脚本，不参与Gowin综合。
