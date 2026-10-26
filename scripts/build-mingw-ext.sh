#!/bin/bash
# build-mingw-ext.sh — static dyncall + twapi + Img for MinGW UCRT64.
# Run: MSYSTEM=UCRT64 bash -lc '/c/src/winkit/scripts/build-mingw-ext.sh'
set -e
ROOT=/c/src/winkit
EXT=$ROOT/build/mingw/ext
TCL=$ROOT/build/mingw/tcl9.0.4
TK=$ROOT/build/mingw/tk9.0.4
LOGS=$ROOT/build/mingw/logs
mkdir -p "$LOGS"

echo "=== dyncall 0.9 (gcc, static) ==="
cd "$EXT/dyncall-0.9"
./configure > "$LOGS/dyncall-mingw.log" 2>&1
make -f dynMakefile all >> "$LOGS/dyncall-mingw.log" 2>&1 \
  || make -f Makefile.generic all >> "$LOGS/dyncall-mingw.log" 2>&1
DCL=$(find "$EXT/dyncall-0.9" -name 'libdyncall_s.a' | head -1)
DYLD=$(find "$EXT/dyncall-0.9" -name 'libdynload_s.a' | head -1)
DCB=$(find "$EXT/dyncall-0.9" -name 'libdyncallback_s.a' | head -1)
if [ -z "$DCL" ] || [ -z "$DYLD" ] || [ -z "$DCB" ]; then
  echo "DYNCALL LIBS NOT FOUND"; tail -30 "$LOGS/dyncall-mingw.log"; exit 1
fi
echo "dyncall: $DCL | $DYLD | $DCB"
mkdir -p "$EXT/twapi-5.2.0/dyncall/dyncall-0.9/lib/release_amd64"
cp "$DCL"  "$EXT/twapi-5.2.0/dyncall/dyncall-0.9/lib/release_amd64/libdyncall_s.lib"
cp "$DYLD" "$EXT/twapi-5.2.0/dyncall/dyncall-0.9/lib/release_amd64/libdynload_s.lib"
cp "$DCB"  "$EXT/twapi-5.2.0/dyncall/dyncall-0.9/lib/release_amd64/libdyncallback_s.lib"

echo "=== twapi 5.2.0 (static) ==="
cd "$EXT/twapi-5.2.0"
rm -rf bld && mkdir bld && cd bld
CPPFLAGS="-I$TCL/libtommath" ../configure --enable-threads --disable-shared \
  --with-tcl="$TCL/win" --with-tclinclude="$TCL/generic" \
  > "$LOGS/twapi-mingw.log" 2>&1
make >> "$LOGS/twapi-mingw.log" 2>&1

echo "=== Img 2.1.2 (static, toplevel configure) ==="
cd "$EXT/Img-2.1.2"
rm -rf bld && mkdir bld && cd bld
../configure --disable-shared --with-tcl="$TCL/win" --with-tk="$TK/win" \
  > "$LOGS/img-mingw.log" 2>&1
make >> "$LOGS/img-mingw.log" 2>&1

echo "=== MINGW EXT OK ==="
