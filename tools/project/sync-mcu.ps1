#Requires -Version 5.1
<#
.SYNOPSIS
    Sync chip settings from mcu.json into .vscode/launch.json.

.DESCRIPTION
    The CMake toolchain file reads mcu.json automatically, but VSCode's launch.json
    cannot include external files. Run this script after editing mcu.json to refresh
    device / svdFile / configFiles / executable in every debug configuration.

    Values are patched in place with regular expressions, so the original layout,
    ordering and comments in launch.json are preserved (the file stays diff-friendly).

    NOTE: this file is intentionally ASCII-only so that Windows PowerShell 5.1
    parses it correctly regardless of the system code page.

.PARAMETER ProjectRoot
    Project root directory. Defaults to the parent folder of this script.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/project/sync-mcu.ps1
#>
[CmdletBinding()]
param(
    [string]$ProjectRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# $PSScriptRoot is NOT reliably populated while parameters are being bound
# (under Windows PowerShell 5.1 it was observed to be empty here), so the
# default is resolved in the body instead. Falling back to the current
# directory also makes it work when launched as a VSCode task, where the
# working directory is already the project root.
if (-not $ProjectRoot) {
    # 从脚本所在目录逐级往上找，第一个含 mcu.json 的目录就是工程根。
    # 这样脚本在 tools/ 子树里怎么挪都不会失效 —— 比数 ".." 的层数可靠得多。
    $ProjectRoot = $PSScriptRoot
    if (-not $ProjectRoot) { $ProjectRoot = (Get-Location).Path }
    while (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot 'mcu.json'))) {
        $parent = Split-Path -Parent $ProjectRoot
        if (-not $parent -or $parent -eq $ProjectRoot) { $ProjectRoot = (Get-Location).Path; break }
        $ProjectRoot = $parent
    }
}

$mcuPath    = Join-Path $ProjectRoot 'mcu.json'
$launchPath = Join-Path $ProjectRoot '.vscode/launch.json'

if (-not (Test-Path -LiteralPath $mcuPath)) {
    throw "mcu.json not found: $mcuPath"
}
if (-not (Test-Path -LiteralPath $launchPath)) {
    throw "launch.json not found: $launchPath"
}

$mcu = Get-Content -LiteralPath $mcuPath -Raw | ConvertFrom-Json

# '${workspaceFolder}' must stay literal, so build these with single quotes.
$svdPath = '${workspaceFolder}/.svd/' + $mcu.svd

# Artifact name = project folder name, sanitised exactly the same way as in
# CMakeLists.txt (CMake target names may not contain spaces or parentheses, so
# the build renames them to '_'). Keep both sides in sync here.
$dirName = Split-Path -Leaf (Resolve-Path -LiteralPath $ProjectRoot).Path
$artifact = $dirName -replace '[^A-Za-z0-9_.+-]', '_'
if (-not $artifact) { $artifact = 'mcu_firmware' }
$exePath = '${workspaceFolder}/build/Debug/' + $artifact + '.elf'

# Swap a "key": "value" pair without touching the rest of the file.
# '$' is escaped for the .NET replacement string so that '${workspaceFolder}'
# is not mistaken for a named group reference.
function Set-JsonString {
    param(
        [string]$Text,
        [string]$Key,
        [string]$Value
    )
    $pattern     = '"' + [regex]::Escape($Key) + '"\s*:\s*"[^"]*"'
    $replacement = '"' + $Key + '": "' + $Value.Replace('$', '$$') + '"'
    return [regex]::Replace($Text, $pattern, $replacement)
}

$raw = [System.IO.File]::ReadAllText($launchPath, [System.Text.Encoding]::UTF8)

$before = $raw
$raw = Set-JsonString -Text $raw -Key 'device'     -Value $mcu.device
$raw = Set-JsonString -Text $raw -Key 'svdFile'    -Value $svdPath
$raw = Set-JsonString -Text $raw -Key 'executable' -Value $exePath

# The second entry of configFiles is the OpenOCD target script, e.g. "target/stm32f4x.cfg"
$raw = [regex]::Replace($raw, '"target/[^"]*[.]cfg"', '"' + $mcu.openocdTarget + '"')

if ($raw -eq $before) {
    Write-Host "[sync-mcu] launch.json already up to date" -ForegroundColor DarkGray
} else {
    # UTF-8 without BOM, otherwise launch.json fails to parse
    [System.IO.File]::WriteAllText($launchPath, $raw, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "[sync-mcu] updated $launchPath"
}

Write-Host "[sync-mcu] device=$($mcu.device)  svd=$($mcu.svd)  openocd=$($mcu.openocdTarget)" -ForegroundColor Green

$svdFull = Join-Path $ProjectRoot (".svd/" + $mcu.svd)
if (-not (Test-Path -LiteralPath $svdFull)) {
    Write-Host "[sync-mcu] hint: .svd/$($mcu.svd) does not exist yet - put the SVD there to get the peripheral register view." -ForegroundColor Yellow
}
