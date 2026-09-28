# Phase 1：多正弦 ROM 与 LTC1668

本阶段实现九频激励的数字输出链路，数字仿真和独立模块（OOC）综合通过。上板实现和模拟输出测量尚未进行，完整验收状态见 [验证记录](verification/phase1_report.md)。

## 配置与生成结果

唯一参数入口是 [config.json](config.json)。当前 `xc7z020clg400-2`、50 MHz 参考时钟由用户确认；MMCM 用 50 MHz × 16 / 78.125 生成 10.24 MHz，VCO 为 800 MHz。2048 点 ROM 每 200 μs 重复一次，频率间隔为 5 kHz。

| bin | 频率 / kHz |
|---|---|
| 2, 3, 7, 11, 19, 37, 61, 113, 199 | 10, 15, 35, 55, 95, 185, 305, 565, 995 |

`generate_multisine.py` 固定随机种子，使用时域限幅投影与频域固定幅值迭代来搜索相位。限幅只用于优化过程；最终九正弦叠加按幅度缩放后量化，输出不削顶。算法不宣称求得全局最优，也不宣称复现论文未公开的原始 LUT。32 倍密集采样网格检查的峰均比为 2.515710，全零相位对照为 3.041173。

LTC1668 使用 16 位 straight binary，数字中心为 `0x8000`，导出码范围 6554–58962。`headroom=0.8` 表示密集网格峰值相对于 32767 的比例，不是输出电流或电压标定。实际激励幅值需结合 DAC 参考电流、模拟增益、负载与滤波路径实测。

## 文件与接口

- `generated/`：`waveform.hex/.coe`、逐点浮点/量化 `reference.csv`、相位/峰均比/hash 报告、RTL 参数头和参考时钟约束。
- `rtl/dac/`：2048×16 同步 BRAM ROM、参数化循环地址播放器、LTC1668 接口。
- `rtl/clock/`：真实 MMCM/BUFG 时钟与锁定后复位释放。
- `rtl/top/phase1_dac_top.sv`：独立顶层；输入 `ref_clk/reset_n`，输出 `dac_data[15:0]/dac_clk` 和调试标签。
- `sim/`：非二次幂 17 点播放器测试，以及真实 UNISIM MMCM/ODDR 的全链路测试。
- `scripts/`：波形生成、独立对照、工程重建、仿真、综合和证据导出。
- `verification/`：本次结果、源文件 SHA-256、Vivado 综合报告；完整仿真采样 CSV 可在 `build/reports/` 重建。

每个采样时钟正沿读取 ROM，随后负沿寄存 DAC 数据，下一正沿由 LTC1668 锁存。`sample_valid`、`sample_index`、`period_start` 在该锁存正沿后更新，表示本次锁存样点；`period_start` 标记索引 0，每 2048 个有效样点一次。下游同步逻辑须按寄存器延迟消费这些标签，不应当作提前一个边沿的采样使能。

外部复位或 MMCM 失锁立即中止有效输出，接口回到 `0x8000`；MMCM 重新锁定后，复位经过四个采样正沿释放，播放从索引 0 重启。BRAM 地址同步复位，接口异步中止。单独使用 `dac_player` 时，复位必须覆盖至少一个采样正沿。异步中止时不保证 DAC 建立/保持时间，也不保证模拟端立即归零；有效输出期间才检查接口时序。DACCLK 由 ODDR 转发，未使用 LUT 门控。

## 重建与检查

需要 Vivado 2020.2（含 XSim/UNISIM）及带 NumPy 的 Python 3。测试版本见 [digital_result.json](verification/digital_result.json)。从仓库根目录运行 PowerShell：

```powershell
./Phase1/scripts/run_phase1.ps1 -Vivado 'D:\Application\Xilinx\Vivado\2020.2\bin\vivado.bat' -Python 'python'
```

若 `python` 是 Windows 商店别名，请传入实际 `python.exe` 路径。脚本按顺序生成、复现检查、仿真、逐码比较、综合、导出证据，失败即停止。Vivado 2020.2 在本机中文路径综合时出现内部 `TclStackFree` 崩溃；脚本自动借用空闲盘符建立临时英文路径，结束后撤销别名，源目录不移动。请勿在同一目录并发执行构建。

也可在 Phase1 目录逐步运行：

```powershell
python scripts/generate_multisine.py
python scripts/check_waveform.py --reproduce
vivado -mode batch -source scripts/run_sim.tcl
python scripts/check_waveform.py --capture build/reports/dac_capture.csv --reproduce --report verification/waveform_check.json
vivado -mode batch -source scripts/run_synth.tcl -log build_synth.log
python scripts/export_verification.py
```

修改 Fs、长度、频点时必须重新生成；Fs 与 MMCM 参数不一致会报错。任意新 MMCM 参数仍须经 Vivado 合法性和时序检查。相位搜索结果可能受 NumPy 版本影响，`--reproduce` 会逐字节检查本环境重建的一致性。提交中的波形与 hash 是本次固定基线。

## 板级验收剩余项

`constraints/phase1_ooc.xdc` 仅给 DAC 数据设置器件侧建立 8 ns、保持 4 ns 的输出预算，尚未加入板上走线偏斜、时钟抖动等余量。没有虚构封装球位、IOSTANDARD 或 Bank 电压。

需先取得核心板原理图/准确 XDC，确认参考时钟及 DAC 数据/时钟的 PACKAGE_PIN、Bank VCCO、复位来源、时钟与数据传播预算，并完成 Zynq PS7 集成、实现后的时序及 DRC。随后用示波器/频谱验证 200 μs 周期、九频点、模拟幅值和削顶情况。综合报告中的 ZPS7-1 是独立 PL 模块未集成 PS7 的警告，不能作为完整 Zynq 工程忽略。

本阶段未实现 ADC、MUX 扫描、FFT/CORDIC、PS 传输或成像。Phase 2 仍需另行启动，并满足 Phase 0 记录的硬件入口条件。
