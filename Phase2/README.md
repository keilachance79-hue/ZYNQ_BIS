# Phase2：双 ADC 采集数字原型

本阶段已启动双 DCO 接收、转换样点标签、完整 V/I 帧缓存和原始数据调试出口。当前成果是**有明确相位假设的数字原型**，不是可直接下载的整板工程。Phase1 完整备份位于 [../Phase1/snapshot](../Phase1/snapshot/)，对应提交 `d6bee3667699f73031e37c1e17bad18c71062e88` 的全部 103 个受控文件。

用户新增核心板原理图后，50 MHz/U18、默认 3.3 V Bank 电压得到图纸支持；但 DCOA/W8、DCOB/U8 非 SRCC/MRCC，ADC 时钟负端 U13 带 1 kΩ 下拉。完整接线候选、更正和未决项见 [hardware_review.md](docs/hardware_review.md)。未设置可执行的板级 PACKAGE_PIN/IOSTANDARD，未把未经验证的 DCO 走线限制放宽。

## 数据路径

2026-10-07 新增 [EDA 原工程核对](docs/eda_audit_2026-10-07.md)：32 位 ADC 数据在 PCB 网络记录中互相独立，B12–B15 的网络分配歧义已关闭；R148=510 kΩ 获器件料号支持，CLK± 直连和 DCO 资源问题仍待解决。

```text
conversion_clk -> 32-bit registered Gray timestamp
                                     |
ADC A -> DCOA input register + tag -> XPM async FIFO --+
                                                     +-> tag check -> two frame banks -> raw stream
ADC B -> DCOB input register + tag -> XPM async FIFO --+
```

A=电压，B=电流。输入按默认 offset binary 解释，翻转 bit15 得到 signed int16：`0x0000→-32768`、`0x8000→0`、`0xffff→32767`。当前不支持自动识别 Gray/two's-complement 模式，也不冒充能够通过板上 SPI 开启 ADC 测试码。

每路 FIFO 深度 256，写入 32-bit 转换样点号和 16-bit signed 数据。进入 DSP 域后先对齐首次共同标签，此后要求两路标签相同且每次递增 1。DSP 时钟目标 100 MHz，转换时钟 10.24 MHz。两个帧 bank 共 `2×2048×32bit=16KiB`，只在收齐 2048 对且无错误后提交。帧间没有空 bank 时不接受新请求，输入数据继续被检查/丢弃，不能暂停 ADC 来等待下游。

## 必须理解的 epoch 条件

两个灰码同步器只降低亚稳态传播概率，**不证明 A/B 对应同一转换时刻**。本实现采用候选方法：转换域输出寄存的 Gray tick，DCO 域两级同步，按通道 `TAG_SUB_A/B` 校正整拍关系。默认值 8 仅对应本次模型：9 周期 ADC 流水、数据输出在转换沿之后、DCO 相位落在同一转换周期内，并留有足够稳定窗口。它不是从“流水=9”直接推得的板上通用常量。

上板前必须建立 DCO 与转换时钟的稳定相位窗口，约束 Gray 总线延迟/偏斜，并用同源可识别模拟波形校准两路标签、流水和 DAC 周期原点。共同偏差一拍可能在两路标签比较中完全不可见；仿真不会模拟亚稳态。改变输出模式、时钟相位、失锁或复位后都需重新建立证据。

`alignment_verified=0` 时不接受帧请求。该输入是由经过验证的板级控制器提供的资格状态，不能为绕过验证而硬接 1。`clock_ok` 也来自板级时钟监测器，本原型不包含实际 MMCM/DCO 物理监测。TB 中显式提供这些条件。Phase1 的实际 DAC 样点 0 与 `conversion_tick` 的对应关系尚未在整板 wrapper 中建立，因此当前固定起点是模型转换 epoch，不宣称实际板上已实现整数周期 V/I 采样。

## 请求、输出与错误合同

`phase2_capture_top` 的控制/输出均在 `dsp_clk` 域；`conversion_clk`、DCOA、DCOB 是独立时钟端口。`request_valid && request_ready` 锁存 `request_start`、`request_id`、`request_calibration`。起点必须在未来，且由上层按已校准的 DAC 周期选择；等待过程中不能把过期目标自动改成后续周期。32 位计数按模 2³² 比较，请求时间距离应小于 2³¹ 个转换周期。

输出为 AXI-Stream 风格的 `m_data/m_valid/m_ready/m_last`，一拍一对数据，低 16 位 V、高 16 位 I。`m_index` 为 0..2047，`m_last` 只标最后一对；`m_frame_id/m_start/m_calibration` 为独立旁带描述符，反压期间保持稳定。没有 TKEEP 端口，接标准 AXIS/DMA wrapper 时须固定 `TKEEP=4'b1111`，并提供描述符配套存储或序列化。一次 raw 载荷为 8192 字节，小端 `int16 V, int16 I` 交错排列。

当前调试路径是 `XSim raw_capture.csv → check_capture.py → .bin → analyze_raw.py`；**没有实际 PS/DMA 数据传输**。没有使用未完成的 BSP/XSA 伪装 PS 验证通过。

`fault` 记录首次故障时的位组合，必须全局复位恢复：

| bit/mask | 含义 |
|---|---|
| 0 / 0x01 | A FIFO 溢出 |
| 1 / 0x02 | B FIFO 溢出 |
| 2 / 0x04 | A/B 标签不等 |
| 3 / 0x08 | 非连续样点/帧内序号错误 |
| 4 / 0x10 | 配对超时（默认 2048 DSP 周期，20.48 μs） |
| 5 / 0x20 | 时钟资格撤销 |
| 6 / 0x40 | 活动帧的对齐资格撤销 |
| 7 / 0x80 | 错过请求的起始 epoch |

故障使当前未完成帧作废，不向输出提交半帧；已完成帧保持原数据并可继续排空。`completed_frames`、`aborted_frames` 分别计数。外部复位会丢弃全部 bank 和输出；消费端须把复位视为会话中止，不能把已接收的半个传输与新会话拼接。

FIFO 复位由各写时钟同步，复位期间 conversion、两个 DCO 和 DSP 时钟都必须运行。推荐与 TB 一致，保持至少 80 个转换周期再释放，然后等待 `request_ready`。某 DCO 停振时必须先恢复时钟再执行完整复位，不能认为缺失时钟域已经清空。控制输入须由板级逻辑同步到指定域；本原型未提供通用异步控制端口适配。

## 重建与验证

Vivado 2020.2、Python 3.12 + NumPy 2.3.5 已测试。仓库根目录执行：

```powershell
./Phase2/scripts/run_phase2.ps1 -Python 'python' -Vivado 'D:\Application\Xilinx\Vivado\2020.2\bin\vivado.bat'
```

Python 参数可替换为实际可执行文件。中文目录下脚本使用临时英文盘符规避本机 Vivado Tcl 崩溃。不要并发在同一目录构建。该流程生成模型输入，执行仿真、逐码/二进制/FFT 验证、OOC 综合和球位数据库检查，保存证据。

分析一帧实际符合格式的 raw 文件：

```powershell
python Phase2/scripts/analyze_raw.py path/to/payload.bin --output spectrum.json
```

输出只含 ADC code 幅值、FFT 相角和未校准 V/I 码比；单位不是 Ω。默认 N=2048、Fs=10.24 MHz、九 bin 与 Phase1 一致。硬件输入并未实际测量；软件 reference FFT 不代表 Phase3 的 FPGA FFT 已实现。

详细数字结果、工具警告和剩余验证见 [verification/phase2_report.md](verification/phase2_report.md)。`digital_ooc.xdc` 中的输入延迟和时钟相位**仅描述 TB 的理想模型**，不能用于板级时序签核。

## 下一阶段入口

先解决 ADC 时钟电气接口、RBIAS、连接器实物核验、DCO 接收资源与实际 epoch 校准，再完成板级时序/CDC、PS 调试传输和同源双路台架测试。Phase2 整体验收仍未完成，Phase3 尚未开始。
