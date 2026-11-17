# safe_main_gui.tcl --
#
#	Startup script of the SAFE GUI kit (tksafe.exe), evaluated by
#	Tk_MainEx in the MASTER interpreter.
#
#	Why this file exists at all (plan section 3.1, decision 20). The GUI
#	image carries no root main.tcl, deliberately: TclZipfs_AppHook promotes
#	/main.tcl to the startup script for ANY exe carrying the image
#	(tclZipfs.c:6637-6641), and that image is shared with tkwin.exe, which
#	must keep behaving exactly like stock wish. Left to itself Tk_MainEx
#	would take argv[1] as the script and evaluate it in the fully privileged
#	master -- a sandbox bypass in the one executable named "safe". So
#	kit_safe_wish_main.c calls Tcl_SetStartupScript on this file from
#	Tcl_AppInit, and Tk_MainEx re-reads the slot afterwards (tkMain.c:323,
#	"Must fetch it again, as the appInitProc might have reset it"). Living
#	under lib/winkit/ instead of at the image root is what keeps this file
#	invisible to TclZipfs_AppHook.
#
#	What is already true when this file runs. Tk_MainEx parsed the command
#	line BEFORE calling the C stub (tkMain.c:246-267) and published
#	argv0/argc/argv (tkMain.c:278) and tcl_interactive (tkMain.c:306) from
#	the result, so:
#	  * argv0 is the user's script name, and argv/argc are the arguments
#	    that followed it -- safe_master.tcl copies all of them into the
#	    child, which is why nothing here re-derives them;
#	  * tcl_interactive is 0, because it is computed as !path and a script
#	    was found;
#	  * Tk's own options are already gone from argv: Initialize() parses
#	    them out of the argv VARIABLE (tkWindow.c:3197-3211, 3311-3340) and
#	    leaves unrecognized ones behind instead of failing, because it
#	    passes a rest pointer (tclIndexObj.c:1083-1098).
#
#	The C stub's SAFE-HANDOVER block publishes two more variables, because
#	it is the only place that can still see them:
#	  ::winkit::gui_script    the script name, or "" when there was none
#	  ::winkit::gui_encoding  its -encoding value, or "" when there was none
#	Both are read out of the startup-script slot before that slot is
#	overwritten. -encoding in particular survives nowhere else: argv no
#	longer holds it and Initialize() never sees it. This file treats the two
#	as a contract and deliberately does NOT default them -- an unset
#	variable means the process did not come through kit_safe_wish_main.c,
#	and that must fail loudly rather than quietly run no applet at all.
#
#	Two outcomes, and only two:
#	  gui_script eq "" -> usage in a MessageBox, exit 1 (decision 21)
#	  otherwise        -> the applet runs in a safe child and this file
#	                      RETURNS normally, so that Tk_MainEx reaches
#	                      Tk_MainLoop() (tkMain.c:374) and the process lives
#	                      until its last window goes away
#
#	No resource limit is armed in gui mode (decision 19). The time limit
#	fires inside vwait as well as in a busy loop, so any finite deadline
#	would kill a legitimate applet merely for being open. -safetime and
#	-safecmds are consequently not recognized here, and that shows: one of
#	them before the script name makes argv[1] start with a dash, so
#	Tk_MainEx finds no script and the user gets the usage dialog.

namespace eval ::winkit::gui {}

# ----------------------------------------------------------------------
#  usage_text -- what the dialog says when no script was named
#
#  Built as a list of literal lines rather than one backslash-continued
#  string: inside a quoted Tcl string a trailing backslash swallows the
#  newline AND the following indentation and emits a single space, which
#  would put a stray space at the start of every wrapped line.
# ----------------------------------------------------------------------
proc ::winkit::gui::usage_text {} {
    set lines {
	{tksafe.exe -- run a Tcl/Tk applet in a safe interpreter}
	{}
	{Usage: tksafe.exe ?-encoding E? script.tcl ?Tk options? ?arg ...?}
	{}
	{The script name comes first. -encoding is read immediately before}
	{it, while Tk's own options (-geometry, -name, -display, -sync,}
	{-use, -visual, -colormap) are taken from what follows it, so}
	{"tksafe.exe -geometry 600x400 app.tcl" finds no script at all.}
	{}
	{The applet runs in a sandboxed child interpreter and draws into a}
	{host window titled "Untrusted Tcl applet" (plan decision 17 keeps}
	{Tk's own title, so the sandbox stays visible to the user).}
	{}
	{There is no interactive mode: this executable has no console, so a}
	{startup without a script name can only report this message.}
    }
    return [join $lines \n]
}

# ----------------------------------------------------------------------
#  show_usage -- decision 21: usage in a MessageBox, then exit 1
#
#  A MessageBox rather than stderr because there is no stderr to reach:
#  tksafe.exe is a windows-subsystem executable whose console is suppressed
#  (the NO-CONSOLE block in kit_safe_wish_main.c sets consoleRequired to
#  FALSE), so when it is double-clicked its output goes nowhere at all. This
#  runs in the MASTER, which is a full kit -- the dialogs that do not work in
#  a safe-Tk child (plan section 2.6) are a different matter.
#
#  "." is withdrawn first. The master window holds no user code, and leaving
#  it mapped would put an empty default-sized window behind the dialog.
#  create_gui_host withdraws it too on the path that does have a script.
# ----------------------------------------------------------------------
proc ::winkit::gui::show_usage {} {
    wm withdraw .
    tk_messageBox -title "tclwinkit safe GUI kit" -icon info -type ok \
	    -message [usage_text]
    exit 1
}

# ----------------------------------------------------------------------
#  host_geometry -- the -geometry the user asked for, or ""
#
#  Tk's Initialize() stores the string verbatim in the master's ::geometry
#  immediately before applying it (tkWindow.c:3441-3451), and leaves the
#  variable unset when no such option was given. Measured on the healthy
#  dist/mingw/tkwin.exe with tmp/b52-geometry-var-probe.tcl:
#  `-geometry 600x400+40+40` gives ::geometry = 600x400+40+40, the abbrevi-
#  ated `-g 300x200+10+10` gives 300x200+10+10 because Tcl_ParseArgsObj
#  matches options by unique prefix, and no flag at all gives
#  `info exists ::geometry` = 0 -- in all three cases with argc 0 and argv
#  empty, i.e. the request is nowhere else (plan section 2.7.1).
#
#  The child cannot compete for the value: the safe branch of Initialize()
#  takes its Tk arguments from the parent's ::safe::TkInit result rather than
#  from the master's argv (tkWindow.c:3303), so its own geometryObj stays
#  NULL. create_gui_host takes the string as an argument and applies it to
#  the SafeTk host, which keeps safe_master.tcl free of both this Tk-internal
#  variable name and any dependency on Tk being loaded.
# ----------------------------------------------------------------------
proc ::winkit::gui::host_geometry {} {
    if {[info exists ::geometry]} {
	return $::geometry
    }
    return ""
}

# ----------------------------------------------------------------------
#  run_applet -- create the safe child and evaluate the user's script in it
# ----------------------------------------------------------------------
proc ::winkit::gui::run_applet {script encoding geometry} {
    # uplevel #0 because `source` evaluates in the caller's scope, and
    # safe_master.tcl sets namespace-level state that has to land at global
    # level. Same idiom main.tcl uses for this file and for the TclReadLine
    # win32 shim. Sourced here rather than at the top of this file so that the
    # usage path never pays for safe.tcl.
    uplevel #0 [list source [file join $::winkit::libdir winkit safe_master.tcl]]

    # argv0/argc/argv/tcl_interactive are NOT set here -- see the file header.
    # init's step 7 copies them into the child as they stand, and Tk_MainEx
    # already published all four correctly for this mode.
    set child [::winkit::safe::init $script gui $geometry]

    # The CHILD's own `source` runs the applet, not a read here: only safe.tcl's
    # AliasSource applies the accessPath check, and only it honours -encoding.
    # A relative name resolves because the script's directory is on the
    # accessPath (decision 12) and FileInAccessPath normalizes it against the
    # master's cwd.
    if {$encoding ne ""} {
	interp eval $child [list source -encoding $encoding $script]
    } else {
	interp eval $child [list source $script]
    }

    # No exit and no error trapping, in both directions on purpose:
    #   * an applet that fails lets the error escape, and Tk_MainEx turns it
    #     into TkpDisplayWarning(errorInfo, "Error in startup script") plus
    #     Tcl_Exit(1) (tkMain.c:326-337) -- stock wish behaviour, and the only
    #     visible channel this exe has;
    #   * an applet that succeeds must let this file return, so Tk_MainEx
    #     reaches Tk_MainLoop() (tkMain.c:374). That loop is what keeps the
    #     window alive after the script's last command and what exits the
    #     process with 0 once the last window goes away.
    return
}

# --- dispatch -----------------------------------------------------------
#
# Global level: Tk_MainEx evaluates this file with Tcl_FSEvalFileEx
# (tkMain.c:326), so the reads below see argv0/argv/argc/tcl_interactive and
# ::geometry where Tk put them.

if {$::winkit::gui_script eq ""} {
    ::winkit::gui::show_usage
    ;# not reached: show_usage exits 1
}

::winkit::gui::run_applet $::winkit::gui_script $::winkit::gui_encoding \
	[::winkit::gui::host_geometry]
