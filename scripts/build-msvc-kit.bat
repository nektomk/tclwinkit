@echo off
rem =====================================================================
rem build-msvc-kit.bat - compile & link tclwinkit exes (MSVC, static CRT)
rem Requires: build-msvc-core.bat finished (OPTS=static,nomsvcrt)
rem =====================================================================
setlocal
call "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat" || exit /b 1

set ROOT=C:\src\winkit
set TCLROOT=%ROOT%\build\msvc\tcl9.0.4
set TKROOT=%ROOT%\build\msvc\tk9.0.4
set TCLOUT=%TCLROOT%\win\Release_AMD64_VC1951
set TKOUT=%TKROOT%\win\Release_AMD64_VC1951
set PKGS=%TCLROOT%\pkgs
set KITOUT=%ROOT%\build\msvc\kit
set KITSRC=%ROOT%\src\kit
mkdir %KITOUT% 2>nul

rem ---- compile flags mirroring the core static nomsvcrt build ---------
set KITDEFS=/DSTDC_HEADERS /DUSE_NMAKE=1 /DHAVE_STDINT_H=1 /DHAVE_INTTYPES_H=1 /DHAVE_STDBOOL_H=1 /DTCL_THREADS=1 /DUSE_THREAD_ALLOC=1 /DSTATIC_BUILD /DNDEBUG /DTCL_CFG_OPTIMIZED /DTCL_CFG_DO64BIT /DUNICODE /D_UNICODE
set KITPKGS=/DKIT_HAVE_ITCL /DKIT_HAVE_THREAD /DKIT_HAVE_TDBC /DKIT_HAVE_SQLITE3 /DKIT_HAVE_TDBCODBC
set TCLINC=/I"%TCLROOT%\generic" /I"%TCLROOT%\win"
set TKINC=%TCLINC% /I"%TKROOT%\generic" /I"%TKROOT%\win" /I"%TKROOT%\xlib"
set CFLAGS=/nologo /c /O2 /MT /W3 %KITDEFS% %KITPKGS%

rem ---- optional external packages (uncomment when libs are built) -----
rem set KITPKGS=%KITPKGS% /DKIT_HAVE_TWAPI
rem set KITPKGS=%KITPKGS% /DKIT_HAVE_IMG
rem set KITPKGS=%KITPKGS% /DKIT_HAVE_TCLREADLINE
rem set KITPKGS=%KITPKGS% /DKIT_HAVE_CAWT

rem ---- static libs -----------------------------------------------------
set TCLLIBS="%TCLOUT%\tcl90s.lib" "%TCLOUT%\tclstub.lib" "%TCLOUT%\tcl9registry13s.lib" "%TCLOUT%\tcl9dde14s.lib" "%PKGS%\itcl4.3.8\win\Release_AMD64_VC1951\tcl9itcl438s.lib" "%PKGS%\thread3.0.6\win\Release_AMD64_VC1951\tcl9thread306s.lib" "%PKGS%\tdbc1.1.13\win\Release_AMD64_VC1951\tcl9tdbc1113s.lib" "%PKGS%\sqlite3.53.0\win\Release_AMD64_VC1951\tcl9sqlite3530s.lib" "%PKGS%\tdbcodbc1.1.13\win\Release_AMD64_VC1951\tcl9tdbcodbc1113s.lib"
set TKLIBS="%TKOUT%\tcl9tk90s.lib" "%TKOUT%\tkstub.lib"
set TCSYS=kernel32.lib advapi32.lib netapi32.lib userenv.lib ws2_32.lib odbc32.lib
set TKSYS=%TCSYS% gdi32.lib user32.lib uxtheme.lib comdlg32.lib comctl32.lib imm32.lib shell32.lib uuid.lib winspool.lib ole32.lib oleaut32.lib oleacc.lib
set LFLAGS=-nologo -machine:X64 -release -opt:ref -opt:icf,3 -stack:2300000

rem ---- compile ----------------------------------------------------------
cd /d %KITOUT%
echo === Compiling kit sources ===
cl %CFLAGS% %TCLINC% "%KITSRC%\kit_register.c" /Fo%KITOUT%\kit_register.obj || exit /b 1
cl %CFLAGS% %TCLINC% "%KITSRC%\kit_main.c" /Fo%KITOUT%\kit_main.obj || exit /b 1
cl %CFLAGS% %TKINC% "%KITSRC%\kit_wish_main.c" /Fo%KITOUT%\kit_wish_main.obj || exit /b 1

rem ---- link console kit -------------------------------------------------
echo === Linking tclwinkit-raw.exe (console) ===
link %LFLAGS% -subsystem:console -out:%KITOUT%\tclwinkit-raw.exe %KITOUT%\kit_main.obj %KITOUT%\kit_register.obj %TCLLIBS% %TCSYS% || exit /b 1
if exist "%TCLOUT%\tclsh90s.exe.manifest" mt -nologo -manifest "%TCLOUT%\tclsh90s.exe.manifest" -outputresource:%KITOUT%\tclwinkit-raw.exe;1

rem ---- link GUI kit ------------------------------------------------------
echo === Linking winkitwish-raw.exe (GUI) ===
link %LFLAGS% -subsystem:windows -out:%KITOUT%\winkitwish-raw.exe %KITOUT%\kit_wish_main.obj %KITOUT%\kit_register.obj %TKLIBS% %TCLLIBS% %TKSYS% || exit /b 1
if exist "%TKOUT%\wish.exe.manifest" mt -nologo -manifest "%TKOUT%\wish.exe.manifest" -outputresource:%KITOUT%\winkitwish-raw.exe;1

echo === MSVC KIT EXES BUILT ===
dir /b %KITOUT%\*-raw.exe
endlocal
