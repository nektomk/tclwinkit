# safe_master.tcl --
#
#	Safe interpreter bootstrap for tclwinkit (v0.3).
#	Runs in the MASTER interpreter, creates and manages a safe child.
#
#	Responsibilities:
#	  * load safe.tcl / safetk.tcl (parent provides API)
#	  * build accessPath (recursive walk of //zipfs:/app)
#	  * create safe child interp with -accessPath
#	  * share stdin/stdout/stderr channels
#	  * provide aliases: pwd, file readable, exit
#	  * enforce limits (command/time) and handle trips
#	  * REPL and script execution live here; eval goes to child
#
#	Usage (called from main.tcl in safe mode):
#	  ::winkit::safe::init $argv
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
#  Args: argv (original command line), mode ("script" | "repl")
# ----------------------------------------------------------------------
proc ::winkit::safe::init {argv {mode script}} {
    variable child
    variable accessPath

    # 1. Load safe.tcl and safetk.tcl from the VFS
    set safe_tcl    //zipfs:/app/tcl_library/safe.tcl
    set safetk_tcl  //zipfs:/app/tcl_library/safetk.tcl

    if {![file exists $safe_tcl]} {
	error "safe.tcl not found at $safe_tcl"
    }
    source $safe_tcl

    if {[file exists $safetk_tcl]} {
	source $safetk_tcl
    }

    # 2. Enable sync mode (auto_path in child = opaque tokens)
    ::safe::setSyncMode 1

    # 3. Build accessPath (recursive walk of //zipfs:/app)
    set accessPath [build_access_path //zipfs:/app]

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

    # 7. Apply limits (mode from caller: script/repl)
    apply_limits $child $mode

    # 8. Return child handle to caller (main.tcl continues with REPL/script)
    return $child
}

# ----------------------------------------------------------------------
#  build_access_path -- recursive walk of the VFS root
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
# ----------------------------------------------------------------------
proc ::winkit::safe::build_access_path {root} {
    set tcl_lib [file join $root tcl_library]

    set result [list $root]
    collect_dirs $root result

    set idx [lsearch -exact $result $tcl_lib]
    if {$idx < 0} {
	error "tcl_library not found at $tcl_lib"
    }
    set result [lreplace $result $idx $idx]
    return [linsert $result 0 $tcl_lib]
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
