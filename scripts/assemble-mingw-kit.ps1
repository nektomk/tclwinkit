# assemble-mingw-kit.ps1 — stage VFS, zip it with zipfs, attach to MinGW kit exes.
# Usage: pwsh -File scripts\assemble-mingw-kit.ps1
param(
    [string]$Root = 'C:\src\winkit'
)
$ErrorActionPreference = 'Stop'

$B      = "$Root\build\mingw"
$TclWin = "$B\tcl9.0.4\win"
$TkWin  = "$B\tk9.0.4\win"
$Pkgs   = "$B\tcl9.0.4\pkgs"
$Ext    = "$B\ext"
$ExtMsvc= "$Root\build\msvc\ext"
$Common = "$Root\build\common"
$Kit    = "$B\kit"
$Stage  = "$Kit\stage"
$Dist   = "$Root\dist"
New-Item -ItemType Directory -Force $Dist | Out-Null

function New-VfsTree {
    param([switch]$WithTk)
    if (Test-Path $Stage) { Remove-Item -Recurse -Force $Stage }
    New-Item -ItemType Directory -Force "$Stage\kit.vfs\lib" | Out-Null

    # Core script libraries (staged by the MinGW make build)
    Copy-Item -Recurse "$TclWin\libtcl.vfs\tcl_library" "$Stage\kit.vfs\tcl_library"
    if ($WithTk) {
        Copy-Item -Recurse "$TkWin\libtk.vfs\tk_library" "$Stage\kit.vfs\tk_library"
    }

    # Kit Tcl bootstrap + physical package index for static/mixed packages
    Copy-Item "$Root\src\kit\vfs\lib\kit_init.tcl" "$Stage\kit.vfs\lib\"
    Copy-Item "$Root\src\kit\vfs\lib\pkgIndex.tcl" "$Stage\kit.vfs\lib\"

    # Tcl sides of mixed packages
    New-Item -ItemType Directory -Force "$Stage\kit.vfs\lib\tdbc" | Out-Null
    Copy-Item "$Pkgs\tdbc1.1.13\library\tdbc.tcl"               "$Stage\kit.vfs\lib\tdbc\"
    Copy-Item "$Pkgs\tdbcsqlite3-1.1.13\library\tdbcsqlite3.tcl" "$Stage\kit.vfs\lib\tdbc\"
    Copy-Item "$Pkgs\tdbcodbc1.1.13\library\tdbcodbc.tcl"        "$Stage\kit.vfs\lib\tdbc\"

    # itcl 4 finds its itcl.tcl at [file dirname $tcl_library]/itcl<ver>/
    New-Item -ItemType Directory -Force "$Stage\kit.vfs\itcl4.3.8" | Out-Null
    Copy-Item "$Pkgs\itcl4.3.8\library\itcl.tcl" "$Stage\kit.vfs\itcl4.3.8\"

    # Thread's ttrace
    New-Item -ItemType Directory -Force "$Stage\kit.vfs\thread_library" | Out-Null
    Copy-Item "$Pkgs\thread3.0.6\lib\ttrace.tcl" "$Stage\kit.vfs\thread_library\"

    # TWAPI: library scripts + static-aware pkgIndex
    # (TEA make may not generate it; fall back to the nmake-generated one —
    #  identical content after @PACKAGE_VERSION@ substitution)
    New-Item -ItemType Directory -Force "$Stage\kit.vfs\lib\twapi" | Out-Null
    Copy-Item "$Ext\twapi-5.2.0\library\*.tcl" "$Stage\kit.vfs\lib\twapi\"
    $twapiIdx = "$Ext\twapi-5.2.0\bld\pkgIndex.tcl"
    if (-not (Test-Path $twapiIdx)) {
        $twapiIdx = "$ExtMsvc\twapi-5.2.0\win\Release_AMD64_VC1951\pkgIndex.tcl"
    }
    Copy-Item $twapiIdx "$Stage\kit.vfs\lib\twapi\"

    # CAWT 3.1.1 (pure Tcl)
    New-Item -ItemType Directory -Force "$Stage\kit.vfs\lib\cawt" | Out-Null
    Copy-Item "$Common\cawt-3.1.1\pkgIndex.tcl" "$Stage\kit.vfs\lib\cawt\"
    Copy-Item "$Common\cawt-3.1.1\cawtapp.tcl"  "$Stage\kit.vfs\lib\cawt\"
    Get-ChildItem "$Common\cawt-3.1.1" -Directory -Filter 'Cawt*' | ForEach-Object {
        Copy-Item -Recurse $_.FullName "$Stage\kit.vfs\lib\cawt\"
    }

    # TclReadLine (pure-Tcl REPL)
    New-Item -ItemType Directory -Force "$Stage\kit.vfs\lib\TclReadLine" | Out-Null
    Copy-Item "$Common\TclReadLine\tclreadline.tcl" "$Stage\kit.vfs\lib\TclReadLine\"
    Copy-Item "$Common\TclReadLine\pkgIndex.tcl"    "$Stage\kit.vfs\lib\TclReadLine\"
    Copy-Item "$Root\src\kit\vfs\lib\TclReadLine\tclreadline-win.tcl" "$Stage\kit.vfs\lib\TclReadLine\"

    # tcllib 2.0
    New-Item -ItemType Directory -Force "$Stage\kit.vfs\lib\tcllib2.0" | Out-Null
    Copy-Item -Recurse "$Common\tcllib-2.0\modules\*" "$Stage\kit.vfs\lib\tcllib2.0\"

    if ($WithTk) {
        # tklib 0.9 (GUI only)
        New-Item -ItemType Directory -Force "$Stage\kit.vfs\lib\tklib0.9" | Out-Null
        Copy-Item -Recurse "$Common\tklib-0.9\modules\*" "$Stage\kit.vfs\lib\tklib0.9\"

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
    # entries (zipfs-compatible; ~100x faster than zipfs mkzip).
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zipPath = "$Stage\$ZipName"
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
    $zip = [System.IO.Compression.ZipFile]::Open($zipPath, 'Create')
    try {
        $root = (Resolve-Path "$Stage\kit.vfs").Path.TrimEnd('\') + '\'
        $dirs = [System.Collections.Generic.HashSet[string]]::new()
        Get-ChildItem -LiteralPath "$Stage\kit.vfs" -Recurse -File | ForEach-Object {
            $rel = $_.FullName.Substring($root.Length) -replace '\\','/'
            $d = [System.IO.Path]::GetDirectoryName($rel) -replace '\\','/'
            while ($d -and $dirs.Add($d)) {
                $null = $zip.CreateEntry($d + '/')
                $d = [System.IO.Path]::GetDirectoryName($d) -replace '\\','/'
            }
            $null = [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $zip, $_.FullName, $rel,
                [System.IO.Compression.CompressionLevel]::Fastest)
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
Join-Binaries @("$Kit\tclwinkit-raw.exe", "$Stage\kit-console.zip") "$Dist\tclwinkit-mingw.exe"
if (-not (Test-Path "$Dist\tclwinkit-mingw.exe")) { throw 'attach failed (console)' }

# ---- GUI kit ------------------------------------------------------------
New-VfsTree -WithTk
New-KitZip 'kit-gui.zip'
Join-Binaries @("$Kit\winkitwish-raw.exe", "$Stage\kit-gui.zip") "$Dist\winkitwish-mingw.exe"
if (-not (Test-Path "$Dist\winkitwish-mingw.exe")) { throw 'attach failed (gui)' }

Get-ChildItem $Dist\*-mingw.exe | Select-Object Name, @{n='MB';e={[math]::Round($_.Length/1MB,2)}}
Write-Host '=== MINGW KIT ASSEMBLED ==='
