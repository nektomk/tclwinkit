# make-licenses.ps1 -- generate the tracked LICENSES/ tree from vendor sources.
#
# Everything under LICENSES/ is produced here, never hand-typed, so that each
# text is byte-verbatim from its upstream source and each extraction is
# reproducible. Run after a fresh build (vendor trees must exist):
#
#     powershell -NoProfile -ExecutionPolicy Bypass -File scripts\make-licenses.ps1
#     powershell ... -File scripts\make-licenses.ps1 -Check     # CI: verify, don't write
#
# Three parts:
#   A  copy upstream license files verbatim (content-identical; git normalises
#      line endings to LF for this tree, so -Check compares EOL-insensitively)
#   B  extract specific source-header blocks that have no upstream file
#   C  sweep every source file that actually ships in kit.vfs and classify its
#      licence header -- the 100 percent audit, not a sample. Emits, per
#      package: classification counts, verbatim text of every block that
#      carries its OWN grant (i.e. an exception to the package license), and an
#      inventory of distinct copyright holders.
#
# Encoding: upstream files are copied as bytes; generated files are UTF-8
# without BOM, CRLF. This script is ASCII-only (Windows PowerShell 5.1 reads
# BOM-less .ps1 as ANSI).

[CmdletBinding()]
param(
    [string]$Repo,
    [switch]$Check
)

$ErrorActionPreference = 'Stop'
# $PSScriptRoot is not populated during parameter binding on Windows PowerShell 5.1
if (-not $Repo) {
    $here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
    $Repo = Split-Path -Parent $here
}
$Repo = (Resolve-Path -LiteralPath $Repo).Path

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$Lat1 = [System.Text.Encoding]::GetEncoding('iso-8859-1')

$msvc = Join-Path $Repo 'build\msvc'
$common = Join-Path $Repo 'build\common'
$out = Join-Path $Repo 'LICENSES'
$tcl = Join-Path $msvc 'tcl9.0.4'
$tk = Join-Path $msvc 'tk9.0.4'
$ext = Join-Path $msvc 'ext'
$img = Join-Path $ext 'Img-2.1.2'

# ---------------------------------------------------------------- part A ----
$Copy = [ordered]@{
    'tcl-core/license.terms'         = (Join-Path $tcl 'license.terms')
    'tk-core/license.terms'          = (Join-Path $tk 'license.terms')
    'zlib/LICENSE'                   = (Join-Path $tcl 'compat\zlib\LICENSE')
    'libtommath/LICENSE'             = (Join-Path $tcl 'libtommath\LICENSE')
    'minizip/LICENSE.Info-Zip'       = (Join-Path $tcl 'compat\zlib\contrib\minizip\LICENSE.Info-Zip')
    'itcl/license.terms'             = (Join-Path $tcl 'pkgs\itcl4.3.8\license.terms')
    'itcl/doc-license.terms'         = (Join-Path $tcl 'pkgs\itcl4.3.8\doc\license.terms')
    'thread/license.terms'           = (Join-Path $tcl 'pkgs\thread3.0.6\license.terms')
    'sqlite/license.terms'           = (Join-Path $tcl 'pkgs\sqlite3.53.0\license.terms')
    'tdbc/license.terms'             = (Join-Path $tcl 'pkgs\tdbc1.1.13\license.terms')
    # tdbc::sqlite3 ships its own text (Scriptics holders), not a copy of tdbc's
    'tdbc/tdbcsqlite3-license.terms' = (Join-Path $tcl 'pkgs\tdbcsqlite3-1.1.13\license.terms')
    'img/license.terms'              = (Join-Path $img 'license.terms')
    'libpng/LICENSE'                 = (Join-Path $img 'compat\libpng\LICENSE')
    'libtiff/LICENSE.md'             = (Join-Path $img 'compat\libtiff\LICENSE.md')
    'libjpeg/README'                 = (Join-Path $img 'compat\libjpeg\README')
    'itk/license.terms'              = (Join-Path $ext 'itk-4.2.7\license.terms')
    'mpexpr/LICENSE.TERMS'           = (Join-Path $ext 'mpexpr\LICENSE.TERMS')
    'rl_json/LICENSE'                = (Join-Path $ext 'rl_json-0.17.8\LICENSE')
    'tkdnd/license.terms'            = (Join-Path $ext 'tkdnd-2.9.5\license.terms')
    'tktreectrl/license.terms'       = (Join-Path $ext 'tktreectrl-2.5.1\license.terms')
    'twapi/LICENSE'                  = (Join-Path $ext 'twapi-5.2.0\LICENSE')
    'dyncall/LICENSE'                = (Join-Path $ext 'dyncall-0.9\LICENSE')
    'cawt/CAWT-License.txt'          = (Join-Path $common 'cawt-3.1.1\CAWT-License.txt')
    'tcllib/license.terms'           = (Join-Path $common 'tcllib-2.0\license.terms')
    'tcllib/amazon-s3.LICENSE.txt'   = (Join-Path $common 'tcllib-2.0\modules\amazon-s3\LICENSE.txt')
    'tcllib/snit.license.txt'        = (Join-Path $common 'tcllib-2.0\modules\snit\license.txt')
    'tcllib/expander_license.txt'    = (Join-Path $common 'tcllib-2.0\modules\textutil\expander_license.txt')
    'tcllib/comm.LICENSE'            = (Join-Path $common 'tcllib-2.0\modules\comm\comm.LICENSE')
    'tcllib/generator.license.terms' = (Join-Path $common 'tcllib-2.0\modules\generator\license.terms')
    'tcllib/hook.license.terms'      = (Join-Path $common 'tcllib-2.0\modules\hook\license.terms')
    'tcllib/mkdoc.LICENSE'           = (Join-Path $common 'tcllib-2.0\modules\mkdoc\LICENSE')
    'tklib/license.terms'            = (Join-Path $common 'tklib-0.9\license.terms')
    'tklib/ctext.LICENSE'            = (Join-Path $common 'tklib-0.9\modules\ctext\LICENSE')
    'tklib/shtmlview.LICENSE'        = (Join-Path $common 'tklib-0.9\modules\shtmlview\LICENSE')
    'tklib/mentry.COPYRIGHT.txt'     = (Join-Path $common 'tklib-0.9\modules\mentry\COPYRIGHT.txt')
    'tklib/scrollutil.COPYRIGHT.txt' = (Join-Path $common 'tklib-0.9\modules\scrollutil\COPYRIGHT.txt')
    'tklib/tablelist.COPYRIGHT.txt'  = (Join-Path $common 'tklib-0.9\modules\tablelist\COPYRIGHT.txt')
    'tklib/wcb.COPYRIGHT.txt'        = (Join-Path $common 'tklib-0.9\modules\wcb\COPYRIGHT.txt')
    'tklib/widgetl-icons.readme.txt' = (Join-Path $common 'tklib-0.9\modules\widgetl\icons\readme.txt')
    'iwidgets/license.terms'         = (Join-Path $common 'iwidgets-4.1.1\license.terms')
}

# ---------------------------------------------------------------- part B ----
$Extract = [ordered]@{
    'tcl-core/regexpr.NOTICE'         = @(
        (Join-Path $tcl 'generic\regcomp.c'), (Join-Path $tcl 'generic\regexec.c'),
        (Join-Path $tcl 'generic\regerror.c'), (Join-Path $tcl 'generic\regfree.c'))
    'tcl-core/bison-tclDate.NOTICE'   = @( (Join-Path $tcl 'generic\tclDate.c') )
    'tk-core/koblas-gif.NOTICE'       = @( (Join-Path $tk 'generic\tkImgGIF.c') )
    'tk-core/nanosvg.NOTICE'          = @( (Join-Path $tk 'generic\nanosvg.h'),
                                           (Join-Path $tk 'generic\nanosvgrast.h'),
                                           (Join-Path $tk 'generic\tkImgSVGnano.c') )
    'tk-core/x11-headers.NOTICE'      = @( (Join-Path $tk 'xlib\X11\X.h'),
                                           (Join-Path $tk 'xlib\X11\keysymdef.h'),
                                           (Join-Path $tk 'xlib\X11\Xutil.h'),
                                           (Join-Path $tk 'xlib\X11\Sunkeysym.h'),
                                           (Join-Path $tk 'xlib\X11\cursorfont.h') )
    'thread/tclXkeylist.NOTICE'       = @( (Join-Path $tcl 'pkgs\thread3.0.6\generic\tclXkeylist.c'),
                                           (Join-Path $tcl 'pkgs\thread3.0.6\generic\tclXkeylist.h') )
    'minizip/crypt.h.NOTICE'          = @( (Join-Path $tcl 'compat\zlib\contrib\minizip\crypt.h') )
    'libtiff/lzw.NOTICE'              = @( (Join-Path $img 'compat\libtiff\libtiff\tif_lzw.c') )
    'tcllib/filtergen.GPL-NOTICE'     = @( (Join-Path $common 'tcllib-2.0\modules\math\filtergen.tcl') )
    'tclreadline/NOTICE'              = @( (Join-Path $common 'TclReadLine\tclreadline.tcl'),
                                           (Join-Path $common 'TclReadLine\README.md') )
}

# --------------------------------------------------------------- helpers ----
function Read-Lines([string]$path) {
    $bytes = [System.IO.File]::ReadAllBytes($path)
    $text = $Utf8NoBom.GetString($bytes)
    if ($text.IndexOf([char]0xFFFD) -ge 0) { $text = $Lat1.GetString($bytes) }
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $text = $text.Substring(1)
    }
    return ,($text -split "\r?\n")
}

# Vendor texts are copied byte-verbatim, so anything unusual in a source file
# (a UTF-8 BOM, say) is preserved on purpose: we do not edit another project's
# release material. The generator reports it instead, so the exception stays
# visible in the log and in CI rather than turning into a silent surprise.
function Test-Utf8Bom([string]$path) {
    $b = [System.IO.File]::ReadAllBytes($path)
    return ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
}

$Cmt = '^\s*(#|//|/\*|\*|\+|\||;|--|!\[)'
$Grant = '(?i)permission is hereby granted|subject to the following (restrictions|conditions)|redistribution and use in source and binary|GNU GENERAL PUBLIC LICENSE|general public license|public domain|disclaims copyright|bsd licen|mit licen|isc licen|free software; you can use|as freely available as possible|the following terms apply|redistributions in (source|binary) form|this notice is included verbatim|prominently acknowledged|in supporting documentation|without fee'
$Pointer = '(?i)licen[cs]e\.terms|licen[cs]e file|see the file'
$CopyLine = '(?i)^\s*(?:[#/*+|;\-]\s*)?(copyright|\(c\)opyright|\(c\))\s'
$LegalStart = '(?i)^\s*[#/*+\-|;]+\s*(copyright|\(c\)|permission to|the following terms|redistribution and use|this software is)'

function Get-LegalSlice([string[]]$run) {
    # A file's leading comment run usually starts with the module's own
    # description ("Buttonbox -- manages a framed area ..."), which differs per
    # file and carries no licence text. Slice from the first legal line to the
    # end of the run so that files sharing one licence collapse together.
    for ($i = 0; $i -lt $run.Count; $i++) {
        if ($run[$i] -match $LegalStart) { return ,@($run[$i..($run.Count - 1)]) }
    }
    return ,$run
}

function Get-Runs([string[]]$lines) {
    # Contiguous comment runs of >= 2 lines, each returned with its start index.
    $res = New-Object System.Collections.Generic.List[object]
    $runStart = -1
    $cur = $null
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match $Cmt) {
            if ($null -eq $cur) { $cur = New-Object System.Collections.Generic.List[string]; $runStart = $i }
            $cur.Add($lines[$i])
        }
        elseif ($null -ne $cur) {
            if ($cur.Count -ge 2) { $res.Add(@{ start = $runStart; lines = @($cur) }) }
            $cur = $null
        }
    }
    if ($null -ne $cur -and $cur.Count -ge 2) { $res.Add(@{ start = $runStart; lines = @($cur) }) }
    return ,$res.ToArray()
}

function Norm([string[]]$block) {
    $s = ($block -join ' ')
    $s = $s -replace '[#/*+\-]{1,2}', ' '
    $s = $s -replace '\s+', ' '
    return $s.Trim().ToLowerInvariant()
}

function NormLegal([string[]]$block) {
    # Group blocks by their LEGAL body only: drop identification lines (author,
    # e-mail, RCS Id, the copyright line itself) so that the DSC/iwidgets and
    # tcllib header families collapse into one entry each. The names do not get
    # lost -- section 2 of the output lists every distinct copyright line.
    $keep = New-Object System.Collections.Generic.List[string]
    foreach ($l in $block) {
        $t = $l -replace '^\s*[#/*+\-|;]+\s*', ''
        if ($t -match '(?i)^\s*(author|e-?mail|from|version|created|notes|\$[Ii]d|@\(#\))') { continue }
        if ($t -match $CopyLine) { continue }
        if ($t -match '^\s*[<>()\[\].,;:*=-]*\s*$') { continue }
        $keep.Add($t)
    }
    if ($keep.Count -eq 0) { return '' }
    return (Norm $keep.ToArray())
}

function Rel([string]$p) { return $p.Substring($Repo.Length).TrimStart('\').Replace('\', '/') }

# ---------------------------------------------------------------- write -----
$report = New-Object System.Collections.Generic.List[string]
$script:mismatch = 0

function Put-Generated([string]$relDest, [string[]]$content, [string]$origin) {
    $dest = Join-Path $out $relDest
    # LF on disk: this is what git stores for text files, so a checkout on a
    # Linux CI runner is byte-identical to what the generator produced here.
    $text = ($content -join "`n") + "`n"
    if ($Check) {
        if (-not (Test-Path $dest)) { $script:mismatch++; $report.Add("MISSING  $relDest"); return }
        $want = $Utf8NoBom.GetString([System.IO.File]::ReadAllBytes($dest)) -replace "`r`n", "`n"
        if ($want -ne $text) { $script:mismatch++; $report.Add("DIFFERS  $relDest") }
        return
    }
    $dir = Split-Path -Parent $dest
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($dest, $text, $Utf8NoBom)
    $report.Add(('wrote {0,-38} {1,7} B  <- {2}' -f $relDest, $text.Length, $origin))
}

# part A: byte-verbatim copies
foreach ($rel in $Copy.Keys) {
    $src = $Copy[$rel]
    if (-not (Test-Path $src)) { $report.Add('!! MISSING SOURCE: ' + (Rel $src)); $script:mismatch++; continue }
    $dest = Join-Path $out $rel
    if ($Check) {
        if (-not (Test-Path $dest)) { $script:mismatch++; $report.Add("MISSING  $rel"); continue }
        # Compare content with line endings normalised: git checks these out as
        # CRLF when core.autocrlf=true, so a raw hash comparison would fail on
        # a Windows working tree while the committed blob is identical.
        $a = $Utf8NoBom.GetString([System.IO.File]::ReadAllBytes($src)) -replace "`r`n", "`n"
        $b = $Utf8NoBom.GetString([System.IO.File]::ReadAllBytes($dest)) -replace "`r`n", "`n"
        if ($a -ne $b) { $script:mismatch++; $report.Add("CONTENT DIFFERS  $rel") }
        elseif (Test-Utf8Bom $src) { $report.Add("vendor BOM preserved  $rel") }
        continue
    }
    $dir = Split-Path -Parent $dest
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Copy-Item -LiteralPath $src -Destination $dest -Force
    if (Test-Utf8Bom $src) { $report.Add(('  note: source carries a UTF-8 BOM, preserved verbatim: {0}' -f $rel)) }
    $report.Add(('copied {0,-38} {1,7} B  <- {2}' -f $rel, (Get-Item $dest).Length, (Rel $src)))
}

# part B: extracted header blocks (whole leading comment run of each file)
foreach ($rel in $Extract.Keys) {
    $buf = New-Object System.Collections.Generic.List[string]
    $title = $rel -replace '\.NOTICE$', ''
    $title = $title -replace '\.GPL-NOTICE$', ' :: GPL'
    $title = $title -replace '/', ' :: '
    $buf.Add('# ' + $title)
    $buf.Add('# Verbatim extraction of copyright/licence text from upstream source')
    $buf.Add('# headers, because no licence file ships for this component.')
    $buf.Add('# Generated by scripts/make-licenses.ps1 -- do not edit by hand.')
    $buf.Add('')
    foreach ($src in $Extract[$rel]) {
        if (-not (Test-Path $src)) { $buf.Add('## MISSING SOURCE: ' + (Rel $src)); $script:mismatch++; continue }
        $lines = Read-Lines $src
        $runs = Get-Runs $lines
        $buf.Add('## ' + (Rel $src))
        $shown = 0
        foreach ($r in $runs) {
            $txt = $r.lines -join "`n"
            if ($txt -notmatch $Grant) { continue }
            $buf.Add('# --- lines ' + ($r.start + 1) + '-' + ($r.start + $r.lines.Count) + ' ---')
            foreach ($l in $r.lines) { $buf.Add($l) }
            $buf.Add('')
            $shown++
            if ($shown -ge 4) { break }
        }
        if ($shown -eq 0) { $buf.Add('#   (no grant-bearing comment block found in the first runs)') }
    }
    Put-Generated $rel $buf.ToArray() ('extract ' + (($Extract[$rel] | ForEach-Object { Rel $_ }) -join ', '))
}

# ----------------------------------------------------------- part C: sweep --
$kitlib = Join-Path $msvc 'kit\stage\kit.vfs\lib'
$sweepTargets = @('tcllib2.0', 'tklib0.9', 'iwidgets4.1.1')
if (-not (Test-Path $kitlib)) {
    $report.Add('!! staged kit not found: ' + (Rel $kitlib) + ' -- part C skipped')
}
else {
    foreach ($pkg in $sweepTargets) {
        $dir = Join-Path $kitlib $pkg
        if (-not (Test-Path $dir)) { continue }
        $files = @(Get-ChildItem $dir -Recurse -File | Where-Object { $_.Extension -in @('.tcl', '.itcl', '.itk') })

        $cls = @{ pointer = 0; grant = 0; none = 0 }
        $grantBlocks = @{}
        $holders = @{}
        foreach ($f in $files) {
            $lines = Read-Lines $f.FullName
            $runs = Get-Runs $lines
            $rel = $f.FullName.Substring($dir.Length + 1).Replace('\', '/')
            $fileHasGrant = $false
            foreach ($r in $runs) {
                $txt = $r.lines -join "`n"
                # copyright-holder inventory: first copyright line of each run
                foreach ($l in $r.lines) {
                    if ($l -match $CopyLine) {
                        $h = ($l -replace '^\s*[#/*+\-|;]+\s*', '').Trim()
                        $h = $h -replace '\s+', ' '
                        if ($h.Length -gt 4 -and -not $holders.ContainsKey($h)) {
                            $holders[$h] = New-Object System.Collections.Generic.List[string]
                        }
                        if ($h.Length -gt 4) { $holders[$h].Add($rel) }
                        break
                    }
                }
                if ($txt -match $Grant) {
                    $fileHasGrant = $true
                    $sl = Get-LegalSlice $r.lines
                    $off = 0
                    for ($q = 0; $q -lt $r.lines.Count; $q++) {
                        if ($r.lines[$q] -match $LegalStart) { $off = $q; break }
                    }
                    $k = NormLegal $sl
                    if ($k -eq '') { $k = Norm $sl }
                    if (-not $grantBlocks.ContainsKey($k)) {
                        $grantBlocks[$k] = @{ lines = $sl; start = ($r.start + $off)
                                              files = New-Object System.Collections.Generic.List[string]
                                              cpr = New-Object System.Collections.Generic.List[string] }
                    }
                    $grantBlocks[$k].files.Add($rel)
                    foreach ($l in $r.lines) {
                        if ($l -match $CopyLine) {
                            $c = ($l -replace '^\s*[#/*+\-|;]+\s*', '').Trim() -replace '\s+', ' '
                            if ($c -and -not $grantBlocks[$k].cpr.Contains($c)) { $grantBlocks[$k].cpr.Add($c) }
                        }
                    }
                }
            }
            if ($fileHasGrant) { $cls.grant++ }
            elseif (($runs | ForEach-Object { $_.lines -join "`n" }) -join "`n" -match $Pointer) { $cls.pointer++ }
            else { $cls.none++ }
        }

        $buf = New-Object System.Collections.Generic.List[string]
        $buf.Add('# ' + $pkg + ' :: in-file licence audit')
        $buf.Add('#')
        $buf.Add('# Generated by scripts/make-licenses.ps1 from the sources that actually ship')
        $buf.Add('# in kit.vfs (' + $files.Count + ' Tcl/Itcl/Itk files swept, every comment run of')
        $buf.Add('# every file examined -- this is a full audit, not a sample). Do not edit by hand.')
        $buf.Add('#')
        $buf.Add('# Classification:')
        $buf.Add('#   own-grant     ' + $cls.grant + ' file(s) carry a licence grant in their header, quoted below')
        $buf.Add('#   pointer       ' + $cls.pointer + ' file(s) point at the package licence file (the default)')
        $buf.Add('#   no-header     ' + $cls.none + ' file(s) have no licence text and fall under the package')
        $buf.Add('#                 licence by its own terms ("unless explicitly disclaimed in individual files")')
        $buf.Add('')
        $buf.Add('## 1. In-file licence grants, verbatim')
        $buf.Add('')
        $buf.Add('# Detection is mechanical: a header block qualifies if it matches licence-grant')
        $buf.Add('# vocabulary. The most common shape(s) are the package licence itself and are')
        $buf.Add('# named, not reproduced. Hand-verified exceptions (per-module licence FILES that')
        $buf.Add('# the staging step prunes, dual-licensed modules, GPL/CC-BY corner cases) are')
        $buf.Add('# enumerated in THIRD-PARTY-NOTICES.md, which is the authority; this file is')
        $buf.Add('# the evidence that the sweep covered every shipped source.')
        $buf.Add('')
        # The two most frequent shapes are the package default (the standard Tcl
        # licence block and the pointer to license.terms); they are named, not
        # reproduced -- their full text is already in ../<pkg>/license.terms.
        $ordered = @($grantBlocks.Keys | Sort-Object { -$grantBlocks[$_].files.Count }, { $_ })
        $pkgLic = ($pkg -replace '\d+(\.\d+)*$', '')
        $quoted = 0
        for ($g = 0; $g -lt $ordered.Count; $g++) {
            $k = $ordered[$g]
            $e = $grantBlocks[$k]
            if ($g -lt 2 -and ($ordered.Count -eq 1 -or $e.files.Count -gt [math]::Ceiling($files.Count / 4))) {
                $buf.Add('### [package default shape #' + ($g + 1) + '] ' + $e.files.Count + ' of ' + $files.Count +
                         ' file(s), first: ' + $e.files[0])
                $buf.Add('    ' + (($e.lines | Select-Object -First 2 | ForEach-Object { $_.Trim() }) -join ' / '))
                $buf.Add('    (full text: LICENSES/' + $pkgLic + '/license.terms -- not reproduced here)')
                $buf.Add('')
                continue
            }
            $buf.Add('### ' + $e.files.Count + ' file(s): ' + (($e.files | Select-Object -First 10) -join ', ') +
                     $(if ($e.files.Count -gt 10) { ' ... (+' + ($e.files.Count - 10) + ' more)' } else { '' }))
            $buf.Add('')
            $buf.Add('    (first occurrence at line ' + ($e.start + 1) + ' of ' + $e.files[0] + ')')
            $buf.Add('')
            foreach ($l in $e.lines) { $buf.Add('    ' + $l) }
            $buf.Add('')
            if ($e.cpr.Count -gt 1) {
                $buf.Add('    Copyright lines seen in this shape (' + $e.cpr.Count + '):')
                foreach ($c in $e.cpr) { $buf.Add('      - ' + $c) }
                $buf.Add('')
            }
            $quoted++
        }
        if ($quoted -eq 0) {
            $buf.Add('### (no exception shapes: every in-file grant in this package is the')
            $buf.Add('    package licence itself, quoted above.)')
            $buf.Add('')
        }
        $buf.Add('## 2. Distinct copyright holders (' + $holders.Count + ')')
        $buf.Add('')
        $buf.Add('# One line per distinct header copyright line, with how many shipped files')
        $buf.Add('# carry it. Retained unchanged in those files; listed here so that the')
        $buf.Add('# holder set of the package is enumerable without reading the sources.')
        $buf.Add('')
        foreach ($h in @($holders.Keys | Sort-Object { -$holders[$_].Count }, { $_ })) {
            $buf.Add('- ' + $h + '  --  ' + $holders[$h].Count + ' file(s)')
        }
        Put-Generated ("kit-headers/" + $pkg + ".NOTICE") $buf.ToArray() ("sweep " + (Rel $dir))
        $report.Add(('   sweep {0}: {1} files | grant-bearing {2} ({3} distinct legal shapes, {4} quoted, {5} treated as package default) | pointer {6} | no-header {7} | holders {8}' -f `
            $pkg, $files.Count, $cls.grant, $grantBlocks.Count, $quoted, ($grantBlocks.Count - $quoted), $cls.pointer, $cls.none, $holders.Count))
    }
}

# ---------------------------------------------------------------- README ----
if (-not $Check) {
    $rd = @(
        '# Bundled third-party licences',
        '',
        'Every file here is generated from the vendor sources by',
        '[`scripts/make-licenses.ps1`](../scripts/make-licenses.ps1) -- nothing is',
        'hand-typed, so each text is verbatim from upstream. Do not edit files',
        'in this directory; change the generator instead, then re-run it. Pass',
        '`-Check` to verify the tree against the vendor sources without writing',
        '(that is what CI does).',
        '',
        '* `*/license.terms`, `*/LICENSE*`, `*/README`, `*/COPYRIGHT.txt` -- copied',
        '  verbatim from the upstream tree. Line endings are normalised by git',
        '  (`.gitattributes` pins this directory to LF), so a handful of vendor',
        '  files that ship CRLF land in the repository as LF; their content is',
        '  unchanged, and `-Check` compares content with EOL normalised.',
        '* `*.NOTICE` -- compiled by us from source-file headers, because those',
        '  licences ship no file of their own. Each block is quoted verbatim and',
        '  carries the path and line range it came from.',
        '* `kit-headers/*.NOTICE` -- the full in-file audit of every source that',
        '  actually ships inside the kit: classification, every header that carries',
        '  its own licence grant, and the set of distinct copyright holders.',
        '',
        'See [`THIRD-PARTY-NOTICES.md`](../THIRD-PARTY-NOTICES.md) for what each',
        'licence obliges us to reproduce and where that obligation comes from.'
    )
    [System.IO.File]::WriteAllText((Join-Path $out 'README.md'), (($rd -join "`n") + "`n"), $Utf8NoBom)
}

# ---------------------------------------------------------------- output ----
''
$report | ForEach-Object { '  ' + $_ }
''
if ($Check) {
    if ($script:mismatch -eq 0) { 'CHECK OK: LICENSES/ matches vendor sources' }
    else { 'CHECK FAILED: ' + $script:mismatch + ' problem(s)'; exit 1 }
}
else {
    $fl = @(Get-ChildItem $out -Recurse -File)
    'LICENSES/: ' + $fl.Count + ' files, ' + [math]::Round(($fl | Measure-Object Length -Sum).Sum / 1KB, 1) + ' KB'
}
