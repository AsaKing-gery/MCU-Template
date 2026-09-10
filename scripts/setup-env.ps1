#Requires -Version 5.1
<#
.SYNOPSIS
    One-time Windows environment setup for this template.

.DESCRIPTION
    Makes `cmake`, `ninja` and `openocd` usable from a plain terminal (which is what
    the tasks in tasks.json use), and sets OPENOCD_SCRIPTS so that ST's bundled
    OpenOCD can find interface/stlink.cfg.

    What it does:
      1. Locates cmake / ninja / openocd (existing PATH entries first, then common
         install locations such as Visual Studio and STM32CubeIDE)
      2. Adds only the missing directories to the *User* PATH
      3. Sets the User variable OPENOCD_SCRIPTS when the OpenOCD build needs it
      4. Backs everything up to %USERPROFILE%\.mcu-template-backup\ before writing

    The toolchain (arm-none-eabi-gcc) is deliberately NOT added to PATH: the CMake
    toolchain file auto-detects CubeIDE / CubeCLT / Arm installations, so nothing
    needs configuring and a CubeIDE upgrade will not break it.

    NOTE: this file is intentionally ASCII-only so that Windows PowerShell 5.1
    parses it correctly regardless of the system code page.

    IMPORTANT: `setx PATH ...` is deliberately NOT used - setx truncates at 1024
    characters and would destroy a long PATH. The .NET API used here does not.

.PARAMETER DryRun
    Show what would change without writing anything.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts/setup-env.ps1 -DryRun
    powershell -ExecutionPolicy Bypass -File scripts/setup-env.ps1
#>
[CmdletBinding()]
param(
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

# Return the newest matching path for a set of wildcard patterns (or $null).
# Note: always wrap in @(...) before indexing - a one-element pipeline result is
# a scalar, and scalar[0] would return a single character.
function Find-NewestPath {
    param([string[]]$Patterns)
    foreach ($pattern in $Patterns) {
        $hits = @(Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue)
        if ($hits.Count -gt 0) {
            $sorted = @($hits | ForEach-Object { $_.FullName } | Sort-Object -Descending)
            return $sorted[0]
        }
    }
    return $null
}

# Is <Exe> reachable through any of the given PATH entries? Returns that entry.
function Find-InPathEntries {
    param([string]$Exe, [string[]]$Entries)
    foreach ($e in $Entries) {
        if ($e -and $e.Trim() -ne '' -and (Test-Path -LiteralPath (Join-Path $e $Exe))) {
            return $e
        }
    }
    return $null
}

function Write-Info {
    param([string]$Message, [string]$Color = 'Gray')
    Write-Host $Message -ForegroundColor $Color
}

# -----------------------------------------------------------------------------
# 1. Read the persistent PATH (what a freshly opened terminal will see)
# -----------------------------------------------------------------------------
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (-not $userPath) { $userPath = '' }
$machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
if (-not $machinePath) { $machinePath = '' }
$oldScripts = [Environment]::GetEnvironmentVariable('OPENOCD_SCRIPTS', 'User')

$userParts = @($userPath -split ';' | Where-Object { $_ -and $_.Trim() -ne '' } | Select-Object -Unique)
$machineParts = @($machinePath -split ';' | Where-Object { $_ -and $_.Trim() -ne '' })
$allParts = @($userParts + $machineParts | Select-Object -Unique)

Write-Info "== Looking for cmake / ninja / openocd ==" -Color Cyan

# -----------------------------------------------------------------------------
# 2. cmake
# -----------------------------------------------------------------------------
$cmakeDir = Find-InPathEntries 'cmake.exe' $allParts
if (-not $cmakeDir) {
    $vsRoot = Find-NewestPath @(
        'C:\Program Files\Microsoft Visual Studio\*\*\Common7\IDE\CommonExtensions\Microsoft\CMake'
        'C:\Program Files (x86)\Microsoft Visual Studio\*\*\Common7\IDE\CommonExtensions\Microsoft\CMake'
    )
    if ($vsRoot) {
        foreach ($cand in @("$vsRoot\CMake\bin", "$vsRoot\bin", $vsRoot)) {
            if (Test-Path -LiteralPath (Join-Path $cand 'cmake.exe')) { $cmakeDir = $cand; break }
        }
    }
    if (-not $cmakeDir) {
        foreach ($cand in @(
                (Find-NewestPath @('C:\Program Files\CMake\bin', 'C:\Program Files (x86)\CMake\bin')),
                (Find-NewestPath @('C:\Program Files\CMake\*', 'C:\Program Files (x86)\CMake\*')))) {
            if ($cand -and (Test-Path -LiteralPath (Join-Path $cand 'cmake.exe'))) { $cmakeDir = $cand; break }
        }
    }
}

# -----------------------------------------------------------------------------
# 3. ninja
# -----------------------------------------------------------------------------
$ninjaDir = Find-InPathEntries 'ninja.exe' $allParts
if (-not $ninjaDir) {
    $ninjaDir = Find-NewestPath @(
        'C:\Program Files\Microsoft Visual Studio\*\*\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja'
        'C:\Program Files (x86)\Microsoft Visual Studio\*\*\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja'
    )
    if ($ninjaDir -and -not (Test-Path -LiteralPath (Join-Path $ninjaDir 'ninja.exe'))) { $ninjaDir = $null }
}

# -----------------------------------------------------------------------------
# 4. openocd (+ where its scripts live)
# -----------------------------------------------------------------------------
$openocdDir = Find-InPathEntries 'openocd.exe' $allParts
if (-not $openocdDir) {
    $cand = Find-NewestPath @(
        'C:\ST\STM32CubeIDE_*\STM32CubeIDE\plugins\com.st.stm32cube.ide.mcu.externaltools.openocd.*\tools\bin'
        'C:\Program Files\STMicroelectronics\STM32Cube\STM32CubeIDE\plugins\com.st.stm32cube.ide.mcu.externaltools.openocd.*\tools\bin'
        'C:\ST\STM32CubeCLT_*\OpenOCD\bin'
        'C:\Program Files\xpack-openocd-*\bin'
    )
    if ($cand -and (Test-Path -LiteralPath (Join-Path $cand 'openocd.exe'))) { $openocdDir = $cand }
}

$ocdScripts = $null
if ($openocdDir) {
    # A standard build ships its scripts next to the binary; ST's build does not.
    foreach ($guess in @(
            (Join-Path $openocdDir 'scripts'),
            (Join-Path (Split-Path -Parent $openocdDir) 'share\openocd\scripts'))) {
        if (Test-Path -LiteralPath (Join-Path $guess 'interface\stlink.cfg')) { $ocdScripts = $guess; break }
    }
    if (-not $ocdScripts) {
        $guess = Find-NewestPath @(
            'C:\ST\STM32CubeIDE_*\STM32CubeIDE\plugins\com.st.stm32cube.ide.mcu.debug.openocd_*\resources\openocd\st_scripts'
            'C:\Program Files\STMicroelectronics\STM32Cube\STM32CubeIDE\plugins\com.st.stm32cube.ide.mcu.debug.openocd_*\resources\openocd\st_scripts'
            'C:\ST\STM32CubeCLT_*\OpenOCD\share\openocd\scripts'
        )
        if ($guess -and (Test-Path -LiteralPath (Join-Path $guess 'interface\stlink.cfg'))) { $ocdScripts = $guess }
    }
}

# -----------------------------------------------------------------------------
# 5. Report + work out the diff
# -----------------------------------------------------------------------------
$entries = @(
    [pscustomobject]@{ Name = 'cmake';   Dir = $cmakeDir;   Exe = 'cmake.exe' }
    [pscustomobject]@{ Name = 'ninja';   Dir = $ninjaDir;   Exe = 'ninja.exe' }
    [pscustomobject]@{ Name = 'openocd'; Dir = $openocdDir; Exe = 'openocd.exe' }
)

$toAdd = @()
foreach ($e in $entries) {
    if (-not $e.Dir) {
        $hint = switch ($e.Name) {
            'cmake'   { 'install CMake, or the VS "C++ CMake tools" workload' }
            'ninja'   { 'install Ninja, e.g. "pip install ninja"' }
            'openocd' { 'only needed for flashing/debugging with OpenOCD (J-Link users can skip)' }
            default   { 'install it' }
        }
        Write-Info ("  {0,-8}: not found  ({1})" -f $e.Name, $hint) -Color Yellow
        continue
    }
    if ($userParts -contains $e.Dir) {
        Write-Info ("  {0,-8}: ready      {1}" -f $e.Name, $e.Dir) -Color Green
    } elseif ($machineParts -contains $e.Dir) {
        Write-Info ("  {0,-8}: ready (system PATH)  {1}" -f $e.Name, $e.Dir) -Color Green
    } else {
        Write-Info ("  {0,-8}: will add   {1}" -f $e.Name, $e.Dir) -Color Green
        $toAdd += $e.Dir
    }
}
if ($ocdScripts) { Write-Info ("  {0,-8}: {1}" -f 'scripts', $ocdScripts) -Color Green }

$scriptsChanged = [bool]($ocdScripts -and ($oldScripts -ne $ocdScripts))
if ($toAdd.Count -eq 0 -and -not $scriptsChanged) {
    Write-Info ""
    Write-Info "Everything is already in place. Nothing to do." -Color Green
    return
}

Write-Info ""
Write-Info "== Planned changes ==" -Color Cyan
$toAdd | ForEach-Object { Write-Info "  User PATH += $_" }
if ($scriptsChanged) {
    Write-Info "  OPENOCD_SCRIPTS = $ocdScripts"
    if ($oldScripts) { Write-Info "  (was: $oldScripts)" -Color DarkGray }
}

if ($DryRun) {
    Write-Info ""
    Write-Info "DryRun: nothing was written." -Color Yellow
    return
}

# -----------------------------------------------------------------------------
# 6. Back up, then write
# -----------------------------------------------------------------------------
$backupDir = Join-Path $env:USERPROFILE '.mcu-template-backup'
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
$backupFile = Join-Path $backupDir ("env-{0}.txt" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
@"
# MCU-Template environment backup
# Restore with PowerShell:
#   `$line = (Get-Content '<this file>' | Where-Object { `$_ -like 'PATH=*' }) -replace '^PATH=',''
#   [Environment]::SetEnvironmentVariable('Path', `$line, 'User')
#   [Environment]::SetEnvironmentVariable('OPENOCD_SCRIPTS', '', 'User')
PATH=$userPath
OPENOCD_SCRIPTS=$oldScripts
"@ | Set-Content -LiteralPath $backupFile -Encoding UTF8
Write-Info ""
Write-Info "Backup: $backupFile" -Color Cyan

$newPath = (@($userParts) + $toAdd) -join ';'

# Safety net: never write a shorter User PATH than before (guards against truncation)
if ($newPath.Length -lt $userPath.Length) {
    throw "Aborted: the new User PATH would be shorter than the old one ($($userPath.Length) -> $($newPath.Length))."
}

[Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
if ($scriptsChanged) {
    [Environment]::SetEnvironmentVariable('OPENOCD_SCRIPTS', $ocdScripts, 'User')
}

Write-Info ""
Write-Info "== Done ==" -Color Green
Write-Info "  User PATH: $($userPath.Length) -> $($newPath.Length) chars"
if ($scriptsChanged) { Write-Info "  OPENOCD_SCRIPTS = $ocdScripts" }
Write-Info ""
Write-Info "Restart VS Code (all windows) and open a new terminal for the changes to take effect." -Color Yellow
