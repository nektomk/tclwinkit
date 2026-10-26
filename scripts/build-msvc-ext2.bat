@echo off
rem =====================================================================
rem build-msvc-ext2.bat - rl_json, tkdnd, treectrl, itk, mpexpr (MSVC /MT)
rem Requires: build-msvc-core.bat + build-msvc-ext.bat (twapi paths pattern)
rem Junctions needed for itk nmakehlp -L search (created by assemble step):
rem   %EXT%\itcl4.3.8 -> tcl9.0.4\pkgs\itcl4.3.8
rem   %EXT%\tk9.0.4   -> tk9.0.4
rem =====================================================================
setlocal
call "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat" || exit /b 1
set ROOT=C:\src\winkit
set TCLROOT=%ROOT%\build\msvc\tcl9.0.4
set TKROOT=%ROOT%\build\msvc\tk9.0.4
set EXT=%ROOT%\build\msvc\ext
set LOGS=%ROOT%\build\msvc\logs
set KOPTS=OPTS=static,nomsvcrt
mkdir %LOGS% 2>nul

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
