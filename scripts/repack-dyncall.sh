#!/bin/bash
# repack-dyncall.sh — dyncall 0.9 makefile on MSYS2 produces empty archives
# (ar rule loses the object list); objects compile fine, so just re-archive.
set -e
cd /c/src/winkit/build/mingw/ext/dyncall-0.9
for d in dyncall dynload dyncallback; do
  cd /c/src/winkit/build/mingw/ext/dyncall-0.9/$d
  n=$(ls *.o 2>/dev/null | wc -l)
  if [ "$n" -eq 0 ]; then echo "NO OBJECTS in $d"; exit 1; fi
  rm -f lib*_s.a
  ar rcs lib${d}_s.a *.o
  echo "$d: $n objects -> lib${d}_s.a $(stat -c %s lib${d}_s.a) bytes"
done
echo "=== dc symbols check ==="
nm /c/src/winkit/build/mingw/ext/dyncall-0.9/dyncall/libdyncall_s.a | grep -c ' T dc'
