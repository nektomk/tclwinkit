# kit_init.tcl --
#
#	Tcl-side bootstrap for tclwinkit. Sourced from the C AppInit
#	(Kit_RegisterPackages) right after Tcl_Init/Tk_Init.
#	Lives inside the attached zipfs image at //zipfs:/app/lib/kit_init.tcl.
#
#	Responsibilities:
#	  * extend auto_path with pure-Tcl package trees in the image;
#	  * declare name aliases for statically registered binary packages;
#	  * expose the kit version banner variable.

namespace eval ::winkit {
    variable root    //zipfs:/app
    variable libdir  //zipfs:/app/lib
    variable version 0.1
}

# ---------------------------------------------------------------------
# auto_path: tcllib/tklib installed trees (their children are the
# module directories carrying pkgIndex.tcl files), plus any standalone
# package directories placed directly under lib/.
# ---------------------------------------------------------------------
namespace eval ::winkit {
    variable libdir
    variable d
    foreach d [concat \
	    [glob -nocomplain -directory $libdir -type d tcllib* tklib*] \
	    [glob -nocomplain -directory $libdir -type d pkgs/*]] {
	if {[lsearch -exact $::auto_path $d] < 0} {
	    lappend ::auto_path $d
	}
    }
    if {[lsearch -exact $::auto_path $libdir] < 0} {
	lappend ::auto_path $libdir
    }
    unset -nocomplain d
}

# ---------------------------------------------------------------------
# Aliases: canonical static registrations use one spelling; provide the
# common alternative spellings as thin redirects. (The static table has
# "itcl" and "Thread"; tclsqlite answers to "sqlite3".)
# ---------------------------------------------------------------------
package ifneeded Itcl 4.3.8 [list package require itcl]
package ifneeded incr::tcl 4.3.8 [list package require itcl]
package ifneeded thread 3.0.6 [list package require Thread]
package ifneeded Tdbc 1.1.13 [list package require tdbc]
package ifneeded tdbc::sqlite3 1.1.13 [list apply {{dir} {
    package require tdbc
    package require sqlite3
    source -encoding utf-8 [file join $dir tdbcsqlite3.tcl]
}} //zipfs:/app/lib/tdbc]

# tcl::tm module paths inside the image (if a tm/ tree is present)
if {[namespace which ::tcl::tm::path] ne ""} {
    foreach ::winkit::d [glob -nocomplain -directory //zipfs:/app/lib -type d tm*] {
	::tcl::tm::path add $::winkit::d
    }
    unset -nocomplain ::winkit::d
}
