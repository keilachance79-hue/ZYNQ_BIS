# Phase4：九频点 V/I 幅度与相位

2026-10-08：用户授权启动。数字 CORDIC 模块、位精确仿真和 100 MHz 内部 OOC 综合已通过，详见 [验证记录](verification/phase4_report.md)。[Phase3 遗留问题](../Phase3/open_issues.md)和[硬件问题](../docs/hardware_blockers.md)仍需单独验收；Phase5 尚未开始。

## 数据路径

```text
Phase3: nine signed28 complex V/I bins + frame descriptor
  -> complete nine-record frame buffer and protocol checks
  -> V then I, one word-serial CORDIC reused across nine bins
  -> inverse normalization, peak amplitude, canonical phase, validity flags
  -> nine results: original complex + polar + original descriptor
```

固定九 bin：2、3、7、11、19、37、61、113、199。FPGA 为 `xc7z020clg400-2`。`clk` 是待系统提供的 100 MHz 数字处理时钟；已确认的 50 MHz 板上参考时钟需要后续顶层生成该时钟。本阶段没有新增板级引脚或 ADC 时钟驱动。

采用 Vivado 2020.2 的 Xilinx CORDIC 6.0 revision 16，Translate、Word_Serial、Coarse_Rotation、SignedFraction、Radians、32 位输入/输出、Nearest_Even，内部精度与迭代次数 Auto，LUT_based 增益补偿，Blocking AXIS + TREADY。IP 内部已补偿 CORDIC 增益，外部不再次乘除增益常数。

## 数值合同

Phase3 的 FFT 为正向、N=2048、unscaled；实部和虚部都是 signed28 符号扩展到 signed32。对每个非零合法向量 `(x,y)`，令：

```text
s = 28 - floor(log2(max(abs(x), abs(y))))  // 1..28
CORDIC input = (x << s, y << s)            // signed Q2.30
G = compensated magnitude output code     // Q2.30
A = 2|X|/2048 = |X|/1024                  // peak amplitude, ADC codes
A_q14 = G * 2^(4-s)                       // unsigned Q18.14
theta_q29 = arg(X) * 2^29                 // signed radians Q3.29
```

归一化只有左移，保留输入全部有效位；最大分量位于 [0.25,0.5)，向量长度小于 0.708，避免 CORDIC 中间量越界。取绝对值/最大值、求移位数、实际移位分开三个周期，满足内部 100 MHz 目标。

幅度末级右移按最近值舍入，半 LSB 向上；左移不舍入。这与 IP 内部 Nearest_Even 是两个不同位置的舍入。幅度为单边正频点**峰值**，不是 RMS，也没有换算伏特/安培。该 `2/N` 仅适用于当前九个正频点，不能直接用于 DC 或 Nyquist。

相位规范为 `[-π,π)`，负实轴固定为 `-π`，纯虚轴固定为 `±π/2`，零向量相位填 0 并标记无效。对 `A*sin(2πkn/N+phi)`，输出 `arg(X[k])=wrap(phi-π/2)`；要展示正弦初相才加 `π/2`。V/I 的相差直接相减并 wrap，共同偏移抵消。本模块保留原始 FFT 相位，不额外加偏移，也没有实现 Z=V/I。

## 接口

输入沿用 Phase3 的 128 位结果、valid/ready、slot/bin/last、frame_id/start/calibration。每帧必须按 slot 0..8 输入；所有旁带在握手时采样。输出 `m_data` 为 256 位：

| 位段 | 内容 |
|---|---|
| [31:0], [63:32] | 原始 V 实部、虚部，signed32 |
| [95:64], [127:96] | 原始 I 实部、虚部，signed32 |
| [159:128] | V 峰值幅度，unsigned32 Q18.14 |
| [191:160] | V 相位，signed32 Q3.29 rad |
| [223:192] | I 峰值幅度，unsigned32 Q18.14 |
| [255:224] | I 相位，signed32 Q3.29 rad |

输出描述符原样保留，`m_slot/m_bin/m_last` 与输入顺序一致。`m_flags[3:0]` 属于 V，`[7:4]` 属于 I；每个 nibble 的含义：

| bit | 含义 |
|---|---|
| 0 | 非零且范围合法，相位在数学上有效；不代表已达到 SNR/电流阈值 |
| 1 | 输入未正确符号扩展 signed28；幅度和相位均填 0，跳过 IP |
| 2 | 幅度溢出；饱和为 `0xffffffff` |
| 3 | 零向量；幅度、相位填 0，相位无效，跳过 IP |

当前合法输入最大幅度约 185,364 个 ADC 码，低于 Q18.14 的 262,144 上限，因此幅度溢出分支在现有输入合同下不可达；保留该保护位，不声称已通过注入覆盖。弱信号/低电流的实际可靠性阈值由后续测量与标定决定。

模块先收齐九条并计算全部 V/I，再开始发布。计算和结果未排空时 `s_ready=0`，上游必须遵守反压；`m_valid && !m_ready` 时载荷与旁带稳定，可无限停顿。模块只容纳一个工作帧，不保证整条扫描链持续吞吐。

`fault` 为粘滞故障：bit0=输入 slot/bin/TLAST/描述符不一致，bit1=活动处理无进展超时（默认 100,000 周期）。故障阻塞后续输入且不发布当前帧，需要全局复位。输入首条之前、正常输出反压不计超时；单通道 signed28 范围错误用 `m_flags` 报告，不将整帧判为协议故障。

`reset_n` 在 `clk` 运行时保持低至少 20 周期，同时复位 IP。复位丢弃工作与未排空结果；若已经开始输出，下游应把该会话的部分帧作废。

## 重建

Windows、Vivado 2020.2、64 位 Python + NumPy，在仓库根目录执行：

```powershell
./Phase4/scripts/run_phase4.ps1 -Python python -Vivado 'D:\Application\Xilinx\Vivado\2020.2\bin\vivado.bat'
```

脚本自动选择空闲盘符处理中文路径，并在退出时移除自己创建的映射；同一阶段不要并发构建。输入来自已受控的 `Phase3/verification/nine_bins.csv`，不要求保留先前 build 缓存。每次重新生成供应商位精确参考、IP、HDL 仿真、OOC 综合并导出证据；失败返回错误。

供应商 C 模型来自本机 Vivado 的 `cordic_v6_0_bitacc_cmodel_nt64.zip`，仅提取 DLL 到忽略目录。该 C API 接收/返回用 double 承载的**原始定点整数码**。GitHub 保存重建脚本、模型/输入指纹、精简结果，不分发供应商 DLL 或生成 IP。模型配置和 IP 配置由导出脚本交叉核对。

定义依据：[AMD/Xilinx PG105 CORDIC 6.0](https://www.amd.com/content/dam/xilinx/support/documents/ip_documentation/cordic/v6_0/pg105-cordic.pdf)。本阶段对 Phase3 CSV 作离线 HDL 重放；Phase2→Phase3→Phase4 在线 RTL 集成、实际时钟与模拟链路验证仍待完成。
