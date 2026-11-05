@echo off
rem =====================================================================
rem build-msvc-ext2.bat - rl_json, tkdnd, treectrl, itk, mpexpr (MSVC /MT)
rem Requires: build-msvc-core.bat + build-msvc-ext.bat (twapi paths pattern)
rem Paths and the MSVC environment come from msvc-env.bat.
rem Creates the two derived junctions itk's nmakehlp -L search needs (see
rem vendor-layout.json "derived" and docs/SOURCES.md). Nothing else made them:
rem   %EXT%\itcl4.3.8 -> %PKGS%\itcl4.3.8   (itcl has no archive of its own)
rem   %EXT%\tk9.0.4   -> %TKROOT%
rem =====================================================================
setlocal
call "%~dp0msvc-env.bat" || exit /b 1
set KOPTS=OPTS=static,nomsvcrt

rem ---------------------------------------------------------------------
rem Derived junctions, before anything compiles. itk's makefile.vc asks
rem nmakehlp -L for the itcl source directory next to the other ext dirs, and
rem without it dies before the first cl.exe line:
rem   makefile.vc(63) : fatal error U1050: Could not locate ITCL source
rem directory.
rem Both are links, never copies: itcl arrives inside the Tcl tarball and Tk is
rem the core tree, so a copy here would fork sources the build must not fork.
rem ---------------------------------------------------------------------
call :junction "%EXT%\itcl4.3.8" "%PKGS%\itcl4.3.8" || exit /b 1
call :junction "%EXT%\tk9.0.4" "%TKROOT%" || exit /b 1

rem ---------------------------------------------------------------------
rem Vendor UUIDs must not describe this build.
rem
rem rl_json and itk both derive their version UUID from
rem   git rev-parse HEAD
rem run inside the vendor tree. That tree lives inside our checkout, so git
rem reports OUR commit: a hash that exists in neither upstream, and a
rem different value on every rebuild, i.e. the shipped exe would carry
rem builder state. Building from a tarball is exactly the case upstream's
rem own fallback covers (Makefile.in: no git, no svn -> "unknown"), so that
rem is the value we use. Measured: the seeded header is byte-stable across
rem runs of the rule and the stringification still joins ("4.2.7+unknown").
rem
rem rl_json's MSVC makefile has no rule for the header at all (upstream
rem generates it from autoconf), so it is written here. itk does have one,
rem in our patched makefile, but the target is prerequisiteless: nmake skips
rem it when the file is already there, so the stale copy has to go first.
rem ---------------------------------------------------------------------
set RLJ=%EXT%\rl_json-0.17.8
set ITKD=%EXT%\itk-4.2.7
del /q "%RLJ%\generic\rl_jsonUuid.h" "%RLJ%\manifest.uuid" "%ITKD%\manifest.uuid" 2>NUL
> "%RLJ%\generic\rl_jsonUuid.h" (
  echo #define RL_JSON_VERSION_UUID ^\
  echo unknown
)
if not exist "%RLJ%\generic\rl_jsonUuid.h" (echo UUID SEED FAILED: rl_jsonUuid.h & exit /b 1)
if exist "%ITKD%\manifest.uuid" (echo UUID SEED FAILED: itk manifest.uuid survived the delete & exit /b 1)

echo === rl_json 0.17.8 ===
cd /d %EXT%\rl_json-0.17.8\win
nmake /s /f makefile.vc TCLDIR=%TCLROOT% %KOPTS% > %LOGS%\rl_json.txt 2>&1
if errorlevel 1 (echo RL_JSON BUILD FAILED & exit /b 1)

echo === tkdnd 2.9.5 ===
cd /d %EXT%\tkdnd-2.9.5\win
nmake /s /f makefile.vc TCLDIR=%TCLROOT% TKDIR=%TKROOT% %KOPTS% > %LOGS%\tkdnd.txt 2>&1
if errorlevel 1 (echo TKDND BUILD FAILED & exit /b 1)

echo === treectrl 2.5.1 ===
cd /d %EXT%\tktreectrl-2.5.1\win
nmake /s /f makefile.vc TCLDIR=%TCLROOT% TKDIR=%TKROOT% %KOPTS% > %LOGS%\treectrl.txt 2>&1
if errorlevel 1 (echo TRECTRL BUILD FAILED & exit /b 1)

echo === itk 4.2.7 ===
cd /d %EXT%\itk-4.2.7\win
nmake /s /f makefile.vc TCLDIR=%TCLROOT% TKDIR=%TKROOT% %KOPTS% > %LOGS%\itk.txt 2>&1
if errorlevel 1 (echo ITK BUILD FAILED & exit /b 1)

echo === mpexpr (master, v1.2-vc) ===
cd /d %EXT%\mpexpr\win
nmake /s /f makefile.vc TCLDIR=%TCLROOT% %KOPTS% > %LOGS%\mpexpr.txt 2>&1
if errorlevel 1 (echo MPEXPR BUILD FAILED & exit /b 1)

echo === MSVC EXT2 OK ===
endlocal
exit /b 0

rem ---- helpers: create a directory junction idempotently ----------------
rem %~1 = link path, %~2 = target path. Three states are told apart, and only
rem one of them is ever removed:
rem   already a reparse point  kept as it is. `dir /AL` lists reparse points
rem                            and nothing else, so the test does not depend on
rem                            a localized dir output (unlike matching the
rem                            JUNCTION token) and does not need fsutil.
rem   empty plain directory    removed and replaced. This is what a fresh
rem                            unpack leaves at both paths, so refusing here
rem                            would make step 3 unrunnable from scratch.
rem   anything else            an error naming the path. A populated tree is
rem                            never deleted by a build script.
rem The target is checked first, so a missing core build says so here instead
rem of surfacing as U1050 two compiles later.
rem Flat gotos rather than if-blocks: paths reach these commands unquoted-by-
rem design in places, and msvc-env.bat keeps parentheses out of blocks for the
rem same reason.
:junction
if exist "%~2\" goto :junc_target_ok
echo MENV ERROR: junction target missing: "%~2"
echo MENV ERROR: run build-msvc-core.bat first
exit /b 1
:junc_target_ok
dir /AL /B "%~dp1" 2>NUL | findstr /I /L /X "%~nx1" >NUL
if not errorlevel 1 goto :junc_kept
if not exist "%~1\" goto :junc_make
dir /B "%~1" 2>NUL | findstr /R "." >NUL
if not errorlevel 1 goto :junc_occupied
rmdir "%~1"
if exist "%~1\" goto :junc_noremove
:junc_make
mklink /J "%~1" "%~2" >NUL
if errorlevel 1 goto :junc_mkfail
echo === junction made: "%~1"
exit /b 0
:junc_kept
echo === junction kept: "%~1"
exit /b 0
:junc_occupied
echo MENV ERROR: "%~1" is a plain directory and is not empty
echo MENV ERROR: remove it by hand; a populated tree is never deleted here
exit /b 1
:junc_noremove
echo MENV ERROR: cannot remove the empty directory "%~1"
exit /b 1
:junc_mkfail
echo MENV ERROR: mklink /J failed for "%~1"
exit /b 1
