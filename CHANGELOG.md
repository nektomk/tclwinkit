# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The version number lives in exactly one place: `variable version` in
[`src/kit/vfs/lib/kit_init.tcl`](src/kit/vfs/lib/kit_init.tcl). Every
release ships five artifacts — four executables (MSVC and MinGW-w64, console
and GUI) plus the documentation archive — and a `SHA256SUMS.txt`.

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

[0.1]: https://github.com/nektomk/tclwinkit/releases/tag/v0.1
