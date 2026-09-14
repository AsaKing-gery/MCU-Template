# MCU-Template

[![CI](https://github.com/AsaKing-gery/MCU-Template/actions/workflows/ci.yml/badge.svg)](https://github.com/AsaKing-gery/MCU-Template/actions/workflows/ci.yml)

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
├── .clang-format               ★ 代码格式化规则（Tab + Allman，按国内单片机习惯调过）
├── .gitignore
├── cmake/
│   ├── gcc-arm-none-eabi.cmake 工具链文件，自动解析 mcu.json
│   └── disasm.cmake             反汇编辅助脚本（供给 disasm 目标调用）
├── scripts/
│   ├── build.ps1               ★ 一键构建：修 UTF-8 中文乱码 + 打印彩色摘要（Ctrl+Shift+B 用它）
│   ├── setup-env.ps1           ★ 一次性配置 Windows 用户环境变量（PATH / OPENOCD_SCRIPTS）
│   ├── fix-encoding.ps1        ★ 找出（并可转换）GBK 编码的源文件——clangd 只认 UTF-8
│   ├── format-all.ps1          ★ 整个工程跑 clang-format（默认预览、可备份应用）
│   ├── new-project.ps1         ★ 一键建工程 / 把模板应用到已有工程（Windows）
│   ├── new-project.sh          同上（Linux / macOS）
│   ├── sync-mcu.ps1            mcu.json → launch.json 同步
│   └── sync-mcu.sh             同上（Linux / macOS）
├── .vscode/
│   ├── settings.json           CMake Presets + clangd + clang-format
│   ├── launch.json             Cortex-Debug：OpenOCD / J-Link / Attach
│   ├── tasks.json              Configure / Build / Rebuild / Flash / Sync / Format
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
| **CMake** | ≥ 3.22（`string(JSON)` / Presets 需要）。装了 VS 的话它自带的也能用 | `cmake --version` |
| **Ninja** | 构建后端。装了 VS 也一样自带 | `ninja --version` |
| **Arm GNU Toolchain** | `arm-none-eabi-*`。装过 STM32CubeIDE / CubeCLT 就不用另外装，模板会自动找到 | `arm-none-eabi-gcc --version` |
| **OpenOCD** | 烧录 / 调试用（用 J-Link 可跳过）。CubeIDE 自带的也能自动找到 | `openocd --version` |
| **clang-format** | 代码格式化（可选）。**VS 自带一份**，`setup-env.ps1` 会自动找到 | `clang-format --version` |
| **STM32CubeMX** | 生成初始化代码（可只用一次） | — |

### 一键配置环境（Windows，推荐先跑这个）

`cmake` / `ninja` / `openocd` 经常装了却不在 `PATH` 里（尤其是 VS 自带的 cmake 和 ninja），
而 `tasks.json` 里的任务是在**普通终端**里跑的，会报"找不到 ninja"。

跑一次这个脚本就全好了 —— 它自动探测、备份、写环境变量：

```powershell
# 先看会改什么，不实际写入
powershell -ExecutionPolicy Bypass -File scripts/setup-env.ps1 -DryRun

# 确认后执行
powershell -ExecutionPolicy Bypass -File scripts/setup-env.ps1
```

输出示例：

```
== Looking for cmake / ninja / openocd ==
  cmake   : will add   C:\Program Files\Microsoft Visual Studio\18\Community\...\CMake\CMake\bin
  ninja   : will add   C:\Program Files\Microsoft Visual Studio\18\Community\...\CMake\Ninja
  openocd : will add   C:\ST\STM32CubeIDE_2.0.0\...\externaltools.openocd.../tools/bin
  scripts : C:\ST\STM32CubeIDE_2.0.0\...\mcu.debug.openocd_.../resources/openocd/st_scripts
```

它做的事：

1. 查找 `cmake` / `ninja` / `openocd`（先看现有 `PATH`，再找 VS 和 CubeIDE 的常见安装位置）
2. 把缺的目录加进**用户** `PATH`
3. 设置用户变量 `OPENOCD_SCRIPTS`（ST 版 OpenOCD 必须，否则报 `Can't find interface/stlink.cfg`）
4. 改之前备份到 `%USERPROFILE%\.mcu-template-backup\`

> ⚠️ 脚本**故意不用 `setx PATH`**：`setx` 有 1024 字符截断限制，`PATH` 一长就会**被砍掉一半**。
> 它用的是 .NET API，没有这个限制，并且写回前会检查"新值不能比旧值短"。
>
> ⚠️ 工具链（`arm-none-eabi-gcc`）**故意不加进 PATH**：CMake 工具链文件会自己探测
> CubeIDE / CubeCLT / Arm 的位置，这样 CubeIDE 升级后也不会失效。

**改完必须重启 VSCode（所有窗口）+ 开新终端**才会生效。

**VSCode 扩展**（打开工程时会自动提示，见 `.vscode/extensions.json`）：

- `llvm-vs-code-extensions.vscode-clangd` — 代码补全 / 跳转 / 诊断
- `ms-vscode.cmake-tools` — 构建集成
- `marus25.cortex-debug` — 调试
- `ms-vscode.cpptools` — 仅作 Cortex-Debug 的依赖（IntelliSense 已在 settings 里关掉）
- `dan-c-underwood.arm` — `.s` 汇编语法高亮

### 工具链路径怎么找

模板按以下顺序查找 `arm-none-eabi-gcc`，**装过 STM32CubeIDE 的话通常第 3 步就自动命中了，什么都不用配**：

1. 环境变量 `ARM_GCC_PATH`（指向工具链**根目录**，其下有 `bin/`）
2. 系统 `PATH`
3. 自动探测常见安装位置：
   - `C:/ST/STM32CubeCLT_*/GNU-tools-for-STM32/bin`
   - `C:/ST/STM32CubeIDE_*/STM32CubeIDE/plugins/com.st.stm32cube.ide.mcu.externaltools.gnu-tools-for-stm32.*/tools/bin`
   - `C:/Program Files/STMicroelectronics/STM32Cube/STM32CubeIDE/plugins/...`
   - `C:/Program Files/Arm/GNU Toolchain*/bin`
   - Linux / macOS 对应路径

configure 时会打印实际用了哪一个：

```
-- 工具链来源：自动探测 -> C:/ST/STM32CubeIDE_2.0.0/.../tools/bin
```

想强制指定（比如同时装了多个版本）：

```powershell
setx ARM_GCC_PATH "C:\Program Files\Arm\GNU Toolchain mingw-w64-x86_64-arm-none-eabi"
# 或 CubeCLT 自带的
setx ARM_GCC_PATH "C:\ST\STM32CubeCLT_1.17.0\GNU-tools-for-STM32"
```

> CubeIDE 的插件目录名里带版本号，**CubeIDE 升级后路径会变**。模板用的是通配符匹配，
> 所以升级后自动还是能找到；但你手动设过 `ARM_GCC_PATH` 的话需要重新设置。

### OpenOCD 从哪来

**CubeIDE 自带的 OpenOCD 需要额外的脚本目录**，否则报 `Can't find interface/stlink.cfg`——
它的脚本在另一个插件里（`com.st.stm32cube.ide.mcu.debug.openocd_*/resources/openocd/st_scripts`），
不在 OpenOCD 自己的目录下。

两种解决办法：

**① 用 `OPENOCD_SCRIPTS` 环境变量（推荐，`setup-env.ps1` 会自动设好）**

OpenOCD 认这个环境变量，把它加进脚本搜索路径。设好之后：

- `flash` 目标直接能用
- **F5 调试也直接能用**，`launch.json` 一个字都不用改，模板保持通用

```powershell
[Environment]::SetEnvironmentVariable(
    'OPENOCD_SCRIPTS',
    'C:\ST\STM32CubeIDE_2.0.0\STM32CubeIDE\plugins\com.st.stm32cube.ide.mcu.debug.openocd_2.3.200.202510310951\resources\openocd\st_scripts',
    'User')
```

> 注意：`flash` 目标**不依赖**这个环境变量，它自己会探测并显式传 `-s`。
> 所以即使忘了设，命令行烧录也是好的——只有 F5 需要它。

**② 在 `launch.json` 里写死路径（不依赖环境变量，但跟机器绑定）**

```jsonc
"openocdPath": "C:/ST/STM32CubeIDE_2.0.0/.../externaltools.openocd.win32_2.4.300.202509300731/tools/bin/openocd.exe",
"searchDir":   ["C:/ST/STM32CubeIDE_2.0.0/.../com.st.stm32cube.ide.mcu.debug.openocd_2.3.200.202510310951/resources/openocd/st_scripts"],
```

**③ 或者干脆装独立的 [xPack OpenOCD](https://github.com/xpack-dev-tools/openocd-xpack/releases)**

它自带 `share/openocd/scripts`，解压后把 `bin` 加进 `PATH` 即可，①②都不用做，也不会被 CubeIDE 升级影响。

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

| 任务 | 作用 | Keil 里对应 |
|---|---|---|
| `Build (Debug)` | 默认构建，`Ctrl+Shift+B`，自动先 configure | **Build（F7）** |
| `Build (Release)` | `-Os` 体积优化构建 | 切到 Release Target 再 Build |
| `Rebuild (clean-first)` | 全量重编，改了 `CMakeLists.txt` / 预设后用它 | **Rebuild** |
| `Clean (Debug)` | 清理产物 | Clean Target |
| `Reset Build (delete cache)` | 删掉整个 `build/`。**移动/重命名工程目录后必须跑一次** | 删掉 Objects 目录（更彻底） |
| `Flash (OpenOCD)` | 只烧录，不调试（ST-Link） | **Download（F8）** |
| `Disassemble (.asm)` | 生成反汇编，排查 HardFault | 反汇编窗口 |
| `MCU: Sync from mcu.json` | 改完 `mcu.json` 后刷新 `launch.json` | 改完 Device 设置 |
| `Format All (preview)` | **预览**全工程 clang-format 会改哪些文件、多少行，不写盘 | — |
| `Format All (apply)` | 真正执行格式化（先备份到 `%USERPROFILE%\.mcu-template-backup\`） | — |

> ⚠️ **`.vscode/tasks.json` 里刻意不写 `${workspaceFolder}`**
>
> 工程路径一旦含**括号**（例如 `JY.RFM-0A-U575(24G)-cmake`），PowerShell 会把
> `(24G)` 当成**子表达式**，命令会被拆坏：
>
> ```
> 24G : 无法将"24G"项识别为 cmdlet、函数、脚本文件或可运行程序的名称
> ```
>
> 任务的工作目录默认就是工程根，所以这里全部用**相对路径**（`scripts/xxx.ps1`、`build`）。
> **你自己加任务时也请照做。**

### 构建 / 重新构建 / 烧录 —— 别混

**编译和烧录是完全两件事**：编译只是产出 `.elf` / `.hex` / `.bin`，**不会碰芯片**。

| 想干什么 | 怎么做 | 说明 |
|---|---|---|
| **只编译** | `Ctrl+Shift+B` | 产出固件文件，芯片里什么都没变 |
| **编译 + 烧录 + 进调试** | **`F5`** | `launch.json` 里配了 `preLaunchTask: "Build (Debug)"`，一步到位。**日常就用这个** |
| **只烧录**（不调试） | `Tasks: Run Task` → `Flash (OpenOCD)` | 相当于 Keil 的 Download（F8） |
| **附加到正在跑的目标** | F5 选 `Attach (OpenOCD)` | 不复位、不下载，看现场 |

**关于 Rebuild（编译缓存冲突）**

Keil 因为依赖追踪较弱，经常需要 Rebuild。CMake + Ninja 的依赖追踪是**文件级 + 命令行级**的
（改了源码、头文件、编译参数、甚至 `mcu.json` 都会自动重编），所以**平时不需要 Rebuild**。

需要的时候：

| 情况 | 用哪个 |
|---|---|
| 改了 `CMakeLists.txt` / `CMakePresets.json` / `mcu.json` | `Rebuild (clean-first)` |
| 改了工具链文件的 flags | `Rebuild (clean-first)` |
| **移动 / 重命名了工程目录** | `Reset Build (delete cache)` ← **必须**，否则 CMakeCache 里的旧绝对路径会直接报错 |
| 出现莫名其妙的链接错误、怀疑缓存脏了 | `Reset Build (delete cache)` → `Ctrl+Shift+B` |
| 只是想把产物清掉 | `Clean (Debug)` |

### 输出颜色 / 中文乱码

**用 `Ctrl+Shift+B`（终端）构建，不要用 CMake Tools 状态栏的 Build 按钮。**

#### ① CMake Tools 的"输出"面板显示不了颜色

CMake Tools 扩展把配置/构建输出写到 VSCode 的 **Output 面板**，而那个面板会把 ANSI
转义序列当**普通文字**打印出来：

```
[cmake] -- [1;36m━━━ MCU 配置 ━━━━━━━━━━━━━━━━━━━[0m     ← 乱码，不是颜色
```

这是扩展 + 面板的限制，**没法让它显示颜色**。只有真正的**终端**才渲染 ANSI。

#### ② 中文乱码：`[Console]::OutputEncoding` 没设成 UTF-8

中文 Windows 控制台默认代码页是 **936（GBK）**，而 CMake 输出 UTF-8，
于是 `生成 .hex / .bin` 变成 `鐢熸垚 .hex / .bin`。

**踩过的坑：光敲 `chcp 65001` 修不好。** 实测确认：

| 试过的办法 | 结果 |
|---|---|
| 终端里敲 `chcp 65001` | ❌ 还是乱码 |
| 在 `settings.json` 里自定义一个"先 chcp"的终端 profile | ❌ 反而把终端搞坏了（见下面的教训） |
| 终端里敲 `[Console]::OutputEncoding=[Text.Encoding]::UTF8` | ✅ **正常** |
| `scripts/build.ps1`（内部设了上面这行） | ✅ 正常 |

**原因**：`chcp` 改的是控制台代码页，而 PowerShell 启动时就已经把
`[Console]::OutputEncoding` 初始化好了，**`chcp` 不会刷新这个 .NET 属性**。
真正决定"PowerShell 怎么解码 cmake 的输出"的是后者。

所以现在**每个 CMake 任务的命令前面都加了这一段**（8 个任务）：

```jsonc
"command": "[Console]::OutputEncoding=[Text.Encoding]::UTF8; cmake --preset Debug",
```

> ⚠️ 注意这段是 **PowerShell 语法**。本工程默认终端就是 PowerShell，所以没问题；
> 如果哪天换成 cmd，要改成 `chcp 65001 >nul & cmake --preset Debug`。
>
> ⚠️ **另一个喂过血的教训：不要试图用自定义终端 profile 修这个。**
> VSCode 是经 `cmd.exe` 拉起 profile 的，参数里只要有 `>` 就会被 cmd 当成重定向，
> 结果任务直接报 `参数格式不正确 - -Command`，整个终端都用不了。
> 修在**任务的 command 里**是安全的（直接交给 PowerShell 执行）。

#### ③ 颜色从哪来

| 输出内容 | 怎么上色 | 在哪能看见 |
|---|---|---|
| CMake 配置摘要 / 警告 | `CMakeLists.txt` 里的 ANSI 转义（`MCU_COLOR_OUTPUT`） | **终端** ✓ |
| 编译器 warning / error | `CMAKE_COLOR_DIAGNOSTICS` → GCC 的 `-fdiagnostics-color=always` | **终端** ✓ |
| 固件体积报告 | `cmake/report_size.cmake` | **终端** ✓ |

`Build` / `Rebuild` 任务通过 `options.env` 打开它：

```jsonc
"options": { "env": { "MCU_COLOR_OUTPUT": "1" } }
```

`report_size.cmake` 同时认**运行时环境变量**和配置时写进去的值，所以不管上次是谁
configure 的（终端任务还是 CMake Tools），在终端里构建都有颜色。

> CMake Tools 那条路径永远是**干净纯文本**、不会出乱码 —— 因为 `MCU_COLOR_OUTPUT`
> 用 `set()` 而**不是 `option()`**，**故意不写进 `CMakeCache.txt`**。

#### 备用：`scripts/build.ps1`

如果哪天终端里也没颜色了，还有个更彻底的办法 —— 这个脚本自己打印彩色摘要
（**不经过 ninja，颜色一定生效**），并且强制 UTF-8：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build.ps1                 # Debug
powershell -ExecutionPolicy Bypass -File scripts/build.ps1 -Preset Release
powershell -ExecutionPolicy Bypass -File scripts/build.ps1 -Rebuild        # = Keil Rebuild
powershell -ExecutionPolicy Bypass -File scripts/build.ps1 -Flash          # 编译 + 烧录
```

> 它**故意没有**接进 `tasks.json`：用 `-File <路径>` 调用时，工程路径里的括号
> （`...(24G)...`）会被 PowerShell 拆坏，见上面那条警告。相对路径调用没问题。

### 只想按一个键：`Ctrl+Shift+B`，或者绑成 F7

`Ctrl+Shift+B` 本身就是**一个组合键**，直接跑默认构建任务 `Build (Debug)`。

想更贴近 Keil 的手感，把 **F7** 绑上去 —— 把你的 `keybindings.json`
（`Ctrl+Shift+P` → `Preferences: Open Keyboard Shortcuts (JSON)`）加上一条：

```jsonc
// F7 = 编译（和 Keil 一样）
{ "key": "f7", "command": "workbench.action.tasks.build" },

// 想指定具体任务就用这条
// { "key": "f7", "command": "workbench.action.tasks.runTask", "args": "Build (Debug)" },
```

**分工建议**

| 用途 | 用什么 |
|---|---|
| **构建 / 重编 / 烧录** | `Ctrl+Shift+B`、F7、或 `Tasks: Run Task` —— 走终端，有颜色 ✓ |
| 切换 Debug / Release preset、看 CMake 状态 | CMake Tools 状态栏按钮 ✓（跟构建无关，用它没问题） |
| 看警告 / 错误清单 | **Problems 面板**（`Ctrl+Shift+M`），构建时自动填 |

> CMake Tools 状态栏那个 ▶ Build 按钮**能用，但输出是白的** —— 因为它走 Output 面板。
> 想有颜色就别用它构建。

### 代码格式化（clang-format）

规则在工程根的 **`.clang-format`**，已经按国内单片机代码习惯调好：

| 选项 | 值 | 说明 |
|---|---|---|
| `UseTab` / `TabWidth` | `Always` / `4` | **Tab 缩进**，和 Keil、CubeMX 生成的代码一致 |
| `BreakBeforeBraces` | `Allman` | 大括号独占一行 |
| `SpaceBeforeParens` | `Never` | `if(` `while(` 不留空格 |
| `PointerAlignment` | `Right` | `uint8_t *p` |
| `ColumnLimit` | `0` | **不折行** —— 对已有代码改动最小，只动缩进/空格/大括号 |
| `SortIncludes` | `Never` | 不重排 `#include`（嵌入式里包含顺序常有依赖，排了会编不过） |
| `AlignConsecutiveMacros` | `true` | 连续的宏定义对齐（`#define` 表格好看） |

**三种用法：**

```powershell
# ① 单个文件：VSCode 里 Shift+Alt+F
# ② 整个工程（先预览）
powershell -ExecutionPolicy Bypass -File scripts/format-all.ps1 -ProjectRoot <工程目录>
# ③ 确认后执行（自动备份）
powershell -ExecutionPolicy Bypass -File scripts/format-all.ps1 -ProjectRoot <工程目录> -Apply
```

### ⚠️ 两个必须避开的坑

**① 汇编文件绝对不能格式化**

`clang-format` **没有汇编前端**。给它 `.s` 文件，它会按 C++ 解析并把文件毁掉：

```
cpu cortex-m33              ->   cpu cortex-
                                 m33             Error: unknown cpu `cortex-'
.section .text.Reset_Handler ->  .section.text.reset_handler
```

所以脚本的扩展名列表里**故意没有 `.s` / `.S`**。CubeMX 生成的
`Core/Startup/startup_stm32xxxx.s` 必须原样保留。

**② 厂商代码要排除，否则 diff 会失控**

CubeMX 工程里的第三方代码往往比你自己的代码多得多，而且都是空格缩进 ——
强制转成 Tab 会让**每一行都算改动**。实测某工程：

| 范围 | 待格式化文件 | 行改动 |
|---|---:|---:|
| 只排除 `Drivers` | 172 | **+114461 / −116113** |
| 再加上 `User\Src\Libraries`、`arm_math.h`、`FATFS` | 96 | **+18282 / −18682** |

**差 6 倍。** 厂商代码还会带来别的问题：

- 以后没法再和上游版本对比
- CubeMX 重新生成代码时会产生一堆无意义的 diff
- 有些厂商头文件（如 IAR 专用的 `cmsis_iccarm.h`）clang-format 直接解析失败

典型需要排除的位置：

| 位置 | 是什么 |
|---|---|
| `Drivers/` | ST 的 HAL / CMSIS 驱动 |
| `User/Src/Libraries/`（视工程而定） | 另一份 ST LL 驱动副本 |
| `arm_math.h` | ARM CMSIS-DSP 数学库 |
| `sd_card/FATFS/`（视工程而定） | FatFs 文件系统 |
| `Middlewares/` | FreeRTOS / LwIP / USB 协议栈等 |

用法：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/format-all.ps1 -ProjectRoot <工程目录> `
    -ExcludeDirs Drivers,'User\Src\Libraries','sd_card\FATFS' `
    -ExcludeFiles 'arm_math.h'
```

`-ExcludeDirs @()` 表示不排除任何目录（格式化所有东西）。

> 判断标准很简单：**这段代码不是你写的、而且以后还会被上游覆盖 → 排除掉。**

**为什么 `editor.formatOnSave` 默认是关的**

格式化的代价是 diff。老工程第一次全量格式化通常会**改动 70% 以上的行** ——
如果开着"保存即格式化"，你每改一个字符都会顺手把整个文件重排一遍，
git/svn 的 diff 会变得完全没法 review，blame 也全废。

建议流程：

1. 先跑一次 `Format All (apply)`，把存量一次性清干净
2. **单独提交这个"纯格式"变更**（commit message 写明 formatting only）
3. 之后再考虑打开 `editor.formatOnSave`，增量维护就轻松了

> ⚠️ **clang-format 不改代码语义**，但它会重排空白。格式化后请**重新编译一次**，
> 确认 `.bin` 的 md5 没变（除了极少数因为字符串字面量跨行拼接而变化的场景）。
>
> ⚠️ 它对 **GBK 文件是安全的**（实测中文一个不丢，只动空白字节），
> 但混着编码容易乱，建议先用 `fix-encoding.ps1` 转成 UTF-8 再格式化。

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

`<项目名>` = 工程目录名，但会**消毒**一次。

CMake 的 target 名只允许 `字母 / 数字 / _ / - / . / +`，而真实工程目录名常带空格和括号
（比如 `JY.RFM-0A-U575(24G)`），直接拿来会 configure 失败。
所以模板会把非法字符统一换成下划线：

| 工程目录名 | 产物名 |
|---|---|
| `MyF407` | `MyF407.elf` |
| `JY.RFM-0A-U575(24G)-cmake` | `JY.RFM-0A-U575_24G_-cmake.elf` |

`launch.json` 里的 `executable` 由 `scripts/sync-mcu` 按**同一套规则**写入，
两边永远一致，不用手动改。所以**项目路径里有空格也没问题**。

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
  "floatIo": true,                              // 见下方"浮点 printf"，缺省 true
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

### 浮点 printf / scanf

由 `mcu.json` 的 **`floatIo`** 控制，**缺省 `true`**（和 CubeIDE 的行为一致）。

| 值 | 链接参数 | 代价 |
|---|---|---|
| `true` | `-Wl,--undefined=_printf_float` + `-Wl,--undefined=_scanf_float` | 约 +14 KB flash |
| `false` | 无 | 省约 14 KB |

```jsonc
"floatIo": true    // 关掉就改成 false
```

> **为什么默认开**：关掉的话 `printf("%f")` 不会报错，而是**在运行时静默输出错值/空值**，
> 极难排查。开着的代价每次构建都会在内存占用里显示出来，是看得见的。
>
> ⚠️ 这个开关**必须写在 `mcu.json` 里**，不能只靠命令行 `-D`：命令行设置只存在
> CMake 缓存里，一旦删缓存（比如移动工程目录后）就会悄悄掉回默认值。
>
> 实现细节：不能写成 `-u _printf_float -u _scanf_float` —— CMake 会对
> `target_link_options` 里的重复项去重，第二个 `-u` 会被删掉，
> `_scanf_float` 就被当成输入文件报 `cannot find _scanf_float`。

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
模板会自动探测 CubeCLT / CubeIDE / Arm 官方包的常见安装位置。
三个都试过还是没有，就按报错信息里的提示设一次 `ARM_GCC_PATH`（新开终端生效）：

```powershell
setx ARM_GCC_PATH "C:\ST\STM32CubeIDE_2.0.0\STM32CubeIDE\plugins\com.st.stm32cube.ide.mcu.externaltools.gnu-tools-for-stm32.<版本>.win32_<版本>\tools"
```

然后重新 configure：`cmake --preset Debug --fresh`（VSCode 里跑 `Rebuild (clean-first)`）。

**Q：代码能编译成功，但编辑器里还是满屏红波浪线**

先记住一件事：**构建用 `arm-none-eabi-gcc`，编辑器用 clangd（clang）—— 两套完全独立的分析。**
"编译过了"不等于"clangd 没意见"。

按下面三条依次排查，覆盖 99% 的情况：

**① clangd 是不是拿不到工具链的路径？（最常见）**

看输出面板（`Ctrl+Shift+U` → 选 `clangd`），如果有：

```
E[...] System include extraction: driver arm-none-eabi-gcc not found in PATH
E[...] [pp_file_not_found] Line 20: in included file: 'math.h' file not found
```

说明 clangd **不认识交叉编译器的内建头文件**（`stdio.h` / `math.h` / `stdint.h` 来自 GCC 自带的 newlib）。
`--query-driver` 是**按程序名去 PATH 里找** `arm-none-eabi-gcc` 的，PATH 里没有就拿不到。

→ 跑 `scripts/setup-env.ps1`（它会把工具链 bin 也加进 PATH），然后**重启 VSCode**。

> 注意：CMake **不需要**工具链在 PATH 里（工具链文件自己会找），所以"能编译"和"clangd 报错"会同时出现。

**② 源文件是不是 GBK 编码？（中文 Windows 的高频坑）**

```
E[...] File has invalid UTF-8 near offset 3: 092F2FB2E2CAD40D
                                       ↑ B2E2CAD4 = GBK 的"测试"
```

- **GCC 不看编码**：GBK 注释对它只是字节，照样编译通过
- **clangd 强制 UTF-8**：读到非法字节就放弃整个文件 → 爆几百条错误

Keil / CubeIDE 在中文 Windows 上很容易把文件存成 GBK。查一下有多少：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/fix-encoding.ps1 -ProjectRoot <工程目录>
```

确认后转换（会先备份到 `%USERPROFILE%\.mcu-template-backup\`）：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/fix-encoding.ps1 -ProjectRoot <工程目录> -Apply
```

> ⚠️ 脚本会单独列出**中文出现在字符串字面量里**的文件（比如 `printf("看门狗未开启")`）。
> 这类文件转成 UTF-8 后，**发给串口/LCD 的字节会变**，接收端也要改成 UTF-8。
> 只出现在注释里的文件转了没有任何副作用。

**③ clang 比 GCC 严格，报出的是真问题**

同样一份代码，两个编译器的态度可能完全不同：

| 写法 | GCC 13 | clang（clangd） | GCC 14+ |
|---|---|---|---|
| 调用前没声明的函数 | ⚠️ 警告 | ❌ **错误** | ❌ 错误 |
| 不兼容的函数指针 | ⚠️ 警告 | ❌ **错误** | ⚠️ 警告 |

典型的 clangd 报错：

```
call to undeclared function 'TCP_send_string';
ISO C99 and later do not support implicit function declarations
```

**这不是误报，是 clang 提前把 GCC 以后也会报的错报出来了。** 隐式声明时编译器会假设函数返回
`int`，在 32 位 ARM 上指针刚好也是 32 位，"碰巧能跑"—— 换个优化级别就可能崩。
建议把这类错误修掉（补 `#include` 或加函数声明）。

**其它检查项**

1. `build/Debug/compile_commands.json` 存在吗？clangd 全靠它。没有就先 `Ctrl+Shift+B`。
2. `Ctrl+Shift+P` → `clangd: Restart language server`（改了 `.clangd` / `settings.json` 后）。
3. `.clangd` 里的 `CompilationDatabase: build/Debug` 要和实际输出目录一致（换 Release 时要改）。

**Q：移动 / 重命名了工程目录，configure 报 `CMakeCache.txt directory ... is different`**

这不是代码问题，是 CMake 的正常保护机制。`build/Debug/CMakeCache.txt` 里存的是
**绝对路径**（`CMAKE_HOME_DIRECTORY`、编译器路径、头文件路径……几百条），
目录一移动就对不上了，CMake 会拒绝继续。

`build/` 是一次性的缓存，删掉重配即可。三种方式任选：

```powershell
# 命令行
cmake --preset Debug --fresh      # 需要 CMake >= 3.24
```

- VSCode：`Ctrl+Shift+P` → `CMake: Delete Cache and Reconfigure`
- 或跑任务 `Reset Build (delete cache)`，然后 `Ctrl+Shift+B`

> **除 `build/` 外，工程里其它配置都是路径无关的**（`mcu.json`、`CMakePresets.json`、
> `.vscode/`、`.clangd`、工具链文件全部用 `${workspaceFolder}` / `${sourceDir}` / 相对路径），
> 所以换目录、换电脑都不用改任何配置。

**Q：CubeMX 重新生成后 `CMakeLists.txt` 被覆盖了**
CubeMX 选 `CMake` toolchain 时确实会覆盖。重新执行一次
`scripts/new-project.ps1 <你的工程目录>`（不会动 `mcu.json`）。
想彻底避免，就把 CubeMX 的 Toolchain 改成 `Makefile`。

**Q：链接报 `undefined reference to _exit / _sbrk / _write`**
缺 `syscalls.c` / `sysmem.c`。CubeMX 默认会生成到 `Core/Src/`，确认这两个文件在，且没被排除。

**Q：链接报 `cannot find linker script xxx.ld`**
`.ld` 不在工程根目录（模板也会在根目录、`Core/`、`ld/`、`LinkerScript/` 里找）。
把文件放对位置，或修改 `mcu.json` 的 `linkerScript`。

**Q：找不到 `ninja` / `cmake` / `openocd`**
先跑一次 `scripts/setup-env.ps1`，它会自动找到并加进用户 `PATH`。

装 VS 的用户注意：VS 自带 cmake 和 ninja，但**不在 `PATH` 里**。
CMake Tools 扩展自己会找到它们，所以侧边栏能构建；但 `tasks.json` 里的任务是在普通终端跑的，会报找不到。

如果非想手动加，**不要用 `setx PATH "%PATH%;..."`** —— `setx` 会在 1024 字符处截断，
`PATH` 长一点就会被砍掉一半。用：

```powershell
$p = [Environment]::GetEnvironmentVariable('Path','User')
[Environment]::SetEnvironmentVariable('Path', "$p;C:\你的\ninja\目录", 'User')
```

改完要**重启 VSCode + 开新终端**。

**Q：改了 `mcu.json` 但调试时 device 没变**
`launch.json` 需要同步：运行任务 `MCU: Sync from mcu.json`。
CMake 侧改了 `-mcpu` / `-mfpu` 后要重新 configure（`Rebuild (clean-first)`）。

**Q：`printf` 输出不了 `%f`**
检查 `mcu.json` 的 `floatIo` 是不是被改成了 `false`（默认是 `true`）。
注意**不要**用命令行 `-DMCU_USE_PRINTF_FLOAT=ON` 来解决 —— 那样只改 CMake 缓存，
换台电脑或删掉 `build/` 之后又会失效。

**Q：`flash` 任务提示找不到 openocd**
`flash` 目标会自动探测 CubeIDE 自带的 OpenOCD，所以正常情况不用配。
实在找不到（没装 CubeIDE）就装一个 xPack OpenOCD。

**Q：F5 调试报 `Can't find interface/stlink.cfg`**
CubeIDE 自带 OpenOCD 的脚本在**另一个插件**里，需要告诉它。最省事的是设一次环境变量
（`scripts/setup-env.ps1` 会自动配好）：

```powershell
[Environment]::SetEnvironmentVariable('OPENOCD_SCRIPTS', '<st_scripts 目录>', 'User')
```

详见「OpenOCD 从哪来」一节。

**Q：F5 报 `openocd` 找不到**
CubeIDE 自带的不在 `PATH` 里。跑 `scripts/setup-env.ps1`，或手动把它的 `bin` 加进用户 `PATH`。

**Q：`flash` 任务报 `embedded:startup.tcl:1520: Error: Infinite eval recursion`**
这是 ST 版 OpenOCD 的报错 bug：它真正想说的是"没连上 ST-Link"（`exit` 在 `init` 之前非法，
它在报这个错时自己递归了）。插上调试器再试；或者用 F5 下载——Cortex-Debug 不走这条路径。

**Q：装了 ST 官方的 STM32 VS Code Extension 扩展包，会不会冲突**
`stmicroelectronics.stm32cube-ide-*` 系列自带 clangd 与 CMake 构建集成，和本模板的
`vscode-clangd` + `cmake-tools` 是两套并行方案，可能抢同一块地方。建议二选一：
用本模板时把 ST 那一套禁掉（只留它的 `-debug-stlink-gdbserver` 也行）。

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

---

## 十二、CI（持续集成）

### 嵌入式项目的 CI 能做什么、不能做什么

| 能做（纯软件，不需要硬件） | 不能做（必须有板子） |
|---|---|
| **Debug / Release 都能编过** —— 防止"我本地能编" | 烧录 |
| **固件体积不超标** —— 有人加个大数组撑爆 FLASH，CI 直接拦住 | 上板测试 |
| **没有循环包含** —— 它能让编辑器补全失效，但编译照样过 | 硬件在环（HIL） |
| **格式一致** —— 强制 clang-format | 真实外设行为验证 |
| **每个提交都留一份 .elf/.hex/.bin** —— 随时回滚固件 | |

一句话：**CI 保证"能编、体积不炸、代码健康"，硬件相关留在你本地 F5。**

### 本地：`scripts/ci.ps1`（提交前跑这个）

```powershell
powershell -ExecutionPolicy Bypass -File scripts/ci.ps1
```

它会依次做四件事，任何一件不过就返回非 0：

```
=== 1/4  circular includes ===      循环包含检查
=== 2/4  clang-format ===           格式检查（有一处没格式化就失败）
=== 3/4  build (Debug/Release) ===  两个配置都编一遍，统计 warning 数
=== 4/4  firmware size ===          FLASH / RAM 占用
```

常用参数：

```powershell
# 体积门禁：超过就失败（默认 0 = 只看数字不卡人）
powershell -ExecutionPolicy Bypass -File scripts/ci.ps1 -MaxFlashPercent 90 -MaxRamPercent 90

# 从零开始构建（模拟 CI 机器）
powershell -ExecutionPolicy Bypass -File scripts/ci.ps1 -Fresh

# 只跑一部分
powershell -ExecutionPolicy Bypass -File scripts/ci.ps1 -SkipFormat
powershell -ExecutionPolicy Bypass -File scripts/ci.ps1 -SkipIncludes -Presets Debug
```

VSCode 里也能跑：`Ctrl+Shift+P` → `Tasks: Run Task` → **`CI (full check)`**。

### 相关脚本

| 脚本 | 作用 |
|---|---|
| `scripts/ci.ps1` | 完整流水线（上面那四步） |
| `scripts/check-includes.ps1` | 单独查循环包含，会打印出**每一个环的完整路径** |
| `scripts/format-all.ps1 -Strict` | 单独做格式检查（有不一致就返回非 0） |

### `.format-exclude`：哪些代码不检查

厂商代码（ST 的 HAL/LL、FatFs、CMSIS-DSP）**不参与**格式检查和包含检查。
清单写在工程根的 **`.format-exclude`** 里：

```
# 一行一条，只能整行注释
Drivers/                结尾带斜杠 = 跳过这个目录
User/Src/Libraries/
sd_card/FATFS/
arm_math.h              不带斜杠 = 按文件名匹配（支持通配符）
```

为什么必须排除厂商代码：格式化它们会导致 diff 失控（实测某工程：不排除 +114461 行，
排除后降到 +18282 行），而且以后没法跟上游版本对比。

### 云端：`.github/workflows/ci.yml`

推到 GitHub 后会自动跑（`push` / `pull_request` / 手动触发都行）：

1. 装 `gcc-arm-none-eabi` + `cmake` + `ninja`
2. `cmake --preset Debug` → 构建
3. `cmake --preset Release` → 构建
4. 统计 FLASH / RAM（想卡住就把 workflow 里的 `BUDGET=0` 改成 `90` 之类）
5. 把 `.elf/.hex/.bin/.map` 作为 artifact 上传（保留 90 天）

> ⚠️ **首次运行可能失败在 Linux 的大小写敏感上**：Windows 不区分大小写，
> 所以 `#include "Uart5.h"` 这种写错大小写的代码在 Windows 能编过、在 Linux 报错。
> 这是**有价值的反馈**，按报错把 include 大小写改对即可。
>
> ⚠️ 云端只做"构建 + 体积"（PowerShell 检查脚本在 Linux 上要额外装 pwsh，不划算）；
> 循环包含和格式检查请在**本地**用 `ci.ps1` 跑。

### 用起来的最低成本方案

还没有 git 仓库的话，**先只用 `scripts/ci.ps1`**：

```
改完代码 → 跑一次 scripts/ci.ps1 → 绿了再提交
```

等你把工程推到 GitHub，把 `.github/workflows/ci.yml` 一起推上去就自动生效 ——
它做的是同一件事，只是换了个触发的地方。