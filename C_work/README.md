# C：E203 SoC 与 A/B 前馈线性加速器集成

本目录把公开 Hummingbirdv2 E203 的 **真实 CPU 和原生 SoC 主系统**与
`../B_work/rtl/linear_accel_a_top.sv` 连接，后者调用 `../A_work` 的正式运算 RTL。
A/B 源码保持原样。所有新代码、依赖、构建结果和验证资料均放在 C_work。

这是公开 E203 平台的可复现集成基线。尚未收到组委会平台工程，因此不能将它称为
“组委会指定平台已经验收”。指定工艺综合、官方 SRAM 宏替换和功耗评估另外进行。

## 结构与源码

```text
参数装载口（测试平台只搬运编码数据）─────────────┐
                                             ↓
E203 原生 SoC 主系统 ── sysmem ICB ── 三方仲裁 ── 512 KiB共享SRAM
       │                                     ↑
       └─ sysper ICB → C寄存器 → B矩阵调度 → C访存适配
                                   │
                              A compute_lane
```

| 文件 | 责任 |
|---|---|
| `rtl/e203_ffn_soc.sv` | 集成顶层，实例化上游 `e203_subsys_main`、C外设与共享SRAM |
| `rtl/ffn_soc_peripheral.sv` | C寄存器、B正式顶层、C访存适配的连接 |
| `rtl/accel_csr.sv` | ICB寄存器、配置锁、启动脉冲、粘滞done/error与可选IRQ输出 |
| `rtl/shared_mem_adapter.sv` | B张量元素请求转换为物理32位ICB事务、半字打包和40位偏置读取 |
| `rtl/icb_shared_sram.sv` | CPU/加速器/装载口公平仲裁及共享SRAM行为后端 |
| `sw/ffn_driver.c`、`sw/main.c` | 真正运行于E203的MMIO驱动和连续任务示例 |
| `tb/tb_e203_ffn_soc.sv` | 经装载口加载固件和真实数据，由CPU启动，逐项检查SRAM输出 |
| `tb/tb_c_interfaces.sv` | C接口单测：打包、等待、反压、错误、配置锁、状态和复位 |

上游版本和工具下载校验见 `dependencies.json`。E203 为 Apache-2.0；上游授权原文位于
`vendor/e203_hbirdv2/LICENSE`。依赖使用本地独立checkout，不修改上游源码。

## Windows复现

依赖：Python 3、Icarus Verilog（接口单测），以及 WSL 的 Ubuntu-24.04、Python 3、
Perl、GNU Make、支持C++20的G++。本机使用WSL的G++13。Zig只作RISC-V交叉编译器。

在本目录执行：

```powershell
python scripts/setup_deps.py --compiler --verilator --direct
python scripts/run_unit.py
python scripts/run_soc.py
python scripts/run_soc.py --full --layers 0,1,2,3,4,5,6,7,8,9,10,11
```

也可以使用PowerShell入口：`./Run-C-Tests.ps1` 跑接口单测和默认SoC小规模测试，
`./Run-C-Tests.ps1 -Full -Layers 0` 跑接口单测和第0层完整矩阵。
`./Run-C-Tests.ps1 -Full` 会执行全部12个完整矩阵任务，耗时更长。
本次实际完成的验证范围与日志索引见 `reports/STATUS.md`、`reports/VERIFICATION.json`；
脚本支持的范围和本次已经执行的范围分别记录。

`--direct` 仅让本次依赖下载绕过代理，不改系统/Git全局代理配置。
默认SoC测试从真实矩阵选取第0/49/98行、第0/1/127/254/255列，依次执行第0/2/11层。
完整模式固定为99×64×256，所有任务依次运行，中间不复位E203和加速器。
`--sram-wait N` 控制共享SRAM响应等待；默认1拍。`--wsl-distro NAME` 可指定已准备好的WSL环境。

每次运行创建独立 `build/soc_时间/`，保存RISC-V ELF、固件、输入、编译日志、仿真日志、
完整实际输出和含SHA-256的摘要。`build/latest_soc.json` 指向最近一次运行结果。
成功标记为 `E203_SOC_ALL_PASS`，接口单测为 `C_INTERFACES_PASS`。

完整SoC回归使用Verilator。Icarus入口仅保留用于调试；目前只对C接口单测验证了Icarus运行。
上游SVA在不支持其语法的工具中用上游提供的`DISABLE_SV_ASSERTION`禁用，C自检仍运行。

## 地址与格式

CSR映射在上游实际支持的SysPer区域 `0x11000000`；共享SRAM位于SysMem区域
`0xA0000000..0xA007FFFF`。这两个地址由本公开参考平台分配，移植官方平台时应统一调整。

| 区域 | 起始地址 | 正式尺寸与布局 |
|---|---|---|
| X | `0xA0000000` | 99×64，有符号16位，每元素2字节，行优先 |
| W | `0xA0004000` | 64×256，有符号16位，每元素2字节，行优先 |
| b | `0xA000C000` | 256，有符号40位符号扩展到8字节容器 |
| Y | `0xA0010000` | 99×256，有符号16位，每元素2字节，行优先 |
| 示例邮箱 | `0xA0060000` | CPU与参数装载测试平台握手 |
| 固件/栈 | `0xA0070000..0xA007FFFF` | ELF装入共享SRAM，由E203原生访存路径取指 |

所有容器均小端。X/W读取对齐32位字，再按半字位置取16位；Y使用0011/1100字节使能，
不覆盖邻接结果。偏置读取两个32位字，仅取低40位原始编码交给B。逐层shift来自A的
`formats.json`，不沿用旧C原型的Q8.8、16位偏置或内部数据窗口。

| CSR偏移 | 名称 | 访问与语义 |
|---|---|---|
| 0x00 | CONTROL | 写bit0启动一次；bit1清done/error；其他非零位报总线错误 |
| 0x04 | STATUS | 只读bit0 busy、bit1粘滞done、bit2粘滞error、bit3 start_ready |
| 0x08 / 0x0C | LAYER / SHIFT | 空闲可写，分别0..11 / 0..63 |
| 0x10/14/18/1C | X/W/B/Y_BASE | 空闲可写，物理字节基址 |
| 0x20 | OUTPUTS | 已成功收到写回确认的输出数量 |
| 0x24 | CYCLES | B内部任务周期，仅调试用途 |
| 0x28 | ERROR_CODE | 粘滞错误码，含义沿用B接口说明 |
| 0x2C | VERSION | 0x00010000 |
| 0x30 | IRQ_ENABLE | bit0启用顶层accel_irq输出；示例使用轮询 |

CSR只接受对齐32位访问，写mask必须1111。非法访问返回ICB错误且不修改配置。
busy、启动交接和完成交接阶段均锁住配置；重复START报总线错误。
B的单拍done/error由C锁存。done只能在全部Y写回响应成功之后出现。

访存适配器检查张量边界、地址对齐、SRAM范围和合法读写方向；一次逻辑请求对应一次响应。
偏置由两次物理读取组成，任一次错误都终止当前请求。命令/响应在反压期间保持。
驱动超时不等于硬件中止；恢复应复位整个总线与加速器，不能只重启CPU留下旧事务。
`core_hold`仅用于启动时暂缓CPU、装入固件，不作为运行中任务中止接口。

## 验证和验收边界

SoC测试平台不发START、不访问加速器CSR、不计算矩阵结果，只经装载口提供固件和
A已冻结的输入/权重/偏置。真实E203执行驱动、配置寄存器、轮询，并读取所有输出计算校验和。
测试平台独立经共享SRAM总线逐项比较A的期望输出，并核对CPU校验和。

本地`window_cycles`从输入/参数开始装载，到B收到全部写回确认结束，包含本平台装载口、
总线等待和CPU调度，不包含后续测试平台结果比对。它只是本公开平台的功能仿真记录，
不能代替组委会平台、指定库、活动覆盖和同配置条件下的正式吞吐/功耗成绩。

公开SoC主系统中的CPU、TCM、CLINT/PLIC和原生存储/外设互连保持原样。外部AON和调试端点
未集成到此顶层；IRQ仅导出，示例不走PLIC中断。功能仿真显式选择外部时钟旁路，
采用约150MHz测试时钟，尚未完成PLL/时钟树或工艺时序验收。
内部B SRAM和本地共享SRAM仍为行为模型。官方SRAM宏、150MHz静态时序、2.25mm²预算、
综合前后功能与功耗/能耗属于后续指定平台验收工作。
