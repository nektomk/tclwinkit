# verify-docs-artifact.ps1 -- gate the fifth shipped asset: the docs archive.
#
# This is the machine half of the docs-artifact contract. It checks structure
# (licence objects present, no stale flat licenses/, forward slashes only per
# ZIP APPNOTE 4.4.17), content identity against the repository tree, the
# shipped-text encoding rule for the three generated texts inside the archive,
# that every entry is pinned to the DOS epoch, and that MANIFEST.txt agrees
# with the archive it describes.
#
# Contract:
#   * ASCII-only source (CONVENTIONS section 5).
#   * Read-only. Exit code = number of failed assertions (capped, exit codes
#     are one byte).
#   * No memorised sizes or counts. Every expectation is either derived from
#     the repository, or cross-checked against another part of the same
#     archive. A hardcoded "137006 B" would have been right for 0.1 and a lie
#     for 0.2 -- the same stale-constant class this repo already tripped over
#     twice (".gitattributes: 123 tracked files", "verdict: ok 32").
param(
    [string]$Repo = '',
    [string]$Zip = ''
)
$ErrorActionPreference = 'Continue'
if (-not $Repo) { $Repo = Split-Path -Parent $PSScriptRoot }
if (-not (Test-Path -LiteralPath $Repo)) {
    Write-Output ('FATAL: repo not found: ' + $Repo); exit 1
}

# PowerShell 7 / .NET Core has these built in and cannot resolve the .NET
# Framework assembly names, so load only when a type is genuinely missing --
# and then load BOTH names and verify each type resolved. Measured on Windows
# PowerShell 5.1: System.IO.Compression.FileSystem supplies ZipFile and
# ZipArchive but not the ZipArchiveMode enum, which lives in
# System.IO.Compression; a script that assumed one assembly gets TypeNotFound
# at first use, i.e. halfway through writing an archive.
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
function Invoke-Git([string[]]$ga) {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $o = @(& git @ga 2>&1 | Out-String -Stream)
    $ErrorActionPreference = $prev
    return ,@($o | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}
function Read-EntryBytes($entry) {
    $buf = New-Object byte[] $entry.Length
    $s = $entry.Open()
    try {
        $got = 0
        while ($got -lt $buf.Length) {
            $n = $s.Read($buf, $got, $buf.Length - $got)
            if ($n -le 0) { break }
            $got += $n
        }
    } finally { $s.Dispose() }
    return ,@($buf[0..([Math]::Max(0, $got - 1))])
}

# --- locate the archive ----------------------------------------------------
if (-not $Zip) {
    $cands = @(Get-ChildItem -LiteralPath (Join-Path $Repo 'dist') -Filter 'tclwinkit-docs-*.zip' -File -ErrorAction SilentlyContinue)
    Chk ($cands.Count -eq 1) ('archives matching dist/tclwinkit-docs-*.zip: ' + $cands.Count + ' (expected exactly 1)')
    if ($cands.Count -ne 1) {
        Write-Output 'VERIFY-DOCS-ARTIFACT FAILED: nothing to verify'
        if ($fail -gt 200) { exit 200 }
        exit ([Math]::Max(1, $fail))
    }
    $Zip = $cands[0].FullName
}
if (-not (Test-Path -LiteralPath $Zip)) {
    Write-Output ('FATAL: archive not found: ' + $Zip)
    exit 1
}
# Resolve to an absolute path HERE. Test-Path above goes through the PowerShell
# provider and honours the shell's location, while ZipFile::OpenRead below is a
# .NET call that resolves a relative path against the PROCESS working directory
# -- and PowerShell does not keep the two in sync. Measured with
# -Zip 'dist\tclwinkit-docs-0.2.zip' from the repository root: Test-Path said
# yes, OpenRead threw "Could not find a part of the path
# 'C:\src\winkit\dist\tclwinkit-docs-0.2.zip'", and because
# $ErrorActionPreference is 'Continue' the run carried on with $z null. A null
# $z then yields a phantom one-element array -- @($null | ForEach-Object {
# $_.FullName }) has exactly one item -- so the report claimed
# "entries: 1 (files 1, directories 0)" and seven failures against an archive
# that verifies clean. The size line still read 13.6 MB because that one came
# from the provider, which is what made the output look plausible.
$Zip = (Resolve-Path -LiteralPath $Zip).ProviderPath
Write-Output ('archive under test: ' + $Zip)

$z = $null
try { $z = [System.IO.Compression.ZipFile]::OpenRead($Zip) }
catch {
    Write-Output ('FATAL: cannot open the archive: ' + $Zip)
    Write-Output ('       ' + $_.Exception.Message)
    exit 1
}
# Vacuity guard. Every check below asks whether something is present in the
# archive, so an unopened or empty one turns them all into failures for the
# wrong reason -- and, as the comment above records, a null handle does not even
# produce an honest zero. Refuse loudly instead of reporting a verdict.
if (-not $z) { Write-Output ('FATAL: the archive handle is null: ' + $Zip); exit 1 }
if ($z.Entries.Count -eq 0) {
    Write-Output ('FATAL: the archive has no entries: ' + $Zip)
    $z.Dispose()
    exit 1
}
$names = @($z.Entries | ForEach-Object { $_.FullName })
$fileEntries = @($z.Entries | Where-Object { $_.FullName -notmatch '/$' })
$dirEntries  = @($z.Entries | Where-Object { $_.FullName -match '/$' })
Write-Output ('entries: ' + $names.Count + '  (files ' + $fileEntries.Count + ', directories ' + $dirEntries.Count + ')  size: ' + [math]::Round((Get-Item -LiteralPath $Zip).Length / 1MB, 2) + ' MB')

$root = ($names | Where-Object { $_ -match '^[^/]+/$' } | Select-Object -First 1)
if ($root) { $root = $root -replace '/$', '' } else { $root = '' }
Write-Output ('archive root: ' + $root)
Chk ($root -ne '') 'a single top-level directory exists (the archive is not loose files)'

# --- structure -------------------------------------------------------------
# -cmatch, not -match: PowerShell matching is case-insensitive, so '/licenses/'
# would match the new '/LICENSES/' directory and report a false leftover.
Chk (@($names | Where-Object { $_ -cmatch '(^|/)licenses/' }).Count -eq 0) 'old flat licenses/ is gone'
Chk (@($names | Where-Object { $_ -match ('^' + [regex]::Escape($root) + '/LICENSES/.+') }).Count -gt 0) 'LICENSES/ present'
Chk (@($names | Where-Object { $_ -eq ($root + '/LICENSE') }).Count -gt 0) 'LICENSE at archive root'
Chk (@($names | Where-Object { $_ -eq ($root + '/THIRD-PARTY-NOTICES.md') }).Count -gt 0) 'THIRD-PARTY-NOTICES.md at archive root'
$mfEntry = $z.Entries | Where-Object { $_.FullName -eq ($root + '/MANIFEST.txt') }
Chk ($null -ne $mfEntry) 'MANIFEST.txt present'
Chk (@($names | Where-Object { $_ -match 'LICENSES/LICENSES' }).Count -eq 0) 'no nested LICENSES/LICENSES (Copy-Item trap)'
Chk (@($names | Where-Object { $_ -match '\\' }).Count -eq 0) 'no backslash entry names (ZIP APPNOTE 4.4.17)'

# --- the three generated texts: LF-only, no BOM ---------------------------
# Level 3 of the encoding rule (.gitattributes / CONVENTIONS): what ships is
# LF and BOM-free, regardless of how the working copy looks.
$textOk = 0; $textTotal = 0
foreach ($rel in @('/MANIFEST.txt', '/VERSIONS.txt', '/THIRD-PARTY-NOTICES.md')) {
    $en = $z.Entries | Where-Object { $_.FullName -eq ($root + $rel) }
    if (-not $en) { continue }
    $textTotal++
    $b = Read-EntryBytes $en
    $noBom = -not ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
    $txt = [System.Text.Encoding]::UTF8.GetString($b)
    $lf = ($txt -notmatch "`r`n")
    $nonEmpty = ($b.Length -gt 0)
    $ok = ($noBom -and $lf -and $nonEmpty)
    if ($ok) { $textOk++ }
    Chk $ok ($rel.Substring(1) + ': ' + $b.Length + ' B, LF-only=' + $lf + ', no BOM=' + $noBom)
}
Chk ($textTotal -eq 3) ('generated texts found in the archive: ' + $textTotal + '/3')

# --- MANIFEST.txt must agree with the archive it ships inside --------------
# This replaces the memorised byte size with a real cross-check: every listed
# path exists, and its listed length equals the entry length.
if ($mfEntry) {
    $mb = Read-EntryBytes $mfEntry
    $mtxt = [System.Text.Encoding]::UTF8.GetString($mb)
    $mlines = @($mtxt -split "`n")
    $hdr = $mlines | Where-Object { $_ -match '^#\s' } | Select-Object -First 1
    $claim = 0
    if ($hdr -and $hdr -match '\((\d+)\s+files\)') { $claim = [int]$Matches[1] }
    Chk ($claim -gt 0) ('MANIFEST header declares a file count: ' + $claim)
    $rows = @($mlines | Where-Object { $_ -match '^\s*\d+\s{2}\S' })
    Chk ($rows.Count -eq $claim) ('MANIFEST rows ' + $rows.Count + ' == header claim ' + $claim)
    # The manifest is written after the listing is taken, so it does not contain
    # itself: listed + 1 == file entries in the archive.
    Chk (($rows.Count + 1) -eq $fileEntries.Count) ('MANIFEST rows + itself = archive files: ' + $rows.Count + ' + 1 = ' + $fileEntries.Count)
    $byName = @{}
    foreach ($en in $fileEntries) { $byName[$en.FullName] = $en.Length }
    $ghost = 0; $sizeMismatch = 0
    foreach ($r in $rows) {
        if ($r -match '^\s*(\d+)\s{2}(\S+)\s*$') {
            $sz = [int64]$Matches[1]; $p = $Matches[2]
            $full = $root + '/' + $p
            if (-not $byName.ContainsKey($full)) {
                if ($ghost -lt 5) { Write-Output ('  LISTED BUT ABSENT: ' + $p) }
                $ghost++
            } elseif ($byName[$full] -ne $sz) {
                if ($sizeMismatch -lt 5) { Write-Output ('  SIZE DIFFERS: ' + $p + '  listed=' + $sz + ' actual=' + $byName[$full]) }
                $sizeMismatch++
            }
        }
    }
    Chk ($ghost -eq 0) ('MANIFEST paths missing from the archive: ' + $ghost)
    Chk ($sizeMismatch -eq 0) ('MANIFEST sizes disagreeing with the archive: ' + $sizeMismatch)
}

# --- every relative link in the archived NOTICES resolves inside it --------
$ntEntry = $z.Entries | Where-Object { $_.FullName -eq ($root + '/THIRD-PARTY-NOTICES.md') }
if ($ntEntry) {
    $doc = [System.Text.Encoding]::UTF8.GetString((Read-EntryBytes $ntEntry))
    $rels = @([regex]::Matches($doc, '\]\((?!http|#)([^)#]+?)(?:#[^)]*)?\)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    # The document is written for the repository, where patches/, scripts/,
    # src/ and docs/ exist; the archive carries LICENSES/, LICENSE and itself
    # only. The preamble says so, so the exception list is deliberate.
    $repoOnly = @('patches/', 'scripts/', 'src/', 'docs/')
    $dead = 0; $except = 0
    foreach ($r in $rels) {
        $skip = $false
        foreach ($pre in $repoOnly) { if ($r -like ($pre + '*')) { $skip = $true } }
        if ($skip) { $except++; continue }
        $p = $root + '/' + ($r -replace '^\./', '')
        if (@($names | Where-Object { $_ -eq $p -or $_ -match ('^' + [regex]::Escape($p) + '/') }).Count -eq 0) {
            if ($dead -lt 5) { Write-Output ('  DEAD LINK in archive: ' + $r) }
            $dead++
        }
    }
    Chk ($dead -eq 0) ('archive-relative links resolve (' + ($rels.Count - $except) + ' checked, ' + $except + ' repository-only by design)')
}

# --- content identity against the repository tree -------------------------
$licDir = Join-Path $Repo 'LICENSES'
if (-not (Test-Path -LiteralPath $licDir)) {
    Chk $false 'LICENSES/ missing in the repository (cannot cross-check)'
} else {
    $enc = New-Object System.Text.UTF8Encoding($false)
    $repoFiles = @(Get-ChildItem -LiteralPath $licDir -Recurse -File)
    $diff = 0; $miss = 0
    foreach ($f in $repoFiles) {
        $rel = $f.FullName.Substring($licDir.Length + 1) -replace '\\', '/'
        $e = $z.Entries | Where-Object { $_.FullName -eq ($root + '/LICENSES/' + $rel) }
        if (-not $e) { if ($miss -lt 5) { Write-Output ('  MISSING IN ZIP: LICENSES/' + $rel) }; $miss++; continue }
        $az = $enc.GetString((Read-EntryBytes $e)) -replace "`r`n", "`n"
        $rz = $enc.GetString([System.IO.File]::ReadAllBytes($f.FullName)) -replace "`r`n", "`n"
        if ($az -ne $rz) { if ($diff -lt 5) { Write-Output ('  CONTENT DIFFERS: LICENSES/' + $rel) }; $diff++ }
    }
    Chk ($miss -eq 0) ('LICENSES/ files missing from the archive: ' + $miss + ' of ' + $repoFiles.Count)
    Chk ($diff -eq 0) ('LICENSES/ files differing from the repository: ' + $diff + ' of ' + $repoFiles.Count)
    # And the other direction: nothing in the archive that the repo does not have.
    $extra = @($z.Entries | Where-Object {
        $_.FullName -match ('^' + [regex]::Escape($root) + '/LICENSES/') -and $_.FullName -notmatch '/$'
    } | Where-Object {
        $rel = $_.FullName.Substring(($root + '/LICENSES/').Length)
        -not (Test-Path -LiteralPath (Join-Path $licDir ($rel -replace '/', [System.IO.Path]::DirectorySeparatorChar)))
    })
    Chk ($extra.Count -eq 0) ('LICENSES/ entries in the archive absent from the repo: ' + $extra.Count)
}

# --- VERSIONS.txt: deterministic stamp, tied to the commit it names --------
$vEntry = $z.Entries | Where-Object { $_.FullName -eq ($root + '/VERSIONS.txt') }
if ($vEntry) {
    $vt = [System.Text.Encoding]::UTF8.GetString((Read-EntryBytes $vEntry))
    $gen = @($vt -split "`n" | Where-Object { $_ -match '(?i)^generated: ' })
    Chk ($gen.Count -eq 1) ('VERSIONS.txt has exactly one generated: line (' + $gen.Count + ')')
    if ($gen.Count -eq 1) {
        # The line MAY carry a timestamp -- it must carry a DETERMINISTIC one.
        # The generator uses SOURCE_DATE_EPOCH, else the committer date of the
        # HEAD it was built from, and never the wall clock of the run. Asserting
        # equality with THAT commit's date is what catches a Get-Date
        # regression; asserting "no date at all" (an earlier version of this
        # check) flagged the correct value as a leak.
        $sha = ''
        if ($gen[0] -match 'commit\s+([0-9a-f]{7,40})') { $sha = $Matches[1] }
        Chk ($sha -ne '') ('VERSIONS.txt names the commit it was built from: ' + $(if ($sha) { $sha } else { 'NONE' }))
        $got = ''
        if ($gen[0] -match '(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z)') { $got = $Matches[1] }
        Chk ($got -ne '') ('VERSIONS.txt carries a UTC stamp: ' + $(if ($got) { $got } else { 'NONE' }))
        if ($sha -and $got) {
            $sde = $env:SOURCE_DATE_EPOCH
            if ($sde -and $sde -match '^[0-9]+$') {
                $want = [DateTimeOffset]::FromUnixTimeSeconds([int64]$sde).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                $srcName = 'SOURCE_DATE_EPOCH'
            } else {
                $ci = ((Invoke-Git @('-C', $Repo, 'show', '-s', '--format=%cI', $sha)) -join '').Trim()
                $parsed = [DateTimeOffset]::MinValue
                if ([DateTimeOffset]::TryParse($ci, [ref]$parsed)) {
                    $want = $parsed.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); $srcName = 'committer date of ' + $sha
                } else {
                    $want = ''; $srcName = 'unresolvable commit ' + $sha
                }
            }
            Chk ($want -ne '') ('stamp source resolvable: ' + $srcName)
            Chk ($got -ceq $want) ('VERSIONS.txt stamp ' + $got + ' == ' + $srcName + ' ' + $want)
        }
        $head = ((Invoke-Git @('-C', $Repo, 'rev-parse', 'HEAD')) -join '').Trim()
        if ($sha -and $head) {
            # Informational, not an assertion: an archive can legitimately be
            # older than HEAD (that is the state between a release build and
            # the docs commit). What must never happen is a stamp that tracks
            # the clock.
            Write-Output ('  info  built from ' + $sha + '; HEAD is ' + $head + $(if ($head.StartsWith($sha) -or $sha.StartsWith($head)) { '  (same commit)' } else { '  (archive predates HEAD: rebuild before publishing)' }))
        }
        Chk ($vt -notmatch '(?i)generated:.*\b(Get-Date|now|timestamped at run)') 'VERSIONS.txt shows no sign of a wall-clock generator'
    }
}

# --- every entry pinned to the DOS epoch ----------------------------------
# Compare the LOCAL part, not UtcDateTime: the DOS field stores a bare wall
# clock with no zone and .NET stamps it with the reader's offset, so on a UTC+3
# box 1980-01-01T00:00:00+03:00 converts to 1979-12-31T21:00Z and a UTC
# comparison rejects every correct entry (measured). Directory entries are
# included on purpose: the first version of this measurement looked at files
# only and missed a 504-byte drift across the directory entries.
$epoch = [datetime]::new(1980, 1, 1, 0, 0, 0)
$badTime = 0; $badDirs = 0
foreach ($en in $z.Entries) {
    if ($en.LastWriteTime.LocalDateTime -ne $epoch) {
        if ($badTime -lt 5) { Write-Output ('  NOT PINNED: ' + $en.FullName + '  ' + $en.LastWriteTime.ToString('o')) }
        $badTime++
        if ($en.FullName -match '/$') { $badDirs++ }
    }
}
Chk ($badTime -eq 0) ('entries not pinned to 1980-01-01: ' + $badTime + ' of ' + $names.Count + ' (directories: ' + $badDirs + ')')
$z.Dispose()

Write-Output ('RESULT: failures ' + $fail)
if ($fail -eq 0) { 'VERIFY-DOCS-ARTIFACT OK' } else { 'VERIFY-DOCS-ARTIFACT FAILED' }
if ($fail -gt 200) { exit 200 }
exit $fail
