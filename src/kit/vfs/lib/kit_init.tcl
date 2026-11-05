# kit_init.tcl --
#
#	Tcl-side kit bootstrap for tclwinkit. Sourced from the C AppInit
#	(Kit_RegisterPackages) right after Tcl_Init/Tk_Init.
#	Lives inside the attached zipfs image at //zipfs:/app/lib/kit_init.tcl.
#
#	Responsibilities:
#	  * source lib/pkgIndex.tcl eagerly into the MAIN interp so that the
#	    statically linked packages are registered without waiting for the
#	    first package-unknown scan;
#	  * expose the kit version banner variable.
#
#	ALL package registrations (static C extensions, mixed C+Tcl wrappers,
#	aliases, and the auto_path wiring for the tcllib/tklib trees) live in
#	lib/pkgIndex.tcl — a PHYSICAL package index. That file is discovered
#	automatically by every slave/safe/thread interp in this process:
#	init.tcl puts [file dirname $tcl_library] (= //zipfs:/app) on each
#	new interp's ::auto_path, and the default tclPkgUnknown scans the
#	immediate children of auto_path entries for pkgIndex.tcl files,
#	finding //zipfs:/app/lib/pkgIndex.tcl. Do not re-add programmatic
#	`package ifneeded` lines here — they would be main-interp-only and
#	invisible to child interpreters (the classic "can't find package"
#	in thread::create scripts).

namespace eval ::winkit {
    variable root    //zipfs:/app
    variable libdir  //zipfs:/app/lib
    variable version 0.2
}

# Static/mixed package index — single source of truth.
::tcl::Pkg::source //zipfs:/app/lib/pkgIndex.tcl

# tcl::tm module paths inside the image (if a tm/ tree is present)
if {[namespace which ::tcl::tm::path] ne ""} {
    foreach ::winkit::d [glob -nocomplain -directory //zipfs:/app/lib -type d tm*] {
	::tcl::tm::path add $::winkit::d
    }
    unset -nocomplain ::winkit::d
}
