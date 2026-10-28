# Link audit for tracked markdown: resolve every relative [text](target) link,
# validate every #fragment against the headings of the file it points into, and
# report external URL shapes.
#
# Why this matters for a public repo specifically: the repository ships only
# 141 tracked files while vendor/, dist/ and build/ are gitignored, so a link
# that works on the reference machine can be dead for a reader. docs/SOURCES.md
# and docs/CONVENTIONS.md already carry the rule ("a tracked document never
# links into the scratch directory"); this measures compliance instead of
# asserting it.
#
# Anchor checking was added after the first run reported 0 findings while
# walking ZERO of the 26 in-file #fragment links in THIRD-PARTY-NOTICES.md: a
# gate that counts a class of input and then `continue`s past it is the
# vacuous-pass shape recorded in docs/NOTES.md section 10, so fragments are now
# resolved against the real heading slugs (GitHub algorithm: lowercase, drop
# punctuation, spaces to hyphens; headings inside fenced code blocks do not
# count; explicit <a name=...>/<a id=...> also count).
#
# Promotion to scripts/ (2026-10-28, block G): the tracked documents state that
# every relative link and every #fragment in this repository resolve. That claim
# is public, so its evidence has to be public too -- a checker living in the
# gitignored scratch directory cannot be re-run by a reader. CONTRIBUTING.md
# ("Layout") requires a promoted tool to move in the same change that links to
# it, and .github/workflows/ci.yml now runs this file. Its negative control
# lives in scripts/check-gates-selftest.ps1, which injects six link defects into
# throwaway repositories and requires this auditor to name each one.
#
# Read-only. Exit code = number of findings, capped at 200.
param([string]$Repo = '')
$ErrorActionPreference = 'Stop'
# One level, not two: this file lives in scripts/, so the repository root is the
# parent of $PSScriptRoot. The scratch copy computed the grandparent, which was
# right only because build/research/ is two levels deep.
if (-not $Repo) { $Repo = Split-Path -Parent $PSScriptRoot }
$enc = New-Object System.Text.UTF8Encoding($false)

$prev = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$md = @(& git -C $Repo ls-files '*.md' 2>&1 | Out-String -Stream) | Where-Object { $_.Trim() -ne '' }
$trackedRaw = @(& git -C $Repo ls-files 2>&1 | Out-String -Stream) | Where-Object { $_.Trim() -ne '' }
# gitignored-but-present paths, so "target exists on my machine" is not mistaken
# for "target is publishable"
$ignored = @(& git -C $Repo ls-files --others --ignored --exclude-standard 2>&1 | Out-String -Stream) | Where-Object { $_.Trim() -ne '' }
$ErrorActionPreference = $prev

$tracked = New-Object System.Collections.Generic.HashSet[string]
foreach ($t in $trackedRaw) { [void]$tracked.Add($t.Trim().Replace('\', '/')) }
$ign = New-Object System.Collections.Generic.HashSet[string]
foreach ($t in $ignored) { [void]$ign.Add($t.Trim().Replace('\', '/')) }
Write-Output ('tracked files: ' + $tracked.Count + '   tracked .md: ' + $md.Count + '   ignored paths present: ' + $ign.Count)
Write-Output ''
# A repository with no tracked markdown walks zero links and reports zero
# findings, which reads as a clean bill of health but is not one: the audit
# never looked at anything. Same guard as check-encoding section 1.
if ($md.Count -eq 0) {
    Write-Output 'FINDING tracked .md count 0 (must be > 0): nothing was audited'
    Write-Output 'LINK-AUDIT FAILED'
    exit 1
}

# --- slug sets ---------------------------------------------------------------
# NOTE the leading comma on every `return`: a HashSet is IEnumerable, so a bare
# `return $set` unrolls it. An empty set then arrives at the caller as $null
# (measured: "You cannot call a method on a null-valued expression"), and a
# non-empty one arrives as string[], which happens to answer .Contains by
# accident. Both shapes silently change what the anchor leg checks, so the type
# is preserved explicitly and re-checked at the call site.
$slugCache = @{}
function Get-SlugSet([string]$repo, [string]$rel, [hashtable]$cache) {
    if ($cache.ContainsKey($rel)) { return ,$cache[$rel] }
    $set = New-Object System.Collections.Generic.HashSet[string]
    $full = Join-Path $repo ($rel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    if (Test-Path -LiteralPath $full) {
        $e2 = New-Object System.Text.UTF8Encoding($false)
        $txt = $e2.GetString([System.IO.File]::ReadAllBytes($full)) -replace "`r`n", "`n"
        $inFence = $false
        foreach ($ln in ($txt -split "`n")) {
            if ($ln -match '^\s*(```|~~~)') { $inFence = -not $inFence; continue }
            if ($inFence) { continue }
            # explicit HTML anchors count too (vendored notices use them)
            foreach ($am in [regex]::Matches($ln, '(?i)<a\s+(?:name|id)\s*=\s*"([^"]+)"')) {
                [void]$set.Add($am.Groups[1].Value.ToLowerInvariant())
            }
            $hm = [regex]::Match($ln, '^(#{1,6})\s+(.*?)\s*#*\s*$')
            if (-not $hm.Success) { continue }
            $h = $hm.Groups[2].Value
            $h = $h.Replace([string][char]96, '')          # inline code spans
            $h = $h.Replace('[', '').Replace(']', '')      # link brackets
            $h = $h.ToLowerInvariant()
            $h = [regex]::Replace($h, '[^\p{L}\p{Nd} _-]', '')
            $h = [regex]::Replace($h, '\s+', '-')
            [void]$set.Add($h)
        }
    }
    $cache[$rel] = $set
    return ,$set
}

# Guard at the call site: the anchor leg is only as trustworthy as the type it
# looks up in. A null or a plain array here would mean the leg is not doing what
# its verdict line claims, so it is reported as a finding, not swallowed.
function Assert-SlugSet($s, [string]$rel, [ref]$cnt) {
    if ($s -is [System.Collections.Generic.HashSet[string]]) { return $true }
    $kind = $(if ($null -eq $s) { 'null' } else { $s.GetType().Name })
    Write-Output ('FINDING slug set for ' + $rel + ' is ' + $kind + ', not HashSet[string]: the anchor leg cannot be trusted')
    $cnt.Value++
    return $false
}

$findings = 0
$totalLinks = 0
$relLinks = 0
$extLinks = 0
$anchorLinks = 0
$anchorChecked = 0
$schemes = @{}

function Resolve-Rel([string]$dir, [string]$target) {
    $relNorm = $target.Replace('\', '/')
    if ($relNorm.StartsWith('/')) { $relNorm = $relNorm.TrimStart('/') } else { $relNorm = ($dir + '/' + $relNorm) }
    $segs = New-Object System.Collections.Generic.List[string]
    foreach ($seg in ($relNorm -split '/')) {
        if ($seg -eq '' -or $seg -eq '.') { continue }
        if ($seg -eq '..') { if ($segs.Count) { $segs.RemoveAt($segs.Count - 1) }; continue }
        $segs.Add($seg)
    }
    return ($segs -join '/')
}

foreach ($f in ($md | Sort-Object)) {
    $full = Join-Path $Repo ($f -replace '/', [System.IO.Path]::DirectorySeparatorChar)
    $text = $enc.GetString([System.IO.File]::ReadAllBytes($full)) -replace "`r`n", "`n"
    $lines = $text -split "`n"
    $dir = ($f -replace '/[^/]*$', '')
    if ($dir -eq $f) { $dir = '' }
    $selfSlugs = Get-SlugSet $Repo $f $slugCache
    $slugsOk = Assert-SlugSet $selfSlugs $f ([ref]$findings)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        foreach ($m in [regex]::Matches($lines[$i], '\]\(([^\s)]+)')) {
            $target = $m.Groups[1].Value
            $totalLinks++
            if ($target.StartsWith('#')) {
                $anchorLinks++
                $frag = $target.Substring(1)
                if ($frag -eq '') { continue }
                if (-not $slugsOk) { continue }   # the leg is broken; already a finding, and not counted as checked
                $anchorChecked++
                if (-not $selfSlugs.Contains($frag.ToLowerInvariant())) {
                    Write-Output ('FINDING ' + $f + ':' + ($i + 1) + '  DEAD ANCHOR: ' + $target + '  (no such heading in ' + $f + ')')
                    $findings++
                }
                continue
            }
            if ($target -match '^[a-zA-Z][a-zA-Z0-9+.-]*:') {
                $extLinks++
                $sch = ($target -split ':')[0].ToLowerInvariant()
                if (-not $schemes.ContainsKey($sch)) { $schemes[$sch] = 0 }
                $schemes[$sch]++
                if ($sch -notin @('http', 'https', 'mailto')) {
                    Write-Output ('FINDING ' + $f + ':' + ($i + 1) + '  unusual scheme: ' + $target)
                    $findings++
                }
                continue
            }
            $relLinks++
            $fragIdx = $target.IndexOf('#')
            $frag = ''
            if ($fragIdx -ge 0) { $frag = $target.Substring($fragIdx + 1) }
            $clean = ($target -split '[#?]')[0]
            if ($clean -eq '') { continue }
            $resolved = Resolve-Rel $dir $clean
            $onDisk = Test-Path -LiteralPath (Join-Path $Repo ($resolved -replace '/', [System.IO.Path]::DirectorySeparatorChar))
            $isTracked = $tracked.Contains($resolved)
            $isIgnored = $ign.Contains($resolved)
            # a directory link (e.g. LICENSES/) resolves to a prefix, not a file
            $isDirPrefix = $false
            if (-not $isTracked) {
                foreach ($t in $trackedRaw) { if ($t.Trim().Replace('\', '/').StartsWith($resolved + '/')) { $isDirPrefix = $true; break } }
            }
            if ($isIgnored) {
                Write-Output ('FINDING ' + $f + ':' + ($i + 1) + '  links into a GITIGNORED path: ' + $target + '  -> ' + $resolved)
                $findings++
            } elseif ($isTracked -or $isDirPrefix) {
                if ($frag -ne '' -and $resolved.EndsWith('.md', [System.StringComparison]::OrdinalIgnoreCase)) {
                    $set = Get-SlugSet $Repo $resolved $slugCache
                    if (-not (Assert-SlugSet $set $resolved ([ref]$findings))) { continue }
                    $anchorChecked++
                    if (-not $set.Contains($frag.ToLowerInvariant())) {
                        Write-Output ('FINDING ' + $f + ':' + ($i + 1) + '  DEAD FRAGMENT: ' + $target + '  (no such heading in ' + $resolved + ')')
                        $findings++
                    }
                }
            } elseif ($onDisk) {
                Write-Output ('FINDING ' + $f + ':' + ($i + 1) + '  exists on disk but NOT tracked: ' + $target + '  -> ' + $resolved)
                $findings++
            } else {
                Write-Output ('FINDING ' + $f + ':' + ($i + 1) + '  DEAD LINK: ' + $target + '  -> ' + $resolved)
                $findings++
            }
        }
    }
}
Write-Output ''
Write-Output ('links: total=' + $totalLinks + '  relative=' + $relLinks + '  external=' + $extLinks + '  anchor=' + $anchorLinks)
Write-Output ('fragments actually resolved against headings: ' + $anchorChecked + ' (must be > 0 whenever anchor=' + $anchorLinks + ' > 0)')
if ($anchorLinks -gt 0 -and $anchorChecked -eq 0) {
    Write-Output 'FINDING anchors present but none were checked: the anchor leg is vacuous'
    $findings++
}
if ($schemes.Count) { Write-Output ('external schemes: ' + (($schemes.Keys | Sort-Object | ForEach-Object { $_ + '=' + $schemes[$_] }) -join '  ')) }
Write-Output ('findings: ' + $findings)
if ($findings -eq 0) { Write-Output 'LINK-AUDIT OK' } else { Write-Output 'LINK-AUDIT FAILED' }
if ($findings -gt 200) { exit 200 }
exit $findings
