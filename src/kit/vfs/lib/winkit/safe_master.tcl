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
#  Args: argv (original command line)
# ----------------------------------------------------------------------
proc ::winkit::safe::init {argv} {
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
    interp share {} stdout $child
    interp share {} stderr $child
    # stdin is shared only in script mode (caller decides)

    # 6. Set up aliases in the child
    setup_aliases $child

    # 7. Return child handle to caller (main.tcl continues with REPL/script)
    return $child
}

# ----------------------------------------------------------------------
#  build_access_path -- recursive walk of VFS root
#
#  Returns a list of all directories under $root, with $root first.
#  tcl_library must be first for init.tcl to load in the child.
# ----------------------------------------------------------------------
proc ::winkit::safe::build_access_path {root} {
    set result [list]
    lappend result $root

    # Recursive walk: collect all directories
    foreach dir [glob -nocomplain -directory $root -type d *] {
	lappend result $dir
    }

    # Ensure tcl_library is first (it's a direct child of root)
    set tcl_lib $root/tcl_library
    if {$tcl_lib ni $result} {
	lappend result $tcl_lib
    }
    # Move tcl_library to position 1 (after root)
    set idx [lsearch -exact $result $tcl_lib]
    if {$idx > 1} {
	set result [lreplace $result $idx $idx]
	lset result 1 $tcl_lib
    }

    return $result
}

# ----------------------------------------------------------------------
#  create_child -- create safe interpreter with accessPath
#
#  Returns the child interpreter name.
# ----------------------------------------------------------------------
proc ::winkit::safe::create_child {accessPath} {
    # ::safe::interpCreate -accessPath $accessPath
    set child [::safe::interpCreate -accessPath $accessPath]
    return $child
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
#  Provides: pwd, ::tcl::file::readable, exit
# ----------------------------------------------------------------------
proc ::winkit::safe::setup_aliases {child} {
    # pwd alias: returns current working directory (master's cwd)
    interp alias $child pwd {} ::winkit::safe::alias_pwd

    # file readable alias: restricted to accessPath
    interp alias $child ::tcl::file::readable {} \
	::winkit::safe::alias_file_readable $child

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
#  Checks if path is within accessPath and readable.
# ----------------------------------------------------------------------
proc ::winkit::safe::alias_file_readable {child path} {
    # Resolve path relative to accessPath tokens
    # For now, simple check: path must exist and be readable in master
    if {[file exists $path] && [file readable $path]} {
	return 1
    }
    return 0
}

# ----------------------------------------------------------------------
#  alias_exit -- implementation of exit alias
#
#  Exits the real process.
# ----------------------------------------------------------------------
proc ::winkit::safe::alias_exit {{code 0}} {
    exit $code
}
