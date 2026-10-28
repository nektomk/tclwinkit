# zip-entry.ps1 -- deterministic ZIP entry writers, shared by the three
# packagers (assemble-msvc-kit.ps1, assemble-mingw-kit.ps1,
# build-docs-artifact.ps1). Dot-sourced; call Add-ZipDir / Add-ZipFile
# instead of the raw .NET methods.
#
# Why this exists. Measured on 2026-10-27: two consecutive runs of
# assemble-msvc-kit.ps1 produced kit images of identical size whose SHA-256
# differed, in exactly 504 bytes, all of them mod-time fields (252 local
# headers + 252 central-directory entries), zero bytes anywhere else. Cause:
# ZipArchive.CreateEntry(name) stamps a directory entry with the current
# clock, while CreateEntryFromFile stamps a file entry with the source file's
# mtime. So every run re-broke the image digest, which makes a published
# checksum unverifiable by a third party and any CI attestation meaningless.
#
# Pinning every entry, directories included, is what removes it: a fresh
# clone has different file mtimes than this disk, so copying source mtimes
# would not be reproducible across machines either.
#
# 1980-01-01 00:00:00 is the earliest stamp the MS-DOS fields can hold
# (APPNOTE 4.4.6.7), i.e. the neutral sentinel, and it is what
# reproducible-build tooling conventionally uses. Verified on this machine:
# .NET stores the wall clock of the DateTimeOffset literally, with no
# local-time conversion, so the value does not depend on the machine zone or
# on DST (same bytes under TZ=UTC, Asia/Tokyo and America/New_York); and it
# adds no extended-timestamp extra field (extra=0 bytes), so pinning changes
# no size, only those 504 bytes.
#
# The stored time is what `file mtime` reports for //zipfs:/ paths. Nothing
# shipped reads it: the glue has zero hits for file mtime / file attributes,
# and the tcllib hits (amazon-s3, counter) operate on user files at runtime,
# not on the image.
#
# Two .NET Framework 4.x constraints, both measured rather than guessed:
#
#   * LastWriteTime cannot be changed once the entry has been opened for
#     writing ("Cannot modify entry in Create mode after entry has been
#     opened for writing"), and CreateEntryFromFile opens it internally, so
#     the only construction able to pin a file entry is CreateEntry(name,
#     level) then set the time then copy the bytes by hand.
#   * ZipArchiveEntry has no public Dispose(). Calling it throws
#     MethodNotFound, which is what broke the first version of this file and
#     turned every packager into a 136-byte archive.

# Pinned timestamp for every entry in every artifact we generate.
$ZipEpoch1980 = [System.DateTimeOffset]::new(1980, 1, 1, 0, 0, 0, [System.TimeSpan]::Zero)

function Add-ZipDir {
    param(
        [Parameter(Mandatory = $true)]$Zip,
        [Parameter(Mandatory = $true)][string]$Name
    )
    # Never opened for writing, so the time can be set here; the header is
    # emitted when the archive itself is disposed.
    $entry = $Zip.CreateEntry($Name)
    $entry.LastWriteTime = $ZipEpoch1980
}

function Add-ZipFile {
    param(
        [Parameter(Mandatory = $true)]$Zip,
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Name,
        [System.IO.Compression.CompressionLevel]$Level =
            [System.IO.Compression.CompressionLevel]::Optimal
    )
    $entry = $Zip.CreateEntry($Name, $Level)
    $entry.LastWriteTime = $ZipEpoch1980
    $in = [System.IO.File]::OpenRead($Source)
    try {
        $out = $entry.Open()
        try { $in.CopyTo($out) } finally { $out.Dispose() }
    } finally { $in.Dispose() }
}

function Get-SortedFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    # Ordinal order on full paths, returned as the FileInfo objects.
    # Sort-Object -Property FullName compares with the current culture, which
    # differs per machine and, measured on this tree, disagrees with ordinal
    # order in 1091 of 1866 positions; -Culture 'InvariantDomain' is rejected
    # outright by Windows PowerShell 5.1, which validates the name against
    # Windows LCIDs. Bare Get-ChildItem order is NTFS-index order: stable on
    # one volume, not guaranteed across a freshly cloned tree.
    $map = @{}
    $names = New-Object 'System.Collections.Generic.List[string]'
    foreach ($f in (Get-ChildItem -LiteralPath $Path -Recurse -File)) {
        $map[$f.FullName] = $f
        $names.Add($f.FullName)
    }
    $arr = $names.ToArray()
    [System.Array]::Sort($arr, [System.StringComparer]::Ordinal)
    foreach ($n in $arr) { $map[$n] }
}
