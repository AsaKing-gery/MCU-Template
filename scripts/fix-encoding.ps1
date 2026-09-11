#Requires -Version 5.1
<#
.SYNOPSIS
    Find (and optionally convert) source files that are not valid UTF-8.

.DESCRIPTION
    Why this matters:

      * GCC does not care about source encoding. A GBK-encoded comment is just
        bytes to it, so the project builds perfectly.
      * clangd (the language server behind the editor) REQUIRES UTF-8. On a
        non-UTF-8 file it reports "invalid UTF-8" and gives up, which shows up
        as hundreds of red errors in the editor while `cmake --build` stays
        green.

    This is the classic Chinese-Windows situation: files created by Keil or
    CubeIDE on a zh-CN system are often saved as GBK (code page 936).

    The script reports every non-UTF-8 file, and separately flags the ones
    where Chinese text sits INSIDE a string literal -- those are the only ones
    whose runtime behaviour changes when converted (the bytes sent to a serial
    port / LCD become UTF-8 instead of GBK).

    NOTE: this file is intentionally ASCII-only so that Windows PowerShell 5.1
    parses it correctly regardless of the system code page.

.PARAMETER ProjectRoot
    Project root. Defaults to the parent folder of this script.

.PARAMETER CodePage
    Code page of the existing files. 936 = GBK/GB2312 (Simplified Chinese),
    950 = Big5 (Traditional Chinese), 932 = Shift-JIS. Default 936.

.PARAMETER Apply
    Actually convert the files to UTF-8 (without BOM). Without this switch the
    script only reports; nothing is modified.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts/fix-encoding.ps1
    powershell -ExecutionPolicy Bypass -File scripts/fix-encoding.ps1 -Apply
#>
[CmdletBinding()]
param(
    [string]$ProjectRoot,
    [int]$CodePage = 936,
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# $PSScriptRoot is NOT reliably populated while parameters are being bound
# (under Windows PowerShell 5.1 it was observed to be empty here), so the
# default is resolved in the body instead. Falling back to the current
# directory also makes it work when launched as a VSCode task, where the
# working directory is already the project root.
if (-not $ProjectRoot) {
    $ProjectRoot = if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot } else { (Get-Location).Path }
}

# -----------------------------------------------------------------------------
# Get the legacy code page encoder (PowerShell 7 needs the provider registered)
# -----------------------------------------------------------------------------
try {
    $legacy = [System.Text.Encoding]::GetEncoding($CodePage)
} catch {
    try {
        [System.Text.Encoding]::RegisterProvider([System.Text.CodePagesEncodingProvider]::Instance)
        $legacy = [System.Text.Encoding]::GetEncoding($CodePage)
    } catch {
        throw "Cannot load code page $CodePage. Run this script with Windows PowerShell 5.1 (powershell.exe) instead of PowerShell 7 (pwsh.exe)."
    }
}

$utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)
$utf8NoBom  = New-Object System.Text.UTF8Encoding($false)

$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
Write-Host "Project: $root"
Write-Host "Code page: $CodePage"

# NOTE: -Include does not work together with -LiteralPath, so filter explicitly.
$sourceExt = @('.c', '.h', '.s', '.cpp', '.hpp')
$files = @(Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue |
           Where-Object {
               $sourceExt -contains $_.Extension.ToLowerInvariant() -and
               $_.FullName -notmatch '[\\/](build|Debug|Release)[\\/]'
           })

$bad = New-Object System.Collections.ArrayList
foreach ($f in $files) {
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    $ok = $true
    try { [void]$utf8Strict.GetString($bytes) } catch { $ok = $false }
    if (-not $ok) { [void]$bad.Add($f) }
}

Write-Host ("Scanned: {0} files, not valid UTF-8: {1}" -f $files.Count, $bad.Count)

if ($bad.Count -eq 0) {
    Write-Host 'All good, nothing to do.' -ForegroundColor Green
    return
}

# Chinese (or any CJK) inside "..." changes runtime bytes when converted
$runtimeAffected = New-Object System.Collections.ArrayList
foreach ($f in $bad) {
    $text = $legacy.GetString([System.IO.File]::ReadAllBytes($f.FullName))
    $hits = [regex]::Matches($text, '"[^"\r\n]*[\u3000-\u9fff\uff00-\uffef][^"\r\n]*"')
    if ($hits.Count -gt 0) {
        [void]$runtimeAffected.Add([pscustomobject]@{ File = $f; Count = $hits.Count; Sample = $hits[0].Value })
    }
}

Write-Host ''
Write-Host '--- CJK inside string literals (runtime output changes if converted) ---' -ForegroundColor Yellow
Write-Host '    Review these first: if the text goes to a serial port / LCD, the'
Write-Host '    receiving side must also switch to UTF-8.'
if ($runtimeAffected.Count -eq 0) {
    Write-Host '    (none - conversion is completely behaviour neutral)'
} else {
    foreach ($r in $runtimeAffected) {
        Write-Host ("    {0,3} literal(s)  {1}" -f $r.Count, $r.File.FullName.Replace("$root\", ''))
        Write-Host ("             e.g. " + $r.Sample)
    }
}

Write-Host ''
Write-Host '--- all non-UTF-8 files ---'
foreach ($f in $bad) { Write-Host ("  " + $f.FullName.Replace("$root\", '')) }

if (-not $Apply) {
    Write-Host ''
    Write-Host 'Dry run: nothing was modified. Re-run with -Apply to convert to UTF-8 (no BOM).' -ForegroundColor Yellow
    return
}

# -----------------------------------------------------------------------------
# Convert, with a backup
# -----------------------------------------------------------------------------
$backupDir = Join-Path $env:USERPROFILE ('.mcu-template-backup\encoding-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
Write-Host ''
Write-Host "Backing up originals to $backupDir"
$converted = 0
foreach ($f in $bad) {
    $rel = $f.FullName.Replace("$root\", '')
    $dst = Join-Path $backupDir $rel
    $dstDir = Split-Path -Parent $dst
    if (-not (Test-Path -LiteralPath $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
    Copy-Item -LiteralPath $f.FullName -Destination $dst -Force

    $text = $legacy.GetString([System.IO.File]::ReadAllBytes($f.FullName))
    # Normalise line endings to CRLF->LF is NOT done on purpose: keep the file
    # byte-identical apart from the encoding of the non-ASCII characters.
    [System.IO.File]::WriteAllText($f.FullName, $text, $utf8NoBom)
    $converted++
}

Write-Host ("Converted {0} files to UTF-8 (no BOM)." -f $converted) -ForegroundColor Green
Write-Host ''
Write-Host 'Next steps:'
Write-Host '  1. Build once to confirm the firmware is still identical.'
Write-Host '  2. If any of the string-literal files drive a display or a serial'
Write-Host '     terminal, switch that consumer to UTF-8.'
Write-Host '  3. Restart the clangd language server (or reload the window).'
