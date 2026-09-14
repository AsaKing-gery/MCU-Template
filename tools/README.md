# `tools/` —— 工具脚本索引

模板里的脚本按**用途**分组，**代码（`App/`）和工具完全分开**。
不知道跑哪个，就先看这张表。

> 所有脚本都可以随处运行：它会**从自己所在目录逐级往上找 `mcu.json`** 来确定工程根，
> 所以换个位置、被复制到新工程里都不会失效（详见文末）。

---

## 一、建工程（只做一次）

| 脚本 | 什么时候用 |
|---|---|
| `project/new-project.ps1` / `project/new-project.sh` | **新建工程**，或把模板应用到已有的 CubeMX 工程 |

```powershell
# 全新工程
powershell -ExecutionPolicy Bypass -File tools/project/new-project.ps1 ..\MyF407 -Chip stm32f407vg
# 套用到已有工程（不会覆盖已有的 mcu.json）
powershell -ExecutionPolicy Bypass -File tools/project/new-project.ps1 ..\MyCubeProj -Chip stm32g431rb
```

```bash
bash tools/project/new-project.sh ../MyF407 stm32f407vg
```

---

## 二、环境准备（只做一次）

| 脚本 | 什么时候用 |
|---|---|
| `env/setup-env.ps1` | 把 Arm 工具链 / CMake / Ninja / OpenOCD / clang-format 写进用户 `PATH` |

```powershell
powershell -ExecutionPolicy Bypass -File tools/env/setup-env.ps1 -DryRun   # 先看会改什么
powershell -ExecutionPolicy Bypass -File tools/env/setup-env.ps1           # 确认后执行
```

> 改完 **要重启 VSCode**，新的 `PATH` 才会生效。

---

## 三、日常开发

| 脚本 | 什么时候用 |
|---|---|
| `project/sync-mcu.ps1` / `.sh` | 改了 `mcu.json` 之后，把芯片信息刷进 `.vscode/launch.json` |
| `build/build.ps1` | 命令行构建（约等于 `Ctrl+Shift+B`，但额外修中文乱码并打印彩色摘要） |
| `format/format-all.ps1` | 全工程 clang-format。**默认只预览**，加 `-Apply` 才写盘（会先备份） |
| `format/fix-encoding.ps1` | 找出（并可转换）GBK 编码的源文件 —— clangd 只认 UTF-8 |

```powershell
powershell -ExecutionPolicy Bypass -File tools/project/sync-mcu.ps1
powershell -ExecutionPolicy Bypass -File tools/format/format-all.ps1
powershell -ExecutionPolicy Bypass -File tools/format/format-all.ps1 -Apply
```

> 日常大多数操作直接用 VSCode 任务就行（`Ctrl+Shift+P` → `Run Task`）。
> 这些脚本就是那些任务背后真正执行的东西。

---

## 四、检查 / CI

| 脚本 | 什么时候用 |
|---|---|
| `check/ci.ps1` | **提交前跑这个**：循环包含 → 格式检查 → Debug/Release 都编一遍 → 体积统计 |
| `check/check-includes.ps1` | 只查循环包含。比完整 CI 快得多，而且会打印**每一个环的完整路径** |
| `check/ci-smoke.sh` | 云端 CI 用的模板冒烟测试（在临时目录里复制模板 + 最小固件并编译），本地一般不用跑 |

```powershell
powershell -ExecutionPolicy Bypass -File tools/check/ci.ps1
powershell -ExecutionPolicy Bypass -File tools/check/check-includes.ps1
```

常用开关：

```powershell
# 打开体积门禁：FLASH / RAM 超过 90% 就返回非 0
powershell -ExecutionPolicy Bypass -File tools/check/ci.ps1 -MaxFlashPercent 90 -MaxRamPercent 90
# 只编 Debug
powershell -ExecutionPolicy Bypass -File tools/check/ci.ps1 -Presets Debug
# 跳过某一项
powershell -ExecutionPolicy Bypass -File tools/check/ci.ps1 -SkipFormat
```

---

## 五、为什么这些脚本可以随便挪

它们**不靠"数 `..` 的层数"**来定位工程根，而是从自己所在目录**逐级往上找 `mcu.json`**：

```
tools/check/ci.ps1
  └─ tools/check/   有 mcu.json 吗？  没有
     └─ tools/      有吗？            没有
        └─ <工程根>/ 有吗？           有！就是这里
```

所以以后再怎么调整 `tools/` 下的目录结构，都不用回头改脚本。

> 顺带一提：`.clangd`、`.vscode/`、`cmake/` 这些也都是靠**固定约定**找的，
> 只有 `mcu.json` 是那个"锚点"。删掉它，脚本会明确报错而不是猜错路径。

---

## 六、目录约定

```
tools/
├── project/   建工程、同步 mcu.json → launch.json
├── env/       一次性环境配置
├── build/     构建
├── format/    格式化、编码转换
└── check/     检查与 CI
```

新增脚本时，**按用途丢进对应目录**即可；如果它需要定位工程根，
把这段照抄进去（PowerShell）：

```powershell
# 从脚本所在目录逐级往上找，第一个含 mcu.json 的目录就是工程根
$ProjectRoot = $PSScriptRoot
if (-not $ProjectRoot) { $ProjectRoot = (Get-Location).Path }
while (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot 'mcu.json'))) {
    $parent = Split-Path -Parent $ProjectRoot
    if (-not $parent -or $parent -eq $ProjectRoot) { $ProjectRoot = (Get-Location).Path; break }
    $ProjectRoot = $parent
}
```

Bash 版本：

```bash
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$PROJECT_ROOT/mcu.json" ] && [ "$PROJECT_ROOT" != "/" ]; do
    PROJECT_ROOT="$(dirname "$PROJECT_ROOT")"
done
```
