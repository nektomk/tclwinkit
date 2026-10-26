@echo off
rem Full static MSVC build (Tcl + bundled pkgs + Tk) with STATIC CRT (nomsvcrt)
call "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat" || exit /b 1
mkdir C:\src\winkit\build\msvc\logs 2>nul
set TCLROOT=C:\src\winkit\build\msvc\tcl9.0.4
set TKROOT=C:\src\winkit\build\msvc\tk9.0.4
set OPTSVAL=static,nomsvcrt

cd /d %TCLROOT%\win
echo === Cleaning Tcl ===
nmake -f makefile.vc clean OPTS=%OPTSVAL% > C:\src\winkit\build\msvc\logs\clean-tcl.txt 2>&1
nmake -f makefile.vc clean-pkgs OPTS=%OPTSVAL% TCLDIR=%TCLROOT% >> C:\src\winkit\build\msvc\logs\clean-tcl.txt 2>&1
echo === Building Tcl (static, nomsvcrt) ===
nmake -f makefile.vc release OPTS=%OPTSVAL% > C:\src\winkit\build\msvc\logs\tcl.txt 2>&1
if errorlevel 1 (echo TCL BUILD FAILED & exit /b 1)

cd /d %TKROOT%\win
echo === Cleaning Tk ===
nmake -f makefile.vc clean OPTS=%OPTSVAL% TCLDIR=%TCLROOT% > C:\src\winkit\build\msvc\logs\clean-tk.txt 2>&1
echo === Building Tk (static, nomsvcrt) ===
nmake -f makefile.vc release OPTS=%OPTSVAL% TCLDIR=%TCLROOT% > C:\src\winkit\build\msvc\logs\tk.txt 2>&1
if errorlevel 1 (echo TK BUILD FAILED & exit /b 1)

echo === MSVC CORE BUILD OK (nomsvcrt) ===
