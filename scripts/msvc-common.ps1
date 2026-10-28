# msvc-common.ps1 -- shared MSVC path helpers for the packaging step.
# Dot-sourced by assemble-msvc-kit.ps1 and assemble-mingw-kit.ps1.
#
# Sibling of scripts\msvc-env.bat: that one discovers the same name for the
# nmake chain, this one for the kit assembly. Neither hardcodes it, because
# Tcl's win/rules.vc builds the output directory as Release_<arch>_VC<VCVER>
# and computes VCVER from _MSC_VER, so the suffix is whatever toolset did
# the build.
#
# Ordering caveat, shared with msvc-env.bat: the name is compared as a
# STRING, so with two toolsets installed the highest name wins lexically
# (VC9999 would beat VC1951). One toolset per build tree is the normal case;
# set WINKIT_BUILDDIR when it is not.

function Get-MsvcBuilddir {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$Hint = 'run scripts\build-msvc-core.bat first'
    )
    if ($env:WINKIT_BUILDDIR) { return $env:WINKIT_BUILDDIR }
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "no MSVC build tree at $Path ($Hint)"
    }
    $found = Get-ChildItem -LiteralPath $Path -Directory -Filter 'Release_*' |
        Sort-Object -Property Name -Descending | Select-Object -First 1
    if (-not $found) {
        throw "no Release_* dir under $Path ($Hint)"
    }
    return $found.Name
}
