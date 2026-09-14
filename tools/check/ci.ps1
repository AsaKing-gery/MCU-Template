#Requires -Version 5.1
<#
.SYNOPSIS
    Local CI pipeline for this MCU project.

.DESCRIPTION
    What CI can and cannot do for embedded firmware:

      CAN do (pure software, no hardware needed)
        * prove that Debug AND Release still compile
        * catch firmware size regressions (FLASH / RAM budget)
        * catch circular includes - they compile fine thanks to include guards
          but silently break the editor's completion
        * enforce clang-format
        * keep the .elf / .hex / .bin of every revision around

      CANNOT do (needs the board)
        * flashing, on-target tests, hardware in the loop

    Run this before you commit. .github/workflows/ci.yml runs the same checks on
    a runner, so "green locally" means "green in CI".

    NOTE: this file is intentionally ASCII-only so that Windows PowerShell 5.1
    parses it correctly regardless of the system code page.

.PARAMETER ProjectRoot
    Project root. Defaults to the parent of this script's folder, falling back
    to the current directory.

.PARAMETER Presets
    Which configurations to build. Default: Debug and Release.

.PARAMETER MaxFlashPercent
    Fail if FLASH usage exceeds this percentage of the region size.
    0 (the default) disables the check.

.PARAMETER MaxRamPercent
    Same for RAM. 0 disables.

.PARAMETER SkipFormat
    Skip the clang-format check.

.PARAMETER SkipIncludes
    Skip the circular-include check.

.PARAMETER Fresh
    Delete the CMake cache before configuring, i.e. a truly clean build.
    Slower, but that is what a CI machine does.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/check/ci.ps1
    powershell -ExecutionPolicy Bypass -File tools/check/ci.ps1 -Fresh -MaxFlashPercent 90
#>
[CmdletBinding()]
param(
    [string]$ProjectRoot,
    [ValidateSet('Debug', 'Release')]
    [string[]]$Presets = @('Debug', 'Release'),
    [int]$MaxFlashPercent = 0,
    [int]$MaxRamPercent = 0,
    [switch]$SkipFormat,
    [switch]$SkipIncludes,
    [switch]$Fresh
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

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
$root = (Resolve-Path -LiteralPath $ProjectRoot).Path

# -----------------------------------------------------------------------------
# Colours (only when asked for, so redirected CI logs stay readable)
# -----------------------------------------------------------------------------
if ($env:MCU_COLOR_OUTPUT) {
    $esc = [string][char]27
    $cT = "$esc[1;36m"
    $cK = "$esc[1;32m"
    $cW = "$esc[1;33m"
    $cE = "$esc[1;31m"
    $cD = "$esc[2m"
    $cX = "$esc[0m"
} else {
    $cT = ''
    $cK = ''
    $cW = ''
    $cE = ''
    $cD = ''
    $cX = ''
}

$script:results = New-Object System.Collections.ArrayList

function Add-Result {
    param([string]$Name, [string]$Status, [string]$Detail = '')
    [void]$script:results.Add([pscustomobject]@{ Name = $Name; Status = $Status; Detail = $Detail })
}

function Write-Head {
    param([string]$Text)
    Write-Host ''
    Write-Host ("$cT=== $Text ===$cX")
}

Write-Host "$cT=== CI: $root ===$cX"
Write-Host "$cD    presets: $($Presets -join ', ')$cX"

$failed = 0

# -----------------------------------------------------------------------------
# 1. circular includes
# -----------------------------------------------------------------------------
if (-not $SkipIncludes) {
    Write-Head '1/4  circular includes'
    $checker = Join-Path $PSScriptRoot 'check-includes.ps1'
    if (-not (Test-Path -LiteralPath $checker)) {
        Write-Host "$cW    check-includes.ps1 not found - skipped$cX"
        Add-Result 'circular includes' 'SKIP' 'script missing'
    } else {
        & $checker -ProjectRoot $root
        if ($LASTEXITCODE -eq 0) { Add-Result 'circular includes' 'PASS' }
        else { Add-Result 'circular includes' 'FAIL' "$LASTEXITCODE cycle(s) or error"; $failed++ }
    }
} else {
    Add-Result 'circular includes' 'SKIP' '-SkipIncludes'
}

# -----------------------------------------------------------------------------
# 2. formatting
# -----------------------------------------------------------------------------
if (-not $SkipFormat) {
    Write-Head '2/4  clang-format'
    # format-all 挪到了同级的 format/ 目录，所以这里要跨一层
    $fmt = Join-Path $PSScriptRoot '../format/format-all.ps1'
    if (-not (Test-Path -LiteralPath $fmt)) {
        Write-Host "$cW    format-all.ps1 not found - skipped$cX"
        Add-Result 'clang-format' 'SKIP' 'script missing'
    } else {
        & $fmt -ProjectRoot $root -Strict
        if ($LASTEXITCODE -eq 0) { Add-Result 'clang-format' 'PASS' }
        else { Add-Result 'clang-format' 'FAIL' 'files need reformatting'; $failed++ }
    }
} else {
    Add-Result 'clang-format' 'SKIP' '-SkipFormat'
}

# -----------------------------------------------------------------------------
# 3. build every preset
# -----------------------------------------------------------------------------
foreach ($preset in $Presets) {
    Write-Head "3/4  build ($preset)"

    $cfgArgs = @('--preset', $preset)
    if ($Fresh) { $cfgArgs += '--fresh' }
    Push-Location $root
    & cmake @cfgArgs 2>&1 | Out-String | Write-Host
    $cfgExit = $LASTEXITCODE

    if ($cfgExit -ne 0) {
        Add-Result "configure ($preset)" 'FAIL' "cmake exit $cfgExit"
        $failed++
        Pop-Location
        continue
    }
    Add-Result "configure ($preset)" 'PASS'

    $log = & cmake --build --preset $preset 2>&1 | Out-String
    $buildExit = $LASTEXITCODE
    Write-Host $log

    $warnCount = ([regex]::Matches($log, ':\s*warning:')).Count
    $errCount = ([regex]::Matches($log, ':\s*error:|FAILED:')).Count

    if ($buildExit -ne 0) {
        Add-Result "build ($preset)" 'FAIL' "$errCount error line(s)"
        $failed++
    } else {
        $detail = "$warnCount warning(s)"
        if ($warnCount -gt 0) { Add-Result "build ($preset)" 'PASS' $detail }
        else { Add-Result "build ($preset)" 'PASS' 'clean' }
    }
    Pop-Location
}

# -----------------------------------------------------------------------------
# 4. firmware size
# -----------------------------------------------------------------------------
Write-Head '4/4  firmware size'

foreach ($preset in $Presets) {
    $binDir = Join-Path $root ("build\$preset")
    $elf = @(Get-ChildItem -LiteralPath $binDir -Filter '*.elf' -ErrorAction SilentlyContinue |
             Sort-Object LastWriteTime -Descending)
    if ($elf.Count -eq 0) {
        Write-Host "$cD    ($preset) no .elf - skipped$cX"
        Add-Result "size ($preset)" 'SKIP' 'no .elf'
        continue
    }

    # the tool location is already in the CMake cache
    $sizeExe = $null
    $cache = Join-Path $binDir 'CMakeCache.txt'
    if (Test-Path -LiteralPath $cache) {
        foreach ($line in [System.IO.File]::ReadAllLines($cache)) {
            if ($line -like 'CMAKE_SIZE:FILEPATH=*') { $sizeExe = $line.Substring($line.IndexOf('=') + 1); break }
        }
    }
    if (-not $sizeExe -or -not (Test-Path -LiteralPath $sizeExe)) {
        Write-Host "$cW    ($preset) arm-none-eabi-size not found$cX"
        Add-Result "size ($preset)" 'SKIP' 'size tool missing'
        continue
    }

    $out = & $sizeExe $elf[0].FullName 2>&1 | Out-String
    $lines = ($out -split "`r?`n") | Where-Object { $_.Trim() -ne '' }
    if ($lines.Count -lt 2) { Add-Result "size ($preset)" 'SKIP' 'unparsable size output'; continue }
    $nums = [regex]::Matches($lines[1], '[0-9]+') | ForEach-Object { [int]$_.Value }
    if ($nums.Count -lt 3) { Add-Result "size ($preset)" 'SKIP' 'unparsable size output'; continue }

    $text = $nums[0]; $data = $nums[1]; $bss = $nums[2]
    $flashUsed = $text + $data
    $ramUsed = $data + $bss

    # region sizes from the linker map
    $flashTotal = 0; $ramTotal = 0
    $map = [System.IO.Path]::ChangeExtension($elf[0].FullName, '.map')
    if (Test-Path -LiteralPath $map) {
        $mapRaw = [System.IO.File]::ReadAllText($map)
        $m1 = [regex]::Match($mapRaw, '(^|\n)[ \t]*FLASH[ \t]+0x[0-9a-fA-F]+[ \t]+0x([0-9a-fA-F]+)')
        if ($m1.Success) { $flashTotal = [Convert]::ToInt64($m1.Groups[2].Value, 16) }
        $m2 = [regex]::Match($mapRaw, '(^|\n)[ \t]*RAM[ \t]+0x[0-9a-fA-F]+[ \t]+0x([0-9a-fA-F]+)')
        if ($m2.Success) { $ramTotal = [Convert]::ToInt64($m2.Groups[2].Value, 16) }
    }

    $fp = if ($flashTotal -gt 0) { [math]::Round(100.0 * $flashUsed / $flashTotal, 2) } else { -1 }
    $rp = if ($ramTotal -gt 0) { [math]::Round(100.0 * $ramUsed / $ramTotal, 2) } else { -1 }

    $flashTxt = if ($fp -ge 0) { "$flashUsed / $flashTotal B  ($fp%)" } else { "$flashUsed B" }
    $ramTxt = if ($rp -ge 0) { "$ramUsed / $ramTotal B  ($rp%)" } else { "$ramUsed B" }
    Write-Host "    FLASH : $flashTxt"
    Write-Host "    RAM   : $ramTxt"

    $over = $false
    if ($MaxFlashPercent -gt 0 -and $fp -ge 0 -and $fp -gt $MaxFlashPercent) {
        Write-Host "$cE    FLASH over budget: $fp% > $MaxFlashPercent%$cX"; $over = $true
    }
    if ($MaxRamPercent -gt 0 -and $rp -ge 0 -and $rp -gt $MaxRamPercent) {
        Write-Host "$cE    RAM over budget: $rp% > $MaxRamPercent%$cX"; $over = $true
    }

    if ($over) { Add-Result "size ($preset)" 'FAIL' "FLASH $fp% / RAM $rp%"; $failed++ }
    else { Add-Result "size ($preset)" 'PASS' "FLASH $fp% / RAM $rp%" }
}

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
Write-Head 'summary'
foreach ($r in $script:results) {
    $col = switch ($r.Status) {
        'PASS' { $cK }
        'FAIL' { $cE }
        'SKIP' { $cD }
        default { '' }
    }
    Write-Host ("  {0,-6} {1,-22} {2}" -f "$col$($r.Status)$cX", $r.Name, "$cD$($r.Detail)$cX")
}

Write-Host ''
if ($failed -eq 0) {
    Write-Host "$cK=== CI PASSED ===$cX"
    exit 0
}
Write-Host "$cE=== CI FAILED ($failed check(s)) ===$cX"
exit 1
