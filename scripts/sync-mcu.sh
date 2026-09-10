#!/usr/bin/env bash
# 把 mcu.json 里的芯片参数同步到 .vscode/launch.json（Linux / macOS 版）
#
# 采用正则原地替换，保留 launch.json 原有的排版与注释。
# 用法：bash scripts/sync-mcu.sh [工程根目录]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${1:-$(dirname "$SCRIPT_DIR")}"

if ! command -v python3 >/dev/null 2>&1; then
    echo "需要 python3 才能解析 mcu.json，请先安装。" >&2
    exit 1
fi

python3 - "$PROJECT_ROOT" <<'PY'
import json
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
mcu_path = root / "mcu.json"
launch_path = root / ".vscode" / "launch.json"

if not mcu_path.is_file():
    sys.exit(f"找不到 {mcu_path}")
if not launch_path.is_file():
    sys.exit(f"找不到 {launch_path}")

mcu = json.loads(mcu_path.read_text(encoding="utf-8"))

# ${workspaceFolder} 必须保持字面量，所以用字符串拼接
svd_path = "${workspaceFolder}/.svd/" + mcu["svd"]

# 产物名 = 工程目录名，按 CMakeLists.txt 里完全相同的规则消毒
# （CMake 的 target 名不允许空格和括号，构建时会换成下划线）
artifact = re.sub(r"[^A-Za-z0-9_.+-]", "_", root.resolve().name) or "mcu_firmware"
exe_path = "${workspaceFolder}/build/Debug/" + artifact + ".elf"

raw = original = launch_path.read_text(encoding="utf-8")


def set_json_string(text: str, key: str, value: str) -> str:
    pattern = r'"%s"\s*:\s*"[^"]*"' % re.escape(key)
    # 用 lambda 作为替换内容，避免 value 里的反斜杠被当成转义序列
    return re.sub(pattern, lambda _m: '"%s": "%s"' % (key, value), text)


raw = set_json_string(raw, "device", mcu["device"])
raw = set_json_string(raw, "svdFile", svd_path)
raw = set_json_string(raw, "executable", exe_path)
raw = re.sub(r'"target/[^"]*[.]cfg"', lambda _m: '"%s"' % mcu["openocdTarget"], raw)

if raw == original:
    print("[sync-mcu] launch.json 已是最新")
else:
    launch_path.write_text(raw, encoding="utf-8", newline="\n")
    print(f"[sync-mcu] 已更新 {launch_path}")

print(f"[sync-mcu] device={mcu['device']}  svd={mcu['svd']}  openocd={mcu['openocdTarget']}")

if not (root / ".svd" / mcu["svd"]).is_file():
    print(f"[sync-mcu] 提示：.svd/{mcu['svd']} 还不存在，放进去后调试面板才能看外设寄存器。")
PY
