@echo off
rem =====================================================================
rem build-msvc-kit.bat - compile & link tclwinkit exes (MSVC, static CRT)
rem Requires: build-msvc-core.bat, build-msvc-ext.bat, build-msvc-img.bat
rem =====================================================================
setlocal EnableDelayedExpansion
call "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat" || exit /b 1

set ROOT=C:\src\winkit
set TCLROOT=%ROOT%\build\msvc\tcl9.0.4
set TKROOT=%ROOT%\build\msvc\tk9.0.4
set TCLOUT=%TCLROOT%\win\Release_AMD64_VC1951
set TKOUT=%TKROOT%\win\Release_AMD64_VC1951
set PKGS=%TCLROOT%\pkgs
set EXT=%ROOT%\build\msvc\ext
set IMG=%EXT%\Img-2.1.2
set OUTDIR=Release_AMD64_VC1951
set KITOUT=%ROOT%\build\msvc\kit
set KITSRC=%ROOT%\src\kit
mkdir %KITOUT% 2>nul

rem ---- compile flags mirroring the core static nomsvcrt build ---------
set KITDEFS=/DSTDC_HEADERS /DUSE_NMAKE=1 /DHAVE_STDINT_H=1 /DHAVE_INTTYPES_H=1 /DHAVE_STDBOOL_H=1 /DTCL_THREADS=1 /DUSE_THREAD_ALLOC=1 /DSTATIC_BUILD /DNDEBUG /DTCL_CFG_OPTIMIZED /DTCL_CFG_DO64BIT /DUNICODE /D_UNICODE
set KITPKGS=/DKIT_HAVE_ITCL /DKIT_HAVE_THREAD /DKIT_HAVE_TDBC /DKIT_HAVE_SQLITE3 /DKIT_HAVE_TDBCODBC /DKIT_HAVE_TWAPI
set TCLINC=/I"%TCLROOT%\generic" /I"%TCLROOT%\win" /I"%TCLROOT%\libtommath"
set TKINC=%TCLINC% /I"%TKROOT%\generic" /I"%TKROOT%\win" /I"%TKROOT%\xlib"
set CFLAGS=/nologo /c /O2 /MT /W3 %KITDEFS%

rem ---- core static libs (/MT = sx suffix) ------------------------------
set CORELIBS="%TCLOUT%\tcl90sx.lib" "%TCLOUT%\tclstub.lib" "%TCLOUT%\tcl9registry13sx.lib" "%TCLOUT%\tcl9dde14sx.lib"
set TKCORELIBS="%TKOUT%\tcl9tk90sx.lib" "%TKOUT%\tkstub.lib"

rem ---- bundled pkgs: glob *sx.lib + *stub.lib from each package outdir --
set PKGLIBS=
for %%p in (itcl4.3.8 thread3.0.6 tdbc1.1.13 sqlite3.53.0 tdbcodbc1.1.13) do call :addlibs "%PKGS%\%%p\win\%OUTDIR%"
rem ---- twapi ------------------------------------------------------------
set TWAPILIBS=
call :addlibs2 TWAPILIBS "%EXT%\twapi-5.2.0\win\%OUTDIR%"
set TWAPILIBS=%TWAPILIBS% "%EXT%\dyncall-0.9\dyncall\libdyncall_s.lib" "%EXT%\dyncall-0.9\dynload\libdynload_s.lib" "%EXT%\dyncall-0.9\dyncallback\libdyncallback_s.lib"
rem ---- Img (GUI only) ---------------------------------------------------
set IMGLIBS=
for %%p in (base zlib libjpeg libpng libtiff bmp dted flir gif ico jpeg pcx pixmap png ppm ps raw sgi sun tga tiff window xbm xpm) do call :addlibs2 IMGLIBS "%IMG%\%%p\win\%OUTDIR%"

rem ---- system libs -------------------------------------------------------
set TCSYS=kernel32.lib advapi32.lib netapi32.lib userenv.lib ws2_32.lib odbc32.lib cfgmgr32.lib credui.lib crypt32.lib iphlpapi.lib mpr.lib ole32.lib oleaut32.lib pdh.lib powrprof.lib psapi.lib rpcrt4.lib secur32.lib setupapi.lib shell32.lib shlwapi.lib user32.lib uxtheme.lib version.lib winmm.lib winspool.lib wintrust.lib wtsapi32.lib gdi32.lib
set TKSYS=%TCSYS% imm32.lib comdlg32.lib comctl32.lib oleacc.lib uuid.lib
set LFLAGS=-nologo -machine:X64 -release -opt:ref -opt:icf,3 -stack:2300000

rem ---- compile ------------------------------------------------------------
cd /d %KITOUT%
echo === Compiling kit sources ===
rem console flavor of kit_register (no Img: it needs Tk)
cl %CFLAGS% %KITPKGS% %TCLINC% "%KITSRC%\kit_register.c" /Fo%KITOUT%\kit_register_c.obj || exit /b 1
rem GUI flavor (with Img)
cl %CFLAGS% %KITPKGS% /DKIT_HAVE_IMG /DKIT_GUI %TKINC% "%KITSRC%\kit_register.c" /Fo%KITOUT%\kit_register_g.obj || exit /b 1
cl %CFLAGS% %KITPKGS% %TCLINC% "%KITSRC%\kit_main.c" /Fo%KITOUT%\kit_main.obj || exit /b 1
cl %CFLAGS% %KITPKGS% /DKIT_HAVE_IMG /DKIT_GUI %TKINC% "%KITSRC%\kit_wish_main.c" /Fo%KITOUT%\kit_wish_main.obj || exit /b 1

rem ---- link console kit ----------------------------------------------------
echo === Linking tclwinkit-raw.exe (console) ===
link %LFLAGS% -subsystem:console -out:%KITOUT%\tclwinkit-raw.exe %KITOUT%\kit_main.obj %KITOUT%\kit_register_c.obj %CORELIBS% %PKGLIBS% %TWAPILIBS% %TCSYS% || exit /b 1
for %%m in ("%TCLOUT%\tclsh90sx.exe.manifest" "%TCLOUT%\tclsh90s.exe.manifest") do if exist %%m mt -nologo -manifest %%m -outputresource:%KITOUT%\tclwinkit-raw.exe;1

rem ---- link GUI kit ---------------------------------------------------------
echo === Linking winkitwish-raw.exe (GUI) ===
link %LFLAGS% -subsystem:windows -out:%KITOUT%\winkitwish-raw.exe %KITOUT%\kit_wish_main.obj %KITOUT%\kit_register_g.obj %TKCORELIBS% %CORELIBS% %PKGLIBS% %TWAPILIBS% %IMGLIBS% %TKSYS% || exit /b 1
for %%m in ("%TKOUT%\wish90sx.exe.manifest" "%TKOUT%\wish.exe.manifest") do if exist %%m mt -nologo -manifest %%m -outputresource:%KITOUT%\winkitwish-raw.exe;1

echo === MSVC KIT EXES BUILT ===
dir /b %KITOUT%\*-raw.exe
endlocal
exit /b 0

rem ---- helpers: append "*sx.lib" and "*stub.lib" from a build outdir -------
:addlibs
for %%f in ("%~1\*sx.lib") do set PKGLIBS=!PKGLIBS! "%%~ff"
for %%f in ("%~1\*stub.lib") do set PKGLIBS=!PKGLIBS! "%%~ff"
exit /b 0

:addlibs2
for %%f in ("%~2\*sx.lib") do set %~1=!%~1! "%%~ff"
for %%f in ("%~2\*stub.lib") do set %~1=!%~1! "%%~ff"
exit /b 0
