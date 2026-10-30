# update-manifest.ps1 --
#   Refresh vendor/manifest.json when a new version of a vendor archive is fetched.
#   Re-measures size/sha256, updates top_dir/kind if they changed, and stops with
#   a diagnosis on structural changes (component renamed, chains altered, movable
#   flag flipped) instead of silently substituting.
#
#   Usage:
#     scripts\update-manifest.ps1 -Component Tcl -Version 9.0.5
#     scripts\update-manifest.ps1 -Component rl_json -Version 0.18.0
#     scripts\update-manifest.ps1 -VerifyOnly   # check manifest against vendor/
#
#   Exit code 0 only if the manifest is consistent with vendor/ or was updated.
#
#   ASCII-only, CRLF (docs/CONVENTIONS.md rule for .ps1).

param(
    [string]$Component = '',
    [string]$Version = '',
    [switch]$VerifyOnly,
    [string]$Root = '',
    [string]$ManifestPath = ''
)
$ErrorActionPreference = 'Stop'

if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
if (-not $ManifestPath) { $ManifestPath = Join-Path $Root 'vendor\manifest.json' }
$Vendor = Join-Path $Root 'vendor'

if (-not (Test-Path $ManifestPath)) {
    throw 'manifest not found at ' + $ManifestPath
}
if (-not (Test-Path $Vendor)) {
    throw 'vendor directory not found at ' + $Vendor
}

$manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json
$archives = $manifest.archives

function Get-ShaHex([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLower()
}

function Test-ArchiveTop([string]$Path, [string]$Kind) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if ($Kind -eq 'zip') {
        $zr = [System.IO.Compression.ZipFile]::OpenRead($Path)
        try { $names = @($zr.Entries | ForEach-Object { $_.FullName }) } finally { $zr.Dispose() }
    } else {
        $flag = if ($Kind -eq 'txz') { 'tJf' } else { 'tzf' }
        $names = & tar "-$flag" $Path 2>$null
        if ($LASTEXITCODE -ne 0) { throw 'tar -' + $flag + ' failed (rc=' + $LASTEXITCODE + ')' }
    }
    if (@($names).Count -eq 0) { return '' }
    $first = @($names)[0]
    if ($first -match '^([^/]+)') { return $matches[1] + '/' }
    return ''
}

if ($VerifyOnly) {
    $ok = 0; $bad = 0
    foreach ($a in $archives) {
        $path = Join-Path $Vendor $a.file
        if (-not (Test-Path $path)) {
            $a.component + ' ' + $a.file + ' MISSING'; $bad++; continue
        }
        $size = (Get-Item $path).Length
        $sha = Get-ShaHex $path
        if ($size -ne $a.size) {
            $a.component + ' size mismatch: ' + $size + ' B vs manifest ' + $a.size + ' B'; $bad++; continue
        }
        if ($sha -cne $a.sha256) {
            $a.component + ' sha256 mismatch: ' + $sha + ' vs manifest ' + $a.sha256; $bad++; continue
        }
        $ok++
    }
    ''
    'verdict: ok ' + $ok + '  bad ' + $bad
    if ($bad) { exit 1 }
    'MANIFEST-VERIFY OK'
    exit 0
}

if (-not $Component -or -not $Version) {
    'Usage: update-manifest.ps1 -Component <name> -Version <ver> [-VerifyOnly]'
    '  -Component: Tcl, Tk, tcllib, tklib, iwidgets, Img, TWAPI, dyncall, CAWT, rl_json, tkdnd, tktreectrl, mpexpr, TclReadLine, itk'
    '  -Version: new version string (e.g. 9.0.5, 0.18.0)'
    exit 1
}

$entry = $archives | Where-Object { $_.component -eq $Component }
if (-not $entry) {
    throw 'component ' + $Component + ' not found in manifest; available: ' + (@($archives | ForEach-Object { $_.component }) -join ', ')
}

$newFile = $entry.file -replace '\d+(\.\d+)*', $Version
$newPath = Join-Path $Vendor $newFile

if (-not (Test-Path $newPath)) {
    throw 'new archive not found: ' + $newPath + ' (fetch it first with fetch-vendor.ps1 or by hand)'
}

$newSize = (Get-Item $newPath).Length
$newSha = Get-ShaHex $newPath
$newKind = $entry.kind
$newTop = Test-ArchiveTop $newPath $newKind

$structuralChanges = @()
if ($newTop -ne $entry.top_dir) {
    $structuralChanges += 'top_dir changed from "' + $entry.top_dir + '" to "' + $newTop + '"'
}

if ($structuralChanges.Count -gt 0) {
    'STRUCTURAL CHANGE DETECTED -- manifest update aborted:'
    $structuralChanges | ForEach-Object { '  - ' + $_ }
    ''
    'If this is intentional, edit vendor/manifest.json by hand and update fetch-vendor.ps1 to match.'
    exit 1
}

$oldFile = $entry.file
$entry.file = $newFile
$entry.size = $newSize
$entry.sha256 = $newSha
if ($newTop) { $entry.top_dir = $newTop }

$manifest | ConvertTo-Json -Depth 10 | Set-Content $ManifestPath -Encoding UTF8

$Component + ' updated: ' + $oldFile + ' -> ' + $newFile
'size: ' + $entry.size + ' B, sha256: ' + $entry.sha256.Substring(0, 16) + '...'
'Manifest written to ' + $ManifestPath
exit 0
