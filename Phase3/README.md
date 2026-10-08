# Phase3：2048 点 FFT 与九频点复数结果

> 2026-10-08 交接：[仍存在的问题与关闭条件](open_issues.md)已记录。用户授权启动 [Phase4 CORDIC](../Phase4/README.md)，不改变本阶段板级未验收状态。

本阶段在用户 2026-10-08 授权后启动，先完成数字处理模块。**[硬件重点问题](../docs/hardware_blockers.md)保持 OPEN；Phase2 实物采集、对齐、PS/DMA 和整板验收尚未完成。**本阶段不包含 CORDIC、阻抗标定、MUX 扫描或可下载 bitstream。

## 数据路径与数值定义

```text
Phase2 raw frame (2048 V/I pairs + descriptor)
  -> complete-frame RAM and protocol checks
  -> V samples -> one FFT IP -> 9 complex V bins
  -> I samples -> same FFT IP -> 9 complex I bins
  -> 9 paired complex results + original descriptor
```

Xilinx `xfft:9.1`，Vivado 2020.2，xc7z020clg400-2；固定 N=2048，pipelined streaming，非实时 AXIS，自然序并启用 XK_INDEX，正向 FFT，输入实部 signed16、虚部 0，旋转系数 24 位、convergent rounding、unscaled。每个输出实部/虚部有效位数为 `16+11+1=28`，分别占 32 位字节对齐字段；wrapper 显式符号扩展至 signed32。

原始 ADC signed 整数直接作为输入位模式，等效 IP Q1.15。输出整数与未归一化 `numpy.fft.fft(int16_codes)` 对应；C 模型使用输入 `/32768`、输出 `×32768`。没有除以 N 或额外缩放，也没有幅度/相位计算。后续若计算峰值幅度，公式为 `2|X|/2048`，单位仍为 ADC code，不能直接标为 V/A/Ω。

仅输出 bin `2,3,7,11,19,37,61,113,199`，在 Fs=10.24 MHz 下为 `10,15,35,55,95,185,305,565,995 kHz`。使用实际 XK_INDEX 选频，并逐点检查自然序及 TLAST；不会仅凭输出计数假定 IP 排序正确。

## 接口合同

所有端口位于单一 `clk` 域，目标 100 MHz。`s_valid && s_ready` 接收一对样点，`s_data[15:0]=V`、`[31:16]=I`，二者均为 signed16。`s_index` 必须依次为 0..2047，`s_last` 仅在最后一对为 1。帧 ID、转换起点、校准 ID 在首拍锁存，其后每个有效传输都必须相同。可直接匹配 Phase2 的 raw stream 端口；本阶段以 Phase2 仿真导出文件重放验证，尚未做两个 RTL 顶层的在线联合仿真。

`m_valid && m_ready` 输出一条频点结果：

| 位段/端口 | 定义 |
|---|---|
| `m_data[31:0]` | V 实部，signed32 |
| `m_data[63:32]` | V 虚部，signed32 |
| `m_data[95:64]` | I 实部，signed32 |
| `m_data[127:96]` | I 虚部，signed32 |
| `m_slot` / `m_bin` | 0..8 / 对应 FFT bin |
| `m_last` | 第九条时为 1 |
| `m_frame_id/m_start/m_calibration` | 原帧描述符 |

若后续序列化，建议每条载荷为小端 `int32 Vre,Vim,Ire,Iim`，九条共 144 字节，描述符另传。本模块没有实现 DMA 或网络序列化。输出反压时数据与全部旁带保持稳定；允许无限期停在结果输出，不覆盖结果。

只有整个输入帧通过检查、V/I 两次 FFT 完整输出均通过检查后，才开始发布结果。当前仅一组工作帧 RAM，计算及结果未排空时拉低输入 ready；上游必须遵守 ready，由 Phase2 缓存保存待发数据。尚未证明整条扫描链达到论文吞吐量，不能把上游停发误解为 ADC 停采样。

`fault` 粘滞位：bit0=输入索引/TLAST/描述符错误，bit1=FFT TLAST 事件，bit2=FFT 输出索引/TLAST/九 bin 数错误，bit3=活动处理无进展超时（默认 1,000,000 周期）。错误后不发布当前帧，必须整体复位恢复。FFT 输入/输出 halt 事件在合法反压下可以出现，不当作损坏数据。输入开始前及输出反压不计超时。

`reset_n` 同时复位 wrapper 和 FFT IP，应在 clk 运行时保持低至少 20 周期。复位会丢弃未完成工作及未排空结果；下游应按会话中断处理已经收到的部分结果。

## 重建

Windows、Vivado 2020.2、64 位 Python + NumPy。先运行 Phase2 重建流程，提供其 `build/reports/raw_capture.csv`，再在仓库根目录运行：

```powershell
./Phase3/scripts/run_phase3.ps1 -Python python -Vivado 'D:\Application\Xilinx\Vivado\2020.2\bin\vivado.bat'
```

脚本使用空闲盘符处理中文路径；同一阶段不要并发运行构建。IP 由 Tcl 固定配置生成，XCI 位于 build 内。位精确模型来自本机 Vivado 安装中的 `xfft_v9_1_bitacc_cmodel_nt64.zip`，仅临时提取 DLL 到忽略目录；不向 GitHub 分发供应商 DLL/头文件。

## 验证标准

仿真对 19 组 V/I 帧的全部 2048 点复数输出逐位比较供应商 C 模型，再核对九 bin、V/I 顺序与描述符。包含零、正负极限 DC、九个单频幅相、Phase1 多正弦、满范围随机、脉冲、Nyquist 极限交替，以及 Phase2 的四帧真实仿真导出。另测提前/缺失 TLAST、索引错误、描述符变化、断流超时、输入/FFT 运算中复位、连续多帧和输出反压。

浮点比较以复数绝对误差为准，预算 4096 个未缩放 FFT 输出整数码，折算峰值幅度误差上界为 4 个 ADC code；这是测试验收预算，不是所有输入的形式化误差证明。近零频点不使用相对误差，防止除零；大信号可按 `4096/|X_ref|` 换算保守相对界。位精确模型比较要求零误差，不以这个浮点容差掩盖位级不一致。

证据见 [验证记录](verification/phase3_report.md)。综合只验证数字模块资源和内部目标时钟；无板级 I/O 延迟、物理实现和实际抖动签核。

依据：[PG109 数值精度与 AXIS 定义](https://www.amd.com/content/dam/xilinx/support/documents/ip_documentation/xfft/v9_1/pg109-xfft.pdf)。本机 IP 与 C 模型版本由重建脚本及证据指纹锁定。
