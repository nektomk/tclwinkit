# main.tcl --
#
#	tclwin console shell startup script (root of the attached
#	zipfs image).
#
#	TclZipfs_AppHook installs //zipfs:/app/main.tcl as the Tcl
#	startup script, so Tcl_Main hands control here with the ORIGINAL
#	command line intact: $argv0 is this file and $argv holds every
#	user argument. This script reproduces stock tclsh behaviour:
#
#	  tclwin script.tcl ?arg ...?      run a script file
#	  tclwin -encoding enc script.tcl  run with explicit encoding
#	  ... | tclwin                     evaluate stdin until EOF
#	  tclwin                           interactive REPL
#
#	The interactive REPL uses the pure-Tcl TclReadLine package with
#	a Win32 console shim (lib/TclReadLine/tclreadline-win.tcl) that
#	feeds Windows key events to TclReadLine as the ANSI sequences it
#	expects. The GUI kit (tkwin) intentionally has no main.tcl
#	and behaves exactly like stock wish.

# --- tclsh-compatible return-code handling -----------------------------

proc ::winkit::report_error {result opts} {
    if {[dict exists $opts -errorinfo]} {
	puts stderr [dict get $opts -errorinfo]
    } else {
	puts stderr $result
    }
    return
}

proc ::winkit::finish_script {code result opts} {
    # NB: catch normalizes `return -code N` into plain code N (with
    # -code/-level in opts), so TCL_RETURN never reaches us.
    switch -- $code {
	0 {
	    exit 0
	}
	1 - 3 - 4 {
	    ;# error / break / continue: tclsh prints errorInfo, exit 1
	    ::winkit::report_error $result $opts
	    exit 1
	}
	default {
	    puts stderr "command returned bad code: $code"
	    exit 1
	}
    }
}

proc ::winkit::run_script {script encoding rest} {
    global argv0 argc argv
    set argv0 $script
    set argv $rest
    set argc [llength $rest]
    if {$encoding ne ""} {
	set code [catch {uplevel #0 [list source -encoding $encoding $script]} result opts]
    } else {
	set code [catch {uplevel #0 [list source $script]} result opts]
    }
    ::winkit::finish_script $code $result $opts
}

# --- stdin (piped input) mode ------------------------------------------

proc ::winkit::stdin_loop {} {
    set buf ""
    while {1} {
	if {[gets stdin line] < 0} {
	    if {[eof stdin]} {
		break
	    }
	    continue
	}
	append buf $line \n
	if {![info complete $buf]} {
	    continue
	}
	set code [catch {uplevel #0 $buf} result opts]
	set buf ""
	if {$code == 1 || $code == 3 || $code == 4} {
	    ::winkit::report_error $result $opts
	}
    }
    exit 0
}

# --- interactive REPL ---------------------------------------------------

proc ::winkit::have_console {} {
    # The REAL stdin handle (not CONIN$!) must be a console: pipes and
    # redirected files fail GetConsoleMode.
    if {[catch {package require twapi}]} {
	return 0
    }
    if {[catch {set h [twapi::get_standard_handle stdin]}]} {
	return 0
    }
    return [expr {![catch {twapi::GetConsoleMode $h}]}]
}

proc ::winkit::repl {} {
    global argv0 tcl_interactive tcl_rcFileName
    set argv0 [info nameofexecutable]
    set tcl_interactive 1

    puts "tclwinkit — Tcl [info patchlevel] interactive shell\
	    (packages: [llength [package names]] registered)"
    puts "Tab-completion: Shift-Tab always; Ctrl-t toggles plain Tab.\
	    Type \"exit\" or Ctrl-d on an empty line to quit."

    # Tcl_Main skips the rc file when a startup script (this file) is
    # attached, so honour tcl_rcFileName ourselves:
    if {[info exists tcl_rcFileName] && [file exists $tcl_rcFileName]} {
	if {[catch {uplevel #0 [list source $tcl_rcFileName]} err]} {
	    puts stderr "error sourcing $tcl_rcFileName: $err"
	}
    }

    package require TclReadLine
    set shim [file join $::winkit::libdir TclReadLine tclreadline-win.tcl]
    if {[file exists $shim]} {
	# uplevel #0: evaluate at global level regardless of caller context
	if {[catch {uplevel #0 [list source $shim]} err]} {
	    puts stderr "warning: TclReadLine win32 shim failed to load: $err"
	}
    }
    set ::TclReadLine::PROMPT {winkit% }
    ::TclReadLine::interact
    exit 0
}

# --- dispatch -----------------------------------------------------------

if {$argc > 0} {
    set a0 [lindex $argv 0]
    if {$a0 eq "-encoding" && $argc >= 3
	    && ![string match -* [lindex $argv 2]]} {
	::winkit::run_script [lindex $argv 2] [lindex $argv 1] [lrange $argv 3 end]
    } elseif {![string match -* $a0]} {
	::winkit::run_script $a0 "" [lrange $argv 1 end]
    }
    ;# leading-dash args (that are not -encoding): like tclsh, fall
    ;# through to stdin/interactive mode with argv untouched
}

if {[::winkit::have_console]} {
    ::winkit::repl
} else {
    ::winkit::stdin_loop
}
exit 0
