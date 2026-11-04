> 此为上一阶段说明。本次请优先阅读README_OfflineGuide.md；已加入SD卡与鼓棒RGB驱动。

# KP 新线序修改说明

基于 KeyboardPercussion(20261031-024140)。

|功能|引脚|
|---|---|
|FPGA蓝牙TX|E17|
|FPGA蓝牙RX|F16|
|右SDA/SCL/PLG/RGB|C18 / C19 / E19 / D19|
|左SDA/SCL/PLG/RGB|D20 / C20 / F15 / F19|

物理DRUM0为右棒，DRUM1为左棒；保留SWAP_STICKS=1，对外编号0左、1右。PLG为上拉输入，低电平已插入，双级同步并经5次1ms采样确认。
STATUS.state_flags bit12=左棒已插入、bit13=右棒已插入（1表示插入）；bit8/9仍为左/右在线，bit10/11仍为左/右校准完成。旧App若按原始PLG电平解码，需要同步调整。未新增校准中或校准命令。
两路RGB输出固定低电平，不发送WS2812数据。插入状态不门控I2C通信。

实际修改文件：src/keyboard_top.v、src/KeyboardPercussion.cst。保留其他功能与MPU驱动。请重新综合、布局布线并烧录新的位流。

验证：全CST无重复引脚；10路映射、端口、左右顺序与插入极性静态检查通过。当前环境无Gowin/iverilog/verilator，未完成综合、时序和实板验证，不能保证此前掉线问题已解决。
