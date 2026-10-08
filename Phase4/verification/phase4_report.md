# Phase4 数字验证记录

日期：2026-10-08。Vivado 2020.2 / xc7z020clg400-2，CORDIC 6.0 revision 16；Python 3.12.14。详细计数和源文件 SHA-256 见 [digital_result.json](digital_result.json)。

源文件指纹以 LF 换行归一化后计算，兼容 Windows Git autocrlf；参考模型同时保留本地 CSV 原始字节指纹和 LF 指纹。构建 fixture 的原始字节指纹对应本次 Windows 实际仿真输入。

| 项目 | 最终结果 |
|---|---|
| HDL 仿真 | PASS：41 帧，369 条 V/I 结果 |
| 原始 CORDIC 输出与官方 C 模型 | 642 次逐位一致；其余 96 个零/范围非法通道旁路 |
| 完整输出、原始复数、标志、旁带 | 369 条全部一致；CSV 再由 Python 独立核对 |
| CORDIC 幅度最大误差 | 0.000245603 ADC code；预算 0.005 |
| CORDIC 相位最大误差 | 1.929e-9 rad；预算 1e-7 |
| 已知单频峰值幅度最大误差 | 0.0164795 ADC code；预算 0.05 |
| 已知正弦初相最大误差 | 2.043e-6 rad；预算 1e-5 |
| 相同 V/I 向量的相差 | 0；验证记录索引 179、186 |
| OOC 综合 | PASS，无黑盒；2644 LUT、1644 FF、0 DSP、0 BRAM tile |
| 100 MHz 内部综合时序 | WNS +3.036 ns，TNS 0，WHS +0.158 ns |
| 整板实现 / 联合在线 RTL / PS-DMA / 台架 | NOT_RUN |

## 覆盖与误差含义

前 171 条来自 Phase3 已提交的 19 帧九 bin 结果，包含九个已知单频、Phase1 多正弦、随机/脉冲/DC/Nyquist，以及 Phase2 四帧采集仿真输出。其余向量覆盖四象限、坐标轴、零、最小非零整数、signed28 极值、±π 分支切口、每个 2 的幂附近归一化边界、越界输入及固定种子随机向量。

“CORDIC 误差”比较同一 FFT 复数整数与浮点 `hypot/atan2`；不包含 FFT、ADC 或模拟误差。“已知单频误差”使用 Phase3 量化正弦经过 FFT 后再经过本阶段 HDL 的结果，对照原始设定幅度与初相；检验了 `2/N`、CORDIC 增益和正弦初相 `+π/2` 关系。两组容差不能混用。这里没有完成实际阻抗或物理单位校准。

测试包含提前/缺失 TLAST、slot/bin 错误、描述符变化、部分输入断流超时、输入和 CORDIC 运算中复位、连续多帧、随机输入停顿、随机结果反压和固定 100 周期反压。TB 对 IP 输出 ready 另作随机强制停顿，检查 IP 的 AXIS 保持行为；产品 RTL 在 WAIT_RESULT 时持续 ready。

全部输出先在 HDL 与供应商模型加 wrapper 定点规则比较，再在 Python 中核对 CSV。异常帧在发布前拒绝；范围非法/零输入的逐通道状态及原始复数保留均已验证。未穷举内部状态位翻转、所有 IP 故障或不可达幅度溢出保护分支。

包含停顿的最大观测处理时间为 **890 周期 = 8.90 μs @ 100 MHz**，不是允许无限反压时的吞吐保证。描述符由 TB 生成，Phase3 CSV 离线重放不等于三个顶层在线联调。

## 综合与工具限制

首次综合在“读帧缓存→绝对值→最大值→移位量→左移”路径发现 WNS -1.539 ns。最终 RTL 将取最大值、求移位量、左移拆开，重新执行全部 HDL 比较与综合，得到上述最终结果。

[时序报告](timing_synth.rpt)无未约束内部端点、无无时钟寄存器；243 输入、409 输出未设板级延迟，HD.CLK_SRC 未指定，时钟分布/偏斜仍需顶层实现。IP 配置中的 ACLK_INTF.FREQ_HZ=1000000 是生成器接口元数据默认值，仿真时钟和 OOC XDC 均为 100 MHz；该字段不产生硬件时钟。

[DRC](drc_synth.rpt)保留 1 项 ZPS7-1 Warning（需要集成 PS7）。IP 属性枚举时 Vivado 另提示 generate_synth_checkpoint / is_managed 应从文件对象查询；脚本实际设置 checkpoint 时使用文件对象，未改变功能配置。最终 synth_design 为 0 errors、0 critical warnings、0 warnings；这里仍保留时序估计与 DRC 层面的限制，不称为整板签核。

原始证据：[仿真摘要](simulation_summary.txt)、[结果 CSV](polar_results.csv)、[IP 配置](cordic_config.txt)、[资源报告](utilization_synth.rpt)。[Phase3 未决项](../../Phase3/open_issues.md)和[硬件清单](../../docs/hardware_blockers.md)继续保持可追踪；Phase5 未启动。
