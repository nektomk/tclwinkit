# Bundled third-party licences

Every file here is generated from the vendor sources by
[`scripts/make-licenses.ps1`](../scripts/make-licenses.ps1) -- nothing is
hand-typed, so each text is verbatim from upstream. Do not edit files
in this directory; change the generator instead, then re-run it. Pass
`-Check` to verify the tree against the vendor sources without writing
(that is what CI does).

* `*/license.terms`, `*/LICENSE*`, `*/README`, `*/COPYRIGHT.txt` -- copied
  verbatim from the upstream tree. Line endings are normalised by git
  (`.gitattributes` pins this directory to LF), so a handful of vendor
  files that ship CRLF land in the repository as LF; their content is
  unchanged, and `-Check` compares content with EOL normalised.
* `*.NOTICE` -- compiled by us from source-file headers, because those
  licences ship no file of their own. Each block is quoted verbatim and
  carries the path and line range it came from.
* `kit-headers/*.NOTICE` -- the full in-file audit of every source that
  actually ships inside the kit: classification, every header that carries
  its own licence grant, and the set of distinct copyright holders.

See [`THIRD-PARTY-NOTICES.md`](../THIRD-PARTY-NOTICES.md) for what each
licence obliges us to reproduce and where that obligation comes from.
