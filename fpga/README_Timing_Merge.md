# RippleKeep 时序优化合并版

基于KeyboardPercussion_RippleKeep。修改src/keyboard_menu_renderer.v与src/hallpad_sd_catalog.v；鼓棒水波逐灯保色代码保持逐字节一致。其他RTL不变。

## 菜单
原先格式化、文本长度优先编码、文字宽度计算和右对齐减法在同一拍。现在FORMAT锁存四行缓存中的文本和语言标志，VALUE_LENGTH计算并寄存长度，VALUE_POSITION计算右对齐坐标。每行多2拍，每次四行增加8拍，50MHz下160ns。不影响LCD像素握手或音频路径。

## SD
合并之前SD_Timing中的FAT32几何计算流水：先计算开销、数据区扇区数、簇数量，再校验和生成地址，挂载多6拍约120ns。

## 原报告
上传基线布局布线Fmax36.812MHz，50MHz目标，WNS -7.164ns，TNS -3891.615ns，2987个setup违规端点，hold违规0。最差25条前19条为菜单文字起点，后6条SD。综合7分33秒，布局布线18分钟，总约25分33秒。clk_d普通布线警告仍需后续检查。

## 验证范围
菜单修改前后四行文本/语言/对齐坐标对照；SD使用与已通过离线集成测试完全相同的RTL；水波保色RTL完全未改，沿用已通过测试结果。工程不包含新Gowin编译结果，实际Fmax、资源及耗时需重新综合布局布线确认。未增加屏幕评分或修改鼓棒I2C。
