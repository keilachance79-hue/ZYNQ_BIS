# Phase2 数字原型验证记录

日期 2026-09-28，Vivado 2020.2，xc7z020clg400-2，Python 3.12.14 / NumPy 2.3.5。输入指纹与本次运行状态见 [digital_result.json](digital_result.json)。

## 状态

| 项目 | 本次结果 |
|---|---|
| 双 DCO、FIFO、配对、帧缓存行为仿真 | PASS，10 类场景 |
| 逐码与 raw 文件解析对照 | PASS，4 帧 / 8192 对样点 |
| Python 九频 FFT 对照 | PASS，已知幅比/相差 |
| 可综合性与 OOC 资源 | PASS |
| 理想 TB 时钟/输入延迟下的综合时序 | PASS，仅模型约束 |
| 板级时钟/CDC、布局布线、bitstream | NOT_SIGNED_OFF / NOT_RUN |
| 实际 PS/DMA、同源双路台架采样 | NOT_RUN |

## 自检查覆盖

1. 未确认 `alignment_verified` 时拒绝请求。
2. 顺序填满两个完整 bank，继续输入不会覆盖，随后随机反压排空。
3. 九频 V/I 已知信号采集与相位验证。
4. B 路 DCO 停止，使活动帧超时作废。
5. B 路丢失一个 DCO 沿，后续标签不一致/不连续使帧作废。
6. 活动帧中时钟资格撤销。
7. 活动帧中对齐资格撤销。
8. 停止 DSP 消费而 DCO 继续，触发 FIFO 溢出。
9. 请求已经错过的起点，报错而不偷偷更换 epoch。
10. 帧中复位后恢复，丢弃未完成帧，从新会话重新采集。

模型由 10.24 MHz 转换时基驱动，经 9 周期流水产生 A/B 数据。A 数据在转换沿后 4 ns、B 在 11 ns 更新；三组 DCO 相位分别为 A=20/27/34 ns、B=51/56/61 ns，测试三种复位释放相位。100 MHz DSP 域与两个 DCO 域通过真实 XPM FIFO 通信。随机反压采用固定种子的 LFSR，可复现。模型没有模拟 ADC 模拟噪声、真实板延迟或亚稳态。

通过帧 ID 为 10、11、20、81，所有索引为 0..2047，无交换/丢点/重复。ID、起点、校准 ID 在请求时锁存；故意改变下一请求配置不会改写当前帧描述符。输出反压时同时检查 data、valid、last、index 和全部描述符保持稳定。数值边界检查覆盖 `0x0000/0x8000/0xffff` 的 signed 转换。

XPM 使用默认关闭的可选内部仿真断言配置 `SIM_ASSERT_CHK=0`；本 TB 在接口和帧层检查完整性、溢出故障、反压稳定性及恢复。此配置不构成供应商内部断言集全部通过的声明。

## Raw 导出和参考 FFT

每帧导出 8192 字节，按小端 signed int16 的 V/I 交错排列，并回读逐码比较。四个文件的 hash 和描述符见 [capture_check.json](capture_check.json)，完整 CSV 和二进制载荷可由脚本重建于 `build/`。

九频模型的 V/I 幅比设为 2、相差设为 +0.3 rad。量化后最大幅比误差 **5.7471338e-5**，最大相差误差 **1.7994045e-5 rad**，均低于 0.001 的阈值。公开的 `analyze_raw.py` 也对同一文件运行并检查结果。该比值只有 ADC code 单位，没有模拟增益/电流标定，不能报告为阻抗 Ω。

## 综合、CDC 与警告

[资源报告](utilization_synth.rpt)：682 LUT、1095 FF、6 RAMB36E1、0 DSP，其中 4 个 BRAM 支撑 16 KiB 帧缓存，其余为异步 FIFO 等存储。报告对应独立数字子模块，未集成 PS7、ADC 时钟驱动或 Phase1 DAC 顶层。

[综合时序](timing_synth.rpt)：WNS=2.843 ns、WHS=0.157 ns、TNS=THS=0。no_clock=0，未约束内部终点=0。ADC 输入延迟以模型的 conversion clock 为参考，不把负的 DCO 相对延迟错误套到保持检查上。外部控制/调试端口没有真实板级延迟；四个 OOC 时钟尚无实际 HD.CLK_SRC。不能把该结果视为板上 100 MHz 时序签核。

[CDC 明细](cdc_synth.rpt) 保留 2 组 CDC-6 灰码多位同步器警告和 32 项 ADC 外部输入对应的 CDC-26 警告。后者在此报告中位于 `adc_a/b → input_code` 路径，使用独立 primary clock 的理想输入模型；不能因规则名称提到 LUTRAM 就认定 FPGA 内部双口 RAM 有已证实故障，也不能直接屏蔽后宣称 CDC 安全。必须在真实板 wrapper 中建立源同步时序关系，结合 DCO 路由和实测采样窗口复核。灰码组另有 datapath/max-skew 约束，见 [bus_skew_synth.rpt](bus_skew_synth.rpt)，物理实现后还需再次验证。

[DRC](drc_synth.rpt) 有 32 项 PLIO-6：OOC 没有实际 I/O buffer，输入寄存器的 `IOB=TRUE` 无法在该上下文落实；以及 1 项 ZPS7-1：未集成 PS7。这些警告已归档，没有设置 waiver 或关闭时钟专用路由检查。

Vivado 数据库确认 U18 为 MRCC、W8/U8 为非 MRCC/SRCC 的普通 I/O 功能，见 [package_pins.txt](package_pins.txt)。结合两份原理图后的硬件结论见 [hardware_review.md](../docs/hardware_review.md)。

## 尚未完成的 Phase2 验收

需要确定并实现合法 ADC 时钟驱动及 DCO 接收方案，关闭 RBIAS/总线接线疑点，建立实际 DAC 周期与 ADC 转换 epoch 的校准关系，完成板级实现/CDC/时序、实际 raw PS/DMA 调试传输和同源输入测量。当前提交完成 Phase2 原型的可复现数字验证，不标记整个 Phase2 验收完成，也不开始 Phase3。
