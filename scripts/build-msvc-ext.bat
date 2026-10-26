@echo off
rem =====================================================================
rem build-msvc-ext.bat - dyncall (static CRT) + TWAPI static lib (MSVC)
rem Requires: build-msvc-core.bat finished (OPTS=static,nomsvcrt)
rem =====================================================================
setlocal
call "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat" || exit /b 1
set ROOT=C:\src\winkit
set TCLROOT=%ROOT%\build\msvc\tcl9.0.4
set EXT=%ROOT%\build\msvc\ext
set LOGS=%ROOT%\build\msvc\logs
mkdir %LOGS% 2>nul

echo === dyncall 0.9 (x64 msvc, default /MT) ===
cd /d %EXT%\dyncall-0.9
call configure.bat /target-x64 /tool-msvc /config-release > %LOGS%\dyncall.txt 2>&1
if errorlevel 1 (echo DYNCALL CONFIGURE FAILED & exit /b 1)
nmake /f Nmakefile >> %LOGS%\dyncall.txt 2>&1
if errorlevel 1 (echo DYNCALL BUILD FAILED & exit /b 1)

echo === replacing twapi's prebuilt /MD dyncall libs with our /MT ones ===
copy /y %EXT%\dyncall-0.9\dyncall\libdyncall_s.lib       %EXT%\twapi-5.2.0\dyncall\dyncall-0.9\lib\release_amd64\ || exit /b 1
copy /y %EXT%\dyncall-0.9\dynload\libdynload_s.lib       %EXT%\twapi-5.2.0\dyncall\dyncall-0.9\lib\release_amd64\ || exit /b 1
copy /y %EXT%\dyncall-0.9\dyncallback\libdyncallback_s.lib %EXT%\twapi-5.2.0\dyncall\dyncall-0.9\lib\release_amd64\ || exit /b 1

echo === twapi 5.2.0 static (nomsvcrt) ===
rem tclTomMath.h includes tommath.h which lives in the Tcl libtommath dir
set "INCLUDE=%INCLUDE%;%TCLROOT%\libtommath"
cd /d %EXT%\twapi-5.2.0\win
nmake /s /f makefile.vc TCLDIR=%TCLROOT% OPTS=static,nomsvcrt > %LOGS%\twapi.txt 2>&1
if errorlevel 1 (echo TWAPI BUILD FAILED & exit /b 1)

echo === MSVC EXT OK ===
endlocal
