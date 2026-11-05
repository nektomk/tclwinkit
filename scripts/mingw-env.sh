# mingw-env.sh -- shared prologue for the build-mingw-*.sh chain.
#
# Sourced by build-mingw-core.sh / -ext.sh / -ext2.sh / -kit.sh:
#     . "$(dirname "${BASH_SOURCE[0]}")/mingw-env.sh"
#
# Every path below is derived from this file's own location, so the chain
# runs from any checkout directory. Override with WINKIT_ROOT when the build
# tree is deliberately outside the source tree.
#
# Must be MSYS2 bash (UCRT64), not WSL: /c/... drive paths, cygpath and the
# mingw64-ucrt x86_64 toolchain all come from MSYS2. Run it as
#     MSYSTEM=UCRT64 bash -lc '<repo>/scripts/build-mingw-core.sh'
#
# Defines: WINKIT_ROOT B TCL TK EXT LOGS and leaves the shell in the repo
# root. Returns 2 instead of exiting, so a sourced failure does not kill an
# interactive shell.

if [ -n "${BASH_SOURCE[0]:-}" ]; then
    _winkit_me="${BASH_SOURCE[0]}"
else
    _winkit_me="$0"
fi
case "$_winkit_me" in
    /*) ;;
    *) _winkit_me="$PWD/$_winkit_me" ;;
esac
_winkit_dir="${_winkit_me%/*}"
# Normalize a Windows-style path to the POSIX form this script uses.
if command -v cygpath >/dev/null 2>&1; then
    _winkit_dir="$(cygpath -u "$_winkit_dir")"
fi
WINKIT_ROOT="${WINKIT_ROOT:-$(cd "$_winkit_dir/.." && pwd -P)}"
unset _winkit_me _winkit_dir

# Quote and space sensitive: the paths below reach configure and gcc as bare
# words, so a metacharacter in the root breaks the build in ways that look
# like a compiler bug.
case "$WINKIT_ROOT" in
    *' '*|*'$'*|*'&'*|*'('*|*')'*|*"'"*|*'*'*|*'['*|*']'*)
        echo "MINGW ENV ERROR: repo path contains shell metacharacters: $WINKIT_ROOT"
        echo "MINGW ENV ERROR: use a plain path such as /c/src/winkit"
        return 2
        ;;
esac
if [ ! -f "$WINKIT_ROOT/src/kit/kit_main.c" ]; then
    echo "MINGW ENV ERROR: not a tclwinkit repo root: $WINKIT_ROOT"
    echo "MINGW ENV ERROR: set WINKIT_ROOT to the checkout and retry"
    return 2
fi

# ---- host tool: zip -----------------------------------------------------
# Not optional, and easy to miss when provisioning a new machine: Tcl's and
# Tk's zipfs targets shell out to a `zip` program. configure prefers one found
# on PATH and falls back to building its own minizip -- but Tk 9.0.4's
# win/Makefile.in defines MINIZIP_OBJS without ever giving it a rule, so the
# fallback dies with "No rule to make target 'minizip', needed by
# libtk9.0.4.zip" (Tcl's Makefile.in does carry the rule, which is why Tcl
# builds either way and only Tk fails). Fail here, naming the remedy.
if ! command -v zip >/dev/null 2>&1; then
    echo "MINGW ENV ERROR: no zip in PATH (MSYS2 package msys/zip)"
    echo "MINGW ENV ERROR: install it with: pacman -S zip"
    echo "MINGW ENV ERROR: without it Tk's zipfs target fails in make, not configure"
    return 2
fi

# ---- toolchain guard ----------------------------------------------------
# Measured on this machine: with MSYSTEM unset, /etc/profile falls back to
# MSYSTEM=MSYS, whose PATH has no /ucrt64/bin, so gcc is absent and every
# configure dies with "no acceptable C compiler found in $PATH" -- after
# configure has already run, far from the cause and looking like a vendor
# bug. Fail here instead, naming the remedy.
if ! command -v gcc >/dev/null 2>&1; then
    echo "MINGW ENV ERROR: no gcc in PATH (MSYSTEM=${MSYSTEM:-unset})"
    echo "MINGW ENV ERROR: run as:  MSYSTEM=UCRT64 bash -lc '<repo>/scripts/build-mingw-core.sh'"
    echo "MINGW ENV ERROR: or start the UCRT64 shell from the MSYS2 launcher first"
    return 2
fi
_wk_host="$(gcc -dumpmachine 2>/dev/null)"
if [ "$_wk_host" != "x86_64-w64-mingw32" ]; then
    echo "MINGW ENV ERROR: gcc targets '$_wk_host', expected x86_64-w64-mingw32 (UCRT64)"
    echo "MINGW ENV ERROR: an MSYS-toolchain compiler produces a cygwin-dependent exe, not a static kit"
    return 2
fi
unset _wk_host
for _wk_tool in make ar sed; do
    if ! command -v "$_wk_tool" >/dev/null 2>&1; then
        echo "MINGW ENV ERROR: $_wk_tool not found in PATH (MSYSTEM=${MSYSTEM:-unset})"
        return 2
    fi
done
unset _wk_tool

B="$WINKIT_ROOT/build/mingw"
TCL="$B/tcl9.0.4"
TK="$B/tk9.0.4"
EXT="$B/ext"
LOGS="$B/logs"
mkdir -p "$LOGS"
cd "$WINKIT_ROOT" || return 2
echo "=== root: $WINKIT_ROOT"
return 0
