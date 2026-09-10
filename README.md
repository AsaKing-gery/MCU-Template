# MCU-Template

一个"配一次、以后每个新项目复制即用"的 **VSCode + CMake + clangd + Cortex-Debug** Cortex-M 开发模板。

目标是解决裸 CMake 方案最大的痛点：**每开一个新工程都要重配 `settings.json` / `launch.json` / `tasks.json`**。
本模板把所有会变的东西压缩成**一个文件 `mcu.json`**，其余全部通用。

> Keil 的省心是"封闭换来的"，这套模板的思路是**把配置成本一次性付清，然后模板化**。

---

## 一、核心设计：单点配置

```
mcu.json  ──┬─► cmake/gcc-arm-none-eabi.cmake   （工具链自动读取，生成 -mcpu/-mfpu/-T 等）
            └─► .vscode/launch.json             （运行一次 sync 脚本刷进去：device / svd）
```

- **CMake 侧**：工具链文件用 `string(JSON)` 直接解析 `mcu.json`，不用手改一行 CMake。
- **VSCode 侧**：`launch.json` 不支持 include，所以提供一个同步脚本 / 任务一键刷新。

结果：换芯片 = **改 `mcu.json` 一个文件**。

---

## 二、目录结构

```
MCU-Template/
├── mcu.json                  ★ 单点配置：整个工程只有这里需要按芯片修改
├── CMakeLists.txt              通用构建脚本（不含任何芯片信息）
├── CMakePresets.json           Debug / Release 两套预设
├── .clangd                     clangd 配置（指向 build/Debug）
├── .gitignore
├── cmake/
│   ├── gcc-arm-none-eabi.cmake 工具链文件，自动解析 mcu.json
│   └── disasm.cmake             反汇编辅助脚本（供给 disasm 目标调用）
├── scripts/
│   ├── new-project.ps1         ★ 一键建工程 / 把模板应用到已有工程（Windows）
│   ├── new-project.sh          同上（Linux / macOS）
│   ├── sync-mcu.ps1            mcu.json → launch.json 同步
│   └── sync-mcu.sh             同上（Linux / macOS）
├── .vscode/
│   ├── settings.json           CMake Presets + clangd
│   ├── launch.json             Cortex-Debug：OpenOCD / J-Link / Attach
│   ├── tasks.json              Configure / Build / Rebuild / Flash / Sync
│   └── extensions.json         推荐扩展
├── App/                        你自己的代码放这里（CubeMX 不会覆盖）
│   ├── Inc/app.h
│   └── Src/app.c
└── .svd/                       放芯片 SVD 文件（用于查看外设寄存器）
```

---

## 三、前置依赖

| 组件 | 版本 / 说明 | 检查命令 |
|---|---|---|
| **CMake** | ≥ 3.22（`string(JSON)` / Presets 需要） | `cmake --version` |
| **Ninja** | 任意版本，构建后端 | `ninja --version` |
| **Arm GNU Toolchain** | `arm-none-eabi-*`，或直接用 STM32CubeCLT 里自带的 | `arm-none-eabi-gcc --version` |
| **OpenOCD** | 烧录 / 调试（用 J-Link 可跳过） | `openocd --version` |
| **STM32CubeMX** | 生成初始化代码（可只用一次） | — |

**VSCode 扩展**（打开工程时会自动提示，见 `.vscode/extensions.json`）：

- `llvm-vs-code-extensions.vscode-clangd` — 代码补全 / 跳转 / 诊断
- `ms-vscode.cmake-tools` — 构建集成
- `marus25.cortex-debug` — 调试
- `ms-vscode.cpptools` — 仅作 Cortex-Debug 的依赖（IntelliSense 已在 settings 里关掉）
- `dan-c-underwood.arm` — `.s` 汇编语法高亮

### 工具链路径怎么找

模板按以下顺序查找 `arm-none-eabi-gcc`：

1. 环境变量 `ARM_GCC_PATH`（指向工具链**根目录**，其下有 `bin/`）
2. 系统 `PATH`

```powershell
# 如果没加进 PATH，设置一次即可（新开终端生效）
setx ARM_GCC_PATH "C:\Program Files\Arm\GNU Toolchain mingw-w64-x86_64-arm-none-eabi"
# 或用 CubeCLT 自带的
setx ARM_GCC_PATH "C:\ST\STM32CubeCLT_1.16.0\GNU-tools-for-STM32"
```

---

## 四、快速开始

### 方式 A：用脚本新建工程（推荐）

```powershell
# 在 MCU-Template 目录下
powershell -ExecutionPolicy Bypass -File scripts/new-project.ps1 ..\MyF407 -Chip stm32f407vg
```

Linux / macOS：

```bash
bash scripts/new-project.sh ../MyF407 stm32f407vg
```

脚本会：建目录 → 复制模板文件 → 按芯片写好 `mcu.json` → 同步 `launch.json`。

### 方式 B：套用到已有的 CubeMX 工程

```powershell
powershell -ExecutionPolicy Bypass -File scripts/new-project.ps1 ..\MyCubeProj -Chip stm32g431rb
```

**已存在的 `mcu.json` 不会被覆盖**（除非加 `-Force`），所以可以放心反复执行来更新模板文件。

### 方式 C：当成 GitHub 模板仓库

把本仓库设为 Template Repository，新项目点 "Use this template"，然后：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/new-project.ps1 . -Chip stm32f401re -Force
```

### 之后的标准流程

1. **STM32CubeMX** 打开工程目录生成代码
   - **Toolchain 建议选 `Makefile`**：这样 CubeMX 不会生成 `CMakeLists.txt`，不会和模板冲突
   - 若选了 `CMake`，CubeMX 每次重新生成都会覆盖 `CMakeLists.txt`，重新跑一次 `new-project.ps1` 即可恢复
2. 确认 `.ld` 链接脚本在工程根目录（或改 `mcu.json` 的 `linkerScript`）
3. 把芯片 SVD 丢进 `.svd/`（可选，用于寄存器视图）
4. VSCode 打开工程目录，**`Ctrl+Shift+B`** 构建，**F5** 调试

---

## 五、日常操作：任务与快捷键

VSCode 里 `Ctrl+Shift+P` → `Tasks: Run Task`，或直接 `Ctrl+Shift+B`。

| 任务 | 作用 |
|---|---|
| `Build (Debug)` | 默认构建，`Ctrl+Shift+B`，自动先 configure |
| `Build (Release)` | `-Os` 体积优化构建 |
| `Rebuild (clean-first)` | 全量重编，改了 `CMakeLists.txt` / 预设后用它 |
| `Clean (Debug)` | 清理 |
| `Flash (OpenOCD)` | 命令行烧录（ST-Link） |
| `Disassemble (.asm)` | 生成反汇编，排查 HardFault |
| `MCU: Sync from mcu.json` | 改完 `mcu.json` 后刷新 `launch.json` |

命令行等价：

```bash
cmake --preset Debug
cmake --build --preset Debug
cmake --build --preset Debug --target flash
cmake --build --preset Debug --target disasm
```

调试直接按 **F5**，选择 `Debug (OpenOCD / ST-Link)`（会先自动构建）。

### 构建产物

```
build/Debug/
├── <项目名>.elf     调试用
├── <项目名>.hex     烧录用
├── <项目名>.bin     烧录用
├── <项目名>.map     内存布局 / 符号表
└── compile_commands.json   clangd 依赖它
```

`<项目名>` = 工程目录名（例如目录叫 `MyF407` 就是 `MyF407.elf`），
所以 `launch.json` 里用 `${workspaceFolderBasename}` 就能自动对上，永远不用改。

---

## 六、`mcu.json` 字段详解

```jsonc
{
  "name": "STM32F407VG",                        // 仅作标识，脚本里用来起名字
  "device": "STM32F407VG",                      // Cortex-Debug 的 device
  "cpu": "cortex-m4",                           // → -mcpu=cortex-m4 -mthumb
  "fpu": "fpv4-sp-d16",                         // → -mfpu=fpv4-sp-d16（soft 时忽略）
  "floatAbi": "hard",                           // hard | soft | softfp → -mfloat-abi=
  "linkerScript": "STM32F407VGTx_FLASH.ld",     // 链接脚本文件名，工具链自动在根目录/Core/查找
  "svd": "STM32F407.svd",                       // 放在 .svd/ 下，调试时看外设寄存器
  "openocdTarget": "target/stm32f4x.cfg",       // OpenOCD 的 target 配置
  "defines": ["USE_HAL_DRIVER", "STM32F407xx"]  // 预处理宏，就是 HAL 的器件宏
}
```

改完执行 `cmake --preset Debug`（或 `Rebuild`）让 CMake 侧生效，
再跑一次 `MCU: Sync from mcu.json` 任务让 `launch.json` 生效。

### 常用芯片对照表

| 芯片 | cpu | fpu | floatAbi | linkerScript | openocdTarget | defines |
|---|---|---|---|---|---|---|
| STM32F103C8 | cortex-m3 | none | soft | `STM32F103C8Tx_FLASH.ld` | `target/stm32f1x.cfg` | `STM32F103xB` |
| STM32F401RE | cortex-m4 | fpv4-sp-d16 | hard | `STM32F401RETx_FLASH.ld` | `target/stm32f4x.cfg` | `STM32F401xE` |
| STM32F407VG | cortex-m4 | fpv4-sp-d16 | hard | `STM32F407VGTx_FLASH.ld` | `target/stm32f4x.cfg` | `STM32F407xx` |
| STM32F411CE | cortex-m4 | fpv4-sp-d16 | hard | `STM32F411CEUx_FLASH.ld` | `target/stm32f4x.cfg` | `STM32F411xE` |
| STM32F429ZI | cortex-m4 | fpv4-sp-d16 | hard | `STM32F429ZITx_FLASH.ld` | `target/stm32f4x.cfg` | `STM32F429xx` |
| STM32F446RE | cortex-m4 | fpv4-sp-d16 | hard | `STM32F446RETx_FLASH.ld` | `target/stm32f4x.cfg` | `STM32F446xx` |
| STM32F746ZG | cortex-m7 | fpv5-sp-d16 | hard | `STM32F746ZGTx_FLASH.ld` | `target/stm32f7x.cfg` | `STM32F746xx` |
| STM32H743ZI | cortex-m7 | fpv5-d16 | hard | `STM32H743ZITx_FLASH.ld` | `target/stm32h7x.cfg` | `STM32H743xx` |
| STM32G071RB | cortex-m0plus | none | soft | `STM32G071RBTx_FLASH.ld` | `target/stm32g0x.cfg` | `STM32G071xx` |
| STM32G431RB | cortex-m4 | fpv4-sp-d16 | hard | `STM32G431RBTx_FLASH.ld` | `target/stm32g4x.cfg` | `STM32G431xx` |
| STM32L431RC | cortex-m4 | fpv4-sp-d16 | hard | `STM32L431RCTx_FLASH.ld` | `target/stm32l4x.cfg` | `STM32L431xx` |

上表已内置进 `new-project` 脚本，用 `-Chip <名字>` 即可一次填好。
表里没有的芯片，直接传 `-Device` / `-Cpu` / `-Fpu` / `-FloatAbi` / `-LinkerScript` / `-Svd` / `-OpenocdTarget` / `-Defines`。

> 链接脚本名和器件宏最准确的办法：看 CubeMX 生成的工程里 `.ld` 叫什么、`Makefile` 里 `C_DEFS` 写的是什么。

---

## 七、`CMakeLists.txt` 里你可能要改的地方

只有一个：

```cmake
set(MCU_SOURCE_DIRS Core Drivers App)   # 新增源码目录时加在这里
```

其余全自动：

- **源文件**：递归收集上述目录下的 `.c` / `.s` / `.S`，用 `CONFIGURE_DEPENDS`，**新增文件无需改脚本**
- 自动排除 HAL 的 `*_template.c` 和 CMSIS `Source/Templates/` 里重复的 `system_*.c`
- **头文件目录**：自动收集 `Core`/`Drivers`/`App` 下所有名为 `Inc` / `Include` / `Legacy` 的目录，因此换 STM32 系列不用改路径

### 用户代码放哪

`App/` 目录是留给你的，CubeMX 不会碰它。在 `main.c` 里：

```c
#include "app.h"

/* ... MX_xxx_Init() 之后 ... */
App_Init();
while (1)
{
    App_Loop();
}
```

### 浮点 printf

默认关闭（省空间）。需要 `printf("%f")` 时：

```bash
cmake --preset Debug -DMCU_USE_PRINTF_FLOAT=ON
```

---

## 八、Debug 配置说明

`launch.json` 三条配置：

| 配置 | 用途 |
|---|---|
| `Debug (OpenOCD / ST-Link)` | 最常用，ST-Link + OpenOCD |
| `Debug (J-Link)` | J-Link 用户 |
| `Attach (OpenOCD)` | 附加到正在运行的目标，不复位、不下载 |

- `runToEntryPoint: "main"`：下载后自动停在 `main`，不用手动打断点。
- `preLaunchTask: "Build (Debug)"`：F5 前自动构建。
- **外设寄存器视图**：把 `.svd/<芯片>.svd` 放好，调试时左下角会出现 `XPERIPHERALS` 面板。
  没放 SVD 也能调试，只是看不到寄存器；`.svd/*.svd` 已在 `.gitignore` 中忽略。
- OpenOCD 不在 `PATH` 时，可以在配置里加 `"openocdPath": "C:/path/to/openocd.exe"`。

---

## 九、常见问题

**Q：报错"未找到 arm-none-eabi-gcc"**
装 Arm GNU Toolchain 或 STM32CubeCLT，加入 `PATH`，或设置环境变量 `ARM_GCC_PATH`。

**Q：clangd 满屏红波浪线，找不到 `stm32f4xx.h`**
先**构建一次**（`Ctrl+Shift+B`）生成 `build/Debug/compile_commands.json`。
还有问题就在 `settings.json` 里确认 `--query-driver=**/arm-none-eabi-*` 能匹配到你的编译器绝对路径。

**Q：CubeMX 重新生成后 `CMakeLists.txt` 被覆盖了**
CubeMX 选 `CMake` toolchain 时确实会覆盖。重新执行一次
`scripts/new-project.ps1 <你的工程目录>`（不会动 `mcu.json`）。
想彻底避免，就把 CubeMX 的 Toolchain 改成 `Makefile`。

**Q：链接报 `undefined reference to _exit / _sbrk / _write`**
缺 `syscalls.c` / `sysmem.c`。CubeMX 默认会生成到 `Core/Src/`，确认这两个文件在，且没被排除。

**Q：链接报 `cannot find linker script xxx.ld`**
`.ld` 不在工程根目录（模板也会在根目录、`Core/`、`ld/`、`LinkerScript/` 里找）。
把文件放对位置，或修改 `mcu.json` 的 `linkerScript`。

**Q：找不到 `ninja`**
`pip install ninja`，或装 STM32CubeCLT（自带 ninja 与 cmake）。

**Q：改了 `mcu.json` 但调试时 device 没变**
`launch.json` 需要同步：运行任务 `MCU: Sync from mcu.json`。
CMake 侧改了 `-mcpu` / `-mfpu` 后要重新 configure（`Rebuild (clean-first)`）。

**Q：`printf` 输出不了 `%f`**
打开 `MCU_USE_PRINTF_FLOAT`（见上一节），会增大固件体积。

**Q：`flash` 任务提示找不到 openocd**
装 OpenOCD 并加入 `PATH`；或直接用 F5 调试（Cortex-Debug 会自己调 OpenOCD）。

---

## 十、与 Keil 的对应关系

| Keil | 本模板 |
|---|---|
| `Options for Target → Device` | `mcu.json` 的 `device` / `cpu` / `fpu` / `floatAbi` |
| Target 里的 `Define` | `mcu.json` 的 `defines` |
| Target 里的 `Include Paths` | 自动收集，不用配 |
| Linker → Scatter File | `mcu.json` 的 `linkerScript` |
| Debug → ST-Link Settings | `launch.json` 的 `servertype` / `configFiles` |
| 下载按钮 | F5 或 `Flash (OpenOCD)` 任务 |
| Watch / Peripheral 窗口 | 调试侧边栏 + `XPERIPHERALS`（需 SVD） |
| `.uvprojx` 工程文件 | `CMakeLists.txt` + `CMakePresets.json` |

---

## 十一、维护这个模板

改了模板本身之后，已有工程这样同步（**不会覆盖你的 `mcu.json`**）：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/new-project.ps1 <已有工程目录>
```

建议约定：

- 模板里只放**通用**的东西；任何芯片专属的值都进 `mcu.json`。
- 新增的构建开关用 `option()` 暴露，不要硬编码进 `CMakeLists.txt`。
- 想同步 VSCode 扩展与全局设置到多台机器，用 VSCode 的 **Settings Sync** 或 **Profiles**（`Profiles: Export Profile`）。
