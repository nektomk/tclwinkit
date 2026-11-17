# safe_master.tcl --
#
#	Safe interpreter bootstrap for tclwinkit (v0.3).
#	Runs in the MASTER interpreter, creates and manages a safe child.
#
#	Responsibilities:
#	  * load safe.tcl / safetk.tcl (parent provides API)
#	  * build accessPath (VFS walk + script dir + cwd)
#	  * create safe child interp with -accessPath
#	  * share the channels this mode allows (stdin only for "script")
#	  * provide aliases: pwd, file readable, exit
#	  * mirror argv0/argv/argc/tcl_interactive into the child
#	  * enforce limits (command/time) and handle trips
#	  * REPL and script execution live here; eval goes to child
#	  * "gui" mode only: create the safe-Tk host window for the child
#
#	Usage (called from main.tcl in safe mode):
#	  set child [::winkit::safe::init $scriptPath $mode ?$geometry?]
#	where $scriptPath is the ALREADY RESOLVED script file ("" when there is
#	none) and $mode is one of four values. The first three match the three
#	rows of the stdin policy table in plan §2.11 (decision 18):
#	  script -- script read from a FILE; stdin IS shared with the child
#	  stdin  -- script read from standard input; stdin is NOT shared, the
#	          master is consuming it
#	  repl   -- interactive loop; stdin is NOT shared, the master owns the
#	          console in raw mode (see plan §2.12)
#	The fourth stands outside that table because a GUI applet never reads
#	the console:
#	  gui    -- safe-Tk host window for an applet; stdin is NOT shared and
#	          no resource limit is armed (plan §1 decisions 19, 20)
#	$geometry is read by "gui" only and ignored by every other mode; the
#	caller passes the -geometry string the user asked for, which Tk has
#	already published in the master's ::geometry (see create_gui_host).
#	main.tcl owns argv parsing -- it already handles -encoding and the
#	"first non-dash argument" rule -- so this file never looks at argv.
#
#	Contract: the caller must have set the master's ::argv0, ::argv, ::argc
#	and ::tcl_interactive BEFORE calling init, because step 7 copies them
#	into the child as they stand. main.tcl already sets them per mode.
#

namespace eval ::winkit::safe {
    # Child interpreter handle (set by create_child)
    variable child ""

    # AccessPath list (populated by build_access_path)
    variable accessPath {}

    # Recognised run modes. The first three are one per row of the stdin
    # policy table in plan §2.11 (decision 18); "script" and "stdin" differ
    # ONLY in whether the child gets stdin -- they share the same limits.
    # "gui" is the fourth mode, added in B5 for the safe-Tk host: it shares
    # nothing with the stdin table because a GUI applet never reads the
    # console, so stdin is not shared (see step 5).
    variable modes {script stdin repl gui}

    # Limit configuration (defaults, overridden by CLI flags)
    variable limit_time_script   300      ;# seconds (absolute deadline)
    variable limit_cmd_script    2000000000 ;# 2·10⁹ commands
    variable limit_time_repl     60       ;# seconds per line
    variable limit_cmd_repl      500000000 ;# 5·10⁸ commands per line

    # B5: the GUI mode gets NO resource limit (user decision 2026-11-16). A
    # safe-Tk child sits in an event loop, and plan §4 records that the time
    # limit fires inside `vwait` as well as in a busy loop, so any absolute
    # deadline would kill a legitimate applet while it is merely open. The
    # command counter is left off too: an idling applet executes almost no
    # commands, and the user can always close the host window -- the SafeTk
    # toplevel carries its own Delete button -- or kill the process.
    # 0 means "disabled" here and apply_limits turns it into the empty string
    # that `interp limit` wants; a literal 0 would instead mean a 1970
    # deadline and a zero-command budget (see the comment in apply_limits).
    variable limit_time_gui      0        ;# 0 = no time limit
    variable limit_cmd_gui       0        ;# 0 = no command limit
}

# ----------------------------------------------------------------------
#  init -- main entry point
#
#  Called from main.tcl in the console kit and from safe_main_gui.tcl in the
#  GUI kit, in both cases when safe mode is active.
#  Args: scriptPath -- resolved script file, or "" when there is none
#                     (stdin, REPL and GUI modes)
#        mode       -- "script" | "stdin" | "repl" | "gui" (see file header)
#        geometry   -- the -geometry string the user asked for, used only by
#                     "gui" to size the host window and ignored by every other
#                     mode. The caller reads it from the master's ::geometry,
#                     which Tk itself sets while parsing its -X options (see
#                     create_gui_host for the measurement behind this).
# ----------------------------------------------------------------------
proc ::winkit::safe::init {scriptPath {mode script} {geometry {}}} {
    variable child
    variable accessPath
    variable modes

    # 0. Reject an unknown mode before creating anything. The mode drives both
    #    the stdin policy (step 5) and the limits (step 8), so a typo must not
    #    get as far as handing back a mis-configured child.
    if {$mode ni $modes} {
	error "unknown mode \"$mode\": expected [join $modes |]"
    }

    # 1. Load safe.tcl and safetk.tcl from the VFS
    #
    # Guarded, because re-sourcing safe.tcl is destructive: its tail runs
    # `variable AutoPathSync 0`, so a second `init` would reset sync mode and
    # then fail on `setSyncMode 1` with "cannot set new value while Safe Base
    # child interpreters exist" whenever a child from the first call is still
    # registered. Measured in tmp/b15a-accesspath-probe.tcl section E.
    if {[llength [info commands ::safe::interpCreate]] == 0} {
	set safe_tcl    //zipfs:/app/tcl_library/safe.tcl

	# safe.tcl ships in tcl_library and safetk.tcl in tk_library: they are
	# NOT neighbours, and looking for safetk.tcl beside safe.tcl silently
	# finds nothing, because the guard below is an [file exists]. Measured
	# inside a shipped GUI image (tmp/b53-safetk-probe.tcl run on a copy of
	# dist/mingw/tkwin.exe outside the workspace):
	#   //zipfs:/app/tcl_library/safe.tcl    exists=1
	#   //zipfs:/app/tcl_library/safetk.tcl  exists=0
	#   //zipfs:/app/tk_library/safetk.tcl   exists=1
	#   ::safe::loadTk defined before any source = 0, after sourcing the
	#   tk_library copy = 1
	# safe.tcl contains no occurrence of "loadTk" at all; safetk.tcl defines
	# it (lines 62 and 64 of the Tk 9.0.4 copy). Nothing auto-loads it --
	# it is not a package.
	#
	# The guard stays [file exists] rather than becoming an error: the
	# CONSOLE image has no tk_library at all (assemble-*-kit.ps1 copies it
	# only in the -WithTk pass), and the three console modes never need
	# ::safe::loadTk. A missing safetk.tcl in gui mode is still reported, by
	# create_gui_host, which cannot proceed without it and names it.
	set safetk_tcl  //zipfs:/app/tk_library/safetk.tcl

	if {![file exists $safe_tcl]} {
	    error "safe.tcl not found at $safe_tcl"
	}
	source $safe_tcl

	if {[file exists $safetk_tcl]} {
	    source $safetk_tcl
	}
    }

    # 2. Enable sync mode (auto_path in child = opaque tokens)
    ::safe::setSyncMode 1

    # 3. Build accessPath: the VFS walk, then the script's own directory and
    #    the process cwd (plan decisions 12 and 14).
    set accessPath [build_access_path //zipfs:/app $scriptPath]

    # 4. Create the safe child interpreter
    set child [create_child $accessPath]

    # 5. Share the channels this mode allows
    #
    # stdout/stderr always: the child prints to the master's console.
    # stdin only in mode "script", i.e. a script read from a FILE. Plan §2.11
    # (decision 18) has exactly three rows, and the three console modes are
    # those rows:
    #   script from a file -> share; the master never reads the console, and
    #                         CI/agents pipe data into the script
    #   script from stdin  -> do not share; the master is consuming stdin
    #   interactive REPL   -> do not share; the master owns the console in raw
    #                         mode (TclReadLine + the twapi shim), and a child
    #                         `gets stdin` would block past every limit (§2.12)
    # The fourth mode, "gui", is not a row of that table at all: an applet
    # draws its own windows and never reads the console, so stdin is not
    # shared either -- for absence of a reader, not because the master is
    # holding the channel. stdout/stderr are still shared, but whether they
    # reach anyone is up to how the process was launched: tksafe.exe is a
    # windows-subsystem executable with its console suppressed, so it writes
    # into an inherited handle when a shell started it and into nothing at all
    # when it was double-clicked (NO-CONSOLE block in kit_safe_wish_main.c).
    # Sharing costs nothing and is the only route an applet's `puts` has.
    #
    # The child cannot `fconfigure` stdin -- it is hidden -- but it CAN `close`
    # it, and that is harmless to the master: `interp share` refcounts the
    # channel, so a child's close drops only the child's own reference.
    # Measured in tmp/b15c-close-probe.tcl: with data still pending, after the
    # child closed stdin the master read the next line normally, and a NEW child
    # could share the same channel and read the one after that. Only the
    # master's own close destroys the channel. Plan §2.11 finding 3 claims the
    # master is left without input; that measurement was confounded (the stream
    # was already at EOF before the close was tried) and is corrected there.
    interp share {} stdout $child
    interp share {} stderr $child
    if {$mode eq "script"} {
	interp share {} stdin $child
    }

    # 6. Set up aliases in the child
    setup_aliases $child

    # 7. Mirror the master's startup globals into the child. The caller must
    #    have set them first -- main.tcl does that per mode before calling
    #    init (see copy_startup_vars).
    copy_startup_vars $child

    # 8. Apply limits (mode from caller: script/stdin/repl/gui)
    apply_limits $child $mode

    # 9. GUI mode only: hand the child its host toplevel. Done AFTER the
    #    limits so a trip cannot land between Tk's initialisation and the
    #    window existing, and after copy_startup_vars because the child's Tk
    #    initialisation reads what the master published there.
    if {$mode eq "gui"} {
        create_gui_host $child $geometry
    }

    # 10. Return child handle to caller (main.tcl continues with REPL/script)
    return $child
}

# ----------------------------------------------------------------------
#  create_gui_host -- give a safe child its Tk host window (B5)
#
#  ::safe::loadTk creates the decorated host toplevel itself -- a toplevel
#  with class SafeTk, title "Untrusted Tcl applet (<child>)" and a warning
#  bar carrying a Delete button -- embeds the child's "." inside it and then
#  returns the CHILD handle, not the window name. The host is therefore found
#  by diffing `winfo children .` across the call instead of guessing
#  ".safe1" (safetk names hosts from an internal counter) or reading
#  ::safe's private state, and the candidate is then confirmed by its window
#  class so a false match cannot pass silently.
#
#  $geometry is the -geometry string the user asked for, which the CALLER
#  supplies rather than this proc reading it out of a global. Tk empties argv
#  while consuming its -X options, so by the time the startup script runs the
#  request is gone from $argv -- but Initialize() first stores the string
#  verbatim in the master's ::geometry (tkWindow.c:3441-3451:
#  Tcl_SetVar2Ex(interp, "geometry", ...) immediately before applying
#  `wm geometry . $geometryObj`). Measured on dist/mingw/tkwin.exe with
#  tmp/b52-geometry-var-probe.tcl: `-geometry 600x400+40+40` leaves argc=0,
#  argv={} and ::geometry = 600x400+40+40, and the abbreviated form
#  `-g 300x200+10+10` works the same way because Tcl_ParseArgsObj matches
#  options by unique prefix. Reading Tk's own variable beats intercepting
#  argv in C, which would have to reimplement that prefix matching to accept
#  `-g` at all (plan §2.7.1).
#
#  Taking it as an argument keeps this file free of any dependency on that
#  Tk-internal variable name and on Tk being loaded at all, which is what
#  lets the console-side probe exercise apply_limits and the mode table
#  without a Tk master. The child's "." ends up shorter than the request by
#  the height of the host's warning bar -- plan section 2.5 measured 500x400
#  on the host giving 500x367 in the child.
#
#  The child cannot compete for this value: the safe branch of Initialize()
#  takes its Tk arguments from the parent's ::safe::TkInit result, not from
#  the master's argv (tkWindow.c:3303), so with no -use/-display passed to
#  ::safe::loadTk the child's geometryObj stays NULL and it sets no ::geometry
#  of its own.
#
#  The master's own "." is withdrawn: it holds no user code, everything the
#  applet owns lives in the host, and leaving it mapped would put a second,
#  empty window next to the real one (decision 2026-11-16).
#
#  The title is deliberately NOT set. Plan decision 17 keeps Tk's own
#  "Untrusted Tcl applet (<child>)" so the user always sees that the code is
#  sandboxed; overriding it from a user-supplied -name would remove exactly
#  that warning.
# ----------------------------------------------------------------------
proc ::winkit::safe::create_gui_host {child geometry} {
    if {![winfo exists .]} {
        error "gui mode needs a Tk master: \".\" does not exist"
    }
    if {[llength [info commands ::safe::loadTk]] == 0} {
        error "gui mode needs safetk.tcl: ::safe::loadTk is not defined\
                (see step 1 -- it ships in tk_library, not tcl_library)"
    }

    set before [winfo children .]
    ::safe::loadTk $child
    set added {}
    foreach w [winfo children .] {
        if {$w ni $before} {
            lappend added $w
        }
    }
    if {[llength $added] != 1} {
        error "::safe::loadTk created [llength $added] host window(s):\
                expected exactly 1 (added: $added)"
    }
    set host [lindex $added 0]

    # Confirm this really is the SafeTk host and not an unrelated toplevel
    # that happened to appear during the call.
    if {[winfo class $host] ne "SafeTk"} {
        error "host window $host has class \"[winfo class $host]\",\
                expected \"SafeTk\""
    }

    if {$geometry ne ""} {
        wm geometry $host $geometry
    }

    # The master's "." carries no user code; hide it so the applet's host is
    # the only window on screen.
    wm withdraw .

    return $host
}

# ----------------------------------------------------------------------
#  build_access_path -- VFS walk plus the real-filesystem directories
#
#  Returns every directory under $root (//zipfs:/app) plus $root itself,
#  with tcl_library FIRST: safe.tcl makes accessPath(0) the child's
#  tcl_library and interpCreate fails when it holds no init.tcl.
#
#  $root is included deliberately -- init.tcl puts [file dirname
#  $tcl_library] (= //zipfs:/app) on a normal interp's auto_path, and the
#  default tclPkgUnknown finds //zipfs:/app/lib/pkgIndex.tcl from there
#  (see lib/kit_init.tcl). Dropping the root would make the child's
#  package discovery depend on lib/ happening to be listed separately.
#
#  After the VFS come the real directories from extra_dirs: the script's
#  own directory (decision 12 -- `source sibling.tcl` must work) and the
#  process cwd (decision 14). They go last so the kit's own packages win
#  the child's auto_path lookup.
# ----------------------------------------------------------------------
proc ::winkit::safe::build_access_path {root {scriptPath ""}} {
    set tcl_lib [file join $root tcl_library]

    set result [list $root]
    collect_dirs $root result

    foreach d [extra_dirs $scriptPath] {
	if {[lsearch -exact $result $d] < 0} {
	    lappend result $d
	}
    }

    set idx [lsearch -exact $result $tcl_lib]
    if {$idx < 0} {
	error "tcl_library not found at $tcl_lib"
    }
    set result [lreplace $result $idx $idx]
    return [linsert $result 0 $tcl_lib]
}

# ----------------------------------------------------------------------
#  extra_dirs -- real-filesystem directories to add to the accessPath
#
#  Decisions 12 and 14: the script's directory and the process cwd both go
#  in. Paths are normalized so a relative script name yields the cwd
#  rather than "." (which would then be added twice), and only existing
#  directories are returned -- safe.tcl tokenizes what it is given, and a
#  bogus entry would surface later as a confusing lookup failure.
#
#  A script path that does not exist contributes nothing here; reporting
#  that is the caller's job, exactly as it is for stock tclsh.
# ----------------------------------------------------------------------
proc ::winkit::safe::extra_dirs {scriptPath} {
    set out {}

    if {$scriptPath ne ""} {
	set scriptDir [file normalize [file dirname $scriptPath]]
	if {[file isdirectory $scriptDir]} {
	    lappend out $scriptDir
	}
    }

    set cwd [file normalize [pwd]]
    if {[file isdirectory $cwd]} {
	lappend out $cwd
    }

    return $out
}

# ----------------------------------------------------------------------
#  collect_dirs -- depth-first directory walk
#
#  Appends every subdirectory of $dir to the variable named by $accVar.
# ----------------------------------------------------------------------
proc ::winkit::safe::collect_dirs {dir accVar} {
    upvar 1 $accVar acc
    foreach sub [glob -nocomplain -directory $dir -types d *] {
	lappend acc $sub
	collect_dirs $sub acc
    }
    return
}

# ----------------------------------------------------------------------
#  create_child -- create safe interpreter with accessPath
#
#  Returns the child interpreter name. Channel sharing deliberately does
#  NOT happen here: init owns the channel policy (step 5, plan §2.11).
# ----------------------------------------------------------------------
proc ::winkit::safe::create_child {accessPath} {
    return [::safe::interpCreate -accessPath $accessPath]
}

# ----------------------------------------------------------------------
#  eval_in_child -- evaluate a script in the safe child
#
#  Wrapper for interp eval with error handling.
# ----------------------------------------------------------------------
proc ::winkit::safe::eval_in_child {child script} {
    return [interp eval $child $script]
}

# ----------------------------------------------------------------------
#  copy_startup_vars -- mirror the master's startup globals into the child
#
#  A safe child starts with argv0/argv/argc unset and tcl_interactive at 0
#  (measured in tmp/b15b-argv-probe.tcl), so a script running inside it
#  cannot see its own command line. Copy what the master already has:
#  main.tcl sets those globals per mode before calling init -- run_script
#  sets argv0 to the script and argv/argc to the remaining arguments, repl
#  sets argv0 to [info nameofexecutable] and tcl_interactive to 1, and
#  stdin_loop leaves them as Tcl_Main set them. Copying instead of
#  re-deriving keeps that per-mode logic in exactly one place.
#
#  argv0 crosses over as the real path the user typed, not a $p(:N:) token.
#  The pwd alias already discloses the real cwd (decision 13, ruled
#  2026-11-14 to keep it), and nothing here reveals a path the child could
#  not already read.
#
#  Each variable needs its own [list set ...]: packing several `set`
#  commands into one list would hand interp eval a single command with far
#  too many arguments. The list form also preserves argv elements that
#  contain spaces, e.g. {two words}.
#
#  Nothing in Tcl enforces argc == [llength argv] -- a child happily reports
#  argc 99 beside a three-element argv -- so the invariant is inherited from
#  the master rather than recomputed here.
# ----------------------------------------------------------------------
proc ::winkit::safe::copy_startup_vars {child} {
    interp eval $child [list set ::argv0 $::argv0]
    interp eval $child [list set ::argv $::argv]
    interp eval $child [list set ::argc $::argc]
    interp eval $child [list set ::tcl_interactive $::tcl_interactive]
    return
}

# ----------------------------------------------------------------------
#  setup_aliases -- create safe aliases in the child
#
#  Provides: pwd, ::tcl::file::readable (restricted to accessPath), exit
# ----------------------------------------------------------------------
proc ::winkit::safe::setup_aliases {child} {
    variable accessPath

    # pwd alias: returns current working directory (master's cwd)
    interp alias $child pwd {} ::winkit::safe::alias_pwd

    # file readable alias: restricted to accessPath
    # The child sees token paths ($p(:0:), etc.), so we must translate
    # and verify against the accessPath list.
    interp alias $child ::tcl::file::readable {} \
	::winkit::safe::alias_file_readable $child $accessPath

    # exit alias: real process exit
    interp alias $child exit {} ::winkit::safe::alias_exit
}

# ----------------------------------------------------------------------
#  alias_pwd -- implementation of pwd alias
# ----------------------------------------------------------------------
proc ::winkit::safe::alias_pwd {} {
    return [pwd]
}

# ----------------------------------------------------------------------
#  alias_file_readable -- implementation of file readable alias
#
#  Checks if the path (translated from tokens) is within accessPath
#  and is readable. Uses safe.tcl's TranslatePath for token resolution.
# ----------------------------------------------------------------------
proc ::winkit::safe::alias_file_readable {child accessPath path} {
    # safe.tcl provides TranslatePath to convert tokens to real paths
    # It will throw an error if the path is not in accessPath
    try {
	set real_path [::safe::TranslatePath $child $path]
	# Double-check with FileInAccessPath for security
	::safe::FileInAccessPath $child $real_path
	# Now check actual file existence and readability
	if {[file exists $real_path] && [file readable $real_path]} {
	    return 1
	}
	return 0
    } on error msg {
	# Path translation failed (not in accessPath, invalid token, etc.)
	return 0
    }
}

# ----------------------------------------------------------------------
#  alias_exit -- implementation of exit alias
#
#  Exits the real process.
# ----------------------------------------------------------------------
proc ::winkit::safe::alias_exit {{code 0}} {
    exit $code
}

# ----------------------------------------------------------------------
#  apply_limits -- set command/time limits on the child
#
#  mode: "script"  -> 300 s / 2·10⁹ commands (CI/agent, script from a file)
#        "stdin"   -> same numbers; the only difference from "script" is that
#                     the child gets no stdin (see init step 5)
#        "repl"    -> 60 s / 5·10⁸ commands per line; the REPL loop calls
#                     this again before each line to re-arm
#
#  Time limit is an ABSOLUTE deadline (clock seconds + N), NOT "in N
#  seconds": -milliseconds alone would set a 1970 deadline and trip
#  instantly (see plan §2.8). The -command script runs in the MASTER at
#  trip time and does NOT re-arm -- see limit_handler for the measured
#  reason.
# ----------------------------------------------------------------------
proc ::winkit::safe::apply_limits {child mode} {
    variable limit_time_script
    variable limit_cmd_script
    variable limit_time_repl
    variable limit_cmd_repl
    variable limit_time_gui
    variable limit_cmd_gui
    variable modes

    switch -- $mode {
	script -
	stdin {
	    set seconds      $limit_time_script
	    set maxcommands  $limit_cmd_script
	}
	repl {
	    set seconds      $limit_time_repl
	    set maxcommands  $limit_cmd_repl
	}
	gui {
	    # B5: no resource limit for a GUI applet (user decision
	    # 2026-11-16). Both stay 0, which the block below turns into the
	    # empty string that `interp limit` reads as "not set". An absolute
	    # time deadline cannot work here at all: plan §4 records that the
	    # time limit fires inside `vwait` as well as in a busy loop, so any
	    # finite value would kill a legitimate applet while it is merely
	    # open and idle. The command counter is left off too -- an idling
	    # applet runs almost no commands, and the SafeTk host carries its
	    # own Delete button for the case where it does.
	    set seconds      $limit_time_gui
	    set maxcommands  $limit_cmd_gui
	}
	default {
	    error "unknown limit mode \"$mode\": expected [join $modes |]"
	}
    }

    # Apply each limit, or remove it when its configured value is 0.
    #
    # 0 MUST become the empty string, not a literal 0. doc/interp.n says both
    # -seconds and -value accept "" to mean "not set", while a numeric 0 means
    # something entirely different: -seconds 0 is an ABSOLUTE deadline at the
    # 1970 epoch and -value 0 is a command budget of zero, so either one trips
    # on the first limit check. Measured in tmp/b3-limit-zero-probe.tcl: under
    # `-seconds 0 -milliseconds 0` a ~3M-iteration loop died with `time limit
    # exceeded` after 0 ms, and `-value 0` gave `command count limit exceeded`
    # on a trivial eval, while `-seconds {}` let ~2 s of work finish (rc=0).
    # Passing 0 through would therefore make `-safetime 0` / `-safecmds 0`
    # (documented in plan §4 as "disabled") kill the script instantly -- the
    # exact opposite of what was asked for.
    #
    # A trivial eval under `-seconds 0` does NOT trip, because time limits are
    # only checked every -granularity points; that is why the first version of
    # this measurement looked like "0 means disabled". See
    # tmp/b3-limit-off-probe.tcl section A for the misleading case.
    if {$maxcommands > 0} {
	interp limit $child commands -value $maxcommands
    } else {
	interp limit $child commands -value {}
    }

    if {$seconds > 0} {
	interp limit $child time \
	    -seconds [expr {[clock seconds] + $seconds}] \
	    -milliseconds 0
    } else {
	interp limit $child time -seconds {}
    }

    # Handler fires in the master when either limit trips. Installed for both
    # types even when one is disabled: re-arming later (REPL per line, or a
    # future limit change) must not leave a type without its handler.
    set handler [list ::winkit::safe::limit_handler $child $mode]
    interp limit $child commands -command $handler
    interp limit $child time -command $handler

    return
}

# ----------------------------------------------------------------------
#  set_limits -- override the defaults from the command line
#
#  Called by main.tcl for -safetime / -safecmds BEFORE init, so the values
#  are already in place when apply_limits runs. Both apply to every mode:
#  an operator who passes -safetime 60 means "60 seconds" whether this ends
#  up being a script run or a REPL line, and guessing per mode would make
#  the flag mean two different things.
#
#  A value of 0 means DISABLED and is stored as 0; apply_limits turns it
#  into the empty string that interp limit wants (see the comment there --
#  a literal 0 is an epoch deadline, not "no limit").
#
#  Negative or non-integer values are rejected here rather than reaching
#  interp limit, because the value arrives from a user's command line.
# ----------------------------------------------------------------------
proc ::winkit::safe::set_limits {{seconds {}} {commands {}}} {
    variable limit_time_script
    variable limit_cmd_script
    variable limit_time_repl
    variable limit_cmd_repl
    variable limit_time_gui
    variable limit_cmd_gui

    foreach {val name} [list $seconds -safetime $commands -safecmds] {
	if {$val eq ""} {
	    continue
	}
	if {![string is integer -strict $val] || $val < 0} {
	    error "invalid $name value \"$val\": expected a non-negative integer\
		    (0 disables the limit)"
	}
    }

    if {$seconds ne ""} {
	set limit_time_script $seconds
	set limit_time_repl   $seconds
	set limit_time_gui    $seconds
    }
    if {$commands ne ""} {
	set limit_cmd_script $commands
	set limit_cmd_repl   $commands
	set limit_cmd_gui     $commands
    }
    return
}

# ----------------------------------------------------------------------
#  limit_handler -- runs in the MASTER when a limit trips
#
#  Reports the trip and deliberately does NOT re-arm. doc/interp.n:
#  "If those callbacks increase or remove the limit, execution within the
#  (previously) limited interpreter continues" -- measured in
#  tmp/b14-limit-probe.tcl: a re-arming handler fired 5 trips out of a
#  single `interp eval`, so a runaway loop would never stop. Leaving the
#  limit in force makes the error propagate to the master's interp eval,
#  which reports it; the child stays usable afterwards (probe case D).
#
#  Re-arming for the REPL is the per-line loop's job: call apply_limits
#  with mode "repl" before evaluating each line.
# ----------------------------------------------------------------------
proc ::winkit::safe::limit_handler {child mode} {
    puts stderr "safe: $mode limit exceeded in child \"$child\""
    return
}
