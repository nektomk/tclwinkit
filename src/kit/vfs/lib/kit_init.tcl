# kit_init.tcl --
#
#	Tcl-side bootstrap for tclwinkit. Sourced from the C AppInit
#	(Kit_RegisterPackages) right after Tcl_Init/Tk_Init.
#	Lives inside the attached zipfs image at //zipfs:/app/lib/kit_init.tcl.
#
#	Responsibilities:
#	  * extend auto_path with pure-Tcl package trees in the image
#	    (tcllib/tklib module trees live one level below lib/tcllibX.Y);
#	  * declare `load {}` package indices for statically linked
#	    extensions (Img family);
#	  * declare name aliases for statically registered binary packages;
#	  * expose the kit version banner variable.
#
#	Note: directories directly under lib/ that carry a pkgIndex.tcl
#	(twapi, cawt, TclReadLine, ...) are discovered automatically by
#	Tcl's depth-1 package index scan once lib/ itself is in auto_path.

namespace eval ::winkit {
    variable root    //zipfs:/app
    variable libdir  //zipfs:/app/lib
    variable version 0.1
}

# ---------------------------------------------------------------------
# auto_path: tcllib/tklib trees (their children are the module
# directories carrying pkgIndex.tcl files) and any pkgs/ tree.
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
# Primary package indices for the statically linked binary extensions.
# Tcl_StaticLibrary() only makes `load {} <Prefix>` work; the package
# system still needs ifneeded entries. Prefixes must match the exact
# strings registered in kit_register.c.
# ---------------------------------------------------------------------
package ifneeded itcl 4.3.8       [list load {} itcl]
package ifneeded Thread 3.0.6     [list load {} Thread]
package ifneeded tdbc 1.1.13      [list load {} tdbc]
package ifneeded sqlite3 3.53.0   [list load {} sqlite3]
# tdbc::odbc: the C Init attaches constructors to the OO classes created
# by tdbcodbc.tcl, so the script must be sourced BEFORE load (same order
# as the native pkgIndex.tcl).
package ifneeded tdbc::odbc 1.1.13 [list apply {{dir} {
    source -encoding utf-8 [file join $dir tdbcodbc.tcl]
    load {} tdbc::odbc
}} //zipfs:/app/lib/tdbc]

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

# ---------------------------------------------------------------------
# Img 2.1.2 (GUI variant only): statically linked, driven through
# `load {} <Prefix>` where prefixes match the Tcl_StaticLibrary() calls
# in kit_register.c. Format handlers pull img::base/zlibtcl/pngtcl/
# jpegtcl/tifftcl via their *tcl_InitStubs calls at load time.
# ---------------------------------------------------------------------
if {[package provide Tk] ne ""} {
    # Img base has two spellings depending on the build system:
    # nmake/MSVC provides "tkimg", TEA/MinGW provides "img::base".
    # Load once via the static prefix, then satisfy whichever spelling
    # the C init did not provide itself.
    foreach ::winkit::n {tkimg img::base} {
	package ifneeded $::winkit::n 2.1.2 [list apply {{name} {
	    if {[package provide tkimg] eq "" && [package provide img::base] eq ""} {
		load {} Tkimg
	    }
	    if {[package provide $name] eq ""} {
		package provide $name 2.1.2
	    }
	}} $::winkit::n]
    }
    unset -nocomplain ::winkit::n
    package ifneeded zlibtcl   1.3.2 [list load {} Zlibtcl]
    package ifneeded pngtcl    1.6.58 [list load {} Pngtcl]
    package ifneeded jpegtcl   10.0.0 [list load {} Jpegtcl]
    package ifneeded tifftcl   4.7.2 [list load {} Tifftcl]
    foreach {::winkit::t ::winkit::p} {
	bmp Tkimgbmp       dted Tkimgdted     flir Tkimgflir
	gif Tkimggif       ico Tkimgico       jpeg Tkimgjpeg
	pcx Tkimgpcx       pixmap Tkimgpixmap png Tkimgpng
	ppm Tkimgppm       ps Tkimgps        raw Tkimgraw
	sgi Tkimgsgi       sun Tkimgsun      tga Tkimgtga
	tiff Tkimgtiff     window Tkimgwindow xbm Tkimgxbm
	xpm Tkimgxpm
    } {
	package ifneeded img::$::winkit::t 2.1.2 [list load {} $::winkit::p]
    }
    unset -nocomplain ::winkit::t ::winkit::p

    # Union package: mirrors base/pkgIndex.tcl.in ( Img = all standard
    # format handlers; dted/flir/gif/raw/ps remain opt-in via img::<fmt> ).
    package ifneeded Img 2.1.2 {
	package require img::window
	package require img::tga
	package require img::ico
	package require img::pcx
	package require img::sgi
	package require img::sun
	package require img::xbm
	package require img::xpm
	package require img::jpeg
	package require img::png
	package require img::tiff
	package require img::bmp
	package require img::ppm
	package require img::pixmap
	package provide Img 2.1.2
    }
}

# tcl::tm module paths inside the image (if a tm/ tree is present)
if {[namespace which ::tcl::tm::path] ne ""} {
    foreach ::winkit::d [glob -nocomplain -directory //zipfs:/app/lib -type d tm*] {
	::tcl::tm::path add $::winkit::d
    }
    unset -nocomplain ::winkit::d
}
