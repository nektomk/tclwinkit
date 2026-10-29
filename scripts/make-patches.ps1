# make-patches.ps1 --
#   Recompute patches/ from two trees that must both exist before this runs:
#
#     * -PristineRoot : a root whose build/<chain>/... trees come from
#                       unpack-vendor.ps1 and carry NO patches (step 1 output,
#                       unmodified);
#     * -Root         : this repository, whose build/<chain>/... trees are the
#                       reference -- the ones the kit was built and tested from.
#
#   The declared intent lives in patches/patches.json and is authored by hand:
#   which file is patched, which chain, what the change is for. This script
#   computes what must not be authored -- the patch bytes, the hash of the
#   pristine input, the hash of the expected result -- and refuses to write
#   unless a round trip through its own output reproduces the reference tree.
#
#   Line endings. patches.json declares canon.eol = "lf": both sides are
#   normalized CRLF -> LF before diffing, so the .patch files are pure LF and
#   satisfy this repository's tracked-file rule with no exception in
#   .gitattributes or check-encoding.ps1. The normalization is a declared
#   operation of apply-patches.ps1, not something hidden in the diff bytes.
#   Measured 2026-10-29 on the reference trees: of the 44 CR bytes present,
#   none sits inside a string literal (all are on comment or preprocessor
#   lines), and the one file whose upstream is CRLF (itk win/makefile.vc, 163
#   lines) costs a 338-line whole-file hunk if those bytes are preserved.
#
#   Git has to be switched off explicitly, every time. core.autocrlf is a
#   global setting on the build machine, so it applies even to a staging
#   directory outside every repository: with it on, `git diff --no-index`
#   normalizes both sides (the patch loses CR bytes it should carry) and
#   `git apply` puts them back (the result stops matching the reference).
#   Measured 2026-10-29: all 23 round trips failed that way before the flags
#   were added. Every git call below therefore passes
#   -c core.autocrlf=false -c core.eol=lf.
#
#   The audit is the point. Beyond regenerating, this script walks both trees
#   and reports every source-shaped file that differs without being declared,
#   every declared entry whose difference has evaporated, and every file one
#   side has and the other does not. That is how generic/api.c surfaced: it
#   carried 65 SEH-keyword renames and no entry in patches/ claimed it.
#
#   Usage:
#     scripts\make-patches.ps1 -PristineRoot R:\winkit\exp\prist           # report
#     scripts\make-patches.ps1 -PristineRoot ... -Write                   # emit
#     scripts\make-patches.ps1 -PristineRoot ... -Check                   # CI leg
#     scripts\make-patches.ps1 -PristineRoot ... -Only rl_json
#
#   -Check writes nothing and exits 1 when a computed value disagrees with what
#   patches.json already holds -- the assertion a CI leg can run with no
#   compiler and no vendor/ sources.
#
#   ASCII-only, CRLF (docs/CONVENTIONS.md rule for .ps1).

param(
    [string]$Root = '',
    [Parameter(Mandatory = $true)][string]$PristineRoot = '',
    [string]$Chain = 'msvc',
    [string[]]$Only = @(),
    [switch]$Write,
    [switch]$Check
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

if ($Only.Count -eq 1 -and $Only[0] -match ',') {
    $Only = @($Only[0] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
}
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
if (-not $PristineRoot) { throw '-PristineRoot is required: an unpacked, unpatched root' }
if ($Write -and $Check) { throw '-Write and -Check are mutually exclusive' }
$PristineRoot = (Resolve-Path -LiteralPath $PristineRoot).Path
$Root = (Resolve-Path -LiteralPath $Root).Path

$LayoutPath = Join-Path $PSScriptRoot 'vendor-layout.json'
$PatchDir = Join-Path $Root 'patches'
$ManifestPath = Join-Path $PatchDir 'patches.json'
# Global autocrlf is not a repository property, so it is not removed by
# stepping outside one; both flags are required on every call.
$GitOff = '-c core.autocrlf=false -c core.eol=lf'

$Lf = [char]10
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$Utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)

foreach ($p in @($LayoutPath, $ManifestPath)) {
    if (-not (Test-Path -LiteralPath $p)) { throw 'required file missing: ' + $p }
}
$Layout = Get-Content -LiteralPath $LayoutPath -Raw -Encoding UTF8 | ConvertFrom-Json
$Manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $Manifest.entries -or @($Manifest.entries).Count -eq 0) { throw 'patches.json declares no entries' }
if ($Manifest.canon.eol -ne 'lf') { throw 'patches.json canon.eol must be "lf", got: ' + $Manifest.canon.eol }

$ByComponent = @{}
foreach ($e in @($Layout.entries)) { $ByComponent[$e.component] = $e }

function Tree-Path([string]$base, $Lay, [string]$chain, [string]$rel) {
    $scope = $Layout.rules.scopePaths.($Lay.scope)
    $scope = $scope.Replace('{chain}', $chain)
    return (Join-Path $base ($scope + '\' + ($Lay.dir -replace '/', '\') + '\' + ($rel -replace '/', '\')))
}

function Read-LfText([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { throw 'file absent: ' + $path }
    $bytes = [System.IO.File]::ReadAllBytes($path)
    # Strict decode, and no BOM: a patch that silently mangles a vendor byte is
    # worse than one that refuses to build.
    try { $text = $Utf8Strict.GetString($bytes) } catch { throw 'not valid UTF-8: ' + $path }
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        throw 'BOM: ' + $path
    }
    return ($text -replace "`r`n", "`n")
}

function Get-ShaOfString([string]$text) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Utf8NoBom.GetBytes($text)))).Replace('-', '').ToLower() }
    finally { $sha.Dispose() }
}

function Invoke-Git([string]$cwd, [string]$line) {
    $saveEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    Push-Location $cwd
    cmd.exe /c ('git ' + $GitOff + ' ' + $line + ' >NUL 2>NUL') | Out-Null
    $rc = $LASTEXITCODE
    Pop-Location
    $ErrorActionPreference = $saveEap
    return $rc
}

# Diff two LF texts inside a throwaway directory, then rewrite the three header
# lines so the result reads "a/<rel>" / "b/<rel>" and applies with the
# conventional -p1. Hunk bodies are carried through byte for byte.
function New-PatchText([string]$stage, [string]$rel, [string]$preText, [string]$postText) {
    $win = $rel -replace '/', '\'
    $aFile = Join-Path $stage ('a\' + $win)
    $bFile = Join-Path $stage ('b\' + $win)
    foreach ($f in @($aFile, $bFile)) {
        $d = Split-Path -Parent $f
        if (-not (Test-Path -LiteralPath $d)) { $null = New-Item -ItemType Directory -Path $d -Force }
    }
    [System.IO.File]::WriteAllBytes($aFile, $Utf8NoBom.GetBytes($preText))
    [System.IO.File]::WriteAllBytes($bFile, $Utf8NoBom.GetBytes($postText))
    $out = Join-Path $stage ('raw.diff')
    if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Force }
    $rc = Invoke-Git $stage ('diff --no-index --output="' + $out + '" -- "a/' + $rel + '" "b/' + $rel + '"')
    if ($rc -eq 0) { return $null }                       # no difference left
    if ($rc -ne 1 -or -not (Test-Path -LiteralPath $out)) {
        throw ('git diff rc=' + $rc + ' (expected 1 = the files differ) for ' + $rel)
    }
    $lines = @([System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($out)) -split $Lf)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].StartsWith('diff --git ')) { $lines[$i] = 'diff --git a/' + $rel + ' b/' + $rel }
        elseif ($lines[$i].StartsWith('--- ')) { $lines[$i] = '--- a/' + $rel }
        elseif ($lines[$i].StartsWith('+++ ')) { $lines[$i] = '+++ b/' + $rel }
    }
    return ($lines -join $Lf)
}

function Escape-Json([string]$s) {
    $t = $s -replace '\\', '\\'
    $t = $t -replace '"', '\"'
    $t = $t -replace '`t', '\t'
    return $t
}

$Stage = Join-Path $env:TEMP ('winkit-mkpatches-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -ItemType Directory -Path $Stage -Force

$rows = @()
$problems = @()
$written = @()

try {
    foreach ($entry in @($Manifest.entries)) {
        if ($Only.Count -gt 0 -and ($Only -notcontains $entry.component)) { continue }
        $lay = $ByComponent[$entry.component]
        if (-not $lay) { $problems += ('{0}: unknown component' -f $entry.component); continue }

        $isRename = $entry.PSObject.Properties.Name -contains 'rename_file'
        $srcRel = if ($isRename) { $entry.rename_file.from } else { $entry.file }
        $dstRel = if ($isRename) { $entry.rename_file.to } else { $entry.file }
        $tag = '{0,-12} {1,-27}' -f $entry.component, $dstRel

        $priPath = Tree-Path $PristineRoot $lay $Chain $srcRel
        $refPath = Tree-Path $Root $lay $Chain $dstRel
        if (-not (Test-Path -LiteralPath $priPath)) { $problems += ($tag + 'pristine absent: ' + $priPath); continue }
        if (-not (Test-Path -LiteralPath $refPath)) { $problems += ($tag + 'reference absent: ' + $refPath); continue }

        $preText = Read-LfText $priPath
        $postText = Read-LfText $refPath
        $fromSha = Get-ShaOfString $preText
        $toSha = Get-ShaOfString $postText

        $matches_ = 0
        $opText = $preText
        if ($entry.PSObject.Properties.Name -contains 'rename_token') {
            $rt = $entry.rename_token
            $rx = '(?<![\w])' + [regex]::Escape($rt.from) + '(?![\w])'
            $matches_ = @([regex]::Matches($preText, $rx)).Count
            $opText = [regex]::Replace($preText, $rx, $rt.to)
            $remaining = @([regex]::Matches($opText, $rx)).Count
            if ($matches_ -ne $rt.matches) {
                $problems += ($tag + 'rename_token found ' + $matches_ + ' occurrences, manifest says ' + $rt.matches)
            }
            if ($remaining -ne $rt.remaining) {
                $problems += ($tag + 'rename_token left ' + $remaining + ', manifest says ' + $rt.remaining)
            }
        }

        $patchText = $null
        $declaresPatch = ($entry.PSObject.Properties.Name -contains 'patch' -and $entry.patch)
        if ($isRename) {
            if ($fromSha -ne $toSha) {
                $problems += ($tag + 'rename_file content differs between pristine and reference')
            }
        } elseif ($declaresPatch) {
            $patchText = New-PatchText $Stage $dstRel $opText $postText
            if ($null -eq $patchText) {
                # The declared patch has nothing left to say. Usually this means
                # an operation covers the file on its own, so the patch field is
                # what has to go, not the entry.
                $problems += ($tag + 'declared patch has no difference left: drop the patch field, the declared operations cover this file')
                continue
            }
            # round trip: the patch must reproduce the reference from the op result.
            # The working directory is the round root, not the file's own parent:
            # -p1 turns "a/generic/rl_json.c" into "generic/rl_json.c" relative to
            # wherever git is invoked, so applying from the parent directory looks
            # for generic/generic/rl_json.c and fails with rc=1.
            $roundRoot = Join-Path $Stage 'round'
            $rtFile = Join-Path $roundRoot ($dstRel -replace '/', '\')
            $d = Split-Path -Parent $rtFile
            if (-not (Test-Path -LiteralPath $d)) { $null = New-Item -ItemType Directory -Path $d -Force }
            [System.IO.File]::WriteAllBytes($rtFile, $Utf8NoBom.GetBytes($opText))
            $pf = Join-Path $Stage 'candidate.patch'
            [System.IO.File]::WriteAllBytes($pf, $Utf8NoBom.GetBytes($patchText))
            $rc = Invoke-Git $roundRoot ('apply -p1 --unsafe-paths "' + $pf + '"')
            if ($rc -ne 0) { $problems += ($tag + 'round trip: git apply rc=' + $rc); continue }
            $gotSha = Get-ShaOfString (Read-LfText $rtFile)
            if ($gotSha -ne $toSha) { $problems += ($tag + 'round trip hash mismatch'); continue }
        } elseif ($opText -cne $postText) {
            # Mirror image of the rule above: a file with no patch field must be
            # reproduced by its declared operations alone. This is what catches a
            # hand edit nobody declared, and it caught generic/api.c from the
            # other side -- 65 finally occurrences and no residue at all.
            $residue = New-PatchText $Stage $dstRel $opText $postText
            $rLines = if ($residue) { @($residue -split $Lf).Count } else { 0 }
            $problems += ($tag + 'no patch declared but ' + $rLines + ' lines of residue after the declared operations')
            continue
        }

        # ---- report the entry, and check it against what is stored ----
        $storedFrom = $entry.from_sha256
        $storedTo = $entry.sha256
        $drift = @()
        if ($storedFrom -and $storedFrom -ne $fromSha) { $drift += 'from_sha256' }
        if ($storedTo -and $storedTo -ne $toSha) { $drift += 'sha256' }
        if ($entry.PSObject.Properties.Name -contains 'rename_token' -and
            $entry.rename_token.matches -ne $matches_) { $drift += 'rename_token.matches' }
        $patchName = if ($patchText) { [System.IO.Path]::GetFileName($entry.patch) } else { '-' }
        $patchLines = if ($patchText) { @($patchText -split $Lf).Count } else { 0 }
        $patchHunks = if ($patchText) { @([regex]::Matches($patchText, '(?m)^@@')).Count } else { 0 }

        $rows += [pscustomobject]@{
            tag = $tag; entry = $entry; rel = $dstRel; lay = $lay
            fromSha = $fromSha; toSha = $toSha; matches = $matches_
            patchText = $patchText; patchName = $patchName
            patchLines = $patchLines; patchHunks = $patchHunks; drift = $drift
        }
        '{0} patch={1,-22} lines={2,-5} hunks={3,-3} matches={4,-4} drift={5}' -f `
            $tag, $patchName, $patchLines, $patchHunks, $matches_, $(if ($drift.Count) { $drift -join ',' } else { '-' })
    }

    # ---------------------------------------------------------------- audit ---
    ''
    'audit: source-shaped files that differ but are not declared'
    $allowExt = @($Manifest.rules.auditExtensions)
    $skipNames = @($Manifest.rules.auditSkipNames)
    $skipDirs = @($Manifest.rules.auditSkipDirs)
    $declared = @{}
    foreach ($e in @($Manifest.entries)) {
        if ($e.PSObject.Properties.Name -contains 'rename_file') {
            $declared[($e.component + '|' + $e.rename_file.from)] = $true
            $declared[($e.component + '|' + $e.rename_file.to)] = $true
        } else {
            $declared[($e.component + '|' + $e.file)] = $true
        }
    }
    function Test-SkippedDir([string]$rel) {
        # Entries may be a literal name or a wildcard: the MSVC output directory
        # is Release_<arch>_<compiler> and its name moves with the toolchain.
        $segs = $rel.Split('/')
        for ($i = 0; $i -lt $segs.Count - 1; $i++) {
            foreach ($s in $skipDirs) { if ($segs[$i] -like $s) { return $true } }
        }
        return $false
    }
    $hard = 0
    $info = 0
    $seenComponents = @{}
    foreach ($entry in @($Manifest.entries)) {
        if ($Only.Count -gt 0 -and ($Only -notcontains $entry.component)) { continue }
        if (-not $ByComponent[$entry.component]) { continue }
        if ($seenComponents.ContainsKey($entry.component)) { continue }
        $seenComponents[$entry.component] = $true
        $lay = $ByComponent[$entry.component]
        $priRoot = (Tree-Path $PristineRoot $lay $Chain '').TrimEnd('\')
        $refRoot = (Tree-Path $Root $lay $Chain '').TrimEnd('\')
        if (-not (Test-Path -LiteralPath $priRoot)) { '   pristine tree absent: ' + $priRoot; $hard++; continue }
        if (-not (Test-Path -LiteralPath $refRoot)) { '   reference tree absent: ' + $refRoot; $hard++; continue }

        $relSet = @{}
        foreach ($r in @(Get-ChildItem -LiteralPath $priRoot -Recurse -File -Force -EA SilentlyContinue)) {
            $k = $r.FullName.Substring($priRoot.Length + 1) -replace '\\', '/'
            if (Test-SkippedDir $k) { continue }
            $relSet[$k] = 'pri'
        }
        foreach ($r in @(Get-ChildItem -LiteralPath $refRoot -Recurse -File -Force -EA SilentlyContinue)) {
            $k = $r.FullName.Substring($refRoot.Length + 1) -replace '\\', '/'
            if (Test-SkippedDir $k) { continue }
            if ($relSet.ContainsKey($k)) { $relSet[$k] = 'both' } else { $relSet[$k] = 'ref' }
        }
        foreach ($k in ($relSet.Keys | Sort-Object)) {
            $ext = [System.IO.Path]::GetExtension($k).TrimStart('.').ToLower()
            $name = [System.IO.Path]::GetFileName($k)
            if ($skipNames -contains $name) { continue }
            if ($allowExt -notcontains $ext) { continue }
            $state = $relSet[$k]
            $isDecl = $declared.ContainsKey(($entry.component + '|' + $k))
            if ($state -eq 'both') {
                $a = Read-LfText (Join-Path $priRoot ($k -replace '/', '\'))
                $b = Read-LfText (Join-Path $refRoot ($k -replace '/', '\'))
                if ($a -ceq $b) {
                    if ($isDecl) {
                        '   HARD {0,-11} {1,-30} declared but IDENTICAL (obsolete entry)' -f $entry.component, $k
                        $hard++
                    }
                } elseif (-not $isDecl) {
                    '   HARD {0,-11} {1,-30} DIFFERS, undeclared' -f $entry.component, $k
                    $hard++
                }
            } elseif ($state -eq 'pri' -and -not $isDecl) {
                '   HARD {0,-11} {1,-30} only in pristine (a file we deleted without saying so)' -f $entry.component, $k
                $hard++
            } elseif ($state -eq 'ref' -and -not $isDecl) {
                # Legitimate: the build seeds headers and uuid files into the
                # tree (rl_jsonUuid.h, manifest.uuid). Reported, not failed.
                '   info {0,-11} {1,-30} only in reference (build-generated?)' -f $entry.component, $k
                $info++
            }
        }
    }
    if ($hard -eq 0 -and $info -eq 0) { '   (nothing to report)' }
    ''
    'audit verdict: hard=' + $hard + ' info=' + $info

    # --------------------------------------------------------- write / check ---
    ''
    if ($Write) {
        foreach ($r in $rows) {
            if ($r.patchText) {
                $dest = Join-Path $PatchDir (($r.entry.patch -replace '/', '\'))
                $d = Split-Path -Parent $dest
                if (-not (Test-Path -LiteralPath $d)) { $null = New-Item -ItemType Directory -Path $d -Force }
                [System.IO.File]::WriteAllBytes($dest, $Utf8NoBom.GetBytes($r.patchText))
                $written += $r.entry.patch
            }
        }
        $json = [System.Text.StringBuilder]::New()
        $null = $json.AppendLine('{')
        $null = $json.AppendLine('  "schema": ' + $Manifest.schema + ',')
        $null = $json.AppendLine('  "canon": { "eol": "lf", "encoding": "utf-8" },')
        $null = $json.AppendLine('  "rules": {')
        $null = $json.AppendLine('    "marker": "' + (Escape-Json $Manifest.rules.marker) + '",')
        $null = $json.AppendLine('    "apply": "git -c core.autocrlf=false -c core.eol=lf apply -p1 --unsafe-paths",')
        $null = $json.AppendLine('    "auditExtensions": [' + ((@($Manifest.rules.auditExtensions) | ForEach-Object { '"' + $_ + '"' }) -join ', ') + '],')
        $null = $json.AppendLine('    "auditSkipNames": [' + ((@($Manifest.rules.auditSkipNames) | ForEach-Object { '"' + (Escape-Json $_) + '"' }) -join ', ') + '],')
        $null = $json.AppendLine('    "auditSkipDirs": [' + ((@($Manifest.rules.auditSkipDirs) | ForEach-Object { '"' + (Escape-Json $_) + '"' }) -join ', ') + '],')
        $null = $json.AppendLine('    "notes": [')
        $notes = @($Manifest.rules.notes)
        for ($i = 0; $i -lt $notes.Count; $i++) {
            $null = $json.AppendLine('      "' + (Escape-Json $notes[$i]) + '"' + $(if ($i -lt $notes.Count - 1) { ',' } else { '' }))
        }
        $null = $json.AppendLine('    ]')
        $null = $json.AppendLine('  },')
        $null = $json.AppendLine('  "entries": [')
        $ens = @($rows | ForEach-Object { $_.entry })
        for ($i = 0; $i -lt $ens.Count; $i++) {
            $r = $rows[$i]
            $e = $ens[$i]
            $null = $json.AppendLine('    {')
            $null = $json.AppendLine('      "component": "' + (Escape-Json $e.component) + '",')
            if ($e.PSObject.Properties.Name -contains 'rename_file') {
                $null = $json.AppendLine('      "rename_file": { "from": "' + (Escape-Json $e.rename_file.from) + '", "to": "' + (Escape-Json $e.rename_file.to) + '" },')
            } else {
                $null = $json.AppendLine('      "file": "' + (Escape-Json $e.file) + '",')
            }
            if ($e.PSObject.Properties.Name -contains 'chains') {
                $null = $json.AppendLine('      "chains": [' + ((@($e.chains) | ForEach-Object { '"' + $_ + '"' }) -join ', ') + '],')
            }
            if ($e.PSObject.Properties.Name -contains 'rename_token') {
                $null = $json.AppendLine('      "rename_token": { "from": "' + $e.rename_token.from + '", "to": "' + $e.rename_token.to + '", "matches": ' + $r.matches + ', "remaining": ' + $e.rename_token.remaining + ' },')
            }
            if ($r.patchText) {
                $null = $json.AppendLine('      "patch": "' + (Escape-Json $e.patch) + '",')
            }
            if ($e.PSObject.Properties.Name -contains 'note') {
                $null = $json.AppendLine('      "note": "' + (Escape-Json $e.note) + '",')
            }
            $null = $json.AppendLine('      "from_sha256": "' + $r.fromSha + '",')
            $null = $json.AppendLine('      "sha256": "' + $r.toSha + '"')
            $null = $json.AppendLine('    }' + $(if ($i -lt $ens.Count - 1) { ',' } else { '' }))
        }
        $null = $json.AppendLine('  ]')
        $null = $json.AppendLine('}')
        [System.IO.File]::WriteAllBytes($ManifestPath, $Utf8NoBom.GetBytes(($json.ToString() -replace "`r`n", "`n")))
        # re-read it: a manifest that does not parse is not a manifest
        $re = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (@($re.entries).Count -ne $rows.Count) { throw 'rewritten manifest has ' + @($re.entries).Count + ' entries, expected ' + $rows.Count }
        'wrote ' + $written.Count + ' patch file(s) and patches.json (' + $rows.Count + ' entries)'
    } elseif ($Check) {
        $bad = @($rows | Where-Object { $_.drift.Count -gt 0 })
        if ($bad.Count -gt 0) {
            foreach ($b in $bad) { '   STALE {0} drift: {1}' -f $b.tag, ($b.drift -join ',') }
            'CHECK FAILED: ' + $bad.Count + ' entr(ies) disagree with the computed values'
        } else {
            'CHECK OK: ' + $rows.Count + ' entr(ies) match the computed values'
        }
    } else {
        'report only (pass -Write to emit, -Check to assert)'
    }

    ''
    if ($problems.Count -gt 0) {
        foreach ($p in $problems) { 'PROBLEM ' + $p }
        exit 1
    }
    if ($Check -and @($rows | Where-Object { $_.drift.Count -gt 0 }).Count -gt 0) { exit 1 }
    if ($Check -and $findings -gt 0) { exit 1 }
    exit 0
}
finally {
    if (Test-Path -LiteralPath $Stage) { Remove-Item -LiteralPath $Stage -Recurse -Force }
}
