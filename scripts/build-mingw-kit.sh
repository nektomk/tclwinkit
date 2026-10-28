#!/bin/bash
# build-mingw-kit.sh - compile & link tclwinkit exes (MinGW UCRT64, static).
# Run after build-mingw-core.sh and build-mingw-ext.sh.
# MSYSTEM=UCRT64 bash -lc '<repo>/scripts/build-mingw-kit.sh'
set -e
. "$(dirname "${BASH_SOURCE[0]}")/mingw-env.sh" || exit 1
# windres is only needed here, for the Tk cursor resources
if ! command -v windres >/dev/null 2>&1; then
    echo "MINGW ENV ERROR: windres not found (MSYSTEM=${MSYSTEM:-unset}); needed for kit_wish.rc"
    exit 1
fi
OUT=$B/kit
SRC=$WINKIT_ROOT/src/kit
mkdir -p "$OUT"
cd "$OUT"

DEFS="-DSTATIC_BUILD -DTCL_THREADS=1 -DUSE_THREAD_ALLOC=1 -DUNICODE -D_UNICODE \
 -DHAVE_STDINT_H=1 -DHAVE_INTTYPES_H=1 -DHAVE_STDBOOL_H=1 -DSTDC_HEADERS=1 \
 -DNDEBUG -DTCL_CFG_OPTIMIZED -DTCL_CFG_DO64BIT"
PKGS="-DKIT_HAVE_ITCL -DKIT_HAVE_THREAD -DKIT_HAVE_TDBC -DKIT_HAVE_SQLITE3 -DKIT_HAVE_TDBCODBC -DKIT_HAVE_TWAPI -DKIT_HAVE_RLJSON -DKIT_HAVE_MPEXPR"
GUIS="-DKIT_HAVE_IMG -DKIT_GUI -DKIT_HAVE_ITK -DKIT_HAVE_TKDND -DKIT_HAVE_TREECTRL"
TCLINC="-I$TCL/generic -I$TCL/win -I$TCL/libtommath"
TKINC="$TCLINC -I$TK/generic -I$TK/win -I$TK/xlib"
CFLAGS="-O2 -Wall $DEFS"

# ---- collect archives ---------------------------------------------------
CORELIBS="$TCL/win/libtcl90.a $TCL/win/libtclstub.a"
TKCORELIBS="$TK/win/libtcl9tk90.a $TK/win/libtkstub.a"
# bundled pkgs: static libs from the --disable-shared builds in pkgs/*
# LC_ALL=C: `sort` collates by the locale, and the archive order on the gcc
# line is not arbitrary -- it decides which definition wins for a duplicate
# symbol. Pinning it keeps the link identical on a machine whose locale would
# order '-' and '_' differently.
PKGLIBS=$(ls $TCL/pkgs/*/libtcl9*.a $TCL/pkgs/*/lib*stub*.a 2>/dev/null | LC_ALL=C sort -u | tr '\n' ' ')
# twapi + dyncall
TWAPIOBJ=$(ls "$EXT"/twapi-5.2.0/bld/lib*twapi*.a 2>/dev/null | grep -v '\.dll\.a' | head -1)
if [ -z "$TWAPIOBJ" ]; then echo "TWAPI STATIC LIB NOT FOUND"; exit 1; fi
DCL=$(find "$EXT/dyncall-0.9" -name 'libdyncall_s.a' | head -1)
DYLD=$(find "$EXT/dyncall-0.9" -name 'libdynload_s.a' | head -1)
DCB=$(find "$EXT/dyncall-0.9" -name 'libdyncallback_s.a' | head -1)
TWAPILIBS="$TWAPIOBJ $DCL $DYLD $DCB"
# Img (static archives from the toplevel bld tree)
IMGLIBS=$(find "$EXT/Img-2.1.2/bld" -name 'lib*.a' ! -name '*dll.a' 2>/dev/null | LC_ALL=C sort | tr '\n' ' ')
# ext2: rl_json + mpexpr (console & GUI)
EXT2LIBS="$EXT/rl_json-0.17.8/libtcl9rl_json0178.a $EXT/mpexpr/bld-mingw/libmpexpr.a"
# ext2 GUI-only: itk + tkdnd + treectrl
EXT2GUILIBS="$EXT/itk-4.2.7/bld/libtcl9itk427.a $EXT/tkdnd-2.9.5/bld/libtcl9tkdnd295.a $EXT/tktreectrl-2.5.1/bld/libtcl9treectrl252.a"
for a in $EXT2LIBS $EXT2GUILIBS; do [ -f "$a" ] || { echo "MISSING EXT2 ARCHIVE: $a"; exit 1; }; done

TCSYS="-lnetapi32 -luserenv -lws2_32 -ladvapi32 -lkernel32 -luser32 -lodbc32 \
 -lcfgmgr32 -lcredui -lcrypt32 -lgdi32 -liphlpapi -lmpr -lole32 -loleaut32 -lpdh \
 -lpowrprof -lpsapi -lrpcrt4 -lsecur32 -lsetupapi -lshell32 -lshlwapi -ltdh -luxtheme \
 -luuid -lversion -lwinmm -lwinspool -lwintrust -lwtsapi32"
TKSYS="$TCSYS -limm32 -lcomdlg32 -lcomctl32 -loleacc -luuid"
LDFLAGS="-static -municode -Wl,--stack,2300000"

# ---- pin the PE TimeDateStamp ---------------------------------------------
# ld writes the link wall clock into the image header, so two rebuilds of
# identical sources differ in four bytes (measured on this box: two gcc links
# one second apart produced different sha256 with nothing but the stamp
# differing). binutils honours SOURCE_DATE_EPOCH for PE images, so exporting
# it makes the link reproducible.
#
# 315532800 = 1980-01-01T00:00:00Z, the same constant the VFS zip entries use
# ($ZipEpoch1980 in scripts/zip-entry.ps1), so everything time-stamped inside
# a shipped kit reads the DOS epoch. The MSVC chain has no such knob that
# works (link /TIMESTAMP is accepted and ignored) and uses -Brepro instead,
# so the two toolchains disagree on the stamp value -- as they do on every
# byte -- but each is reproducible on its own.
export SOURCE_DATE_EPOCH=315532800

# ---- compile -------------------------------------------------------------
echo "=== compiling kit sources ==="
gcc -c $CFLAGS $PKGS $TCLINC "$SRC/kit_register.c" -o kit_register_c.o
gcc -c $CFLAGS $PKGS $GUIS $TKINC "$SRC/kit_register.c" -o kit_register_g.o
gcc -c $CFLAGS $PKGS $TCLINC "$SRC/kit_main.c" -o kit_main.o
gcc -c $CFLAGS $PKGS $GUIS $TKINC "$SRC/kit_wish_main.c" -o kit_wish_main.o

# ---- Tk resources for the GUI kit (X11 cursor names, tk icon, dialogs) --
# Tk on Windows resolves -cursor names like "gumby" through
# LoadCursorA(Tk_GetHINSTANCE(), name): those are named CURSOR resources in
# the exe (stock wish gets them via win/rc/wish.rc -> tk_base.rc). Without
# them every X11-style cursor spec fails ("bad cursor spec").
# cwd = Tk's rc dir so the relative cursorNN.cur / tk.ico paths resolve.
echo "=== compiling kit_wish.rc (Tk cursor resources) ==="
( cd "$TK/win/rc" && windres -i "$SRC/kit_wish.rc" -o "$OUT/kit_wish_res.o" \
    -O coff -I "$TK/win/rc" -I "$TK/generic" -I "$TCL/generic" \
    --define STATIC_BUILD=1 )

# ---- link console (archive list doubled to resolve circular deps) ---------
echo "=== linking tclwinkit-raw.exe (console) ==="
gcc $LDFLAGS -o tclwinkit-raw.exe kit_main.o kit_register_c.o \
  $CORELIBS $PKGLIBS $TWAPILIBS $EXT2LIBS $CORELIBS $PKGLIBS $TWAPILIBS $EXT2LIBS $TCSYS

# ---- link GUI --------------------------------------------------------------
# -lstdc++: tkdnd's OleDND.cpp is C++ (linked with gcc, needs the C++ runtime)
echo "=== linking winkitwish-raw.exe (GUI) ==="
gcc $LDFLAGS -mwindows -o winkitwish-raw.exe kit_wish_main.o kit_register_g.o \
  kit_wish_res.o \
  $TKCORELIBS $CORELIBS $PKGLIBS $TWAPILIBS $IMGLIBS $EXT2LIBS $EXT2GUILIBS \
  $TKCORELIBS $CORELIBS $PKGLIBS $TWAPILIBS $IMGLIBS $EXT2LIBS $EXT2GUILIBS $TKSYS -lstdc++

echo "=== MINGW KIT EXES BUILT ==="
ls -la tclwinkit-raw.exe winkitwish-raw.exe
