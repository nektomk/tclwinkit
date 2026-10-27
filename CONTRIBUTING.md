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
| `patches/` | vendor modifications, one directory per package, indexed in `patches/README.md` |
| `LICENSES/` | generated — never hand-edit |
| `build/` | gitignored: toolchain output, staging trees, and all scratch work |

`build/research/` is scratch. Log directories, throwaway checkers, draft
documents, audit output — none of it is published, and nothing tracked
should link to it. If a scratch tool earns its keep, promote it to
`scripts/` or `tests/` in the same change that adds the link.

## Building

Both toolchains produce the same kit; a change is not done until it builds
on both.

MSVC (x64 Native Tools prompt, or `vcvars64.bat` first):

```
scripts\build-msvc-core.bat     # Tcl+Tk+pkgs: nmake OPTS=static,nomsvcrt
scripts\build-msvc-ext.bat      # dyncall 0.9 + TWAPI 5.2.0
scripts\build-msvc-img.bat      # Img 2.1.2: base, support, 19 formats
scripts\build-msvc-ext2.bat     # rl_json, mpexpr, itk, tkdnd, treectrl
scripts\build-msvc-kit.bat      # kit glue objects + link the exe
scripts\assemble-msvc-kit.ps1   # stage VFS -> zip -> attach -> dist\
```

MinGW (MSYS2 UCRT64; the script needs a login shell):

```
$env:MSYSTEM = 'UCRT64'
C:\msys64\usr\bin\bash.exe -lc '/c/path/to/winkit/scripts/build-mingw-core.sh'
C:\msys64\usr\bin\bash.exe -lc '/c/path/to/winkit/scripts/build-mingw-ext.sh'
C:\msys64\usr\bin\bash.exe -lc '/c/path/to/winkit/scripts/build-mingw-ext2.sh'
C:\msys64\usr\bin\bash.exe -lc '/c/path/to/winkit/scripts/build-mingw-kit.sh'
scripts\assemble-mingw-kit.ps1
```

Then, once both trees exist under `build/`:

```
scripts\make-licenses.ps1          # regenerate LICENSES/ (or -Check to verify)
scripts\build-docs-artifact.ps1    # the fifth asset, built from build\msvc|mingw|common
```

The absolute paths above are examples of one developer machine; nothing here
is pinned to a checkout location yet, and that is a known gap (tracked as
build hygiene, see [`docs/ENVIRONMENT.md`](docs/ENVIRONMENT.md)).

## Conventions that are easy to break

**Encoding has three levels and they are not the same rule.** The full table,
with the measurement behind each row, is [`docs/CONVENTIONS.md`](docs/CONVENTIONS.md);
what you need to obey while editing:

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

Every modification of upstream code lives in `patches/<pkg>/` and gets a row
in the table in [`patches/README.md`](patches/README.md) — the table is the
index, and an unindexed patch does not exist. Rules:

- A modified file stays under the **original** license. No separate rights
  are claimed and copyright headers are never removed.
- The `WINKIT:` marker is reserved for changes in **test logic** (a legacy
  expectation that Tcl 9 / Tk 9 / Windows invalidates). It is not stamped
  into library code, because marking is required only when new terms are
  applied, and they are not.
- Where upstream simply has no copyright header (`rl_json.c`, `names.c`,
  `scopedobject.itcl`), none is invented and no holder is guessed.
- Patches should be minimal and each one must say what it fixes. A patch
  that only silences a compiler warning belongs in the build script instead.

## Testing

Gates run against the **shipped** executables, not against a build tree:

```
dist\tclwinkit-msvc.exe     tests\smoke.tcl               # SMOKE OK
dist\winkitwish-msvc.exe    tests\smoke.tcl
dist\tclwinkit-mingw.exe    tests\smoke.tcl
dist\winkitwish-mingw.exe   tests\smoke.tcl

dist\tclwinkit-msvc.exe     tests\tcllib-probe.tcl        # PROBE OK
... each of the four
dist\tclwinkit-msvc.exe     tests\kit-license-check.tcl   # KIT LICENSE CHECK OK
... each of the four

scripts\test-repl.ps1       # interactive REPL: key injection, history, completion
```

Expected numbers on a healthy build:

| Gate | Console kit | GUI kit |
|---|---|---|
| `tcllib-probe` | 439 offered / 384 loaded / 55 failed, all 55 known-upstream, **0 NEW** | 571 / 508 / 63 known, **0 NEW** |
| `smoke` | `SMOKE OK` (~35 checks) | `SMOKE OK` (adds Img PNG, tklib, Tk widgets, Itk, Iwidgets, tkdnd, Treectrl) |
| `kit-license-check` | `KIT LICENSE CHECK OK` (Tk layer skipped) | `KIT LICENSE CHECK OK` (17 paths + 11 phrase probes) |

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
architecture (`tclwinkit-0.1-msvc-x64-console.exe`); `dist/` keeps short
names.

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
