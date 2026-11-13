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
| `dist\msvc\tclwin.exe` | MSVC, static CRT | console |
| `dist\msvc\tkwin.exe` | MSVC, static CRT | GUI |
| `dist\mingw\tclwin.exe` | MinGW-w64, UCRT | console |
| `dist\mingw\tkwin.exe` | MinGW-w64, UCRT | GUI |
| `dist\tclwinkit-docs-*.zip` | — | docs archive |

The exe names carry no toolchain, so `dist/` keeps one subdirectory per
toolchain; the docs archive stays at the `dist/` root. Release assets carry
`tclwinkit-<version>-<toolchain>-x64-<subsystem>.exe`.

## Preconditions

- Windows 10 or newer, x64.
- The repository checked out with **no spaces and no parentheses** in the
  path (Tcl's `makefile.vc` takes `TCLDIR` as a bare nmake macro; this is an
  upstream constraint, not a choice here).
- MSVC: Visual Studio Build Tools with the C++ workload. Located
  automatically via `vswhere`.
- MinGW: MSYS2 with the UCRT64 environment (see step 4 for the exact shell
  invocation), **plus the `zip` package** — `pacman -S zip`. Tcl's and Tk's
  zipfs targets shell out to a `zip` program; with none on `PATH`, `configure`
  falls back to building its own minizip, and Tk 9.0.4's `win/Makefile.in`
  declares `MINIZIP_OBJS` with no rule for it — so Tcl builds, prints `TCL_OK`,
  and Tk then dies in `make` with `No rule to make target 'minizip', needed by
  libtk9.0.4.zip`, two stages away from the cause. `scripts/mingw-env.sh`
  checks for `zip` before the first `configure` and names the remedy.
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

## Step 1 — unpack into the build layout (scripted)

```
scripts\unpack-vendor.ps1
```

Expands `vendor/` into the fixed paths the build expects:

- `build/<chain>/tcl9.0.4`
- `build/<chain>/tk9.0.4`
- `build/<chain>/ext/<top>` for each extension
- `build/common/<name>` for pure-Tcl collections

The archive → directory mapping is data in `scripts/vendor-layout.json`
(including the top-directory renames and the `itcl4.3.8` / `tk9.0.4` junctions
SOURCES.md describes); the same table in
[`docs/SOURCES.md`](docs/SOURCES.md) is the human-facing view. The script
refuses to unpack anything `fetch-vendor.ps1 -VerifyOnly` has not verified,
extracts through a scratch directory so a half-extracted tree cannot be
mistaken for a complete one, and marks each tree with
`.winkit-unpacked.json` (component, archive, SHA-256) — `-VerifyOnly` re-checks
the marks, `-Force` replaces a tree that exists, `-Chain`/`-Only` narrow the
plan. No build script touches `vendor/` itself.

**Invariant after step 1:** the directories above exist, are marked, and hold
complete trees; `vendor/` itself is untouched. `scripts\unpack-vendor.ps1
-VerifyOnly` exits 0.

## Step 2 — apply vendor patches (scripted)

```
scripts\apply-patches.ps1
```

Turns the pristine trees of step 1 into the trees the kit builds from. What is
changed, and why, is data in [`patches/patches.json`](patches/patches.json) — 24
entries over five components, each declaring its operations (EOL normalization,
an asserted whole-word identifier rename, a unified diff, a file rename) and the
SHA-256 of both the pristine and the final file. The 22 `*.patch` files next to
it are derived, not authored: `scripts\make-patches.ps1` recomputes their bytes
and both hashes from two trees, and `-Check` fails a manifest that drifted from
the sources. [`patches/README.md`](patches/README.md) is the human index.

The script refuses to patch a tree `unpack-vendor.ps1 -VerifyOnly` has not
accepted, and requires every file it touches to be either pristine or already
final. Everything is staged in a throwaway directory outside every repository
and nothing reaches a tree until the whole run has produced zero failures, so a
refusal cannot leave a half-patched tree — the one state a later run could not
tell apart from a hand edit. `-VerifyOnly` re-checks the marks and the bytes,
`-DryRun` announces a plan, `-Force` re-applies over a patched tree,
`-Chain`/`-Only` narrow the plan. Line endings are a declared operation
(`canon.eol = lf`), not diff bytes: applying drops 163 CR bytes, all of them from
upstream `itk/win/makefile.vc`.

Three things that alter a build stay outside the manifest on purpose, because
they are properties of the build rather than of the vendor source — the dyncall
`.lib` substitution, the `rl_jsonUuid.h`/`manifest.uuid` seeding, and the two
derived junctions under `build/msvc/ext`. All three are indexed at the end of
[`patches/README.md`](patches/README.md) and measured in
[`docs/SOURCES.md`](docs/SOURCES.md).

**Invariant: dyncall 0.9 is tied to TWAPI 5.2.0.** The version is dictated by the
path hardcoded in TWAPI 5.2.0 (`win/makefile.vc:37` `DYNCALLDIR=$(ROOT)\dyncall\dyncall-0.9`,
`:124` `PRJ_LIBS = libdyncall_s.lib libdynload_s.lib libdyncallback_s.lib`; `configure.ac:93,267-269`
and `configure:5011,8127-8132` `-I"${srcdir}/dyncall/dyncall-0.9/include"`, `win/ffi.c:10`
`#include "dyncall.h"`). TWAPI 5.2.0 ships only 4 headers and 6 prebuilt `.lib`s — no dyncall
sources. Substituting a 1.x tree into `dyncall-0.9` compiles TWAPI against 0.9 headers but links
1.x objects (silent ABI mismatch). Upgrading dyncall requires upgrading TWAPI > 5.2, where dyncall
is absent from master (GitHub API 404; latest release = v5.2).

**Invariant after step 2:** `scripts\apply-patches.ps1 -VerifyOnly` exits 0; the
tree builds the patched sources; the kit reports modified versions (e.g.
`treectrl 2.5.2` from the `main` branch).

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

**Invariant after step 3:** `dist\msvc\tclwin.exe` and
`dist\msvc\tkwin.exe` exist.

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

The chain repairs one known vendor defect itself. dyncall's `dynMakefile`
builds its archives with an `ar -rv` rule that reaches `ar` with an empty
object list under MSYS2, so all three come out 8 bytes with zero members while
every object file compiled fine. That step still exits 0: the failure appears
two steps later, at the kit link, as `undefined reference to dcArgChar` and
friends — which reads like a TWAPI problem and is not one, since TWAPI builds
and merely references the symbols. `build-mingw-ext.sh` therefore counts the
members of each archive, calls `scripts\repack-dyncall.sh` when any is empty,
and then asserts both the member count and the exported `dc*` symbols before
anything is allowed to link against them. The repair is conditional on purpose:
where the vendor rule does produce a populated archive, its bytes are left
alone. Also: the MinGW chain must run under MSYS2 bash, **not WSL**.

**Invariant after step 4:** `dist\mingw\tclwin.exe` and
`dist\mingw\tkwin.exe` exist.

## Step 5 — licenses and the docs artifact

Once both trees exist under `build/`:

```
scripts\make-licenses.ps1            # regenerate LICENSES/ (must run before packaging)
scripts\build-docs-artifact.ps1      # the docs archive, from build\msvc|mingw|common
scripts\build-release-archives.ps1   # one exe archive per toolchain -> build\release-stage\
```

- `make-licenses.ps1 -Check` re-verifies the tree against vendor sources
  (content compared with line endings normalised; vendor files that carry a
  UTF-8 BOM are reported, not silently changed).
- `assemble-*.ps1` prune the staged image with `scripts\kit-prune.ps1`:
  `dist/` carries runtime files only. Pruning removes documentation but
  **never** license texts — they stay in the image by filename rule
  (`$KitLicenseNames`), so `tests\kit-license-check.tcl` can read each one out
  of the finished exe.
- **The docs artifact names the commit it was built from.** Its `VERSIONS.txt`
  carries `generated: <committer date of HEAD> (commit <sha>)`, both derived
  from git rather than from a wall clock, so the archive is reproducible *at a
  given commit* and legitimately differs at any other one. Build it **after the
  last commit** you intend to ship: built mid-work it records a stale sha, and
  built on a dirty tree it says so in the same line. The four executables carry
  no builder state at all (`check-encoding.ps1` asserts zero occurrences of
  `HEAD` in each), so re-assembling them for a fresh stamp is unnecessary —
  measured across a rebuild: all four byte-identical, only the docs archive
  changed.
- `build-docs-artifact.ps1` removes a previous version's
  `dist\tclwinkit-docs-*.zip` once the new archive is written **and verified**,
  so a version bump cannot leave two of them side by side; `-KeepStale` opts
  out. Two archives are not a cosmetic problem: `verify-docs-artifact.ps1`
  refuses to run unless exactly one matches.
- **The two exe archives are what actually ships.** `build-release-archives.ps1`
  packs `dist\<chain>\*.exe` into `build\release-stage\tclwinkit-<chain>-<version>.zip`,
  each with a single top-level directory named after the archive, so unpacking
  both into one folder cannot silently overwrite one toolchain with the other and
  the download folder still says which toolchain and version a file came from.
  Entries go through `zip-entry.ps1` (pinned DOS epoch, ordinal order), so the
  archives are byte-identical across rebuilds. The script reads each archive back
  and asserts entry names, pinned timestamps, the single top-level directory and
  per-file byte identity with `dist\` before accepting it; it packs only
  allowlisted exe names and refuses to run on a missing or unexpected file, so an
  interrupted build cannot be published under an authoritative-looking checksum.
  A previous version's archives are removed only after the new ones verify
  (`-KeepStale` opts out), and every removal is printed.
- **`SHA256SUMS.txt` goes stale on every rebuild.** It lives in
  `build\release-stage\` and lists the *published* asset names, so no build
  script renders it — `publish-release.ps1` does, in its step 2. Re-render it
  with `publish-release.ps1 -DryRun`, which touches neither GitHub nor any ref
  and does its rendering **before** the clean-tree check, so it also works
  mid-change. Without that, `check-encoding.ps1 -RequireArtifacts` (and with it
  `check-gates-selftest.ps1`) fails with `listed hashes matching no built file`
  plus `built files absent from the list`.

**Invariant after step 5:** `LICENSES/` is up to date; `dist\` holds five
files — four exe under `dist\msvc\` and `dist\mingw\`, plus
`tclwinkit-docs-*.zip` at the `dist\` root — and `build\release-stage\` holds
the two `tclwinkit-<chain>-<version>.zip` archives that actually ship.
`build\release-stage\SHA256SUMS.txt` matches those three archives, so
`scripts\check-encoding.ps1 -RequireArtifacts` exits 0.

## Step 6 — verify

```
dist\msvc\tclwin.exe tests\smoke.tcl              # SMOKE OK
dist\msvc\tclwin.exe tests\tcllib-probe.tcl       # PROBE OK
dist\msvc\tclwin.exe tests\kit-license-check.tcl  # KIT LICENSE CHECK OK
```

Run all three against **each of the four** executables. Expected numbers on a
healthy build are in CONTRIBUTING.md (_Testing_); the REPL-specific suite is
`scripts\test-repl.ps1`.

## Step 7 — publish (only for maintainers)

```
scripts\build-release-archives.ps1    # pack dist\<chain>\*.exe into the two shipped archives
scripts\publish-release.ps1 -DryRun   # every local step, touches neither GitHub nor refs
scripts\publish-release.ps1           # annotated tag + release + 4 assets:
                                      #   tclwinkit-{msvc,mingw}-<ver>.zip,
                                      #   tclwinkit-docs-<ver>.zip, SHA256SUMS.txt
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

Two full rebuilds on the reference host reproduce every shipped byte for byte:
the five files in `dist\` (four exe plus the docs archive) and the two release
archives packed from them. What makes that hold: ZIP entry times pinned to the
DOS epoch (directory entries included — in the kit images, the docs archive and
the release archives alike), `generated:` in `VERSIONS.txt` from `HEAD` and
`SOURCE_DATE_EPOCH`, and the PE timestamp from `-Brepro` (MSVC) or
`SOURCE_DATE_EPOCH` (MinGW). No `Get-Date`, no `__DATE__`/`__TIME__`, no
`git rev-parse` output reaches anything shipped. Reproducibility is measured
**per toolchain**: the two chains differ from each other by design, and a
different compiler version is expected to differ. The mechanisms are in
CONTRIBUTING.md (_Reproducibility_).

## Why there is no CI build job

CI runs two jobs (encoding/determinism gates and the vendor-fetch step), and no
build job. Steps 0–2 are no longer the reason: they are scripted, so
`fetch-vendor` → `unpack-vendor` → `apply-patches` → `-VerifyOnly` is a chain CI
could execute today on the `sources` job, which already has all 15 archives.

The reason is the compilers. The MSVC chain needs an x64 Native Tools prompt and
the MinGW chain an MSYS2 login shell with `MSYSTEM` set — without it the MSYS2
profile falls back to the MSYS toolchain, which has no `gcc` — and a build job
that ran only one of the two would prove less than the local rule does, because
the kit is defined as the pair: a change is not done until it builds on both.
`SOURCE_DATE_EPOCH` and `-Brepro` make the artifacts reproducible **per
toolchain**, so the missing piece is not determinism but a second toolchain in
CI and the wall clock to run both.

What CI can gain without either is the patch half of the chain, and that is the
next candidate: `unpack-vendor.ps1 -DryRun` on the `encoding` job (it needs no
`vendor/`), and `apply-patches.ps1` plus `make-patches.ps1 -Check` on `sources`.
`-Check` takes a `-PristineRoot` as well as the patched tree, so that leg needs
two unpacked copies and the disk to hold them — a design constraint, not a
one-liner, which is why it is not wired up yet.