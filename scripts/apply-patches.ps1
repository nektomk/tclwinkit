# apply-patches.ps1 --
#   Apply patches/patches.json to the unpacked vendor trees, and verify that a
#   tree already carries exactly what it declares.
#
#   This is step 2 of the pipeline: fetch-vendor.ps1 puts the archives in place,
#   unpack-vendor.ps1 turns them into pristine trees, this script turns those
#   trees into the ones the kit is built from, and build-*.bat/sh do the build.
#   Nothing here is manual: the point of the manifest is that a tree can be
#   recreated from the archives without consulting any checked-in copy.
#
#   Preconditions, in order:
#     * the tree must be marked as unpacked (unpack-vendor.ps1 -VerifyOnly). An
#       unmarked tree may be stale, hand-edited or half-deleted, and patching it
#       produces something that looks derived but is not reproducible.
#     * every file about to be touched must be either pristine (from_sha256) or
#       already final (sha256). Anything else stops the run: a partially patched
#       file cannot be told apart from a hand-edited one, so the recovery is to
#       re-unpack, not to guess.
#
#   Each entry is applied as a fixed sequence of declared operations:
#     1. normalize the file to LF. canon.eol in the manifest says the diffs are
#        LF, and the pristine trees arrive with whatever line endings upstream
#        shipped (itk win/makefile.vc is 100% CRLF), so this is a step of its
#        own rather than something smuggled into the hunk bytes;
#     2. rename_token, if declared -- a whole-word identifier rename, asserted
#        against its declared occurrence count before and after;
#     3. git apply -p1, if the entry declares a patch;
#     4. rename_file, if the entry declares one (a rename has no diff bytes);
#     5. hash the result and compare with sha256.
#
#   Every result goes to a staging directory first and no tree file is written
#   until the whole run has produced zero failures, at which point the staged
#   bytes are committed and the markers written. A refusal is therefore
#   all-or-nothing: either every declared operation landed, or the trees are
#   exactly as they were found. That is worth more than it looks. A run that
#   commits the files it liked and then refuses leaves a hybrid tree, and a
#   hybrid tree is the one thing this script must never produce, because the
#   next run cannot tell it apart from a hand-edited one -- it reports
#   already-patched for four files and DIRTY for the fifth, which reads like a
#   problem with the fifth.
#
#   The boundary of that guarantee is the commit loop itself: it is a sequence of
#   file writes, so an I/O error there (disk full, tree deleted mid-run) can still
#   leave some changes in and others out. Nothing detects that except the marker,
#   which is written only after a clean commit, so such a tree fails
#   -VerifyOnly and the recovery is the same one the script always advises:
#   re-unpack with -Force and re-run. Refusals are designed for; a crash is
#   merely made recoverable.
#
#   Why git apply and not a hand-rolled hunk walker: the hunk format has edge
#   cases (context at EOF, "\ No newline at end of file", mode bits) that are
#   each a chance to silently produce a slightly wrong file, and git is the same
#   tool that produced the diffs. The cost is that git must be switched off
#   explicitly on every call -- core.autocrlf is a global setting on the build
#   machine, and with it on, apply re-inserts CR bytes the patch never contained.
#
#   Usage:
#     scripts\apply-patches.ps1                      # apply to both chains
#     scripts\apply-patches.ps1 -Chain msvc          # one chain
#     scripts\apply-patches.ps1 -Only rl_json,itk    # subset
#     scripts\apply-patches.ps1 -DryRun              # plan, touch nothing
#     scripts\apply-patches.ps1 -VerifyOnly          # assert the current trees
#     scripts\apply-patches.ps1 -Force               # re-apply over a patched tree
#
#   Exit codes: 0 ok, 1 precondition/verification/apply failure.
#
#   ASCII-only, CRLF (docs/CONVENTIONS.md rule for .ps1).

param(
    [string]$Root = '',
    [ValidateSet('msvc', 'mingw', 'both')] [string]$Chain = 'both',
    [string[]]$Only = @(),
    [switch]$VerifyOnly,
    [switch]$DryRun,
    [switch]$Force
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

if ($Only.Count -eq 1 -and $Only[0] -match ',') {
    $Only = @($Only[0] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
}
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
$Root = (Resolve-Path -LiteralPath $Root).Path
if ($VerifyOnly -and ($DryRun -or $Force)) { throw '-VerifyOnly cannot be combined with -DryRun or -Force' }

$LayoutPath = Join-Path $PSScriptRoot 'vendor-layout.json'
# Two roots, deliberately: -Root says where the vendor TREES live, while the
# patch set is part of this repository and always comes from where the script is
# installed. That is what lets a throwaway root be patched with the committed
# patches, and what keeps the CI leg from having to copy patches/ around.
$RepoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
$ManifestPath = Join-Path $RepoRoot 'patches\patches.json'
$PatchRoot = Join-Path $RepoRoot 'patches'
$UnpackScript = Join-Path $PSScriptRoot 'unpack-vendor.ps1'
foreach ($p in @($LayoutPath, $ManifestPath, $UnpackScript)) {
    if (-not (Test-Path -LiteralPath $p)) { throw 'required file missing: ' + $p }
}

$Layout = Get-Content -LiteralPath $LayoutPath -Raw -Encoding UTF8 | ConvertFrom-Json
$Manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($Manifest.schema -ne 1) { throw 'unsupported patches.json schema: ' + $Manifest.schema }
if ($Manifest.canon.eol -ne 'lf') { throw 'canon.eol must be "lf", got: ' + $Manifest.canon.eol }
if ($Manifest.canon.encoding -ne 'utf-8') { throw 'canon.encoding must be "utf-8", got: ' + $Manifest.canon.encoding }

# The chain list comes from step 1's map, not from a literal here: if a third
# chain ever appears, the patch set follows.
$Chains = if ($Chain -eq 'both') { @($Layout.rules.chains) } else { @($Chain) }
if ($Chains.Count -eq 0) { throw 'vendor-layout.json declares no chains' }
foreach ($c in $Chains) {
    if (@($Layout.rules.chains) -notcontains $c) { throw 'unknown chain: ' + $c }
}

$MarkerName = $Manifest.rules.marker
$ByComponent = @{}
foreach ($e in @($Layout.entries)) { $ByComponent[$e.component] = $e }

$Lf = [char]10
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$Utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)
# Global autocrlf is not a property of the repository, so leaving the repository
# is not enough; both flags are required on every call.
$GitOff = @('-c', 'core.autocrlf=false', '-c', 'core.eol=lf')

function Get-TreeRoot([string]$root, $Lay, [string]$chain) {
    $scope = $Layout.rules.scopePaths.($Lay.scope)
    $scope = $scope.Replace('{chain}', $chain)
    return (Join-Path $root ($scope + '\' + ($Lay.dir -replace '/', '\')))
}

function Get-BytesSha([byte[]]$bytes) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLower() }
    finally { $sha.Dispose() }
}

function Get-LfBytes([byte[]]$bytes) {
    # Strip every CR that precedes an LF. Byte-level on purpose: doing it
    # without decoding keeps this valid for any file the manifest names, and the
    # manifest is the only place that decides what is text.
    $out = New-Object 'byte[]' $bytes.Length
    $n = 0
    $dropped = 0
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        if ($bytes[$i] -eq 13 -and $i + 1 -lt $bytes.Length -and $bytes[$i + 1] -eq 10) { $dropped++; continue }
        $out[$n] = $bytes[$i]; $n++
    }
    if ($n -eq $bytes.Length) { return @{ bytes = $bytes; dropped = $dropped } }
    $trim = New-Object 'byte[]' $n
    [Array]::Copy($out, 0, $trim, 0, $n)
    return @{ bytes = $trim; dropped = $dropped }
}

function Get-CanonicalSha([byte[]]$bytes) {
    # Every hash in patches.json is the hash of LF-normalized content, so the
    # same file compares equal whether the tree holds it with CRLF (as the
    # reference checkout does: 44 CR bytes) or with LF (as a freshly patched
    # tree does). Without this, -VerifyOnly could only ever pass in one of the
    # two states.
    return Get-BytesSha ((Get-LfBytes $bytes).bytes)
}

function Get-FileSha([string]$path) {
    return Get-CanonicalSha ([System.IO.File]::ReadAllBytes($path))
}

function Decode-LfText([byte[]]$bytes, [string]$path) {
    # Strict decode, and no BOM: a patched file that silently mangles a vendor
    # byte is worse than one that refuses to apply. Three of the patched files
    # carry non-ASCII (rl_json.c 36 B, rl_jsonInt.h 20 B, tkWinTree.c 3 B), so
    # this is not a theoretical check.
    try { $text = $Utf8Strict.GetString($bytes) } catch { throw 'not valid UTF-8: ' + $path }
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        throw 'BOM: ' + $path
    }
    return $text
}

function Invoke-GitApply([string]$cwd, [string]$patchFile) {
    $saveEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    Push-Location $cwd
    $out = & git @GitOff apply -p1 --unsafe-paths --verbose $patchFile 2>&1 | Out-String -Stream
    $rc = $LASTEXITCODE
    Pop-Location
    $ErrorActionPreference = $saveEap
    return @{ rc = $rc; lines = @($out) }
}

# ------------------------------------------------------------------ planning ---
$entries = @($Manifest.entries)
if ($Only.Count -gt 0) {
    # Validate the names before filtering anything: filtering first turns a typo
    # into "-Only matched no entry", which names nothing and sends the reader off
    # to guess which of the five components they misspelled.
    foreach ($o in $Only) {
        if (@($Manifest.entries | Where-Object { $_.component -eq $o }).Count -eq 0) {
            throw '-Only names an unknown component: ' + $o
        }
    }
    $entries = @($entries | Where-Object { $Only -contains $_.component })
    if ($entries.Count -eq 0) { throw '-Only matched no entry in patches.json' }
}
$wantedComponents = @($entries | ForEach-Object { $_.component } | Sort-Object -Unique)

# ---------------------------------------------------- precondition: unpacked ---
if (-not $VerifyOnly) {
    'precondition: unpack-vendor.ps1 -VerifyOnly -Root ' + $Root
    $uvOut = @(& $UnpackScript -VerifyOnly -Root $Root -Only ($wantedComponents -join ',') 2>&1 | Out-String -Stream)
    $uvRc = $LASTEXITCODE
    foreach ($l in $uvOut) { if ($l -match '^(verdict|UNPACK-VENDOR|  \[)' ) { '            ' + $l } }
    if ($uvRc -ne 0) {
        'PRECONDITION FAILED: the trees are not verified-unpacked, so patching them'
        '                     would produce something irreproducible.'
        '                     Run: unpack-vendor.ps1 -Root ' + $Root + ' -Force'
        exit 1
    }
    ''
}

$results = @()
$failures = @()

# One staging directory for the whole run, outside every repository and outside
# every -Root. Nothing is written to a tree until the run has produced zero
# failures, so a refusal costs the staged bytes and not the trees.
$StageRoot = Join-Path $env:TEMP ('winkit-apply-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$pending = @()
function Stage-Bytes([string]$chainName, [string]$component, [string]$rel, [byte[]]$bytes) {
    $p = Join-Path $StageRoot ($chainName + '\' + $component + '\' + ($rel -replace '/', '\'))
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $p) -Force
    [System.IO.File]::WriteAllBytes($p, $bytes)
    return $p
}
# Scope-wide cleanup, because the run loop can terminate by throwing rather than
# by exiting: Decode-LfText throws on a non-UTF-8 or BOM'd tree file, and a throw
# would walk past the removal at the end of the commit block and leave the
# staging tree in %TEMP% forever. Verified on PS 5.1: a script-scope trap runs on
# an escaping throw, does not run on exit, and leaves the exit code at 1.
#
# A trap covers its whole scope, INCLUDING the statements above and below it, so
# it also fires for the early throws in this script (a bad -Chain, an unknown
# -Only, a missing patches.json). It therefore has to be null-safe: an earlier
# version called Test-Path on an unset $StageRoot, the trap threw its own
# "cannot bind argument to parameter 'LiteralPath' because it is null", and that
# replaced the real diagnostic -- "-Only names an unknown component: nosuchpkg"
# disappeared from the output entirely. Hence the empty default above and the
# guard here, and hence why nothing else may run in a trap.
trap {
    if ($StageRoot -and (Test-Path -LiteralPath $StageRoot)) {
        Remove-Item -LiteralPath $StageRoot -Recurse -Force
    }
    break
}

foreach ($chainName in $Chains) {
    foreach ($entry in $entries) {
        $lay = $ByComponent[$entry.component]
        if (-not $lay) { $failures += ('unknown component: ' + $entry.component); continue }
        if ($entry.PSObject.Properties.Name -contains 'chains') {
            if (@($entry.chains) -notcontains $chainName) { continue }
        }
        # A common-scope tree is shared by both chains, so it is patched once,
        # by the first chain in the list. Walking it twice would report the
        # second pass as "already patched" and hide which chain did the work.
        if ($lay.scope -eq 'common' -and $chainName -ne $Chains[0]) { continue }
        $treeRoot = Get-TreeRoot $Root $lay $chainName
        $isRename = $entry.PSObject.Properties.Name -contains 'rename_file'
        $srcRel = if ($isRename) { $entry.rename_file.from } else { $entry.file }
        $dstRel = if ($isRename) { $entry.rename_file.to } else { $entry.file }
        $tag = '{0,-11} {1,-6} {2,-27}' -f $entry.component, $chainName, $dstRel

        $srcPath = Join-Path $treeRoot ($srcRel -replace '/', '\')
        $dstPath = Join-Path $treeRoot ($dstRel -replace '/', '\')

        # ---- rename_file: no diff bytes, so it is handled on its own ----
        if ($isRename) {
            $dstExists = Test-Path -LiteralPath $dstPath
            $srcExists = Test-Path -LiteralPath $srcPath
            if ($dstExists -and -not $srcExists) {
                $got = Get-FileSha $dstPath
                $rnOk = ($got -eq $entry.sha256)
                $results += [pscustomobject]@{ comp = $entry.component; chain = $chainName; tag = $tag; action = $(if ($rnOk) { 'renamed-ok' } else { 'HASH-MISMATCH' }); cr = 0 }
                if (-not $rnOk) { $failures += ($tag + 'renamed file hash ' + $got.Substring(0, 12) + ' != expected ' + $entry.sha256.Substring(0, 12)) }
                '{0} {1}' -f $tag, $(if ($rnOk) { 'renamed-ok' } else { 'HASH-MISMATCH' })
                continue
            }
            if (-not $srcExists) {
                $results += [pscustomobject]@{ comp = $entry.component; chain = $chainName; tag = $tag; action = 'ABSENT'; cr = 0 }
                $failures += ($tag + 'neither ' + $srcRel + ' nor ' + $dstRel + ' exists')
                continue
            }
            if ($dstExists) {
                $results += [pscustomobject]@{ comp = $entry.component; chain = $chainName; tag = $tag; action = 'BOTH-EXIST'; cr = 0 }
                $failures += ($tag + 'both ' + $srcRel + ' and ' + $dstRel + ' exist')
                continue
            }
            if ($VerifyOnly) {
                $results += [pscustomobject]@{ comp = $entry.component; chain = $chainName; tag = $tag; action = 'NOT-APPLIED'; cr = 0 }
                $failures += ($tag + 'verify: still named ' + $srcRel)
                continue
            }
            if ($DryRun) {
                $results += [pscustomobject]@{ comp = $entry.component; chain = $chainName; tag = $tag; action = 'would rename'; cr = 0 }
                '{0} would rename {1} -> {2}' -f $tag, $srcRel, $dstRel
                continue
            }
            # A rename is staged like a file edit: the bytes are copied to the
            # staging directory and verified there, and the tree keeps both names
            # until the whole run commits. Moving first and hashing second would
            # put the tree in a state it was not in before the run, which is what
            # a refusal is supposed to avoid.
            $got = Get-FileSha $srcPath
            if ($got -ne $entry.sha256) {
                $results += [pscustomobject]@{ comp = $entry.component; chain = $chainName; tag = $tag; action = 'HASH-MISMATCH'; cr = 0 }
                $failures += ($tag + 'rename source hash ' + $got.Substring(0, 12) + ' != expected ' + $entry.sha256.Substring(0, 12) + ' (tree left alone)')
                continue
            }
            $staged = Stage-Bytes $chainName $entry.component $dstRel ([System.IO.File]::ReadAllBytes($srcPath))
            $pending += [pscustomobject]@{ kind = 'rename'; src = $srcPath; dst = $dstPath; staged = $staged; tag = $tag }
            $results += [pscustomobject]@{ comp = $entry.component; chain = $chainName; tag = $tag; action = 'staged'; cr = 0 }
            '{0} staged  (rename {1} -> {2})' -f $tag, $srcRel, $dstRel
            continue
        }

        # ---- ordinary file ----
        if (-not (Test-Path -LiteralPath $srcPath)) {
            $results += [pscustomobject]@{ comp = $entry.component; chain = $chainName; tag = $tag; action = 'ABSENT'; cr = 0 }
            $failures += ($tag + 'file absent: ' + $srcPath)
            continue
        }
        $bytes = [System.IO.File]::ReadAllBytes($srcPath)
        $norm = Get-LfBytes $bytes
        $before = Get-BytesSha $norm.bytes
        $crDropped = $norm.dropped

        if ($before -eq $entry.sha256) {
            # Already final. Only trustworthy when the bytes match the expected
            # result exactly, which is precisely what this branch checks.
            $results += [pscustomobject]@{ comp = $entry.component; chain = $chainName; tag = $tag; action = 'ok (already patched)'; cr = 0 }
            # One line per file, like unpack-vendor.ps1 does for its ok trees:
            # a run that silently reports nothing cannot be told from a run that
            # silently checked nothing.
            '{0} ok (already patched)' -f $tag
            continue
        }

        if ($VerifyOnly) {
            $results += [pscustomobject]@{ comp = $entry.component; chain = $chainName; tag = $tag; action = 'NOT-APPLIED'; cr = $crDropped }
            $failures += ($tag + 'verify: not patched (hash ' + $before.Substring(0, 12) + '...)')
            continue
        }

        $isPristine = ($before -eq $entry.from_sha256)
        if (-not $isPristine -and -not $Force) {
            $results += [pscustomobject]@{ comp = $entry.component; chain = $chainName; tag = $tag; action = 'DIRTY'; cr = $crDropped }
            $failures += ($tag + 'neither pristine nor final (hash ' + $before.Substring(0, 12) + '...): re-unpack the tree, do not patch over it')
            continue
        }

        $work = Decode-LfText $norm.bytes $srcPath

        if ($DryRun) {
            $ops = @('eol')
            if ($entry.PSObject.Properties.Name -contains 'rename_token') { $ops += 'rename_token(' + $entry.rename_token.matches + ')' }
            if ($entry.PSObject.Properties.Name -contains 'patch') { $ops += 'patch' }
            $results += [pscustomobject]@{ comp = $entry.component; chain = $chainName; tag = $tag; action = ('would apply: ' + ($ops -join ' + ')); cr = $crDropped }
            '{0} would apply {1}  (drops {2} CR)' -f $tag, ($ops -join ' + '), $crDropped
            continue
        }


        if ($entry.PSObject.Properties.Name -contains 'rename_token') {
            $rt = $entry.rename_token
            $rx = '(?<![\w])' + [regex]::Escape($rt.from) + '(?![\w])'
            $found = @([regex]::Matches($work, $rx)).Count
            if ($found -ne $rt.matches) {
                $results += [pscustomobject]@{ comp = $entry.component; chain = $chainName; tag = $tag; action = 'TOKEN-COUNT'; cr = $crDropped }
                $failures += ($tag + 'rename_token found ' + $found + ' occurrences of ' + $rt.from + ', manifest says ' + $rt.matches)
                continue
            }
            $work = [regex]::Replace($work, $rx, $rt.to)
            $left = @([regex]::Matches($work, $rx)).Count
            if ($left -ne $rt.remaining) {
                $results += [pscustomobject]@{ comp = $entry.component; chain = $chainName; tag = $tag; action = 'TOKEN-LEFT'; cr = $crDropped }
                $failures += ($tag + 'rename_token left ' + $left + ', manifest says ' + $rt.remaining)
                continue
            }
        }

        # The result is assembled in the run-wide staging directory and copied
        # into the tree only after the whole run has produced zero failures.
        # Writing the tree file directly would leave it half-patched on any
        # failure below, and a half-patched file is indistinguishable from a
        # hand-edited one, which is exactly the state this script exists to
        # refuse. Staging also keeps git apply's -p1 path resolution away from
        # the real tree, and away from this repository's .gitattributes.
        $stageBase = Join-Path $StageRoot ($chainName + '\' + $entry.component)
        $stageFile = Join-Path $stageBase ($dstRel -replace '/', '\')
        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $stageFile) -Force
        $applied = $false
        $why = ''
        $verdict = ''
        [System.IO.File]::WriteAllBytes($stageFile, $Utf8NoBom.GetBytes($work))

        if ($entry.PSObject.Properties.Name -contains 'patch' -and $entry.patch) {
            $patchFile = [System.IO.Path]::GetFullPath((Join-Path $PatchRoot ($entry.patch -replace '/', '\')))
            if (-not (Test-Path -LiteralPath $patchFile)) {
                $verdict = 'PATCH-MISSING'; $why = 'patch file absent: ' + $entry.patch
            } else {
                # git apply reads from disk, so it gets the staged copy; -p1
                # turns the patch's own a/<rel> into this very path.
                $g = Invoke-GitApply $stageBase $patchFile
                if ($g.rc -ne 0) {
                    $verdict = 'APPLY-FAILED'; $why = 'git apply rc=' + $g.rc
                    foreach ($l in $g.lines) { if ($l -match 'error|fatal|warning') { '           ' + $l } }
                } else {
                    $applied = $true
                }
            }
        } else {
            $applied = $true
        }

        if ($applied) {
            $after = Get-FileSha $stageFile
            if ($after -eq $entry.sha256) {
                $verdict = 'staged'
                $pending += [pscustomobject]@{ kind = 'write'; dst = $srcPath; staged = $stageFile; tag = $tag; cr = $crDropped }
            } else {
                $verdict = 'HASH-MISMATCH'
                $why = 'result hash ' + $after.Substring(0, 12) + '... != expected ' + $entry.sha256.Substring(0, 12) + '...'
            }
        }

        if ($verdict -ne 'staged') {
            $results += [pscustomobject]@{ comp = $entry.component; chain = $chainName; tag = $tag; action = $verdict; cr = $crDropped }
            $failures += ($tag + $why + ' (not staged)')
            continue
        }
        $results += [pscustomobject]@{ comp = $entry.component; chain = $chainName; tag = $tag; action = $verdict; cr = $crDropped }
        '{0} staged  (eol -{1} CR)' -f $tag, $crDropped
    }
}

# ------------------------------------------------------------------- commit ---
# Everything above computed and verified; nothing above touched a tree. This is
# the only place that writes, so a refusal anywhere leaves the trees exactly as
# they were found.
$committed = 0
if (-not $VerifyOnly -and -not $DryRun) {
    if ($failures.Count -gt 0) {
        ''
        'COMMIT REFUSED: ' + $failures.Count + ' failure(s), so none of the ' + $pending.Count +
            ' staged change(s) was written.'
        '                The trees are byte-for-byte as they were found; re-unpack'
        '                and re-run rather than patching over the refusal.'
    } else {
        foreach ($ch in $pending) {
            # Copy the verified bytes rather than moving the staged file: the
            # staging directory lives on the system drive while -Root may be
            # another volume, and a cross-volume Move-Item is a copy-then-delete
            # with the tree file briefly absent.
            [System.IO.File]::WriteAllBytes($ch.dst, [System.IO.File]::ReadAllBytes($ch.staged))
            if ($ch.kind -eq 'rename') { Remove-Item -LiteralPath $ch.src -Force }
            $committed++
        }
        ''
        'committed ' + $committed + ' change(s)'
    }
}
# Normal-path cleanup; the trap above covers a throw escaping the run loop.
if (Test-Path -LiteralPath $StageRoot) { Remove-Item -LiteralPath $StageRoot -Recurse -Force }

# ------------------------------------------------- read the markers back ---
# The marker records which patches.json produced the tree. Nothing here fails on
# a disagreement: the per-file sha256 checks above are the authority on the
# bytes, and a manifest edit that only touches notes or a note in Russian does
# not change what a tree should contain. It is printed because the field would
# otherwise be write-only provenance, and a stale marker is worth a human seeing:
# "these trees were patched from a different patch set text" is exactly what you
# want to know before trusting an -VerifyOnly pass on someone else's machine.
if (-not $DryRun) {
    $curManifestSha = Get-FileSha $ManifestPath
    $staleMarkers = 0
    foreach ($chainName in $Chains) {
        foreach ($comp in $wantedComponents) {
            $lay = $ByComponent[$comp]
            if (-not $lay) { continue }
            $treeRoot = Get-TreeRoot $Root $lay $chainName
            $markPath = Join-Path $treeRoot $MarkerName
            if (-not (Test-Path -LiteralPath $markPath)) { continue }
            $mk = $null
            try { $mk = Get-Content -LiteralPath $markPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $mk = $null }
            if (-not $mk) {
                'note: ' + $comp + ' ' + $chainName + ' marker is not readable JSON: ' + $markPath
                $staleMarkers++
                continue
            }
            if ($mk.manifest_sha256 -ne $curManifestSha) {
                'note: ' + $comp + ' ' + $chainName + ' marker was written against manifest ' +
                    $(if ($mk.manifest_sha256) { $mk.manifest_sha256.Substring(0, 12) + '...' } else { '(no manifest_sha256)' }) +
                    ', current is ' + $curManifestSha.Substring(0, 12) + '...'
                $staleMarkers++
            }
        }
    }
    if ($staleMarkers -gt 0) {
        '      ' + $staleMarkers + ' marker(s) disagree with the current patches.json.'
        '      File hashes above are what decides whether the trees are correct.'
    }
}

# ------------------------------------------------------------------- marker ---
if (-not $VerifyOnly -and -not $DryRun -and $failures.Count -eq 0) {
    $manifestSha = Get-FileSha $ManifestPath
    foreach ($chainName in $Chains) {
        foreach ($comp in $wantedComponents) {
            $lay = $ByComponent[$comp]
            $treeRoot = Get-TreeRoot $Root $lay $chainName
            if (-not (Test-Path -LiteralPath $treeRoot)) { continue }
            if (@($results | Where-Object { $_.comp -eq $comp -and $_.chain -eq $chainName }).Count -eq 0) { continue }
            # Same shape as step 1's marker: chain is present only where the
            # tree belongs to a chain, so a common-scope tree does not grow a
            # field that would have to mean "which of the two".
            $mark = [ordered]@{
                schema = $Manifest.schema
                component = $comp
                archive = $lay.archive
                scope = $lay.scope
                dir = $lay.dir
            }
            if ($lay.scope -ne 'common') { $mark.chain = $chainName }
            $mark.manifest = 'patches/patches.json'
            $mark.manifest_sha256 = $manifestSha
            $mark.canon = $Manifest.canon
            $markPath = Join-Path $treeRoot $MarkerName
            [System.IO.File]::WriteAllBytes($markPath, $Utf8NoBom.GetBytes((($mark | ConvertTo-Json -Depth 5) -replace "`r`n", "`n") + $Lf))
        }
    }
}

# ------------------------------------------------------------------ verdict ---
''
$byAction = @{}
foreach ($r in $results) {
    $k = $r.action
    if ($byAction.ContainsKey($k)) { $byAction[$k]++ } else { $byAction[$k] = 1 }
}
'verdict: ' + (($byAction.Keys | Sort-Object | ForEach-Object { $_ + ' ' + $byAction[$_] }) -join ', ')
$totalCr = @($results | Measure-Object -Property cr -Sum).Sum
'       eol normalization dropped ' + $totalCr + ' CR byte(s)'

if ($failures.Count -gt 0) {
    ''
    foreach ($f in $failures) { 'FAIL ' + $f }
    ''
    if ($VerifyOnly) { 'APPLY-VERIFICATION FAILED' } else { 'APPLY FAILED' }
    exit 1
}
''
if ($DryRun) { 'DRY RUN OK: nothing written' }
elseif ($VerifyOnly) { 'APPLY-VERIFICATION OK: every declared file carries its expected bytes' }
else { 'APPLY OK' }
exit 0
