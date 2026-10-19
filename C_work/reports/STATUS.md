# E203 与 A/B 集成验证记录

验证日期：2026-10-19，Asia/Shanghai。

**公开E203参考SoC集成已通过本地功能验证。** 真实E203执行RISC-V固件，配置C的寄存器，
启动B的 `linear_accel_a_top`，通过A的正式 `compute_lane` 完成计算，将结果写回共享SRAM，
随后由CPU逐项读取输出计算校验和。测试平台经装载口独立读取并比对每项输出。

## 实际执行范围

| 测试 | 范围 | 结果 |
|---|---|---|
| C接口单测 | 16位高低半字、邻接保护、两拍40位偏置、命令等待、响应反压、边界/对齐/范围/读写方向错误、物理读写错误、寄存器保护、启动脉冲、粘滞状态/IRQ、未取响应时复位 | PASS |
| 真实E203完整矩阵 | 第0层，99×64乘64×256加偏置，输出99×256 | 25,344项逐位一致，CPU校验和394a81b5 |
| 真实E203十二层切换 | 第0至11层，每层选取3行和5列，维度3×64×5，连续执行、任务间不复位 | 180项逐位一致，每层CPU校验和匹配 |

真实输入和参数来自 `A_work/artifacts/real_12_layers`。每次运行先核对交接包的格式、二进制
长度、SHA-256、小端解码与整数期望；数据来源校验值保存到相应摘要。
层号2采用shift=17，其余冻结层采用16；驱动配置来自元数据，硬件不按层号硬编码。
所有SoC测试的共享SRAM响应额外等待1拍。

完整矩阵的B内部调试周期为5,343,132；本地输入/参数装载开始至最后写回确认的窗口为
5,426,840拍。两者定义不同。后者包含本参考平台装载、总线等待与CPU调度，仍不作为
组委会统一吞吐量成绩。CPU输出校验和和测试平台逐项结果比对在该窗口之后完成。

## 固定来源与证据

- 上游：`https://github.com/riscv-mcu/e203_hbirdv2.git`
- 固定提交：`9f3e34f337f5d0a1236a285871ffa2032491617a`
- A/B源码未修改；实例化A/B的正式模块，未用旧C原型替代B提交。
- `soc_full_summary.json` / `soc_full_simulation.log` / `soc_full_observed.txt`：完整矩阵证据。
- `soc_12_layers_summary.json` / `soc_12_layers_simulation.log` / `soc_12_layers_observed.txt`：十二层小规模SoC证据。
- `interfaces_summary.json` / `interfaces_simulation.log`：C接口单测证据。
- 摘要含输入及源码校验值；发布前重新核对源码未变化。`MANIFEST.sha256`核对本报告包。
- 两种SoC测试各附实际运行的RISC-V `firmware.elf`、固件编译日志和SoC编译日志。

## 复现

在C_work执行，首次先按README准备依赖：

```powershell
python scripts/run_unit.py
python scripts/run_soc.py --full --layers 0
python scripts/run_soc.py --layers 0,1,2,3,4,5,6,7,8,9,10,11
```

每次生成独立build目录；报告保存的路径对应本次运行，不要求下一次使用相同时间戳。
脚本另支持12个完整矩阵任务；本次实际SoC验证为上述一个完整矩阵加十二层小规模切换，
不能将支持运行的范围写成全部已经执行通过。

## 当前集成边界

采用上游真实 `e203_subsys_main`，保留CPU、TCM、CLINT/PLIC及原生存储/外设互连。
本地补充512KiB共享SRAM、CPU/加速器/装载口仲裁和C接口。固件从共享SRAM取指；
测试平台不直接启动加速器，也不代算乘加。

尚未取得组委会指定平台及工艺/SRAM库。本顶层是公开平台参考集成，外部AON和调试端点
未接入；加速器IRQ只导出，软件使用轮询；功能测试选用外部时钟旁路。
SRAM仍使用行为模型，未完成官方平台移植、指定ASIC综合、综合前后检查、150MHz静态时序、
2.25mm²面积或功耗/能耗验收。这些项目不能由本次功能仿真结果推定通过。
