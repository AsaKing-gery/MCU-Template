#!/usr/bin/env bash
# 用模板创建新的 MCU 工程（Linux / macOS 版）
#
# 用法：
#   bash scripts/new-project.sh <目标目录> [芯片]
# 例：
#   bash scripts/new-project.sh ../MyF407 stm32f407vg
#   bash scripts/new-project.sh ../MyCubeProj            # 只用默认芯片，之后自己改 mcu.json
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_ROOT="$(dirname "$SCRIPT_DIR")"

TARGET="${1:-}"
CHIP="${2:-}"

if [[ -z "$TARGET" ]]; then
    echo "用法: bash scripts/new-project.sh <目标目录> [芯片]" >&2
    exit 1
fi

# chip -> device cpu fpu abi linkerScript svd openocdTarget defines
chip_defaults() {
    case "$1" in
        stm32f103c8) echo "STM32F103C8 cortex-m3     none        soft STM32F103C8Tx_FLASH.ld  STM32F103.svd target/stm32f1x.cfg STM32F103xB" ;;
        stm32f401re) echo "STM32F401RE cortex-m4     fpv4-sp-d16 hard STM32F401RETx_FLASH.ld STM32F401.svd target/stm32f4x.cfg STM32F401xE" ;;
        stm32f407vg) echo "STM32F407VG cortex-m4     fpv4-sp-d16 hard STM32F407VGTx_FLASH.ld STM32F407.svd target/stm32f4x.cfg STM32F407xx" ;;
        stm32f411ce) echo "STM32F411CE cortex-m4     fpv4-sp-d16 hard STM32F411CEUx_FLASH.ld STM32F411.svd target/stm32f4x.cfg STM32F411xE" ;;
        stm32f429zi) echo "STM32F429ZI cortex-m4     fpv4-sp-d16 hard STM32F429ZITx_FLASH.ld STM32F429.svd target/stm32f4x.cfg STM32F429xx" ;;
        stm32f446re) echo "STM32F446RE cortex-m4     fpv4-sp-d16 hard STM32F446RETx_FLASH.ld STM32F446.svd target/stm32f4x.cfg STM32F446xx" ;;
        stm32f746zg) echo "STM32F746ZG cortex-m7     fpv5-sp-d16 hard STM32F746ZGTx_FLASH.ld STM32F746.svd target/stm32f7x.cfg STM32F746xx" ;;
        stm32h743zi) echo "STM32H743ZI cortex-m7     fpv5-d16    hard STM32H743ZITx_FLASH.ld STM32H743.svd target/stm32h7x.cfg STM32H743xx" ;;
        stm32g071rb) echo "STM32G071RB cortex-m0plus none        soft STM32G071RBTx_FLASH.ld STM32G071.svd target/stm32g0x.cfg STM32G071xx" ;;
        stm32g431rb) echo "STM32G431RB cortex-m4     fpv4-sp-d16 hard STM32G431RBTx_FLASH.ld STM32G431.svd target/stm32g4x.cfg STM32G431xx" ;;
        stm32l431rc) echo "STM32L431RC cortex-m4     fpv4-sp-d16 hard STM32L431RCTx_FLASH.ld STM32L431.svd target/stm32l4x.cfg STM32L431xx" ;;
        *) return 1 ;;
    esac
}

if [[ -n "$CHIP" ]]; then
    if ! DEFAULTS="$(chip_defaults "$(echo "$CHIP" | tr '[:upper:]' '[:lower:]')")"; then
        echo "未知芯片 '$CHIP'。可用：stm32f103c8 stm32f401re stm32f407vg stm32f411ce stm32f429zi stm32f446re stm32f746zg stm32h743zi stm32g071rb stm32g431rb stm32l431rc" >&2
        exit 1
    fi
    read -r DEVICE CPU FPU ABI LDSCRIPT SVD OPENOCD DEF_HAL DEF_MCU <<< "$DEFAULTS"
else
    DEVICE=STM32F407VG; CPU=cortex-m4; FPU=fpv4-sp-d16; ABI=hard
    LDSCRIPT=STM32F407VGTx_FLASH.ld; SVD=STM32F407.svd; OPENOCD=target/stm32f4x.cfg
    DEF_HAL=USE_HAL_DRIVER; DEF_MCU=STM32F407xx
fi

mkdir -p "$TARGET"

echo "[new-project] 复制模板文件到 $TARGET"
for entry in .vscode cmake scripts App .svd .clangd .gitignore CMakeLists.txt CMakePresets.json; do
    if [[ -e "$TEMPLATE_ROOT/$entry" ]]; then
        cp -R "$TEMPLATE_ROOT/$entry" "$TARGET/"
        echo "  + $entry"
    fi
done

MCU_JSON="$TARGET/mcu.json"
if [[ -f "$MCU_JSON" ]]; then
    echo "[new-project] 已存在 mcu.json，保持不变"
else
    cat > "$MCU_JSON" <<EOF
{
  "name": "$DEVICE",
  "device": "$DEVICE",
  "cpu": "$CPU",
  "fpu": "$FPU",
  "floatAbi": "$ABI",
  "linkerScript": "$LDSCRIPT",
  "svd": "$SVD",
  "openocdTarget": "$OPENOCD",
  "defines": [
    "$DEF_HAL",
    "$DEF_MCU"
  ]
}
EOF
    echo "  + mcu.json ($DEVICE)"
fi

bash "$TARGET/scripts/sync-mcu.sh" "$TARGET"

echo ""
echo "[new-project] 完成：$TARGET"
echo "下一步："
echo "  1. 用 STM32CubeMX 在该目录生成代码（Toolchain 建议选 Makefile）"
echo "  2. 把 CubeMX 生成的 .ld 放到工程根目录（或改 mcu.json 的 linkerScript）"
echo "  3. 把 SVD 放进 .svd/ 目录（可选）"
echo "  4. VSCode 打开该目录，Ctrl+Shift+B 构建"
