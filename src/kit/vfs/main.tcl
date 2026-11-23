# main.tcl --
#
#	tclwin / tclsafe console shell startup script (root of the
#	attached zipfs image).
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
#	The safe kit (tclsafe) shares this file and this image; only its C
#	stub differs, publishing ::winkit::safe_mode before we run. Its
#	script and stdin paths evaluate in a safe CHILD interpreter
#	(lib/winkit/safe_master.tcl) rather than in the master:
#
#	  tclsafe ?-safetime S? ?-safecmds N? script.tcl ?arg ...?
#	  ... | tclsafe ?-safetime S? ?-safecmds N?
#
#	-safetime / -safecmds take a non-negative integer, where 0 disables
#	that limit, and are honoured only before the script name -- like
#	tclsh's own flags, anything after it belongs to the script. The safe
#	kit has no interactive REPL yet; see the safe_main comment.
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

# --- command-line parsing ------------------------------------------------

# Parse the command line ONCE, for both the normal and the safe kit, so the two
# cannot drift apart. Returns a dict:
#   script    the script file to run, or "" when there is none
#   encoding  the -encoding value, or ""
#   rest      arguments after the script name (become the script's argv)
#
# Mirrors stock tclsh: a leading dash that is not a recognised -encoding form
# is not consumed here -- the caller falls through to stdin/interactive mode
# with argv untouched.
proc ::winkit::parse_argv {argv} {
    set n [llength $argv]
    if {$n == 0} {
	return [dict create script "" encoding "" rest {}]
    }
    set a0 [lindex $argv 0]
    if {$a0 eq "-encoding" && $n >= 3
	    && ![string match -* [lindex $argv 2]]} {
	return [dict create script [lindex $argv 2] \
		encoding [lindex $argv 1] rest [lrange $argv 3 end]]
    }
    if {![string match -* $a0]} {
	return [dict create script $a0 encoding "" rest [lrange $argv 1 end]]
    }
    return [dict create script "" encoding "" rest {}]
}

# --- safe mode -----------------------------------------------------------
#
# tclsafe.exe carries the SAME VFS image as tclwin.exe. What differs is the C
# stub: kit_safe_main.c publishes ::winkit::safe_mode from Tcl_AppInit, which
# runs before Tcl_Main evaluates this file, so the branch at the bottom is the
# only place that knows which kit is running.
#
# In safe mode the master stays unsandboxed and does nothing but parse the
# command line and drive a safe child; every user script runs in that child.

proc ::winkit::is_safe {} {
    # Both halves matter: tclwin.exe never sets the variable at all, and a
    # variable explicitly set to 0 must not enable the sandbox either.
    return [expr {[info exists ::winkit::safe_mode] && $::winkit::safe_mode}]
}

# Strip the safe-kit limit flags off the FRONT of the command line, apply them,
# and return what is left for parse_argv.
#
# Only leading flags are consumed, exactly as stock tclsh treats its own: the
# first non-dash argument starts the script's argv, so
#   tclsafe script.tcl -safetime 5
# hands "-safetime 5" to script.tcl instead of setting a limit.
proc ::winkit::strip_safe_flags {argv} {
    set seconds ""
    set commands ""
    set n [llength $argv]
    set i 0

    while {$i < $n} {
	set flag [lindex $argv $i]
	if {$flag ne "-safetime" && $flag ne "-safecmds"} {
	    break
	}
	if {$i + 1 >= $n} {
	    puts stderr "$flag requires a value: a non-negative integer, 0 disables"
	    exit 1
	}
	set value [lindex $argv [incr i]]
	incr i
	if {$flag eq "-safetime"} {
	    set seconds $value
	} else {
	    set commands $value
	}
    }

    # set_limits validates the values; report a bad one the way tclsh reports a
    # bad -encoding instead of dumping errorInfo out of a startup script.
    if {[catch {::winkit::safe::set_limits $seconds $commands} err]} {
	puts stderr $err
	exit 1
    }
    return [lrange $argv $i end]
}

# Run a script file inside the safe child. Mirrors run_script's bookkeeping,
# then hands the file to the CHILD's own `source` rather than reading it here:
# only safe.tcl's AliasSource applies the accessPath check, and only it honours
# -encoding. The script's directory is in accessPath (plan decision 12), so a
# relative name works -- FileInAccessPath normalizes [file dirname] against the
# master's cwd, and extra_dirs put both that directory and the cwd on the
# list -- and AliasSource leaves the child's `info script` as the name typed
# rather than the real absolute path.
proc ::winkit::safe_script {script encoding rest} {
    global argv0 argc argv

    set argv0 $script
    set argv $rest
    set argc [llength $rest]

    set child [::winkit::safe::init $script script]
    if {$encoding ne ""} {
	set code [catch {interp eval $child [list source -encoding $encoding $script]} result opts]
    } else {
	set code [catch {interp eval $child [list source $script]} result opts]
    }
    ::winkit::finish_script $code $result $opts
}

# Evaluate piped stdin in the safe child, one complete command at a time.
#
# Mode "stdin", not "script": the master is consuming stdin and must not also
# hand it to the child (plan §2.11, decision 18). The limits are the
# script-mode numbers, armed ONCE for the whole stream -- §2.11 makes stdin
# differ from script only in the channel policy, and a piped script is still
# one script, so it gets one budget rather than a fresh one per line.
proc ::winkit::safe_stdin_loop {} {
    set child [::winkit::safe::init "" stdin]
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
	set code [catch {::winkit::safe::eval_in_child $child $buf} result opts]
	set buf ""
	if {$code == 1 || $code == 3 || $code == 4} {
	    ::winkit::report_error $result $opts
	}
    }
    exit 0
}

proc ::winkit::safe_main {argv} {
    # Sourced here rather than at the top of this file so that tclwin.exe does
    # not pay for safe.tcl on every start: the normal kit never reaches this
    # line. uplevel #0 matches how the REPL loads its win32 shim.
    uplevel #0 [list source [file join $::winkit::libdir winkit safe_master.tcl]]

    set argv [::winkit::strip_safe_flags $argv]
    set parsed [::winkit::parse_argv $argv]
    set script [dict get $parsed script]

    if {$script ne ""} {
	::winkit::safe_script $script [dict get $parsed encoding] \
		[dict get $parsed rest]
	;# safe_script does not return: it exits via finish_script
    }

    if {[::winkit::have_console]} {
	# B4: the safe REPL. The master owns the console -- TclReadLine and its
	# twapi shim cannot exist in a safe interp -- while the child runs the
	# user's code: tclreadline.tcl's TARGET wrappers send both the eval and
	# every completion lookup there.
	#
	# init copies argv0/argv/argc/tcl_interactive into the child as they
	# stand, so they are set first, per safe_master.tcl's contract; skip
	# that and every script in the child runs with tcl_interactive 0.
	#
	# tcl_rcFileName is deliberately NOT sourced here. An rc file would run
	# as the master, i.e. outside the sandbox, which is exactly what safe
	# mode exists to prevent; ::winkit::repl honours it only because that
	# kit has no sandbox.
	#
	# Limits are armed once, by init, for mode "repl". Per-line re-arming is
	# B6; until it lands the deadline is absolute, so a session that
	# outlives -safetime trips the limit and every later line fails on it.
	global argv0 tcl_interactive
	set argv0 [info nameofexecutable]
	set tcl_interactive 1

	set child [::winkit::safe::init "" repl]

	package require TclReadLine
	set shim [file join $::winkit::libdir TclReadLine tclreadline-win.tcl]
	if {[file exists $shim]} {
	    if {[catch {uplevel #0 [list source $shim]} err]} {
		puts stderr "warning: TclReadLine win32 shim failed: $err"
	    }
	}

	puts "tclsafe — Tcl [info patchlevel] safe interactive shell\
		(sandboxed: [llength [interp eval $child {package names}]] packages)"
	puts "Tab-completion: Shift-Tab always; Ctrl-t toggles plain Tab.\
		Type \"exit\" or Ctrl-d on an empty line to quit."

	TclReadLine::setTarget $child
	set ::TclReadLine::PROMPT {winkit% }

	::TclReadLine::interact
	exit 0
    }

    ::winkit::safe_stdin_loop
    ;# safe_stdin_loop does not return
    exit 0
}

# --- dispatch -----------------------------------------------------------

if {[::winkit::is_safe]} {
    ::winkit::safe_main $argv
    ;# safe_main does not return: every path through it exits
}

set ::winkit::parsed [::winkit::parse_argv $argv]
if {[dict get $::winkit::parsed script] ne ""} {
    ::winkit::run_script [dict get $::winkit::parsed script] \
	    [dict get $::winkit::parsed encoding] \
	    [dict get $::winkit::parsed rest]
    ;# run_script does not return: it exits via finish_script
}

if {[::winkit::have_console]} {
    ::winkit::repl
} else {
    ::winkit::stdin_loop
}
exit 0
