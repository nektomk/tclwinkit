# verify-release-archives.ps1 -- gate the shipped executables archives.
#
# This is the machine half of the release-archive contract, the sibling of
# verify-docs-artifact.ps1. build-release-archives.ps1 verifies what it has
# just written; this script verifies what is ON DISK now, from scratch and
# without trusting the builder: a rebuild may never have run, an archive may
# have been replaced or truncated, SHA256SUMS.txt may predate it. "We just
# built it" and "we just verified it" are not the same claim.
#
# Checks, per archive:
#   * exactly one archive per toolchain for the CURRENT version, and no
#     leftover archive of another version beside them;
#   * entry names use forward slashes only (ZIP APPNOTE 4.4.17);
#   * exactly one directory entry, and a single top-level directory whose name
#     equals the archive name without .zip -- that directory is what stops two
#     toolchains unpacked into one folder from overwriting each other;
#   * every entry pinned to the DOS epoch, directories included;
#   * packed file names come from the allowlist;
#   * every packed file is byte-identical to its source in dist/<chain>/, and
#     dist/<chain>/ holds nothing that was NOT packed;
#   * SHA256SUMS.txt lists this archive with a matching hash.
#
# Contract:
#   * ASCII-only source (docs/CONVENTIONS.md section 4).
#   * Read-only. Exit code = number of failed assertions (capped at 200).
#   * No memorised sizes or counts. Every expectation is derived from the
#     repository: the version from kit_init.tcl, the packed set from dist/,
#     the hashes from SHA256SUMS.txt. A hardcoded byte count would be right for
#     one build and a lie for the next.
param(
    [string]$Repo = ''
)
$ErrorActionPreference = 'Continue'
if (-not $Repo) { $Repo = Split-Path -Parent $PSScriptRoot }
if (-not (Test-Path -LiteralPath $Repo)) {
    Write-Output ('FATAL: repo not found: ' + $Repo); exit 1
}

# PowerShell 7 / .NET Core has these built in and cannot resolve the .NET
# Framework assembly names, so load only when a type is genuinely missing --
# and then load BOTH names and verify each type resolved (same reasoning as
# verify-docs-artifact.ps1: assuming one assembly gives TypeNotFound at first
# use rather than at load).
foreach ($asm in @('System.IO.Compression', 'System.IO.Compression.FileSystem')) {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    Add-Type -AssemblyName $asm | Out-Null
    $ErrorActionPreference = $prev
}
foreach ($t in @('System.IO.Compression.ZipFile', 'System.IO.Compression.ZipArchive')) {
    if (-not ($t -as [type])) {
        Write-Output ('FATAL: type not available: ' + $t)
        exit 1
    }
}

$fail = 0
function Chk([bool]$ok, [string]$what) {
    if (-not $ok) { $script:fail++ }
    Write-Output ('  ' + $(if ($ok) { 'ok   ' } else { 'FAIL ' }) + $what)
}
function Say([string]$what) { Write-Output ('  info  ' + $what) }

# --- expected shape, derived rather than memorised --------------------------
$Chains  = @('msvc', 'mingw')
$Allowed = @('tclwin.exe', 'tkwin.exe', 'tclsafe.exe', 'tksafe.exe')
$Dist    = Join-Path $Repo 'dist'
$Stage   = Join-Path $Repo 'build\release-stage'

$kitInit = Join-Path $Repo 'src\kit\vfs\lib\kit_init.tcl'
if (-not (Test-Path -LiteralPath $kitInit)) {
    Write-Output ('FATAL: version source not found: ' + $kitInit); exit 1
}
$mver = Select-String -LiteralPath $kitInit -Pattern 'variable version\s+(\S+)' | Select-Object -First 1
if (-not $mver) {
    Write-Output 'FATAL: cannot read the version from kit_init.tcl'; exit 1
}
$Ver = $mver.Matches[0].Groups[1].Value
Chk ($Ver -match '^[0-9]+(\.[0-9]+)*$') ('version reads as a version: ' + $Ver)

$sumsPath = Join-Path $Stage 'SHA256SUMS.txt'
if (-not (Test-Path -LiteralPath $sumsPath)) {
    Write-Output ('FATAL: no checksum list at ' + $sumsPath + ' (run publish-release.ps1 -DryRun)')
    exit 1
}
$sumBytes = [System.IO.File]::ReadAllBytes($sumsPath)
$sums = @{}
foreach ($line in [System.Text.Encoding]::UTF8.GetString($sumBytes) -split "`n") {
    $l = $line.TrimEnd("`r")
    if ($l -match '^([0-9a-fA-F]{64})\s+\*?(.+)$') { $sums[$Matches[2].Trim()] = $Matches[1].ToLower() }
}

$epoch = [datetime]::new(1980, 1, 1, 0, 0, 0)

# --- the archive family present in build/release-stage ----------------------
Write-Output '=== 1. archive family ==='
$allZips = @(Get-ChildItem -LiteralPath $Stage -Filter 'tclwinkit-*.zip' -File -ErrorAction SilentlyContinue)
$wantNames = @($Chains | ForEach-Object { 'tclwinkit-' + $_ + '-' + $Ver + '.zip' })
$found = @($allZips | ForEach-Object { $_.Name })
Chk ($allZips.Count -eq $Chains.Count) ('archives in build/release-stage: ' + $allZips.Count + ' (expected ' + $Chains.Count + ')')
foreach ($w in $wantNames) {
    Chk ($found -contains $w) ('expected archive present: ' + $w)
}
foreach ($f in $found) {
    if ($wantNames -notcontains $f) {
        Chk $false ('unexpected archive of another version or family: ' + $f)
    }
}
foreach ($f in $found) { Say ('found: ' + $f) }

# --- per-archive structure and content --------------------------------------
foreach ($chain in $Chains) {
    $name    = 'tclwinkit-' + $chain + '-' + $Ver
    $zipPath = Join-Path $Stage ($name + '.zip')
    $srcDir  = Join-Path $Dist $chain

    Write-Output ('=== 2.' + $chain + ': ' + $name + '.zip ===')
    if (-not (Test-Path -LiteralPath $zipPath)) {
        Chk $false ('archive missing: ' + $zipPath)
        continue
    }
    if (-not (Test-Path -LiteralPath $srcDir)) {
        Chk $false ('source directory missing: ' + $srcDir)
        continue
    }

    # What dist/<chain>/ actually holds is the expectation for what is packed:
    # nothing may be dropped, nothing extra may be smuggled in.
    $srcFiles = @(Get-ChildItem -LiteralPath $srcDir -File | Sort-Object Name)
    $srcNames = @($srcFiles | ForEach-Object { $_.Name })
    Chk ($srcNames.Count -gt 0) ('dist\' + $chain + '\ holds ' + $srcNames.Count + ' file(s): ' + ($srcNames -join ', '))
    $straySrc = @($srcNames | Where-Object { $Allowed -notcontains $_ })
    Chk ($straySrc.Count -eq 0) ('dist\' + $chain + '\ outside the allowlist: ' + $(if ($straySrc.Count) { $straySrc -join ', ' } else { 'none' }))

    $z = $null
    try { $z = [System.IO.Compression.ZipFile]::OpenRead($zipPath) } catch {
        Chk $false ('archive does not open: ' + $_.Exception.Message)
    }
    if (-not $z) { continue }

    try {
        $entries = @($z.Entries)
        $names   = @($entries | ForEach-Object { $_.FullName })

        Say ('entries: ' + $entries.Count)
        $badSlash = @($names | Where-Object { $_.Contains('\') })
        Chk ($badSlash.Count -eq 0) ('backslash entry names: ' + $badSlash.Count + $(if ($badSlash.Count) { ' e.g. ' + $badSlash[0] } else { '' }))

        $dirs  = @($names | Where-Object { $_.EndsWith('/') })
        $files = @($names | Where-Object { -not $_.EndsWith('/') })
        Chk ($dirs.Count -eq 1) ('directory entries: ' + $dirs.Count + ' (expected exactly 1)')
        if ($dirs.Count -ge 1) {
            Chk ($dirs[0] -eq ($name + '/')) ('the single directory entry is "' + $name + '/" (found "' + $dirs[0] + '")')
        }

        $tops = @($names | ForEach-Object { ($_ -split '/')[0] } | Sort-Object -Unique)
        Chk (($tops.Count -eq 1) -and ($tops[0] -eq $name)) ('single top-level directory named after the archive: ' + ($tops -join ', '))

        $outside = @($files | Where-Object { -not $_.StartsWith($name + '/') })
        Chk ($outside.Count -eq 0) ('file entries outside the top-level directory: ' + $outside.Count)

        $badTime = @($entries | Where-Object { $_.LastWriteTime.LocalDateTime -ne $epoch })
        Chk ($badTime.Count -eq 0) ('entries not pinned to 1980-01-01: ' + $badTime.Count + $(if ($badTime.Count) { ' e.g. ' + $badTime[0].FullName + ' ' + $badTime[0].LastWriteTime.ToString('o') } else { '' }))

        $packedNames = @($files | ForEach-Object { $_.Substring($name.Length + 1) } | Sort-Object)
        Chk ($packedNames.Count -eq $srcNames.Count) ('packed ' + $packedNames.Count + ' file(s), dist holds ' + $srcNames.Count)
        $notPacked = @($srcNames | Where-Object { $packedNames -notcontains $_ })
        $extra     = @($packedNames | Where-Object { $srcNames -notcontains $_ })
        Chk ($notPacked.Count -eq 0) ('dist files absent from the archive: ' + $(if ($notPacked.Count) { $notPacked -join ', ' } else { 'none' }))
        Chk ($extra.Count -eq 0) ('archive entries with no dist source: ' + $(if ($extra.Count) { $extra -join ', ' } else { 'none' }))

        # Byte identity, per file: the archive is what a user runs, so it must
        # carry exactly the binary that was tested in dist/.
        $mismatch = 0
        foreach ($f in $srcFiles) {
            $entryName = $name + '/' + $f.Name
            $e = $z.GetEntry($entryName)
            if (-not $e) { $mismatch++; continue }
            if ($e.Length -ne $f.Length) {
                Write-Output ('  SIZE DIFF: ' + $entryName + ' ' + $e.Length + ' B vs dist ' + $f.Length + ' B')
                $mismatch++
                continue
            }
            $tmp = Join-Path $env:TEMP ('winkit-verarch-' + [guid]::NewGuid().ToString('n').Substring(0, 8))
            $out = [System.IO.File]::Create($tmp)
            try {
                $s = $e.Open()
                try { $s.CopyTo($out) } finally { $s.Dispose() }
            } finally { $out.Dispose() }
            $hE = (Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash.ToLower()
            Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
            $hS = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLower()
            if ($hE -ne $hS) {
                Write-Output ('  HASH DIFF: ' + $entryName + ' ' + $hE + ' vs ' + $hS)
                $mismatch++
            }
        }
        Chk ($mismatch -eq 0) ('packed files byte-identical to dist\' + $chain + '\ (' + $srcNames.Count + ' checked)')
    } finally { $z.Dispose() }

    # --- checksum list agrees with the bytes on disk -------------------------
    $h = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLower()
    Say ('sha256 ' + $h + '  (' + (Get-Item -LiteralPath $zipPath).Length + ' B)')
    if ($sums.ContainsKey($name + '.zip')) {
        Chk ($sums[$name + '.zip'] -eq $h) ('SHA256SUMS.txt entry matches the file on disk')
    } else {
        Chk $false ('SHA256SUMS.txt has no entry for ' + $name + '.zip')
    }
}

# --- nothing stale or unlisted in the checksum file --------------------------
Write-Output '=== 3. checksum list scope ==='
$listedArchives = @($sums.Keys | Where-Object { $_ -match '^tclwinkit-(msvc|mingw)-.+\.zip$' })
Chk ($listedArchives.Count -eq $Chains.Count) ('exe archives listed in SHA256SUMS.txt: ' + $listedArchives.Count + '/' + $Chains.Count)
$listedHashes = @($sums.Values)
Chk (($listedHashes | Sort-Object -Unique).Count -eq $listedHashes.Count) ('all listed hashes distinct: ' + ($listedHashes | Sort-Object -Unique).Count + ' of ' + $listedHashes.Count)
$onDisk = @($allZips | ForEach-Object { (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLower() })
$unlisted = @($onDisk | Where-Object { $listedHashes -notcontains $_ })
Chk ($unlisted.Count -eq 0) ('archives on disk whose hash is not listed: ' + $unlisted.Count)

Write-Output ('RESULT: failures ' + $fail)
if ($fail -eq 0) { 'VERIFY-RELEASE-ARCHIVES OK' } else { 'VERIFY-RELEASE-ARCHIVES FAILED' }
if ($fail -gt 200) { exit 200 }
exit $fail
