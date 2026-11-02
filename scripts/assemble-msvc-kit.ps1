# assemble-msvc-kit.ps1 -- stage VFS, zip it with zipfs, attach to kit exes.
# Usage: pwsh -File scripts\assemble-msvc-kit.ps1
param(
    [string]$Root = ''
)
$ErrorActionPreference = 'Stop'

# $PSScriptRoot is not populated during parameter binding on Windows
# PowerShell 5.1, so the default is resolved in the body, not in param().
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }

# The nmake output dir name embeds the toolset version, so it is discovered
# rather than hardcoded (see scripts\msvc-common.ps1).
. "$Root\scripts\msvc-common.ps1"
$Builddir = Get-MsvcBuilddir -Path "$Root\build\msvc\tcl9.0.4\win"

$TclOut = "$Root\build\msvc\tcl9.0.4\win\$Builddir"
$TkOut  = "$Root\build\msvc\tk9.0.4\win\$Builddir"
$Pkgs   = "$Root\build\msvc\tcl9.0.4\pkgs"
$Ext    = "$Root\build\msvc\ext"
$Common = "$Root\build\common"
$Kit    = "$Root\build\msvc\kit"
$Stage  = "$Kit\stage"
$Dist   = "$Root\dist"
New-Item -ItemType Directory -Force $Dist | Out-Null

# Runtime-only staging rules: strip test suites, manuals, benchmarks and sample
# data out of the tcllib/tklib trees (they are published in the docs artifact).
. "$Root\scripts\kit-prune.ps1"
$PruneStats = @()

function New-VfsTree {
    param([switch]$WithTk)
    if (Test-Path $Stage) { Remove-Item -Recurse -Force $Stage }
    New-Item -ItemType Directory -Force "$Stage\kit.vfs\lib" | Out-Null

    # Core script library (prepared by the nmake build: manifest->pkgIndex, no registry/dde pkgIndex)
    Copy-Item -Recurse "$TclOut\libtcl.vfs\tcl_library" "$Stage\kit.vfs\tcl_library"
    if ($WithTk) {
        # Tk script library (demos already removed by the tk build)
        Copy-Item -Recurse "$TkOut\libtk.vfs\tk_library" "$Stage\kit.vfs\tk_library"
    }

    # Kit Tcl bootstrap + the physical package index for static/mixed
    # packages (child interps discover it via //zipfs:/app on auto_path)
    Copy-Item "$Root\src\kit\vfs\lib\kit_init.tcl" "$Stage\kit.vfs\lib\"
    Copy-Item "$Root\src\kit\vfs\lib\pkgIndex.tcl" "$Stage\kit.vfs\lib\"

    # Tcl sides of mixed packages (C parts are linked into the exe)
    New-Item -ItemType Directory -Force "$Stage\kit.vfs\lib\tdbc" | Out-Null
    Copy-Item "$Pkgs\tdbc1.1.13\library\tdbc.tcl"               "$Stage\kit.vfs\lib\tdbc\"
    Copy-Item "$Pkgs\tdbcsqlite3-1.1.13\library\tdbcsqlite3.tcl" "$Stage\kit.vfs\lib\tdbc\"
    Copy-Item "$Pkgs\tdbcodbc1.1.13\library\tdbcodbc.tcl"        "$Stage\kit.vfs\lib\tdbc\"

    # itcl 4 finds its itcl.tcl at [file dirname $tcl_library]/itcl<ver>/
    New-Item -ItemType Directory -Force "$Stage\kit.vfs\itcl4.3.8" | Out-Null
    Copy-Item "$Pkgs\itcl4.3.8\library\itcl.tcl" "$Stage\kit.vfs\itcl4.3.8\"

    # Thread's ttrace at the path its pkgIndex supports for zipfs kits
    New-Item -ItemType Directory -Force "$Stage\kit.vfs\thread_library" | Out-Null
    Copy-Item "$Pkgs\thread3.0.6\lib\ttrace.tcl" "$Stage\kit.vfs\thread_library\"

    # TWAPI: vendor library scripts + static-aware generated pkgIndex.tcl
    # (falls back to `load {} Twapi` -- matches the static registration)
    New-Item -ItemType Directory -Force "$Stage\kit.vfs\lib\twapi" | Out-Null
    Copy-Item "$Ext\twapi-5.2.0\library\*.tcl" "$Stage\kit.vfs\lib\twapi\"
    Copy-Item "$Ext\twapi-5.2.0\win\Release_AMD64_VC1951\pkgIndex.tcl" "$Stage\kit.vfs\lib\twapi\"

    # CAWT 3.1.1 (pure Tcl on top of twapi::comobj)
    New-Item -ItemType Directory -Force "$Stage\kit.vfs\lib\cawt" | Out-Null
    Copy-Item "$Common\cawt-3.1.1\pkgIndex.tcl" "$Stage\kit.vfs\lib\cawt\"
    Copy-Item "$Common\cawt-3.1.1\cawtapp.tcl"  "$Stage\kit.vfs\lib\cawt\"
    Get-ChildItem "$Common\cawt-3.1.1" -Directory -Filter 'Cawt*' | ForEach-Object {
        Copy-Item -Recurse $_.FullName "$Stage\kit.vfs\lib\cawt\"
    }

    # TclReadLine (pure-Tcl REPL, package TclReadLine 1.1)
    New-Item -ItemType Directory -Force "$Stage\kit.vfs\lib\TclReadLine" | Out-Null
    Copy-Item "$Common\TclReadLine\tclreadline.tcl" "$Stage\kit.vfs\lib\TclReadLine\"
    Copy-Item "$Common\TclReadLine\pkgIndex.tcl"    "$Stage\kit.vfs\lib\TclReadLine\"
    Copy-Item "$Root\src\kit\vfs\lib\TclReadLine\tclreadline-win.tcl" "$Stage\kit.vfs\lib\TclReadLine\"

    # rl_json 0.17.8 - statically linked into the exe (kit_register.c),
    # so pkgIndex.tcl just needs 'load {} Rl_json' (no .lib file in VFS).
    New-Item -ItemType Directory -Force "$Stage\kit.vfs\lib\rl_json0.17.8" | Out-Null
    @'
if {[package vsatisfies [package provide Tcl] 9.0-]} {
    package ifneeded rl_json 0.17.8 [list load {} Rl_json]
} else {
    package ifneeded rl_json 0.17.8 [list load {} Rl_json]
}
'@ | Set-Content "$Stage\kit.vfs\lib\rl_json0.17.8\pkgIndex.tcl" -Encoding UTF8

    # mpexpr 1.2 - statically linked into the exe (kit_register.c),
    # so pkgIndex.tcl just needs 'load {} Mpexpr' (no .lib file in VFS).
    New-Item -ItemType Directory -Force "$Stage\kit.vfs\lib\mpexpr1.2" | Out-Null
    @'
if {[package vsatisfies [package provide Tcl] 9.0]} {
    package ifneeded Mpexpr 1.2 [list load {} Mpexpr]
} else {
    package ifneeded Mpexpr 1.2 [list load {} Mpexpr]
}
'@ | Set-Content "$Stage\kit.vfs\lib\mpexpr1.2\pkgIndex.tcl" -Encoding UTF8

    # tcllib 2.0 module tree (every module dir carries its pkgIndex.tcl)
    New-Item -ItemType Directory -Force "$Stage\kit.vfs\lib\tcllib2.0" | Out-Null
    Copy-Item -Recurse "$Common\tcllib-2.0\modules\*" "$Stage\kit.vfs\lib\tcllib2.0\"
    $script:PruneStats += Remove-KitBloat "$Stage\kit.vfs\lib\tcllib2.0"

    if ($WithTk) {
        # tklib 0.9 (GUI variant only)
        New-Item -ItemType Directory -Force "$Stage\kit.vfs\lib\tklib0.9" | Out-Null
        Copy-Item -Recurse "$Common\tklib-0.9\modules\*" "$Stage\kit.vfs\lib\tklib0.9\"
        $script:PruneStats += Remove-KitBloat "$Stage\kit.vfs\lib\tklib0.9"

        # Itk 4.2.7: Itk_Init finds itk.tcl at [file dirname $tcl_library]/itk4.2.7/
        New-Item -ItemType Directory -Force "$Stage\kit.vfs\itk4.2.7" | Out-Null
        Copy-Item "$Ext\itk-4.2.7\library\*" "$Stage\kit.vfs\itk4.2.7\"

        # Iwidgets 4.1.1 (pure Tcl): iwidgets.tcl generated from the template,
        # widget classes autoload from generic/tclIndex
        New-Item -ItemType Directory -Force "$Stage\kit.vfs\lib\iwidgets4.1.1\generic" | Out-Null
        $iw = [System.IO.File]::ReadAllText("$Common\iwidgets-4.1.1\iwidgets.tcl.in")
        $iw = $iw.Replace('@itcl_VERSION@', '4.3.8').Replace('@PACKAGE_VERSION@', '4.1.1')
        # Tcl 9 rejects `package require Tcl/Tk 8.0` (version conflict);
        # 8.6- means ">= 8.6, including 9.x" and works on both.
        $iw = $iw.Replace('package require Tcl 8.0', 'package require Tcl 8.6-')
        $iw = $iw.Replace('package require Tk 8.0', 'package require Tk 8.6-')
        # Tcl 9 resolves qualified variable names strictly relative to the
        # current namespace (no implicit global fallback): inside
        # `namespace eval ::iwidgets`, $iwidgets::library would look for
        # ::iwidgets::iwidgets::library. Use the `variable`-linked simple name.
        $iw = $iw.Replace('lappend auto_path $iwidgets::library', 'lappend auto_path $library')
        $iw = $iw.Replace('[file join $iwidgets::library $subdir]', '[file join $library $subdir]')
        # Same Tcl 9 strictness: inside the namespace eval, `lappend auto_path`
        # would modify ::iwidgets::auto_path instead of the global one.
        $iw = $iw.Replace('lappend auto_path', 'lappend ::auto_path')
        [System.IO.File]::WriteAllText("$Stage\kit.vfs\lib\iwidgets4.1.1\iwidgets.tcl", $iw)
        Get-ChildItem "$Common\iwidgets-4.1.1\generic" -File | Copy-Item -Destination "$Stage\kit.vfs\lib\iwidgets4.1.1\generic\"
        # Its license.terms must travel with the code: the file says the
        # copyright holder is listed per source file and requires the notice in
        # all copies, and 58 .itk/.itcl files ship without any text otherwise.
        Copy-Item "$Common\iwidgets-4.1.1\license.terms" "$Stage\kit.vfs\lib\iwidgets4.1.1\license.terms"

        # tkdnd 2.9.5: Tcl side (kit_init.tcl wires the static C part)
        New-Item -ItemType Directory -Force "$Stage\kit.vfs\lib\tkdnd2.9.5" | Out-Null
        Copy-Item "$Ext\tkdnd-2.9.5\library\*.tcl" "$Stage\kit.vfs\lib\tkdnd2.9.5\"

        # Treectrl 2.5.2: treectrl.tcl + filelist-bindings.tcl (::treectrl_library)
        New-Item -ItemType Directory -Force "$Stage\kit.vfs\lib\treectrl2.5.2" | Out-Null
        Copy-Item "$Ext\tktreectrl-2.5.1\library\*.tcl" "$Stage\kit.vfs\lib\treectrl2.5.2\"
    } else {
        # Console startup script: tclsh semantics + TclReadLine REPL.
        # The GUI kit intentionally has NO main.tcl (stock wish behaviour).
        Copy-Item "$Root\src\kit\vfs\main.tcl" "$Stage\kit.vfs\"
    }
}

function New-KitZip {
    param([string]$ZipName)
    # Fast pure-.NET zip with forward-slash entry names and directory
    # entries (zipfs-compatible; ~100x faster than zipfs mkzip). Entries go
    # through scripts\zip-entry.ps1 so every timestamp is pinned and the
    # image is byte-identical between runs; Get-SortedFile walks the tree in
    # ordinal path order for the same reason (bare Get-ChildItem order is
    # NTFS-index order, and Sort-Object compares with the current culture).
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    . "$Root\scripts\zip-entry.ps1"
    $zipPath = "$Stage\$ZipName"
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
    $zip = [System.IO.Compression.ZipFile]::Open($zipPath, 'Create')
    try {
        # $vfsRoot, not $root: PowerShell names are case-INsensitive, so assigning
        # $root here silently overwrote the $Root parameter holding the repo path.
        # Latent only today (nothing reads $Root after this line), but the shape is
        # the one that silently reported "0 opened" twice in this repository's history.
        $vfsRoot = (Resolve-Path "$Stage\kit.vfs").Path.TrimEnd('\') + '\'
        $dirs = [System.Collections.Generic.HashSet[string]]::new()
        $files = Get-SortedFile -Path "$Stage\kit.vfs"
        foreach ($f in $files) {
            $rel = $f.FullName.Substring($vfsRoot.Length) -replace '\\','/'
            $d = [System.IO.Path]::GetDirectoryName($rel) -replace '\\','/'
            while ($d -and $dirs.Add($d)) {
                Add-ZipDir -Zip $zip -Name ($d + '/')
                $d = [System.IO.Path]::GetDirectoryName($d) -replace '\\','/'
            }
            Add-ZipFile -Zip $zip -Source $f.FullName -Name $rel -Level ([System.IO.Compression.CompressionLevel]::Fastest)
        }
    } finally { $zip.Dispose() }
}

function Join-Binaries {
    param([string[]]$Parts, [string]$Destination)
    $out = [System.IO.File]::Create($Destination)
    try {
        foreach ($p in $Parts) {
            $in = [System.IO.File]::OpenRead($p)
            try { $in.CopyTo($out) } finally { $in.Dispose() }
        }
    } finally { $out.Dispose() }
}

# ---- console kit -------------------------------------------------------
New-VfsTree
New-KitZip 'kit-console.zip'
Join-Binaries @("$Kit\tclwinkit-raw.exe", "$Stage\kit-console.zip") "$Dist\tclwinkit-msvc.exe"
if (-not (Test-Path "$Dist\tclwinkit-msvc.exe")) { throw 'attach failed (console)' }

# ---- GUI kit ------------------------------------------------------------
New-VfsTree -WithTk
New-KitZip 'kit-gui.zip'
Join-Binaries @("$Kit\winkitwish-raw.exe", "$Stage\kit-gui.zip") "$Dist\winkitwish-msvc.exe"
if (-not (Test-Path "$Dist\winkitwish-msvc.exe")) { throw 'attach failed (gui)' }

Get-ChildItem $Dist\*-msvc.exe | Select-Object Name, @{n='MB';e={[math]::Round($_.Length/1MB,2)}}
if ($PruneStats) {
    '--- kit.vfs prune (runtime-only staging) ---'
    $seen = @{}
    foreach ($s in $PruneStats) {
        $k = Split-Path $s.path -Leaf
        if ($seen.ContainsKey($k)) { continue }   # console pass repeats tcllib
        $seen[$k] = 1
        "{0,-22} {1,5} -> {2,5} files  removed {3,5}  freed {4,6} MB" -f `
            $k, $s.files, $s.kept, $s.removed, $s.freedMB
    }
}
Write-Host '=== MSVC KIT ASSEMBLED ==='

