# Phase2 → Phase3 交接

2026-10-08：用户要求重点标记硬件问题，并开始下一阶段。Phase2 基线由 Git 提交 `03b42e6a1729f16bdeba7511302065bc979e879b` 锁定，可按该提交恢复完整仓库；本轮不重复复制历史快照。

已完成：数字采集原型、帧缓存及参考 FFT 验证；EDA 核对确认 32 位接口网络独立。未完成：[硬件重点问题](../../docs/hardware_blockers.md)及 Phase2 实际板级/PS 验收。

Phase3 先使用数字夹具与已验证的 Phase2 仿真帧，输入仍为 2048 对 signed int16，V 在低 16 位、I 在高 16 位，并附索引、帧 ID、转换起点及校准 ID。不能将“Phase3 数字验证通过”解释为 ADC 实物已工作。实际采集的 alignment_verified 资格门控保持原义。
