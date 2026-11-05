# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The version number lives in exactly one place: `variable version` in
[`src/kit/vfs/lib/kit_init.tcl`](src/kit/vfs/lib/kit_init.tcl). Every
release ships five artifacts — four executables (MSVC and MinGW-w64, console
and GUI) plus the documentation archive — and a `SHA256SUMS.txt`.

## [0.2] — 2026-11-05

24 commits since `v0.1`. **No bundled component changed version** — the kit is
the same Tcl 9.0.4 / Tk 9.0.4 and the same 20 packages, and the gates report the
same numbers as 0.1 (`smoke` OK on all four executables; `tcllib-probe`
439 offered / 384 loaded / 55 known-upstream / **0 NEW** for the console kits
and 571 / 508 / 63 / **0 NEW** for the GUI kits; `kit-license-check`
0 failures). What changed is how the kit behaves on a messy or hostile host,
and how it is built.

### Changed

- **The kit no longer inherits anything from an externally installed Tcl.**
  `tcl_library` is pinned to `//zipfs:/app/tcl_library` and `TCL_LIBRARY` is
  removed from the process environment block *before* any interpreter is
  created, so the main interpreter, the second interpreter that
  `Tk_CreateConsoleWindow` makes for the GUI console, and every slave
  interpreter (`interp create`) all resolve the library inside the attached
  image. Previously the GUI kit did read an external one: each new interpreter
  re-reads `$env` from the OS block rather than from the parent, and `[tclInit]`
  checks `env(TCL_LIBRARY)` before the zipfs mount, so a valid external
  `init.tcl` won even with `tcl_library` pinned. Measured with a trap copy of
  `init.tcl` carrying a marker: the marker no longer appears from any of the
  four interpreter kinds, and `info library` reports the VFS in each.
- **The REPL neither reads nor writes the user's home directory.** TclReadLine
  no longer executes `~/.tcllinerc`, no longer reads or appends
  `~/.tclline_history`, and its `package require Expect` block is commented out —
  that `package require` could read a `pkgIndex.tcl` from the untrusted
  environment. The `tcl_rcFileName` hooks are gone from both mains as well
  (`~/winkitrc.tcl` for the console kit, `~/winkitwishrc.tcl` for the GUI one),
  so the kit behaves identically on a read-only volume and next to a hostile
  `$HOME`. The READMEs always claimed this; it is now true, and it is what
  makes "nothing is written next to the exe" checkable.
- **A clean-machine rebuild has now been performed** — the item 0.1 listed as
  not yet done. After an OS reinstall the whole chain ran from scratch: fetch,
  unpack, patch, both compilers, both assembles, the docs artifact, and every
  gate green, including the 87-assertion negative-control suite. Byte-for-byte
  equality with the reference host is still not claimed (the two toolchains
  differ by design); the versions here are MSVC 14.51.36231 and gcc 16.2.0,
  so a rebuild is expected to differ from both 0.1 and this one.

### Fixed

- **`build-msvc-ext2.bat` creates the two derived junctions itself**
  (`build\msvc\ext\itcl4.3.8` → the itcl that arrives inside the Tcl tarball,
  `build\msvc\ext\tk9.0.4` → the Tk core tree). `vendor-layout.json` and
  `CONTRIBUTING.md` both said the script made them, but only a comment existed,
  so a checkout nobody had built by hand died in itk with
  `fatal error U1050: Could not locate ITCL source directory` — and a re-unpack
  leaves both paths as empty directories, which is what a fresh machine has.
  The helper is idempotent, tells an existing junction from an empty directory,
  and never deletes a populated tree.
- **The MinGW chain now states its `zip` requirement instead of failing
  obscurely.** Tcl and Tk shell out to a `zip` program for their zipfs targets;
  with none on `PATH`, configure falls back to building its own minizip, and
  Tk 9.0.4's `win/Makefile.in` declares `MINIZIP_OBJS` without a rule for it.
  Measured: Tcl printed `TCL_OK` and Tk died in make with
  `No rule to make target 'minizip', needed by libtk9.0.4.zip`. `mingw-env.sh`
  checks for `zip` up front and names the remedy (`pacman -S zip`).
- **No import libraries inside the attached image**: rl_json and mpexpr
  packaging was putting `.lib` files into `kit.vfs`, where nothing can load
  them and where they only cost bytes.
- **The docs archive no longer ships a dead link.** `THIRD-PARTY-NOTICES.md`
  is part of the archive and pointed at `BUILDING.md`, which is not;
  `verify-docs-artifact` now reports 60 archive-relative links resolved, 4
  repository-only by design, 0 dead. The archive's own `README.md` had also
  grown into a 216-line duplicate of the repository documentation and is now
  28 lines: what the archive is, where the attribution lives, and how to open a
  man page or a demo.

### Added

- **Steps 0–2 of the build are scripted and machine-readable.** A vendor layout
  map (`scripts/vendor-layout.json`) drives `unpack-vendor.ps1`, which marks
  every tree it writes (`.winkit-unpacked.json` with the component, archive and
  SHA-256), re-checks them with `-VerifyOnly`, and can attest a hand-unpacked
  tree with `-Adopt`. Vendor patches became real diffs with a verifying
  applier: `patches/patches.json` (25 entries over 6 components — 23 unified
  diffs, 1 file rename, 1 asserted identifier rename — each declaring the
  SHA-256 of both the pristine and the final bytes) plus the 23 derived
  `.patch` files, applied all-or-nothing by `apply-patches.ps1` and
  re-derivable from two trees by `make-patches.ps1 -Check`. 25 control
  snapshots were dropped in favour of the diffs; line endings became a declared
  operation rather than diff bytes.
- **`docs/BUILDING.md`**: the build as an ordered sequence of steps, each
  stating its precondition, its command and the invariant it must leave behind,
  written so a person or an agent can follow it top to bottom. It also records
  why dyncall is pinned at 0.9 (TWAPI 5.2.0 hardcodes that path and ships no
  dyncall sources, so a 1.x tree there would compile against 0.9 headers and
  link 1.x objects).
- **CI is split in two**: `encoding.yml` runs the cheap gates on every push,
  `sources.yml` runs the expensive vendor legs only when one of its inputs
  changed, with the 15 archives cached on the manifest bytes.

### Known limitations

- Unchanged from 0.1: TWAPI is still partial (its own suite reports 380
  failures of 3494 on the reference host), Tk's and the full tcllib/tklib
  suites are still not run in full, `tdbc::mysql` and `tdbc::postgres` are
  still absent, and `__FILE__` strings reachable from panic messages still
  carry build-machine paths. That last one was announced for "the next
  release" in 0.1 and did **not** land here; it remains open.

## [0.1] — 2026-10-27

First release. [Tag `v0.1`](https://github.com/nektomk/tclwinkit/releases/tag/v0.1).

### Added

- **Portable single-file Tcl 9.0.4 distribution for Windows x64.** The
  interpreter plus statically linked binary extensions, with the pure-Tcl
  libraries attached to the exe as a ZIP archive mounted through the
  built-in `zipfs` at `//zipfs:/app`. No DLLs beside the exe, no installer,
  no registry writes, no dependency outside system Windows DLLs.
- **Two independent toolchains for one kit**: MSVC 19.51 with a static CRT
  (`OPTS=static,nomsvcrt` — not one CRT DLL) and MinGW-w64 GCC 16.1 with
  `-static` plus UCRT forwarders. Both build all four executables from the
  same source tree and carry the same version.
- **Console kit as a drop-in `tclsh`** (same argument semantics, stdin mode
  and exit codes) with an added interactive REPL: line editing, history,
  emacs bindings, Shift-Tab completion, implemented in pure Tcl
  (TclReadLine 1.1) over a Win32 shim on TWAPI.
- **GUI kit as a drop-in `wish`** with the Tk console widget, and a tray
  icon path through `twapi::systemtray` in place of the unmaintained
  `winico` package.
- **Bundled components** (full attribution in
  [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md)): Tcl 9.0.4, Tk 9.0.4,
  registry 1.3.7, dde 1.4.6, Itcl 4.3.8, Itk 4.2.7, Iwidgets 4.1.1,
  Thread 3.0.6, tdbc 1.1.13, sqlite3 3.53.0, tdbc::sqlite3 1.1.13,
  tdbc::odbc 1.1.13, TWAPI 5.2.0 with dyncall 0.9, Img 2.1.2 (19 formats,
  including zlib 1.3.2, png 1.6.58, jpeg 10.0.0, tiff 4.7.2), rl_json
  0.17.8, mpexpr 1.2, tkdnd 2.9.5, Treectrl 2.5.2, tcllib 2.0, tklib 0.9,
  CAWT 3.1.1, TclReadLine 1.1.
- **Documentation archive as the fifth artifact**
  (`tclwinkit-docs-0.1.zip`, 13.57 MB, 3129 entries): `man/` (584 nroff
  pages across 14 packages), `html/` (1473), `demos/` (519), `docs/` (47),
  `tools/` (`man.tcl`, a groff-free man renderer, and the iwidgets demo
  launcher), `LICENSES/` (54 files), `LICENSE`, `THIRD-PARTY-NOTICES.md`,
  `VERSIONS.txt`, `MANIFEST.txt`. The kits deliberately carry runtime files
  only; everything pruned is published in this archive instead.
- **License machinery**: [`LICENSE`](LICENSE) (MIT) for the glue,
  [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md) as the attribution
  authority, [`LICENSES/`](LICENSES/) generated end to end by
  `scripts/make-licenses.ps1` with a CI-ready `-Check` mode that re-verifies
  the tree against vendor sources, and `tests/kit-license-check.tcl`, which
  reads every mandatory text out of the finished exe's mounted image and
  checks the phrases that specific license requires.
- **Vendor patch set** in [`patches/`](patches/README.md), indexed per file
  with the reason for each change: Tcl 9 removals (`case`,
  `trace variable`) in Iwidgets runtime, legacy Tk 9 / Windows test
  expectations, `rl_json` clang-only attribute and MSVC `mkstemp`/SEH
  `finally` collisions, `mpexpr` Tcl 8.x legacy macros and the
  `Tcl_Backslash` shim, itk and tktreectrl makefile fixes, tkdnd build
  plumbing.
- **Regression gates** (`tests/smoke.tcl`, `tests/tcllib-probe.tcl`,
  `tests/kit-license-check.tcl`, `scripts/test-repl.ps1`) run against the
  shipped executables rather than a build tree. On this release: SMOKE OK
  ×4, PROBE OK ×4 (console 439 offered / 384 loaded / 55 known-upstream
  failures / 0 new; GUI 571 / 508 / 63 / 0 new), KIT LICENSE CHECK OK ×4.
- **Reproducible builds within a toolchain**: two full rebuilds on the same
  host produce byte-identical assets — all five files in `dist/` matched
  across a complete `ext2 → kit → assemble → docs` double pass (verified
  2026-10-28). Three sources of nondeterminism were eliminated: ZIP entry
  timestamps (pinned to the 1980-01-01 DOS epoch, directory entries
  included), the `generated:` stamp in `VERSIONS.txt` (now the committer date
  of `HEAD`, or `SOURCE_DATE_EPOCH`, with a `dirty working tree` marker), and
  the PE `TimeDateStamp` the linker writes from the wall clock (MSVC
  `-Brepro`, MinGW `SOURCE_DATE_EPOCH`). Vendor version UUIDs no longer
  inherit the builder's git commit either: `rl_json` and `itk` derive theirs
  from `git rev-parse HEAD` inside a tree that lives inside this checkout, so
  the shipped executables used to carry — and expose through
  `rl_json::build-info commit` and `itk::build-info commit` — a hash of this
  repository; both now report `unknown`, which is what upstream's own
  fallback writes when no VCS is present.
- **Continuous integration** (`.github/workflows/encoding.yml` +
  `.github/workflows/sources.yml`, split out of the original `ci.yml`), two
  jobs, both executed on a real fresh clone before the files were added:
  `encoding` runs on every push and runs
  `scripts/check-gates-selftest.ps1`, then `scripts/check-encoding.ps1` (the
  three-level encoding rule, PowerShell syntax of every tracked `.ps1`, and the
  PE timestamp / builder-state gates), then `scripts/link-audit.ps1` and
  `scripts/source-parity.ps1`; `sources` runs only when a vendor/patching input
  changes (see CONTRIBUTING) and runs `scripts/fetch-vendor.ps1`, then
  `-VerifyOnly`, then unpack both chains, apply, `-VerifyOnly`,
  `make-patches -Check`. The 15 archives are cached between runs
  (`actions/cache`, keyed on `scripts/fetch-vendor.ps1` +
  `vendor/manifest.json`), so a manifest bump re-downloads only the moved
  archive and the other 14 come from cache; `fetch-vendor.ps1` re-verifies
  every entry, cached or not. Every script exits with the number of failed
  assertions, so no job parses logs.
- **Documentation gates** (`scripts/link-audit.ps1`, `scripts/source-parity.ps1`):
  the first resolves all 218 markdown links of the tracked tree — 183 relative
  targets against the index, the worktree and the ignore rules, 26 `#fragment`
  anchors against the real heading slugs (fenced headings excluded) — and the
  second checks that `docs/SOURCES.md` and the `scripts/fetch-vendor.ps1`
  manifest carry the same 15 URLs, digests, sizes and vendored filenames, in
  both directions, with the size required to sit on the same line as its digest.
  Both were scratch tools during the audit and were promoted in the same change
  that publishes their result, because a claim whose evidence lives in a
  gitignored directory cannot be re-run by a reader. Measured on this tree: 0
  findings, 5.4 s and 0.6 s.
- **Negative control for the gates** (`scripts/check-gates-selftest.ps1`, the
  first step of the `encoding` job): 126 assertions (124 on a bare checkout —
  two need the built artifacts), 34 injected defect classes and 6 vacuous-pass
  guards, each built as a throwaway repository or archive carrying exactly one
  defect, with the valid baseline required to pass first and re-verified after
  every teardown. A gate that has only ever been observed passing is not
  evidence, and CI is precisely where the encoding gate sees no artifacts.
  Running it exposed an artifact section that passed while skipping, a wrong
  search path for `SHA256SUMS.txt`, a fixture that failed for a reason of its
  own, a link audit that counted 26 anchors and resolved none, a parity parser
  that extracted 1 of 15 manifest fields and reported findings as if it worked,
  and a diagnostic message whose second half PowerShell silently dropped.
- **Release automation** (`scripts/publish-release.ps1`): annotated tag,
  GitHub release with versioned and architecture-qualified asset names,
  rendered `SHA256SUMS.txt`, release body generated from
  `src/docs/release-notes.md` placeholders, a clean-tree requirement, a
  refusal to move a tag a published release points at, and `-DryRun` that
  performs every local step without touching GitHub or refs.
- **Process documents**: [`SECURITY.md`](SECURITY.md),
  [`CONTRIBUTING.md`](CONTRIBUTING.md), [`SUPPORT.md`](SUPPORT.md), this
  changelog, and [`README.ru.md`](README.ru.md) alongside the English
  [`README.md`](README.md).
- **Internal engineering documents** (Russian):
  [`docs/PLAN.md`](docs/PLAN.md) (build decisions and findings),
  [`docs/ENVIRONMENT.md`](docs/ENVIRONMENT.md) (toolchain and host
  inventory), [`docs/COMPARISON.md`](docs/COMPARISON.md) (MSVC vs MinGW,
  measured), [`docs/NOTES.md`](docs/NOTES.md) (vendor test-suite runs with
  root causes and accepted failures).

### Changed

- **0.1 was re-issued on 2026-10-29 and its artifacts are different bytes.**
  The release first published on 2026-10-27 was withdrawn and re-created. All
  five assets changed, not just the documentation archive: eight commits landed
  between the old tag (`85f142b`) and the new one (`ddea773`), and one of them
  edited `src/kit/vfs/lib/TclReadLine/tclreadline-win.tcl`, a file that lives
  inside `kit.vfs` and therefore inside all four executables.
- **The published `SHA256SUMS.txt` used to be unverifiable.** It was CRLF and
  carried a blank line between its header and the digests, so the command both
  READMEs print, `sha256sum -c SHA256SUMS.txt`, failed on it: 5 × `FAILED open
  or read`, `WARNING: 5 listed files could not be read`, exit 1. It is now LF,
  620 B, and verified 5 × OK with exit 0 under both `-c` and `-c --strict`
  against copies downloaded from the release rather than from the local build.

### Known limitations

- TWAPI is documented as **partial**: its own suite reports 380 failures of
  3494 on the reference host (`wmic` removed from Windows, the `Twapi.Test`
  COM object unregistered, tests assuming interactive dialogs, aged
  crypto/pdh/ui/tls suites). The functions this kit uses are covered by
  `tests\smoke.tcl`.
- Tcl's own suite was run in full (69 780 tests, every failure traced to the
  kit's REPL wrapper, zero against a stock-tclsh control). Tk's suite and the
  complete tcllib/tklib suites were **not** run in full.
- `tdbc::mysql` and `tdbc::postgres` are absent; they need vendor SDKs that
  are not redistributable here.
- X11 cursor names (`gumby`, `trek`, …) have no meaning on Windows Tk, which
  takes cursors from the exe's `CURSOR` resources.
- Some CAWT demos require a installed Office application; they are the
  package author's demos, shipped as upstream published them.
- Windows 7/8 need KB2999226/KB3118401 for the MinGW build's UCRT
  forwarders; the MSVC build has no such requirement.
- `__FILE__` strings reachable from panic messages contain the build machine
  paths (no user name, no host name). Trimming them via `/d1trimfile` and
  `-ffile-prefix-map` is planned for the next release.
- Reproducibility is measured **on the reference host and toolchain** (MSVC
  14.51.36231 / MinGW gcc 16.1.0, see [`docs/ENVIRONMENT.md`](docs/ENVIRONMENT.md)).
  A rebuild elsewhere is expected to differ — the two toolchains do not even
  agree on the PE timestamp value, by design — and a clean-machine rebuild
  has not been performed yet.

[0.2]: https://github.com/nektomk/tclwinkit/releases/tag/v0.2
[0.1]: https://github.com/nektomk/tclwinkit/releases/tag/v0.1
