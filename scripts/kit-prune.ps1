# kit-prune.ps1 -- drop everything from a staged kit.vfs that a script never
# loads at runtime. Sourced by assemble-msvc-kit.ps1 and
# assemble-mingw-kit.ps1.
#
# Why: the kit is a runtime image, but tcllib 2.0 and tklib 0.9 ship their
# whole development trees -- test suites, nroff/HTML manuals, benchmark
# corpora, diagram sources, sample images, C helper sources. None of it is
# reachable by `package require`, yet it costs ~25 MB and ~3800 files per exe
# in the zipfs index. The removed material is published in the docs artifact
# instead (scripts/build-docs-artifact.ps1), so nothing is lost.
#
# What stays: .tcl code, pkgIndex.tcl / tclIndex / tmIndex.tcl, the
# extension-less data catalogs (syntax/, def/, emsg/, ecode/, ...) that
# modules read at runtime, message catalogs (msgs/) and the few image files
# listed in $KitRuntimeAssets.

# Directory names that never hold runtime material, matched at any depth.
$KitPruneDirs = @(
    'tests', 'test', 'test-assets', 'doc', 'docs', 'html', 'demo', 'demos',
    'examples', 'inst', 'CVS', 'build', 'bench', 'benches', 'benchmark',
    'perf', 'figures', 'alternates', 'include', 'cvs', '.svn', '.git'
)

# Extensions that are documentation, test, sample or build leftovers.
$KitPruneExts = @(
    # test scaffolding
    '.test', '.tests', '.testsuite', '.result', '.results', '.log', '.bench',
    # documentation
    '.man', '.n', '.nh', '.3', '.1', '.3tclobj', '.md', '.txt', '.html',
    '.dtx', '.ins', '.pdf', '.ps', '.dvi', '.rtf', '.odt',
    # diagrams and sources of generated files
    '.dia', '.plat', '.pre', '.work', '.bak', '.orig', '.norm',
    # C helper sources (the kit links nothing from them)
    '.c', '.h', '.cc', '.cpp', '.cxx', '.m4', '.ac', '.am', '.in',
    # archives and data corpora
    '.csv', '.xz', '.gz', '.bz2', '.zip', '.tar', '.tgz',
    # sample images
    '.jpg', '.jpeg', '.bmp', '.tif', '.tiff', '.eps', '.pcx', '.pbm',
    '.pgm', '.ppm', '.rgb', '.rgb', '.gif', '.png',
    # tcllib grammar includes (nothing reads them at runtime)
    '.inc'
)

# Runtime assets that the extension rules would otherwise remove, given as
# path fragments relative to the pruned tree.
$KitRuntimeAssets = @(
    'widgetl\icons',      # tklib widgetl loads these .png via [info script]
    'widgetl\msgs',       # message catalogs for the same widgets
    'tile\icons'          # (present in some tklib snapshots)
)

function Remove-KitBloat {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string[]]$Dirs = $KitPruneDirs,
        [string[]]$Exts = $KitPruneExts,
        [string[]]$Keep = $KitRuntimeAssets,
        [switch]$Report
    )
    if (-not (Test-Path $Path)) { return $null }
    $rootLen = $Path.Length
    $dirArr  = @($Dirs)
    $extArr  = @($Exts | ForEach-Object { $_.ToLowerInvariant() })
    $keepArr = @($Keep)
    $sep = [char]92

    function Test-Kept([string]$full) {
        foreach ($frag in $keepArr) {
            if ($full.Contains($sep + $frag + $sep)) { return $true }
        }
        return $false
    }

    $before = @(Get-ChildItem $Path -Recurse -File -Force)
    $bytesBefore = ($before | Measure-Object Length -Sum).Sum

    # deepest-first: a removed parent must not hide its children from the count
    Get-ChildItem $Path -Recurse -Directory -Force |
        Sort-Object { $_.FullName.Length } -Descending |
        Where-Object { $dirArr -contains $_.Name } |
        Remove-Item -Recurse -Force

    Get-ChildItem $Path -Recurse -File -Force |
        Where-Object {
            $extArr -contains $_.Extension.ToLowerInvariant() -and
            -not (Test-Kept $_.FullName) -and
            $_.Name -notin @('pkgIndex.tcl', 'tclIndex', 'tmIndex.tcl') -and
            $_.Extension -ne '.tcl'
        } |
        Remove-Item -Force

    # empty directory leaves from the file pass
    $pass = $true
    while ($pass) {
        $pass = $false
        Get-ChildItem $Path -Recurse -Directory -Force |
            Sort-Object { $_.FullName.Length } -Descending |
            Where-Object { -not (Get-ChildItem $_.FullName -Force -EA SilentlyContinue) } |
            ForEach-Object { Remove-Item $_.FullName -Force; $script:pass = $true }
    }

    $after = @(Get-ChildItem $Path -Recurse -File -Force)
    $bytesAfter = ($after | Measure-Object Length -Sum).Sum
    $info = [pscustomobject]@{
        path    = $Path
        files   = $before.Count
        kept    = $after.Count
        removed = $before.Count - $after.Count
        freedMB = [math]::Round(($bytesBefore - $bytesAfter) / 1MB, 2)
        keptMB  = [math]::Round($bytesAfter / 1MB, 2)
    }
    if ($Report) {
        "{0,-22} {1,5} -> {2,5} files  removed {3,5}  freed {4,6} MB (kept {5} MB)" -f `
            (Split-Path $Path -Leaf), $info.files, $info.kept, $info.removed,
            $info.freedMB, $info.keptMB
    }
    $info
}
