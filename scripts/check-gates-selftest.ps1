# check-gates-selftest.ps1 -- negative control for the two gates in scripts/.
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
# the gates themselves, against the real repository and the real artifacts
# ===========================================================================
Say ''
Say '=== both gates against this checkout ==='
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
