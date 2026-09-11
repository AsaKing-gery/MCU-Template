#Requires -Version 5.1
<#
.SYNOPSIS
    Detect circular #include chains among the project's own headers.

.DESCRIPTION
    Why this is worth checking:

      Include guards make a cycle compile happily, so it can sit in a codebase
      for years unnoticed. But an editor language server (clangd) cannot build
      a preamble for a header that is part of a cycle and reports

          pp_including_mainfile_in_preamble
          "main file cannot be included recursively when building a preamble"

      which silently disables completion / go-to-definition for those headers.
      That is exactly the kind of paper cut that eats an afternoon.

    The graph is built from quoted includes only ("foo.h"), because those are
    the project's own files. Angle-bracket includes (<stdio.h>) are system or
    toolchain headers and are ignored.

    Vendor directories are excluded by default - their internal structure is
    not yours to fix, and scanning them just produces noise.

    NOTE: this file is intentionally ASCII-only so that Windows PowerShell 5.1
    parses it correctly regardless of the system code page.

.PARAMETER ProjectRoot
    Project root. Defaults to the parent of this script's folder, falling back
    to the current directory.

.PARAMETER ExcludeDirs
    Vendor directories to skip, relative to the project root.

.PARAMETER ExcludeFiles
    File-name wildcard patterns to skip (vendor code that sits inside your own
    directories, such as ARM's arm_math.h).

.PARAMETER NoExcludes
    Scan absolutely everything, including vendor directories.

    This switch exists because passing an empty array does not survive a
    `powershell -File script.ps1 -ExcludeDirs @()` invocation (PowerShell drops
    the parameter and complains about a missing argument), so `-NoExcludes` is
    the portable way to say "no exclusions".

.PARAMETER MaxCycles
    Stop after this many cycles (keeps the output readable). Default 50.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts/check-includes.ps1
    powershell -ExecutionPolicy Bypass -File scripts/check-includes.ps1 -ProjectRoot E:\myproj
#>
[CmdletBinding()]
param(
    [string]$ProjectRoot,
    [string[]]$ExcludeDirs = @('Drivers', 'User\Src\Libraries', 'sd_card\FATFS'),
    [string[]]$ExcludeFiles = @('arm_math.h'),
    [switch]$NoExcludes,
    [int]$MaxCycles = 50
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($NoExcludes) {
    $ExcludeDirs = @()
    $ExcludeFiles = @()
}

if (-not $ProjectRoot) {
    $ProjectRoot = if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot } else { (Get-Location).Path }
}

# Optional per-project exclude list, shared with format-all.ps1:
#   # comment
#   Drivers/        <- trailing slash = directory
#   arm_math.h      <- otherwise a file-name glob
$excludeFile = Join-Path $ProjectRoot '.format-exclude'
if (-not $NoExcludes -and (Test-Path -LiteralPath $excludeFile)) {
    $dirs = New-Object System.Collections.ArrayList
    foreach ($d in $ExcludeDirs) { [void]$dirs.Add($d) }
    $pats = New-Object System.Collections.ArrayList
    foreach ($p in $ExcludeFiles) { [void]$pats.Add($p) }
    foreach ($line in [System.IO.File]::ReadAllLines($excludeFile)) {
        $l = $line.Trim()
        if (-not $l -or $l.StartsWith('#')) { continue }
        if ($l.EndsWith('/') -or $l.EndsWith('\')) {
            $d = $l.TrimEnd('/', '\')
            # normalise separators so "User\Src\Libraries" and "User/Src/Libraries"
            # are recognised as the same entry
            $dn = $d -replace '/', '\'
            $dup = $false
            foreach ($x in $dirs) { if (($x -replace '/', '\') -eq $dn) { $dup = $true; break } }
            if (-not $dup) { [void]$dirs.Add($d) }
        } else {
            [void]$pats.Add($l)
        }
    }
    $ExcludeDirs = $dirs.ToArray()
    $ExcludeFiles = $pats.ToArray()
}
$root = (Resolve-Path -LiteralPath $ProjectRoot).Path

# -----------------------------------------------------------------------------
# 1. Collect our own sources
# -----------------------------------------------------------------------------
$files = @(Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object {
        if (@('.c', '.h') -notcontains $_.Extension.ToLowerInvariant()) { return $false }
        if ($_.FullName -match '[\\/](build|Debug|Release|\.git|\.svn)[\\/]') { return $false }
        if ($_.Name -match '^_tmp') { return $false }
        # Normalise separators: .format-exclude usually uses forward slashes,
        # the relative path here uses backslashes on Windows.
        $rel = $_.FullName.Substring($root.Length).TrimStart('\', '/') -replace '/', '\'
        foreach ($d in $ExcludeDirs) {
            $dn = $d.TrimEnd('\', '/') -replace '/', '\'
            if ($rel -like "$dn\*") { return $false }
        }
        foreach ($p in $ExcludeFiles) {
            if ($_.Name -like $p) { return $false }
        }
        return $true
    })

Write-Host "Scanned  : $($files.Count) files under $root"
if ($ExcludeDirs.Count -gt 0) { Write-Host "Skipped  : $($ExcludeDirs -join ', ')" }

# -----------------------------------------------------------------------------
# 2. name -> paths, so a quoted include can be resolved
#    (same-name duplicates are possible, e.g. a vendor copy of an LL header;
#     the compiler would pick whichever -I comes first, we pick the first hit
#     and remember the ambiguity so it can be reported)
# -----------------------------------------------------------------------------
$byName = @{}
foreach ($f in $files) {
    $k = $f.Name.ToLowerInvariant()
    if (-not $byName.ContainsKey($k)) { $byName[$k] = New-Object System.Collections.ArrayList }
    [void]$byName[$k].Add($f.FullName)
}

# -----------------------------------------------------------------------------
# 3. Build the graph
# -----------------------------------------------------------------------------
$graph = @{}
$dupNames = @{}
foreach ($f in $files) {
    $text = [System.IO.File]::ReadAllText($f.FullName)
    $inc = New-Object System.Collections.ArrayList
    foreach ($m in [regex]::Matches($text, '#[ \t]*include[ \t]+"([^"]+)"')) {
        $name = $m.Groups[1].Value
        if ($name -match '[\\/]') {
            # relative include such as "sub/foo.h" - resolve against this file's folder
            $cand = Join-Path (Split-Path -Parent $f.FullName) $name
            if (Test-Path -LiteralPath $cand) { [void]$inc.Add((Resolve-Path -LiteralPath $cand).Path) }
            continue
        }
        $base = Split-Path -Leaf $name
        $key = $base.ToLowerInvariant()
        if (-not $byName.ContainsKey($key)) { continue }        # system / external

        # prefer a header sitting next to the includer (matches the preprocessor)
        $sameDir = Join-Path (Split-Path -Parent $f.FullName) $base
        $target = $null
        if (Test-Path -LiteralPath $sameDir) { $target = (Resolve-Path -LiteralPath $sameDir).Path }
        else { $target = $byName[$key][0] }

        if ($byName[$key].Count -gt 1) { $dupNames[$key] = $byName[$key].Count }
        if ($target -and -not $inc.Contains($target)) { [void]$inc.Add($target) }
    }
    $graph[$f.FullName] = $inc
}

Write-Host "Graph    : $($graph.Count) nodes, $(($graph.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum) edges"
if ($dupNames.Count -gt 0) {
    Write-Host "Note     : $($dupNames.Count) header name(s) exist in more than one place:"
    foreach ($k in ($dupNames.Keys | Sort-Object)) { Write-Host "             $k  ($($dupNames[$k]) copies)" }
}
Write-Host ''

# -----------------------------------------------------------------------------
# 4. Find cycles (DFS with an explicit recursion stack)
# -----------------------------------------------------------------------------
$script:state = @{}
$script:stack = New-Object System.Collections.ArrayList
$script:cycles = New-Object System.Collections.ArrayList
$script:seen = @{}

function Visit-Node {
    param([string]$node)

    $script:state[$node] = 1
    [void]$script:stack.Add($node)

    foreach ($nxt in $script:graph[$node]) {
        $s = 0
        if ($script:state.ContainsKey($nxt)) { $s = $script:state[$nxt] }

        if ($s -eq 0) {
            Visit-Node -node $nxt
        }
        elseif ($s -eq 1) {
            # back edge -> cycle from $nxt to the top of the stack
            $start = $script:stack.IndexOf($nxt)
            if ($start -ge 0) {
                $cyc = @($script:stack[$start..($script:stack.Count - 1)])
                $key = (($cyc | Sort-Object) -join '|')
                if (-not $script:seen.ContainsKey($key)) {
                    $script:seen[$key] = $true
                    [void]$script:cycles.Add($cyc)
                }
            }
        }
    }

    [void]$script:stack.RemoveAt($script:stack.Count - 1)
    $script:state[$node] = 2
}

foreach ($node in @($graph.Keys)) {
    $s = 0
    if ($script:state.ContainsKey($node)) { $s = $script:state[$node] }
    if ($s -eq 0) { Visit-Node -node $node }
    if ($script:cycles.Count -ge $MaxCycles) { break }
}

# -----------------------------------------------------------------------------
# 5. Report
# -----------------------------------------------------------------------------
if ($script:cycles.Count -eq 0) {
    Write-Host 'No circular includes found.' -ForegroundColor Green
    exit 0
}

Write-Host "Found $($script:cycles.Count) circular include chain(s):" -ForegroundColor Yellow
Write-Host ''
$i = 0
foreach ($cyc in $script:cycles) {
    $i++
    Write-Host "  [$i] $($cyc.Count) files:" -ForegroundColor Yellow
    foreach ($p in $cyc) { Write-Host "      $($p.Substring($root.Length).TrimStart('\','/'))" }
    Write-Host "      -> back to $((Split-Path -Leaf $cyc[0]))"
    Write-Host ''
}

Write-Host 'How to fix: pick the edge whose includer does not actually use anything'
Write-Host 'from the included header, drop it, and if some .c file relied on getting'
Write-Host 'it transitively, add the include there explicitly.'
exit 1
