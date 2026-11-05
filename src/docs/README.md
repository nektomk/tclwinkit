# tclwinkit docs archive

The fifth artifact of the tclwinkit build: the four executables carry runtime
only, and everything pruned out of them — license texts, manual pages, HTML
documentation, demos and changelogs of the bundled components — is published
here instead. Unpack it anywhere; all paths inside are relative.

Read `THIRD-PARTY-NOTICES.md` first: it is the mandatory attribution for every
third-party component in the kit. `LICENSE` covers our glue only, and
`LICENSES/` holds the individual license texts, generated from the vendor
trees. `MANIFEST.txt` lists every file in the archive, `VERSIONS.txt` names the
versions it was built from.

```tcl
tclwinkit-msvc.exe  tools\man.tcl man\tcl\subst.n   ;# read a man page
winkitwish-msvc.exe demos\tk\widget                 ;# browse the Tk demos
```

The console kit (`tclwinkit`) has no Tk — use `winkitwish` for anything that
draws a window. Most Tk demos are pages of a browser rather than standalone
programs, so enter through `demos\tk\widget`, `demos\iwidgets\catalog` or
`demos\treectrl\demo.tcl`; the iwidgets demos are the exception and start
directly. The `Excel-*`/`Word-*`/`Ppt-*` CAWT demos drive real Office
applications over COM and need them installed.

Paths of the form `scripts/...`, `tests/...`, `docs/...` name files in the
[source repository](https://github.com/nektomk/tclwinkit), not in this archive;
`man/`, `html/`, `demos/`, `docs/`, `tools/` and `LICENSES/` are here.
