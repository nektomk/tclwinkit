# Contributing

Two things first: the internal documentation is in Russian (this file and the
other process documents are English on purpose — maintainers and lawyers read
them), and the project is a **distribution of upstream releases**, so almost
every change is either packaging glue or a vendor bump. Contributions that
add new vendor code need a license decision before they are written; open an
issue first.

## Layout

| Path | What it is |
|---|---|
| `src/kit/` | the glue: `kit_main.c`, `kit_wish_main.c`, `kit_register.c`, `src/kit/vfs/**` (the staged zipfs content: `main.tcl`, `pkgIndex.tcl`, `lib/kit_init.tcl`, the TclReadLine shim) |
| `scripts/` | build, assemble, prune, license generation, docs artifact, release publishing |
| `src/docs/` | sources of the docs archive and of the release body (`release-notes.md` with `{{PLACEHOLDER}}` tokens) |
| `docs/` | internal engineering documents (Russian) |
| `tests/` | gates that run **inside the shipped image** |
| `patches/` | vendor modifications as data: `patches.json` is the manifest, `*.patch` are derived from it, `patches/README.md` is the human index |
| `LICENSES/` | generated — never hand-edit |
| `build/` | gitignored: toolchain output, staging trees, and all scratch work |

`build/research/` is scratch. Log directories, throwaway checkers, draft
documents, audit output — none of it is published, and nothing tracked
should link to it. If a scratch tool earns its keep, promote it to
`scripts/` or `tests/` in the same change that adds the link.

## Building

Both toolchains produce the same kit; a change is not done until it builds
on both.

Step zero — the vendor archives are not in this repository (67.65 MB,
gitignored), so a fresh clone cannot build anything until they are fetched:

```
scripts\fetch-vendor.ps1          # 15 archives -> vendor\
```

The script downloads each one from the URL recorded in
[`docs/SOURCES.md`](docs/SOURCES.md) and verifies size, SHA-256 **and** that
the bytes are a readable archive before it lets the file replace anything.
That third check is not ceremony: `https://www.dyncall.org/pub/dyncall-0.9.tar.gz`
answers HTTP 200 with `Content-Type: text/html` and zero bytes, so a status
code alone admits an HTML page into a build tree, where it surfaces much
later as an inexplicable `configure` failure. `-VerifyOnly` re-checks an
existing `vendor/` without network access; `-UsePins` switches the four
movable-branch sources to their commit-pinned forms (same files, different
bytes — see the SOURCES.md section on it).

Unpack `vendor/` into the fixed paths the build expects
(`build/<chain>/tcl9.0.4`, `build/<chain>/tk9.0.4`, `build/<chain>/ext/<top>`,
`build/common/<name>`); the mapping is data in `scripts/vendor-layout.json`
and the human view is SOURCES.md. `scripts\unpack-vendor.ps1` performs the
step: it verifies `vendor/` via `fetch-vendor.ps1 -VerifyOnly` first, extracts
through a scratch directory, and marks each tree with `.winkit-unpacked.json`,
so a half-extracted tree cannot be mistaken for a fetched one. No build script
touches `vendor/` itself.

Steps 0, 1 and 2 are all scripted — fetch, unpack, patch — and each one refuses
to run on top of a tree the previous one has not verified, so the chain is
checkable at every seam rather than only at the end:

```
scripts\fetch-vendor.ps1 -VerifyOnly
scripts\unpack-vendor.ps1 -VerifyOnly
scripts\apply-patches.ps1            # or -VerifyOnly to re-check without applying
```

`apply-patches.ps1` stages every change outside any repository and writes none of
them until the whole run has produced zero failures, so a refused patch cannot
leave a half-patched tree; `make-patches.ps1 -Check` recomputes the diffs and
both hashes from two trees and fails a manifest that drifted. The `itcl4.3.8` /
`tk9.0.4` junctions that SOURCES.md describes are created by
`build-msvc-ext2.bat` itself, not by any of the three. The command lists below
therefore assume step 2 has been run: `build-msvc-kit.bat` states
`Requires: build-msvc-core.bat, build-msvc-ext.bat, build-msvc-img.bat` and
invokes none of them. This is why CI has no build job — see "Continuous
integration" below.

MSVC (x64 Native Tools prompt, or `vcvars64.bat` first):

```
scripts\build-msvc-core.bat     # Tcl+Tk+pkgs: nmake OPTS=static,nomsvcrt
scripts\build-msvc-ext.bat      # dyncall 0.9 + TWAPI 5.2.0
scripts\build-msvc-img.bat      # Img 2.1.2: base, support, 19 formats
scripts\build-msvc-ext2.bat     # rl_json, mpexpr, itk, tkdnd, treectrl
scripts\build-msvc-kit.bat      # kit glue objects + link the exe
scripts\assemble-msvc-kit.ps1   # stage VFS -> zip -> attach -> dist\
```

MinGW (MSYS2 UCRT64; the script needs a login shell **with `MSYSTEM` set**):

```
$env:MSYSTEM = 'UCRT64'
C:\msys64\usr\bin\bash.exe -lc '/c/path/to/winkit/scripts/build-mingw-core.sh'
C:\msys64\usr\bin\bash.exe -lc '/c/path/to/winkit/scripts/build-mingw-ext.sh'
C:\msys64\usr\bin\bash.exe -lc '/c/path/to/winkit/scripts/build-mingw-ext2.sh'
C:\msys64\usr\bin\bash.exe -lc '/c/path/to/winkit/scripts/build-mingw-kit.sh'
scripts\assemble-mingw-kit.ps1
```

Without `MSYSTEM` the MSYS2 profile falls back to the MSYS toolchain, which
has no `gcc`, and `scripts/mingw-env.sh` stops there with
`no gcc in PATH` rather than letting the first `configure` die with
`no acceptable C compiler found in $PATH` further down.

Then, once both trees exist under `build/`:

```
scripts\make-licenses.ps1          # regenerate LICENSES/ (or -Check to verify)
scripts\build-docs-artifact.ps1    # the fifth asset, built from build\msvc|mingw|common
```

Nothing above is pinned to a checkout location: every script derives the repo
root from its own path (`%~dp0`, `$PSScriptRoot`, `${BASH_SOURCE[0]}`) and
accepts `WINKIT_ROOT` / `-Root` as an override. The toolchain location is
discovered too — `vswhere` for MSVC, the `Release_*` directory name that
`win/rules.vc` computes from `_MSC_VER`, and `gcc -dumpmachine` for MinGW —
so a different VS version or toolset is not an obstacle. Absolute paths in
these examples describe one developer machine; see
[`docs/ENVIRONMENT.md`](docs/ENVIRONMENT.md) for what was measured and how.

Two constraints remain, both inherited from upstream rather than chosen here:
the repo path must contain no spaces and no parentheses (Tcl's `makefile.vc`
takes `TCLDIR` as a bare, unquotable nmake macro), and the MinGW chain must
run under MSYS2 bash, not WSL.

## Reproducibility

Two full rebuilds on the reference host produce byte-identical assets: all
five files in `dist/` matched across a complete `ext2 → kit → assemble → docs`
double pass (2026-10-28). Treat that as a rule to keep, not as a property you
may spend. Three things had to be pinned to get there, and each is a place
where a new line of code can put the wall clock back in:

| what | mechanism | where |
|---|---|---|
| ZIP entry times | pinned to the 1980-01-01 DOS epoch, **directory entries included** | `scripts/zip-entry.ps1` |
| `generated:` in `VERSIONS.txt` | committer date of `HEAD`, or `SOURCE_DATE_EPOCH` if set | `scripts/build-docs-artifact.ps1` |
| PE `TimeDateStamp` | MSVC `-Brepro` (stamp becomes a hash of the image); MinGW `SOURCE_DATE_EPOCH=315532800` | `scripts/build-msvc-kit.bat`, `scripts/build-mingw-kit.sh` |

So, concretely: no `Get-Date`, no `__DATE__`/`__TIME__`, and no
`git rev-parse` output reaching anything we ship. The last one is not
hypothetical — `rl_json` and `itk` both derive their version UUID from
`git rev-parse HEAD` run inside the vendor tree, which lives inside this
checkout, so before it was pinned the shipped executables carried a commit
hash of **this** repository and served it through `rl_json::build-info commit`
and `itk::build-info commit`. Both now report `unknown`, which is exactly what
upstream's own fallback writes when no version control is present. See
[`patches/README.md`](patches/README.md) for the mechanism and
[`docs/SOURCES.md`](docs/SOURCES.md) for what `manifest.uuid` does and does
not prove.

Reproducibility is measured per toolchain, not across them: the two chains do
not agree on the timestamp value (nor on any other byte), and a rebuild with a
different compiler version is expected to differ. What is verified is that the
same host and toolchain rebuild to the same bytes.

## Conventions that are easy to break

**Encoding has three levels and they are not the same rule.** The full table,
with the measurement behind each row, is [`docs/CONVENTIONS.md`](docs/CONVENTIONS.md);
the defects and decisions it grew out of are in
[`docs/CONVENTIONS-HISTORY.md`](docs/CONVENTIONS-HISTORY.md), and how the gates
verify the tree is in [`docs/CONVENTIONS-CI.md`](docs/CONVENTIONS-CI.md).
What you need to obey while editing:

1. **In the index: LF, always.** `* text=auto eol=lf` in `.gitattributes`
   normalizes every tracked file, so blobs, diffs and a Linux checkout are
   identical regardless of who committed what. Nothing in the repository is
   binary today; if a binary ever arrives, it needs an explicit `-text` rule,
   because `text=auto` guesses from content and a misdetected binary gets
   bytes rewritten.
2. **In the working copy: LF, except `.bat` and `.ps1`, which are CRLF.**
   Those two are the only exception because `cmd.exe` and Windows PowerShell
   5.1 read them in their final resting place; the blob stays LF either way.
   `.editorconfig` says the same thing, so an editor will not fight it.
3. **In what we ship: LF, no BOM** — for every file we generate ourselves
   (`dist\`, the zipfs image, the docs archive, the release body,
   `SHA256SUMS.txt`).

Write generated text with
`[System.IO.File]::WriteAllText($path, $text, $Utf8NoBom)` and build line
endings explicitly as `` "`n" ``. These primitives look equivalent and are not,
each verified against this repository's own output:

| do not use | what it actually produces |
|---|---|
| `Set-Content` / `Out-File` / `Add-Content` with `-Encoding UTF8` | BOM **and** CRLF on PowerShell 5.1 |
| `>` / `>>` redirection | UTF-16LE |
| `[System.IO.File]::WriteAllLines` | `Environment.NewLine`, i.e. CRLF on Windows |
| `[System.IO.File]::WriteAllText` with no encoder argument | UTF-8 without BOM, but whatever endings you handed it |

`publish-release.ps1` and `build-docs-artifact.ps1` each carry a local
`Put-LfText` helper for exactly this reason. A CRLF `SHA256SUMS.txt` is not
cosmetic either: it makes the `sha256sum -c SHA256SUMS.txt` line printed in
both READMEs fail on every non-Windows machine, and a blank separator line in
that file is a hard failure under `--strict`.

**Vendor material is as-is.** Third-party license texts are copied
byte-verbatim by `scripts/make-licenses.ps1`; git normalizes line endings and
nothing else happens to them — no trimming, no re-wrapping, no re-encoding, no
typo fixes. A vendor UTF-8 BOM is **kept**, not stripped: we do not edit
another project's release material, so `-Check` reports each such file instead
of silently changing it. The same logic covers the files we only re-point
inside the docs archive: `build-docs-artifact.ps1` inserts its anchor line
using whatever ending that file already uses, so our edit never leaves a
mixed-EOL file behind.

**Scripts and generated docs are UTF-8 without BOM; `.ps1` and `.bat` are
ASCII-only, comments included.** Windows PowerShell 5.1 decodes a BOM-less
`.ps1` using the machine code page, so non-ASCII bytes become mojibake and a
parse error. On a DBCS code page (932/936/950) it is worse than unreadable:
the lead byte of a double-width character swallows the following ASCII byte,
so a comment that is harmless on a Latin machine breaks parsing on another.
That is why the em dash in a comment counts as a violation, not just Cyrillic
in a string. Non-ASCII data belongs in UTF-8 side files (templates, regex
lists, documents) that the script reads explicitly with
`[System.Text.UTF8Encoding]::new($false)`.

**Two variables named `$L` and `$l` are the same variable.** PowerShell is
case-insensitive; a loop variable that differs from a collection only in case
silently replaces the list with a string.

**`ZipFile::CreateFromDirectory` writes backslash entry names under
PowerShell 5.1**, so both assemblers and the docs builder construct
`/`-separated entries by hand. Keep it that way or archives become
unportable.

**Relative paths in .NET calls resolve against the process directory, not
PowerShell's.** `cd` does not move `[System.IO.File]::ReadAllText`. Pass
absolute paths.

## Vendor patches

Every modification of upstream code is declared in
[`patches/patches.json`](patches/patches.json) — one entry per file, naming the
operations and the pristine and final SHA-256 — and gets a row in the table in
[`patches/README.md`](patches/README.md), the human index. An undeclared edit of
a vendor tree does not exist: `apply-patches.ps1 -VerifyOnly` fails on it, and so
does `make-patches.ps1 -Check`. Rules:

- A modified file stays under the **original** license. No separate rights
  are claimed and copyright headers are never removed.
- The `WINKIT:` marker is reserved for changes in **test logic** (a legacy
  expectation that Tcl 9 / Tk 9 / Windows invalidates) — three files, measured
  2026-10-30. It is not stamped into library code, because marking is required
  only when new terms are applied, and they are not. Where a library change is
  not self-evident from its diff, the patch carries an ordinary lowercase
  `winkit` comment instead (four files, plus both makefiles).
- Where upstream simply has no copyright header (`rl_json.c`, `names.c`,
  `scopedobject.itcl`), none is invented and no holder is guessed.
- Patches should be minimal and each one must say what it fixes. A patch
  that only silences a compiler warning belongs in the build script instead.
- Never hand-edit a `*.patch`: `make-patches.ps1 -Write` recomputes it from two
  trees, so an authored hunk is overwritten on the next run. Edit the tree,
  regenerate, and let `-Check` agree.
- Line endings are a declared operation (`canon.eol = lf`), not diff bytes. A
  CR that survives into a `.patch` is a bug in the generator, not a cosmetic
  issue: `git apply` matches hunk context byte for byte.

## Continuous integration

CI is two workflows, split so that the expensive job never runs for a
docs-only push. `.github/workflows/encoding.yml` runs on **every** push (it is
cheap — selftest, encoding gate, link audit, source parity, dry unpack — and it
is the canary). `.github/workflows/sources.yml` runs only when one of the
vendor / patching inputs actually changed: `scripts/fetch-vendor.ps1`,
`scripts/unpack-vendor.ps1`, `scripts/vendor-layout.json`,
`scripts/apply-patches.ps1`, `scripts/make-patches.ps1`, `patches/**`,
`vendor/manifest.json`, or `.gitattributes`. `docs/SOURCES.md` deliberately is
**not** a trigger — its manifest rows live in `fetch-vendor.ps1` and the parity
check runs in the encoding job. The 15 archives are cached between runs
(`actions/cache`, keyed on `scripts/fetch-vendor.ps1` +
`vendor/manifest.json`), so a manifest bump re-downloads only the moved
component and the other 14 come from cache; `fetch-vendor.ps1` still
re-verifies size/SHA-256/archive-shape of every entry, cached or not. Both
jobs' scripts were executed on a real fresh clone of this repository before
ci.yml was split — a job that has never run anywhere is not a guarantee, it is
a promise — and the clone run is what exposed two defects in
`fetch-vendor.ps1` and the silent-skip behaviour of the artifact sections:

| Job | What it runs | What it proves |
|---|---|---|
| `encoding` | `scripts\check-gates-selftest.ps1`, then `scripts\check-encoding.ps1`, `scripts\link-audit.ps1`, `scripts\source-parity.ps1` | first that the four gates are able to fail and to name the right defect, then the three-level encoding rule (index/blob/worktree) plus the PE `TimeDateStamp` and builder-state gates when artifacts exist, then that every relative link and `#fragment` in the tracked markdown resolves, then that `docs\SOURCES.md` publishes exactly what `scripts\fetch-vendor.ps1` fetches |
| `sources` | `scripts\fetch-vendor.ps1`, then `-VerifyOnly`, then `scripts\unpack-vendor.ps1` (both chains), a pristine snapshot of `build\`, then `scripts\apply-patches.ps1 -Chain msvc`, `-VerifyOnly`, and `scripts\make-patches.ps1 -Check` | step zero: all 15 archives are present and pass size, SHA-256 and archive-shape checks (the second fetch run proves idempotence with no network); step 1: the trees unpack to the fixed layout; step 2: the manifest applies cleanly; step 3: `-Check` recomputes the hashes and bytes from pristine vs patched and agrees with `patches.json` — all of it with no compiler |

**What CI does not do, and why.** There is no build job, and it is no longer
because patching was manual — the `sources` job already runs
`unpack-vendor` → `apply-patches` → `-VerifyOnly` → `make-patches -Check`.
The blocker is the compilers: MSVC needs an x64 Native Tools prompt,

**What CI does not do, and why.** There is no build job, and it is no longer
because patching was manual — steps 0–2 are scripted, and `sources` already holds
all 15 archives, so `unpack-vendor` → `apply-patches` → `-VerifyOnly` could run
there today. The blocker is the compilers: MSVC needs an x64 Native Tools prompt,
MinGW an MSYS2 login shell with `MSYSTEM` set, and a job that built only one of
the two would prove less than the local rule, because the kit is the pair. The
test gates in *Testing* below run against built executables for that same reason:
they are local, not CI. BUILDING.md (_Why there is no CI build job_) has the
longer version, including the two legs that could be added without either
toolchain and why neither is wired up yet.

On a CI checkout the three artifact sections of `check-encoding.ps1` **skip
loudly** rather than pass silently; `-RequireArtifacts` turns each skip into a
failure and is what the local pre-publish run uses. The exit code of every
script here is the number of failed assertions, so a step fails on its own and
the workflow parses no logs.

```
scripts\check-gates-selftest.ps1               # negative control for the gates
scripts\check-encoding.ps1 -RequireArtifacts   # pre-publish: skips become failures
scripts\verify-docs-artifact.ps1               # the fifth artifact (local: needs dist/)
scripts\link-audit.ps1                         # every tracked markdown link resolves
scripts\source-parity.ps1                      # docs\SOURCES.md == fetch-vendor.ps1
```

**Why the selftest runs in CI and not only locally.** This job is the one place
where the artifact sections have nothing to look at, so it is also the one place
where a section that skipped silently would go unnoticed. The rule in *Testing*
— every "check passed" needs a negative control — applies to the checkers
themselves, and a checker whose failure has only ever been read about in a
document is not a checker. It costs 56 seconds on a bare checkout and 60 to 63
on a full one: it builds throwaway repositories and archives under `build/`
(gitignored) carrying exactly one injected defect each, requires the valid
baseline to pass, then requires each defect to produce a nonzero exit **and**
the specific assertion named. 34 injected defect classes — 16 for the two
encoding gates (12 table-driven, plus a `.ps1` that is ASCII-and-CRLF-correct
but does not parse, plus three on the release checksum list: a header that lost
two of its three lines, an empty separator line, and a CRLF list), 6 for the
link audit, 12 for the source-map parity check —
and 6 guards that a leg actually ran: missing artifacts under
`-RequireArtifacts`, a zero-tracked-file repository, a missing archive, a
markdown set whose anchors were never resolved, a manifest whose notation was
not understood at all, and a source map with no URL-bearing rows. The last two
are also among the 31, because there the injected defect *is* that the parser
understood nothing. 126 assertions on a full tree, 124 on a
bare checkout: two of them need the built artifacts and print a skip instead.

**Why the two documentation gates are in CI.** `link-audit.ps1` and
`source-parity.ps1` were scratch tools until this change, and they moved into
`scripts/` in the same commit that states their result in a tracked document.
The reason is the rule above: the repository now publishes "every cross-link in
the markdown resolves" and "the vendor map publishes exactly what the manifest
fetches", and a published claim whose evidence lives in a gitignored directory
is not evidence — a reader cannot re-run it, and whoever edits
`docs\SOURCES.md` next cannot check the edit. Together they cost six seconds,
which is why they are two more steps of the existing `encoding` job rather than
a third job.

`verify-docs-artifact.ps1` is the exception to being in CI: it checks entry
pinning, the manifest cross-check, license byte-identity and the `VERSIONS.txt`
stamp of the fifth artifact, and on a checkout there is no archive to check. Its
negative control is in the selftest, which builds synthetic archives instead.

Both jobs are `windows-latest` only. A second OS would be the honest test of
the `.gitattributes` normalization, but the reference machine has no Linux, no
PowerShell 7 and no container, so that leg has never executed anywhere and
shipping it would put an unexercised promise in public. It is tracked as a
post-flip item instead.

## Testing

Gates run against the **shipped** executables, not against a build tree:

```
dist\msvc\tclwin.exe     tests\smoke.tcl               # SMOKE OK
dist\msvc\tkwin.exe      tests\smoke.tcl
dist\mingw\tclwin.exe    tests\smoke.tcl
dist\mingw\tkwin.exe     tests\smoke.tcl

dist\msvc\tclwin.exe     tests\tcllib-probe.tcl        # PROBE OK
... each of the four
dist\msvc\tclwin.exe     tests\kit-license-check.tcl   # KIT LICENSE CHECK OK
... each of the four

scripts\test-repl.ps1       # interactive REPL: key injection, history, completion
```

Expected numbers on a healthy build:

| Gate | Console kit | GUI kit |
|---|---|---|
| `tcllib-probe` | 439 offered / 384 loaded / 55 failed, all 55 known-upstream, **0 NEW** | 571 / 508 / 63 known, **0 NEW** |
| `smoke` | `SMOKE OK` (36 checks) | `SMOKE OK` (adds Img PNG, tklib, Tk widgets, Itk, Iwidgets, tkdnd, Treectrl) |
| `kit-license-check` | `KIT LICENSE CHECK OK` (Tk layer skipped) | `KIT LICENSE CHECK OK` (17 paths + 11 phrase probes) |

One `smoke` check reports a value rather than a verdict: `tdbc odbc` drives a
real ODBC round-trip (connect, metadata, `SELECT`, and a prepared statement with
a bound parameter) through the file-based Text driver that client Windows
ships. On a host without any such driver it prints
`skipped: no ODBC text driver (drivers seen: N)` and still counts as passing,
because `smoke.tcl` has no skip state — so read that line rather than trusting
the `SMOKE OK` alone when the ODBC leg matters to you.

Vendor suite baselines, for comparison after any change to `patches/` or to
staging: iwidgets 3308/3308 passed, itk 100/100, Img 290/272/18 skipped,
Treectrl 1236/1216/19 skipped/1 failed (upstream `itemdesc`), rl_json
2565/2562/3 skipped, mpexpr clean (`MPEXPR-DONE`), itcl 793/727/66 skipped,
thread 143/117/26 skipped, tdbc 13/13, tdbc::sqlite3 161/158/3 skipped.

**`tests/tcllib-probe.baseline.txt` is regenerated with a stock
interpreter**, never with a kit:** the kit cannot be its own reference for
what the unpruned tree offers.

```
build\msvc\tcl9.0.4\win\Release_AMD64_VC1951\tclsh90s.exe tests\tcllib-probe.tcl -baseline
```

The baseline comes from unpruned source trees (576 packages / 415 loaded) and
is **not byte-comparable** to kit output — compare the summary line only.
This is deliberate: an upstream failure that a kit also has must be excused,
and a new failure must be impossible to hide.

Adding a package to the kit means, in one change: static registration in
`src/kit/kit_register.c`, version and aliases in
`src/kit/vfs/lib/kit_init.tcl`, staging rules in both `assemble-*.ps1`,
prune rules if the package ships non-runtime bulk, a `tests\smoke.tcl` check,
a license row in `THIRD-PARTY-NOTICES.md`, an entry in
`scripts/make-licenses.ps1`, and — if the package carries a mandatory
license text — a path in `tests\kit-license-check.tcl`'s `want` list.

## Licenses

`LICENSES/` is generated by `scripts/make-licenses.ps1` and must never be
edited by hand; `THIRD-PARTY-NOTICES.md` is the authority and the generated
sweep is evidence of coverage. The regex sweep misses hand-verified cases on
purpose (a dual-licensed module, a file whose label says MIT while its text
says otherwise, holder lists that live only in `.man` pages). When you touch
vendor material:

```
scripts\make-licenses.ps1            # regenerate
scripts\make-licenses.ps1 -Check     # verify against vendor sources, CI mode
```

`-Check` compares content with line endings normalised, because vendor files
ship CRLF while the repository pins LF, and it reports (without failing on) any
vendor file that carries a UTF-8 BOM, since that BOM is preserved verbatim.

Pruning never removes license texts: `scripts\kit-prune.ps1` keeps them by
filename rule (`$KitLicenseNames`), evaluated before the extension cut, and
`tests\kit-license-check.tcl` proves they survive into the mounted image of
the finished exe. If you add a prune rule, add the negative control for it
(remove a text, expect a failure) before you trust the rule.

## Releases

Version numbers live in exactly one place: `variable version` in
`src/kit/vfs/lib/kit_init.tcl`.

```
scripts\publish-release.ps1 -DryRun   # does every local step, touches neither GitHub nor refs
scripts\publish-release.ps1           # annotated tag + release + 5 assets + SHA256SUMS.txt
```

The publisher renders `src/docs/release-notes.md` (`{{PLACEHOLDER}}` tokens
substituted from the built artifacts), requires a clean working tree, refuses
to move a tag that a published release already points at, and with `-Force`
replaces same-named assets. Names in the release carry version and
architecture (`tclwinkit-<version>-msvc-x64-console.exe`, where `<version>` is
`variable version` in `src/kit/vfs/lib/kit_init.tcl`); `dist/` keeps short
names and, because those carry no toolchain, one subdirectory per toolchain
(`dist\msvc\tclwin.exe`, `dist\mingw\tkwin.exe`).

To re-issue a release at a different commit, delete the release and its tag
first — that is the only sanctioned way past the refusal, and it is only
acceptable while downloads are demonstrably zero.

## Pull requests

- State what problem the change solves and which gate proves it.
- Two toolchains, four executables: a change that only builds on one is not
  ready.
- Do not reformat vendor files, do not sort `LICENSES/`, do not "clean up"
  generated trees — the diffs are unreadable and `-Check` will fight you.
- New documentation belongs in the language of its neighbourhood: process
  documents English, internal documents Russian.
- Translations of the README are welcome as their own pull request with the
  `i18n` label; machine translation is not accepted (see the README's
  translations section for why it fails here specifically).
