# unpack-vendor.ps1 --
#   Expand the archives in vendor/ into the build layout described by
#   scripts/vendor-layout.json. This is step 1 of BUILDING.md, which used to be
#   a manual instruction ("unpack vendor/ into the fixed paths the build
#   expects") because nothing else could be trusted to get the renames right.
#
#   Why the step was not automated before: seven of the fifteen archives have a
#   top-level directory that differs from the path every build script uses
#   (twapi-5.2 vs twapi-5.2.0, mpexpr-master vs mpexpr,
#   tkdnd-tkdnd-release-test-v2.9.5 vs tkdnd-2.9.5, ...). An unpack that
#   extracts in place produces a tree that no build script can find, and the
#   failure surfaces much later as a missing-file error in a makefile. The map
#   of those renames is now data, so the step can be executed instead of
#   performed by hand.
#
#   Three properties this script is built around:
#
#     * vendor/ is never written to. The archives are read-only inputs, exactly
#       as when a person did this by hand, so a half-done run cannot corrupt a
#       fetched copy.
#
#     * Nothing is unpacked that fetch-vendor.ps1 has not verified. The run
#       starts by calling it with -VerifyOnly and refuses to continue unless it
#       exits 0, so a wrong archive cannot reach a build tree and show up later
#       as an incomprehensible configure error (the dyncall 200/HTML trap,
#       docs/SOURCES.md).
#
#     * A tree is either complete or absent. Extraction goes to a scratch
#       directory on the same volume and the result is renamed into place; the
#       marker file is written only after that rename succeeds. A run killed in
#       the middle leaves an unmarked directory, which -VerifyOnly reports and
#       which a later -Force run replaces. This is the property the manual step
#       used to claim for itself ("a half-extracted tree cannot be mistaken for
#       a fetched one") and it now holds with nobody watching.
#
#   Usage:
#     scripts\unpack-vendor.ps1                  # unpack what is missing
#     scripts\unpack-vendor.ps1 -VerifyOnly      # check the trees, write nothing
#     scripts\unpack-vendor.ps1 -DryRun          # print the plan, touch nothing
#     scripts\unpack-vendor.ps1 -Force           # replace trees that exist
#     scripts\unpack-vendor.ps1 -Chain msvc      # one toolchain only
#     scripts\unpack-vendor.ps1 -Only tkdnd,itk  # a subset of components
#     scripts\unpack-vendor.ps1 -Root D:\other   # repo root override
#
#   Exit code 0 only when every planned destination is present and marked.
#
#   ASCII-only, CRLF (docs/CONVENTIONS.md rule for .ps1).

param(
    [string]$Root = '',
    [string]$Chain = 'both',
    [string[]]$Only = @(),
    [switch]$VerifyOnly,
    [switch]$DryRun,
    [switch]$Force
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# powershell -File passes "-Only a,b,c" as ONE string, while -File-free
# invocation binds it as an array; normalize so both forms work.
if ($Only.Count -eq 1 -and $Only[0] -match ',') {
    $Only = @($Only[0] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
}

# $PSScriptRoot is not populated during parameter binding on Windows
# PowerShell 5.1, so the root is resolved in the body, not in param().
# Same rule as fetch-vendor.ps1.
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
$Vendor  = Join-Path $Root 'vendor'
$Build   = Join-Path $Root 'build'
$Scratch = Join-Path $Build '_unpack'
$LayoutPath = Join-Path $PSScriptRoot 'vendor-layout.json'
$Utf8 = New-Object System.Text.UTF8Encoding($false)

if (-not (Test-Path -LiteralPath $LayoutPath)) { throw 'layout map missing: ' + $LayoutPath }
$Layout = Get-Content -LiteralPath $LayoutPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $Layout.entries -or @($Layout.entries).Count -eq 0) {
    throw 'layout map yielded 0 entries: ' + $LayoutPath
}
$ScopePaths = $Layout.rules.scopePaths
$MarkerName = $Layout.rules.marker

function Get-ShaHex([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLower()
}

function Get-DestPaths($Entry) {
    # A common entry has no chains key: it is one tree shared by both toolchains.
    # core/ext entries carry the chains they are unpacked for. scopePaths are
    # repo-relative ("build/{chain}"), so they hang off $Root, not off $Build --
    # joining them to $Build produced build\build\msvc.
    $base = $ScopePaths.($Entry.scope)
    if ($null -eq $base -or $base -eq '') { throw 'unknown scope "' + $Entry.scope + '" for ' + $Entry.component }
    $sep = [System.IO.Path]::DirectorySeparatorChar
    $out = @()
    if ($Entry.PSObject.Properties.Name -contains 'chains') {
        foreach ($ch in @($Entry.chains)) {
            $rel = ($base -replace '\{chain\}', $ch) -replace '/', $sep
            $out += [pscustomobject]@{ dest = (Join-Path (Join-Path $Root $rel) $Entry.dir); chain = $ch }
        }
    } else {
        if ($base -match '\{chain\}') { throw 'scope ' + $Entry.scope + ' needs a chain but the entry has none' }
        $rel = $base -replace '/', $sep
        $out += [pscustomobject]@{ dest = (Join-Path (Join-Path $Root $rel) $Entry.dir); chain = '' }
    }
    return $out
}

function Test-TopName($Entry, [string]$Name) {
    # '' when $Name is the top-level directory the map expects, else the reason.
    # Fixed-top entries must match exactly. Movable entries carry top_prefix
    # instead of top, because on GitHub the ref name IS the directory name:
    # tktreectrl-main/ (branch form) and tktreectrl-<sha>/ (commit-pinned form)
    # are both correct, and a fixed top would reject whichever form
    # fetch-vendor.ps1 did not measure. Same reason that script leaves t='' on
    # those rows (docs/SOURCES.md, "movable git refs").
    $props = $Entry.PSObject.Properties.Name
    if ($props -contains 'top') {
        if ($Name -eq $Entry.top) { return '' }
        return 'top "' + $Name + '", map says "' + $Entry.top + '"'
    }
    if ($props -contains 'top_prefix') {
        $pfx = $Entry.top_prefix
        if ($Name.Length -gt $pfx.Length -and $Name.StartsWith($pfx, [System.StringComparison]::Ordinal)) { return '' }
        return 'top "' + $Name + '", map requires prefix "' + $pfx + '"'
    }
    return 'entry ' + $Entry.component + ' has neither top nor top_prefix'
}

function Test-Dest([string]$Dest, $Entry, [string]$ArchiveSha) {
    # Returns '' when the tree is present and marked from this very archive,
    # otherwise the reason it is not usable.
    if (-not (Test-Path -LiteralPath $Dest)) { return 'MISSING' }
    $files = @(Get-ChildItem -LiteralPath $Dest -Recurse -File -Force -EA SilentlyContinue)
    if ($files.Count -eq 0) { return 'EMPTY (no files)' }
    $markPath = Join-Path $Dest $MarkerName
    if (-not (Test-Path -LiteralPath $markPath)) { return 'UNMARKED (' + $files.Count + ' files, no ' + $MarkerName + ')' }
    $mark = $null
    try { $mark = Get-Content -LiteralPath $markPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return 'marker unreadable' }
    if ($mark.component -ne $Entry.component) { return 'marker names ' + $mark.component }
    if ($mark.archive -ne $Entry.archive) { return 'marker names ' + $mark.archive }
    $why = Test-TopName $Entry $mark.top
    if ($why) { return $why }
    if ($mark.sha256 -ne $ArchiveSha) { return 'marker sha ' + $mark.sha256.Substring(0, 12) + '..., vendor is ' + $ArchiveSha.Substring(0, 12) + '...' }
    # The Tcl tree carries the eight pkg directories that have no archive of
    # their own; if they are absent, the entry that provides them is a lie.
    if ($Entry.PSObject.Properties.Name -contains 'provides') {
        foreach ($p in @($Entry.provides)) {
            $sub = Join-Path (Join-Path $Dest 'pkgs') $p
            if (-not (Test-Path -LiteralPath $sub)) { return 'provided dir absent: pkgs\' + $p }
        }
    }
    return ''
}

# ---------------------------------------------------------------- the plan ---
$plan = @()
foreach ($e in @($Layout.entries)) {
    if ($Only.Count) {
        $want = $false
        foreach ($o in $Only) { if ($o -ieq $e.component) { $want = $true; break } }
        if (-not $want) { continue }
    }
    foreach ($d in (Get-DestPaths $e)) {
        # A shared (common-scope) tree has no chain, so -Chain keeps it: both
        # toolchains read the same tcllib tree.
        if ($Chain -ne 'both' -and $d.chain -ne '' -and $d.chain -ne $Chain) { continue }
        $plan += [pscustomobject]@{ entry = $e; dest = $d.dest; chain = $d.chain }
    }
}
if ($plan.Count -eq 0) { throw 'the plan is empty: -Only/-Chain matched nothing in the layout map' }

'mode: '    + $(if ($DryRun) { 'dry run' } elseif ($VerifyOnly) { 'verify only' } else { 'unpack' }) + $(if ($Force) { ', force' } else { '' })
'root: '    + $Root
'layout: '  + $LayoutPath + '  (schema ' + $Layout.schema + ', ' + @($Layout.entries).Count + ' entries)'
'plan: '    + $plan.Count + ' tree(s)'
''

if ($DryRun) {
    foreach ($p in $plan) {
        '{0,-12} {1,-7} {2}' -f $p.entry.component, $(if ($p.chain) { $p.chain } else { 'shared' }), $p.dest
    }
    ''
    'DRY RUN DONE (nothing written)'
    exit 0
}

# ----------------------------------------------------- precondition: vendor ---
if (-not $VerifyOnly) {
    $fv = Join-Path $PSScriptRoot 'fetch-vendor.ps1'
    if (-not (Test-Path -LiteralPath $fv)) { throw 'fetch-vendor.ps1 not found: ' + $fv }
    'precondition: fetch-vendor.ps1 -VerifyOnly'
    $fvOut = @(& $fv -VerifyOnly -Root $Root 2>&1 | Out-String -Stream)
    $fvRc = $LASTEXITCODE
    foreach ($l in $fvOut) { if ($l -match '^(verdict|FETCH-VENDOR)') { '            ' + $l } }
    if ($fvRc -ne 0) {
        'PRECONDITION FAILED: fetch-vendor.ps1 -VerifyOnly rc=' + $fvRc + ' for'
        '                   vendor dir: ' + (Join-Path $Root 'vendor')
        '                   (a throwaway -Root needs its own copy of vendor/)'
        '                   refusing to unpack'
        exit 1
    }
    ''
}

# ------------------------------------------------------------------- run ---
Add-Type -AssemblyName System.IO.Compression.FileSystem
$ok = 0; $skipped = 0; $failed = @()
foreach ($p in $plan) {
    $e = $p.entry
    $archPath = Join-Path $Vendor $e.archive
    $tag = '{0,-12} {1,-7}' -f $e.component, $(if ($p.chain) { $p.chain } else { 'shared' })
    if (-not (Test-Path -LiteralPath $archPath)) {
        $failed += ($e.component + ': archive not in vendor/: ' + $e.archive)
        ($tag + 'MISSING ARCHIVE ' + $e.archive)
        continue
    }
    $sha = Get-ShaHex $archPath
    $state = Test-Dest $p.dest $e $sha
    if ($state -eq '' -and (-not $Force -or $VerifyOnly)) {
        # -Force falls through even here: a marked tree is exactly the case the
        # flag exists for. Before 2026-10-29 this early skip ran first, so
        # -Force silently did nothing to any tree that had ever verified, which
        # is the state a patched tree is in -- step 2 needs "give me pristine
        # bytes back" to work on a patched tree, not only on a damaged one.
        $skipped++
        ($tag + 'ok (marked, ' + $e.archive + ')')
        continue
    }
    if ($VerifyOnly) {
        $failed += ($e.component + ' ' + $p.dest + ': ' + $state)
        ($tag + 'BAD  ' + $state)
        continue
    }
    if ($state -ne 'MISSING' -and -not $Force) {
        $failed += ($e.component + ' ' + $p.dest + ': ' + $state + ' (use -Force)')
        ($tag + 'REFUSED ' + $state)
        continue
    }
    if ($state -ne 'MISSING' -and $Force) {
        Remove-Item -LiteralPath $p.dest -Recurse -Force
    }

    # Extract to a scratch directory on the same volume, then rename. A move
    # inside one volume is a directory rename, so no partial tree is ever
    # visible under the final name.
    $sc = Join-Path $Scratch ($e.component + '-' + [System.Guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Force -Path $sc | Out-Null
    $destParent = Split-Path -Parent $p.dest
    New-Item -ItemType Directory -Force -Path $destParent | Out-Null
    try {
        if ($e.kind -eq 'zip') {
            [System.IO.Compression.ZipFile]::ExtractToDirectory($archPath, $sc)
        } else {
            $flag = if ($e.kind -eq 'txz') { '-xJf' } else { '-xzf' }
            & tar $flag $archPath '-C' $sc 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'tar ' + $flag + ' failed (rc=' + $LASTEXITCODE + ')' }
        }
        $tops = @(Get-ChildItem -LiteralPath $sc -Directory)
        if ($tops.Count -ne 1) { throw 'archive unpacked to ' + $tops.Count + ' top-level directories, map expects one' }
        $topWhy = Test-TopName $e $tops[0].Name
        if ($topWhy) { throw $topWhy }
        Move-Item -LiteralPath $tops[0].FullName -Destination $p.dest
        $marker = [ordered]@{
            schema    = $Layout.schema
            component = $e.component
            archive   = $e.archive
            kind      = $e.kind
            top       = $tops[0].Name
            sha256    = $sha
            scope     = $e.scope
            dir       = $e.dir
        }
        if ($p.chain) { $marker['chain'] = $p.chain }
        [System.IO.File]::WriteAllText((Join-Path $p.dest $MarkerName), ($marker | ConvertTo-Json -Depth 4), $Utf8)
        $n = @(Get-ChildItem -LiteralPath $p.dest -Recurse -File -Force).Count
        $ok++
        ($tag + 'unpacked (' + $n + ' files)')
    } catch {
        $failed += ($e.component + ' ' + $p.dest + ': ' + $_.Exception.Message)
        ($tag + 'FAILED ' + $_.Exception.Message)
        if (Test-Path -LiteralPath $p.dest) { Remove-Item -LiteralPath $p.dest -Recurse -Force -EA SilentlyContinue }
    } finally {
        if (Test-Path -LiteralPath $sc) { Remove-Item -LiteralPath $sc -Recurse -Force -EA SilentlyContinue }
    }
}
if (-not $VerifyOnly) {
    if (Test-Path -LiteralPath $Scratch) {
        $left = @(Get-ChildItem -LiteralPath $Scratch -Recurse -Force -EA SilentlyContinue)
        if ($left.Count -eq 0) { Remove-Item -LiteralPath $Scratch -Recurse -Force -EA SilentlyContinue }
    }
}

''
'verdict: ' + $(if ($VerifyOnly) { 'ok ' + $skipped + '  bad ' + $failed.Count } else { 'unpacked ' + $ok + '  already ok ' + $skipped + '  failed ' + $failed.Count })
if ($failed.Count) {
    foreach ($f in $failed) { '  ' + $f }
    'UNPACK-VENDOR FAILED'
    exit 1
}
'UNPACK-VENDOR OK'
exit 0
