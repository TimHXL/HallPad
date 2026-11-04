# V9_SDPhone 布线资源优化

打开 KeyboardPercussion.gprj，分别运行 GowinSynthesis 和 Place & Route。工程带有原失败构建的 process_config，保留 50 MHz、布局选项 3、布线选项 2、Route Maxfan 23 和时序驱动设置。

原报告记录 1170 条未布通网络，逻辑占用 105971，BSRAM 占用 300。原报告只有全局资源统计，无法据此定位具体堵塞的网络。本轮根据源码选择以下三处进行结构优化。

- hallpad_hpg3.v 顺序移入文件头与目录项，兼容旧头部回放。目录项 128 位压缩为 98 位，保留偏移、有效长度、跳过计数、音轨号及非法字段判断。
- hallpad_offline_ctrl.v 只缓存头部所需的 24 字节，用单个标志检查保留区。键位、记录和映射 CRC 用固定移位装配，减少可变位置写入。
- hallpad_sd_catalog.v 按固定顺序移入扇区字与 FAT 目录项，保留现有曲库容量与寻址。

验证记录见 verification/RouteOpt_validation.log。实际 LUT、BSRAM 映射、布线结果和 50 MHz 时序待 Gowin 编译确认。
