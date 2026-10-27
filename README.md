# tclwinkit

**Reporting security issues** · [Русская версия README](README.ru.md)

Portable single-file Tcl 9 for Windows x64.

One executable is a whole distribution: the **Tcl 9.0.4** interpreter (plus
**Tk 9.0.4** in the GUI build), the binary extensions **statically linked
into the exe**, and the pure-Tcl libraries (tcllib, tklib, and the Tcl parts
of mixed packages) attached to the exe as a ZIP archive that the built-in
**zipfs** mounts at startup as `//zipfs:/app`. No DLLs beside the exe, no
installer, no registry writes — copy one file and run it.

```tcl
tclwinkit-msvc.exe script.tcl arg1     ;# drop-in tclsh replacement
tclwinkit-msvc.exe                     ;# interactive REPL with history
winkitwish-msvc.exe app.tcl            ;# drop-in wish replacement
```

## Why

The usual ways to get Tcl 9 on Windows are an installer, a package manager,
or a build of your own. `tclwinkit` is instead a **file you can put in
`PATH`, on a USB stick, or in a CI cache**: the interpreter and ~700 packages
travel together, and two independent toolchains (MSVC and MinGW-w64) ship
the same kit so a toolchain problem never becomes a distribution problem.

Typical uses: shipping a Tcl application to a machine that must not have
anything installed; a throwaway scripting environment in a Windows container
or a locked-down desktop; running someone else's Tcl 8/9 script without
touching the system Tcl.

## Download

Grab a file from the [latest release](https://github.com/nektomk/tclwinkit/releases/latest):

| Asset | Toolchain | Subsystem | Size |
|---|---|---|---|
| `tclwinkit-0.1-msvc-x64-console.exe` | MSVC 19.51, static CRT | console | 10.75 MB |
| `tclwinkit-0.1-msvc-x64-gui.exe` | MSVC 19.51, static CRT | GUI | 15.86 MB |
| `tclwinkit-0.1-mingw-x64-console.exe` | MinGW-w64 GCC 16.1, UCRT | console | 11.62 MB |
| `tclwinkit-0.1-mingw-x64-gui.exe` | MinGW-w64 GCC 16.1, UCRT | GUI | 17.89 MB |
| `tclwinkit-docs-0.1.zip` | — | man pages, HTML docs, demos, licenses | 13.57 MB |

`SHA256SUMS.txt` accompanies every release:

```
certutil -hashfile tclwinkit-0.1-msvc-x64-console.exe SHA256
sha256sum -c SHA256SUMS.txt          # on any machine with coreutils
```

The docs archive is the fifth asset because the kits deliberately carry
**runtime only**. Inside the archive: `man/` (584 nroff pages for 14
packages), `html/` (1473), `demos/` (519), `docs/`, `tools/` (a groff-free man
renderer and the iwidgets demo launcher), `LICENSES/`, `LICENSE`,
`THIRD-PARTY-NOTICES.md`, `VERSIONS.txt`, `MANIFEST.txt`. With the archive
unpacked next to a kit, the demos run from the same exe:

```
winkitwish-msvc.exe demos\tk\widget           # Tk widget browser
winkitwish-msvc.exe demos\iwidgets\catalog    # iwidgets catalog
tclwinkit-msvc.exe  tools\man.tcl man\tcl\subst.n
```

See [`src/docs/README.md`](src/docs/README.md) for the archive's full
contents (English section on top, detailed Russian below).

## What this is not

Asked often enough to be worth answering before the issue tracker:

- **Not a Tcl fork.** Tcl, Tk and every bundled package are upstream
  releases, unmodified except where [`patches/`](patches/README.md) says so.
- **Not `tclkit`.** tclkit is a runtime built for the Starpack/VFS
  ecosystem, with its own `filesystem` package and its own release cadence.
  Here the exe is a plain Tcl/Tk build; the attached ZIP is mounted by
  upstream `zipfs`, and any script that works with stock `tclsh` keeps
  working. There is no `.kit` file format, no `sdx`, and no shell.
- **Not a starpack.** Nothing is self-extracting; nothing writes to a
  temporary directory at startup. The archive is read in place, through the
  mounted filesystem.
- **Not an installer and not a manager.** It does not register file
  associations, touch `PATH`, or coexist with a system Tcl — it simply is
  the interpreter you pointed at.
- **Not ActiveState ActiveTcl.** No proprietary build, no `teapot`, no
  closed tooling; every byte is either upstream open source or glue written
  here under MIT.

## What is inside

| Component | Version | How it is wired |
|---|---|---|
| Tcl core | 9.0.4 | static |
| Tk | 9.0.4 | static (GUI exe) |
| registry / dde | 1.3.7 / 1.4.6 | static (part of the core build) |
| Itcl | 4.3.8 | static + `itcl4.3.8/itcl.tcl` in zipfs |
| Itk | 4.2.7 | static + `itk4.2.7/` in zipfs (GUI) |
| Iwidgets | 4.1.1 | pure Tcl in zipfs (GUI) |
| Thread | 3.0.6 | static + `thread_library/ttrace.tcl` |
| tdbc / sqlite3 / tdbc::sqlite3 / tdbc::odbc | 1.1.13 / 3.53.0 | static, plus Tcl parts in zipfs |
| TWAPI | 5.2.0 | static (+ dyncall 0.9) + Tcl parts in zipfs |
| Img (tkimg) | 2.1.2 | static: 19 image formats (zlib/png/jpeg/tiff/…) |
| rl_json | 0.17.8 | static (both toolchains) |
| mpexpr | 1.2 | static (both toolchains) |
| tkdnd | 2.9.5 | static + Tcl parts in zipfs (GUI) |
| Treectrl | 2.5.2 | static + `treectrl2.5.2/` in zipfs (GUI) |
| tcllib | 2.0 | pure Tcl in zipfs |
| tklib | 0.9 | pure Tcl in zipfs (GUI) |
| CAWT | 3.1.1 | pure Tcl in zipfs |
| TclReadLine | 1.1 | pure Tcl in zipfs + Win32 shim on TWAPI |

`package names` reports 54 eagerly registered names in the console kit and
691 in the GUI kit; tcllib/tklib modules are lazy-loaded through their `tm`
indices, so the full picture is what `tests\tcllib-probe.tcl` measures (439
packages offered in the console kit, 571 in the GUI kit). The exact version
of every bundled component is in `VERSIONS.txt` inside the docs archive,
which the kit can also print at runtime.

## Interactive REPL

The console kit is not a bare `tclsh`: it starts a REPL with line editing,
history and completion, implemented in pure Tcl (TclReadLine 1.1) over a
Win32 shim on TWAPI — character input through `ReadConsoleInput`, rendering
through virtual terminal processing (Windows 10+).

| Key | Action |
|---|---|
| Up / Down | history |
| Left / Right, Home / End, Del | line editing |
| Ctrl-A/E/K/U/W, Ctrl-P/N | emacs bindings |
| Ctrl-C | clear the current line (while typing) |
| Shift-Tab | completion (commands, variables, files) |
| Ctrl-T | toggle plain-Tab completion |
| Ctrl-D on an empty line, `exit` | quit (history is saved) |

History lives in `~/.tclline_history`, REPL config in `~/.tcllinerc`, and the
kit's own rc file (the `tclshrc` equivalent) in `~/winkitrc.tcl` or
`~/winkitwishrc.tcl`.

## Tray icon, no winico

`winico` is not bundled — TWAPI covers it completely:

```tcl
package require twapi
wm withdraw .
set hico [twapi::load_icon_from_file myapp.ico]
set id [twapi::systemtray::addicon $hico [list show]]
twapi::systemtray::modifyicon $id -tip "My application"
proc show {args} { wm deiconify . }
```

## Portability

- All four executables depend only on system Windows DLLs (verified with
  `objdump -p` / `dumpbin /dependents`).
- MSVC builds use a static CRT (`OPTS=nomsvcrt`) — not a single CRT DLL.
- MinGW builds use `-static` plus the `api-ms-win-crt-*` UCRT forwarders,
  which are part of Windows 10+; Windows 7/8 need KB2999226/KB3118401.
- Running from a read-only directory works (the smoke test passes there).

## Known limitations

Honest list, so you do not have to discover them:

- **TWAPI is partially tested.** Its own suite reports 380 failures of 3494
  on this host: `wmic` is gone from Windows, the `Twapi.Test` COM object is
  unregistered, several tests assume interactive dialogs, and a group of
  suites (crypto, pdh, ui, tls) is simply old. The functions this kit uses
  are exercised by `tests\smoke.tcl`. See
  [`docs/NOTES.md`](docs/NOTES.md) (Russian) for the breakdown.
- **Vendor test suites were run, and their failures are classified, not
  hidden** — the numbers and the reasons live in
  [`docs/NOTES.md`](docs/NOTES.md) (Russian). Tcl's own suite was run in
  full (69 780 tests; every failure traced to the kit's REPL wrapper, zero
  against a stock-tclsh control). Tk's suite and the complete tcllib/tklib
  suites were **not** run in full.
- **X11 cursor names are not available.** Tk on Windows takes cursors from
  the exe's `CURSOR` resources, so names like `gumby` or `trek` have no
  meaning here; widgets that ask for them get the platform default.
- **`tdbc::mysql` and `tdbc::postgres` are absent** — they need vendor SDKs
  that are not redistributable here. `tdbc::sqlite3` and `tdbc::odbc` are
  included.
- **Some CAWT demos require Office installed** (Excel/Word/PowerPoint/
  Outlook/OneNote). They are the package author's demos, not tests, and are
  shipped as upstream published them.
- **Most Tk sub-demos do not start standalone.** 63 of the 66 scripts in
  `demos\tk\` open a Tk dialog titled "Error in startup script" saying
  `This script should be run from the "widget" demo.` — nothing on stderr,
  the process stays alive with the dialog. Upstream behaviour, not an
  archive defect: enter through `demos\tk\widget`. The iwidgets demos are
  re-pointed during packaging and all start directly.
- **The docs archive is not covered by the automated gates.** It publishes
  vendor files as received.

## Building from source

Two toolchains, six steps each. Full instructions, conventions, expected
test numbers and the release procedure are in
[`CONTRIBUTING.md`](CONTRIBUTING.md); the environment inventory is in
[`docs/ENVIRONMENT.md`](docs/ENVIRONMENT.md) (Russian).

```
scripts\build-msvc-kit.bat        # core + extensions + kit, then:
scripts\assemble-msvc-kit.ps1     # stage VFS -> zip -> attach to exe -> dist\

scripts\build-mingw-kit.sh        # under MSYS2 UCRT64, then:
scripts\assemble-mingw-kit.ps1

scripts\make-licenses.ps1         # regenerate LICENSES/ (must run before packaging)
scripts\build-docs-artifact.ps1   # the fifth asset
```

`assemble-*.ps1` clean the staged image with `scripts\kit-prune.ps1`, so
`kit.vfs` carries runtime files only (−32.40 MB, −4269 files on the GUI kit).
Pruning removes documentation but **never** license texts: mandatory
licenses stay in the image by filename rule (`$KitLicenseNames`), and
`tests\kit-license-check.tcl` reads each one out of the finished exe and
checks the phrases that particular license requires.

```
dist\tclwinkit-msvc.exe tests\smoke.tcl              # SMOKE OK
dist\tclwinkit-msvc.exe tests\tcllib-probe.tcl       # PROBE OK
dist\tclwinkit-msvc.exe tests\kit-license-check.tcl  # KIT LICENSE CHECK OK
```

Run all three against each of the four executables.

## Licenses

The glue written here (`src/kit`, `scripts`, `src/docs`, `docs`, `tests`) is
**MIT** — see [LICENSE](LICENSE). Everything bundled keeps its own license:
Tcl, BSD-3, BSD-2, ISC, Zlib, libpng, libtiff, IJG, blessing, Info-ZIP,
CC-BY-2.5, public domain, and one copyleft module (`tcllib/math/filtergen`,
GPL-3 with a section-7 permission). Full attribution is in
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md); the texts are in
[LICENSES/](LICENSES/) — 54 files, entirely generated by
[scripts/make-licenses.ps1](scripts/make-licenses.ps1), whose `-Check` mode
re-verifies the tree against vendor sources and is CI-ready.

GitHub will report this repository as MIT. That is true for the glue only.
Mixed detector hits on vendor paths (`tclDate.c` → GPL,
`contrib/gregbook` → GPL) are explained in THIRD-PARTY-NOTICES.md §5.

Vendor modifications follow
[`patches/README.md`](patches/README.md): a modified file stays under the
original license, no separate rights are claimed, copyright headers are not
removed.

## More documentation

Internal documentation is written in Russian, because that is the language
it is maintained in; translations welcome (the `i18n` label collects those
issues, and translating a doc is a canonical good first issue here).

| Document | What it holds |
|---|---|
| [`README.ru.md`](README.ru.md) | this page in Russian, with the detail that does not fit a showcase |
| [`docs/PLAN.md`](docs/PLAN.md) | build decisions and findings (Russian) |
| [`docs/ENVIRONMENT.md`](docs/ENVIRONMENT.md) | toolchain and host inventory (Russian) |
| [`docs/CONVENTIONS.md`](docs/CONVENTIONS.md) | encoding and line-ending rules, with the measurements behind them (Russian) |
| [`docs/COMPARISON.md`](docs/COMPARISON.md) | MSVC vs MinGW, measured (Russian) |
| [`docs/NOTES.md`](docs/NOTES.md) | vendor test-suite runs: numbers, root causes, accepted failures (Russian) |
| [`src/docs/README.md`](src/docs/README.md) | the docs archive: contents and usage |
| [`patches/README.md`](patches/README.md) | index of every vendor modification |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) · [`SECURITY.md`](SECURITY.md) · [`SUPPORT.md`](SUPPORT.md) · [`CHANGELOG.md`](CHANGELOG.md) | process documents |

## Translations

`README.ru.md` is maintained in parallel with this file. Other languages are
welcome — open an issue or a pull request with the `i18n` label. Machine
translation of the README is not accepted: it reliably mangles the
load-bearing words here (kit, man page, attach, bundle).
