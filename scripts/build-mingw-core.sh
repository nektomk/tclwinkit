#!/usr/bin/env bash
# Static MinGW-w64 (UCRT64) build of Tcl 9.0.4 + Tk 9.0.4 + bundled pkgs.
# Run under MSYS2: MSYSTEM=UCRT64 bash /c/src/winkit/scripts/build-mingw-core.sh
set -uo pipefail
ROOT=/c/src/winkit/build/mingw
LOGS=$ROOT/logs
mkdir -p "$LOGS"

echo "=== Tcl (configure, static) ==="
cd "$ROOT/tcl9.0.4/win" || exit 1
if [ ! -f Makefile ]; then
  ./configure --disable-shared > "$LOGS/tcl-configure.log" 2>&1 || { echo TCL_CONFIGURE_FAILED; exit 1; }
fi
make -j16 > "$LOGS/tcl-make.log" 2>&1 || { echo TCL_MAKE_FAILED; exit 1; }
echo TCL_OK

echo "=== Tk (configure, static) ==="
cd "$ROOT/tk9.0.4/win" || exit 1
if [ ! -f Makefile ]; then
  ./configure --disable-shared --with-tcl="$ROOT/tcl9.0.4/win" > "$LOGS/tk-configure.log" 2>&1 || { echo TK_CONFIGURE_FAILED; exit 1; }
fi
make -j16 > "$LOGS/tk-make.log" 2>&1 || { echo TK_MAKE_FAILED; exit 1; }
echo TK_OK

TCLCFG="$ROOT/tcl9.0.4/win"
build_pkg () {
  local dir="$1"; shift
  echo "=== pkg: $dir ==="
  cd "$ROOT/tcl9.0.4/pkgs/$dir" || return 1
  if [ ! -f Makefile ]; then
    ./configure --disable-shared --with-tcl="$TCLCFG" "$@" > "$LOGS/$dir-configure.log" 2>&1 || { echo "$dir CONFIGURE FAILED"; return 1; }
  fi
  make -j8 > "$LOGS/$dir-make.log" 2>&1 || { echo "$dir MAKE FAILED"; return 1; }
  echo "$dir OK"
}

TDBCCFG="$ROOT/tcl9.0.4/pkgs/tdbc1.1.13"
build_pkg itcl4.3.8
build_pkg thread3.0.6
build_pkg sqlite3.53.0
build_pkg tdbc1.1.13
build_pkg tdbcsqlite3-1.1.13 --with-tdbc="$TDBCCFG"
build_pkg tdbcodbc1.1.13 --with-tdbc="$TDBCCFG"
echo "=== MINGW CORE BUILD DONE ==="
