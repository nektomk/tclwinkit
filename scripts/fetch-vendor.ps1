# fetch-vendor.ps1 --
#   Download the vendor archives listed in docs/SOURCES.md into vendor/ and
#   verify each one before it is allowed to touch the build trees.
#
#   Why this exists: vendor/ is not in git (67.65 MB, .gitignore), so this
#   table is the whole interface between "public repository" and "buildable
#   from source". A wrong archive that reaches the trees does not report
#   itself as a download failure -- it shows up much later as an
#   incomprehensible configure error far from the cause, which is the same
#   class of problem as a missing MSYSTEM (see docs/ENVIRONMENT.md).
#
#   Verification is threefold per row: size, SHA-256, and readability as an
#   archive with the expected top-level entry. The third one is not
#   decoration. https://www.dyncall.org/pub/dyncall-0.9.tar.gz answers
#   HTTP 200 with Content-Type: text/html and Content-Length: 0, so checking
#   the status code alone lets an HTML page into the build; the size check
#   would catch it but would not name the reason.
#
#   Transport is curl.exe, deliberately: downloads.sourceforge.net returns
#   403 to a browser User-Agent, and the measured-good configuration is "no
#   custom UA" (docs/SOURCES.md, "Known-bad URLs"). Invoke-WebRequest would
#   put a WindowsPowerShell UA on the wire and prdownloads.sourceforge.net
#   is 403 for everything, so neither default nor fallback belongs here.
#
#   Four upstreams are MOVABLE git branches (tktreectrl, mpexpr, itk,
#   TclReadLine). By default this script fetches the branch form, which is
#   byte-identical to what the shipped kits were built from. -UsePins fetches
#   the commit-pinned form instead: same files (verified per-file for all
#   four), different bytes, because GitHub names the top-level directory
#   after the ref it archived. Both digests are recorded in docs/SOURCES.md,
#   so switching forms means updating the table, not hitting a false reject.
#
#   Usage:
#     scripts\fetch-vendor.ps1                 # fetch what is missing or bad
#     scripts\fetch-vendor.ps1 -VerifyOnly     # check vendor/ , download nothing
#     scripts\fetch-vendor.ps1 -UsePins        # prefer the immutable commit form
#     scripts\fetch-vendor.ps1 -Force          # re-download even a good copy
#     scripts\fetch-vendor.ps1 -Root D:\other  # repo root override
#
#   Exit code 0 only if every row is present and verified.
#
#   ASCII-only, CRLF (docs/CONVENTIONS.md rule for .ps1).

param(
    [string]$Root = '',
    [switch]$VerifyOnly,
    [switch]$UsePins,
    [switch]$Force
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# $PSScriptRoot is not populated during parameter binding on Windows
# PowerShell 5.1, so the root is resolved in the body, not in param().
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
$Vendor = Join-Path $Root 'vendor'
$Curl   = Join-Path $env:SystemRoot 'System32\curl.exe'

function Get-ShaHex([string]$Path) {
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLower()
}

function Test-ArchiveShape([string]$Path, [string]$Kind, [string]$Top) {
    # '' when the bytes really are an archive of the expected shape,
    # otherwise the reason. See the header note on the 200/HTML trap.
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if ($Kind -eq 'zip') {
        try {
            $zr = [System.IO.Compression.ZipFile]::OpenRead($Path)
            try { $names = @($zr.Entries | ForEach-Object { $_.FullName }) } finally { $zr.Dispose() }
        } catch { return 'not a readable zip: ' + $_.Exception.GetType().Name }
        if ($names.Count -eq 0) { return 'zip lists no entries' }
    } else {
        $flag = if ($Kind -eq 'txz') { 'tJf' } else { 'tzf' }
        $names = & tar "-$flag" $Path 2>$null
        if ($LASTEXITCODE -ne 0) { return 'tar -' + $flag + ' failed (rc=' + $LASTEXITCODE + ')' }
        if (@($names).Count -eq 0) { return 'archive lists no entries' }
    }
    if ($Top) {
        $pat = $Top + '*'
        if (-not (@($names | Where-Object { $_ -like $pat }).Count)) {
            return 'no "' + $Top + '" inside; first entry is "' + @($names)[0] + '"'
        }
    }
    return ''
}

# comp, filename in vendor/, kind, top-level entry, URL, sha256, size
$Rows = @(
    @{ c = 'Tcl';        f = 'tcl9.0.4-src.tar.gz';   k = 'tgz'; t = 'tcl9.0.4/';
       u = 'https://master.dl.sourceforge.net/project/tcl/Tcl/9.0.4/tcl9.0.4-src.tar.gz';
       d = 'd0aed49230bc02a65c1e0229e65f34590a4b037ec40d546f32573b467f7551ea'; s = 11866337 },
    @{ c = 'Tk';         f = 'tk9.0.4-src.tar.gz';    k = 'tgz'; t = 'tk9.0.4/';
       u = 'https://downloads.sourceforge.net/tcl/tk9.0.4-src.tar.gz';
       d = 'd7a146d2917eb8b5cc95276dbf0e3d03c7464d2b19c1675357857c989301dbb4'; s = 4613019 },
    @{ c = 'tcllib';     f = 'tcllib-2.0.tar.xz';     k = 'txz'; t = 'tcllib-2.0/';
       u = 'https://downloads.sourceforge.net/tcllib/tcllib-2.0.tar.xz';
       d = '642c2c679c9017ab6fded03324e4ce9b5f4292473b62520e82aacebb63c0ce20'; s = 14872556 },
    @{ c = 'tklib';      f = 'tklib-0.9.tar.xz';      k = 'txz'; t = 'tklib-0.9/';
       u = 'https://downloads.sourceforge.net/tcllib/tklib-0.9.tar.xz';
       d = 'b0258d1a5039d44ac0cde0b3a7ee0aa0d687acc9eb4d9c5f683f2cbffd26c6ca'; s = 6052704 },
    @{ c = 'iwidgets';   f = 'iwidgets-4.1.1.tar.gz'; k = 'tgz'; t = 'iwidgets-4.1.1/';
       u = 'https://deb.debian.org/debian/pool/main/i/iwidgets4/iwidgets4_4.1.1.orig.tar.gz';
       d = '572fd8eed70786b1fbff6e7fec62eab7bd731beea074022d1b5a480ecf2df586'; s = 720630 },
    @{ c = 'Img';        f = 'Img-2.1.2.tar.gz';      k = 'tgz'; t = 'Img-2.1.2/';
       u = 'https://downloads.sourceforge.net/tkimg/Img-2.1.2.tar.gz';
       d = '932d386142e5aaff74add63da283d0547f0515d6155b9a2b69b433f9c353271a'; s = 12544404 },
    @{ c = 'TWAPI';      f = 'twapi-5.2.0-src.zip';   k = 'zip'; t = '';
       u = 'https://github.com/apnadkarni/twapi/archive/refs/tags/v5.2.zip';
       d = '9a0d84e20bb1493467ca0219596462f4feb1975a6a65fd4ec84f9e6b708eec4b'; s = 12102736 },
    @{ c = 'dyncall';    f = 'dyncall-0.9.tar.gz';    k = 'tgz'; t = 'dyncall-0.9/';
       u = 'https://www.dyncall.org/r0.9/dyncall-0.9.tar.gz';
       d = '8a7628fd00b4e0acc952c5d9d03035de90f349d4d4dfdad4c48a037f2a0979f9'; s = 431660 },
    @{ c = 'CAWT';       f = 'Cawt-3.1.1-User.zip';   k = 'zip'; t = 'Cawt-3.1.1-User/';
       u = 'https://downloads.sourceforge.net/cawt/Cawt-3.1.1-User.zip';
       d = 'e20b5ed87557d2b26ba6863fda3f9abbf554caf9713444b71e9a5a55ab27efeb'; s = 4398321 },
    @{ c = 'rl_json';    f = 'rl_json-0.17.8.tar.gz'; k = 'tgz'; t = 'rl_json-v0.17.8/';
       u = 'https://github.com/RubyLane/rl_json/releases/download/v0.17.8/rl_json-v0.17.8.tar.gz';
       d = 'c470edb5c92d44c178a095e45cd1a7992c5db78a9650c18588cf5cbca7619e28'; s = 394235 },
    @{ c = 'tkdnd';      f = 'tkdnd-2.9.5.tar.gz';    k = 'tgz'; t = 'tkdnd-tkdnd-release-test-v2.9.5/';
       u = 'https://github.com/petasis/tkdnd/archive/refs/tags/tkdnd-release-test-v2.9.5.tar.gz';
       d = '7ab2d1d7c0f57a5dc7f6d5542895b44762a31a01621c9d7f80f3bbd67c7bcc39'; s = 1365461 },
    # movable upstreams: branch form (default, what the kits were built from)
    # and commit-pinned form (-UsePins). t is left empty for these four on
    # purpose: the top-level directory name is the ref, so it differs between
    # the two forms (itk-main/ vs itk-e6974078.../), and a fixed expectation
    # would reject the other form. Size + digest already imply the shape, so
    # nothing weakens; the shape check earns its keep on rows where a wrong
    # fetch could have a plausible size, which is the dyncall 200/HTML trap.
    @{ c = 'tktreectrl'; f = 'tktreectrl-2.5.1.tar.gz'; k = 'tgz'; t = ''; movable = $true;
       u = 'https://github.com/tcltk-depot/tktreectrl/archive/refs/heads/main.tar.gz';
       d = 'fe7a7a28c9f2bc74427986d718158dcb040acde4e7f70fa29b4ab91f0d672578'; s = 998346;
       pu = 'https://github.com/tcltk-depot/tktreectrl/archive/51498c7837193d621069d1159577392f2bfc1fb2.tar.gz';
       pd = 'da93cc42438172f5faf1ec394a1fdc60872e3b5f1894b7d16cbce0207b23ae30'; pss = 999449 },
    @{ c = 'mpexpr';     f = 'mpexpr-1.2-vc.tar.gz';  k = 'tgz'; t = ''; movable = $true;
       u = 'https://github.com/tcl-mirror/mpexpr/archive/refs/heads/master.tar.gz';
       d = 'b02c5401f7a610056a25ec31dcb6e9bba37fa615fd9a2bec05721fa47335fcc4'; s = 389336;
       pu = 'https://github.com/tcl-mirror/mpexpr/archive/1d2bf28d360da53b820ee3c5ad10e848d1af8b50.tar.gz';
       pd = '9c49c92a46ce62d51d1280d9dc648017ddb97300d822d66f9b2b789555e0ce6c'; pss = 389516 },
    @{ c = 'TclReadLine'; f = 'TclReadLine.zip';      k = 'zip'; t = ''; movable = $true;
       u = 'https://github.com/derijkp/TclReadLine/archive/refs/heads/master.zip';
       d = '11da53cbbbddb7df9e3559d3013c87f5137a7d4e06c70ce367ce5c94404fb48b'; s = 12284;
       pu = 'https://github.com/derijkp/TclReadLine/archive/8cad690349a3a6b418290bbdca111383519ba02e.zip';
       pd = 'ffd7cd6ad4918878118496af2bec81a7b88313baec51c6fde037179718d8cea2'; pss = 12624 },
    @{ c = 'itk';        f = 'itk-main-4.2.7.tar.gz'; k = 'tgz'; t = ''; movable = $true;
       u = 'https://github.com/tcltk/itk/archive/refs/heads/main.tar.gz';
       d = '54bd2e71e881af80cafb5f640ef4a9f5cd4547ed9636d00adedf5454ab5f3db8'; s = 178751;
       pu = 'https://github.com/tcltk/itk/archive/e697407849b01d3498b56fc46e5a423690190954.tar.gz';
       pd = 'd4db12ef9d984f11681b4bef544350184b13b63a17707f8334c45e2f5a16f301'; pss = 178944 }
)

if (-not $VerifyOnly -and -not (Test-Path $Curl)) {
    throw 'curl.exe not found at ' + $Curl + '; see docs/SOURCES.md on transport'
}
if (-not (Test-Path $Vendor)) { New-Item -ItemType Directory -Path $Vendor | Out-Null }

'mode: ' + $(if ($VerifyOnly) { 'verify only' } else { 'fetch' }) +
    $(if ($UsePins) { ', pinned forms of movable refs' } else { '' }) +
    $(if ($Force) { ', force re-download' } else { '' })
'root: ' + $Root
'vendor: ' + $Vendor + '  (' + @(Get-ChildItem $Vendor -File -EA SilentlyContinue).Count + ' files)'
''

function Test-Local([string]$Path, [string]$Dig, [int]$Size, [string]$Kind, [string]$Top) {
    # Defined before the loop that calls it: PowerShell resolves a function
    # at execution time, so a definition placed after the loop would not
    # exist yet on the first row.
    #
    # Order matters: size is free, the digest reads the whole file, and the
    # archive listing is the slowest -- so a wrong-shaped download gets named
    # before the expensive hash of a large file, and the size mismatch that
    # the dyncall trap produces is reported without hashing 431 KB of HTML.
    $len = (Get-Item -LiteralPath $Path).Length
    if ($len -ne $Size) { return 'size ' + $len + ' B, expected ' + $Size + ' B' }
    $got = Get-ShaHex $Path
    if ($got -cne $Dig) { return 'sha256 ' + $got + ', expected ' + $Dig }
    $why = Test-ArchiveShape $Path $Kind $Top
    if ($why) { return $why }
    return ''
}

$ok = 0; $bad = 0; $missing = @()
foreach ($r in $Rows) {
    $url = $r.u; $dig = $r.d; $size = $r.s; $form = 'branch'
    if ($UsePins -and $r.movable) { $url = $r.pu; $dig = $r.pd; $size = $r.pss; $form = 'pinned' }
    $dest = Join-Path $Vendor $r.f
    $line = ('{0,-11}' -f $r.c) + ('{0,-7}' -f $form)

    $haveGood = $false
    if ((Test-Path $dest) -and -not $Force) {
        $why = Test-Local $dest $dig $size $r.k $r.t
        if (-not $why) { $haveGood = $true }
        elseif ($VerifyOnly) { $bad++; $line += 'BAD  ' + $why; $line; continue }
    }
    if ($haveGood) { $ok++; $line += 'ok (verified local copy)'; $line; continue }
    if ($VerifyOnly) { $bad++; $line += 'MISSING'; $missing += $r.f; $line; continue }

    # Download to a scratch name first: a half-written or wrong file must
    # never land on top of a copy that might have been good.
    $tmp = $dest + '.part'
    Remove-Item $tmp -EA SilentlyContinue
    & $Curl -sS -L --fail --retry 2 -o $tmp $url 2>$null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $tmp)) {
        $bad++; $line += 'DOWNLOAD FAILED (curl rc=' + $LASTEXITCODE + ')'; $line
        Remove-Item $tmp -EA SilentlyContinue
        continue
    }
    $why = Test-Local $tmp $dig $size $r.k $r.t
    if ($why) {
        $bad++; $line += 'REJECTED: ' + $why
        $line
        '           kept aside as ' + (Split-Path $tmp -Leaf) + ' for inspection'
        continue
    }
    Move-Item -LiteralPath $tmp -Destination $dest -Force
    $ok++; $line += 'downloaded and verified'
    $line
}

''
'verdict: ok ' + $ok + '  bad ' + $bad + '  missing ' + $missing.Count
if ($bad) { exit 1 }
if ($missing.Count) { exit 1 }
'FETCH-VENDOR OK'
exit 0
