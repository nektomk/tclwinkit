# safe_master.tcl --
#
#	Safe interpreter bootstrap for tclwinkit (v0.3).
#	Runs in the MASTER interpreter, creates and manages a safe child.
#
#	Responsibilities:
#	  * load safe.tcl / safetk.tcl (parent provides API)
#	  * build accessPath (VFS walk + script dir + cwd)
#	  * create safe child interp with -accessPath
#	  * share stdin/stdout/stderr channels
#	  * provide aliases: pwd, file readable, exit
#	  * mirror argv0/argv/argc/tcl_interactive into the child
#	  * enforce limits (command/time) and handle trips
#	  * REPL and script execution live here; eval goes to child
#
#	Usage (called from main.tcl in safe mode):
#	  set child [::winkit::safe::init $scriptPath $mode]
#	where $scriptPath is the ALREADY RESOLVED script file ("" when there is
#	none, i.e. stdin and REPL modes) and $mode is "script" or "repl".
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

    # Limit configuration (defaults, overridden by CLI flags)
    variable limit_time_script   300      ;# seconds (absolute deadline)
    variable limit_cmd_script    2000000000 ;# 2·10⁹ commands
    variable limit_time_repl     60       ;# seconds per line
    variable limit_cmd_repl      500000000 ;# 5·10⁸ commands per line
}

# ----------------------------------------------------------------------
#  init -- main entry point
#
#  Called from main.tcl when safe mode is active.
#  Args: scriptPath -- resolved script file, or "" when there is none
#                     (stdin and REPL modes)
#        mode       -- "script" | "repl"
# ----------------------------------------------------------------------
proc ::winkit::safe::init {scriptPath {mode script}} {
    variable child
    variable accessPath

    # 1. Load safe.tcl and safetk.tcl from the VFS
    #
    # Guarded, because re-sourcing safe.tcl is destructive: its tail runs
    # `variable AutoPathSync 0`, so a second `init` would reset sync mode and
    # then fail on `setSyncMode 1` with "cannot set new value while Safe Base
    # child interpreters exist" whenever a child from the first call is still
    # registered. Measured in tmp/b15a-accesspath-probe.tcl section E.
    if {[llength [info commands ::safe::interpCreate]] == 0} {
	set safe_tcl    //zipfs:/app/tcl_library/safe.tcl
	set safetk_tcl  //zipfs:/app/tcl_library/safetk.tcl

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

    # 5. Share standard channels
    #
    # stdout/stderr always: the child prints to the master's console.
    # stdin is NEVER shared here. Plan §2.11 (decision 18) splits script
    # mode in two, and only the argv dispatch in main.tcl tells them apart:
    #   script from a file -> share (CI/agents pipe data into the script)
    #   script from stdin  -> do not share (the master is consuming it)
    #   interactive REPL   -> do not share (the master owns the console in
    #                         raw mode, and a child `gets stdin` blocks past
    #                         every limit -- §2.12)
    # main.tcl (B1.5/B3) shares stdin itself in the one case that wants it.
    interp share {} stdout $child
    interp share {} stderr $child

    # 6. Set up aliases in the child
    setup_aliases $child

    # 7. Mirror the master's startup globals into the child. The caller must
    #    have set them first -- main.tcl does that per mode before calling
    #    init (see copy_startup_vars).
    copy_startup_vars $child

    # 8. Apply limits (mode from caller: script/repl)
    apply_limits $child $mode

    # 9. Return child handle to caller (main.tcl continues with REPL/script)
    return $child
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
#  mode: "script"  -> 300 s / 2·10⁹ commands (CI/agent)
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

    switch -- $mode {
	script {
	    set seconds      $limit_time_script
	    set maxcommands  $limit_cmd_script
	}
	repl {
	    set seconds      $limit_time_repl
	    set maxcommands  $limit_cmd_repl
	}
	default {
	    error "unknown limit mode \"$mode\": expected script|repl"
	}
    }

    # Command limit
    interp limit $child commands -value $maxcommands

    # Time limit: absolute deadline
    interp limit $child time \
	-seconds [expr {[clock seconds] + $seconds}] \
	-milliseconds 0

    # Handler fires in the master when either limit trips
    set handler [list ::winkit::safe::limit_handler $child $mode]
    interp limit $child commands -command $handler
    interp limit $child time -command $handler

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
