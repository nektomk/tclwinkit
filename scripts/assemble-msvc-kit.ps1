# assemble-msvc-kit.ps1 — stage VFS, zip it with zipfs, attach to kit exes.
# Usage: pwsh -File scripts\assemble-msvc-kit.ps1
param(
    [string]$Root = 'C:\src\winkit'
)
$ErrorActionPreference = 'Stop'

$TclOut = "$Root\build\msvc\tcl9.0.4\win\Release_AMD64_VC1951"
$TkOut  = "$Root\build\msvc\tk9.0.4\win\Release_AMD64_VC1951"
$Pkgs   = "$Root\build\msvc\tcl9.0.4\pkgs"
$Ext    = "$Root\build\msvc\ext"
$Common = "$Root\build\common"
$Kit    = "$Root\build\msvc\kit"
$Stage  = "$Kit\stage"
$Dist   = "$Root\dist"
New-Item -ItemType Directory -Force $Dist | Out-Null

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

    # Kit Tcl bootstrap
    Copy-Item "$Root\src\kit\vfs\lib\kit_init.tcl" "$Stage\kit.vfs\lib\"

    # Tcl sides of mixed packages (C parts are linked into the exe)
    New-Item -ItemType Directory -Force "$Stage\kit.vfs\lib\tdbc" | Out-Null
    Copy-Item "$Pkgs\tdbc1.1.13\library\tdbc.tcl"               "$Stage\kit.vfs\lib\tdbc\"
    Copy-Item "$Pkgs\tdbcsqlite3-1.1.13\library\tdbcsqlite3.tcl" "$Stage\kit.vfs\lib\tdbc\"

    # itcl 4 finds its itcl.tcl at [file dirname $tcl_library]/itcl<ver>/
    New-Item -ItemType Directory -Force "$Stage\kit.vfs\itcl4.3.8" | Out-Null
    Copy-Item "$Pkgs\itcl4.3.8\library\itcl.tcl" "$Stage\kit.vfs\itcl4.3.8\"

    # Thread's ttrace at the path its pkgIndex supports for zipfs kits
    New-Item -ItemType Directory -Force "$Stage\kit.vfs\thread_library" | Out-Null
    Copy-Item "$Pkgs\thread3.0.6\lib\ttrace.tcl" "$Stage\kit.vfs\thread_library\"

    # TWAPI: vendor library scripts + static-aware generated pkgIndex.tcl
    # (falls back to `load {} Twapi` — matches the static registration)
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

    # tcllib 2.0 module tree (every module dir carries its pkgIndex.tcl)
    New-Item -ItemType Directory -Force "$Stage\kit.vfs\lib\tcllib2.0" | Out-Null
    Copy-Item -Recurse "$Common\tcllib-2.0\modules\*" "$Stage\kit.vfs\lib\tcllib2.0\"

    if ($WithTk) {
        # tklib 0.9 (GUI variant only)
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
        & "$TclOut\tclsh90sx.exe" "$Stage\zipper.tcl"
        if ($LASTEXITCODE -ne 0) { throw "zipfs mkzip failed for $ZipName" }
    } finally { Pop-Location }
}

# ---- console kit -------------------------------------------------------
New-VfsTree
New-KitZip 'kit-console.zip'
cmd /c copy /b "`"$Kit\tclwinkit-raw.exe`"+`"$Stage\kit-console.zip`" `"$Dist\tclwinkit-msvc.exe`"" | Out-Null
if (-not (Test-Path "$Dist\tclwinkit-msvc.exe")) { throw 'attach failed (console)' }

# ---- GUI kit ------------------------------------------------------------
New-VfsTree -WithTk
New-KitZip 'kit-gui.zip'
cmd /c copy /b "`"$Kit\winkitwish-raw.exe`"+`"$Stage\kit-gui.zip`" `"$Dist\winkitwish-msvc.exe`"" | Out-Null
if (-not (Test-Path "$Dist\winkitwish-msvc.exe")) { throw 'attach failed (gui)' }

Get-ChildItem $Dist\*-msvc.exe | Select-Object Name, @{n='MB';e={[math]::Round($_.Length/1MB,2)}}
Write-Host '=== MSVC KIT ASSEMBLED ==='
