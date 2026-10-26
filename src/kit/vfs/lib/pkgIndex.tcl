# pkgIndex.tcl --
#
#	Package index for the tclwinkit static/mixed packages.
#	Lives at //zipfs:/app/lib/pkgIndex.tcl inside the kit image.
#
#	Why a physical pkgIndex (not programmatic `package ifneeded` in
#	kit_init.tcl): every interpreter created in this process gets
#	[tcl_library] and its parent (//zipfs:/app) on ::auto_path
#	(library/init.tcl), and the default package-unknown hook
#	(tclPkgUnknown) scans the immediate children of auto_path entries
#	for pkgIndex.tcl files. So slave interps, safe interps and
#	thread::create interps all discover the statically linked
#	packages through THIS file. The main interp gets the same
#	registrations eagerly: lib/kit_init.tcl sources it at startup.
#
#	The `load {} Prefix` strings must match the Tcl_StaticLibrary()
#	prefixes in src/kit/kit_register.c EXACTLY (case-sensitive).
#
#	This file is sourced in EVERY interp (slaves/threads too), so it
#	must not assume anything the kit bootstrap set up there: all local
#	variables live in the ::winkit::pkgindex namespace (created on
#	demand) and the auto_path scan is guarded by catch (restricted
#	glob in safe interps).

namespace eval ::winkit::pkgindex {
    # -----------------------------------------------------------------
    # Make the kit's own package trees discoverable *in this interp*:
    # tclPkgUnknown re-checks ::auto_path after sourcing each index file,
    # so the directories appended here are scanned by the same search
    # that found this file (twapi/cawt/TclReadLine pkgIndex.tcl live in
    # lib/*, tcllib/tklib module indexes in lib/tcllib*/**, lib/tklib*/**).
    # -----------------------------------------------------------------
    catch {
	variable d
	foreach d [concat [list //zipfs:/app/lib] \
		[glob -nocomplain -directory //zipfs:/app/lib -type d tcllib* tklib*]] {
	    if {$d ni $::auto_path} {
		lappend ::auto_path $d
	    }
	}
	unset -nocomplain d
    }

    # -----------------------------------------------------------------
    # Static C extensions (linked into the exe; prefixes match
    # kit_register.c). Pure-C packages work in ANY interp: the static
    # library table is process-global, `load {} P` calls P_Init(target).
    # -----------------------------------------------------------------
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

    # rl_json 0.17.8 / mpexpr 1.2: pure C extensions, both kit variants.
    # NB: Rl_json_Init reads the variable `dir` from the calling frame (the
    # vendor pkgIndex passes the package dir through `apply`) — mirror that.
    package ifneeded rl_json 0.17.8 [list apply {{dir} {load {} Rl_json}} //zipfs:/app/lib]
    package ifneeded Mpexpr 1.2     [list load {} Mpexpr]
    package ifneeded mpexpr 1.2     [list package require Mpexpr]

    # -----------------------------------------------------------------
    # Aliases: canonical static registrations use one spelling; provide
    # the common alternative spellings as thin redirects. (The static
    # table has "itcl" and "Thread"; tclsqlite answers to "sqlite3";
    # itcl/itk test suites and [incr Tk]-style code use the titled
    # "Itcl" — also registered statically, see kit_register.c.)
    # -----------------------------------------------------------------
    package ifneeded Itcl 4.3.8 [list package require itcl]
    package ifneeded incr::tcl 4.3.8 [list package require itcl]
    package ifneeded thread 3.0.6 [list package require Thread]
    package ifneeded Tdbc 1.1.13 [list package require tdbc]
    package ifneeded tdbc::sqlite3 1.1.13 [list apply {{dir} {
	package require tdbc
	package require sqlite3
	source -encoding utf-8 [file join $dir tdbcsqlite3.tcl]
    }} //zipfs:/app/lib/tdbc]

    # -----------------------------------------------------------------
    # GUI-variant packages (Img, Itk, Iwidgets, tkdnd, Treectrl).
    # Registered unconditionally: in the console kit the image simply
    # lacks these dirs and the static prefixes are absent, so a
    # `package require` fails with a clear "no library with prefix ..."
    # error only if actually requested. (A [package provide Tk] guard
    # here would WRONGLY hide them from slave/thread interps of the GUI
    # kit, which do not have Tk loaded in each interp.)
    # -----------------------------------------------------------------

    # Img 2.1.2: format handlers pull img::base/zlibtcl/pngtcl/jpegtcl/
    # tifftcl via their *tcl_InitStubs calls at load time.
    # Img base has two spellings depending on the build system:
    # nmake/MSVC provides "tkimg", TEA/MinGW provides "img::base".
    # Load once via the static prefix, then satisfy whichever spelling
    # the C init did not provide itself.
    variable n
    foreach n {tkimg img::base} {
	package ifneeded $n 2.1.2 [list apply {{name} {
	    if {[package provide tkimg] eq "" && [package provide img::base] eq ""} {
		load {} Tkimg
	    }
	    if {[package provide $name] eq ""} {
		package provide $name 2.1.2
	    }
	}} $n]
    }
    unset -nocomplain n
    package ifneeded zlibtcl   1.3.2 [list load {} Zlibtcl]
    package ifneeded pngtcl    1.6.58 [list load {} Pngtcl]
    package ifneeded jpegtcl   10.0.0 [list load {} Jpegtcl]
    package ifneeded tifftcl   4.7.2 [list load {} Tifftcl]
    variable t p
    foreach {t p} {
	bmp Tkimgbmp       dted Tkimgdted     flir Tkimgflir
	gif Tkimggif       ico Tkimgico       jpeg Tkimgjpeg
	pcx Tkimgpcx       pixmap Tkimgpixmap png Tkimgpng
	ppm Tkimgppm       ps Tkimgps        raw Tkimgraw
	sgi Tkimgsgi       sun Tkimgsun      tga Tkimgtga
	tiff Tkimgtiff     window Tkimgwindow xbm Tkimgxbm
	xpm Tkimgxpm
    } {
	package ifneeded img::$t 2.1.2 [list load {} $p]
    }
    unset -nocomplain t p

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

    # Itk 4.2.7 / Iwidgets 4.1.1 (Itcl-based megawidgets).
    # Itk_Init requires itcl to be loaded (the ItkKit_Init wrapper in
    # kit_register.c runs `package require itcl` first), locates its
    # itk.tcl under [file dirname $tcl_library]/itk4.2.7 (zipfs root)
    # and provides BOTH spellings "Itk" and "itk" itself.
    # Iwidgets is pure Tcl: iwidgets.tcl + generic/*.itk auto_load tree.
    package ifneeded Itk 4.2.7 [list load {} Itk]
    package ifneeded itk 4.2.7 [list package require Itk]
    # NB: iwidgets.tcl runs `package forget Itk` when Itk is not yet
    # provided (killing our own ifneeded registration) — require Itk first.
    package ifneeded Iwidgets 4.1.1 [list apply {{} {
	package require Itk
	source -encoding utf-8 //zipfs:/app/lib/iwidgets4.1.1/iwidgets.tcl
    }}]
    package ifneeded iwidgets 4.1.1 [list package require Iwidgets]

    # tkdnd 2.9.5: static C part (Tkdnd_Init provides "tkdnd").
    # The native pkgIndex sources tkdnd.tcl and calls tkdnd::initialise,
    # which loads a DLL; for the static kit we replicate its win32
    # steps here with `load {} Tkdnd` in place of the DLL load.
    package ifneeded tkdnd 2.9.5 [list apply {{dir} {
	source -encoding utf-8 [file join $dir tkdnd.tcl]
	set ::tkdnd::_package_dir $dir
	set ::tkdnd::_windowingsystem windows
	set ::tkdnd::_drop_file_temp_dir [file normalize \
	    [expr {[info exists ::env(TEMP)] ? $::env(TEMP) : [pwd]}]]
	# tkdnd_generic/windows/compat use RELATIVE namespaces (`namespace
	# eval generic/olednd`) — the native ::tkdnd::initialise sources them
	# through the ::tkdnd::source wrapper so they land under ::tkdnd.
	# Calling the wrapper directly replicates that exactly (its proc
	# frame runs in the ::tkdnd namespace, and it defaults to utf-8).
	::tkdnd::source [file join $dir tkdnd_generic.tcl]
	::tkdnd::source [file join $dir tkdnd_windows.tcl]
	set ::tkdnd::_platform_namespace olednd
	load {} Tkdnd
	::tkdnd::source [file join $dir tkdnd_compat.tcl]
	::tkdnd::olednd::initialise
    }} //zipfs:/app/lib/tkdnd2.9.5]
    package ifneeded tkdnd::utils 2.9.5 [list apply {{dir} {
	package require tkdnd
	source -encoding utf-8 [file join $dir tkdnd_utils.tcl]
	package provide tkdnd::utils 2.9.5
    }} //zipfs:/app/lib/tkdnd2.9.5]

    # Treectrl 2.5.2: set ::treectrl_library BEFORE the load —
    # Treectrl_Init runs tcl_findLibrary which sources treectrl.tcl
    # (which in turn sources filelist-bindings.tcl from its own dir).
    package ifneeded treectrl 2.5.2 [list apply {{dir} {
	set ::treectrl_library $dir
	load {} Treectrl
    }} //zipfs:/app/lib/treectrl2.5.2]
}
