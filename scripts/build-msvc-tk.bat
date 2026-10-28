@echo off
rem =====================================================================
rem build-msvc-tk.bat -- rebuild Tk only, against an already built Tcl.
rem Not a step of the documented chain (build-msvc-core.bat already builds
rem Tk); it exists so a Tk-only edit does not cost a full Tcl rebuild.
rem OPTS matches core: static,nomsvcrt. Building Tk with plain "static"
rem here would link it against the dynamic CRT while Tcl carries none, and
rem the kit would then silently need a CRT DLL.
rem =====================================================================
call "%~dp0msvc-env.bat" || exit /b 1

cd /d %TKROOT%\win
nmake -f makefile.vc release OPTS=static,nomsvcrt TCLDIR=%TCLROOT% > %LOGS%\tk.txt 2>&1
if errorlevel 1 (echo TK BUILD FAILED & exit /b 1)
echo === MSVC TK BUILD OK (nomsvcrt) ===
