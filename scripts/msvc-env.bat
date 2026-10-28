@echo off
rem =====================================================================
rem msvc-env.bat -- shared prologue for the build-msvc-*.bat chain.
rem
rem Usage from a build-msvc-*.bat:
rem     call "%~dp0msvc-env.bat"            rem core / ext / ext2 / img
rem     call "%~dp0msvc-env.bat" needoutdir rem kit, which links TCLOUT/TKOUT
rem
rem No setlocal of its own on purpose: it defines variables in the CALLER
rem scope. It needs no EnableDelayedExpansion either -- every path with
rem parentheses in it is kept out of if/for blocks, which is why the
rem vswhere and dir results go through files under %LOGS%.
rem
rem Overrides, all optional, set them before calling:
rem   WINKIT_ROOT      repo root; default is the parent of this file
rem   WINKIT_VSVARS    full path of vcvars64.bat; default found by vswhere
rem   WINKIT_VSWHERE   full path of vswhere.exe
rem   WINKIT_BUILDDIR  nmake output dir name; default discovered, see below
rem
rem Sets: ROOT TCLROOT TKROOT EXT LOGS PKGS KITOUT BUILDDIR TCLOUT TKOUT
rem
rem Constraint: the repo path must contain no parentheses and no spaces.
rem Tcl's makefile.vc takes TCLDIR and friends as bare nmake macros, which
rem cannot be quoted, so such a root fails inside nmake regardless of
rem anything done here.
rem =====================================================================

if not defined WINKIT_ROOT for %%i in ("%~dp0..") do set "WINKIT_ROOT=%%~fi"
set "ROOT=%WINKIT_ROOT%"
if exist "%ROOT%\src\kit\kit_main.c" goto :root_ok
echo MENV ERROR: not a tclwinkit repo root: "%ROOT%"
echo MENV ERROR: set WINKIT_ROOT to the checkout and retry
exit /b 1
:root_ok
set "TCLROOT=%ROOT%\build\msvc\tcl9.0.4"
set "TKROOT=%ROOT%\build\msvc\tk9.0.4"
set "EXT=%ROOT%\build\msvc\ext"
set "LOGS=%ROOT%\build\msvc\logs"
set "PKGS=%TCLROOT%\pkgs"
set "KITOUT=%ROOT%\build\msvc\kit"
mkdir "%LOGS%" 2>nul

rem ---- MSVC environment, located by vswhere, not by a hardcoded version ----
if defined WINKIT_VSVARS goto :vcvars_have
rem ProgramFiles(x86) is expanded with % at top level: the variable NAME
rem contains parentheses, which cmd reads as a block start inside an if.
set "VSWHERE_DEF=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not defined WINKIT_VSWHERE set "WINKIT_VSWHERE=%VSWHERE_DEF%"
if exist "%WINKIT_VSWHERE%" goto :vsw_where
echo MENV ERROR: vswhere not found: "%WINKIT_VSWHERE%"
echo MENV ERROR: set WINKIT_VSVARS to the full path of vcvars64.bat
exit /b 1
:vsw_where
set "VSLIST=%LOGS%\vswhere.txt"
"%WINKIT_VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath > "%VSLIST%" 2>nul
set "VSDIR="
for /f "usebackq delims=" %%i in ("%VSLIST%") do set "VSDIR=%%i"
if defined VSDIR goto :vsdir_have
echo MENV ERROR: vswhere reported no MSVC with the x64 C++ toolset
echo MENV ERROR: set WINKIT_VSVARS to the full path of vcvars64.bat
exit /b 1
:vsdir_have
set "WINKIT_VSVARS=%VSDIR%\VC\Auxiliary\Build\vcvars64.bat"
:vcvars_have
if exist "%WINKIT_VSVARS%" goto :vcvars_ok
echo MENV ERROR: vcvars64.bat not found: "%WINKIT_VSVARS%"
exit /b 1
:vcvars_ok
call "%WINKIT_VSVARS%" >nul
if not errorlevel 1 goto :vcvars_ran
echo MENV ERROR: vcvars64.bat failed: "%WINKIT_VSVARS%"
exit /b 1
:vcvars_ran
echo === env: %WINKIT_VSVARS%

rem ---- nmake output directory name -----------------------------------------
rem win/rules.vc builds the name as Release_^<arch^>_VC^<VCVER^> and computes
rem VCVER from _MSC_VER, so it differs per toolset: VC1951 is only what this
rem machine happens to have. Ask the tree instead of guessing -- take the
rem highest such name on disk (/o-n sorts names descending, first wins).
if defined WINKIT_BUILDDIR goto :bld_have
set "BLDLIST=%LOGS%\builddir.txt"
dir /b /ad /o-n "%TCLROOT%\win\Release_*" > "%BLDLIST%" 2>nul
set "WINKIT_BUILDDIR="
for /f "usebackq delims=" %%d in ("%BLDLIST%") do if not defined WINKIT_BUILDDIR set "WINKIT_BUILDDIR=%%d"
:bld_have
if defined WINKIT_BUILDDIR goto :bld_ok
set "BUILDDIR="
set "TCLOUT="
set "TKOUT="
rem Core, ext, ext2 and img builds do not need it; only the kit link does.
if not "%~1"=="needoutdir" exit /b 0
echo MENV ERROR: no Release_* dir under "%TCLROOT%\win"
echo MENV ERROR: run build-msvc-core.bat first, or set WINKIT_BUILDDIR
exit /b 1
:bld_ok
set "BUILDDIR=%WINKIT_BUILDDIR%"
set "TCLOUT=%TCLROOT%\win\%WINKIT_BUILDDIR%"
set "TKOUT=%TKROOT%\win\%WINKIT_BUILDDIR%"
echo === bld: %BUILDDIR%
exit /b 0
