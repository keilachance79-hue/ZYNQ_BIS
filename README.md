# ZYNQ_BIS

> **上板前重点处理：[硬件问题清单](docs/hardware_blockers.md)。CLK± 电气适配、R148=510 kΩ 选型、DCO 接收资源仍未关闭。**
>
> 2026-10-08：用户授权启动 Phase3 FFT 数字开发；Phase2 板级及 PS/DMA 验收仍待完成。交接基线见 [Phase2 → Phase3](Phase2/docs/handoff_phase3.md)。

2026-10-07：[EDA 原工程核对](Phase2/docs/eda_audit_2026-10-07.md)已确认 ADC 32 位数据的 PCB 网络独立，并确认 R148 设计值仍为 510 kΩ；ADC 时钟电气适配和 DCO 接收资源仍需解决。

基于最终版底板的多正弦 EIT/EIS 分阶段实现。已确认 FPGA 为 `xc7z020clg400-2`，参考时钟为 50 MHz。

| 目录 | 内容与状态 |
|---|---|
| [Phase0](Phase0/) | Phase 0 完整受控快照：四份分析文档、旧数字工程和忽略规则；保留原状 |
| [Phase1](Phase1/README.md) | 新的九频多正弦 ROM、LTC1668 播放链路；数字仿真和独立模块综合已通过，上板验收待完成 |
| [Phase1/snapshot](Phase1/snapshot/) | Phase1 结束时整个仓库的 103 文件快照，对应提交 `d6bee36`，归档提交 `e870efb` |
| [Phase2](Phase2/README.md) | 双 DCO 采集、完整帧缓存、raw 导出与参考 FFT 数字原型；板级及 PS/DMA 验收待完成 |
| [Phase3](Phase3/README.md) | 2048 点 FFT IP、V/I 串行复用、九 bin 提取与位精确验证 |
| [docs](docs/) | 原 Phase 0 分析文档，正文中的停止点是当时的历史状态 |
| [vivado_bia](vivado_bia/) | 旧工程基线，供追溯；当前 Phase 1 使用独立顶层 |

Phase0 对应备份前提交 `a5c6849d159503506c4ebb02e5c9f66cbb4abb88` 的全部 34 个受 Git 管理文件，归档提交为 `4a38fe63658977b7bd10e2b806bf1fce64664a73`。外部原始 PDF、ADDA 工程和本机构建缓存的范围见 [输入清单](Phase0/docs/implementation_plan.md)，这些外部文件不在该快照内。

Phase 1 的可重建入口见 [Phase1/README.md](Phase1/README.md)，其状态为当时记录。用户补充核心板图后，50 MHz/U18 与默认 Bank 电压已有图纸证据；硬件未决项见 [重点清单](docs/hardware_blockers.md)。当前没有可直接下载的板级 bitstream。Phase3 数字开发已启动，Phase4 尚未开始。
