# Building tclwinkit from source

Builds the four executables and the docs archive on Windows x64. This file is
written so an agent or a person can follow it top to bottom: every step states
its precondition, the command, and the invariant it must leave behind. The
verbose process documentation (conventions, CI, release procedure) is in
[`CONTRIBUTING.md`](CONTRIBUTING.md); the measured environment inventory is in
[`docs/ENVIRONMENT.md`](docs/ENVIRONMENT.md) (Russian).

## What you get

| Output | Toolchain | Subsystem |
|---|---|---|
| `dist\tclwinkit-msvc.exe` | MSVC, static CRT | console |
| `dist\winkitwish-msvc.exe` | MSVC, static CRT | GUI |
| `dist\tclwinkit-mingw.exe` | MinGW-w64, UCRT | console |
| `dist\winkitwish-mingw.exe` | MinGW-w64, UCRT | GUI |
| `dist\tclwinkit-docs-*.zip` | — | docs archive |

`dist/` keeps short names; release assets carry
`tclwinkit-<version>-<toolchain>-x64-<subsystem>.exe`.

## Preconditions

- Windows 10 or newer, x64.
- The repository checked out with **no spaces and no parentheses** in the
  path (Tcl's `makefile.vc` takes `TCLDIR` as a bare nmake macro; this is an
  upstream constraint, not a choice here).
- MSVC: Visual Studio Build Tools with the C++ workload. Located
  automatically via `vswhere`.
- MinGW: MSYS2 with the UCRT64 environment (see step 5 for the exact shell
  invocation).
- PowerShell 5.1+ and `git` on `PATH`.
- Enabling Developer Mode is **not** required; neither are any admin rights.

Nothing in the build is pinned to a checkout location: every script derives
the repo root from its own path (`%~dp0`, `$PSScriptRoot`,
`${BASH_SOURCE[0]}`) and accepts `WINKIT_ROOT` / `-Root` as an override. The
toolchain is discovered too — `vswhere` for MSVC, the `Release_*` name that
`win/rules.vc` computes from `_MSC_VER`, and `gcc -dumpmachine` for MinGW —
so a different VS version or toolset works without edits.

## Step 0 — fetch the vendor archives (required, has a script)

The vendor sources are **not** in this repository: `vendor/` is gitignored
(15 archives, ~68 MB). A fresh clone cannot build anything until they are
fetched.

```
scripts\fetch-vendor.ps1          # 15 archives -> vendor\
```

- Downloads each archive from the URL recorded in
  [`docs/SOURCES.md`](docs/SOURCES.md).
- Verifies **size, SHA-256, and that the bytes read as an archive** before
  letting the file replace anything. The shape check is not ceremony:
  `https://www.dyncall.org/pub/dyncall-0.9.tar.gz` answers HTTP 200 with
  `Content-Type: text/html` and zero bytes, so a status-code-only download
  admits an HTML page into a build tree.
- `-VerifyOnly` re-checks an existing `vendor/` without network access.
- `-UsePins` switches the four movable-branch sources to their commit-pinned
  forms (same files, different bytes — see the SOURCES.md section on it).

**Invariant after step 0:** `vendor/` has 15 archives and
`scripts\fetch-vendor.ps1 -VerifyOnly` exits 0.

## Step 1 — unpack into the build layout (manual, no script)

Unpack `vendor/` into the fixed paths the build expects:

- `build/<chain>/tcl9.0.4`
- `build/<chain>/tk9.0.4`
- `build/<chain>/ext/<top>` for each extension
- `build/common/<name>` for pure-Tcl collections

The archive → directory mapping (including the top-directory renames and the
`itcl4.3.8` / `tk9.0.4` junctions SOURCES.md describes) is in
[`docs/SOURCES.md`](docs/SOURCES.md). No build script touches `vendor/`
itself — unpacking is deliberately manual, so a half-extracted tree cannot be
mistaken for a fetched one.

**Invariant after step 1:** the directories above exist and hold complete
trees; `vendor/` itself is untouched.

## Step 2 — apply vendor patches (manual, no script)

Apply every patch in [`patches/README.md`](patches/README.md) onto the
extracted trees — that table is the index, and an unindexed patch does not
exist. A modified file stays under the original license; the `WINKIT:` marker
is used only in test-logic changes.

**Invariant after step 2:** the tree builds the patched sources; the kit
reports modified versions (e.g. `treectrl 2.5.2` from the `main` branch).

## Step 3 — MSVC chain

Run from an **x64 Native Tools prompt** (or `vcvars64.bat` first), repo root:

```
scripts\build-msvc-core.bat     # Tcl+Tk+pkgs: nmake OPTS=static,nomsvcrt
scripts\build-msvc-ext.bat      # dyncall 0.9 + TWAPI 5.2.0
scripts\build-msvc-img.bat      # Img 2.1.2: base, support, 19 formats
scripts\build-msvc-ext2.bat     # rl_json, mpexpr, itk, tkdnd, treectrl
scripts\build-msvc-kit.bat      # kit glue objects + link the exe
scripts\assemble-msvc-kit.ps1   # stage VFS -> zip -> attach to exe -> dist\
```

`build-msvc-kit.bat` states `Requires: build-msvc-core.bat,
build-msvc-ext.bat, build-msvc-img.bat` and invokes none of them — the steps
above are a sequence, not a retry loop.

**Invariant after step 3:** `dist\tclwinkit-msvc.exe` and
`dist\winkitwish-msvc.exe` exist.

## Step 4 — MinGW chain

The MinGW chain is the same shape in five steps (Img builds inside `ext`, so
there is no separate Img step). It must run inside an **MSYS2 login shell with
`MSYSTEM` set** — without it the MSYS2 profile falls back to the MSYS
toolchain, which has no `gcc`, and `scripts/mingw-env.sh` stops with
`no gcc in PATH` before the first `configure` can die with a cryptic
`no acceptable C compiler found in $PATH`.

From a PowerShell prompt:

```
$env:MSYSTEM = 'UCRT64'
C:\msys64\usr\bin\bash.exe -lc '/c/path/to/winkit/scripts/build-mingw-core.sh'
C:\msys64\usr\bin\bash.exe -lc '/c/path/to/winkit/scripts/build-mingw-ext.sh'
C:\msys64\usr\bin\bash.exe -lc '/c/path/to/winkit/scripts/build-mingw-ext2.sh'
C:\msys64\usr\bin\bash.exe -lc '/c/path/to/winkit/scripts/build-mingw-kit.sh'
scripts\assemble-mingw-kit.ps1
```

One conditional manual helper lives inside that chain: the dyncall makefile
produces **empty** archives under MSYS2 (the `ar` rule loses the object
list). If `build-mingw-ext.sh` finishes and the TWAPI build then fails on
missing objects, re-archive with `scripts\repack-dyncall.sh` and rerun
`build-mingw-ext.sh`'s TWAPI step. `build-mingw-ext.sh` does not call it, by
design. Also: the MinGW chain must run under MSYS2 bash, **not WSL**.

**Invariant after step 4:** `dist\tclwinkit-mingw.exe` and
`dist\winkitwish-mingw.exe` exist.

## Step 5 — licenses and the docs artifact

Once both trees exist under `build/`:

```
scripts\make-licenses.ps1          # regenerate LICENSES/ (must run before packaging)
scripts\build-docs-artifact.ps1    # the fifth asset, from build\msvc|mingw|common
```

- `make-licenses.ps1 -Check` re-verifies the tree against vendor sources
  (content compared with line endings normalised; vendor files that carry a
  UTF-8 BOM are reported, not silently changed).
- `assemble-*.ps1` prune the staged image with `scripts\kit-prune.ps1`:
  `dist/` carries runtime files only. Pruning removes documentation but
  **never** license texts — they stay in the image by filename rule
  (`$KitLicenseNames`), so `tests\kit-license-check.tcl` can read each one out
  of the finished exe.

**Invariant after step 5:** `LICENSES/` is up to date; `dist\` holds five
files including `tclwinkit-docs-*.zip`.

## Step 6 — verify

```
dist\tclwinkit-msvc.exe tests\smoke.tcl              # SMOKE OK
dist\tclwinkit-msvc.exe tests\tcllib-probe.tcl       # PROBE OK
dist\tclwinkit-msvc.exe tests\kit-license-check.tcl  # KIT LICENSE CHECK OK
```

Run all three against **each of the four** executables. Expected numbers on a
healthy build are in CONTRIBUTING.md (_Testing_); the REPL-specific suite is
`scripts\test-repl.ps1`.

## Step 7 — publish (only for maintainers)

```
scripts\publish-release.ps1 -DryRun   # every local step, touches neither GitHub nor refs
scripts\publish-release.ps1           # annotated tag + release + 5 assets + SHA256SUMS.txt
```

The publisher renders `src/docs/release-notes.md` (`{{PLACEHOLDER}}` tokens
substituted from the built artifacts), requires a clean working tree, refuses
to move a tag that a published release already points at, and with `-Force`
replaces same-named assets. Version numbers live in **one** place:
`variable version` in `src/kit/vfs/lib/kit_init.tcl`. To re-issue a release at
a different commit, delete the release and its tag first — that is the only
sanctioned way past the refusal, and only acceptable while downloads are
demonstrably zero.

## Reproducibility

Two full rebuilds on the reference host reproduce all five files byte for
byte: ZIP entry times pinned to the DOS epoch (directory entries included),
`generated:` in `VERSIONS.txt` from `HEAD`/`SOURCE_DATE_EPOCH`, and the PE
timestamp from `-Brepro` (MSVC) or `SOURCE_DATE_EPOCH` (MinGW). No
`Get-Date`, no `__DATE__`/`__TIME__`, no `git rev-parse` output reaches
anything shipped. Reproducibility is measured **per toolchain**: the two
chains differ from each other by design, and a different compiler version is
expected to differ. The mechanisms are in CONTRIBUTING.md (_Reproducibility_).

## Why there is no CI build job

CI runs two jobs (encoding/determinism gates and the vendor-fetch step), and
no build job, because steps 1 and 2 are manual — a build job would have
nothing to compile and would report success on an empty tree.