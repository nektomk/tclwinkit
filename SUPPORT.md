# Support

## Where to ask

| Question about | Where |
|---|---|
| the kit itself — bootstrap, zipfs mounting, packaging, REPL shim, prune behaviour, missing `package ifneeded`, exe size, toolchain differences | [Issues](https://github.com/nektomk/tclwinkit/issues) here |
| Tcl or Tk the language and core — semantics, `chan`, `interp`, `ttk`, image handling, a core bug repro | [core.tcl.org](https://core.tcl.org/tcl/index) tracker, or `comp.lang.tcl` |
| a bundled package (tcllib, tklib, TWAPI, Img, tdbc, rl_json, mpexpr, tkdnd, Treectrl, Itcl, Itk, Iwidgets, CAWT, TclReadLine) | that package's upstream first, here too if the kit may be at fault |
| general Tcl discussion, idioms, "how do I do X in Tcl" | [Tcler's Wiki](https://wiki.tcl-lang.org) discussion pages, `comp.lang.tcl`, the Tcl Discord/Slack bridges |

The distinction matters because this project is a **distribution**: most
"my code broke" reports turn out to be upstream behaviour, and most
"this package is missing" reports are a packaging decision documented in
[`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md) or
[`docs/NOTES.md`](docs/NOTES.md). Filing here first is still fine — triage
costs nothing and routes the report.

## What to include in an issue

1. Which file you ran: `tclwin.exe` or `tkwin.exe`, from which archive
   (`tclwinkit-msvc-….zip` or `tclwinkit-mingw-….zip`), and the version —
   `set winkit::version` in the kit, or the `v…` tag / release asset name it
   came from.
2. `tcl_platform(osVersion)`, `tcl_platform(machine)`, and whether the
   console or GUI build.
3. The smallest script that shows it. Tcl is happy to be reduced; a
   10-line repro is worth an hour of back-and-forth.
4. What stock `tclsh`/`wish` from the same major version does, if you have it
   — it immediately separates "kit defect" from "upstream behaviour".
5. For loading problems: the output of `package require <name>` **and**
   `package present <name>`, plus `set auto_path`.

Useful one-liners, all verified against the shipped `0.1` executables:

```tcl
info patchlevel        ;# 9.0.4 -- the Tcl the kit actually reports
set ::winkit::version  ;# 0.1   -- the kit version from lib/kit_init.tcl
package names          ;# 54 eagerly registered names (console), 691 (GUI)
zipfs mount            ;# //zipfs:/app <path-to-exe> -- what is attached
tcl::tm::path list     ;# the tm roots the image offers (4 in console)
package present Tcl    ;# 9.0.4
```

`zipfs mount` is the fastest way to tell "the archive did not attach" from
"the package is not in the image": the former lists no `//zipfs:/app`, the
latter lists it but `package require` still fails.

## Expectations

Unpaid hobby project, one maintainer, no SLA. Issues are read; a fix usually
means "a bundled component was updated and the kit rebuilt", so timing
follows upstream more than it follows this tracker. If something is
security-relevant, use [`SECURITY.md`](SECURITY.md) instead of an issue.

## Documentation languages

Process documents (`README.md`, `CONTRIBUTING.md`, `SECURITY.md`,
`SUPPORT.md`, `CHANGELOG.md`, issue and PR templates) are English. Internal
engineering documents ([`docs/`](docs/), [`patches/README.md`](patches/README.md))
are Russian, because that is the language they are maintained in. The
Russian README is [`README.ru.md`](README.ru.md). Translations of the
showcase documents are welcome — see the `i18n` label.
