# ZYNQ7020 多正弦阻抗测量：Vivado RTL 起始工程

本工程对应讨论中的 PS/PL 分工，采用 **SystemVerilog + Vivado XPM FIFO**。默认每帧 16384 组双通道采样、8 个频点、32 位 AXI-Stream；两种模式共用一个 AXI DMA S2MM 通道。

**这是经过仿真与综合检查的数字子系统起始工程，不是已经完成板级适配的可烧录整机工程。** 核心板封装、DDR/MIO 参数、时钟输入引脚、ADC 接收边沿和模拟保护使能还需要按实物确认。不要把示例器件封装、时序占位符当成实际板参数。

## 文件入口

| 路径 | 作用 |
|---|---|
| `rtl/bia_core.sv` | PL 顶层：AXI-Lite 从接口、AXI-Stream 主接口、ADC/DAC/电极逻辑接口 |
| `rtl/bia_axil_regs.sv` | 配置影子寄存器、独立 AW/W 缓冲、波形写入与活动 Bank 保护 |
| `rtl/bia_wave_ram.sv` | 双 Bank、独立读写时钟波形 BRAM |
| `rtl/bia_acquire.sv` | 切换/稳定等待/帧采集状态机、采样 tick、DAC 播放、异常处理 |
| `rtl/bia_async_fifo.sv` | 命令、采样、帧描述符和完成应答的 XPM 异步 FIFO |
| `rtl/bia_demod.sv` | 8 路并行数字正交解调，每路 V/I 各两个分量 |
| `rtl/bia_sincos_rom.sv` | 1024 点 Q1.15 正弦/余弦参考 ROM |
| `rtl/bia_processor.sv` | 帧处理、结果快照、固定长度数据包、异常帧补零 |
| `rtl/bia_axis_fifo.sv` | 具有反压处理的输出 FIFO |
| `sim/tb_bia_core.sv` | 自检查测试平台，驱动独立时钟、AXI 乱序到达、反压和故障 |
| `scripts/create_project.tcl` | 创建 RTL 项目，默认封装仅用于验证 |
| `scripts/run_sim.tcl` / `run_full_sim.tcl` | 256 点快速测试 / 16384 点完整测试 |
| `scripts/run_synth.tcl` | 独立模块综合和资源/时序/CDC 报告 |
| `scripts/create_bd.tcl` | 自定义 IP + PS7 + DMA 的 Block Design 连接模板 |
| `sw/bia_ps_example.c` | Vitis 裸机波形写入、Simple DMA 接收、复数阻抗计算示例 |
| `scripts/decode_packet.py` | Python 解析实际 DMA 数据包；原始模式可在主机执行 DFT |
| `constraints/board_template.xdc.txt` | 待填写的板级约束说明，默认不加载 |
| `docs/verification.md` | 本次实际运行结果与未验证范围 |

## 数据流

```text
PS 多正弦计算 -> AXI-Lite 波形窗口 -> BRAM A/B -> DAC 数据
PS 测量配置 -> 影子寄存器 -> START 时锁存 -> 命令异步 FIFO -> 测量状态机

ADC V/I -> 同一采样边沿接收 -> 采样 FIFO -> 原始模式 / 八频点解调
                                          -> 快照/打包 -> 输出 FIFO
采集状态机 -> START/END 描述符 FIFO ---------^               -> AXI DMA -> PS DDR

PS -> 校验状态 -> 通道幅相校准 -> V/I 复数相除 -> 阻抗结果
```

当前版本 **一个 START 执行一帧**；下一帧在上一包完全被 DMA 数据接口接收后才能启动。重复次数和扫描表由 PS 循环下发，任务之间存在空隙。它保留流式解调、快照和波形双缓冲，但不声称支持无间隙多帧流水并发。若以后需要连续 EIT 高帧率，可在这个接口上增加任务队列、描述符环和多帧结果缓冲。

## 运行

已在本机找到 Vivado 2020.2：`D:/Application/Xilinx/Vivado/2020.2/bin/vivado.bat`。
在本目录打开终端，可执行：

```powershell
& 'D:\Application\Xilinx\Vivado\2020.2\bin\vivado.bat' -mode batch -source scripts/run_sim.tcl
& 'D:\Application\Xilinx\Vivado\2020.2\bin\vivado.bat' -mode batch -source scripts/run_full_sim.tcl
& 'D:\Application\Xilinx\Vivado\2020.2\bin\vivado.bat' -mode batch -source scripts/run_synth.tcl
```

默认 part 是 `xc7z020clg400-1`，**仅为验证选择**。知道真实 FPGA 完整料号后，给脚本添加 `-tclargs <真实料号>`。工程输出到 `build/vivado/bia.xpr`。

也可以在 Vivado Tcl Console 中切换到项目目录，然后执行 `source scripts/create_project.tcl`。

`mem/sin1024.mem` 已提供，综合和仿真会加载它，不需要生成正弦 IP。`mem/wave_example.mem` 是用于电阻/RC 模型调试的数字波形示例，不代表可施加给人体的电流幅度。可用 Python 运行 `scripts/generate_tables.py` 重新生成。

## 时钟、接收和时间戳的明确边界

1. `axi_clk`：PS FCLK/处理时钟，示例 100 MHz。
2. `meas_clk`：**经过板级时序验证的 ADC 接收时钟**，示例 10.24 MHz；输入的 `adc_v/adc_i` 必须在它的上升沿同时有效。ADC 接收、测量状态机、波形播放和 tick 在这个域中运行。
3. 外部 AD9513 分配的 DACCLK 不由本 IP 生成。DAC 数据在 `meas_clk` 下降沿推出，必须验证其与外部 DACCLK 的相位、板级延迟和 setup/hold。
4. 可使用合适相位的 DCOA 同时接收 A/B，但必须确认 B 通道也满足时序。**本 IP 没有实现两个独立 DCO 时钟域的自动样本对齐**。若板子需要分别接收 DCOA/DCOB，应先增加双接收器和样本序号对齐，再输入本 IP；不能把异步两路总线直接拼接。
5. `adc_valid` 对 AD9269 的连续输出正常应固定为 1。一次帧内出现低电平会将整帧标记为丢样，不支持不等间隔采样。
6. 64 位 `tick` 在 `meas_clk` 下连续计数，帧间不清零。第一点时间标签为该接收拍的 tick 减 `ADC_CAPTURE_DELAY`；默认 9 只是用于普通 ADC 流水线的初始参数，必须加上实际接收寄存器/边沿映射并校准。测量时基的初始零点由复位确定，不是 UTC。
7. `TIMESTAMP_CALIBRATED=0` 是默认值，所有包的状态位 4 保持为 1。只有验证板级延迟和 DAC epoch 相位映射后，才设置为 1。亚周期的时钟相位偏移需另外记录在板级校准中。
8. `wave_epoch` 是本实现假设的首个 DAC 码锁存拍：数据在前一下降沿推出，下一上升沿为参考。它不能代替外部 DACCLK 时序测量。采集从稳定等待后可重复的播放相位附近开始，**不假定第一点 ADC 数据正好等于 DAC 波形第零点的即时响应**。
9. 多频解调用共同采样窗口和同一套参考；参考序号随有效输入样本推进，不随 FIFO 等待时间推进。频点须为 `bin * fs / N`，不能直接写任意 Hz 数值。
10. 复位时两个时钟必须持续运行，复位低电平至少保持较慢时钟的 32 个周期。时钟停止/丢锁时需要板级故障/复位管理；本版本没有独立时钟失锁检测器。

原图还需要实际引出 DCO，确认 AD9269 时钟输入电平、供电/偏置、非复用并行输出配置、A/B 相位设置；QEC 不应对本来不同的 V/I 信号盲目开启。AD9513 的四电平配置和 ADC 的 SPI/绑带初始化由板级设计负责，本 IP 不包含其初始化驱动。

## 默认资源尺寸

| 对象 | 默认设置 |
|---|---|
| 波形 Bank A/B | 每 Bank 16384 x 16 位，共 64 KiB 数据 |
| 采样 FIFO | 4096 x 36 位 |
| 命令 FIFO | 16 深度，完整锁存配置 |
| 描述符 FIFO | 16 x 193 位，START/END 两条描述符/帧 |
| 输出 FIFO | 512 x 33 位，32 位数据 + TLAST |
| 解调器 | 8 频点 x 4 个 48 位累加器，32 个有符号乘法 |
| 参考波形 | 14 位相位累加器、取高 10 位查 1024 点 Q1.15 ROM |
| 结果快照 | 32 x 48 位，对外符号扩展成 64 位 |

参考 ROM 有相位/幅度量化误差，当前实现不使用插值，不能据此声称达到某个阻抗精度。精度需求更高时可增加 ROM 精度或改用高精度 DDS。实际占用以综合报告为准。

## AXI-Lite 寄存器与波形窗口

地址均为 IP 基地址的偏移，32 位访问。AW/W 可分开发送，支持配置寄存器的 WSTRB；未映射、非对齐和非法 START 返回 SLVERR。

| 偏移 | 名称 | 含义 |
|---|---|---|
| 0x00 | ID | 只读，0x31414942，ASCII BIA1 |
| 0x04 | CONTROL | 写 bit0=START；bit1=清完成状态 |
| 0x08 | STATUS | bit0=忙；bit1=完成粘滞标志 |
| 0x0C | SESSION_ID | 每次时基重置/采样率改变后使用新会话编号 |
| 0x10 | FRAME_ID | 本次帧编号，PS 递增 |
| 0x14 | CONFIG_ID | 对应频点、波形和增益/校准版本 |
| 0x18 | FS_HZ | 写入实际采样率，仅用于元数据，**不改变硬件时钟** |
| 0x1C | SETTLE | 激励恢复后的最短稳定等待采样周期数，随后还会等待播放边界 |
| 0x20 | BREAK | 断开旧电极的等待周期数，至少执行两个周期 |
| 0x24 | ELECTRODES | bit[4:0]=IP，[9:5]=IN，[14:10]=VP，[19:15]=VN，均从 0 编号 |
| 0x28 | OPTIONS | bit0=波形 Bank；bit1=原始模式；bit2=ADC 输入是 offset binary |
| 0x2C | FRAME_SAMPLES | 只读，编译参数 N；默认 16384 |
| 0x30 | LAST_STATUS | 上一帧最终状态 |
| 0x34 | LAST_ACCEPTED | 上一帧实际接收采样组数 |
| 0x38 | CAPABILITIES | 0x00010008，协议 1，8 个频点 |
| 0x40～0x5C | BIN[0:7] | 每个频点的整数 DFT bin，范围 1～N/2-1，解调模式要求互不重复 |
| 0x10000～0x1FFFF | WAVE_A | 每个 32 位地址存一个 16 位 DAC 码，使用低 16 位 |
| 0x20000～0x2FFFF | WAVE_B | 同上 |

波形窗口只写，不支持读回；低两个字节须一起写（WSTRB[1:0]=11），不支持单字节写波形。每 Bank 的 AXI 地址窗口为 64 KiB，而实际波形数据为 32 KiB。未写入的波形存储器不保证为零，启动前必须完整加载所选 Bank。

忙时可以修改影子配置和非工作波形 Bank，但不能写当前活动 Bank，也不能再次 START。活动配置在 START 时锁存，不会因修改影子寄存器而污染当前帧。

## AXI-Stream 数据协议

数据宽度 32，TKEEP 恒为 0xF，只有整个包的最后一拍 TLAST=1。所有数字按 ZYNQ 小端方式存储。数据在 TVALID=1、TREADY=0 时保持不变。

帧头 16 个 32 位字（64 字节）：

| 字索引 | 内容 |
|---|---|
| 0 | Magic=0x31414942 |
| 1 | 高 16 位版本=1；bit0=1 原始模式，0 解调模式 |
| 2、3、4 | session_id、frame_id、config_id |
| 5 | 电极映射 |
| 6、7 | t_start 低/高 32 位 |
| 8、9 | wave_epoch 低/高 32 位 |
| 10、11、12 | N、fs_hz、频点数=8 |
| 13 | 载荷字节数 |
| 14 | 参考波形小数位数=15 |
| 15 | 保留，0 |

原始载荷：每拍 `{I[15:0], V[15:0]}`，两者均已转换为有符号补码。共 N 拍。

解调载荷：按频点 k=0…7 排列，每个频点依次为 `Vre, Vim, Ire, Iim`，各为有符号 64 位、低字先传。数值为未归一化的整数乘法累加：`sum(x * cos_Q15)` 与 `-sum(x * sin_Q15)`。V/I 比值中公共缩放抵消；换算单频幅度需考虑 `N*32767/2` 和 ADC LSB/增益。

帧尾 4 个 32 位字（16 字节）：`status, accepted_count, t_end_low, t_end_high`。`t_end=t_start+N-1`。

| status 位 | 含义 |
|---|---|
| 0 | 采样 FIFO 溢出，出现丢样 |
| 1、2 | 电压/电流 ADC 过量程 |
| 3 | 外部 fault 输入触发 |
| 4 | 时间戳尚未进行板级延迟校准 |
| 6 | 帧内 adc_valid 出现空洞 |

溢出/故障/输入空洞后，仅保留此前连续前缀，剩余点补零，使 DMA 包长度固定并能正常结束。**带错误位的整帧不可用于阻抗结果，即使解调仍输出了数字。** 不允许将补零误解为有效人体响应。

默认 N=16384：原始包 **65616 字节**；解调包 **336 字节**。DMA 必须配置足够的长度字段（脚本为 23 位）并先准备接收。示例使用独占、64 字节对齐的 128 KiB 缓冲；生产软件再扩展 A/B 缓冲和明确的 DMA/CPU 所有权。

## Block Design 与 PS 软件

先创建 RTL 项目，在 Tcl Console 中执行 `source scripts/create_bd.tcl` 可封装自定义 IP 并建立 PS7/AXI Interconnect/AXI DMA 连接。该脚本默认只生成连接模板。

若已有核心板厂商的 PS 配置 Tcl，可先设置 `set BIA_PS_CONFIG <绝对路径>`。被 source 的 Tcl 可以通过变量 `$ps` 对 PS7 应用已核实的 DDR 和 MIO 配置。不要照搬不同核心板的 DDR 参数。

连接关系：

```text
PS M_AXI_GP0 -> 控制互连 -> bia_core S_AXI + DMA S_AXI_LITE
bia_core M_AXIS -> DMA S_AXIS_S2MM
DMA M_AXI_S2MM -> PS S_AXI_HP0
DMA s2mm_introut -> PS IRQ_F2P
```

`bia_core/irq` 仅表示最后一拍进入 DMA，不保证 DDR 写回完成；PS 应等待 **DMA 完成**，再做缓存维护和读数据。

`sw/bia_ps_example.c` 依赖实际硬件导出的 Vitis BSP，目前没有你的板级 BSP，因此不声称已交叉编译或上板验证。校准系数由调用者提供：`factor(f)=Rsense*HI(f)/HV(f)`，最终 `Z=factor*V/I`。不在软件中猜测采样电阻或模拟增益。

## 接板前必须完成的具体适配

- 核实 ZYNQ 完整料号、DDR/MIO、所有物理管脚和 Bank 电压。
- 核实 ADC 接收边沿与双通道时序；若不能共用一个接收时钟，补齐双 DCO 接收适配。
- 完成外部 DACCLK 关系的输入/输出延迟约束，并做实现后的 timing/CDC 检查。
- 把逻辑 `mux_en` 映射为四片开关真实的使能极性，把 `excitation_en` 接到实际可关断的模拟路径。
- `fault_in` 必须有定义电平；独立硬件限流/关断不由这份 RTL 替代。
- 用标准电阻/RC 模型验证幅相，再确定板级延迟和每频点校准系数。

## 参考

- AMD AXI DMA PG021：https://docs.amd.com/v/u/en-US/pg021_axi_dma
- AMD 7-series/XPM UG953：https://docs.amd.com/v/u/en-US/ug953-vivado-7series-libraries
- AD9269：https://www.analog.com/media/en/technical-documentation/data-sheets/ad9269.pdf
- LTC1668：https://www.analog.com/media/en/technical-documentation/data-sheets/166678f.pdf

XPM 使用本机 Vivado 自带库，工程不复制该库。Vivado 2020.2 的可选 FIFO SIM_ASSERT_CHK 包含对异步读指针同步延迟的一拍比较，实测产生错误的 SLEEP_CHECK 提示；本包装关闭这一可选断言组，并使用端到端数据、边界、反压、溢出恢复和故障测试验证。硬件 CDC 仍由 XPM 实现及其约束负责。
