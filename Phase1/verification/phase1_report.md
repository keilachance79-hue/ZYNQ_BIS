# Phase 1 数字验证记录

日期：2026-09-28。器件 `xc7z020clg400-2`，参考时钟 50 MHz，Vivado 2020.2，Python 3.12.14，NumPy 2.3.5。证据对应 [digital_result.json](digital_result.json) 中逐个源文件的 SHA-256。

| 验收部分 | 结果 |
|---|---|
| 波形生成、逐字节复现、独立正弦求和与 FFT 数值检查 | PASS |
| 参数化播放器与完整时钟/DAC 行为仿真 | PASS |
| OOC 综合、BRAM/MMCM/ODDR 推断检查 | PASS |
| 板级布局布线、完整时序/DRC、bitstream | NOT_RUN |
| 实际 LTC1668 输出与模拟链路测量 | NOT_RUN |

## 波形与数值

2048 点，16 位 straight binary，Fs=10.24 MHz。九目标频率为 10、15、35、55、95、185、305、565、995 kHz。实数波形的负频率分量为对应正频率的共轭，FFT 检查使用单边谱。

| 指标 | 实测数字结果 | 检查标准 |
|---|---|---|
| 密集网格峰均比 | 3.041173 → 2.515710，降低约 17.28% | 相对全零相位改善至少 5% |
| 输出码范围 | 6554–58962 | 全部位于 0–65535，不削顶 |
| 最大逐点量化误差 | 0.499685 code | 四舍五入量化 |
| 各频点峰值幅度最大误差 | 0.00697843 code | ≤1 code |
| 各频点相位最大误差 | 4.74497e-6 rad | <2e-4 rad |
| 非目标 bin 最大单边幅值 | 0.0377296 code | ≤1 code |

相位检查采用正弦初相与 FFT 相角的关系 `angle(X[q]) = phase_sine - π/2`，按环绕相位差比较。浮点独立正弦求和所得量化码与导出的每一码完全相同；HEX、COE 一致。固定种子重新生成的全部导出文件逐字节一致。

波形 HEX SHA-256：`bf31e1a286031a09f77f9c3cd2368f54c65c76f117dda2dd07c84f5e4cb9b317`。数值误差仅属于数字波形；不代表模拟 DAC 失真、输出电流或系统测量精度。

## 仿真

`tb_dac_player` 用 17 点非二次幂 ROM 检查显式回绕、首点、末点、同步 ROM 延迟和播放中复位；测试向量含 `0x0000/0x8000/0xffff` 等边界码。

`tb_phase1_dac` 使用真实 UNISIM MMCM、BUFG、ODDR，按 DACCLK 正沿检查实际输出码和索引。第一次播放 6167 点（超过三个周期），在周期中间异步复位，第二次播放 4103 点，总计 **10,270 点**，全部逐码一致；7 次周期首点标签正确，复位强制无效/中点码，重锁后重新从索引 0 开始。

平均时钟周期为 97.656250 ns，即 10.24 MHz。有效输出段观测到最小建立时间 49.006 ns、最小保持时间 48.650 ns；同时检查高电平 ≥6 ns、低电平 ≥8 ns。采用 1 ps 仿真精度，对长期平均周期设 100 ppm 容差以容纳仿真舍入。尚未单独注入外部晶振停振、抖动或板级延迟模型。

完整采样文件重建路径为 `build/reports/dac_capture.csv`，SHA-256：`78835aa2e74ee902d9e1860f13d62f49b267d5e18e8e9b8bd9bfbdebdea13f88`。仿真日志 PASS 行与独立采样校验汇总保存在 [digital_result.json](digital_result.json) 和 [waveform_check.json](waveform_check.json)。

## 综合与时序边界

[资源报告](utilization_synth.rpt)：22 LUT、68 FF、1 RAMB36E1、0 DSP、2 BUFG、1 MMCM、1 ODDR。HDL 综合为 0 error、0 critical warning、0 warning。

[时钟报告](clocks_synth.rpt) 确认 50 MHz 参考和 10.24 MHz 采样/转发时钟。[综合时序报告](timing_synth.rpt) 为 WNS=40.536 ns、WHS=0.037 ns、TNS/THS=0；no_clock=0，未约束内部终点=0。该结果使用综合估计，**不是板级时序收敛证明**。

剩余限制已显式保留：

- OOC 的 `ref_clk` 未设实际 `HD.CLK_SRC`，Vivado 提示不能估计完整时钟延迟/偏斜。待确定核心板引脚与布局后解决。
- 外部复位输入和 13 个调试输出没有板级输入/输出延迟；DACCLK 本身是生成时钟端口。DAC 数据的 8 ns/4 ns 器件预算已约束，走线偏斜与抖动未加入。
- [DRC](drc_synth.rpt) 仅剩 ZPS7-1：当前 OOC 顶层没有 PS7。上板工程必须完成相应集成和 DRC；未抑制该规则。原 BRAM 地址异步复位 REQP-1839 已通过同步复位修复。
- [CDC 报告](cdc_synth.rpt) 不分析没有输入延迟的外部端口；空报告不等于后续 ADC 跨时钟域已获验证。

本机中文路径曾触发 Vivado 2020.2 内部 `TclStackFree` 崩溃，临时英文盘符重跑成功；一键脚本已包含可复用的路径规避。最终从生成到证据导出的整套流程返回 `PHASE1_DIGITAL_CHECKS_PASS`。

下一步上板前必须补齐真实封装引脚、VCCO、复位与时序预算，并完成实现和仪器测量。Phase 1 的数字部分已完成；板级部分待验收，Phase 2 未开始。
