# RAM结构检查

工具：Yosys 0.70（yowasp）。流程：read_verilog -sv → hierarchy -top drum_strip_rgb_ram → proc → memory_dff → memory_collect。此处没有运行memory_share，目的是核对RTL展开后的原始写口结构。

|版本|数组|位宽|同步读口|写口|
|---|---|---:|---:|---:|
|原版|lastL|24|1|2|
|原版|lastR|24|1|2|
|原版|memL|24|1|1|
|原版|memR|24|1|1|
|优化版|lastL|24|1|1|
|优化版|lastR|24|1|1|
|优化版|memL|24|1|1|
|优化版|memR|24|1|1|

两个参考数组各从2写口变成1写口，帧缓存不变。原版可由verification/drum_strip_rgb_ram_reference.v重新分析（顶层名加_reference），优化版从src读取。不能用此结果替代Gowin最终RAM映射/资源/布线报告。
