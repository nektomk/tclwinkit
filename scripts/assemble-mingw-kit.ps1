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

    # Kit Tcl bootstrap
    Copy-Item "$Root\src\kit\vfs\lib\kit_init.tcl" "$Stage\kit.vfs\lib\"

    # Tcl sides of mixed packages
    New-Item -ItemType Directory -Force "$Stage\kit.vfs\lib\tdbc" | Out-Null
    Copy-Item "$Pkgs\tdbc1.1.13\library\tdbc.tcl"               "$Stage\kit.vfs\lib\tdbc\"
    Copy-Item "$Pkgs\tdbcsqlite3-1.1.13\library\tdbcsqlite3.tcl" "$Stage\kit.vfs\lib\tdbc\"

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

    # tcllib 2.0
    New-Item -ItemType Directory -Force "$Stage\kit.vfs\lib\tcllib2.0" | Out-Null
    Copy-Item -Recurse "$Common\tcllib-2.0\modules\*" "$Stage\kit.vfs\lib\tcllib2.0\"

    if ($WithTk) {
        # tklib 0.9 (GUI only)
        New-Item -ItemType Directory -Force "$Stage\kit.vfs\lib\tklib0.9" | Out-Null
        Copy-Item -Recurse "$Common\tklib-0.9\modules\*" "$Stage\kit.vfs\lib\tklib0.9\"
    }
}

function New-KitZip {
    param([string]$ZipName)
    $zipper = @"
cd [list {$(($Stage -replace '\\','/'))}]
file delete -force [list $ZipName]
zipfs mkzip [list $ZipName] kit.vfs kit.vfs
"@
    Set-Content -Path "$Stage\zipper.tcl" -Value $zipper -Encoding ascii
    Push-Location $Stage
    try {
        & "$TclWin\tclsh90s.exe" "$Stage\zipper.tcl"
        if ($LASTEXITCODE -ne 0) { throw "zipfs mkzip failed for $ZipName" }
    } finally { Pop-Location }
}

# ---- console kit -------------------------------------------------------
New-VfsTree
New-KitZip 'kit-console.zip'
cmd /c copy /b "`"$Kit\tclwinkit-raw.exe`"+`"$Stage\kit-console.zip`" `"$Dist\tclwinkit-mingw.exe`"" | Out-Null
if (-not (Test-Path "$Dist\tclwinkit-mingw.exe")) { throw 'attach failed (console)' }

# ---- GUI kit ------------------------------------------------------------
New-VfsTree -WithTk
New-KitZip 'kit-gui.zip'
cmd /c copy /b "`"$Kit\winkitwish-raw.exe`"+`"$Stage\kit-gui.zip`" `"$Dist\winkitwish-mingw.exe`"" | Out-Null
if (-not (Test-Path "$Dist\winkitwish-mingw.exe")) { throw 'attach failed (gui)' }

Get-ChildItem $Dist\*-mingw.exe | Select-Object Name, @{n='MB';e={[math]::Round($_.Length/1MB,2)}}
Write-Host '=== MINGW KIT ASSEMBLED ==='
