#!/bin/bash
# repack-dyncall.sh - dyncall 0.9 makefile on MSYS2 produces empty archives
# (the ar rule loses the object list); objects compile fine, so just
# re-archive them. Manual helper: build-mingw-ext.sh does NOT call it, run it
# between the dyncall build and the twapi build when the archives come out
# empty (see docs/COMPARISON.md).
#
# Paths come from the shared prologue, so this works from any checkout:
#   MSYSTEM=UCRT64 bash -lc '<repo>/scripts/repack-dyncall.sh'
# WINKIT_ROOT overrides the repo root; DCROOT overrides the dyncall dir
# itself, for the case where the tree lives somewhere unusual.
set -e
. "$(dirname "${BASH_SOURCE[0]}")/mingw-env.sh" || exit 1

DC="${DCROOT:-$EXT/dyncall-0.9}"
if [ ! -d "$DC" ]; then
  echo "REPACK ERROR: no dyncall tree at $DC"
  echo "REPACK ERROR: run build-mingw-ext.sh up to the dyncall step first"
  exit 2
fi

cd "$DC"
for d in dyncall dynload dyncallback; do
  cd "$DC/$d"
  n=$(ls *.o 2>/dev/null | wc -l)
  if [ "$n" -eq 0 ]; then echo "NO OBJECTS in $d"; exit 1; fi
  rm -f lib*_s.a
  ar rcs lib${d}_s.a *.o
  echo "$d: $n objects -> lib${d}_s.a $(stat -c %s lib${d}_s.a) bytes"
done
echo "=== dc symbols check ==="
nm "$DC/dyncall/libdyncall_s.a" | grep -c ' T dc'
