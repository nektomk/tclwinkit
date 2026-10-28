#!/bin/bash
# build-mingw-ext2.sh - static rl_json, tkdnd, treectrl, itk, mpexpr (MinGW UCRT64)
# Run: MSYSTEM=UCRT64 bash -lc '<repo>/scripts/build-mingw-ext2.sh'
set -e
. "$(dirname "${BASH_SOURCE[0]}")/mingw-env.sh" || exit 1

# --- itclConfig.sh location (built with core) ------------------------------
ITCLCFG=$(find "$TCL/pkgs/itcl4.3.8" -name itclConfig.sh | head -1)
if [ -z "$ITCLCFG" ]; then echo "itclConfig.sh NOT FOUND"; exit 1; fi
ITCLDIR=$(dirname "$ITCLCFG")
echo "itcl config dir: $ITCLDIR"

# --- vendor UUIDs: pin to upstream's own non-VCS value --------------------
# rl_json and itk both derive their version UUID from `git rev-parse HEAD`
# run inside the vendor tree ($(srcdir)). That tree lives inside our
# checkout, so git reports OUR commit -- a hash absent from both upstreams,
# and a different value on every rebuild, i.e. the shipped exe would carry
# builder state. We build from tarballs, which is exactly what upstream's
# fallback branch covers: no git, no svn -> "unknown". Seeding the target
# file makes the prerequisiteless rule a no-op, so no vendor file is edited.
# Measured: byte-stable across runs of the rule, and the stringification
# still joins ("4.2.7+unknown"). Img is NOT seeded -- its manifest.uuid
# (=988) arrives inside the tarball and the rule skips it, which is the
# provenance we want to keep.
for d in rl_json-0.17.8 itk-4.2.7; do
  rm -f "$EXT/$d/manifest.uuid" "$EXT/$d/rl_jsonUuid.h" "$EXT/$d/itkUuid.h"
  printf 'unknown\n' > "$EXT/$d/manifest.uuid"
  echo "uuid seed: $d -> $(cat "$EXT/$d/manifest.uuid")"
done

echo "=== rl_json 0.17.8 (static, in-tree - Makefile has -Iteabase relative to srcdir) ==="
cd "$EXT/rl_json-0.17.8"
rm -f *.o teabase/*.o lib*.a 2>/dev/null || true
# LIBS: teabase.m4 uses AC_LINK_IFELSE for Tcl_GetBytesFromObj/Tcl_GetNumberFromObj;
# with stubs-only link they look missing and conflicting polyfills get enabled.
# Linking the probe against the real static libtcl90.a detects them correctly.
# CPPFLAGS: probe must see Tcl 9 headers, not MSYS2 system tcl.h from /ucrt64/include.
./configure --disable-shared --with-tcl="$TCL/win" \
  CPPFLAGS="-I$TCL/generic -I$TCL/win" \
  LIBS="-L$TCL/win -ltcl90" \
  > "$LOGS/rl_json-mingw.log" 2>&1
# default 'all' target also builds docs (needs pandoc) - tolerate doc failure,
# the static libs are built before the doc target runs
make >> "$LOGS/rl_json-mingw.log" 2>&1 || true
if [ ! -f libtcl9rl_json0178.a ]; then
  echo "RL_JSON STATIC LIB MISSING"; tail -20 "$LOGS/rl_json-mingw.log"; exit 1
fi
echo "rl_json libs: $(ls -la lib*.a | awk '{print $9, $5}' | tr '\n' '; ')"

echo "=== tkdnd 2.9.5 (static) ==="
cd "$EXT/tkdnd-2.9.5"
rm -rf bld && mkdir bld && cd bld
../configure --disable-shared --with-tcl="$TCL/win" --with-tk="$TK/win" \
  > "$LOGS/tkdnd-mingw.log" 2>&1
make >> "$LOGS/tkdnd-mingw.log" 2>&1

echo "=== treectrl 2.5.1 (static) ==="
cd "$EXT/tktreectrl-2.5.1"
rm -rf bld && mkdir bld && cd bld
../configure --disable-shared --with-tcl="$TCL/win" --with-tk="$TK/win" \
  > "$LOGS/treectrl-mingw.log" 2>&1
make >> "$LOGS/treectrl-mingw.log" 2>&1

echo "=== itk 4.2.7 (static) ==="
cd "$EXT/itk-4.2.7"
rm -rf bld && mkdir bld && cd bld
../configure --disable-shared --with-tcl="$TCL/win" --with-tk="$TK/win" \
  --with-itcl="$ITCLDIR" \
  > "$LOGS/itk-mingw.log" 2>&1
make >> "$LOGS/itk-mingw.log" 2>&1

echo "=== mpexpr (custom gcc build) ==="
cd "$EXT/mpexpr"
mkdir -p bld-mingw
# -fpermissive: K&R-era code calls static functions before definition
# (GCC 14+ treats implicit declarations as errors by default)
CFLAGS="-O2 -std=gnu17 -fpermissive -DNDEBUG -DSTATIC_BUILD -DUSE_TCL_STUBS -DTCL_THREADS=1 \
 -I$TCL/generic -I$TCL/win -I$EXT/mpexpr/generic -I$EXT/mpexpr/win"
rm -f bld-mingw/*.o bld-mingw/libmpexpr.a
fail=0
for f in generic/*.c; do
  if ! gcc $CFLAGS -c "$f" -o "bld-mingw/$(basename ${f%.c}).o" >> "$LOGS/mpexpr-mingw.log" 2>&1; then
    echo "MPEXPR COMPILE FAILED: $f"; fail=1
  fi
done
[ $fail -eq 1 ] && exit 1
ar rcs bld-mingw/libmpexpr.a bld-mingw/*.o
echo "mpexpr lib: $(ls -la bld-mingw/libmpexpr.a | awk '{print $5}') bytes"

echo "=== MINGW EXT2 OK ==="
