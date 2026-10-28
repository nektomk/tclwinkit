@echo off
rem =====================================================================
rem build-msvc-ext2.bat - rl_json, tkdnd, treectrl, itk, mpexpr (MSVC /MT)
rem Requires: build-msvc-core.bat + build-msvc-ext.bat (twapi paths pattern)
rem Paths and the MSVC environment come from msvc-env.bat.
rem Junctions needed for itk nmakehlp -L search (created by assemble step):
rem   %EXT%\itcl4.3.8 -> tcl9.0.4\pkgs\itcl4.3.8
rem   %EXT%\tk9.0.4   -> tk9.0.4
rem =====================================================================
setlocal
call "%~dp0msvc-env.bat" || exit /b 1
set KOPTS=OPTS=static,nomsvcrt

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
