# ZYNQ_BIS

基于最终版底板的多正弦 EIT/EIS 分阶段实现。已确认 FPGA 为 `xc7z020clg400-2`，参考时钟为 50 MHz。

| 目录 | 内容与状态 |
|---|---|
| [Phase0](Phase0/) | Phase 0 完整受控快照：四份分析文档、旧数字工程和忽略规则；保留原状 |
| [Phase1](Phase1/README.md) | 新的九频多正弦 ROM、LTC1668 播放链路；数字仿真和独立模块综合已通过，上板验收待完成 |
| [docs](docs/) | 原 Phase 0 分析文档，正文中的停止点是当时的历史状态 |
| [vivado_bia](vivado_bia/) | 旧工程基线，供追溯；当前 Phase 1 使用独立顶层 |

Phase0 对应备份前提交 `a5c6849d159503506c4ebb02e5c9f66cbb4abb88` 的全部 34 个受 Git 管理文件，归档提交为 `4a38fe63658977b7bd10e2b806bf1fce64664a73`。外部原始 PDF、ADDA 工程和本机构建缓存的范围见 [输入清单](Phase0/docs/implementation_plan.md)，这些外部文件不在该快照内。

Phase 1 的可重建入口、结果和限制见 [Phase1/README.md](Phase1/README.md)。实际封装引脚、Bank VCCO、参考时钟引脚及板级时序预算尚未确认，因此当前没有可直接下载的板级 bitstream。Phase 2 尚未开始。
