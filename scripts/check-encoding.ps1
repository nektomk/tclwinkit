# check-encoding.ps1 -- machine-readable gate for the three-level encoding rule
# (docs/CONVENTIONS.md) plus the two determinism gates that belong with it: the
# PE TimeDateStamp of the shipped exes and the absence of builder state (our own
# commit hash) inside them.
#
# Contract:
#   * ASCII-only source, per CONVENTIONS section 5.
#   * Read-only w.r.t. the repository. -Report writes one file outside it.
#   * Exit code = number of failed assertions, so CI needs no log parsing.
#   * Works on a fresh clone with no build/, no dist/, no vendor/. Sections
#     that need built artifacts SKIP LOUDLY unless -RequireArtifacts is given,
#     in which case their absence is itself a failure. A gate that silently
#     passes because the thing it guards is missing guards nothing.
#   * File counts are MEASURED, never hardcoded: the tracked set grows with
#     every block, and a stale constant in the checker turns it into a lie
#     (that is how .gitattributes came to say "123 tracked files").
param(
    [string]$Repo = '',
    [string]$Report = '',
    [switch]$RequireArtifacts
)
$ErrorActionPreference = 'Continue'
if (-not $Repo) {
    # $PSScriptRoot is not populated during parameter binding on PS 5.1, hence
    # this is done in the body.
    $Repo = Split-Path -Parent $PSScriptRoot
}
if (-not (Test-Path -LiteralPath $Repo)) {
    Write-Output ('FATAL: repo not found: ' + $Repo)
    exit 1
}
Set-Location -LiteralPath $Repo

$fail = 0
$log = New-Object System.Text.StringBuilder
function Say([string]$s) { [void]$log.AppendLine($s) }
function Rule([string]$t) { Say ''; Say ('=== ' + $t + ' ===') }
function Chk([bool]$ok, [string]$what) {
    if (-not $ok) { $script:fail++ }
    Say ('  ' + $(if ($ok) { 'ok   ' } else { 'FAIL ' }) + $what)
}
function Skip([string]$what) { Say ('  skip ' + $what) }

# Run git without letting a benign stderr line abort the script: native stderr
# under ErrorActionPreference=Stop raises NativeCommandError, which is how a
# healthy repository gets reported as broken.
function Invoke-Git([string[]]$args2) {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $o = @(& git @args2 2>&1 | Out-String -Stream)
    $ErrorActionPreference = $prev
    return ,@($o | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

Rule '0. SCOPE'
Say ('repo             : ' + $Repo)
Say ('git              : ' + ((Invoke-Git @('--version')) -join ''))
Say ('powershell       : ' + $PSVersionTable.PSVersion.ToString())
Say ('os               : ' + [System.Runtime.InteropServices.RuntimeInformation]::OSDescription)
Say ('require artifacts: ' + $RequireArtifacts.IsPresent)

# --- 1. index / worktree EOL and attributes, via regex-parsed --eol ----------
# Parse with a regex, not Split("`t"): the i/, w/, attr/ fields are separated by
# SPACES and the tab precedes only the path. A naive tab split yields one field
# and three empties, so the checker reports "every file violates" on a perfectly
# clean tree -- its own failure becomes indistinguishable from the failure it is
# testing for. Documented in CONVENTIONS section 7.
Rule '1. git ls-files --eol'
$eolRows = Invoke-Git @('ls-files', '--eol')
$paths = @{}
$total = 0; $unparsed = 0
$idxNonLf = 0; $wtWrong = 0; $attrWrong = 0
$crlfFiles = 0; $lfFiles = 0
foreach ($row in $eolRows) {
    $m = [regex]::Match($row, '^(i/\S+)\s+(w/\S+)\s+(attr/\S.*?)\t(.+)$')
    if (-not $m.Success) { $unparsed++; Say ('  UNPARSED: ' + $row); continue }
    $total++
    $idx = $m.Groups[1].Value; $wt = $m.Groups[2].Value
    $attr = $m.Groups[3].Value; $path = $m.Groups[4].Value
    $paths[$path] = 'tracked'
    if ($idx -ne 'i/lf') { $idxNonLf++; Say ('  INDEX NOT LF: ' + $path + '  ' + $idx) }
    $isScript = $path -match '\.(bat|ps1)$'
    $wantWt = if ($isScript) { 'w/crlf' } else { 'w/lf' }
    if ($wt -ne $wantWt) { $wtWrong++; Say ('  WORKTREE WRONG: ' + $path + '  ' + $wt + ', expected ' + $wantWt) }
    if ($isScript) {
        $crlfFiles++
        if ($attr -notmatch 'eol=crlf') { $attrWrong++; Say ('  ATTR WRONG: ' + $path + '  ' + $attr) }
    } else {
        $lfFiles++
        if ($attr -notmatch 'eol=lf') { $attrWrong++; Say ('  ATTR WRONG: ' + $path + '  ' + $attr) }
    }
}
Say ('tracked files     : ' + $total + '  (crlf worktree: ' + $crlfFiles + ', lf: ' + $lfFiles + ')')
# A zero-file run is not a pass. If git is missing, or this is not a checkout,
# every loop below degenerates to "0 violations" and the gate turns green on
# nothing -- the same vacuous-success class that made an earlier reproducibility
# measurement report 5/5 against a stale dist/.
Chk ($total -gt 0) ('tracked file count ' + $total + ' (must be > 0: 0 means the gate ran on nothing)')
Chk ($unparsed -eq 0) ('unparsed --eol rows: ' + $unparsed + ' (a silent output-format change must not read as success)')
Chk ($idxNonLf -eq 0) ('index entries not i/lf: ' + $idxNonLf)
Chk ($wtWrong -eq 0) ('worktree EOL mismatches: ' + $wtWrong)
Chk ($attrWrong -eq 0) ('attribute mismatches: ' + $attrWrong)
Chk (($crlfFiles + $lfFiles) -eq $total) ('crlf + lf = tracked: ' + $crlfFiles + ' + ' + $lfFiles + ' = ' + $total)

# Pending files are invisible to `git ls-files --eol` but the next commit carries
# them and .gitattributes normalizes them on add, so they must go through the
# byte-level sections or the audit is blind about exactly the files being added.
$pend = Invoke-Git @('ls-files', '--others', '--exclude-standard')
Say ('pending files     : ' + $pend.Count)
foreach ($p in $pend) { $paths[$p] = 'pending' }

# --- 2. worktree bytes: no BOM, CR exactly where the rule wants it -----------
# The EOL machinery cannot see a BOM, and `--eol` says nothing about a file that
# is not in the index yet, hence the byte-level pass over tracked + pending.
Rule '2. worktree bytes'
$bom = 0; $crMis = 0; $missing = 0
foreach ($p in ($paths.Keys | Sort-Object)) {
    $fp = Join-Path $Repo $p
    if (-not (Test-Path -LiteralPath $fp)) { $missing++; Say ('  MISSING ON DISK: ' + $p); continue }
    $b = [System.IO.File]::ReadAllBytes($fp)
    if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) {
        $bom++; Say ('  BOM: ' + $p)
    }
    $wantCr = ($p -match '\.(bat|ps1)$')
    $hasCr = ($b -contains 13)
    if ($wantCr -ne $hasCr) {
        $crMis++; Say ('  CR MISMATCH: ' + $p + '  hasCR=' + $hasCr + ' expected=' + $wantCr)
    }
}
Chk ($missing -eq 0) ('tracked/pending files missing on disk: ' + $missing)
Chk ($bom -eq 0) ('files carrying a BOM: ' + $bom)
Chk ($crMis -eq 0) ('files whose CR presence disagrees with the rule: ' + $crMis)

# --- 3. ASCII-only for .ps1 / .bat / .sh -------------------------------------
# Byte-level on purpose: PS 5.1 decodes a BOM-less .ps1 by the machine code page,
# so "reading it as text" is the very thing under test (CONVENTIONS section 5).
Rule '3. non-ASCII bytes in scripts'
$nonAscii = 0; $scriptCount = 0
foreach ($p in ($paths.Keys | Sort-Object)) {
    if ($p -notmatch '\.(ps1|bat|sh)$') { continue }
    $scriptCount++
    $fp = Join-Path $Repo $p
    if (-not (Test-Path -LiteralPath $fp)) { continue }
    $b = [System.IO.File]::ReadAllBytes($fp)
    $n = @($b | Where-Object { $_ -gt 127 }).Count
    if ($n -gt 0) { $nonAscii++; Say ('  NON-ASCII: ' + $p + '  ' + $n + ' bytes') }
}
Say ('script files      : ' + $scriptCount)
Chk ($nonAscii -eq 0) ('script files with non-ASCII bytes: ' + $nonAscii)
Chk ($scriptCount -gt 0) ('script file count ' + $scriptCount + ' (must be > 0)')

# --- 3b. every tracked .ps1 must actually parse ------------------------------
# Bytes alone do not make a script runnable, and no CI job here executes the
# build scripts, so a syntax break in one of them would reach main unnoticed.
# The parser is called with the arguments in the right order: ParseFile takes
# (string, ref ReadOnlyCollection<Token>, ref ParseError[]) -- TOKENS FIRST.
# Swapping them leaves the "errors" variable holding the token list, .Count is
# nonzero forever, and every valid script reports a failure with an empty
# message (measured: five bogus FAILs on a correct workflow file).
Rule '3b. PowerShell syntax'
$psCount = 0; $psBad = 0
foreach ($p in ($paths.Keys | Sort-Object)) {
    if ($p -notmatch '\.ps1$') { continue }
    $psCount++
    $fp = Join-Path $Repo $p
    if (-not (Test-Path -LiteralPath $fp)) { continue }
    $toks = $null; $errs = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($fp, [ref]$toks, [ref]$errs)
    if ($errs -and $errs.Count) {
        $psBad++
        Say ('  SYNTAX: ' + $p + '  ' + $errs[0].Message + '  (line ' + $errs[0].Extent.StartLineNumber + ')')
    }
}
Say ('ps1 files parsed  : ' + $psCount)
Chk ($psBad -eq 0) ('ps1 files that fail to parse: ' + $psBad)
Chk ($psCount -gt 0) ('ps1 file count ' + $psCount + ' (must be > 0)')

# --- 4. the generated checksum list ---------------------------------------
# publish-release.ps1 renders it into build/release-stage/ (it lists the
# PUBLISHED asset names, which differ from the dist/ file names), so both
# locations are searched. The draft of this gate looked only under dist/ and
# therefore skipped the whole section in silence while reporting a clean run --
# the vacuous-pass class this -RequireArtifacts switch exists to expose.
Rule '4. SHA256SUMS.txt'
$sumsCandidates = @('build/release-stage/SHA256SUMS.txt', 'dist/SHA256SUMS.txt')
$sums = $null
foreach ($rel in $sumsCandidates) {
    $fp = Join-Path $Repo $rel
    if (Test-Path -LiteralPath $fp) { $sums = $fp; break }
}
if (-not $sums) {
    if ($RequireArtifacts) { Chk $false ('SHA256SUMS.txt absent (looked in: ' + ($sumsCandidates -join ', ') + ')') }
    else { Skip 'SHA256SUMS.txt not rendered yet (publish-release.ps1 produces it)' }
} else {
    $b = [System.IO.File]::ReadAllBytes($sums)
    $isBom = ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
    Chk ((-not ($b -contains 13)) -and (-not $isBom)) ('SHA256SUMS.txt: CR=0, no BOM, ' + $b.Length + ' B  (' + $sums.Substring($Repo.Length + 1) + ')')
    # The blank-line guard used to be VACUOUS: the old code first dropped every
    # empty element ("Where-Object { $_ -ne '' }") and only then counted
    # '^\s*$', so a truly empty separator line -- the exact defect documented in
    # docs/CONVENTIONS.md 4.2 -- could never be seen by it. Count on the raw split
    # instead, minus the one empty element a trailing newline legitimately produces.
    $raw = @(([System.Text.Encoding]::UTF8.GetString($b) -split "`n"))
    if ($raw.Count -gt 0 -and $raw[$raw.Count - 1] -eq '') { $raw = @($raw[0..($raw.Count - 2)]) }
    $blank = @($raw | Where-Object { $_.Trim() -eq '' }).Count
    $lines = @($raw | Where-Object { $_ -ne '' })
    # A blank line inside the list makes `sha256sum -c --strict` fail on the
    # user's machine, which is the public instruction in README.
    Chk ($blank -eq 0) ('blank lines inside the list: ' + $blank)
    # Accepted shapes, both verified against GNU coreutils 8.32 with -c --strict:
    # a '#' comment header, and the binary-mode asterisk before the name.
    $comment = @($lines | Where-Object { $_ -match '^#' })
    $entries = @($lines | Where-Object { $_ -match '^[0-9a-f]{64} [ *]\S+$' })
    $other = @($lines | Where-Object { ($_ -notmatch '^#') -and ($_ -notmatch '^[0-9a-f]{64} [ *]\S+$') })
    Chk ($other.Count -eq 0) ('lines that are neither a comment nor a checksum entry: ' + $other.Count)
    foreach ($o in $other) { if ($o.Trim()) { Say ('  MALFORMED: ' + $o) } }
    Chk ($entries.Count -eq 5) ('checksum entries: ' + $entries.Count + ' (expected 5: 4 exes + docs archive)')
    # -ge 1 was a vacuous floor: publish-release.ps1 lost TWO of its three header
    # lines to an -f precedence bug (see docs/CONVENTIONS.md 4.2) and this line
    # still passed, because one surviving comment satisfies ">= 1". The header is
    # not decoration -- it is the machine-readable form of the instruction printed
    # in README.md, so assert its exact size and that both commands it advertises
    # are actually named.
    Chk ($comment.Count -eq 3) ('comment header lines: ' + $comment.Count + ' (expected 3)')
    $hdr = $comment -join "`n"
    Chk ($hdr -match 'sha256sum -c SHA256SUMS\.txt') ('  header names the documented sha256sum invocation: ' + ($hdr -match 'sha256sum -c SHA256SUMS\.txt'))
    Chk ($hdr -match 'certutil -hashfile') ('  header names the documented certutil invocation: ' + ($hdr -match 'certutil -hashfile'))
    # The list must name exactly the assets the release carries, and its hashes
    # must be the hashes of the files actually built. Name matching alone is not
    # possible directly: dist/ holds tclwinkit-msvc.exe while the release asset
    # is tclwinkit-<version>-msvc-x64-console.exe, so the published name carries
    # a version infix the working name does not. Match on structure and on
    # content instead -- an earlier draft of this assertion compared published
    # names against working names and reported 0/4 on a correct file.
    $listed = @($entries | ForEach-Object { ($_ -split '\s+')[1] -replace '^\*', '' })
    $listedHashes = @($entries | ForEach-Object { ($_ -split '\s+')[0] })
    foreach ($n in $listed) { Say ('  listed: ' + $n) }
    $exeNames = @($listed | Where-Object { $_ -match '\.exe$' })
    $zipNames = @($listed | Where-Object { $_ -match '\.zip$' })
    Chk ($exeNames.Count -eq 4) ('listed exe names: ' + $exeNames.Count + '/4')
    Chk (($zipNames.Count -eq 1) -and ($zipNames[0] -match '^tclwinkit-docs-.+\.zip$')) ('listed docs archive: ' + $(if ($zipNames.Count) { $zipNames[0] } else { 'NONE' }))
    $cells = @()
    foreach ($tc in @('msvc', 'mingw')) {
        foreach ($fl in @('console', 'gui')) {
            $hit = @($exeNames | Where-Object { $_ -match ('-' + $tc + '-') -and $_ -match ('-' + $fl + '\.exe$') })
            if ($hit.Count -ne 1) { $cells += ($tc + '/' + $fl + '=' + $hit.Count) }
        }
    }
    Chk ($cells.Count -eq 0) ('toolchain x flavor cells covered exactly once (misses: ' + $(if ($cells.Count) { $cells -join ', ' } else { 'none' }) + ')')
    Chk (@($listedHashes | Sort-Object -Unique).Count -eq 5) ('listed hashes unique: ' + @($listedHashes | Sort-Object -Unique).Count + '/5')
    # Content identity with what is on disk, by hash set rather than by name.
    $have = @{}
    $missing = 0
    foreach ($n in @('tclwinkit-msvc.exe', 'winkitwish-msvc.exe', 'tclwinkit-mingw.exe', 'winkitwish-mingw.exe')) {
        $fp = Join-Path $Repo ('dist/' + $n)
        if (-not (Test-Path -LiteralPath $fp)) { $missing++; continue }
        $have[(Get-FileHash -LiteralPath $fp -Algorithm SHA256).Hash.ToLower()] = $n
    }
    $docsFp = @(Get-ChildItem -LiteralPath (Join-Path $Repo 'dist') -Filter 'tclwinkit-docs-*.zip' -File -ErrorAction SilentlyContinue)
    if ($docsFp.Count -eq 1) { $have[(Get-FileHash -LiteralPath $docsFp[0].FullName -Algorithm SHA256).Hash.ToLower()] = $docsFp[0].Name }
    else { $missing++ }
    if ($missing -eq 0 -and $have.Count -eq 5) {
        $stale = @($listedHashes | Where-Object { -not $have.ContainsKey($_) })
        Chk ($stale.Count -eq 0) ('listed hashes matching no built file: ' + $stale.Count)
        $absent = @($have.Keys | Where-Object { $listedHashes -notcontains $_ })
        Chk ($absent.Count -eq 0) ('built files absent from the list: ' + $absent.Count)
        foreach ($h in ($have.Keys | Sort-Object)) { Say ('  built : ' + $h + '  ' + $have[$h]) }
    } else {
        Skip ('hash cross-check against dist/ impossible (missing: ' + $missing + ', hashed: ' + $have.Count + '/5)')
    }
}

# --- 5/6. the shipped executables -------------------------------------------
$exes = @('tclwinkit-msvc.exe', 'winkitwish-msvc.exe', 'tclwinkit-mingw.exe', 'winkitwish-mingw.exe')
$present = @()
foreach ($f in $exes) {
    if (Test-Path -LiteralPath (Join-Path $Repo ('dist/' + $f))) { $present += $f }
}
Rule '5. PE TimeDateStamp of the shipped exes'
if ($present.Count -eq 0) {
    if ($RequireArtifacts) { Chk $false 'no exes under dist/ (-RequireArtifacts)' }
    else { Skip 'no built exes; sections 5 and 6 need dist/*.exe' }
} else {
    $dos = 315532800                       # 1980-01-01T00:00:00Z, the DOS epoch
    $nowTs = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $stamped = 0
    foreach ($f in $present) {
        $b = [System.IO.File]::ReadAllBytes((Join-Path $Repo ('dist/' + $f)))
        $off = [BitConverter]::ToInt32($b, 0x3C)
        $ts = [BitConverter]::ToUInt32($b, $off + 8)
        # -Brepro substitutes a hash of the image, so the value is arbitrary and
        # differs per exe; that is determinism, not a leak. The leak test is
        # proximity to the wall clock, NOT magnitude -- an earlier version of
        # this gate classified the MSVC hashes as "wall clock" because it
        # compared against a year threshold.
        $kind = if ($ts -eq $dos) { 'DOS epoch (SOURCE_DATE_EPOCH)' }
                elseif ([Math]::Abs([int64]$ts - [int64]$nowTs) -lt 86400) { 'WALL CLOCK - NOT PINNED' }
                else { 'image hash (-Brepro), deterministic' }
        $ok = ($kind -notmatch 'WALL CLOCK')
        if ($ok) { $stamped++ }
        Chk $ok ($f + '  ts=' + $ts + '  ' + $kind)
    }
    Chk ($stamped -eq $exes.Count) ('exes with a pinned TimeDateStamp: ' + $stamped + '/' + $exes.Count)
}

Rule '6. builder state inside the shipped exes'
if ($present.Count -eq 0) {
    if ($RequireArtifacts) { Chk $false 'no exes under dist/ (-RequireArtifacts)' }
    else { Skip 'no built exes' }
} else {
    # Latin-1 (28591) is used to decode the image losslessly: [System.Text.Encoding]::Latin1
    # is $null on PS 5.1, hence GetEncoding.
    $lat = [System.Text.Encoding]::GetEncoding(28591)
    # Read HEAD from git rather than hardcoding it, so the check survives the
    # next commit instead of passing by accident against a stale constant.
    $head = ((Invoke-Git @('rev-parse', 'HEAD')) -join '').Trim()
    Say ('HEAD              : ' + $head)
    Chk ($head -match '^[0-9a-f]{40}$') ('HEAD parses as a sha1: ' + $head)
    foreach ($f in $present) {
        $txt = $lat.GetString([System.IO.File]::ReadAllBytes((Join-Path $Repo ('dist/' + $f))))
        $here = @([regex]::Matches($txt, [regex]::Escape($head))).Count
        $anySha = @([regex]::Matches($txt, 'git-[0-9a-f]{7,40}')).Count
        Chk (($here -eq 0) -and ($anySha -eq 0)) ($f + ': HEAD occurrences=' + $here + ', git-<sha> occurrences=' + $anySha)
    }
}

Rule 'VERDICT'
Say ('failures: ' + $fail)
$txt = $log.ToString() -replace "`r`n", "`n"
foreach ($ln in ($txt -split "`n")) { Write-Output $ln }
if ($Report) {
    [System.IO.File]::WriteAllBytes($Report, [System.Text.UTF8Encoding]::new($false).GetBytes($txt))
}
if ($fail -eq 0) { 'CHECK-ENCODING OK' } else { 'CHECK-ENCODING FAILED' }
if ($fail -gt 200) { exit 200 }        # exit codes are one byte; do not wrap
exit $fail
