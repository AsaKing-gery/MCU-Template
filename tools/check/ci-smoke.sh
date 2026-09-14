#!/usr/bin/env bash
# =============================================================================
#  ci-smoke.sh —— 模板端到端冒烟测试
#
#  做什么：
#    在临时目录里「复制模板骨架 → 叠加最小裸机固件 → 编 Debug + Release」，
#    最后断言 .elf / .hex / .bin / .map 都产出了。
#
#  为什么必须这么做（模板仓库 CI 一直红的真实原因）：
#    这个仓库是**骨架**，不是固件工程：
#      * 唯一的源文件 App/Src/app.c 只是个空壳
#      * 没有链接脚本（而 mcu.json 期望 STM32F407VGTx_FLASH.ld）
#      * 没有 newlib 的系统调用桩（_write / _sbrk / _fstat / _isatty / _getpid ...）
#
#    而 mcu.json 里 floatIo=true，CMakeLists.txt 会加
#        -Wl,--undefined=_printf_float -Wl,--undefined=_scanf_float
#    把 newlib-nano 的 stdio 体系强行链进来，上面那些桩就变成**必需的**了。
#    于是直接在仓库里 configure/build 会红在链接阶段：
#        undefined reference to `_getpid'
#        undefined reference to `_fstat'
#        undefined reference to `_isatty'
#        collect2: error: ld returned 1 exit status
#
#    所以 CI 不能"直接在仓库里构建"，而要"复制一份 + 补齐最小固件"再构建。
#    本脚本验证的正是模板的**管道**，而不是业务逻辑：
#      mcu.json 解析 → 架构参数(-mcpu/-mfpu/-mfloat-abi) → 源文件收集
#      → 头文件目录探测 → 编译 → -T 链接脚本 → objcopy 出 .hex/.bin
#      → 彩色固件体积报告
#
#  用法：
#    bash tools/check/ci-smoke.sh
#        临时目录里跑，结束自动清理
#
#    KEEP=1 bash tools/check/ci-smoke.sh
#        保留临时目录，方便事后排查
#
#    SMOKE_WORKDIR=/some/dir bash tools/check/ci-smoke.sh
#        用指定目录当工程目录（CI 里靠它把产物留下来做 artifact）
# =============================================================================
set -euo pipefail

# 模板根：从脚本所在目录往上找 mcu.json
# （脚本在 tools/check/ 下，不能只用一层 ".." 推算）
TPL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$TPL_ROOT/mcu.json" ] && [ "$TPL_ROOT" != "/" ]; do
    TPL_ROOT="$(dirname "$TPL_ROOT")"
done
SMOKE_SRC="$TPL_ROOT/ci/smoke"

if [ ! -d "$SMOKE_SRC" ]; then
    echo "错误：找不到冒烟固件目录 $SMOKE_SRC" >&2
    exit 1
fi

# 要复制进临时工程的条目。
# 必须和 tools/project/new-project.sh 的清单保持一致 —— 这样"新建工程会拿到什么"
# 这件事本身也被 CI 覆盖到了（之前就漏过 .clang-format）。
ENTRIES=".clang-format .clangd .gitignore CMakeLists.txt CMakePresets.json cmake mcu.json tools App .vscode .svd"

if [ -n "${SMOKE_WORKDIR:-}" ]; then
    WORK="$SMOKE_WORKDIR"
    rm -rf "$WORK"
    mkdir -p "$WORK"
    echo "工程目录（指定，产物保留）：$WORK"
elif [ "${KEEP:-0}" = "1" ]; then
    WORK="$(mktemp -d "${TMPDIR:-/tmp}/mcu-smoke-XXXXXX")"
    echo "工程目录（保留）：$WORK"
else
    WORK="$(mktemp -d "${TMPDIR:-/tmp}/mcu-smoke-XXXXXX")"
    trap 'rm -rf "$WORK"' EXIT
fi

echo "==> 1/5 复制模板骨架"
for e in $ENTRIES; do
    if [ -e "$TPL_ROOT/$e" ]; then
        cp -R "$TPL_ROOT/$e" "$WORK/"
        echo "        + $e"
    else
        echo "        - $e  (模板里没有，跳过)"
    fi
done

echo "==> 2/5 叠加最小裸机固件（ci/smoke）"
cp -R "$SMOKE_SRC/." "$WORK/"
find "$WORK/Core" -type f | sed "s|^$WORK/|        |" | sort

cd "$WORK"

echo "==> 3/5 configure + build : Debug"
cmake --preset Debug
cmake --build --preset Debug

echo "==> 4/5 configure + build : Release"
cmake --preset Release
cmake --build --preset Release

echo "==> 5/5 断言产物齐全"
for preset in Debug Release; do
    for ext in elf hex bin map; do
        n="$(ls "build/$preset"/*."$ext" 2>/dev/null | wc -l)"
        if [ "$n" -eq 0 ]; then
            echo "错误：build/$preset 下没有生成 .$ext" >&2
            exit 1
        fi
    done
    echo "        OK  build/$preset/*.{elf,hex,bin,map}"
done

echo
echo "冒烟测试通过：模板骨架 + 最小固件 → Debug/Release 均可构建"
