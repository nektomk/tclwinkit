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
    [string]$Root = 'C:\src\winkit',
    [switch]$Keep
)
$ErrorActionPreference = 'Stop'

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

foreach ($d in @($M, $C, $Src)) {
    if (-not (Test-Path $d)) { throw "missing build tree: $d (run the build scripts first)" }
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
        $txt = [IO.File]::ReadAllText($f.FullName)
        $orig = $txt
        foreach ($k in $IwRepoint.Keys) { $txt = $txt.Replace($k, $IwRepoint[$k]) }
        if ($txt -ne $orig) {
            if ($txt -notmatch 'set ::iwdemo_dir') {
                # define the anchor right after the package requirement
                $txt = [regex]::Replace($txt, '(?m)^(package require Iwidgets[^\n]*)$',
                    "`$1`r`nset ::iwdemo_dir [file dirname [info script]]")
            }
            [IO.File]::WriteAllText($f.FullName, $txt)
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

foreach ($e in $Man) {
    $stats.man += Copy-Set -Src_ $e.s -Dst_ "$D\man\$($e.p)" -Exclude $e.x -OnlyFiles $e.f
}
foreach ($e in $Html) {
    $stats.html += Copy-Set -Src_ $e.s -Dst_ "$D\html\$($e.p)" -Exclude $e.x -OnlyFiles $e.f
}
foreach ($e in $Demos) {
    $stats.demos += Copy-Set -Src_ $e.s -Dst_ "$D\demos\$($e.p)" -Exclude $e.x -OnlyFiles $e.f
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
$probe = "$Root\build\docs-stage\probe-versions.tcl"
Copy-Item "$Src\versions.tcl" $probe -Force
$vers = @("tclwinkit docs $Ver", ("generated: " + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')))
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
Set-Content -Path "$D\VERSIONS.txt" -Value $vers -Encoding UTF8

# --------------------------------------------------------------- MANIFEST ---
$all = @(Get-ChildItem $D -Recurse -File | Sort-Object FullName)
$mf = @("# $Name file manifest ($($all.Count) files)", "")
$mf += $all | ForEach-Object {
    "{0,9}  {1}" -f $_.Length, $_.FullName.Substring($D.Length + 1).Replace('\', '/')
}
Set-Content -Path "$D\MANIFEST.txt" -Value $mf -Encoding UTF8

# ------------------------------------------------------------------- zip ---
# Entry names are built by hand with forward slashes: .NET Framework's
# ZipFile.CreateFromDirectory (what Windows PowerShell 5.1 runs on) writes
# BACKslashes into the archive, which violates the ZIP spec (APPNOTE 4.4.17
# requires '/') and makes Linux/macOS unzip treat the whole tree as one flat
# file name. Same approach as New-KitZip in the assemble scripts.
Add-Type -AssemblyName System.IO.Compression.FileSystem
if (Test-Path $Zip) { Remove-Item $Zip -Force }
$za = [System.IO.Compression.ZipFile]::Open($Zip, 'Create')
try {
    $stageLen = $Stage.Length + 1
    $madeDirs = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($entry in (Get-ChildItem -LiteralPath $Stage -Recurse -File)) {
        $rel = $entry.FullName.Substring($stageLen) -replace '\\', '/'
        $parent = [System.IO.Path]::GetDirectoryName($rel) -replace '\\', '/'
        while ($parent -and $madeDirs.Add($parent)) {
            $null = $za.CreateEntry($parent + '/')
            $parent = [System.IO.Path]::GetDirectoryName($parent) -replace '\\', '/'
        }
        $null = [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $za, $entry.FullName, $rel,
            [System.IO.Compression.CompressionLevel]::Optimal)
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
