#!/bin/bash
# build-mingw-kit.sh — compile & link tclwinkit exes (MinGW UCRT64, static).
# Run after build-mingw-core.sh and build-mingw-ext.sh.
# MSYSTEM=UCRT64 bash -lc '/c/src/winkit/scripts/build-mingw-kit.sh'
set -e
ROOT=/c/src/winkit
B=$ROOT/build/mingw
TCL=$B/tcl9.0.4
TK=$B/tk9.0.4
EXT=$B/ext
OUT=$B/kit
SRC=$ROOT/src/kit
mkdir -p "$OUT"
cd "$OUT"

DEFS="-DSTATIC_BUILD -DTCL_THREADS=1 -DUSE_THREAD_ALLOC=1 -DUNICODE -D_UNICODE \
 -DHAVE_STDINT_H=1 -DHAVE_INTTYPES_H=1 -DHAVE_STDBOOL_H=1 -DSTDC_HEADERS=1 \
 -DNDEBUG -DTCL_CFG_OPTIMIZED -DTCL_CFG_DO64BIT"
PKGS="-DKIT_HAVE_ITCL -DKIT_HAVE_THREAD -DKIT_HAVE_TDBC -DKIT_HAVE_SQLITE3 -DKIT_HAVE_TDBCODBC -DKIT_HAVE_TWAPI"
TCLINC="-I$TCL/generic -I$TCL/win -I$TCL/libtommath"
TKINC="$TCLINC -I$TK/generic -I$TK/win -I$TK/xlib"
CFLAGS="-O2 -Wall $DEFS"

# ---- collect archives ---------------------------------------------------
CORELIBS="$TCL/win/libtcl90.a $TCL/win/libtclstub.a"
TKCORELIBS="$TK/win/libtcl9tk90.a $TK/win/libtkstub.a"
# bundled pkgs: static libs from the --disable-shared builds in pkgs/*
PKGLIBS=$(ls $TCL/pkgs/*/libtcl9*.a $TCL/pkgs/*/lib*stub*.a 2>/dev/null | sort -u | tr '\n' ' ')
# twapi + dyncall
TWAPIOBJ=$(ls "$EXT"/twapi-5.2.0/bld/lib*twapi*.a 2>/dev/null | grep -v '\.dll\.a' | head -1)
if [ -z "$TWAPIOBJ" ]; then echo "TWAPI STATIC LIB NOT FOUND"; exit 1; fi
DCL=$(find "$EXT/dyncall-0.9" -name 'libdyncall_s.a' | head -1)
DYLD=$(find "$EXT/dyncall-0.9" -name 'libdynload_s.a' | head -1)
DCB=$(find "$EXT/dyncall-0.9" -name 'libdyncallback_s.a' | head -1)
TWAPILIBS="$TWAPIOBJ $DCL $DYLD $DCB"
# Img (static archives from the toplevel bld tree)
IMGLIBS=$(find "$EXT/Img-2.1.2/bld" -name 'lib*.a' ! -name '*dll.a' 2>/dev/null | sort | tr '\n' ' ')

TCSYS="-lnetapi32 -luserenv -lws2_32 -ladvapi32 -lkernel32 -luser32 -lodbc32 \
 -lcfgmgr32 -lcredui -lcrypt32 -lgdi32 -liphlpapi -lmpr -lole32 -loleaut32 -lpdh \
 -lpowrprof -lpsapi -lrpcrt4 -lsecur32 -lsetupapi -lshell32 -lshlwapi -ltdh -luxtheme \
 -luuid -lversion -lwinmm -lwinspool -lwintrust -lwtsapi32"
TKSYS="$TCSYS -limm32 -lcomdlg32 -lcomctl32 -loleacc -luuid"
LDFLAGS="-static -municode -Wl,--stack,2300000"

# ---- compile -------------------------------------------------------------
echo "=== compiling kit sources ==="
gcc -c $CFLAGS $PKGS $TCLINC "$SRC/kit_register.c" -o kit_register_c.o
gcc -c $CFLAGS $PKGS -DKIT_HAVE_IMG -DKIT_GUI $TKINC "$SRC/kit_register.c" -o kit_register_g.o
gcc -c $CFLAGS $PKGS $TCLINC "$SRC/kit_main.c" -o kit_main.o
gcc -c $CFLAGS $PKGS -DKIT_HAVE_IMG -DKIT_GUI $TKINC "$SRC/kit_wish_main.c" -o kit_wish_main.o

# ---- link console (archive list doubled to resolve circular deps) ---------
echo "=== linking tclwinkit-raw.exe (console) ==="
gcc $LDFLAGS -o tclwinkit-raw.exe kit_main.o kit_register_c.o \
  $CORELIBS $PKGLIBS $TWAPILIBS $CORELIBS $PKGLIBS $TWAPILIBS $TCSYS

# ---- link GUI --------------------------------------------------------------
echo "=== linking winkitwish-raw.exe (GUI) ==="
gcc $LDFLAGS -mwindows -o winkitwish-raw.exe kit_wish_main.o kit_register_g.o \
  $TKCORELIBS $CORELIBS $PKGLIBS $TWAPILIBS $IMGLIBS \
  $TKCORELIBS $CORELIBS $PKGLIBS $TWAPILIBS $IMGLIBS $TKSYS

echo "=== MINGW KIT EXES BUILT ==="
ls -la tclwinkit-raw.exe winkitwish-raw.exe
