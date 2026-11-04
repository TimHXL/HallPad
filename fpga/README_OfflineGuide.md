> 本次最新灯带与协议入口以README_Drum80.md为准；下文保留SD脱机操作。

# KeyboardPercussion_OfflineGuide

基于DrumControl完整工程：增加协议第21节鼓棒自定义RGB，以及第一步“SD卡脱机LED跟随指引”。保留手动校准、左右击打灯效、双音源0 dB、TimingOpt3和跟随长音规则。

## 马上使用

1. 准备已格式化为FAT32、512字节扇区的SDHC卡（常见4–32GB卡）。将 **sd_card目录里的SCALE.HPG** 复制到SD卡根目录。不是复制外层目录，也不是复制ZIP。
2. 关机插卡；Gowin打开KeyboardPercussion.gprj，保持keyboard_top顶层与50 MHz约束，综合、布局布线，检查时序后烧录。本包是源码，没有预编译位流。
3. 设备设置菜单旋转到新增第10项 `LOCAL SD / OPEN`，短按进入本地曲目页。
4. 旋转选曲（显示8字符短文件名），短按加载。READY后再短按开始，经过原有3秒倒计时后按LED指引演奏。
5. 运行中短按暂停，暂停后短按继续；长按停止并回曲目列表，再长按退出。加载中长按取消；错误页短按重回列表。

不需要手机、蓝牙连接或心跳。播放使用已加载的RAM曲谱；本地拥有曲谱期间，手机的0x60–0x67练习命令返回INVALID_STATE，防止覆盖；其他设备设置仍可使用。进入/离开本地模式会切换共享曲谱RAM所有权，旧手机上传曲谱不会保留。

## 指引规则

沿用现有跟随判定器、速度100%：短音击中后推进；长音命中保持黄灯，按足时长才绿灯；提前松开计未完成并进入下一组；错键红灯。原有按键释放重武装、倒计时和曲谱时间到达条件保留。等待当前音时必须在提示到时且松键重武装后再按。

**本阶段实现跟随练习与LED指引，不包含脱机自动示范发声、蓝牙写SD卡、目录/删除的手机接口。** 卡由电脑复制文件，设备只读，不会改写或格式化用户卡。

## 新曲谱怎么放进去

使用系统Python 3，无第三方依赖。在工程目录运行：

```
python tools/midi_to_hpg.py song.mid STAR.HPG --title "MY SONG"
python tools/midi_to_hpg.py song.mid STAR.HPG --track 1 --transpose -12
```

--track为从0开始的MIDI轨号，可重复；不指定时合并所有旋律轨，排除MIDI通道10打击乐。支持格式0/1、PPQ和变速事件，不支持SMPTE或格式2。起音同毫秒合并和弦，和弦采用最短持续时间，跨下一起音的延音截断到下一组，适配单组跟随。不会偷偷丢弃不可映射的半音/超范围音；遇到这些音会报错，需选轨、移调或提供正确映射。

也支持显式物理键JSON：

```
python tools/midi_to_hpg.py tools/example_score.json TEST.HPG --title "KEY TEST"
```

生成后的HPG复制到卡根目录即可。文件名必须大写8.3，例如STAR.HPG、SONG0001.HPG；本版最多显示32首，仅扫描根目录。显示文件名，不显示32字节标题。长文件名、子目录和exFAT不支持。

默认映射由当前FPGA的KEY_NOTE_MAP/自然音转换生成，见tools/default_mapping.json；它按**内部sensor编号**排列，不等同UI左到右排序。当前C4 MIDI60对应sensor20。自定义键位时，用--mapping-json传入真实35键midi/enable配置，否则设备会拒绝绑定不一致的曲谱。全局音色、主音量变更不影响绑定。

单曲1..4096组、最长24小时，最大98368字节。完整加载后检查曲谱CRC、每条记录与键位绑定，再允许READY；文件损坏不会进入可演奏状态。

## 支持的卡格式与硬件

只读FAT32：512字节逻辑扇区，单扇区至128扇区的2次幂簇；支持无分区FAT32（superfloppy）或MBR第一个分区为0x0B/0x0C FAT32。支持FAT链碎片化的根目录和文件、1/2份FAT与BPB选择活动FAT。不支持GPT、exFAT、FAT16、SDSC字节寻址；SDXC如为exFAT需另备FAT32卡。本版没有热插拔恢复：上电前插好卡，读卡硬件错误后重启重试。

沿用已工作的HP SD-SPI接线：MISO AA15、MOSI Y16、CLK V15、CS_N W15。初始化约200kHz，数据约5MHz。沿用已存在的logger_sd_spi，但写请求恒为0。SD卡缺失/出错不阻塞键盘和鼓棒演奏。

鼓棒物理左DRUM1：SDA D20、SCL C20、PLG F15、RGB F19；物理右DRUM0：SDA C18、SCL C19、PLG E19、RGB D19；BLE TX E17、RX F16。PLG低有效。

## 鼓棒自定义RGB

0x7D设置4字节mode/R/G/B，0x7E查询、0x7F回复，CAPS bit24置1。原六字节0x7A–0x7C不变。默认循环色；mode1固定用户RGB，但依旧击打才亮。活动像素即时换色，不重启包络；自定义模式不推进循环序号，切回恢复各像素保留的组色。

## 验证范围

verification包含实际RTL测试台、测试用稀疏FAT32扇区镜像和转换工具测试。RESULTS.md列出最终结果。测试扇区模型替代物理SD卡，不能证明卡的电气、真实SPI读取或最终布局布线时序。

未执行新版Gowin综合/布局布线及实板验收。上次基线50MHz尚有时序违例，此包也不能宣称已收敛。共享原曲谱RAM，额外只增加扇区缓存、目录元数据与控制逻辑；最终资源以Gowin报告为准。
