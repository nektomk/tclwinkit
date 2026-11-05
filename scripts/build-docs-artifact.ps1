# build-docs-artifact.ps1 -- assemble the 5th build artifact: documentation,
# man pages and demos as a single zip next to the four kit executables.
#
#   pwsh -File scripts\build-docs-artifact.ps1 [-Keep]
#
# Rationale: the kit zipfs images carry only what is needed to RUN scripts
# (tests/doc/demos/html are stripped from tcllib/tklib during assembly). This
# script gathers everything a reader may still want -- reference pages, HTML
# manuals, runnable demos, licenses, changelogs -- into
# dist\tclwinkit-docs-<version>.zip, so nothing is lost but nothing inflates
# the executables.
#
# Requires the build trees to exist (build-msvc-*.bat / build-mingw-*.sh and
# the assemble scripts have been run at least once). -Keep leaves the staging
# tree in build\docs-stage for inspection.

[CmdletBinding()]
param(
    [string]$Root = '',
    [switch]$Keep,
    [switch]$KeepStale
)
$ErrorActionPreference = 'Stop'

# $PSScriptRoot is not populated during parameter binding on Windows
# PowerShell 5.1, so the default is resolved in the body, not in param().
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }

# Deterministic ZIP writers and the ordinal directory walk they need. Loaded
# here, not next to the zip call, because VERSIONS.txt and MANIFEST.txt -- both
# of which end up inside the archive -- have to be laid out in the same order.
. "$Root\scripts\zip-entry.ps1"

$M   = "$Root\build\msvc"
$C   = "$Root\build\common"
$P   = "$M\tcl9.0.4\pkgs"
$E   = "$M\ext"
$Src = "$Root\src\docs"
$Ver = (Select-String -Path "$Root\src\kit\vfs\lib\kit_init.tcl" -Pattern 'variable version\s+(\S+)' |
        Select-Object -First 1).Matches[0].Groups[1].Value
$Name  = "tclwinkit-docs-$Ver"
$Stage = "$Root\build\docs-stage\$Name"
$Dist  = "$Root\dist"
$Zip   = "$Dist\$Name.zip"

# Files this script generates itself (VERSIONS.txt, MANIFEST.txt) end up inside
# the published archive, so they are UTF-8 without BOM with LF endings.
# Set-Content -Encoding UTF8 must not be used here: on Windows PowerShell 5.1
# it emits a BOM *and* CRLF (verified: first bytes EF BB BF ... 0D 0A).
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
function Put-LfText([string]$Path, [string[]]$Lines) {
    [System.IO.File]::WriteAllText($Path, (($Lines -join "`n") + "`n"), $script:Utf8NoBom)
}

# $req, not $d: PowerShell names are case-INsensitive and $D (the staging dir) is
# assigned a few lines below, so a loop variable spelled $d would have clobbered it
# had the order ever been flipped. Same reason for $ent vs $E (= "$M\ext") below.
foreach ($req in @($M, $C, $Src)) {
    if (-not (Test-Path $req)) { throw "missing build tree: $req (run the build scripts first)" }
}
if (Test-Path $Stage) { Remove-Item -Recurse -Force $Stage }
New-Item -ItemType Directory -Force "$Stage\$Name" | Out-Null
New-Item -ItemType Directory -Force $Dist | Out-Null
$D = "$Stage\$Name"
foreach ($k in 'man', 'html', 'demos', 'docs', 'LICENSES', 'tools') {
    New-Item -ItemType Directory -Force "$D\$k" | Out-Null
}

# ----------------------------------------------------------------- copying ---
# Copy a whole subtree, then drop the excluded leaves. $Exclude holds paths
# relative to the source root (dirs or file patterns).
function Copy-Set {
    param([string]$Src_, [string]$Dst_, [string[]]$Exclude = @(), [string[]]$OnlyFiles = @())
    if (-not $Exclude)   { $Exclude = @() }
    if (-not $OnlyFiles) { $OnlyFiles = @() }
    if (-not (Test-Path $Src_)) { Write-Warning "absent: $Src_"; return 0 }
    New-Item -ItemType Directory -Force $Dst_ | Out-Null
    if ($OnlyFiles.Count) {
        foreach ($pat in $OnlyFiles) {
            Get-ChildItem $Src_ -Filter $pat -File -EA SilentlyContinue | ForEach-Object {
                Copy-Item $_.FullName $Dst_
            }
        }
    } else {
        Get-ChildItem $Src_ -Force | Copy-Item -Destination $Dst_ -Recurse -Force
    }
    foreach ($rel in $Exclude) {
        $t = Join-Path $Dst_ $rel
        if (Test-Path $t) { Remove-Item -Recurse -Force $t }
    }
    (Get-ChildItem $Dst_ -Recurse -File -EA SilentlyContinue | Measure-Object).Count
}

# Loose top-level documents of a package tree (README, changelogs, *.md, ...).
$DocPatterns = 'README*', '*.md', 'CHANGES', 'Changes*', 'ChangeLog', 'STATUS',
               'DESCRIPTION*', 'INTRODUCTION*', '*.txt', 'news*', 'NEWS*'
function Copy-Docs {
    param([string]$Src_, [string]$Dst_)
    if (-not (Test-Path $Src_)) { return 0 }
    New-Item -ItemType Directory -Force $Dst_ | Out-Null
    $n = 0
    foreach ($pat in $DocPatterns) {
        Get-ChildItem $Src_ -Filter $pat -File -EA SilentlyContinue | ForEach-Object {
            Copy-Item $_.FullName $Dst_ -Force; $script:n++
        }
    }
    $n
}
# Vendor licence texts are NOT collected here any more. They used to be gathered
# by a per-root glob (license.terms / LICENSE* / copyright*) into a flat
# licenses/ directory; scripts/make-licenses.ps1 now generates the audited,
# supersetting LICENSES/ tree in the repository (54 texts plus the in-file
# sweep), and the archive ships that verbatim so THIRD-PARTY-NOTICES.md links
# resolve inside the artifact. Keeping both would have meant two directories
# differing only by case, which merge into one on NTFS extractions.

# Iwidgets demos load their pictures/help from "$iwidgets::library/demos/...".
# In a kit that variable points inside the zipfs image, which has no demos, so
# the staged copies get repointed at their own directory. The vendor tree is
# left untouched: this is a packaging rule, not a runtime patch.
$IwRepoint = [ordered]@{
    '$iwidgets::library/demos/images/'          = '$::iwdemo_dir/images/'
    '[file join ${iwidgets::library} demos images]'    = '[file join $::iwdemo_dir images]'
    '[file join ${iwidgets::library} demos demo.html]' = '[file join $::iwdemo_dir demo.html]'
    '[file join ${iwidgets::library} demos scrolledtext]' = '[file join $::iwdemo_dir scrolledtext]'
    '-helpdir [file join ${iwidgets::library} demos]'  = '-helpdir $::iwdemo_dir'
}
function Fix-IwidgetsDemoPaths {
    param([string]$Dir)
    $n = 0
    foreach ($f in (Get-ChildItem $Dir -File | Where-Object { -not $_.Extension -or $_.Extension -eq '.tcl' })) {
        $bytes = [IO.File]::ReadAllBytes($f.FullName)
        # Preserve the vendor file's own BOM state: these demos are upstream
        # material we only re-point, so nothing invisible about them changes.
        $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
        $txt = $Utf8NoBom.GetString($bytes)
        if ($hasBom) { $txt = $txt.Substring(1) }
        $orig = $txt
        foreach ($k in $IwRepoint.Keys) { $txt = $txt.Replace($k, $IwRepoint[$k]) }
        if ($txt -ne $orig) {
            if ($txt -notmatch 'set ::iwdemo_dir') {
                # Match whatever ending this vendor file already uses: inserting
                # the opposite one would leave a mixed-EOL file in the published
                # archive, which is our doing, not upstream's.
                $eol = if ($txt.Contains("`r`n")) { "`r`n" } else { "`n" }
                # define the anchor right after the package requirement
                $anchor = 'set ::iwdemo_dir [file dirname [info script]]'
                $txt = [regex]::Replace($txt, '(?m)^(package require Iwidgets[^\n]*)$', ('$1' + $eol + $anchor))
            }
            $outEnc = if ($hasBom) { New-Object System.Text.UTF8Encoding($true) } else { $Utf8NoBom }
            [IO.File]::WriteAllText($f.FullName, $txt, $outEnc)
            $n++
        }
    }
    $left = @(Select-String -Path "$Dir\*" -Pattern 'iwidgets::library' -EA SilentlyContinue)
    if ($left.Count) {
        Write-Warning "unrepointed iwidgets::library refs remain: $(($left | ForEach-Object { $_.Filename + ':' + $_.LineNumber }) -join ', ')"
    }
    $n
}

# ------------------------------------------------------------ what we ship ---
# kind  package        source                                        options
$Man = @(
    @{ p = 'tcl';           s = "$M\tcl9.0.4\doc" }
    @{ p = 'tk';            s = "$M\tk9.0.4\doc" }
    @{ p = 'itcl';          s = "$E\itcl4.3.8\doc" }
    @{ p = 'itk';           s = "$E\itk-4.2.7\doc" }
    @{ p = 'iwidgets';      s = "$C\iwidgets-4.1.1\doc" }
    @{ p = 'img';           s = "$E\Img-2.1.2\doc" }
    @{ p = 'tdbc';          s = "$P\tdbc1.1.13\doc" }
    @{ p = 'tdbc-odbc';     s = "$P\tdbcodbc1.1.13\doc" }
    @{ p = 'tdbc-sqlite3';  s = "$P\tdbcsqlite3-1.1.13\doc" }
    @{ p = 'sqlite3';       s = "$P\sqlite3.53.0\doc" }
    @{ p = 'thread';        s = "$P\thread3.0.6\doc"; x = @('html') }
    @{ p = 'rl_json';       s = "$E\rl_json-0.17.8\doc" }
    @{ p = 'tkdnd';         s = "$E\tkdnd-2.9.5\doc"; f = @('*.n') }
    @{ p = 'treectrl';      s = "$E\tktreectrl-2.5.1\doc"; f = @('*.n', '*.man', 'man.macros') }
)
$Html = @(
    @{ p = 'tcllib';   s = "$C\tcllib-2.0\idoc" }
    @{ p = 'tklib';    s = "$C\tklib-0.9\idoc" }
    @{ p = 'twapi';    s = "$E\twapi-5.2.0\doc" }
    @{ p = 'cawt';     s = "$C\cawt-3.1.1\Documentation" }
    @{ p = 'thread';   s = "$P\thread3.0.6\doc\html" }
    @{ p = 'mpexpr';   s = "$E\mpexpr\doc"; f = @('*.html') }
    @{ p = 'tkdnd';    s = "$E\tkdnd-2.9.5\doc"; x = @('*.n') }
    @{ p = 'treectrl'; s = "$E\tktreectrl-2.5.1\doc"; f = @('*.html', 'manual.txt') }
)
$Demos = @(
    @{ p = 'tk';       s = "$M\tk9.0.4\library\demos" }
    @{ p = 'iwidgets'; s = "$C\iwidgets-4.1.1\demos"; x = @('CVS') }
    @{ p = 'itk';      s = "$E\itk-4.2.7\demos" }
    @{ p = 'treectrl'; s = "$E\tktreectrl-2.5.1\demos" }
    # custom_cursors.tcl wants the X11 cursor sets, useless on Windows
    @{ p = 'tkdnd';    s = "$E\tkdnd-2.9.5\demos"; x = @('cursors\unix', 'cursors\unix-x11',
                                                         'custom_cursors.tcl') }
    @{ p = 'cawt';     s = "$C\cawt-3.1.1\TestPrograms" }
)
# itk examples land next to its demos (they are [incr Tk] class samples)
$ExtraDemos = @{ p = 'itk'; s = "$E\itk-4.2.7\examples"; sub = 'examples' }

$Roots = [ordered]@{
    tcl = "$M\tcl9.0.4";            tk = "$M\tk9.0.4"
    itcl = "$E\itcl4.3.8";          itk = "$E\itk-4.2.7"
    iwidgets = "$C\iwidgets-4.1.1"; img = "$E\Img-2.1.2"
    tdbc = "$P\tdbc1.1.13";         'tdbc-odbc' = "$P\tdbcodbc1.1.13"
    'tdbc-sqlite3' = "$P\tdbcsqlite3-1.1.13"; sqlite3 = "$P\sqlite3.53.0"
    thread = "$P\thread3.0.6";      rl_json = "$E\rl_json-0.17.8"
    mpexpr = "$E\mpexpr";           twapi = "$E\twapi-5.2.0"
    treectrl = "$E\tktreectrl-2.5.1"; tkdnd = "$E\tkdnd-2.9.5"
    tcllib = "$C\tcllib-2.0";       tklib = "$C\tklib-0.9"
    cawt = "$C\cawt-3.1.1";         tclreadline = "$C\TclReadLine"
}

$stats = [ordered]@{ man = 0; html = 0; demos = 0; docs = 0; LICENSES = 0; tools = 0 }

foreach ($ent in $Man) {
    $stats.man += Copy-Set -Src_ $ent.s -Dst_ "$D\man\$($ent.p)" -Exclude $ent.x -OnlyFiles $ent.f
}
foreach ($ent in $Html) {
    $stats.html += Copy-Set -Src_ $ent.s -Dst_ "$D\html\$($ent.p)" -Exclude $ent.x -OnlyFiles $ent.f
}
foreach ($ent in $Demos) {
    $stats.demos += Copy-Set -Src_ $ent.s -Dst_ "$D\demos\$($ent.p)" -Exclude $ent.x -OnlyFiles $ent.f
}
$stats.demos += Copy-Set -Src_ $ExtraDemos.s -Dst_ "$D\demos\$($ExtraDemos.p)\$($ExtraDemos.sub)"
$fixed = Fix-IwidgetsDemoPaths "$D\demos\iwidgets"
foreach ($k in $Roots.Keys) {
    $stats.docs     += Copy-Docs   -Src_ $Roots[$k] -Dst_ "$D\docs\$k"
}

Copy-Item "$Src\man.tcl"            "$D\tools\" -Force
Copy-Item "$Src\iwidgets-demo.tcl"  "$D\tools\" -Force
$stats.tools = (Get-ChildItem "$D\tools" -File).Count
Copy-Item "$Src\README.md"          "$D\README.md" -Force

# ------------------------------------------------------- our own licences ---
# The docs artifact is the only thing a downloader of the executables gets
# besides the exes themselves, so the attribution document has to travel with
# it -- otherwise the notices required by Tcl/Info-ZIP/IJG/libtiff exist only
# in the repository. LICENSES/ is the generated tree (scripts/make-licenses.ps1);
# a missing or stale copy is a release blocker, not a warning.
foreach ($f in 'LICENSE', 'THIRD-PARTY-NOTICES.md') {
    if (-not (Test-Path "$Root\$f")) { throw "release artifact missing: $Root\$f" }
    Copy-Item "$Root\$f" "$D\$f" -Force
}
if (-not (Test-Path "$Root\LICENSES")) { throw "LICENSES/ is not generated; run scripts/make-licenses.ps1 first" }
# copy the CONTENTS: $D\LICENSES already exists (created above), and Copy-Item
# with a directory source would nest LICENSES/LICENSES into it
Copy-Item "$Root\LICENSES\*" "$D\LICENSES" -Recurse -Force
$stats.LICENSES = @(Get-ChildItem "$D\LICENSES" -Recurse -File).Count

# drop empty directory leaves (an OnlyFiles set may have matched nothing)
$pass = $true
while ($pass) {
    $pass = $false
    Get-ChildItem $D -Recurse -Directory | Sort-Object { $_.FullName.Length } -Descending |
        Where-Object { -not (Get-ChildItem $_.FullName -Force -EA SilentlyContinue) } |
        ForEach-Object { Remove-Item $_.FullName -Force; $script:pass = $true }
}

# --------------------------------------------------------------- VERSIONS ---
# Build stamp. A wall-clock "generated:" line makes the archive differ on
# every run even when its content is byte-identical, which is exactly what
# defeats the published digest (see scripts\zip-entry.ps1 for the same class
# of defect in the ZIP headers). So the stamp is derived from the tree, not
# from the clock. Priority:
#   1. SOURCE_DATE_EPOCH -- the reproducible-builds.org convention, integer
#      seconds since the Unix epoch, honored verbatim when present;
#   2. the committer date of HEAD -- a property of the commit, so two people
#      building the same commit produce the same stamp;
#   3. neither -- refuse to build rather than ship an artifact whose published
#      digest nobody can re-verify.
$stamp = $null
$stampSrc = $null
if ($env:SOURCE_DATE_EPOCH -and $env:SOURCE_DATE_EPOCH -match '^[0-9]+$') {
    $stamp = [System.DateTimeOffset]::FromUnixTimeSeconds([int64]$env:SOURCE_DATE_EPOCH).
        ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
    $stampSrc = 'SOURCE_DATE_EPOCH'
} else {
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git) {
        $cd = @(& $git.Source -C $Root show -s --format=%cI HEAD 2>$null)
        if ($LASTEXITCODE -eq 0 -and $cd.Count -ge 1 -and $cd[0].Trim()) {
            $stamp = [System.DateTimeOffset]::Parse($cd[0].Trim()).ToUniversalTime().
                ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
            $sha = @(& $git.Source -C $Root rev-parse --short=7 HEAD 2>$null)
            $stampSrc = 'commit ' + $sha[0].Trim()
        }
    }
}
if (-not $stamp) {
    throw ('no deterministic build stamp: set SOURCE_DATE_EPOCH or build from ' +
           'a git checkout (HEAD committer date)')
}
# Dirty-tree marker. Naming HEAD while the working copy carries uncommitted
# changes would be a lie of the same class as the wall-clock stamp it replaces:
# two people building "commit 4e0f1f1" -- one clean, one with local edits --
# would produce different archives that both claim to be that commit. So the
# stamp says which of the two it is. gitignored scratch (build/) does not
# count: --porcelain omits it by default.
$gitCmd = Get-Command git -ErrorAction SilentlyContinue
if ($gitCmd) {
    $porc = @(& $gitCmd.Source -C $Root status --porcelain 2>$null)
    if ($LASTEXITCODE -eq 0 -and @($porc | Where-Object { $_.Trim() }).Count -gt 0) {
        $stampSrc += ', dirty working tree'
    }
}
$probe = "$Root\build\docs-stage\probe-versions.tcl"
Copy-Item "$Src\versions.tcl" $probe -Force
$vers = @("tclwinkit docs $Ver", ("generated: $stamp ($stampSrc)"))
$vers += ""
$vers += "# runtime package versions (probed from the built kits)"
foreach ($kit in @(@('console', "$Dist\tclwinkit-msvc.exe"), @('gui', "$Dist\winkitwish-msvc.exe"))) {
    $tag, $exe = $kit
    if (-not (Test-Path $exe)) { $vers += "$tag kit: MISSING ($exe)"; continue }
    # the GUI exe has no console: capture its stdout via a redirect file
    $cap = "$Root\build\docs-stage\probe-$tag.out"
    Remove-Item $cap -EA SilentlyContinue
    $pr = Start-Process $exe -ArgumentList @($probe) -RedirectStandardOutput $cap -PassThru -Wait
    if (-not $pr.HasExited -or $pr.ExitCode -ne 0) { }   # tclsh exits 0 on success
    if (Test-Path $cap) {
        $vers += "# --- $tag kit ($([IO.Path]::GetFileName($exe))) ---"
        $vers += @(Get-Content $cap | Where-Object { $_ -match "`t" })
    } else {
        $vers += "$tag kit: probe produced no output"
    }
}
$vers += ""
$vers += "# doc sets shipped in this archive"
foreach ($k in 'man', 'html', 'demos', 'docs') {
    Get-ChildItem "$D\$k" -Directory -EA SilentlyContinue | ForEach-Object {
        $f = @(Get-ChildItem $_.FullName -Recurse -File)
        $vers += ("{0,-6} {1,-14} {2,5} files {3,8:N2} KB" -f $k, $_.Name, $f.Count,
                  ((($f | Measure-Object Length -Sum).Sum) / 1KB))
    }
}
Put-LfText "$D\VERSIONS.txt" $vers

# --------------------------------------------------------------- MANIFEST ---
# Ordinal order, same reason as the archive walk below: Sort-Object -Property
# FullName compares in the current culture, so the line order of this file --
# which is inside the published archive -- would vary per machine.
$all = @(Get-SortedFile -Path $D)
$mf = @("# $Name file manifest ($($all.Count) files)", "")
$mf += $all | ForEach-Object {
    "{0,9}  {1}" -f $_.Length, $_.FullName.Substring($D.Length + 1).Replace('\', '/')
}
Put-LfText "$D\MANIFEST.txt" $mf

# ------------------------------------------------------------------- zip ---
# Entry names are built by hand with forward slashes: .NET Framework's
# ZipFile.CreateFromDirectory (what Windows PowerShell 5.1 runs on) writes
# BACKslashes into the archive, which violates the ZIP spec (APPNOTE 4.4.17
# requires '/') and makes Linux/macOS unzip treat the whole tree as one flat
# file name. Same approach as New-KitZip in the assemble scripts. Entry
# timestamps are pinned through scripts\zip-entry.ps1, so the archive is
# byte-identical between runs and its published digest is checkable.
Add-Type -AssemblyName System.IO.Compression.FileSystem
if (Test-Path $Zip) { Remove-Item $Zip -Force }
$za = [System.IO.Compression.ZipFile]::Open($Zip, 'Create')
try {
    $stageLen = $Stage.Length + 1
    $madeDirs = [System.Collections.Generic.HashSet[string]]::new()
    $entriesList = Get-SortedFile -Path $Stage
    foreach ($entry in $entriesList) {
        $rel = $entry.FullName.Substring($stageLen) -replace '\\', '/'
        $parent = [System.IO.Path]::GetDirectoryName($rel) -replace '\\', '/'
        while ($parent -and $madeDirs.Add($parent)) {
            Add-ZipDir -Zip $za -Name ($parent + '/')
            $parent = [System.IO.Path]::GetDirectoryName($parent) -replace '\\', '/'
        }
        Add-ZipFile -Zip $za -Source $entry.FullName -Name $rel -Level ([System.IO.Compression.CompressionLevel]::Optimal)
    }
} finally { $za.Dispose() }

# verify the archive reads back with spec-conformant names
$check = [System.IO.Compression.ZipFile]::OpenRead($Zip)
try {
    $bad = @($check.Entries | Where-Object { $_.FullName.Contains('\') })
    $entries = $check.Entries.Count
} finally { $check.Dispose() }
if ($bad.Count) {
    throw "zip contains $($bad.Count) backslash entry names, e.g. $($bad[0].FullName)"
}

# ----------------------------------------------------- stale docs archives ---
# The archive name carries the version, so a bump leaves the previous one
# sitting in dist/ beside the new one, and two things break without naming the
# leftover as the cause: BUILDING.md's invariant that dist/ holds exactly five
# files, and verify-docs-artifact.ps1, which refuses to run at all unless
# exactly one tclwinkit-docs-*.zip matches -- it prints "archives matching: 2
# (expected exactly 1)" and then "nothing to verify", so the selftest leg goes
# red looking like a broken archive. Measured on the 0.1 -> 0.2 bump.
# This runs only after the new archive has been written and verified above, so
# a failed build cannot cost the previous good artifact. It touches only this
# script's own artifact family, only inside dist/, and prints every removal:
# a build script that deletes quietly is how a real artifact goes missing.
if ($KeepStale) {
    'stale docs archives kept (-KeepStale)'
} else {
    $stale = @(Get-ChildItem -LiteralPath $Dist -Filter 'tclwinkit-docs-*.zip' -File -EA SilentlyContinue |
               Where-Object { $_.Name -ne ($Name + '.zip') })
    foreach ($s in $stale) {
        $sz = $s.Length
        Remove-Item -LiteralPath $s.FullName -Force
        'removed stale docs archive: {0} ({1:N2} MB), superseded by {2}' -f $s.Name, ($sz / 1MB), ($Name + '.zip')
    }
    if (-not $stale.Count) { 'no stale docs archives in dist/' }
}

$zf = @(Get-ChildItem $D -Recurse -File)
$zb = ($zf | Measure-Object Length -Sum).Sum
$zsize = (Get-Item $Zip).Length
"=== DOCS ARTIFACT ==="
"iwidgets demos repointed to their own dir: $fixed"
foreach ($k in 'man', 'html', 'demos', 'docs', 'LICENSES', 'tools') {
    $f = @(Get-ChildItem "$D\$k" -Recurse -File -EA SilentlyContinue)
    "{0,-10} {1,6} files {2,9:N2} MB" -f $k, $f.Count, (($f | Measure-Object Length -Sum).Sum / 1MB)
}
"{0,-10} {1,6} files {2,9:N2} MB (uncompressed)" -f 'TOTAL', $zf.Count, ($zb / 1MB)
"{0,-10} {1:N2} MB, {2} entries -> {3}" -f 'ZIP', ($zsize / 1MB), $entries, $Zip
if (-not $Keep) { Remove-Item -Recurse -Force "$Root\build\docs-stage" }
else { "stage kept: $Stage" }
