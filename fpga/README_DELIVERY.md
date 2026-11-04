# HallPad FPGA 交付说明

本压缩包为 HallPad / KeyboardPercussion 的可交付 FPGA 工程，目标器件为 `GW5AST-LV138PG484AC1/I0`。

## 目录

- `KeyboardPercussion.gprj`：高云云源工程入口。
- `src/`：Verilog RTL、引脚约束 `KeyboardPercussion.cst` 和时序约束 `main50MHz.sdc`。
- `sd_card/`：设备运行所需的示例 HPG 文件及映射资源。
- `tools/`：MIDI/HPG 转换工具、依赖说明和字体资源。
- `font_source/`：字库源数据与许可证。
- `verification/`：可重复运行的仿真、回归测试、测试夹具及必要参考实现。
- `bitstream/KeyboardPercussion.fs`：已生成的最终下载文件。
- `docs/` 与根目录 Markdown：协议、格式和集成说明。

## 使用方式

1. 使用支持 GW5AST-138C 的高云云源软件打开 `KeyboardPercussion.gprj`。
2. 检查顶层模块和器件配置后重新综合、布局布线。
3. 如只需烧录现有版本，可使用 `bitstream/KeyboardPercussion.fs`。
4. 将 `sd_card/` 中需要的 `.HPG` 文件复制到 FAT32 SD 卡根目录。

## 清理说明

交付包不包含个人 IDE 状态、综合缓存、布局布线数据库、生成日志、差异补丁、验证截图或本机绝对路径。最终 `.fs` 单独置于 `bitstream/`，避免与源码混淆。
