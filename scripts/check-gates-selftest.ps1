# check-gates-selftest.ps1 -- negative control for the four read-only gates in
# scripts/: check-encoding, verify-docs-artifact, link-audit, source-parity.
#
# Why this exists as a shipped script rather than a scratch run: the public
# documents claim the gates have a negative control. A claim whose evidence
# lives in a gitignored directory is not evidence -- a reader cannot reproduce
# it and the next person to touch a gate cannot re-run it. CONTRIBUTING.md
# ("Layout") says a scratch tool that earns its keep is promoted in the same
# change that links to it; this is that change.
#
# Method: build fixtures that are VALID except for exactly one injected defect
# each, run the gate against them, and require (a) a nonzero exit and (b) the
# specific assertion named. The valid baseline must PASS, otherwise a finding
# cannot be told apart from incidental noise. Both directions matter: a gate
# that has only ever been observed passing is not evidence, and a gate that
# fires on everything is not a gate either.
#
# This is what it caught on 2026-10-28, in its own first hours:
#   * the fixture builder threw TypeNotFound (ZipArchiveMode lives in
#     System.IO.Compression, not .FileSystem), wrote a 0-byte archive, and the
#     gate was fed "central directory damaged" as if it were a defect case --
#     all eight switches then produced the SAME exit code, which reads as a
#     working negative test and proves nothing. Hence Test-Fixture below.
#   * Parser::ParseFile's first [ref] is TOKENS, not errors; swapped, every
#     valid step reported a failure with an empty message.
#   * OrderedDictionary.Remove(@(...)) removes nothing silently, because @()
#     turns the lookup key into an array.
#
# Gates 3 and 4 were added on 2026-10-28 (block G) together with the auditors
# they control, promoted from build/research/ in the same change that links to
# them. What their injection loops caught while being written, all of it the
# vacuous-pass class documented in docs/NOTES.md section 10:
#   * link-audit walked 26 anchors and `continue`d past every one of them, so it
#     reported 0 findings while the anchor leg had not run -- hence the
#     "fragments actually resolved" assertion on the BASELINE, not on a case;
#   * Get-SlugSet returned a bare HashSet, which PowerShell unrolled to $null
#     when empty, so the leg died only on files without headings;
#   * source-parity extracted fields with (?m)^\s*key\s*= and got 12 of 15 empty
#     per manifest row, then reported findings about the one field that did
#     extract while looking like a working gate -- hence
#     "rows fully harvested: 3" on the baseline;
#   * three mutation fixtures tested the ABSENCE of a defect while staging the
#     evidence of one (git add -A staged the orphan the untracked case relied on)
#     -- hence "reports exactly one finding, not two" and the teardown that
#     re-verifies the baseline after every case.
# Contract: ASCII-only source (docs/CONVENTIONS.md section 5), read-only
# w.r.t. the repository -- all fixtures go under build/, which is gitignored.
# Exit code = number of failed assertions.
param(
    [string]$Repo = '',
    [switch]$Keep   # leave the fixtures on disk for inspection
)
$ErrorActionPreference = 'Stop'
if (-not $Repo) { $Repo = Split-Path -Parent $PSScriptRoot }
if (-not (Test-Path -LiteralPath $Repo)) {
    Write-Output ('FATAL: repo not found: ' + $Repo); exit 1
}

# Load BOTH assembly names and verify each type resolved. On Windows PowerShell
# 5.1 System.IO.Compression.FileSystem supplies ZipFile and ZipArchive but not
# the ZipArchiveMode enum. PowerShell 7 / .NET Core has them built in and cannot
# resolve the .NET Framework assembly names, hence SilentlyContinue.
$prevAsm = $ErrorActionPreference
$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.IO.Compression | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem | Out-Null
$ErrorActionPreference = $prevAsm
foreach ($t in @('System.IO.Compression.ZipFile', 'System.IO.Compression.ZipArchive', 'System.IO.Compression.ZipArchiveMode')) {
    if (-not ($t -as [type])) { Write-Output ('FATAL: type not available: ' + $t); exit 1 }
}

$enc = New-Object System.Text.UTF8Encoding($false)
$epoch = [datetime]::new(1980, 1, 1, 0, 0, 0)
$scratch = Join-Path $Repo 'build/research/gates-selftest'
$fail = 0
function Say([string]$s) { Write-Output $s }
function Chk([bool]$ok, [string]$what) {
    if (-not $ok) { $script:fail++ }
    Say ('  ' + $(if ($ok) { 'ok   ' } else { 'FAIL ' }) + $what)
}
function Invoke-Git([string[]]$ga) {
    # Native stderr under ErrorActionPreference=Stop raises NativeCommandError,
    # which is how a healthy repository gets reported as broken.
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $o = @(& git @ga 2>&1 | Out-String -Stream)
    $ErrorActionPreference = $prev
    return ,@($o | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}
function Run-Gate([string]$script, [string[]]$ga) {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    # No @() wrapper: Out-String already yields ONE string, and wrapping it makes
    # the field an array, so `$r.out -match` then FILTERS instead of returning a
    # boolean and Chk refuses the argument transformation.
    $o = (& powershell -NoProfile -ExecutionPolicy Bypass -File $script @ga 2>&1 | Out-String)
    $c = $LASTEXITCODE
    $ErrorActionPreference = $prev
    return @{ code = $c; out = [string]$o }
}

if ($Keep -and (Test-Path -LiteralPath $scratch)) { Remove-Item -LiteralPath $scratch -Recurse -Force }
if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
[void](New-Item -ItemType Directory -Force -Path $scratch)

Say ('repo: ' + $Repo)
Say ('scratch: ' + $scratch)

# ===========================================================================
# gate 1: scripts/check-encoding.ps1
# ===========================================================================
$checker = Join-Path $Repo 'scripts/check-encoding.ps1'
if (-not (Test-Path -LiteralPath $checker)) { Say ('FATAL: gate not found: ' + $checker); exit 1 }
$mini = Join-Path $scratch 'repo'
[void](New-Item -ItemType Directory -Force -Path $mini)
[void](Invoke-Git @('init', '-q', '-b', 'main', $mini))
[void](Invoke-Git @('-C', $mini, 'config', 'user.email', 'fixture@invalid.example'))
[void](Invoke-Git @('-C', $mini, 'config', 'user.name', 'fixture'))
# .gitattributes mirrors the real rule closely enough for the EOL machinery
[System.IO.File]::WriteAllBytes((Join-Path $mini '.gitattributes'),
    $enc.GetBytes("* text=auto eol=lf`n*.bat text eol=crlf`n*.ps1 text eol=crlf`n"))
[System.IO.File]::WriteAllBytes((Join-Path $mini 'good.md'), $enc.GetBytes("hello`n"))
# One file per surface the rule distinguishes: LF text, CRLF cmd, CRLF PowerShell,
# LF shell. Without the .ps1 the baseline trips the "ps1 count must be > 0" guard
# in section 3b, and a fixture that fails for a reason of its own makes every
# later finding ambiguous -- the same trap as an invented commit in gate 2.
[System.IO.File]::WriteAllBytes((Join-Path $mini 'tool.bat'), $enc.GetBytes("echo off`r`n"))
[System.IO.File]::WriteAllBytes((Join-Path $mini 'tool.ps1'), $enc.GetBytes("Write-Output 1`r`n"))
[System.IO.File]::WriteAllBytes((Join-Path $mini 'clean.sh'), $enc.GetBytes("# cafe`n"))
[void](Invoke-Git @('-C', $mini, 'add', '-A'))
[void](Invoke-Git @('-C', $mini, 'commit', '-q', '-m', 'baseline'))

Say ''
Say '=== gate 1: scripts/check-encoding.ps1 ==='
$r = Run-Gate $checker @('-Repo', $mini)
Chk ($r.code -eq 0) ('valid mini-repo passes (exit ' + $r.code + ') -- without this the failures below prove nothing')
Chk ($r.out -match 'CHECK-ENCODING OK') 'valid mini-repo prints the success verdict'
# No build/, no dist/, no vendor/ here, so sections 4..6 must SKIP LOUDLY.
Chk ($r.out -match '(?m)^\s*skip ') 'absent artifacts produce a visible skip line, not silence'
Chk ($r.out -match 'SHA256SUMS\.txt not rendered') 'the checksum-list skip is named'
Chk ($r.out -match 'no built exes') 'the exe sections skip explicitly'
$r = Run-Gate $checker @('-Repo', $mini, '-RequireArtifacts')
Chk ($r.code -ne 0) ('-RequireArtifacts turns the same repo red (exit ' + $r.code + ')')
Chk ($r.out -match 'SHA256SUMS\.txt absent') '  and names the missing checksum list'
Chk ($r.out -match 'no exes under dist/') '  and names the missing exes'
# Section 4 reads build/release-stage/SHA256SUMS.txt, a gitignored path with no
# tracked-file surface, so without a fixture here the whole section is
# unexercised. Two real defects lived behind exactly this gap: the "-ge 1"
# comment floor accepted a header that had lost two of its three lines to an -f
# precedence bug, and the blank-line guard counted blanks AFTER filtering the
# empty strings out, so an empty separator line (docs/CONVENTIONS.md 4.2) was
# invisible to it. Each case gets a green baseline first, because a case that
# only ever fails proves nothing.
$sumsDir = Join-Path $mini 'build\release-stage'
[void](New-Item -ItemType Directory -Force -Path $sumsDir)
$sumsFile = Join-Path $sumsDir 'SHA256SUMS.txt'
$hdr = @(('# tclwinkit {0} -- SHA-256 of the release assets' -f '0.1'),
         '# verify:  sha256sum -c SHA256SUMS.txt',
         '#      or:  certutil -hashfile <file> SHA256')
$names = @('tclwinkit-0.1-msvc-x64-console.exe', 'tclwinkit-0.1-msvc-x64-gui.exe',
           'tclwinkit-0.1-mingw-x64-console.exe', 'tclwinkit-0.1-mingw-x64-gui.exe',
           'tclwinkit-docs-0.1.zip')
$ent = @()
for ($i = 0; $i -lt $names.Count; $i++) { $ent += (('{0:x64}' -f ($i + 1)) + ' *' + $names[$i]) }
function Write-Sums([string[]]$L) {
    [System.IO.File]::WriteAllText($sumsFile, (($L -join "`n") + "`n"), $enc)
}
Write-Sums @($hdr + $ent)
$r = Run-Gate $checker @('-Repo', $mini)
Chk ($r.code -eq 0) ('valid checksum list passes (exit ' + $r.code + ') -- baseline for the three cases below')
Chk ($r.out -match 'comment header lines: 3') '  baseline counts all three header lines'
Chk ($r.out -match 'blank lines inside the list: 0') '  baseline reports zero blank lines'
Write-Sums @(@($hdr[0]) + $ent)
$r = Run-Gate $checker @('-Repo', $mini)
Chk ($r.code -ne 0) ('rejects a header that lost two of three lines (exit ' + $r.code + ')')
Chk ($r.out -match 'comment header lines: 1') '  and reports the surviving count'
Write-Sums @($hdr + @('') + $ent)
$r = Run-Gate $checker @('-Repo', $mini)
Chk ($r.code -ne 0) ('rejects an empty separator line inside the list (exit ' + $r.code + ')')
Chk ($r.out -match 'blank lines inside the list: 1') '  and names the blank line'
[System.IO.File]::WriteAllText($sumsFile, ((($hdr + $ent) -join "`r`n") + "`r`n"), $enc)
$r = Run-Gate $checker @('-Repo', $mini)
Chk ($r.code -ne 0) ('rejects a CRLF checksum list (exit ' + $r.code + ')')
Chk ($r.out -match 'FAIL SHA256SUMS\.txt: CR=0') '  and the failure is attributed to the CR/BOM line, not to a coincidence'
Remove-Item -LiteralPath $sumsFile -Force
[void](Remove-Item -LiteralPath $sumsDir -Recurse -Force)
Chk (-not (Test-Path -LiteralPath $sumsFile)) 'checksum fixture removed so the tracked-file cases start clean'

$defects = @(
    @{ n = 'CRLF in a .md worktree file';  b = { param($p) [System.IO.File]::WriteAllBytes($p, $enc.GetBytes("a`r`nb`r`n")) };            f = 'bad-crlf.md';  needle = 'WORKTREE WRONG' },
    @{ n = 'UTF-8 BOM in a .tcl file';     b = { param($p) [System.IO.File]::WriteAllBytes($p, ([byte[]](0xEF, 0xBB, 0xBF) + $enc.GetBytes('puts hi' + "`n"))) }; f = 'bad-bom.tcl'; needle = 'BOM:' },
    @{ n = 'non-ASCII byte in a .sh file'; b = { param($p) [System.IO.File]::WriteAllBytes($p, $enc.GetBytes("# caf" + [string][char]0x00E9 + "`n")) }; f = 'bad-ascii.sh'; needle = 'NON-ASCII:' },
    @{ n = 'LF where the rule wants CRLF'; b = { param($p) [System.IO.File]::WriteAllBytes($p, $enc.GetBytes("Write-Output 1`n")) };      f = 'bad-lf.ps1';   needle = 'CR MISMATCH' }
)
foreach ($d in $defects) {
    $fp = Join-Path $mini $d.f
    & $d.b $fp
    [void](Invoke-Git @('-C', $mini, 'add', '-A'))
    [void](Invoke-Git @('-C', $mini, 'commit', '-q', '-m', $d.n))
    $r = Run-Gate $checker @('-Repo', $mini)
    Chk ($r.code -ne 0) ('rejects: ' + $d.n + ' (exit ' + $r.code + ')')
    Chk ($r.out -match [regex]::Escape($d.needle)) ('  and names it (' + $d.needle + ')')
    # restore the baseline so the next defect is the only one present
    Remove-Item -LiteralPath $fp -Force
    [void](Invoke-Git @('-C', $mini, 'rm', '-q', '-f', $d.f))
    [void](Invoke-Git @('-C', $mini, 'commit', '-q', '-m', 'removed'))
}
# Section 3b (PowerShell syntax) needs a case of its own: a .ps1 that is CRLF
# (so the CR rule is satisfied) and ASCII-only, but does not parse. None of the
# byte sections see it. That gap is why bytes alone were never enough to claim a
# script is runnable, and why no CI job here executes the build scripts.
$syn = Join-Path $mini 'broken-syntax.ps1'
[System.IO.File]::WriteAllBytes($syn, $enc.GetBytes("if ( {`r`n"))
[void](Invoke-Git @('-C', $mini, 'add', '-A'))
[void](Invoke-Git @('-C', $mini, 'commit', '-q', '-m', 'syntax'))
$r = Run-Gate $checker @('-Repo', $mini)
Chk ($r.code -ne 0) ('rejects: a .ps1 that does not parse (exit ' + $r.code + ')')
Chk ($r.out -match 'SYNTAX:') '  and section 3b names it, not just the byte sections'
Remove-Item -LiteralPath $syn -Force
[void](Invoke-Git @('-C', $mini, 'rm', '-q', '-f', 'broken-syntax.ps1'))
[void](Invoke-Git @('-C', $mini, 'commit', '-q', '-m', 'remove syntax defect'))
$r = Run-Gate $checker @('-Repo', $mini)
Chk ($r.code -eq 0) ('baseline is clean again after removing it (exit ' + $r.code + ')')

# A repo with zero tracked files must not read as a pass: every loop below
# degenerates to "0 violations" and the gate turns green on nothing.
$bare = Join-Path $scratch 'bare'
[void](New-Item -ItemType Directory -Force -Path $bare)
[void](Invoke-Git @('init', '-q', '-b', 'main', $bare))
$r = Run-Gate $checker @('-Repo', $bare)
Chk ($r.code -ne 0) ('a 0-tracked-file repo fails instead of passing vacuously (exit ' + $r.code + ')')
Chk ($r.out -match 'must be > 0') '  and the failure names the vacuous-pass guard'

# ===========================================================================
# gate 2: scripts/verify-docs-artifact.ps1
# ===========================================================================
$verifier = Join-Path $Repo 'scripts/verify-docs-artifact.ps1'
if (-not (Test-Path -LiteralPath $verifier)) { Say ('FATAL: gate not found: ' + $verifier); exit 1 }
$zdir = Join-Path $scratch 'zip'
[void](New-Item -ItemType Directory -Force -Path $zdir)
$root = 'tclwinkit-docs-0.1'   # cosmetic: the gate reads the root from the archive

function New-DocsFixture([string]$outPath, [string]$defect = '') {
    # Build a docs archive that satisfies every assertion in
    # scripts/verify-docs-artifact.ps1 except, optionally, the one named by
    # $defect. The entry list is assembled FIRST so MANIFEST.txt describes it
    # truthfully; switches that change the file set or a byte count therefore
    # have to run before the manifest is generated, or the fixture would carry
    # a second unintended defect and the test would stop distinguishing cases.
    # Local, not $script:: the function runs nine times and each run must start
    # from an empty list; a script-scoped dictionary would accumulate entries
    # across fixtures and make the second case inherit the first one's defect.
    $files = New-Object System.Collections.Specialized.OrderedDictionary

    $files['LICENSE'] = $enc.GetBytes("MIT license text`n")
    $licDir = Join-Path $Repo 'LICENSES'
    if (-not (Test-Path -LiteralPath $licDir)) { throw ('LICENSES/ not found under ' + $Repo) }
    # Ordinal order, not culture order: Sort-Object -Property FullName compares
    # in the caller's locale and has no -Culture parameter on PS 5.1 (verified),
    # so the line order of MANIFEST.txt would vary per box.
    $rel = New-Object System.Collections.Generic.List[string]
    foreach ($f in (Get-ChildItem -LiteralPath $licDir -Recurse -File)) {
        $rel.Add($f.FullName.Substring($licDir.Length + 1).Replace('\', '/'))
    }
    $rel.Sort([System.StringComparer]::Ordinal)
    foreach ($rp in $rel) {
        $files[('LICENSES/' + $rp)] = [System.IO.File]::ReadAllBytes((Join-Path $licDir ($rp -replace '/', [System.IO.Path]::DirectorySeparatorChar)))
    }
    $files['THIRD-PARTY-NOTICES.md'] = $enc.GetBytes("# notices`n`n[lic](LICENSES/zlib/LICENSE)`n`n[repo](patches/README.md)`n")
    # The generated line must name a REAL commit with its REAL committer date,
    # because the gate resolves the stamp against `git show -s --format=%cI`.
    # An invented commit makes the BASELINE fixture fail for a reason of its own
    # and then every defect case reports the same finding.
    $headShort = ((Invoke-Git @('-C', $Repo, 'rev-parse', '--short', 'HEAD')) -join '').Trim()
    $headCi = ((Invoke-Git @('-C', $Repo, 'show', '-s', '--format=%cI', 'HEAD')) -join '').Trim()
    $dto = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse($headCi, [ref]$dto)) { throw ('cannot parse %cI: ' + $headCi) }
    $headUtc = $dto.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    if ($headShort -notmatch '^[0-9a-f]{7,40}$') { throw ('HEAD short sha unexpected: ' + $headShort) }
    $files['VERSIONS.txt'] = $enc.GetBytes("generated: $headUtc (commit $headShort)`n")

    # --- file-set / size-changing defects go HERE --------------------------
    if ($defect -eq 'BadTime') { $files['late.txt'] = $enc.GetBytes("text`n") }
    if ($defect -eq 'Backslash') { $files['weird\name.txt'] = $enc.GetBytes("x`n") }
    if ($defect -eq 'BomNotices') {
        $files['THIRD-PARTY-NOTICES.md'] = [byte[]](0xEF, 0xBB, 0xBF) + [byte[]]$files['THIRD-PARTY-NOTICES.md']
    }

    $manifestLines = @("# $root file manifest (" + $files.Count + " files)", '')
    foreach ($k in $files.Keys) {
        $manifestLines += ('{0,9}  {1}' -f ([int64]$files[$k].Length), $k)
    }
    $manifest = ($manifestLines -join "`n") + "`n"
    $files['MANIFEST.txt'] = $enc.GetBytes($manifest)

    # --- content-only defects go AFTER the manifest ------------------------
    if ($defect -eq 'GhostManifest') {
        $manifest = $manifest -replace ('\(' + ($files.Count - 1) + ' files\)'), ('(' + $files.Count + ' files)')
        $manifest += '        9  nope/gone.txt' + "`n"
        $files['MANIFEST.txt'] = $enc.GetBytes($manifest)
    }
    if ($defect -eq 'SizeLieManifest') {
        $rows = @($manifest -split "`n")
        for ($i = 0; $i -lt $rows.Count; $i++) {
            if ($rows[$i] -match '^(\s*)(\d+)(  LICENSE)$') {
                $rows[$i] = ('{0,9}' -f ([int64]$Matches[2] + 7)) + $Matches[3]
                break
            }
        }
        $files['MANIFEST.txt'] = $enc.GetBytes(($rows -join "`n"))
    }
    if ($defect -eq 'WallClockVersions') {
        # same real commit, wrong stamp: this is the "generator used Get-Date"
        # regression, so only the date may move
        $files['VERSIONS.txt'] = $enc.GetBytes("generated: 2031-01-01T00:00:00Z (commit $headShort)`n")
    }
    if ($defect -eq 'CrlfManifest') {
        # Decode first: -replace against a byte[] stringifies the whole array.
        # Parentheses required too: a method call binds tighter than -replace,
        # so GetBytes($cur -replace ...) parses as GetBytes with two arguments.
        $cur = $enc.GetString([byte[]]$files['MANIFEST.txt']) -replace "`r`n", "`n"
        $files['MANIFEST.txt'] = $enc.GetBytes(($cur -replace "`n", "`r`n"))
    }
    if ($defect -eq 'DropLicenseFile') {
        # $victim[0], not $victim: @() wraps the pipeline in an array, and
        # OrderedDictionary.Remove(object) then looks up the ARRAY as a key,
        # finds nothing, and silently deletes nothing -- the fixture would be
        # valid and the gate correctly green.
        $victim = @($files.Keys | Where-Object { $_ -like 'LICENSES/*' } | Select-Object -Last 1)
        if ($victim.Count -ne 1) { throw ('DropLicenseFile: expected one victim, got ' + $victim.Count) }
        $before = $files.Count
        $files.Remove($victim[0])
        if ($files.Count -ne $before - 1) { throw ('DropLicenseFile: removal did not take (' + $victim[0] + ')') }
    }

    $dir = Split-Path -Parent $outPath
    if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Force -Path $dir) }
    if (Test-Path -LiteralPath $outPath) { Remove-Item -LiteralPath $outPath -Force }
    $fsOut = [System.IO.File]::Create($outPath)
    $za = New-Object System.IO.Compression.ZipArchive($fsOut, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        $dirs = New-Object System.Collections.Generic.HashSet[string]
        # The archive root itself is an entry: the walk below only visits
        # RELATIVE paths, and the gate identifies the root by the first entry
        # named '<something>/', so without this seed the fixture reads as a bag
        # of loose files and every structural assertion fails at once.
        [void]$dirs.Add('')
        foreach ($k in $files.Keys) {
            $parts = $k -split '/'
            $acc = ''
            for ($i = 0; $i -lt $parts.Count - 1; $i++) {
                $acc += $parts[$i] + '/'
                [void]$dirs.Add($acc)
            }
        }
        $dl = New-Object System.Collections.Generic.List[string]
        $dl.AddRange([string[]]@($dirs))
        $dl.Sort([System.StringComparer]::Ordinal)
        foreach ($d in $dl) {
            $nm = $root + '/' + $d
            if ($d -eq '') { $nm = $root + '/' }
            $e = $za.CreateEntry($nm)
            $e.LastWriteTime = $epoch
        }
        foreach ($k in $files.Keys) {
            $when = $epoch
            if ($defect -eq 'BadTime' -and $k -eq 'late.txt') { $when = [datetime]::new(2026, 10, 28, 9, 0, 0) }
            $e = $za.CreateEntry($root + '/' + $k)
            $e.LastWriteTime = $when
            $s = $e.Open()
            try { $b = $files[$k]; $s.Write($b, 0, $b.Length) } finally { $s.Dispose() }
        }
    } finally {
        $za.Dispose(); $fsOut.Dispose()
    }
    return $outPath
}
function Test-Fixture([string]$outPath) {
    # Entry count, or -1 when the archive cannot be opened at all. A fixture is
    # itself software and it already failed once this way, so nothing is handed
    # to a gate before this says the archive is readable.
    if (-not (Test-Path -LiteralPath $outPath)) { return -1 }
    if ((Get-Item -LiteralPath $outPath).Length -lt 22) { return -1 }   # bare EOCD is 22 B
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $z = [System.IO.Compression.ZipFile]::OpenRead($outPath)
        try { return $z.Entries.Count } finally { $z.Dispose() }
    } catch { return -1 }
    $ErrorActionPreference = $prev
}

Say ''
Say '=== gate 2: scripts/verify-docs-artifact.ps1 ==='
$baseline = Join-Path $zdir 'baseline.zip'
$prev = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try { [void](New-DocsFixture $baseline '') } catch { Say ('  fixture error: ' + $_.Exception.Message) }
$ErrorActionPreference = $prev
$bn = Test-Fixture $baseline
Chk ($bn -gt 50) ('baseline fixture opens as a zip with ' + $bn + ' entries (must be > 50)')
$r = Run-Gate $verifier @('-Zip', $baseline)
Chk ($r.code -eq 0) ('valid synthetic archive passes (exit ' + $r.code + ')')
if ($r.code -ne 0) {
    @($r.out -split "`r?`n" | Where-Object { $_ -match 'FAIL' }) | Select-Object -First 6 | ForEach-Object { '      ' + $_.Trim() }
}
$cases = @(
    @{ n = 'entry not pinned to the DOS epoch';   d = 'BadTime';           needle = 'NOT PINNED' },
    @{ n = 'backslash in an entry name';          d = 'Backslash';         needle = 'backslash entry names' },
    @{ n = 'MANIFEST lists a path not archived';   d = 'GhostManifest';     needle = 'LISTED BUT ABSENT' },
    @{ n = 'MANIFEST size disagrees by 7 bytes';   d = 'SizeLieManifest';   needle = 'SIZE DIFFERS' },
    @{ n = 'VERSIONS stamp is not its commit';     d = 'WallClockVersions'; needle = 'VERSIONS.txt stamp' },
    @{ n = 'MANIFEST.txt shipped as CRLF';         d = 'CrlfManifest';      needle = 'LF-only=False' },
    @{ n = 'NOTICES shipped with a BOM';           d = 'BomNotices';        needle = 'no BOM=False' },
    @{ n = 'a LICENSES file dropped from the zip'; d = 'DropLicenseFile';   needle = 'MISSING IN ZIP' }
)
foreach ($c in $cases) {
    $zp = Join-Path $zdir ('broken-' + $c.d + '.zip')
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { [void](New-DocsFixture $zp $c.d) } catch { Say ('  fixture error: ' + $_.Exception.Message) }
    $ErrorActionPreference = $prev
    $n = Test-Fixture $zp
    Chk ($n -gt 50) ('fixture opens with ' + $n + ' entries: ' + $c.n)
    if ($n -le 50) { continue }
    $r = Run-Gate $verifier @('-Zip', $zp)
    Chk ($r.code -ne 0) ('  rejects: ' + $c.n + ' (exit ' + $r.code + ')')
    Chk ($r.out -match [regex]::Escape($c.needle)) ('    and names it (' + $c.needle + ')')
}
$r = Run-Gate $verifier @('-Zip', (Join-Path $zdir 'nope.zip'))
Chk ($r.code -ne 0) ('a missing archive exits nonzero instead of reporting a clean run (exit ' + $r.code + ')')

# ===========================================================================
# gate 3: scripts/link-audit.ps1
# ===========================================================================
# The auditor walks every relative link and every #fragment of the 18 tracked
# markdown files and reports zero findings on the real repository. "Zero" from a
# tool that has never been observed to fire is not evidence, and unlike the
# encoding gate this one guards a claim a reader of the public repository acts
# on: that the documentation's cross-links resolve. Six branches of its decision
# are exercised here, one per case.
Say ''
Say '=== gate 3: scripts/link-audit.ps1 ==='
$laTool = Join-Path $Repo 'scripts/link-audit.ps1'
if (-not (Test-Path -LiteralPath $laTool)) { Say ('FATAL: gate not found: ' + $laTool); exit 1 }

function Run-LinkAudit([string]$path) {
    $prev2 = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $o2 = (& powershell -NoProfile -ExecutionPolicy Bypass -File $laTool -Repo $path 2>&1 | Out-String)
    $c2 = $LASTEXITCODE
    $ErrorActionPreference = $prev2
    return @{ code = $c2; out = [string]$o2 }
}
function Write-FixFile([string]$fxBase, [string]$fxRel, [string]$fxBody) {
    $fp2 = Join-Path $fxBase ($fxRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    $dir2 = Split-Path -Parent $fp2
    if (-not (Test-Path -LiteralPath $dir2)) { [void](New-Item -ItemType Directory -Force -Path $dir2) }
    [System.IO.File]::WriteAllBytes($fp2, $enc.GetBytes($fxBody))
    return $fp2
}

$laGood = Join-Path $scratch 'links-good'
[void](New-Item -ItemType Directory -Force -Path $laGood)
[void](Invoke-Git @('init', '-q', '-b', 'main', $laGood))
[void](Invoke-Git @('-C', $laGood, 'config', 'user.email', 'fixture@invalid.example'))
[void](Invoke-Git @('-C', $laGood, 'config', 'user.name', 'fixture'))
# .gitignore mirrors the real repository: without it the "gitignored target"
# case below would take the "not tracked" branch and that branch would never run.
[void](Write-FixFile $laGood '.gitignore' "build/`ndist/`nvendor/`n")
[void](Write-FixFile $laGood 'docs/NOTE.md' "# note`n")
[void](Write-FixFile $laGood 'README.md' "# t`n`n[docs](docs/NOTE.md)`n[anchor](#t)`n[frag](docs/NOTE.md#note)`n[ext](https://example.com/x)`n[dir](docs/)`n")
[void](Invoke-Git @('-C', $laGood, 'add', '-A'))
[void](Invoke-Git @('-C', $laGood, 'commit', '-q', '-m', 'baseline'))
$r = Run-LinkAudit $laGood
Chk ($r.code -eq 0) ('valid mini-repo passes (exit ' + $r.code + ') -- without this the findings below prove nothing')
Chk ($r.out -match 'LINK-AUDIT OK') '  and prints the success verdict'
Chk ($r.out -match 'relative=[1-9]') ('  and walked the relative links (' + ((@($r.out -split "`r?`n") | Where-Object { $_ -match 'links: total' }) -join '').Trim() + ')')
# The anchor leg must be seen PASSING a real fragment here, not only failing one
# later: a check that can only ever report a finding is indistinguishable from a
# check that reports findings because it never looked. This is the exact shape
# that made the first version of the auditor vacuous (26 anchors counted, zero
# resolved), so it is asserted on the baseline, not on a defect case.
Chk ($r.out -match 'fragments actually resolved against headings: [2-9]') '  and resolved at least two fragments against headings (the anchor leg is not vacuous)'
Chk ($r.out -notmatch 'DEAD ANCHOR|DEAD FRAGMENT') '  and the baseline fragments PASS, so a later DEAD FRAGMENT is about the defect and not about the leg'

# Six distinct branches, so no two cases are the same test wearing a different
# name. Each case owns its FILE: the dead-link case originally overwrote
# docs/NOTE.md, which the baseline links to, so tearing it down created a second,
# unintended dead link and every later case reported 2 findings instead of 1.
$laCases = @(
    @{ n = 'dead relative link';           file = 'docs/A-dead.md';      body = "[gone](../nope.md)`n";           needle = 'DEAD LINK';   pre = '' },
    @{ n = 'link into a gitignored path';  file = 'docs/B-ignored.md';   body = "[dist](../dist/kit.exe)`n";      needle = 'GITIGNORED';  pre = @('dist/kit.exe', 'MZ') },
    @{ n = 'untracked-but-present target'; file = 'docs/C-untracked.md'; body = "[orphan](./drafts/orphan.md)`n"; needle = 'NOT tracked'; pre = @('docs/drafts/orphan.md', 'orphan') },
    @{ n = 'dead in-file anchor';          file = 'docs/D-anchor.md';    body = "# host`n`n[x](#no-such-heading)`n"; needle = 'DEAD ANCHOR'; pre = '' },
    @{ n = 'dead fragment in a good file'; file = 'docs/E-frag.md';      body = "[note](NOTE.md#nope)`n";         needle = 'DEAD FRAGMENT'; pre = '' },
    # The heading below sits inside a fence: GitHub does not link to it and
    # neither may the auditor. Backticks are single-quoted so they stay literal.
    @{ n = 'anchor only inside a code fence'; file = 'docs/F-fence.md';  body = (@('[x](#inside)', '```', '# inside', '```', '') -join "`n"); needle = 'DEAD ANCHOR'; pre = '' }
)
foreach ($lc in $laCases) {
    if ($lc.pre) { [void](Write-FixFile $laGood $lc.pre[0] $lc.pre[1]) }
    [void](Write-FixFile $laGood $lc.file $lc.body)
    # Stage ONLY the linking document. `git add -A` here would defeat the point of
    # the untracked case: it stages docs/drafts/orphan.md, the target becomes
    # tracked, the "on disk but not in the index" branch never runs, and the case
    # degrades into a passing link that exits 0 (measured: it did, twice).
    [void](Invoke-Git @('-C', $laGood, 'add', '--', $lc.file))
    [void](Invoke-Git @('-C', $laGood, 'commit', '-q', '-m', $lc.n))
    $r = Run-LinkAudit $laGood
    $laNf = @($r.out -split "`r?`n" | Where-Object { $_ -match '^FINDING ' }).Count
    Chk ($r.code -ne 0) ('rejects: ' + $lc.n + ' (exit ' + $r.code + ')')
    Chk ($laNf -eq 1) ('  reports exactly one finding, not two (findings=' + $laNf + ')')
    Chk ($r.out -match [regex]::Escape($lc.needle)) ('  and names it (' + $lc.needle + ')')
    # tear down and prove the baseline is whole again
    [void](Invoke-Git @('-C', $laGood, 'rm', '-q', '-f', $lc.file))
    [void](Invoke-Git @('-C', $laGood, 'commit', '-q', '-m', ('removed ' + $lc.n)))
    $rb = Run-LinkAudit $laGood
    Chk ($rb.code -eq 0) ('  baseline passes again after teardown (exit ' + $rb.code + ')')
}

$laEmpty = Join-Path $scratch 'links-empty'
[void](New-Item -ItemType Directory -Force -Path $laEmpty)
[void](Invoke-Git @('init', '-q', '-b', 'main', $laEmpty))
[void](Write-FixFile $laEmpty 'a.txt' "x`n")
[void](Invoke-Git @('-C', $laEmpty, 'add', '-A'))
[void](Invoke-Git @('-C', $laEmpty, 'commit', '-q', '-m', 'no md'))
$r = Run-LinkAudit $laEmpty
Chk ($r.code -ne 0) ('a repo with 0 tracked .md fails instead of passing vacuously (exit ' + $r.code + ')')
Chk ($r.out -match 'must be > 0') '  and names the guard'

# ===========================================================================
# gate 4: scripts/source-parity.ps1
# ===========================================================================
# docs/SOURCES.md and scripts/fetch-vendor.ps1 are two hand-written notations of
# one fact -- where the 15 vendor archives come from -- and the direction that
# matters for licensing is the one a reader cannot see: an origin the manifest
# fetches but the document does not publish.
Say ''
Say '=== gate 4: scripts/source-parity.ps1 ==='
$spTool = Join-Path $Repo 'scripts/source-parity.ps1'
if (-not (Test-Path -LiteralPath $spTool)) { Say ('FATAL: gate not found: ' + $spTool); exit 1 }
$spFix = Join-Path $scratch 'parity'

$hex = '0123456789abcdef'
$hex64 = $hex * 4                                  # 64 chars, ends in 'f'
$dTcl = $hex64
$dImg = ('fedcba9876543210' * 4)                   # 64, ends in '0' but BACKTICKED
$dTt = $hex64.Substring(0, 63) + '8'               # 64, ends in a digit, BACKTICKED
$dPin = $hex64.Substring(0, 63) + '0'              # 64, ends in a digit, BARE  <-- regression shape
$uTcl = 'https://example.invalid/tcl.tar.gz'
$uImg = 'https://example.invalid/img.tar.gz'
$uTt = 'https://example.invalid/tt.tar.gz'
$uPin = 'https://example.invalid/tt-pin.tar.gz'
$fTcl = 'tcl9.0.4-src.tar.gz'
$fImg = 'Img-2.1.2.tar.gz'
$fTt = 'tktreectrl-2.5.1.tar.gz'

$spDoc = @(
    '# Vendor sources'
    ''
    '| component | version | source | method | SHA-256 | size, B |'
    '|---|---|---|---|---|---|'
    ('| Tcl | 9.0.4 | `' + $uTcl + '` | GET | `' + $dTcl + '` | 11 866 337 |')
    ('| Img | 2.1.2 | `' + $uImg + '` | GET | `' + $dImg + '` | 12 544 404 |')
    ('| treectrl | 2.5.2 | `' + $uTt + '` | codeload | `' + $dTt + '` | 998 346 |')
    ''
    'Pinned form of the movable ref (bare, as the real map writes it):'
    ''
    '```'
    ('tktreectrl    ' + $uPin)
    ($dPin + '   999 449 B')
    '```'
    ''
    'Archive -> tree:'
    ''
    ('* `' + $fTcl + '` -> build/tcl9.0.4/')
    ('* `' + $fImg + '` -> build/ext/Img-2.1.2/')
    ('* `' + $fTt + '` -> build/ext/')
    ''
) -join "`n"

$spScr = @(
    '$Rows = @('
    ("    @{ c = 'Tcl';  f = '$fTcl'; k = 'tgz'; t = 'tcl9.0.4/';")
    ("       u = '$uTcl';")
    ("       d = '$dTcl'; s = 11866337 },")
    ("    @{ c = 'Img';  f = '$fImg'; k = 'tgz'; t = 'Img-2.1.2/';")
    ("       u = '$uImg';")
    ("       d = '$dImg'; s = 12544404 },")
    ("    @{ c = 'tktreectrl'; f = '$fTt'; k = 'tgz'; t = ''; movable = `$true;")
    ("       u = '$uTt';")
    ("       d = '$dTt'; s = 998346;")
    ("       pu = '$uPin';")
    ("       pd = '$dPin'; pss = 999449 }")
    ')'
    ''
) -join "`n"

function Write-Parity([string]$docTxt, [string]$scrTxt) {
    if (Test-Path -LiteralPath $spFix) { Remove-Item -LiteralPath $spFix -Recurse -Force }
    [void](New-Item -ItemType Directory -Force -Path (Join-Path $spFix 'docs'))
    [void](New-Item -ItemType Directory -Force -Path (Join-Path $spFix 'scripts'))
    [System.IO.File]::WriteAllBytes((Join-Path $spFix 'docs\SOURCES.md'), $enc.GetBytes(($docTxt -replace "`r`n", "`n")))
    [System.IO.File]::WriteAllBytes((Join-Path $spFix 'scripts\fetch-vendor.ps1'), $enc.GetBytes(($scrTxt -replace "`r`n", "`n")))
}
function Run-SourceParity {
    $prev2 = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $o2 = (& powershell -NoProfile -ExecutionPolicy Bypass -File $spTool -RepoRel $spFix 2>&1 | Out-String)
    $c2 = $LASTEXITCODE
    $ErrorActionPreference = $prev2
    return @{ code = $c2; out = [string]$o2 }
}

# The fixture deliberately reproduces the shape that broke the checker on the
# real documents: the pinned digest is written BARE with its size after it, so
# stripping whitespace from the whole line merges the tail of the hex digest into
# the size. Three assertions lock that shape in -- a future edit that makes the
# fixture "tidier" must not be able to retire the regression quietly.
$spPinLine = ((@($spDoc -split "`n") | Where-Object { $_.Contains($dPin) }) -join '')
$spTtLine = ((@($spDoc -split "`n") | Where-Object { $_.Contains($dTt) }) -join '')
Chk ($dPin.Length -eq 64 -and [char]::IsDigit($dPin[$dPin.Length - 1])) 'fixture: the pinned digest is 64 hex and ENDS IN A DIGIT'
Chk ($spPinLine.Contains($dPin) -and -not $spPinLine.Contains([string][char]96)) 'fixture: that digest appears BARE (no backticks) next to its size'
Chk ($spTtLine.Contains([string][char]96)) 'fixture: the branch digest is backticked, so only the pin line exercises the merge'

Write-Parity $spDoc $spScr
$r = Run-SourceParity
Chk ($r.code -eq 0) ('valid fixture passes (exit ' + $r.code + ') -- without this the findings below prove nothing')
if ($r.code -ne 0) { foreach ($ln in ($r.out -split "`r?`n")) { if ($ln.Trim()) { Say ('      | ' + $ln.Trim()) } } }
Chk ($r.out -match 'rows fully harvested: 3') '  and harvested all 3 manifest rows (a count of 0 means the notation was not understood)'
Chk ($r.out -match 'pin triples: 1') '  and exercised the pinned-ref leg once'
Chk ($r.out -match 'with its digest: 3/3') '  and matched every size on its digest line'
Chk ($r.out -match 'tktreectrl -> treectrl') '  and reported the declared name alias'
Chk ($r.out -match 'SOURCE-PARITY OK') '  and printed the success verdict'

# Twelve branches. The last three are vacuity guards, not content defects: they
# ask what happens when the parser understands nothing at all, which is the case
# a parity check is most likely to survive silently.
$spCases = @(
    @{ n = 'URL fetched but not published';            docMut = { param($di, $si) $di.Replace($uTcl, 'gone') }; scrMut = $null; needle = 'URL fetched but not published' },
    @{ n = 'digest enforced but not published';        docMut = { param($di, $si) $di.Replace($dTcl, 'gone') }; scrMut = $null; needle = 'SHA-256 enforced but not published' },
    @{ n = 'size moved off the digest line';           docMut = { param($di, $si) $di.Replace('| 11 866 337 |', '| - |') }; scrMut = $null; needle = 'is not on any' },
    @{ n = 'vendored filename not published';          docMut = { param($di, $si) $di.Replace($fTcl, 'gone') }; scrMut = $null; needle = 'vendored filename not published' },
    @{ n = 'URL in the map but never fetched';         docMut = { param($di, $si) $di.Replace('| Img |', ('| Ghost | 1.0 | `https://example.invalid/ghost.tar.gz` | GET | `0` | 1 |' + "`n" + '| Img |')) }; scrMut = $null; needle = 'never fetched by' },
    @{ n = 'component row renamed (alias must not swallow)'; docMut = { param($di, $si) $di.Replace('| treectrl |', '| Renamed |') }; scrMut = $null; needle = 'no table row' },
    @{ n = 'pinned URL not published';                 docMut = { param($di, $si) $di.Replace($uPin, 'gone') }; scrMut = $null; needle = 'pinned URL not published' },
    @{ n = 'pinned digest not published';              docMut = { param($di, $si) $di.Replace($dPin, 'gone') }; scrMut = $null; needle = 'pinned SHA-256 not published' },
    @{ n = 'pinned size off the pinned line';          docMut = { param($di, $si) $di.Replace(($dPin + '   999 449 B'), ($dPin + '   B')) }; scrMut = $null; needle = 'pinned size' },
    @{ n = 'manifest row lost a field';                docMut = $null; scrMut = { param($si, $di) $si.Replace('; s = 11866337', '') }; needle = 'did not yield' },
    @{ n = 'manifest notation unrecognised';           docMut = $null; scrMut = { param($si, $di) $si.Replace('@{', '[').Replace(' }', ']') }; needle = 'yielded 0 rows' },
    @{ n = 'map has no URL-bearing table rows';        docMut = { param($di, $si) $di.Replace($uTcl, 'gone').Replace($uImg, 'gone').Replace($uTt, 'gone') }; scrMut = $null; needle = '0 URL-bearing table rows' }
)
foreach ($sc in $spCases) {
    $spDt = $spDoc
    $spSt = $spScr
    if ($sc.docMut) { $spDt = & ($sc.docMut) $spDoc $spScr }
    if ($sc.scrMut) { $spSt = & ($sc.scrMut) $spScr $spDoc }
    Write-Parity $spDt $spSt
    $r = Run-SourceParity
    Chk ($r.code -ne 0) ('rejects: ' + $sc.n + ' (exit ' + $r.code + ')')
    Chk ($r.out -match [regex]::Escape($sc.needle)) ('  and names it (' + $sc.needle + ')')
}
Write-Parity $spDoc $spScr
$r = Run-SourceParity
Chk ($r.code -eq 0) ('the undamaged fixture passes again after all 12 injections (exit ' + $r.code + ')')

# ===========================================================================
# the encoding gates, against the real repository and the real artifacts
# ===========================================================================
Say ''
Say '=== the two encoding gates against this checkout ==='
# Gates 3 and 4 are NOT re-run against the real repository here: encoding.yml runs each
# of them as its own step, so doing it twice would only double the wall time of
# the job that has to stay cheap. Their ability to fail is what this file proves.
$hasArtifacts = (Test-Path -LiteralPath (Join-Path $Repo 'dist/tclwinkit-msvc.exe'))
$r = Run-Gate $checker @('-Repo', $Repo)
Chk ($r.code -eq 0) ('check-encoding on this checkout (exit ' + $r.code + $(if ($hasArtifacts) { ', artifacts present' } else { ', no artifacts' }) + ')')
if ($hasArtifacts) {
    $r2 = Run-Gate $checker @('-Repo', $Repo, '-RequireArtifacts')
    Chk ($r2.code -eq 0) ('check-encoding -RequireArtifacts with artifacts present (exit ' + $r2.code + ')')
    $r3 = Run-Gate $verifier @()
    Chk ($r3.code -eq 0) ('verify-docs-artifact on the real dist/ archive (exit ' + $r3.code + ')')
} else {
    Say '  skip  no built exes in dist/; the -RequireArtifacts leg and the real-archive leg need them'
}

Say ''
if (-not $Keep) {
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
    Say ('scratch removed: ' + $scratch)
} else {
    Say ('scratch kept: ' + $scratch)
}
Say ('RESULT: failures ' + $fail)
if ($fail -eq 0) { 'CHECK-GATES-SELFTEST OK' } else { 'CHECK-GATES-SELFTEST FAILED' }
if ($fail -gt 200) { exit 200 }
exit $fail
