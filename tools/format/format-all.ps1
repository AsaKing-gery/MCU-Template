#Requires -Version 5.1
<#
.SYNOPSIS
    Run clang-format over a whole project.

.DESCRIPTION
    Formatting a source tree is a large, mostly whitespace-only change, so this
    script is deliberately conservative:

      * default is a DRY RUN: it only reports what would change
      * -Apply backs every file up to
        %USERPROFILE%\.mcu-template-backup\format-<timestamp>\ before writing
      * the .clang-format style is taken from the project root, falling back to
        the template's own copy, so a project created before this file existed
        still gets formatted consistently

    NOTE: this file is intentionally ASCII-only so that Windows PowerShell 5.1
    parses it correctly regardless of the system code page.

.PARAMETER ProjectRoot
    Project root. Defaults to the parent folder of this script.

.PARAMETER Apply
    Actually write the formatted files (with backup). Without it, dry run.

.PARAMETER ExcludeDirs
    Directories (relative to the project root) that are skipped. Default:
    'Drivers' -- i.e. ST's HAL / CMSIS vendor code.

    Formatting vendor code is almost always a bad idea:
      * you lose the ability to diff against the upstream release
      * re-generating from CubeMX produces a huge, meaningless diff
      * it is by far the biggest source of churn (ST's HAL/CMSIS is ~75 files
        and several hundred thousand lines)
    Pass -ExcludeDirs @() to format absolutely everything.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tools/format/format-all.ps1 -ProjectRoot E:\myproj
    powershell -ExecutionPolicy Bypass -File tools/format/format-all.ps1 -ProjectRoot E:\myproj -Apply
    powershell -ExecutionPolicy Bypass -File tools/format/format-all.ps1 -ProjectRoot E:\myproj -ExcludeDirs Drivers,'sd_card\FATFS'
    powershell -ExecutionPolicy Bypass -File tools/format/format-all.ps1 -ProjectRoot E:\myproj -ExcludeDirs Drivers,'User\Src\Libraries' -ExcludeFiles 'arm_math.h'
#>
[CmdletBinding()]
param(
    [string]$ProjectRoot,
    [switch]$Apply,

    # CI mode: in preview mode, exit non-zero when anything needs reformatting,
    # so a build pipeline can gate on it. Has no effect together with -Apply.
    [switch]$Strict,
    [string[]]$ExcludeDirs = @('Drivers'),

    # Wildcard patterns matched against the file NAME, for vendor code that sits
    # in the middle of your own directories (e.g. ARM's arm_math.h, or a
    # stm32u5xx_ll_*.h copy under User/).
    [string[]]$ExcludeFiles = @()
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

# -----------------------------------------------------------------------------
# Locate clang-format
# -----------------------------------------------------------------------------
function Find-ClangFormat {
    $onPath = Get-Command clang-format -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }

    $globs = @(
        'C:\Program Files\Microsoft Visual Studio\*\*\VC\Tools\Llvm\bin\clang-format.exe'
        'C:\Program Files\Microsoft Visual Studio\*\*\VC\Tools\Llvm\x64\bin\clang-format.exe'
        'C:\Program Files\LLVM\bin\clang-format.exe'
        'C:\Program Files (x86)\LLVM\bin\clang-format.exe'
        '/usr/bin/clang-format*'
        '/usr/local/bin/clang-format*'
        '/opt/homebrew/bin/clang-format*'
    )
    foreach ($g in $globs) {
        $hit = @(Get-ChildItem $g -ErrorAction SilentlyContinue | Sort-Object FullName -Descending)
        if ($hit.Count -gt 0) { return $hit[0].FullName }
    }
    return $null
}

$cf = Find-ClangFormat
if (-not $cf) {
    throw "clang-format not found. Install it (Visual Studio 'C++ Clang tools', 'winget install LLVM.LLVM', or 'apt install clang-format') and re-run."
}

$root = (Resolve-Path -LiteralPath $ProjectRoot).Path

# -----------------------------------------------------------------------------
# Optional per-project exclude list: <root>/.format-exclude
#
#   # comment
#   Drivers/            <- a trailing slash marks a directory to skip
#   Middlewares/
#   sd_card/FATFS/
#   arm_math.h          <- anything else is a file-name glob
#
# Kept in a file rather than always passing -ExcludeDirs, so that running the
# script with no arguments - which is exactly what CI does - already skips your
# vendor code instead of reporting 80+ vendor files as "needs reformatting".
# -----------------------------------------------------------------------------
$excludeFile = Join-Path $root '.format-exclude'
if (Test-Path -LiteralPath $excludeFile) {
    $dirs = New-Object System.Collections.ArrayList
    foreach ($d in $ExcludeDirs) { [void]$dirs.Add($d) }
    $filePatterns = New-Object System.Collections.ArrayList
    foreach ($p in $ExcludeFiles) { [void]$filePatterns.Add($p) }

    foreach ($line in [System.IO.File]::ReadAllLines($excludeFile)) {
        $l = $line.Trim()
        if (-not $l -or $l.StartsWith('#')) { continue }
        if ($l.EndsWith('/') -or $l.EndsWith('\')) {
            $d = $l.TrimEnd('/', '\')
            # compare with normalised separators, otherwise the built-in default
            # ("User\Src\Libraries") and the file entry ("User/Src/Libraries")
            # both survive and get printed twice
            $dn = $d -replace '/', '\'
            $dup = $false
            foreach ($x in $dirs) { if (($x -replace '/', '\') -eq $dn) { $dup = $true; break } }
            if (-not $dup) { [void]$dirs.Add($d) }
        } else {
            [void]$filePatterns.Add($l)
        }
    }
    $ExcludeDirs = $dirs.ToArray()
    $ExcludeFiles = $filePatterns.ToArray()
}

# -----------------------------------------------------------------------------
# Locate the style file
#
# Must be an explicit path: we format a temp copy, so letting clang-format
# search upwards from the copy would never find the project's .clang-format.
# -----------------------------------------------------------------------------
$styleFile = Join-Path $root '.clang-format'
if (-not (Test-Path -LiteralPath $styleFile)) {
    # 兜底：逐级往上找模板自带的 .clang-format。
    # 脚本在 tools/format/ 下，不能再靠一层 ".." 推算模板根。
    $tplStyle = ''
    $probe = $PSScriptRoot
    while ($probe) {
        $cand = Join-Path $probe '.clang-format'
        if (Test-Path -LiteralPath $cand) { $tplStyle = $cand; break }
        $parent = Split-Path -Parent $probe
        if (-not $parent -or $parent -eq $probe) { break }
        $probe = $parent
    }
    if ($tplStyle -and (Test-Path -LiteralPath $tplStyle)) {
        $styleFile = $tplStyle
        $styleNote = ' (fallback: the template copy)'
    } else {
        throw "No .clang-format found in '$root' or next to this script. Copy the template's .clang-format into the project first."
    }
} else {
    $styleNote = ''
}

Write-Host "Project      : $root"
Write-Host "clang-format : $cf"
Write-Host ("Version      : " + ((& $cf --version) | Select-Object -First 1))
Write-Host "Style        : $styleFile$styleNote"
Write-Host ''

# -----------------------------------------------------------------------------
# Collect files
# -----------------------------------------------------------------------------
# NOTE: no '.s' / '.S' here on purpose.
# clang-format has no assembler front end: given a .s file it parses it as C++
# and destroys it. Concretely, ST's startup_stm32xxxx.s comes out with
#   "cpu cortex-m33"  split over two lines   -> Error: unknown cpu `cortex-'
#   ".section .text.Reset_Handler" -> ".section.text.reset_handler"
# which the assembler then rejects. Assembly must never be passed to it.
$sourceExt = @('.c', '.h', '.cpp', '.hpp', '.cc', '.hh')
$files = @(Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object {
        if (-not ($sourceExt -contains $_.Extension.ToLowerInvariant())) { return $false }
        if ($_.FullName -match '[\\/](build|Debug|Release|\.git|\.svn|\.mcu-template-backup)[\\/]') { return $false }
        if ($_.Name -match '^_tmp') { return $false }

        # skip vendor directories such as Drivers/
        # Normalise separators before comparing: .format-exclude is normally
        # written with forward slashes ("User/Src/Libraries/"), while the
        # relative path here uses backslashes on Windows. Comparing them raw
        # silently matches nothing.
        $rel = $_.FullName.Substring($root.Length).TrimStart('\', '/') -replace '/', '\'
        foreach ($d in $ExcludeDirs) {
            $dn = $d.TrimEnd('\', '/') -replace '/', '\'
            if ($rel -like "$dn\*") { return $false }
        }
        foreach ($pat in $ExcludeFiles) {
            if ($_.Name -like $pat) { return $false }
        }
        return $true
    } | Sort-Object FullName)

Write-Host ("Files        : " + $files.Count)
if ($ExcludeDirs.Count -gt 0) {
    Write-Host ("Excluded dirs: " + ($ExcludeDirs -join ', ') + "  (use -ExcludeDirs @() to format everything)")
}
if ($ExcludeFiles.Count -gt 0) {
    Write-Host ("Excluded files: " + ($ExcludeFiles -join ', '))
}
Write-Host ''
if ($files.Count -eq 0) { return }

# -----------------------------------------------------------------------------
# IMPORTANT: Start-Process -ArgumentList does NOT quote array items, so any path
# containing a space ("E:\keil5 project\...") would be split into two argv
# entries. Build one pre-quoted argument string instead.
# -----------------------------------------------------------------------------
$styleArg = '--style=file:"' + $styleFile + '"'

$backupDir = Join-Path $env:USERPROFILE ('.mcu-template-backup\format-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$hasGit = [bool](Get-Command git -ErrorAction SilentlyContinue)
$tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ('fmt-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null

$changedFiles = 0
$addedTotal = 0
$removedTotal = 0
$failed = 0
$pos = 0

foreach ($f in $files) {
    $pos++
    Write-Progress -Activity 'clang-format' -Status $f.FullName.Replace("$root\", '') `
                   -PercentComplete ([int](100.0 * $pos / $files.Count))

    $tmpFile = Join-Path $tmpDir ('x' + $pos + '_' + $f.Name)
    Copy-Item -LiteralPath $f.FullName -Destination $tmpFile -Force

    $p = Start-Process -FilePath $cf -ArgumentList ($styleArg + ' -i "' + $tmpFile + '"') `
                       -NoNewWindow -Wait -PassThru

    if ($p.ExitCode -ne 0) {
        $failed++
        Write-Host ("  [FAIL] " + $f.FullName.Replace("$root\", '')) -ForegroundColor Red
        continue
    }

    $a = [System.IO.File]::ReadAllBytes($f.FullName)
    $b = [System.IO.File]::ReadAllBytes($tmpFile)
    $same = ($a.Length -eq $b.Length) -and ([System.Linq.Enumerable]::SequenceEqual([byte[]]$a, [byte[]]$b))
    if ($same) { continue }

    $changedFiles++

    if ($hasGit) {
        # git writes autocrlf hints to stderr; with ErrorActionPreference=Stop
        # PowerShell would turn that into a terminating error, so relax it here.
        $savedEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $st = & git -c core.autocrlf=false --no-pager diff --no-index --numstat -- $f.FullName $tmpFile 2>&1 |
              Where-Object { [string]$_ -notmatch '^warning:|^fatal:' }
        $ErrorActionPreference = $savedEap
        $first = $st | Select-Object -First 1
        if ($first) {
            $parts = ([string]$first) -split "`t"
            if ($parts.Count -ge 2 -and $parts[0] -match '^\d+$' -and $parts[1] -match '^\d+$') {
                $addedTotal   += [int]$parts[0]
                $removedTotal += [int]$parts[1]
            }
        }
    }

    if ($Apply) {
        $rel = $f.FullName.Replace("$root\", '')
        $dst = Join-Path $backupDir $rel
        $dstDir = Split-Path -Parent $dst
        if (-not (Test-Path -LiteralPath $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
        Copy-Item -LiteralPath $f.FullName -Destination $dst -Force

        [System.IO.File]::WriteAllBytes($f.FullName, $b)
    } else {
        Write-Host ("  would change: " + $f.FullName.Replace("$root\", ''))
    }
}

Write-Progress -Activity 'clang-format' -Completed
Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host ("Files scanned          : {0}" -f $files.Count)
Write-Host ("Files needing reformat : {0}" -f $changedFiles)
if ($failed -gt 0) { Write-Host ("Files that FAILED      : {0}" -f $failed) -ForegroundColor Red }
if ($hasGit -and $changedFiles -gt 0) {
    Write-Host ("Line changes           : +{0} / -{1}" -f $addedTotal, $removedTotal)
}

if (-not $Apply) {
    Write-Host ''
    Write-Host 'DRY RUN - nothing was written. Re-run with -Apply to format (a backup is made first).' -ForegroundColor Yellow
    if ($Strict -and $changedFiles -gt 0) {
        Write-Host ''
        Write-Host "Strict mode: $changedFiles file(s) are not formatted - failing." -ForegroundColor Red
        exit 1
    }
} elseif ($changedFiles -gt 0) {
    Write-Host ''
    Write-Host 'Formatted. Originals backed up to:' -ForegroundColor Green
    Write-Host "  $backupDir"
    Write-Host ''
    Write-Host 'Suggested next steps:'
    Write-Host '  1. Build once and confirm the .bin md5 is unchanged (formatting must not alter codegen)'
    Write-Host '  2. Review the diff - it should be whitespace-only'
    Write-Host '  3. Commit as a dedicated "formatting only" change'
}
