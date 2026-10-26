@echo off
rem Build static Tk 9.0.4 (x64, MSVC) against already-built static Tcl
call "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat" || exit /b 1
cd /d C:\src\winkit\build\msvc\tk9.0.4\win
nmake -f makefile.vc release OPTS=static TCLDIR=C:\src\winkit\build\msvc\tcl9.0.4 > C:\src\winkit\build\msvc\logs\tk.txt 2>&1
if errorlevel 1 (echo TK BUILD FAILED & exit /b 1)
echo === MSVC TK BUILD OK ===
