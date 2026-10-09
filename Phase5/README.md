# Phase5：ADG732 地址控制与自动相邻扫描

2026-10-09。实现四路 MUX 地址更新、电极映射、参数化 adjacent 扫描、settling 等待、采集调度及异常处理。用户确认 **E1→DB1，依次至 E32→DB32**。数字验证已通过；硬件未决项见 [本阶段问题清单](docs/open_issues.md)，Phase6 尚未开始。

## 映射与扫描

[电极映射表](docs/electrode_map.md)逐一列出 E→DB→四片 ADG732 S/address；[配置证据](config/electrode_map.json)保存 PCB 网络记录行号与源文件指纹。四片不能共用 `address=E-1`。当前 EDA 中 I− 的 A0/A1 为 B35_L23P/B35_L23N，与历史 PDF 整理表相反，已明确标记。

从同一 JSON 生成 [C 表](generated/electrode_map.h)、[SV 表](generated/electrode_map.sv)及文档。`electrode_to_db` 必须是 1..32 的排列，后续线束变化应改此表并重新生成。当前实物环序按用户确认处理，PCB 铜皮、焊接和导通并未实测。

`ELECTRODE_NUM` 可设置 4..32，表示 E1..EN 组成环。I+ 从 E1..EN 遍历，I− 为下一电极；V+ 从 E1..EN 遍历，V− 为下一电极。跳过 V 的任一电极与 I 重叠的组合，保留极性，不消除互易测量。有效数量为 **N(N−3)**：4 电极 4 条、16 电极 208 条、32 电极 **928 条**；每条后续应对应九个频点，32 电极一轮共 8352 条频点记录。

扫描表 CSV 位于 generated；RTL 逐项枚举，TB 用 Python 独立生成的表核对整轮顺序、环回、地址及描述符。

## 切换与采集流程

```text
start -> select non-overlapping adjacent pair -> register four addresses
      -> settling wait -> wait for buffer and descriptor capacity
      -> request future integer-period frame -> wait for complete ADC frame
      -> switch next electrodes while the prior frame may still drain/process
```

四片 EN/WR/CS 在当前 EDA 均接地，故 RTL **只输出 20 位地址**，不虚构 disable/enable 控制脚。内部单片 break-before-make 不能代替四片全局隔离；同拍寄存地址不能消除引脚偏斜或译码瞬态。reset/stop/abort 也不会物理断开通道，停机时地址保持最后值，复位时地址为 0。

100 MHz 下 `MUX_SWITCH_WAIT_CYCLES=5000`，初始等待 **50 μs**。ADG732 +5 V 条件下 tTRANSITION 最大 48 ns（覆盖所列最高温度范围、指定 RL/CL 条件），其测量终点为 90%，不代表 16 位模拟链已经稳定。RTL 要求至少 10 周期；50 μs 是可调工程初值，必须通过完整前端、串联电容和负载的阶跃测试确定，不能沿用论文约 2 μs。依据：[ADG726/732 Rev.C，表1、图5/27、表11](https://www.analog.com/media/en/technical-documentation/data-sheets/ADG726_732.pdf)。

默认 `FRAME_SAMPLES=2048`，必须为 2 的幂；`START_LEAD_SAMPLES=4096`，用实时 conversion tag 加提前量，向上对齐到完整 DAC 周期边界。差值在有符号半范围内处理，可跨 32 位 tag 回绕；等待请求时 epoch 过期将报错。该保守提前量在 Fs=10.24 MHz 下引入约 400..600 μs，另有 50 μs settling 与 200 μs 采样；当前配置不是论文帧率验收值，需在真实时基/CDC 确认后调整预算。

当前采样结束的判据是 `capture_completed` 比请求握手时增加 1，**不是 FFT/CORDIC 输出完毕**。因此上一帧可在缓存/后级继续处理；缓存没有容量时等待，不覆盖旧帧。完整 FFT/CORDIC 与扫描在线集成仍待完成。

## 接口合同

顶层 [phase5_scan_top.sv](rtl/phase5_scan_top.sv) 的全部端口均属 `clk` 域，目标 100 MHz。以下输入需要系统集成提供：

| 输入 | 约定 |
|---|---|
| start | IDLE 中上升沿启动单轮；持续高不自动重启 |
| scan_id / calibration_id | start 接受时锁存，本轮保持 |
| system_ready | 上层确认实际时钟、epoch、映射及硬件运行资格后拉高；不是自动硬件检测 |
| latest_tag | **当前物理转换时基**经正确 CDC 后的 tag，必须有已知有界延迟；不能随意用积压 FIFO 中旧样本 tag 替代 |
| request_ready | Phase2 采集缓存可接受请求；不得等待 valid 才拉高 |
| descriptor_ready | 下游描述符队列有空间；不得等待 valid 才拉高 |
| capture_completed / capture_fault | Phase2 完整帧提交计数和粘滞故障，非 DMA 输出完成计数 |
| stop | 优雅停止：等待已发出请求完成；尚未发出请求则在安全控制状态退出，不脉冲 scan_done |
| abort_scan | 立即进入故障，要求全链会话复位 |

`request_*` 与 `descriptor_*` 是**耦合的原子预约接口，不是两条独立 AXI 流**：仅当两个消费者均 ready 才同时握手。valid 受另一侧 ready 限定，所以禁止接入等待 valid 才产生 ready 的逻辑，也不能将任一路当作独立 AXIS。REQUEST 等待时载荷稳定；故障/复位撤销未接受请求。帧缓存与描述符队列须使用同一握手事件。

输出 `request_start/id/calibration` 接采集请求；`descriptor_scan_id`、`measurement_index`、`electrodes` 与请求一起存入后续描述符队列。`electrodes` 从低至高依次为 6 位 I+、I−、V+、V−（1-based）；`mux_address` 从低至高为四片对应 5 位 A4..A0。每片低位即 A0。所有结果应按 request_id 关联，不能读取正在切换的实时端口来标记旧帧。描述符队列及与 Phase3/4 的结果合并属于待集成部分。

`request_id` 跨多轮扫描递增，复位清零；ID 回绕或复位需结合会话标识区分历史结果。`measurement_index` 每轮从 0 开始，仅描述符握手时有效；`measurements_completed` 为本轮完整采集计数。`scan_done` 单周期脉冲表示整轮采集完毕，**不表示全部 DSP/DMA 结果已输出**。

`fault` 粘滞位：bit0=参数/启动资格错误；bit1=运行中资格丢失、采集故障或 abort；bit2=ARM/REQUEST/CAPTURE 等待超时（默认 1,000,000 周期，即 10 ms）；bit3=过期 epoch 或采集完成计数异常。故障后 `acquisition_abort=1`，系统必须丢弃该会话未完成数据并共同复位控制器、缓存和描述符队列。无限下游阻塞最终触发超时，不能默认为静默漏采。

## 验证与重建

[验证报告](verification/phase5_report.md)记录完整扫描、真实 Phase2 双帧缓存联合仿真、采样数据/元信息比较和 OOC 综合。没有用仿真通过关闭模拟、电气或板级问题。

Windows、Vivado 2020.2、Python 3（仅标准库），在仓库根目录运行：

```powershell
./Phase5/scripts/run_phase5.ps1 -Python python -Vivado 'D:\Application\Xilinx\Vivado\2020.2\bin\vivado.bat'
```

脚本生成表、运行 HDL 仿真、综合、检查并导出证据；自动为中文路径分配临时盘符。Phase0..4 源码与原有验证证据保持原状。默认重建使用已审核 JSON，不依赖外部 EDA 文件；需要重新审计新硬件版本时执行：

```powershell
python Phase5/scripts/audit_mux.py 'C:/Users/Aat/Desktop/ProPrj_zynq底板_2026-10-07.epro2'
```

审计只读原件，但会重写本阶段 JSON；当前脚本记录的是本次顺序线束约定，新线束应重新审核 `electrode_to_db`。不得把新原件生成的变化未经检查直接用于旧板。没有生成可下载 bitstream 或板级引脚约束。
