#!/bin/bash
# build-mingw-ext.sh - static dyncall + twapi + Img for MinGW UCRT64.
# Run: MSYSTEM=UCRT64 bash -lc '<repo>/scripts/build-mingw-ext.sh'
set -e
. "$(dirname "${BASH_SOURCE[0]}")/mingw-env.sh" || exit 1

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

# --- measure the archives, repair the empty ones, verify the repair ---------
# dynMakefile's `ar -rv lib*_s.a` rule reaches ar with an empty object list
# under MSYS2, so all three archives come out 8 bytes with zero members while
# every .o compiled fine (docs/COMPARISON.md, dyncall). The compile step
# therefore reports success, and the failure surfaces two steps later, at the
# kit link, as a wall of
#   undefined reference to `dcArgChar' / `dcCallInt' / `dcNewCallVM' ...
# which reads like a TWAPI problem and is not one -- TWAPI itself builds, it
# only references the symbols. So measure instead of trusting the exit code:
# count members, repack from the objects already on disk when empty, then
# assert both the member count and the exported dc* symbols. Conditional on
# purpose: where the vendor rule does produce a populated archive its bytes are
# left alone, so this cannot change a toolchain that already works.
dc_members () { ar t "$1" 2>/dev/null | grep -c '\.o$' || true; }
echo "=== dyncall archives as built ==="
dc_need=0
for a in "$DCL" "$DYLD" "$DCB"; do
  n=$(dc_members "$a")
  echo "  $(basename "$a"): $n member(s), $(stat -c%s "$a") bytes"
  if [ "$n" -eq 0 ]; then dc_need=1; fi
done
if [ "$dc_need" -eq 1 ]; then
  echo "  empty archive(s): the vendor ar rule lost its object list; repacking"
  "$(dirname "${BASH_SOURCE[0]}")/repack-dyncall.sh" || { echo "DYNCALL REPACK FAILED"; exit 1; }
  DCL=$(find "$EXT/dyncall-0.9" -name 'libdyncall_s.a' | head -1)
  DYLD=$(find "$EXT/dyncall-0.9" -name 'libdynload_s.a' | head -1)
  DCB=$(find "$EXT/dyncall-0.9" -name 'libdyncallback_s.a' | head -1)
fi
dc_bad=0
for a in "$DCL" "$DYLD" "$DCB"; do
  n=$(dc_members "$a")
  if [ "$n" -eq 0 ]; then echo "DYNCALL ARCHIVE EMPTY AFTER REPACK: $a"; dc_bad=1; fi
done
dc_syms=$(nm "$DCL" 2>/dev/null | grep -c ' T dc' || true)
echo "  verified: $(dc_members "$DCL")+$(dc_members "$DYLD")+$(dc_members "$DCB") members, $dc_syms exported dc* symbols"
if [ "$dc_syms" -eq 0 ]; then echo "DYNCALL EXPORTS NO dc* SYMBOLS"; dc_bad=1; fi
if [ "$dc_bad" -eq 1 ]; then exit 1; fi

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
