# Phase 0：实施计划与验收门槛

日期：2026-09-28。当前范围严格限定 Phase 0；四份文档完成后停止，等待用户确认。GitHub版本管理属于本次已授权的交付工作，不代表获准开始 Phase 1。

## 1. 本轮交付与工程基线

- [paper_architecture.md](paper_architecture.md)：完整论文阅读、图1/2/4/5/6、公式修正、论文/本板差异。
- [hardware_mapping.md](hardware_mapping.md)：7页原理图、ADC角色、四MUX映射、XDC/工程调查与NEED_CONFIRMATION清单。
- [system_architecture.md](system_architecture.md)：时钟/CDC、完整帧、FFT/CORDIC、定序/吞吐、PS/TCP合同。
- 本文：分阶段产物、验证、入口条件与停止点。

当前 `vivado_bia/` 作为旧数字工程源代码基线保存，不宣称已经满足本轮目标。版本控制纳入RTL、testbench、Tcl、Python、C、ROM初始化文件和约束模板；排除build/.Xil、日志、缓存、临时渲染。外部 ADDA 和两份原始PDF位置见硬件文档；本次不把外部文件路径伪装为仓库内可重建依赖，也不把论文全文加入公开仓库。

GitHub目标：`https://github.com/keilachance79-hue/ZYNQ_BIS`。Projects看板 `https://github.com/users/keilachance79-hue/projects/2` 与Repository不是同一对象。是否关联看板不影响Git提交。

### 输入版本指纹（SHA-256）

| 文件 | SHA-256 |
|---|---|
| 最终原理图 PDF | `f84056431783daae3d6c8379f8d25e1034e5cddd987aa8851bc16ee733bf6de9` |
| 用户提供论文 PDF | `a1a944412b5f5683df0f31415ae83bf12054379380abaceaaf389622a5c1394d` |
| BIS/ADDA.xpr | `d6ce3d624eb884fac568d9deb13dec838e0fe204b01ae68f9d2a68612ecaa104` |
| EXT/ADDA.xdc | `1cc34491f58913716e8cf382c63d0a96da9aee8910a53ebbe1084f8e1e4be3b5` |
| EXT/da_send.V | `0565b44e998f64eb46220ba9afd477376d9eb41722e7be993fe4b31bb088e3a3` |
| EXT/hs_adda.v | `31df7f03a9f03f46a0aa8f032e851825929964a0c766bc0ee0ecabdb18c8eb6d` |
| EXT/PLL.v | `969bae792c3685fe612ac0dbc67d0d369f33838e891174ad8533be7e1eedfef1` |

Git管理的源代码由commit锁定，外部依赖仍须在后续获准迁移时收集成相对路径工程，包含COE和XCI；仅有上表不代表可在另一台机器直接重建ADDA。

## 2. Phase 0 验证与限制

本轮执行：论文12页文本阅读、重点图和公式视觉核对；原理图7页视觉检查、关键区域高倍核对；实际XPR/外部RTL/XDC/XCI、工作区RTL/PS示例/构建脚本调查；查阅原厂datasheet；核算频点、FFT相位公式、扫描计数与吞吐预算；文档相对链接和未修改现有源文件的hash核对。

本轮没有运行硬件仿真、综合、实现、Vitis交叉编译或板上测量，因为只新增分析文档，没有新RTL可验证。不能将已有日志/bitstream当作这次验证通过。后续每阶段必须先完成该阶段仿真/软件测试并记录结果，再进入下一阶段；上板验收另标状态。

实际执行的Phase0检查全部通过：Python枚举E=4/8/16/32得到4/40/208/928；numpy对bin113、五组正负初相验证`2|X|/N`及`φ-π/2`，误差小于1e-12；四角色DB→address表均为0..31置换；四份Markdown的相对链接、代码围栏、Unicode文本检查通过；现有源目录文件hash与审阅前一致。映射置换检查只证明表格内部一致，不能替代EDA/导通验证；这些检查也不是后续可综合FFT/CORDIC的验收。

阶段状态：Phase0文档分析完成待用户审阅；Phase1–6全部未开始。重要硬件未确认项不是通过的验收项。

## 3. Phase 1：只做多正弦ROM与LTC1668

入口：用户确认本次文档；桌面仿真可先行，真实pin/时钟输出实现须H01；涉及ADC时钟同时输出须H02。保留旧工程基线，新目标独立目录/顶层，避免覆盖旧可复查输入。

产物：`generate_multisine.py`、配置/phase/CF报告、浮点与量化reference、`waveform.hex/.coe`、2048×16bit ROM、player、LTC1668接口、时钟模块、关键TB和可重建Tcl。

验收：

1. 恰好2048个16-bit码；合法范围、无削顶；九目标bin与共轭bin，均幅误差与非目标量化杂散单独统计。
2. 固定种子相位优化，可重现；与全零相位baseline比较CF，保存相位和hash，不能只使用一个固定相位公式便声称已最小化。
3. 样点0..2047循环，首点/末点/ROM延迟/复位/锁定测试；连续至少三个周期逐码对比reference，不能出现旧ADDA的2049状态。
4. 输出data/DACCLK以LTC1668正沿建立/保持检查，加入板级预算；时钟IP报告实际10.24MHz，不以`FS_HZ`字段替代。
5. 综合与板级时序报告通过后再上板；示波器/频谱测得频率、周期、削顶情况，记录实际模拟电压及滤波路径。

本阶段不加入ADC扫描或FFT；完成并测试后提交阶段记录。

## 4. Phase 2：固定电极，双AD9269采集

入口：Phase1测试完成；H02–H04/H07/H10核实；准备真实PS平台/BSP或明确的调试传输路径。固定电极也必须基于已确认DB接线，不假定E1映射。

产物：双DCO source-synchronous接收、offset-binary转换、样本对齐、2048对帧缓存、raw调试DMA/PS导出、reference FFT脚本。

TB模型包括转换时钟→ADC流水→两路不同DCO/数据延迟，随机复位和CDC时序，不只在同一理想边沿喂两总线。用通道特有计数码验证不交换/不漏点/不重排；已知同一模拟波形对比通道skew。器件没有可控SPI时，不能把“打开ADC测试码”作为已可执行步骤。

验收：窗口首点为确定epoch，随后连续2048组；offset-binary的0x0000/0x8000/0xffff分别转-32768/0/32767；FIFO溢出、缺一DCO、反压、失锁均报错整帧无效；PS原始数据与reference样本一致，并检查V/I相位关系。完成时序/CDC报告及同源双路台架测试。

## 5. Phase 3：FFT及九bin

入口：Phase2采集准确且通道对齐已验证。产物：2048FFT IP XCI/Tcl、wrapper、bin selector、V/I标签/描述符传递、golden测试集。

测试：单频已知幅相、九频率、纯DC、全零、近满幅、随机合法输入；取九bin逐一核对实部/虚部，而不是只比较幅度。加入输入/输出backpressure、TLAST异常、连续多帧、V/I串行核复用；自然序或索引解码明确，复数打包/补码/大小端无歧义。

误差准则：同一输入与IP bit-accurate模型逐位一致；对浮点参考按选定系数量化/舍入给出明确绝对/相对容差，再批准。不能凭空要求所有定点结果与numpy逐位相等。无IP精确模型时必须说明验证缺口并建立保守数值界限。正常输出只包含九bin，不发送全FFT谱。

## 6. Phase 4：CORDIC

入口：Phase3通过。产物：CORDIC配置与wrapper、幅度归一化、相位单位说明、浮点与定点对照报告。

验收：轴点、四象限、±π换向、零输入相位无效、近满幅；FFT缩放和CORDIC增益只补偿一次；正弦φ经FFT为φ-π/2，若展示正弦初相再加π/2；同相V/I的Zphase=0。幅值峰值/RMS标识明确，误差预算包括输入截位，结果含溢出/无效标志。

## 7. Phase 5：四MUX与流水扫描

入口：H05/H06/H07/H08关闭；可控使能策略与真实板一致。产物：单一映射数据源生成 `electrode_map.h/.sv`、`docs/electrode_map.md`；参数化扫描表、ADG732控制、settle参数、measurement sequencer、缓存队列和TB。

验收：逐角色验证32项映射是0..31的一一置换，连接器导通实验确认物理E顺序；E=4/8/16/32时计数分别4/40/208/928，每条记录两对不重合、包含环绕；非法/未映射电极配置拒绝。

示波器/逻辑分析仪核对各片地址和实际可用EN，在最坏跳变下测稳定。扫描TB随机插入FFT/DMA反压，证明没有旧帧被新配置覆盖、没有满bank写入；在 `FFT(n)`进行时已开始`MUX/SETTLE(n+1)`。每采集帧连续N点且从批准的周期边界起始，溢出显式处理。测得吞吐与400μs/组预算比较，而非要求复现论文20FPS。

## 8. Phase 6：PS复阻抗、校准、Ethernet/TCP和PC

入口：Phase5通过，H09平台参数齐备。产物：可编译Vitis项目/BSP配置、DMA管理、每频点复校准、R/RC验证、版本化网络协议、TCP服务与PC解析/可视化。

验收：已知复数向量（包含极小I、四象限）与Python除法对比；标准R应相位近0，RC趋势正确，误差按校准方案规定；板级电流/电压单位和极性确定。协议测试包含粘包/分包、部分发送、超时、重连、重复/缺失帧；满928组合完整scan_id组帧，长时间网络拥塞不得静默破坏采样。

EIT图像重建需另有几何模型、Jacobian和参考帧；测到九频率V/I或Z不等于已完成并验证成像。可在Phase6测量/传输稳定后明确重建范围。

## 9. 每阶段保存的证据

每阶段commit记录输入配置/hash、工具版本、TB通过/失败、定点误差、综合资源、时序/CDC、板上验证状态和遗留项。仿真通过、实现通过、上板通过分开列；阶段失败不能跳过进入下一阶段。优先保存重建脚本/源文件，不以生成缓存代替工程。

**当前停止点：完成Phase0文档与GitHub提交后等待用户确认，不开始生成波形或修改RTL。**
