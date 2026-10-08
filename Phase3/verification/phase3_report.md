# Phase3 数字验证记录

2026-10-08。当前成果为独立的 FFT/九 bin 数字模块。用户已授权在硬件待办保持 OPEN 的前提下先行开发；本报告不替代 Phase2 的真实 ADC 采集、对齐、板级时序或 PS/DMA 验收。

## 已通过的检查

| 项目 | 本次结果 |
|---|---|
| FFT IP | Xilinx xfft 9.1 revision 5，2048 点、单核 V/I 串行复用 |
| 供应商位精确对照 | 19 帧 × 2 通道 × 2048 = **77,824 个复数输出逐位一致** |
| 九频点输出 | **171 组 V/I 复数结果**，实部、虚部、顺序、bin、TLAST、描述符均正确 |
| 浮点参考 | 最大复数绝对误差 **39.450769 FFT 整数码**，低于预设 4096 预算；该实测误差对应峰值幅度误差上界约 0.03853 ADC code |
| 协议与异常 | 输入间歇、FFT 输出随机反压、结果输出反压、提前/缺失 TLAST、错误索引、帧中描述符变化、输入断流超时、加载/FFT 处理中复位、连续多帧通过 |
| 综合 | 独立模块 OOC，真实 FFT 核参与综合，零黑盒、零 latch |
| 内部 100 MHz 综合时序 | WNS=**5.576 ns**，WHS=**0.166 ns**，TNS=THS=0 |
| 资源 | **3915 LUT、6622 FF、30 DSP48E1、11 BRAM Tile**（2 RAMB36E1 + 18 RAMB18E1） |

逐帧数值、模型和输入指纹、源文件指纹见 [digital_result.json](digital_result.json)，仿真完成标记见 [simulation_summary.txt](simulation_summary.txt)，选频输出见 [nine_bins.csv](nine_bins.csv)。保存的是九频点结果，完整频谱仅用于 testbench 对照。

## 测试内容与边界

19 组包括全零、极限正负 DC、九个单频（通道具有不同幅度/相位）、Phase1 多正弦及移位电流、满范围随机数据、不同位置正负脉冲、Nyquist 正负极限交替，以及 Phase2 仿真实际导出的四帧。Phase2 的样本数据原样重放，测试描述符由 TB 生成；尚未做两个 RTL 顶层在线连接的联合仿真。

供应商模型参数与实际 IP 配置核对一致：`C_NFFT_MAX=11, C_ARCH=3, C_INPUT_WIDTH=16, C_TWIDDLE_WIDTH=24, C_HAS_SCALING=0, C_HAS_BFP=0, C_HAS_ROUNDING=1`。输入除以 32768 后送 C 模型，输出乘以 32768 得到整数比较值。位级比较容差为零。浮点预算不用于放宽位精确检查，也不是对所有合法输入的形式化误差证明。

随机反压使用固定 LFSR，结果接口另有 100 周期强制反压。FFT 内部输出 ready 的随机反压由 testbench 注入，用于检查核和选择器在暂停时的行为；产品 RTL 默认持续接收 FFT 输出，并先完整保存两个通道的九频点结果。异常帧在发布前拒绝，故障粘滞并由全局复位恢复。已测输入协议故障与超时；未通过故障注入穷举所有 IP 内部事件/输出损坏分支。

19 帧中，含输入传输及随机停顿的最大完整处理时间为 **20,764 周期 = 207.64 μs @ 100 MHz**。这是本测试的最大观测值；允许下游无限反压，故不是无条件吞吐保证。单工作帧 RAM 在计算/输出时阻塞新输入，后续流水扫描需要结合 Phase2 双 bank、采样速率及实际 backpressure 做整体预算。

## 工具警告与限制

- [综合时序报告](timing_synth.rpt)中 no_clock=0、unconstrained_internal_endpoints=0；143 个输入和 278 个输出没有板级 I/O 延迟。OOC 没有实际 HD.CLK_SRC，尚不能估计真实时钟分布偏斜。上述 WNS/WHS 仅为内部综合结果。
- [DRC 报告](drc_synth.rpt)保留 **1 项 ZPS7-1 Warning**（未集成 PS7）及 **10 项 AVAL-4 Advisory**（FFT IP 内部 DSP48 未使用 D 端口的功耗优化建议）。未屏蔽这些提示。
- FFT IP 的两个 ROM 地址寄存器出现 Synth 8-6040 提示：初值限制其与 BRAM/URAM 打包，相关资源结果已计入 [资源报告](utilization_synth.rpt)。没有额外修改供应商 RTL。
- 首次综合脚本在 IP 生成后切换 checkpoint 属性，产生输出产品 stale 提示；最终脚本将该属性提前设置，并成功重新生成 IP。前后仿真/综合 wrapper 的 SHA-256 完全相同，确认未改变本次被测 IP 的逻辑配置。
- Vivado 工程的 testbench 源扫描耗时较长，最终重建流程直接使用 xvlog/xvhdl/xelab/xsim 调用安装目录中的真实 IP 仿真库。不是用软件 FFT 替代 HDL 仿真。

硬件改板候选、实际装配、电气波形、DCO 路由、转换 epoch、PS/DMA 和板级实现均保持未验收，见 [硬件重点问题](../../docs/hardware_blockers.md)。

2026-10-08 后续交接：用户已授权开始 [Phase4 CORDIC](../../Phase4/README.md)。本报告原有 Phase3 数字测试结果保持不变，[未决问题](../open_issues.md)继续跟踪。
