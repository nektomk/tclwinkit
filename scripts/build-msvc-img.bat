@echo off
rem =====================================================================
rem build-msvc-img.bat - Img 2.1.2 static libs (MSVC, /MT)
rem Order: base -> zlib -> libjpeg -> libpng -> libtiff -> formats
rem =====================================================================
setlocal
call "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat" || exit /b 1
set ROOT=C:\src\winkit
set TCLROOT=%ROOT%\build\msvc\tcl9.0.4
set TKROOT=%ROOT%\build\msvc\tk9.0.4
set IMG=%ROOT%\build\msvc\ext\Img-2.1.2
set LOGS=%ROOT%\build\msvc\logs
set KOPTS=OPTS=static,nomsvcrt

call :build base          || exit /b 1
call :build zlib          || exit /b 1
call :build libjpeg       || exit /b 1
call :build libpng        || exit /b 1
call :build libtiff       || exit /b 1
for %%f in (bmp dted flir gif ico jpeg pcx pixmap png ppm ps raw sgi sun tga tiff window xbm xpm) do call :build %%f || exit /b 1

echo === IMG BUILD OK ===
endlocal
exit /b 0

:build
echo === Img pkg: %~1 ===
cd /d %IMG%\%~1\win
nmake -f makefile.vc TCLDIR=%TCLROOT% TKDIR=%TKROOT% %KOPTS% > %LOGS%\img-%~1.txt 2>&1
if errorlevel 1 (
  echo IMG BUILD FAILED: %~1
  exit /b 1
)
exit /b 0
