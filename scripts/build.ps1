#Requires -Version 5.1
<#
.SYNOPSIS
    One-key build with readable, coloured output.

.DESCRIPTION
    Wraps `cmake --build` because two things make the raw output hard to read:

      1. Console code page
         On a Chinese Windows the console defaults to code page 936 (GBK),
         while CMake emits UTF-8, so the Chinese text in CMake's messages
         turns into garbage characters.
         This script switches to UTF-8 (code page 65001) and sets the .NET
         console encodings, so the build output comes out readable.

      2. ANSI colours are stripped
         ninja removes ANSI escape sequences whenever its output is not a
         terminal. Everything that goes through ninja (compiler diagnostics,
         POST_BUILD steps) therefore loses its colour.
         This script prints its OWN summary at the end - that part does not go
         through ninja, so its colour is guaranteed to survive.

    The build itself is streamed unchanged, so you still see progress live and
    the VSCode `$gcc` problem matcher still fills the Problems panel.

    NOTE: this file is intentionally ASCII-only so that Windows PowerShell 5.1
    parses it correctly regardless of the system code page.

.PARAMETER Preset
    Debug (default) or Release.

.PARAMETER Rebuild
    Wipe the build output first (cmake --build --clean-first). Same as Keil's
    Rebuild button.

.PARAMETER Flash
    Run the `flash` target (OpenOCD / ST-Link) after a successful build.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts/build.ps1
    powershell -ExecutionPolicy Bypass -File scripts/build.ps1 -Preset Release
    powershell -ExecutionPolicy Bypass -File scripts/build.ps1 -Rebuild
    powershell -ExecutionPolicy Bypass -File scripts/build.ps1 -Flash
#>
[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Preset = 'Debug',

    [switch]$Rebuild,
    [switch]$Flash
)

$ErrorActionPreference = 'Continue'
Set-StrictMode -Version Latest

# See the note in sync-mcu.ps1: $PSScriptRoot is not always populated, so fall
# back to the current directory - which is the project root for a VSCode task.
$root   = if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot } else { (Get-Location).Path }
$binDir = Join-Path $root ("build\" + $Preset)

# -----------------------------------------------------------------------------
# 1. UTF-8 everywhere, otherwise CMake's Chinese messages are unreadable
# -----------------------------------------------------------------------------
$utf8 = New-Object System.Text.UTF8Encoding($false)
try { [Console]::OutputEncoding = $utf8 } catch { }
try { [Console]::InputEncoding  = $utf8 } catch { }
try { $OutputEncoding = $utf8 } catch { }

if ($env:OS -eq 'Windows_NT') {
    # chcp changes the whole console, so the terminal that renders this output
    # also decodes the following bytes as UTF-8.
    & chcp.com 65001 > $null 2>&1
}

# -----------------------------------------------------------------------------
# 2. Colours
#
#    Note the deliberate choice of ANSI escapes over Write-Host -ForegroundColor:
#    VSCode's terminal renders both, but ANSI also works in any other terminal
#    and inside plain text the codes are easy to grep for.
# -----------------------------------------------------------------------------
$esc    = [string][char]27
$cTitle = "$esc[1;36m"   # cyan bold
$cOk    = "$esc[1;32m"   # green bold
$cWarn  = "$esc[1;33m"   # yellow bold
$cErr   = "$esc[1;31m"   # red bold
$cKey   = "$esc[36m"
$cDim   = "$esc[2m"
$cOff   = "$esc[0m"

# -----------------------------------------------------------------------------
# 3. Configure + build (streamed)
# -----------------------------------------------------------------------------
$label = "Build ($Preset"
if ($Rebuild) { $label += ", clean-first" }
$label += ")"

Write-Host ""
Write-Host "$cTitle=== $label ===$cOff"

$cmakeArgs = @('--build', '--preset', $Preset)
if ($Rebuild) { $cmakeArgs += '--clean-first' }

$warnings = 0
$errors   = New-Object System.Collections.ArrayList
$exitCode = 0

# Silence the POST_BUILD size report for this run: it goes through ninja, which
# strips the colour, and we print our own coloured one in step 4 anyway.
$env:MCU_SIZE_QUIET = '1'

Push-Location $root
try {
    & cmake @cmakeArgs 2>&1 | ForEach-Object {
        $line = [string]$_
        Write-Host $line

        if ($line -match '^\s*\S+:\d+:\d+:\s*(warning|error):' -or $line -match ':\s*warning:') {
            if ($line -match ':\s*error:') { [void]$errors.Add($line) } else { $warnings++ }
        }
        elseif ($line -match 'FAILED:|ninja: build stopped') {
            [void]$errors.Add($line)
        }
    }
    $exitCode = $LASTEXITCODE
}
finally {
    Pop-Location
}

# -----------------------------------------------------------------------------
# 4. Firmware size report, printed by THIS script
#
#    Deliberately not left to the POST_BUILD step: that one runs inside ninja,
#    which strips the colour away. Here it survives.
# -----------------------------------------------------------------------------

# the build is over, our own report must be allowed to speak
Remove-Item Env:\MCU_SIZE_QUIET -ErrorAction SilentlyContinue

$elfPath = $null
if (Test-Path -LiteralPath $binDir) {
    $found = @(Get-ChildItem -LiteralPath $binDir -Filter '*.elf' -ErrorAction SilentlyContinue |
               Sort-Object LastWriteTime -Descending)
    if ($found.Count -gt 0) { $elfPath = $found[0].FullName }
}

if ($elfPath -and $exitCode -eq 0) {
    # cmake wrote where the tools are into the cache; reuse that instead of
    # re-implementing the toolchain lookup here.
    $sizeExe = $null
    $ldScript = $null
    $cache = Join-Path $binDir 'CMakeCache.txt'
    if (Test-Path -LiteralPath $cache) {
        foreach ($line in [System.IO.File]::ReadAllLines($cache)) {
            if ($line -like 'CMAKE_SIZE:FILEPATH=*')          { $sizeExe  = $line.Substring($line.IndexOf('=') + 1) }
            if ($line -like 'MCU_LDSCRIPT_FILE:FILEPATH=*')   { $ldScript = $line.Substring($line.IndexOf('=') + 1) }
        }
    }

    if ($sizeExe -and (Test-Path -LiteralPath $sizeExe)) {
        $mapPath = [System.IO.Path]::ChangeExtension($elfPath, '.map')
        & cmake `
            "-DSIZE=$sizeExe" `
            "-DELF=$elfPath" `
            "-DMAP=$mapPath" `
            "-DLDSCRIPT=$ldScript" `
            '-DMCU_COLOR_OUTPUT=ON' `
            -P (Join-Path $root 'cmake\report_size.cmake')
    }
}

# -----------------------------------------------------------------------------
# 5. Coloured summary
# -----------------------------------------------------------------------------
Write-Host ""
if ($exitCode -eq 0) {
    Write-Host "$cOk=== BUILD SUCCEEDED ===$cOff"
} else {
    Write-Host "$cErr=== BUILD FAILED (exit $exitCode) ===$cOff"
}

if ($errors.Count -gt 0) {
    Write-Host "$cErr$($errors.Count) error line(s):$cOff"
    $errors | Select-Object -First 10 | ForEach-Object { Write-Host "  $cErr$_$cOff" }
    if ($errors.Count -gt 10) {
        Write-Host "  $cDim... and $($errors.Count - 10) more$cOff"
    }
}

if ($warnings -gt 0) {
    Write-Host "$cWarn$warnings warning line(s)$cOff $cDim- press Ctrl+Shift+M for the Problems panel$cOff"
} elseif ($exitCode -eq 0) {
    Write-Host "$cDimno warnings$cOff"
}

# -----------------------------------------------------------------------------
# 6. Optional flash
# -----------------------------------------------------------------------------
if ($Flash) {
    if ($exitCode -ne 0) {
        Write-Host "$cWarn-build failed, skipping flash$cOff"
    } else {
        Write-Host ""
        Write-Host "$cTitle=== Flash (OpenOCD / ST-Link) ===$cOff"
        Push-Location $root
        try {
            & cmake --build --preset $Preset --target flash 2>&1 | ForEach-Object { Write-Host ([string]$_) }
            $flashExit = $LASTEXITCODE
        }
        finally {
            Pop-Location
        }
        if ($flashExit -eq 0) {
            Write-Host "$cOk=== FLASH OK ===$cOff"
        } else {
            Write-Host "$cErr=== FLASH FAILED (exit $flashExit) ===$cOff"
            $exitCode = $flashExit
        }
    }
}

Write-Host ""
exit $exitCode
