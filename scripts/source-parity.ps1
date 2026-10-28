# Parity between docs/SOURCES.md (the human-facing map) and scripts/fetch-vendor.ps1
# (the machine-facing manifest).
#
# Why this is the check worth having for a public repo: SOURCES.md is the only
# place a stranger learns where the 15 vendor archives come from, and
# fetch-vendor.ps1 is the only place those origins are executed. They are two
# copies of one fact, written by hand in two notations, so they drift. A URL in
# the document but not in the script is a promise nobody fetches; a URL in the
# script but not in the document is an unpublished provenance hole, and that is
# the direction that matters for licensing because a reader cannot see it.
#
# Direction rules, so the check does not fire on legitimate prose:
#   script -> document  every u= / d= / s= / f= / c= field, plus pu= / pd= / pss=
#                       for the four movable refs;
#   document -> script  URLs inside a component table ROW only, because the
#                       document also quotes URLs as counter-examples (the
#                       dyncall 200-with-empty-HTML trap) and cites fossil
#                       canonicals inside quotations.
#
# Row-level strength: the size is required to appear on the SAME document line as
# the digest it belongs to. Matching the number anywhere in the document would
# pass on an incidental occurrence, which is a weaker claim than the manifest
# makes.
#
# Vacuous-pass guards: every row must yield all of its fields, the totals must be
# nonzero, and the totals are printed, so a future change to the manifest
# notation shows up as a count shift instead of a silent skip.
#
# Two bugs this file already paid for, both of the class recorded in
# docs/NOTES.md section 10:
#   * $doc and $Doc are ONE variable in PowerShell (names are case-insensitive),
#     so reading the document into $doc destroyed the path parameter and the tool
#     printed 447 lines of SOURCES.md inside its own verdict;
#   * field extraction anchored with (?m)^\s*key\s*= matched nothing but the first
#     assignment of each manifest row, because a row carries several per line
#     (@{ c = 'Tcl'; f = '...'; k = 'tgz'; t = '...'; }). Twelve of the fifteen
#     fields then came back empty and their parity checks were skipped quietly:
#     the tool reported findings about the one field that did extract and looked
#     like a working gate.
#
# Read-only. Exit = findings, capped at 200.
#
# Promotion to scripts/ (2026-10-28, block G): docs/SOURCES.md is a public
# provenance claim, and the claim "the map and the manifest agree" cannot be
# evidenced by a tool living in the gitignored scratch directory. CONTRIBUTING.md
# ("Layout") requires the move and the link to land in one change, so
# .github/workflows/ci.yml runs this file and scripts/check-gates-selftest.ps1
# carries its negative control (twelve injected defects, three of which guard the
# "notation not understood" and "leg never ran" vacuous shapes).
param([string]$RepoRel = '', [string]$DocRel = 'docs/SOURCES.md', [string]$ScriptRel = 'scripts/fetch-vendor.ps1')
$ErrorActionPreference = 'Stop'
# One level, not two: this file lives in scripts/, so the repository root is the
# parent of $PSScriptRoot. The scratch copy computed the grandparent, which was
# right only because build/research/ is two levels deep.
$RepoRoot = Split-Path -Parent $PSScriptRoot
if ($RepoRel) { $RepoRoot = $RepoRel }
$enc = New-Object System.Text.UTF8Encoding($false)
$docFull = Join-Path $RepoRoot ($DocRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
$scrFull = Join-Path $RepoRoot ($ScriptRel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
foreach ($pair in @(@($docFull, $DocRel), @($scrFull, $ScriptRel))) {
    if (-not (Test-Path -LiteralPath $pair[0])) { Write-Output ('FATAL: missing ' + $pair[1]); exit 2 }
}
$docText = $enc.GetString([System.IO.File]::ReadAllBytes($docFull)) -replace "`r`n", "`n"
$scrText = $enc.GetString([System.IO.File]::ReadAllBytes($scrFull)) -replace "`r`n", "`n"
$docLines = @($docText -split "`n")

# thousands separators used by the size column, built from code points so this
# file stays ASCII-only like every other .ps1
$sepClass = '[' + [string][char]0x20 + [string][char]0xA0 + [string][char]0x2009 + [string][char]0x202F + ']'
# Tokenise sizes on the RAW line and only then collapse separators inside the
# token. Stripping separators from the whole line first (what this file shipped
# with) glues the tail of a hex digest onto the following size:
#   "...b23ae30   999 449 B"  ->  one run ending in 30999449
# so exactly the three pinned digests that end in a digit failed a check their
# document passes, while mpexpr's (ends in "c") did not. The lookbehind and
# lookahead keep a digit run inside a digest from being read as a size at all.
$tokenRe = '(?<![0-9A-Za-z])\d(?:' + $sepClass + '?\d)*(?![0-9A-Za-z])'
function Get-SizeTokens([string]$line) {
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($m in [regex]::Matches($line, $tokenRe)) { $out.Add(($m.Value -replace $sepClass, '')) }
    return $out
}
function Test-SizeOnLine([string]$line, [string]$want) {
    foreach ($t in (Get-SizeTokens $line)) { if ($t -eq $want) { return $true } }
    return $false
}

# --- harvest the manifest ---------------------------------------------------
$rows = @([regex]::Matches($scrText, '@\{[^}]*\}'))
Write-Output ('manifest rows: ' + $rows.Count + '   document lines: ' + $docLines.Count)
if ($rows.Count -eq 0) {
    Write-Output 'FINDING manifest yielded 0 rows (must be > 0): nothing to compare'
    Write-Output 'SOURCE-PARITY FAILED'
    exit 1
}
function Get-Field([string]$body, [string]$key) {
    # deliberately no line anchor: a manifest row carries several assignments
    $m = [regex]::Match($body, '\b' + [regex]::Escape($key) + "\s*=\s*'([^']*)'")
    if ($m.Success) { return $m.Groups[1].Value }
    return ''
}
function Get-NumField([string]$body, [string]$key) {
    $m = [regex]::Match($body, '\b' + [regex]::Escape($key) + '\s*=\s*([0-9]+)')
    if ($m.Success) { return $m.Groups[1].Value }
    return ''
}

$findings = 0
$need = @('c', 'f', 'k', 'u', 'd', 's')
$pinKeys = @('pu', 'pd', 'pss')
$statRows = 0
$statUrls = 0
$statDigests = 0
$statSizes = 0
$statFiles = 0
$statPins = 0
$statSameLine = 0
$compNames = @()
$scriptUrls = New-Object System.Collections.Generic.HashSet[string]

foreach ($rm in $rows) {
    $body = $rm.Value
    $isMovable = [regex]::IsMatch($body, '\bmovable\s*=')
    $keys = @($need)
    if ($isMovable) { $keys = @($need + $pinKeys) }
    $rowMiss = @()
    foreach ($k in $keys) { if ((Get-Field $body $k) -eq '' -and (Get-NumField $body $k) -eq '') { $rowMiss += $k } }
    if ($rowMiss.Count) {
        $flat = ($body -replace '\s+', ' ')
        Write-Output ('FINDING manifest row did not yield: ' + ($rowMiss -join ',') + '   row: ' + $flat.Substring(0, [Math]::Min(70, $flat.Length)))
        $findings++
        continue
    }
    $statRows++
    $c = Get-Field $body 'c'
    $f = Get-Field $body 'f'
    $u = Get-Field $body 'u'
    $d = Get-Field $body 'd'
    $s = Get-NumField $body 's'
    $compNames += $c
    [void]$scriptUrls.Add($u)
    if (-not $docText.Contains($u)) {
        Write-Output ('FINDING URL fetched but not published in ' + $DocRel + ': ' + $u + '   (' + $c + ')')
        $findings++
    }
    $statUrls++
    if (-not $docText.Contains($f)) {
        Write-Output ('FINDING vendored filename not published in ' + $DocRel + ': ' + $f + '   (' + $c + ')')
        $findings++
    }
    $statFiles++
    $digLines = @($docLines | Where-Object { $_.Contains($d) })
    if ($digLines.Count -eq 0) {
        Write-Output ('FINDING SHA-256 enforced but not published in ' + $DocRel + ': ' + $d + '   (' + $c + ')')
        $findings++
    } else {
        $statDigests++
        $hit = $false
        foreach ($dl in $digLines) { if (Test-SizeOnLine $dl $s) { $hit = $true; break } }
        if ($hit) { $statSameLine++ }
        if (-not $hit) {
            Write-Output ('FINDING size ' + $s + ' is not on any ' + $DocRel + ' line carrying digest ' + $d.Substring(0, 12) + '...   (' + $c + ')')
            $findings++
        }
        $statSizes++
    }
    if ($isMovable) {
        $pu = Get-Field $body 'pu'
        $pd = Get-Field $body 'pd'
        $pss = Get-NumField $body 'pss'
        if (-not $docText.Contains($pu)) {
            Write-Output ('FINDING pinned URL not published in ' + $DocRel + ': ' + $pu + '   (' + $c + ')')
            $findings++
        }
        if (-not $docText.Contains($pd)) {
            Write-Output ('FINDING pinned SHA-256 not published in ' + $DocRel + ': ' + $pd + '   (' + $c + ')')
            $findings++
        }
        $pinHit = $false
        foreach ($pl in @($docLines | Where-Object { $_.Contains($pd) })) {
            if (Test-SizeOnLine $pl $pss) { $pinHit = $true; break }
        }
        if (-not $pinHit) {
            Write-Output ('FINDING pinned size ' + $pss + ' is not on a ' + $DocRel + ' line carrying the pinned digest   (' + $c + ')')
            $findings++
        }
        $statPins++
    }
}
Write-Output ('rows fully harvested: ' + $statRows + '   URLs: ' + $statUrls + '   digests: ' + $statDigests + '   sizes: ' + $statSizes + '   filenames: ' + $statFiles + '   pin triples: ' + $statPins)
Write-Output ('rows whose size shares a document line with its digest: ' + $statSameLine + '/' + $statDigests)
if ($statRows -eq 0) {
    Write-Output 'FINDING 0 rows harvested (must be > 0): the manifest notation is not understood'
    Write-Output 'SOURCE-PARITY FAILED'
    exit 1
}
if ($statUrls -eq 0 -or $statDigests -eq 0) {
    Write-Output 'FINDING 0 URLs or 0 digests checked (must be > 0): the parity is vacuous'
    Write-Output 'SOURCE-PARITY FAILED'
    exit 1
}

# --- document -> script, table rows only ------------------------------------
$tableRows = @([regex]::Matches($docText, '(?m)^\|[^|]+\|[^|]+\|[^|]*https?://[^|]+\|'))
Write-Output ('document URL-bearing table rows: ' + $tableRows.Count)
if ($tableRows.Count -eq 0) {
    Write-Output ('FINDING ' + $DocRel + ' yielded 0 URL-bearing table rows (must be > 0): no reverse comparison possible')
    Write-Output 'SOURCE-PARITY FAILED'
    exit 1
}
$reverse = 0
foreach ($tr in $tableRows) {
    foreach ($um in [regex]::Matches($tr.Value, 'https?://[^\s`|)\]]+')) {
        $u = $um.Value.TrimEnd('.', ',', ';')
        $reverse++
        if (-not $scriptUrls.Contains($u)) {
            Write-Output ('FINDING URL in a ' + $DocRel + ' table row is never fetched by ' + $ScriptRel + ': ' + $u)
            $findings++
        }
    }
}
Write-Output ('reverse direction URLs checked: ' + $reverse)

# --- component names --------------------------------------------------------
# One legitimate divergence exists and is declared rather than tolerated: the
# manifest names the UPSTREAM REPOSITORY (tktreectrl, the GitHub depot) while the
# map names the PACKAGE as it declares itself (AC_INIT([treectrl],[2.5.2]) --
# docs/SOURCES.md has a whole subsection on why the directory says 2.5.1 and the
# tree says 2.5.2). The alias is applied only if the aliased name really is a
# table row, so renaming that row still fires.
$aliasMap = @{ tktreectrl = 'treectrl' }
$missingComp = @()
$aliasedComp = @()
foreach ($c in $compNames) {
    $probe = $c
    if ($aliasMap.ContainsKey($c)) { $probe = $aliasMap[$c] }
    if (-not [regex]::IsMatch($docText, '(?m)^\|\s*' + [regex]::Escape($probe) + '\s*\|')) { $missingComp += $c }
    elseif ($probe -ne $c) { $aliasedComp += ($c + ' -> ' + $probe) }
}
if ($aliasedComp.Count) {
    Write-Output ('declared name aliases (manifest -> map, both present): ' + ($aliasedComp -join ', '))
}
Write-Output ('manifest component names: ' + $compNames.Count + '   without a table row in ' + $DocRel + ': ' + $missingComp.Count)
foreach ($c in $missingComp) {
    Write-Output ('FINDING component fetched but with no table row in ' + $DocRel + ': ' + $c)
    $findings++
}

Write-Output ''
Write-Output ('findings: ' + $findings)
if ($findings -eq 0) { Write-Output 'SOURCE-PARITY OK' } else { Write-Output 'SOURCE-PARITY FAILED' }
if ($findings -gt 200) { exit 200 }
exit $findings
