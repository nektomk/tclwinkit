# tclwinkit

**Reporting security issues** · [Русская версия README](README.ru.md)

Portable single-file Tcl 9 for Windows x64.

One executable is a whole Tcl 9 distribution: the interpreter (plus Tk in the
GUI builds), the binary extensions statically linked in, and ~700 pure-Tcl
libraries carried as a ZIP archive the built-in **zipfs** mounts at startup.
No DLLs beside the exe, no installer, no registry writes — copy one file and
run it.

## Download

Pick **one archive** from the [latest release](https://github.com/nektomk/tclwinkit/releases/latest).
Both carry the same console and GUI executables; the MSVC archive adds the two
safe kits, which is the only functional difference between them. Beyond that the
toolchain is a matter of taste, not quality:

| Asset | Toolchain | Inside |
|---|---|---|
| `tclwinkit-msvc-….zip` | MSVC, static CRT | `tclwin.exe` (`tclsh` replacement + REPL), `tkwin.exe` (`wish` replacement, Tk apps), `tclsafe.exe` / `tksafe.exe` (safe mode) |
| `tclwinkit-mingw-….zip` | MinGW-w64, UCRT | `tclwin.exe` and `tkwin.exe`, GCC-built — this chain ships no safe kits |
| `tclwinkit-docs-….zip` | — | man pages, HTML docs, demos, licenses |

Each archive unpacks into a single directory named after it and holds those
executables and nothing else: no installer, no DLLs to place beside them,
nothing registered. Two independent toolchains ship the same console and GUI
executables, so a toolchain problem never becomes a distribution problem; the
two safe kits are MSVC-only, which is the one functional difference between the
archives. `SHA256SUMS.txt`
accompanies every release:

```
certutil -hashfile tclwinkit-msvc-….zip SHA256
sha256sum -c SHA256SUMS.txt          # on any machine with coreutils
```

The sums are checkable against your own build: two full rebuilds on the
reference host reproduce every shipped byte for byte, and the release archives
are reproducible in their own right — two consecutive runs of the packer over
the same executables give identical bytes. See
[`BUILDING.md`](BUILDING.md) and [`CONTRIBUTING.md`](CONTRIBUTING.md).

Releases up to 0.2 shipped four loose executables named
`tclwinkit-<version>-<toolchain>-x64-<console|gui>.exe`. From 0.3 the same
executables ship inside the two archives above, under short names
(`tclwin.exe`, `tkwin.exe`) that need no renaming after unpacking.

## Quick start

Unpack an archive, then from its directory:

```tcl
tclwin.exe script.tcl arg1           ;# drop-in tclsh: run a script
tclwin.exe                           ;# interactive REPL with history
tkwin.exe app.tcl                    ;# drop-in wish: a Tk application
```

That is the whole story. For REPL keys, see
[Interactive REPL](#interactive-repl).

## What's inside

One file, `//zipfs:/app` at startup — Tcl 9 core, Tk 9 (GUI builds), and the
bundled packages, each chosen because it earns its place:

- **tcllib, tklib** — the standard libraries: JSON, XML, HTML, http, uri,
  base64, structures, math, physics, units, and hundreds more.
- **TWAPI** — the Windows API as Tcl commands: processes, services,
  registry, filesystem, COM, window and input management. The kit's own REPL
  and tray/cursor work are built on it.
- **tdbc + sqlite3** — `tdbc::sqlite3` out of the box, `tdbc::odbc` for
  anything with an ODBC driver.
- **Img** — 19 image formats (PNG, JPEG, TIFF, GIF, BMP, …) for Tk.
- **tkdnd, Treectrl, Itcl, Itk, Iwidgets** — drag-and-drop, tree widgets,
  object orientation, and the big widget set built on Itk.
- **TclReadLine** — the REPL's line editing and completion.
- **mpexpr, rl_json** — native-speed math and JSON.
- **CAWT** — drive Microsoft Office (Excel, Word, PowerPoint, Outlook)
  through COM.

Hand-picked packages stay small and every one is exercised by the test suite
before a release ships; `package names` in the GUI kit reports ~700 names.
The exact version list of every bundled component is `VERSIONS.txt` in the
[docs archive](src/docs/README.md); a running kit reports its own version as
`$::winkit::version`.

## Safe mode

The MSVC toolchain ships two additional executables: `tclsafe.exe` (console)
and `tksafe.exe` (GUI). They run untrusted Tcl scripts in a sandboxed child
interpreter with restricted file access and command limits.

**What it protects against.** Safe kits are designed to run **untrusted
scripts** — for example, third-party code in a CI pipeline or a tooling agent.
The script runs in a child interpreter whose `accessPath` is limited to its
own directory and the standard Tcl/Tk libraries. System commands, arbitrary
file access, and network sockets are blocked by design.

**What it does not protect against.** Safe interpreters protect against the
**script**, not against the **machine** it runs on. They do not provide
isolation from other processes, do not limit memory or CPU usage, and do not
prevent side effects through shared resources (e.g., environment variables or
temporary files).

**Blocked operations.** The following are unavailable in safe mode:

- `exec` — no external commands or processes.
- `open` — no arbitrary file handles; only files within `accessPath`.
- `socket` — no network access.
- `load` — no loading native libraries at runtime.
- `file` — restricted to `readable` checks within `accessPath`.

**Command and time limits.** Two limits apply to every safe script:

- **Script mode:** 300 seconds wall-clock, 2·10⁹ commands.
- **REPL mode:** 60 seconds per line, 5·10⁸ commands per line.
- **GUI mode:** no limits (intended for trusted applets).

When either limit is exceeded, the child interpreter raises an error and
becomes unusable for further evaluation — the master remains intact and can
start a fresh child.

**Unavailable packages.** Packages that require native initialization outside
the safe framework are not accessible: `twapi`, `mpexpr`, `Thread`, `sqlite3`,
`tdbc::*`, `Img`, `tkdnd`, `tktreectrl`, `registry`. Attempting to load them
fails with a clear error message (`no <pkg>_SafeInit procedure`).

**Tk dialogs.** In GUI safe kits (`tksafe.exe`), Tk dialog commands
(`tk_dialog`, `tk_getOpenFile`, `tk_getSaveFile`) do not work — this is
stock Tk behaviour in safe interpreters. The commands exist but fail with an
error.

**Memory and CPU.** Safe interpreters do **not** limit memory consumption or
CPU time. Only the number of Tcl commands and wall-clock time are enforced.

## Why

The usual ways to get Tcl 9 on Windows are an installer, a package manager,
or a build of your own. `tclwinkit` is instead a **file you can put in
`PATH`, on a USB stick, or in a CI cache**: the interpreter and its packages
travel together.

Typical uses: shipping a Tcl application to a machine that must not have
anything installed; a throwaway scripting environment in a Windows container
or a locked-down desktop; running someone else's Tcl 8/9 script without
touching the system Tcl.

Portable in the strict sense: all four executables depend only on system
Windows DLLs, and running from a read-only directory works — nothing writes
beside the exe at startup, so a write-protected USB stick is fine.

## Interactive REPL

The console kit is not a bare `tclsh`: it starts a REPL with line editing,
history and completion, implemented in pure Tcl over a Win32 shim on TWAPI.
Character input goes through `ReadConsoleInput`; rendering through virtual
terminal processing (Windows 10+).

| Key | Action |
|---|---|
| Up / Down | history |
| Left / Right, Home / End, Del | line editing |
| Ctrl-A/E/K/U/W, Ctrl-P/N | emacs bindings |
| Ctrl-C | clear the current line (while typing) |
| Shift-Tab | completion (commands, variables, files) |
| Ctrl-T | toggle plain-Tab completion |
| Ctrl-D on an empty line, `exit` | quit |

History is kept **in memory for the session only** and is never written to
disk, and the kit reads **no** startup file — no `~/.tcllinerc`, no
`~/.tclline_history`, no `tclshrc`-equivalent. That is deliberate: the kit has
to behave identically on a machine it has never seen, so nothing outside the
executable can change what it runs. It is also what makes running from a
read-only directory work.

## Docs archive

The docs archive is a separate asset, because the kits carry **runtime only**.
Inside: `man/`, `html/`, `demos/`, `docs/`, `tools/` (a groff-free man renderer
and the iwidgets demo launcher), `LICENSES/`, `LICENSE`,
`THIRD-PARTY-NOTICES.md`, `VERSIONS.txt`, `MANIFEST.txt`. With both archives
unpacked, the demos run from the same executables (the paths below are relative
to the docs archive):

```
tkwin.exe demos\tk\widget                  # Tk widget browser
tkwin.exe demos\iwidgets\catalog           # iwidgets catalog
tclwin.exe tools\man.tcl man\tcl\subst.n   # read a man page
```

See [`src/docs/README.md`](src/docs/README.md) for the archive's full
contents (English section on top, detailed Russian below).

## What this is not

Asked often enough to be worth answering before the issue tracker:

- **Not a Tcl fork.** Tcl, Tk and every bundled package are upstream
  releases, unmodified except where [`patches/`](patches/README.md) says so.
- **Not `tclkit`.** tclkit is a runtime built for the Starpack/VFS
  ecosystem, with its own `filesystem` package and its own release cadence.
  There is no `.kit` file format, no `sdx`, and no shell here.
- **Not a starpack.** Nothing is self-extracting; nothing writes to a
  temporary directory at startup. The archive is read in place, through the
  mounted filesystem.
- **Not an installer and not a manager.** It does not register file
  associations, touch `PATH`, or coexist with a system Tcl — it simply is
  the interpreter you pointed at.
- **Not ActiveState ActiveTcl.** No proprietary build, no `teapot`, no
  closed tooling; every byte is either upstream open source or glue written
  here under MIT.

## Known limitations

- **`tdbc::mysql` and `tdbc::postgres` are absent** — they need vendor SDKs
  that are not redistributable here. `tdbc::sqlite3` and `tdbc::odbc` are
  included.
- **TWAPI is partially tested.** Its own suite has failures on this host
  (`wmic` gone from Windows, the `Twapi.Test` COM object unregistered,
  suites that assume interactive dialogs, and a group of old suites — crypto,
  pdh, ui, tls). The functions this kit uses are exercised by the kit's own
  tests; the detailed breakdown is in
  [`docs/NOTES.md`](docs/NOTES.md) (Russian).
- **Vendor test suites were run, and their failures are classified, not
  hidden** — the numbers and the reasons live in
  [`docs/NOTES.md`](docs/NOTES.md) (Russian).

## More documentation

Internal documentation is written in Russian, because that is the language it
is maintained in; translations welcome (the `i18n` label collects those
issues, and translating a doc is a canonical good first issue here).

| Document | What it holds |
|---|---|
| [`BUILDING.md`](BUILDING.md) | from a clean checkout to `dist/`, step by step |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | layout, conventions, CI, testing, releases, pull requests |
| [`docs/SOURCES.md`](docs/SOURCES.md) | vendor source map: URLs, SHA-256, how each was measured (Russian) |
| [`docs/ENVIRONMENT.md`](docs/ENVIRONMENT.md) | toolchain inventory of the reference machine (Russian) |
| [`docs/CONVENTIONS.md`](docs/CONVENTIONS.md) | encoding and line-ending rules, with the measurements behind them (Russian) |
| [`docs/CONVENTIONS-HISTORY.md`](docs/CONVENTIONS-HISTORY.md) | the defects and decisions the conventions grew out of: the changelog (Russian) |
| [`docs/CONVENTIONS-CI.md`](docs/CONVENTIONS-CI.md) | how the encoding gates verify the tree: runnable detail (Russian) |
| [`docs/COMPARISON.md`](docs/COMPARISON.md) | MSVC vs MinGW, measured (Russian) |
| [`docs/NOTES.md`](docs/NOTES.md) | vendor test-suite runs: numbers, root causes, accepted failures (Russian) |
| [`src/docs/README.md`](src/docs/README.md) | the docs archive: contents and usage |
| [`patches/README.md`](patches/README.md) | index of every vendor modification |
| [`SECURITY.md`](SECURITY.md) · [`SUPPORT.md`](SUPPORT.md) · [`CHANGELOG.md`](CHANGELOG.md) | process documents |

## Translations

`README.ru.md` is maintained in parallel with this file. Other languages are
welcome — open an issue or a pull request with the `i18n` label. Machine
translation of the README is not accepted: it reliably mangles the
load-bearing words here (kit, man page, attach, bundle).

## Licenses

The glue written here (`src/kit`, `scripts`, `src/docs`, `docs`, `tests`) is
**MIT** — see [LICENSE](LICENSE). Everything bundled keeps its own license:
Tcl, BSD-3, BSD-2, ISC, Zlib, libpng, libtiff, IJG, blessing, Info-ZIP,
CC-BY-2.5, public domain, and one copyleft module (`tcllib/math/filtergen`,
GPL-3 with a section-7 permission). Full attribution is in
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md); the texts are in
[LICENSES/](LICENSES/), entirely generated by
[scripts/make-licenses.ps1](scripts/make-licenses.ps1), whose `-Check` mode
re-verifies the tree against vendor sources and is CI-ready.

GitHub will report this repository as MIT. That is true for the glue only.
Mixed detector hits on vendor paths (`tclDate.c` → GPL,
`contrib/gregbook` → GPL) are explained in THIRD-PARTY-NOTICES.md §5.

Vendor modifications follow
[`patches/README.md`](patches/README.md): a modified file stays under the
original license, no separate rights are claimed, copyright headers are not
removed.

## Acknowledgements

This project was built in the
[DeepSeek Harness](https://www.deepseek.com/harness/) agent environment and
written with the help of the [DeepSeek-V4](https://www.deepseek.com/) and
[Qwen](https://qwen.ai/) language models — they wrote the glue, audited the
vendor trees, and argued with the measurements until the numbers matched.
Model access was provided by [PlusVibe](https://plusvibeapi.ru), an
OpenAI-compatible API that takes payment in rubles; without it, none of
these sessions would have been possible.