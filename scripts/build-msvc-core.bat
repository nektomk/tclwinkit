@echo off
rem =====================================================================
rem build-msvc-core.bat -- Tcl + bundled pkgs + Tk, static, STATIC CRT
rem (nomsvcrt: not one CRT DLL in the result). This is step 1 of the
rem chain; paths and the MSVC environment come from msvc-env.bat.
rem =====================================================================
call "%~dp0msvc-env.bat" || exit /b 1
set OPTSVAL=static,nomsvcrt

cd /d %TCLROOT%\win
echo === Cleaning Tcl ===
nmake -f makefile.vc clean OPTS=%OPTSVAL% > %LOGS%\clean-tcl.txt 2>&1
nmake -f makefile.vc clean-pkgs OPTS=%OPTSVAL% TCLDIR=%TCLROOT% >> %LOGS%\clean-tcl.txt 2>&1
echo === Building Tcl (static, nomsvcrt) ===
nmake -f makefile.vc release OPTS=%OPTSVAL% > %LOGS%\tcl.txt 2>&1
if errorlevel 1 (echo TCL BUILD FAILED & exit /b 1)

cd /d %TKROOT%\win
echo === Cleaning Tk ===
nmake -f makefile.vc clean OPTS=%OPTSVAL% TCLDIR=%TCLROOT% > %LOGS%\clean-tk.txt 2>&1
echo === Building Tk (static, nomsvcrt) ===
nmake -f makefile.vc release OPTS=%OPTSVAL% TCLDIR=%TCLROOT% > %LOGS%\tk.txt 2>&1
if errorlevel 1 (echo TK BUILD FAILED & exit /b 1)

echo === MSVC CORE BUILD OK (nomsvcrt) ===
