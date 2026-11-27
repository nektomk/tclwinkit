# update-manifest.ps1 --
#   Refresh vendor/manifest.json when a new version of a vendor archive is fetched.
#   Re-measures size/sha256, follows the version inside top_dir when the row pins
#   one, and stops with a diagnosis when the archive changed shape instead of
#   silently substituting. kind, patch_chains, movable, url and the component name
#   are hand-maintained: this script never rewrites them, so a change there means
#   editing the manifest by hand.
#
#   What this file is NOT: scripts/fetch-vendor.ps1 remains the authority the
#   build actually runs (source-parity.ps1 reads its rows), and no build or
#   gate script reads vendor/manifest.json -- sources.yml uses its bytes only as
#   part of the vendor cache key. Keeping the two in step is manual until the
#   rows move here; -VerifyOnly checks this manifest against vendor/, not
#   against fetch-vendor.ps1.
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

# Read with an explicit UTF-8 decode: the manifest carries no BOM, and PS 5.1
# falls back to the machine ANSI code page for BOM-less files. ASCII-only today,
# so the two agree -- but a non-ASCII URL would silently corrupt under the default.
$manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
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
# A version bump moves the archive top with it on every row that pins one
# ("tcl9.0.4/" -> "tcl9.0.5/"), so the expectation is the recorded value with the
# same numeric substitution the file name got, not the recorded value verbatim.
# Comparing verbatim aborted the ten versioned rows -- which is the case this
# script exists for (measured 2026-11-27 against a synthetic tcl9.0.5 tar.gz).
# Rows recorded as "" carry no expectation on purpose: four are the movable rows
# (same reason fetch-vendor.ps1 leaves t = '' there: GitHub names the archive top
# after the ref, so the branch and the pinned form differ and a fixed expectation
# would reject one of them); TWAPI's tag is v5.2 while its file is 5.2.0, so its
# top cannot be derived from the version either. With no expectation nothing is
# compared and nothing is written.
$expectedTop = $entry.top_dir
if ($expectedTop) { $expectedTop = $expectedTop -replace '\d+(\.\d+)*', $Version }
if ($expectedTop -and $newTop -ne $expectedTop) {
    $structuralChanges += 'top_dir changed from "' + $entry.top_dir + '" (bump expectation "' + $expectedTop + '") to "' + $newTop + '"'
}

if ($structuralChanges.Count -gt 0) {
    'STRUCTURAL CHANGE DETECTED -- manifest update aborted:'
    $structuralChanges | ForEach-Object { '  - ' + $_ }
    ''
    'If this is intentional, edit vendor/manifest.json by hand and update fetch-vendor.ps1 to match.'
    exit 1
}

$oldFile = $entry.file
$oldTop = $entry.top_dir
$entry.file = $newFile
$entry.size = $newSize
$entry.sha256 = $newSha
# A row recorded as "" is never filled from a probe: that would pin whichever
# ref form happened to be on disk for a movable row, or the un-derivable tag form
# for TWAPI (see the guard above). A versioned row follows the bump.
$hadTop = [bool] $oldTop
if ($hadTop) { $entry.top_dir = $newTop }

# Patch the changed fields inside this component's entry in the raw text
# rather than re-rendering the object: ConvertTo-Json cannot reproduce the
# committed shape in either shell (measured 2026-11-27 -- PS 5.1 indents with 16
# spaces and writes 10287 B for a 6657 B file, and both shells explode the inline
# "patch_chains": ["msvc"] arrays across three lines), so a full rewrite would
# replace a one-line bump with a whole-file diff and a layout that depends on the
# shell. The lookbehinds keep pin_size/pin_sha256 out of the field matches; each
# value written is taken from $entry, which came from the same parse, so key
# order, quoting style and everything else stay untouched.
$text = [System.IO.File]::ReadAllText($ManifestPath, [System.Text.UTF8Encoding]::new($false))
$blockRe = '(\{[^{}]*"component":\s*"' + [regex]::Escape($Component) + '"[^{}]*\})'
$bm = [regex]::Match($text, $blockRe)
if (-not $bm.Success) { throw 'could not locate the ' + $Component + ' entry block in ' + $ManifestPath }
$block = $bm.Value
$newBlock = $block
$newBlock = [regex]::Replace($newBlock, '(?<![a-z_])"file":\s*"[^"]*"', '"file": "' + $entry.file + '"')
$newBlock = [regex]::Replace($newBlock, '(?<![a-z_])"size":\s*[0-9]+', '"size": ' + $entry.size)
$newBlock = [regex]::Replace($newBlock, '(?<!pin_)"sha256":\s*"[^"]*"', '"sha256": "' + $entry.sha256 + '"')
if ($hadTop) {
    $newBlock = [regex]::Replace($newBlock, '"top_dir":\s*"[^"]*"', '"top_dir": "' + $entry.top_dir + '"')
}
$text = $text.Replace($block, $newBlock)

# UTF-8 without BOM, LF endings, trailing newline: vendor/manifest.json is pinned
# eol=lf in .gitattributes and carries no BOM, and check-encoding fails a tracked
# file on either violation (Set-Content -Encoding UTF8 on PS 5.1 prepends a BOM:
# measured first3 239,187,191).
$text = $text -replace "`r`n", "`n"
if (-not $text.EndsWith("`n")) { $text += "`n" }
[System.IO.File]::WriteAllBytes($ManifestPath, [System.Text.UTF8Encoding]::new($false).GetBytes($text))

# Self-check the written file the way make-patches.ps1 does its manifest:
# reparse, and require the entry to carry the new values. A replace that missed
# its regex would otherwise report success while the file kept the old row.
$check = ([System.IO.File]::ReadAllText($ManifestPath, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json).archives |
    Where-Object { $_.component -eq $Component }
if ($check.file -ne $entry.file -or [string]$check.size -ne [string]$entry.size -or $check.sha256 -ne $entry.sha256) {
    throw 'manifest was written but does not read back with the new values for ' + $Component
}
if ($hadTop -and $check.top_dir -ne $entry.top_dir) {
    throw 'manifest was written but top_dir did not change for ' + $Component
}

$Component + ' updated: ' + $oldFile + ' -> ' + $newFile
'size: ' + $entry.size + ' B, sha256: ' + $entry.sha256.Substring(0, 16) + '...'
'Manifest written to ' + $ManifestPath
exit 0
