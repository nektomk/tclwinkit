# build-release-archives.ps1 -- pack the shipped executables into one
# deterministic archive per toolchain:
#
#   build\release-stage\tclwinkit-<chain>-<version>.zip
#
#   pwsh -File scripts\build-release-archives.ps1 [-KeepStale]
#
# Why archives. The executables are named for what they are (tclwin.exe,
# tkwin.exe), not for which compiler produced them, so that a user who unpacks
# an archive gets files that can go on PATH as they are and need no renaming.
# The toolchain and the version are then carried by the archive name and by the
# single top-level directory inside it, which is also what keeps a download
# folder readable and stops two toolchains from silently overwriting each other
# when both are unpacked into the same directory.
#
# Determinism. Entries are written through scripts\zip-entry.ps1, so every
# timestamp -- directory entries included -- is the pinned DOS epoch, and the
# entry order is ordinal. Two runs over the same executables therefore produce
# identical bytes, which is what makes a published SHA-256 of the archive
# something a third party can reproduce and check.
#
# Requires dist\<chain>\ to be populated, i.e. assemble-msvc-kit.ps1 and
# assemble-mingw-kit.ps1 have been run. Nothing here touches dist\.

[CmdletBinding()]
param(
    [string]$Root = '',
    [switch]$KeepStale
)
$ErrorActionPreference = 'Stop'

# $PSScriptRoot is not populated during parameter binding on Windows
# PowerShell 5.1, so the default is resolved in the body, not in param().
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }

# PowerShell 5.1 splits the ZIP types over two assemblies: ZipArchive lives in
# System.IO.Compression, ZipFile in System.IO.Compression.FileSystem. Loading
# only one produces a TypeNotFound at the first use rather than at the load, so
# both are loaded and then asserted (same approach as verify-docs-artifact.ps1).
foreach ($asm in @('System.IO.Compression', 'System.IO.Compression.FileSystem')) {
    try { Add-Type -AssemblyName $asm | Out-Null } catch { }
}
foreach ($t in @('System.IO.Compression.ZipFile', 'System.IO.Compression.ZipArchive')) {
    if (-not ([System.Management.Automation.PSTypeName]$t).Type) { throw "type unavailable: $t" }
}

# Deterministic entry writers (pinned timestamps) and the ordinal walk.
. "$Root\scripts\zip-entry.ps1"

$Dist   = "$Root\dist"
$Stage  = "$Root\build\release-stage"
$Chains = @('msvc', 'mingw')

# Only these names may ever be packed. Without the list, a stray file left in
# dist\<chain>\ by an interrupted build would be published under a checksum
# that looks authoritative, and the archive would carry something nobody meant
# to ship.
$Allowed  = @('tclwin.exe', 'tkwin.exe', 'tclsafe.exe', 'tksafe.exe')
$Required = @('tclwin.exe', 'tkwin.exe')

$Ver = (Select-String -Path "$Root\src\kit\vfs\lib\kit_init.tcl" `
        -Pattern 'variable version\s+(\S+)' | Select-Object -First 1).Matches[0].Groups[1].Value
if ($Ver -notmatch '^[0-9]+(\.[0-9]+)*$') {
    throw "cannot read the version from src\kit\vfs\lib\kit_init.tcl (got '$Ver')"
}
"version: $Ver"
"output:  $Stage"

New-Item -ItemType Directory -Force $Stage | Out-Null

$built = @()
foreach ($chain in $Chains) {
    $srcDir = Join-Path $Dist $chain
    if (-not (Test-Path -LiteralPath $srcDir)) {
        throw "no such directory: $srcDir (run assemble-$chain-kit.ps1 first)"
    }

    $have    = @(Get-ChildItem -LiteralPath $srcDir -File | ForEach-Object { $_.Name })
    $stray   = @($have | Where-Object { $Allowed -notcontains $_ })
    $missing = @($Required | Where-Object { $have -notcontains $_ })
    if ($stray.Count)   { throw "unexpected file(s) in dist\$chain\: $($stray -join ', ')" }
    if ($missing.Count) { throw "dist\$chain\ is missing: $($missing -join ', ')" }

    $name    = "tclwinkit-$chain-$Ver"
    $zipPath = Join-Path $Stage "$name.zip"

    # Directory entry first, then the files in ordinal order: the same rule the
    # other packagers use, so that entry order cannot depend on NTFS enumeration.
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
    $za = [System.IO.Compression.ZipFile]::Open($zipPath, 'Create')
    $packed = 0
    try {
        Add-ZipDir -Zip $za -Name ($name + '/')
        foreach ($f in (Get-SortedFile -Path $srcDir)) {
            Add-ZipFile -Zip $za -Source $f.FullName -Name "$name/$($f.Name)" `
                         -Level ([System.IO.Compression.CompressionLevel]::Optimal)
            $packed++
        }
    } finally { $za.Dispose() }

    # ---- read the archive back and assert what was meant to be written ----
    # A zip that merely "did not throw" is not evidence: the two failure modes
    # this project has already met are a 136-byte archive from a disposed entry
    # and entry names carrying backslashes, and both are invisible at build time.
    $check = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        $entries = @($check.Entries)
        $badSlash = @($entries | Where-Object { $_.FullName.Contains('\') })
        # Compare the LOCAL part, not the instant and not UtcDateTime: the DOS
        # field stores a bare wall clock with no zone and .NET stamps it with
        # the reader's offset, so on a UTC+3 box the correctly pinned
        # 1980-01-01T00:00:00+03:00 converts to 1979-12-31T21:00Z and an
        # instant comparison rejects every correct entry (hit here, and
        # documented in verify-docs-artifact.ps1).
        $epoch  = [datetime]::new(1980, 1, 1, 0, 0, 0)
        $badTime  = @($entries | Where-Object { $_.LastWriteTime.LocalDateTime -ne $epoch })
        $tops     = @($entries | ForEach-Object { ($_.FullName -split '/')[0] } | Sort-Object -Unique)
        $dirs     = @($entries | Where-Object { $_.FullName.EndsWith('/') })
        $files    = @($entries | Where-Object { -not $_.FullName.EndsWith('/') })
        $inDir    = @($files | Where-Object { -not $_.FullName.StartsWith("$name/") })
    } finally { $check.Dispose() }

    if ($badSlash.Count) { throw "$name.zip: $($badSlash.Count) backslash entry names, e.g. $($badSlash[0].FullName)" }
    if ($badTime.Count)  { throw "$name.zip: $($badTime.Count) entries not pinned to 1980-01-01, e.g. $($badTime[0].FullName)" }
    if ($dirs.Count -ne 1)   { throw "$name.zip: $($dirs.Count) directory entries, expected exactly 1" }
    if ($tops.Count -ne 1 -or $tops[0] -ne $name) { throw "$name.zip: top level is '$($tops -join ', ')', expected '$name'" }
    if ($inDir.Count)    { throw "$name.zip: $($inDir.Count) file entries outside the top-level directory" }
    if ($files.Count -ne $packed) { throw "$name.zip: $($files.Count) file entries, packed $packed" }
    if ($files.Count -ne $have.Count) { throw "$name.zip: $($files.Count) file entries, dist\$chain\ holds $($have.Count)" }

    # Every packed file must be byte-identical to the one on disk.
    foreach ($f in (Get-SortedFile -Path $srcDir)) {
        $entryName = "$name/$($f.Name)"
        $srcHash = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLower()
        $tmp = Join-Path $env:TEMP ("winkit-zipchk-" + [guid]::NewGuid().ToString('n').Substring(0, 8))
        $zr = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
        try {
            $e = $zr.GetEntry($entryName)
            if (-not $e) { throw "$name.zip: entry missing after write: $entryName" }
            if ($e.Length -ne $f.Length) {
                throw "$name.zip: $entryName uncompressed $($e.Length) B, source $($f.Length) B"
            }
            $out = [System.IO.File]::Create($tmp)
            try { $s = $e.Open(); try { $s.CopyTo($out) } finally { $s.Dispose() } } finally { $out.Dispose() }
        } finally { $zr.Dispose() }
        $extHash = (Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash.ToLower()
        Remove-Item -LiteralPath $tmp -Force
        if ($extHash -ne $srcHash) { throw "$name.zip: $entryName extracted hash differs from the source" }
    }

    $sha  = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLower()
    $size = (Get-Item -LiteralPath $zipPath).Length
    $raw  = (Get-ChildItem -LiteralPath $srcDir -File | Measure-Object Length -Sum).Sum
    $built += [pscustomobject]@{ chain = $chain; name = "$name.zip"; sha256 = $sha; bytes = $size; files = $files.Count }
    "{0,-28} {1,10:N0} B  from {2,12:N0} B  ({3:P1})  {4} file(s)" -f `
        "$name.zip", $size, $raw, ($size / $raw), $files.Count
    "  sha256 $sha"
}

# ------------------------------------------------------------ stale archives ---
# The archive name carries the version, so a bump leaves the previous one
# beside the new one in build\release-stage\, and a publisher pointed at that
# directory can pick up an artifact nobody built from this tree. Same shape as
# the stale-archive step in build-docs-artifact.ps1: it runs only after every
# new archive has been written and verified above, it touches only this
# script's own artifact family, and it prints every removal.
if ($KeepStale) {
    'stale release archives kept (-KeepStale)'
} else {
    $current = @($built | ForEach-Object { $_.name })
    # Only this script's own family, matched by name shape rather than by a
    # broad tclwinkit-*.zip glob: build\release-stage\ is shared with
    # publish-release.ps1, and a wide glob would eventually delete something
    # this script did not create.
    $stale = @(Get-ChildItem -LiteralPath $Stage -Filter '*.zip' -File -EA SilentlyContinue |
               Where-Object { $_.Name -match '^tclwinkit-(msvc|mingw)-[0-9][0-9.]*\.zip$' -and
                              $current -notcontains $_.Name })
    foreach ($s in $stale) {
        $sz = $s.Length
        Remove-Item -LiteralPath $s.FullName -Force
        'removed stale release archive: {0} ({1:N2} MB), superseded by {2}' -f `
            $s.Name, ($sz / 1MB), ($current -join ', ')
    }
    if (-not $stale.Count) { 'no stale release archives in build\release-stage\' }
}

'=== RELEASE ARCHIVES OK ==='
