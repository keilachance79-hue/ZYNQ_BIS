# Phase 0：硬件映射与工程证据

日期：2026-09-28。原理图为 `SCH_底板3.3v_2026-09-28.pdf`，7 页全部审阅并放大核对关键接线。`CONFIRMED_PDF` 表示 PDF 可辨认，不代表 PCB/netlist 或实物已验证；`NEED_CONFIRMATION` 表示不可作为最终代码常量。

## 1. 证据来源

| 标识 | 文件/依据 |
|---|---|
| SCH | `C:/Users/Aat/Desktop/ZYNQ-BIS/SCH_底板3.3v_2026-09-28.pdf` |
| ADDA | `C:/Users/Aat/Desktop/ZYNQ-BIS/BIS/ADDA.xpr`，Vivado 2020.2 |
| EXT | `C:/Users/Aat/Desktop/verilog source/ADDA/`，包含真实引用的 RTL 与 ADDA.xdc |
| BIA | 当前工作区 `vivado_bia/`，数字子系统起始工程 |
| ADC-DS | [AD9269 Rev.B](https://www.analog.com/media/en/technical-documentation/data-sheets/ad9269.pdf)，尤其第7–12、22–25、29、36页 |
| MUX-DS | [ADG726/ADG732 Rev.C](https://www.analog.com/media/en/technical-documentation/data-sheets/ADG726_732.pdf)，+5V 参数、TQFP 引脚、Table 11 |
| DAC-DS | [LTC1666/1667/1668](https://www.analog.com/media/en/technical-documentation/data-sheets/166678f.pdf)，LTC1668 引脚与 Digital Interface |

SCH 各页依次为 PIN MAP、DAC/通信、ADC/模拟前端、POWER、MUX/DB37、CD&OTG、LCD。文件名日期不等于每页更新时间。

## 2. 已确认的 V/I 与 DAC 链路

**A=电压、B=电流（CONFIRMED_PDF）**，依据 SCH 第3页实际网络，不按 ADC 通道习惯猜测：

```text
V+/V- -> C23/C24、U26 AD8066 -> U25 AD8130 -> V_ADC
      -> U65 ADA4938-2 通道1 -> ±OUT1 -> ADC_V± -> U64 VIN±A（51/52）

I2+/I2- -> U11 AD8130 -> I_ADC -> U65 通道2
        -> ±OUT2 -> ADC_I± -> U64 VIN±B（62/61）
```

U20 电流源支路中 R49=100 Ω，I2+/I2- 为其两端；它是电流检测依据。U11/U25 标注 1 kΩ/200 Ω 反馈电阻；U65 使用 499 Ω 网络。**ADC 码比不是 Ω**，增益、极性、频响必须根据完整电路模型与已知阻抗实验得到。不要在 PS 中只乘一个未经确认的常数。

SCH 第2页 U8 为 LTC1668，DAC0..15 对应 DB0..15，DACCLK 接26脚。数据为 straight binary，寄存器输出应有统一的中心码/满量程约定。第3页 DAC± 驱动 U5/U20 AD830 电流源。

## 3. FPGA 网络层映射

以下为 SCH 第1页的核心板连接器网络名，不是封装球号；不把 B34_Lxx 直接填进 `PACKAGE_PIN`。最后一列均需由核心板原理图/正式 XDC 转成 ball，并确认 Bank VCCO。

| bit | ADC A（电压） | ADC B（电流） | DAC |
|---:|---|---|---|
| 0 | B34_L20N | B34_L1P | B35_L17P |
| 1 | B34_L24P | B34_L2P | B35_L17N |
| 2 | B34_L24N | B34_L2N | B35_L10P |
| 3 | B34_L19P | B34_L6P | B35_L10N |
| 4 | B34_L19N | B34_L6N | B35_L18P |
| 5 | B34_IO0 | B34_L20P | B35_L18N |
| 6 | B34_L23N | B34_L9N | B35_L14P |
| 7 | B34_L23P | B34_L9P | B35_L14N |
| 8 | B34_L13N | B34_L5N | B35_L7N |
| 9 | B34_L13P | B34_L5P | B35_L7P |
| 10 | B34_L14N | B34_L11N | B35_L9P |
| 11 | B34_L14P | B34_L11P | B35_L9N |
| 12 | B34_L15N | B13_L17P* | B35_L8N |
| 13 | B34_L15P | B13_L12P* | B35_L8P |
| 14 | B34_IO25 | B13_L12N* | B35_L16N |
| 15 | B34_L12N | B34_L1N* | B35_L16P |

`*` D12B..D15B 区域存在交叠连线/连接点，以上按端口标签顺序整理；是否有误连/短接必须以 EDA netlist/ERC 核实，不能仅据此生成最终 XDC。

| 信号 | SCH 第1页连接 | 说明 |
|---|---|---|
| DACCLK | B35_L5N | FPGA 输出至 DAC |
| CLK+ | B34_L3N | 正端接 N 命名网络，需处理实际极性 |
| CLK- | B34_L3P | 负端接 P 命名网络 |
| DCOA | B13_L15N | ADC 输出，供 A 数据锁存 |
| DCOB | B13_L17N | ADC 输出，供 B 数据锁存 |
| PD | B35_L3P | 第3页去 U65 两路放大器 PD，非 ADC PDWN |
| IP0..4 | B35_L19N,L19P,IO0,IO25,L11N | I+ 地址 A0..4 |
| IN0..4 | B35_L23N,L23P,L20P,L20N,L11P | I- 地址 A0..4 |
| VP0..4 | B35_L24P,L22N,L22P,L21N,L21P | V+ 地址 A0..4 |
| VN0..4 | B13_L15P,L11N,L11P,L19N,L19P | V- 地址 A0..4 |

本表同一单元格省略的 B35_/B13_ 前缀沿用该行第一个名称。页1另有使能标注，其中 B35_L2N=I-EN、B35_L13P=V+EN；B34_L20P、B34_L9N 邻近两条未清楚命名线与 ADC B 已用网络重叠。**不要把这些线自动解释为四路已接通 EN**。

## 4. 时钟、ADC 配置及板级阻断项

1. **CLK± 电气兼容性：NEED_CONFIRMATION。** SCH 未显示 FPGA 至 U64 CLK± 之间的交流耦合/电平转换。AD9269 的 DRVDD=3.3V 只说明数字输出域，CLK± 属模拟域，绝对最大值为 AVDD+0.2V；不能输出一对 0–3.3V CMOS 反相信号直接接入。须确认 VCCO、可用差分输出标准、终端/共模和核心板路径后确定 ODDR/OBUFDS/外部驱动方案。绝对最大值不是正常工作目标。
2. **RBIAS：明确文档冲突。** 第3页 R148 标 510 kΩ 接 U64 58脚到地，手册要求 10 kΩ、1%。实物/BOM/EDA 修订前，不判定 ADC 可正常工作。
3. **编码：默认 offset binary，需实测验证。** CSB 经 R147=10 kΩ 上拉 D3V3，SCLK/DFS、SDIO/DCS 未引到 FPGA；按手册内部上下拉，默认 DFS 低、DCS 使能。offset binary 转 signed 为翻转 bit15。若实物焊接/配置有变化，必须同步改变转换方式；SPI 测试码目前无可见控制路径。
4. **DCO 时序：** 默认在 DCO 上升沿锁存，ADC 普通流水延迟9转换周期，QEC 开启会变化；不能只把常数9作为总路径延迟。两通道接收寄存器、CDC 和输出模式都需计入。3.3V 数据输出可与相符 VCCO 的 CMOS 输入连接。
5. **DCO 可布线性：NEED_CONFIRMATION。** B13_L15N/L17N 是否具备适用时钟资源、跨 Bank 接收能否达到时序，需 part pin database、核心板图与实现报告确认。不得用 `CLOCK_DEDICATED_ROUTE FALSE` 掩盖未经验证的接收方案。
6. **ORA/ORB、SYNC：** 第3页只见引脚未接到 FPGA；不可宣称硬件过量程/外部同步状态已接入。可在数字层增加端码检测，但不能冒充 ORA/ORB。
7. **参考和滤波：** VREF/VCM 的去耦、ADC 驱动稳定性/带宽、DAC 页“还需后级滤波电路”均需 EDA/BOM/实测复核。第3页的小 RC 不自动等价于论文的六阶低通。
8. **公共时基：** 本 7 页未见 AD9513。旧 BIA README 的外部分配器假设不能继续当作硬件事实。底板未提供已确认的 50 MHz 参考源/球号；ADDA 的 50 MHz 只证明旧项目配置。

## 5. MUX 的真实 DB→S 映射

第5页四颗 ADG732 没有清楚可用的 U 编号，以下按 I+/I-/V+/V- 角色区分。地址位 A0..A4 位于15..19脚；源选择地址为 `S编号-1`，二进制按 A4..A0。四片均 VDD=A+5V、VSS=GND。

**逐片 PDF 读出的规律（CONFIRMED_PDF，待 netlist/导通实验交叉核对）：**

| DB 编号 d | I+ 的 S | I- 的 S | V+ 的 S | V- 的 S |
|---|---:|---:|---:|---:|
| 1..12 | d | 13-d | 13-d | 13-d |
| 13..16 | 29-d | d | d | d |
| 17..28 | d | 45-d | 45-d | d |
| 29..32 | d | d | d | d |

例如 DB1 在 I+ 为 S1/00000，在另外三片为 S12/01011；DB13 在 I+ 为 S16/01111，在其它三片为 S13/01100；DB17 在 I-/V+ 为 S28/11011，在 I+/V- 为 S17/10000。不能共用 `address=DB-1`。

第5页 DSUB1 的 DB1..DB32 分别经过各自 100 nF 串联电容到连接器 pin1..pin32；pin33..37 未连接，38/39 为外壳端。**物理电极 E1..E32、线束端和环形顺序未在图中定义**。因此 `E→DB` 全部是 NEED_CONFIRMATION；DB 编号不能冒充电极编号。

最终数据模型应为 `electrode_to_db[E]` 加 `db_to_address[role][32]`，由同一份已审核映射表生成 `electrode_map.h/.sv` 与 `docs/electrode_map.md`。Phase 0 不生成带猜测 E 编号的可执行表。

### MUX 使能与模拟范围

第5页四片 EN(22)、WR(21)、CS(20) 全接 GND。按 ADG732 真值表：EN低有效，CS/WR低使地址直接控制选择，所以板上当前是常使能的地址控制，而不是 FPGA 可断开四片。页1 EN 注释与此不一致。

因此需求中的 `MUX_DISABLE→MUX_SET→MUX_ENABLE` **不能照当前 PDF 宣称可用**；若实物确为接地，需要硬件改线或经验证的替代策略。内置 break-before-make 只保证单片内部切换，不保证四片地址同时更新时全局隔离。

另一个独立问题：MUX 供电 0/+5V，通道电压应在该供电范围；前端为 ±5V 供电并处理双极性信号，DB 串联电容也不能自动建立所需直流共模。需确认 D/S 各点实际共模和摆幅，避免把 ±5V 运放范围误当 ADG732 允许范围。

## 6. 实际 Vivado / Vitis 工程状态

### 外部 ADDA

- `.xpr` 指定 `xc7z020clg400-2`，top=`hs_ad_da`；存在绝对路径和旧目录路径，不能只保存 xpr 就视为可重建工程。
- 实际读到 EXT 中 `hs_adda.v`、`da_send.V`、`PLL.v`、`ADDA.xdc`，以及 `Desktop/verilog source/dds_2048x10b_wave.coe` 和三个 XCI。
- top 为单路10-bit ADC/10-bit DAC演示，无双16-bit、DCO、MUX、PS或FFT。`PLL.v` 是空模块且 xpr 标为 AutoDisabled。
- `da_send.V` 地址0..2048循环，共2049状态；2048深度ROM合法地址应为0..2047。top ROM线是12bit，而 IP 数据宽度10bit，地址端也存在宽度不一致；属于旧工程缺陷，本次不修。
- `clk_25m_120` 声明与 `clk_25m_deg120` 实际使用拼写不一致，后者形成隐式网络风险。
- XCI 实际输出配置为50、50、25 MHz，第三路120°；与 top 中 `clk_25m` 的注释/命名不一致。不能把它当10.24MHz实现，也不能据注释判断 ADC 时钟。
- ADDA.xdc 约束 sys_clk=20ns/U18、reset=N16；da_data[0..9]=P19,N18,T20,U20,M20,M19,N20,U19,L16,J14，da_clk=M15；ad_data[0..9]=Y18,Y19,T17,R18,V17,V18,T16,U17,Y17,Y16，ad_clk=V16、ad_otr=T15，均 LVCMOS33。没有 AD9269 双DCO及数据延迟约束。此表是旧约束记录，不是最终底板 pin assignment。
- `sim_1` top 仍为 hs_ad_da，没有独立自检查 testbench。已有 bit/dcp/log 不证明匹配新底板。

### 当前工作区 BIA

已读取所有 `rtl/*.sv`，PS C 示例、生成/解包脚本、工程/BD Tcl、约束模板及 testbench。

| 模块 | 现状 | 迁移判断 |
|---|---|---|
| bia_wave_ram | PS写入，双bank，16bit | 后期动态 LUT 可参考；第一版改用预生成ROM |
| bia_acquire | 默认2^14点；ALIGN后SEND_START；WAIT_ACK；播放受状态门控 | 非连续自主扫描，边界还受元数据反压影响，需新合同 |
| bia_demod | 八lane，正交乘累加，Q1.15 ROM，48bit和 | 不等于 FFT IP，不可只改 TONES=9 |
| bia_axil_regs / processor | 多处8硬编码，协议BIA1，单帧活动配置 | 参数与包格式需一起版本化 |
| FIFO/AXI | XPM CDC、AXI-Lite、AXIS反压 | 可审查后复用，不构成双DCO对齐 |
| create_bd.tcl | PS7＋Simple DMA S2MM＋HP0 | 未提供板级DDR/MIO配置，非可烧录整机 |
| bia_ps_example.c | 单帧DMA、波形生成、复数除法 | 无完整BSP，未交叉编译；无TCP |
| tb_bia_core.sv | AXI乱序、bank保护、raw/DFT、反压、故障等 | 仅旧数字模块验证，不覆盖目标 ADC/DAC/IP |

README 引用的 `vivado_bia/docs/verification.md` 在当前目录不存在；历史测试声称不能作为本轮重新运行的结果。工作区与 ZYNQ-BIS 目录内未找到完整 Vitis 平台/BSP/XSA/应用工程；找到了一个 C 示例与生成 BD。结论是“所给范围内缺失”，不是断言用户电脑无 Vitis 工程。

## 7. 后续必须确认的输入

| ID | NEED_CONFIRMATION 项 | 影响/关闭证据 |
|---|---|---|
| H01 | 核心板型号、完整part、Bank VCCO、球号、参考时钟 | 核心板原理图/厂商XDC；Phase1板级前 |
| H02 | CLK±驱动电平、极性、耦合/终端 | 原理图/netlist与示波器；Phase2上板前 |
| H03 | RBIAS 510kΩ vs 10kΩ | BOM/实物与修正版图；Phase2前 |
| H04 | DCO接收资源、B总线重叠接线 | netlist/ERC、实现时序、双路同信号测试 |
| H05 | E编号→线束→DB→环序 | 人工标注线束表及导通测试；Phase5前 |
| H06 | 四片EN实际接地还是可控 | netlist/实物，确定切换状态机能力 |
| H07 | MUX单电源与模拟共模/摆幅兼容 | 模拟分析与示波器验证 |
| H08 | 模拟增益、极性、滤波、稳定时间 | 标准R/RC扫频与阶跃实验 |
| H09 | PS DDR/MIO/GEM/PHY配置、Vitis工程 | 核心板工程与BSP；PS阶段前 |
| H10 | ADC默认模式及无SPI配置路径 | 上电电平/码型验证，是否需要硬件引出SPI |

这些缺项不妨碍完成 Phase 0，但会限制后续上板或自动扫描验收。
