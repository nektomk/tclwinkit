Portable single-file Tcl 9 for Windows x64. One executable is a whole Tcl 9
distribution: the interpreter (plus Tk in the GUI builds), binary extensions
statically linked in, and ~700 pure-Tcl libraries carried as a ZIP archive the
built-in **zipfs** mounts at startup. No DLLs beside the exe, no installer, no
registry writes — copy one file and run it.

## Download

{{ASSET_TABLE}}

Unpack the archive for the toolchain you want — {{MSVC_ZIP}} or {{MINGW_ZIP}}.
Each unpacks into one directory named after the archive and holds exactly two
files, `tclwin.exe` (console) and `tkwin.exe` (GUI): no installer, no DLLs to
place beside them, nothing to register. Both archives and the docs archive are
built from a single source tree and share one version {{VERSION}}. Checksums are
in `SHA256SUMS.txt` (`sha256sum -c SHA256SUMS.txt`, or
`certutil -hashfile <file> SHA256` on Windows; the file ships with the release
assets).

## Running

```
tclwin.exe script.tcl arg1 arg2  ;# like tclsh: arguments, -encoding
type cmds.tcl | tclwin.exe       ;# stdin mode, like tclsh
tclwin.exe                       ;# interactive REPL: history, Ctrl+R,
                                 ;# Tab completion (TclReadLine)
tkwin.exe app.tcl                ;# like wish
tkwin.exe                        ;# GUI + Tk console widget
```

The console exe is a drop-in `tclsh` replacement (same argument semantics, pipe
mode and exit codes); the GUI exe is a drop-in `wish` replacement. The msvc and
mingw builds are interchangeable — pick either archive: msvc links the static
CRT, mingw the UCRT.

## What is inside

| Component | How it is linked |
|---|---|
| Tcl core | statically |
| Tk | statically (GUI builds) |
| registry / dde | statically (part of the core) |
| Itcl / Itk | statically + Tcl parts in zipfs (GUI builds for Itk) |
| Iwidgets | pure Tcl (zipfs, GUI builds) |
| Thread | statically + `thread_library/ttrace.tcl` |
| tdbc / sqlite3 | statically + Tcl parts in zipfs |
| tdbc::sqlite3 / tdbc::odbc | pure Tcl / statically |
| TWAPI | statically (uses dyncall) + Tcl parts in zipfs |
| Img (tkimg) | statically: base, zlibtcl, pngtcl, jpegtcl, tifftcl — 19 formats |
| rl_json | statically |
| mpexpr | statically |
| tkdnd | statically + Tcl parts in zipfs (GUI builds) |
| Treectrl | statically + Tcl parts in zipfs (GUI builds) |
| tcllib | pure Tcl (zipfs) |
| tklib | pure Tcl (zipfs, GUI builds) |
| CAWT | pure Tcl (zipfs) |
| TclReadLine | pure Tcl (zipfs) + Win32 shim on TWAPI |

The exact version of every bundled component is recorded in `VERSIONS.txt`
inside the docs archive.

## Documentation, man pages and demos

The kit executables deliberately carry nothing but the runtime: reference pages,
HTML documentation, package demos and test suites are pruned from the staging
image (`scripts\kit-prune.ps1`) and published as the separate `{{DOCS_ZIP}}`
archive instead. Required license texts stay in the exe — pruning removes
documentation but never license terms (see «Licenses» below).

| Section | Files | What is inside |
|---|---:|---|
| `man/` | 584 | nroff pages for 14 packages (tcl, tk, itcl, itk, iwidgets, img, tdbc ×3, sqlite3, thread, rl_json, tkdnd, treectrl) |
| `html/` | 1473 | tcllib/tklib idoc, TWAPI reference, cawt, thread, mpexpr, tkdnd, treectrl |
| `demos/` | 519 | Tk, iwidgets, itk (+itkedit), treectrl, tkdnd, cawt |
| `docs/` | 47 | README/CHANGES/ChangeLog of the bundled packages |
| `LICENSES/` | 54 | license texts of all bundled components + source-header swaps |
| `tools/` | 2 | `man.tcl`, `iwidgets-demo.tcl` |
| — | 5 | `README.md`, `VERSIONS.txt`, `MANIFEST.txt`, `LICENSE`, `THIRD-PARTY-NOTICES.md` |

After unpacking both archives, the demos run with the same executables (the
paths below are relative to the docs archive):

```
tkwin.exe demos\tk\widget                    ;# Tk demo browser
tkwin.exe demos\iwidgets\catalog             ;# iwidgets demo browser
tkwin.exe demos\treectrl\demo.tcl            ;# Treectrl demo browser
tclwin.exe tools\man.tcl man\tcl\subst.n     ;# a man page as plain text
```

`tools\man.tcl` renders nroff to text on the kit itself — no groff needed.

## Licenses

The kit's own glue (`src/kit`, `scripts`, `docs`, `tests`) is MIT — see the
repository `LICENSE`. Everything else stays under its own license: the bundle is
Tcl / Tk and their extensions (Tcl license), tcllib/tklib (Tcl license with
module exceptions), iwidgets (DSC/BSD), TWAPI and CAWT (BSD-3), SQLite
(public-domain blessing), libpng/libtiff/libjpeg/zlib, the Info-ZIP cipher used
by zipfs, and a few notices that exist only in source headers.

This is a fact of the shipment, not a policy statement:

- the required texts live **inside every exe** (`//zipfs:/app/...`), not only in
  the repository;
- `THIRD-PARTY-NOTICES.md` (in the repo root and in the docs archive) names every
  component, its license, its copyright holders, and quotes verbatim what each
  license requires to be reproduced in a distribution;
- the `LICENSES/` directory (54 texts) is generated entirely by
  `scripts\make-licenses.ps1` from the vendor trees — nothing is typed by hand,
  and the `-Check` flag verifies the tree back and is CI-ready;
- `tests\kit-license-check.tcl` reads the texts from the finished exe's image and
  checks the phrases each specific license requires.

## Verified on this build

- `tests\smoke.tcl` — SMOKE OK on all four exes, including statics in child
  interpreters (`thread create {package require sqlite3 ; thread wait}`).
- `tests\tcllib-probe.tcl` — PROBE OK ×4: console 439 offered / 384 loaded, GUI
  571 / 508 loaded, 0 new breakages against the unpruned tree (upstream failures
  are checked against the `tests\tcllib-probe.baseline.txt` snapshot).
- `tests\kit-license-check.tcl` — KIT LICENSE CHECK OK ×4 (console: 8 paths + 6
  phrases, GUI: 17 + 11; layers are absent only as a whole, so a console kit
  without Tk is not a license miss). The guard is verified by negative controls:
  deleting 6 required texts from a copy of the image → 6 failures and exit 1;
  trimming one to 43 bytes → 2 failures (too short + required phrase missing).
- Package suites, both kits (figures agree between msvc and mingw): iwidgets
  3308/3308/0F, itk 100/100/0F, Img 290/272/18skip/0F, treectrl
  1236/1216/19skip/1F (upstream `itemdesc-1.15`), tkdnd 6/6 load-OK; itcl
  793/727/66skip/0F, thread 143/117/26skip/0F, sqlite3 1/1/0/0, tdbc 13/13/0/0,
  tdbc::sqlite3 161/158/3/0F, rl_json 2565/2562/3/0F, mpexpr clean; tcllib
  modules: doctools 599/599/0F, textutil 211/211/0F, struct 2708/2672/36skip/0F,
  json 527/527/0F.
- `tools\man.tcl` runs through 556/556 man pages of the finished archive with
  exit 0.

Qualifier legend: `N skip` = upstream skip (not a failure of this kit), `N F` =
known upstream failure, `0 NEW` = no new breakage against the unpruned tree.

## Known limitations

- **twapi 5.2.0** — partial support: the main functions exist and work, but part
  of the upstream test suite fails (Windows 11 + Tcl 9). CAWT on top of twapi is
  tested separately and works.
- **X11 cursors**: Tk on Windows takes cursor names from the named CURSOR
  resources of the exe, so non-standard X11 names are unavailable in the kit;
  the standard ones (`arrow`, `hand2`, `xterm`, ...) work. The tkdnd cursors in
  the docs archive are shipped for Windows only.
- **CAWT demos** partially drive real Office apps through COM
  (Excel/Word/PowerPoint/Outlook/OneNote) — these are demos from the package's
  author, not kit tests; an installed Office is required.
- **Tk sub-demos do not start standalone**: 63 of the 66 scripts in
  `demos\tk\` open an «Error in startup script» dialog with the text
  `This script should be run from the "widget" demo.` (nothing goes to stderr,
  the process stays alive with the dialog) — vendor behavior, not an archive
  defect; enter through `demos\tk\widget`. The iwidgets demos are re-bound to
  their own directory at packaging and start directly.
- **MinGW exes** carry `api-ms-win-crt-*` forwarders (UCRT is built into
  Windows 10+; on Win7/8 it needs KB2999226/KB3118401). **MSVC exes** depend on
  no CRT DLL at all — only system DLLs.

## Building from source

Build instructions moved to `BUILDING.md` (repo root): fetch the vendor archives,
apply the patches, build both toolchains, assemble the kits, generate the
licenses and the docs artifact, verify and publish. Vendor archives are not part
of the repository — their sources and checksums are in `docs\SOURCES.md`;
technical decisions and pitfalls in `docs\PLAN.md`; toolchain comparison in
`docs\COMPARISON.md`; environment in `docs\ENVIRONMENT.md`; vendor patches in
`patches\README.md`.

The release is prepared by `scripts\publish-release.ps1`; tag `{{TAG}}` points at
commit `{{HEAD}}`.
