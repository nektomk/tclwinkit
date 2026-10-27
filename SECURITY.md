# Security policy

## Reporting a vulnerability privately

Use **GitHub private vulnerability reporting** for this repository: the
**Security** tab → **Report a vulnerability**. That opens a private advisory
visible only to you and the maintainers, it gets a CVE-request option, and it
keeps the discussion out of the public issue tracker.

If private reporting is unavailable to you for some reason, open an issue
that contains **no** exploit details — just "please see the private advisory
for X" — and send the details separately once a private channel exists. Do
not file a public issue describing an exploitable defect.

There is no mailing list and no encrypted-mail fingerprint for this project
at the moment; the maintainer identity in the git history is a service
account, so do not try to reach a person through it.

## What counts as in scope

`tclwinkit` is a **distribution**, not an interpreter upstream. The split
decides where a fix belongs:

| Area | In scope here | Belongs upstream |
|---|---|---|
| Kit bootstrap: `src/kit/*.c`, `kit_init.tcl`, `pkgIndex.tcl`, zipfs mounting | yes | — |
| REPL and its Win32 shim (`TclReadLine` + `tclreadline-win.tcl`) | yes (the shim is ours) | TclReadLine proper |
| Packaging: what the prune keeps or drops, the docs archive, `SHA256SUMS.txt` | yes | — |
| Build flags: static CRT, `-static`, `/d1trimfile`, path leakage in binaries | yes | — |
| Tcl / Tk core defects | — | `tcltk` upstream ([core.tcl.org](https://core.tcl.org) tracker) |
| Bundled package defects (tcllib, tklib, TWAPI, Img, tdbc, rl_json, mpexpr, tkdnd, Treectrl, Itcl, Itk, Iwidgets, CAWT) | — | that package's upstream |

Report the bundled cases here anyway if you are unsure — a distribution
problem can look like an upstream one (for example, a package that fails to
load because static registration was forgotten, or a stripped file that a
package needs at runtime). We triage and, when the defect is upstream, we
forward it and track the release that fixes it.

## Response expectations

- **Acknowledgement**: we try within 5 business days. This is an unpaid
  hobby project with one maintainer; please do not assume an SLA.
- **Fix path for upstream defects**: a bundled component is updated to an
  upstream release that contains the fix, then all four executables and the
  docs archive are rebuilt and republished. There is no patch pipeline into
  vendor code beyond the small, indexed set in [`patches/README.md`](patches/README.md),
  and no intention to grow it.
- **Latency**: bounded by upstream, not by us. Tcl and Tk ship patch
  releases on their own cadence, and Img, tcllib or tklib much less often;
  a `tclwinkit` release usually follows the upstream one within days, but
  that is a habit, not a promise.
- **Supported versions**: the **latest release only**. `0.1` is the first
  one; nothing backports, no LTS branch. If you are pinned to an older
  release, upgrading the whole kit is the remedy.
- **Embargo**: we do not run an embargo programme. If you need coordinated
  disclosure, say so in the advisory and we will do our best to hold a
  release until your notice date, within the constraints above.

## Credits

Reporters who want to be named are named in the release notes and in
`CHANGELOG.md`. Say so in the advisory if you prefer anonymity.

## Known non-issues

Things a scanner or a first read of the tree tends to flag, which are **not**
vulnerabilities and will be closed as such:

- **tcllib `devtools` certificate material** (`ca.crt`, `ca.key`,
  `ca.key.password`, `receiver.*`, `transmitter.*`, `recreate-certs`) ships
  in the kit image at `//zipfs:/app/lib/tcllib2.0/devtools/` because it is
  part of the published tcllib 2.0 release and we do not edit another
  project's release tree. Those are **test fixtures** for tcllib's own test
  suite (304 `.test` files reference the `devtools` package; the bundled
  `recreate-certs` script regenerates them with `package require pki`), they
  are not service credentials, they are not trusted by anything in this kit,
  and they grant access to nothing. Verified in the shipped `0.1` image:
  13 entries in that directory, key material included. See
  THIRD-PARTY-NOTICES.md §7 for the licensing rationale.
- **Two toolchains for one kit** is a distribution decision, not a
  duplicate-code risk: MSVC is the officially supported Windows build of
  Tcl, MinGW is the alternative, and shipping both makes a toolchain problem
  visible instead of fatal.
- **Paths baked into binaries** (`__FILE__` strings reachable from panic
  messages) contain no user name or host name. Trimming them is tracked as
  build hygiene, not as a secret leak.
- **The kit is writable-by-design**: it is a single file you can copy
  anywhere. Nothing in it escalates, installs a service, or persists outside
  the documented `~/.tclline_history` / `~/.tcllinerc` / `~/winkitrc.tcl`
  files. If a bundled package does something else, that is package behaviour.
