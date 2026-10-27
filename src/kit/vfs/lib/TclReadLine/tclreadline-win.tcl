# tclreadline-win.tcl --
#
#	Windows console shim for TclReadLine (tclwinkit project).
#	Source this AFTER `package require TclReadLine` on Windows.
#
#	TclReadLine is written for POSIX ttys: stty raw mode, ANSI key
#	sequences arriving on stdin, and a fileevent-driven input loop.
#	None of that works on a Win32 console (no stty, arrow keys come
#	as 0xE0-prefixed scan codes, fileevent does not fire on console
#	channels). This shim replaces the low-level parts using TWAPI
#	while keeping all of TclReadLine's line-editing, history and
#	completion logic untouched:
#
#	  rawInput / lineInput  -> SetConsoleMode (char-at-a-time, no echo)
#	  getColumns            -> GetConsoleScreenBufferInfo
#	  ANSI output           -> ENABLE_VIRTUAL_TERMINAL_PROCESSING
#	                           (Windows 10+ conhost / Windows Terminal)
#	  interact              -> synchronous loop over ReadConsoleInput
#	                           records, translated into the exact ANSI
#	                           sequences handleEscapes expects
#	  `read stdin`          -> returns "" while the REPL owns input;
#	                           all key data arrives via the console API
#	                           and is fed straight into keybuffer
#
#	Ctrl+C behaviour: at the prompt the console is in raw mode, so
#	Ctrl+C arrives as \x03 and just clears the current line (like
#	bash). While a command runs, the cooked mode is restored and
#	Ctrl+C terminates the process (like stock tclsh).

package require twapi

namespace eval ::TclReadLine {
    variable WIN_INH {}
    variable WIN_OUTH {}
    variable WIN_INMODE {}
    variable WIN_OUTMODE {}
    variable WIN_ACTIVE 0
}

# Open (once) and remember console input/output handles.
proc ::TclReadLine::win_init {} {
    variable WIN_INH
    variable WIN_OUTH
    if {$WIN_INH eq ""} {
	set WIN_INH [twapi::get_console_handle stdin]
	set WIN_OUTH [twapi::get_console_handle stdout]
    }
    return
}

# Replace: exec stty raw -echo isig
proc ::TclReadLine::rawInput {} {
    variable WIN_INH
    variable WIN_OUTH
    variable WIN_INMODE
    variable WIN_OUTMODE
    win_init
    if {$WIN_INMODE eq ""} {
	set WIN_INMODE [twapi::GetConsoleMode $WIN_INH]
	set WIN_OUTMODE [twapi::GetConsoleMode $WIN_OUTH]
	# ENABLE_VIRTUAL_TERMINAL_PROCESSING so ANSI escapes render.
	catch {twapi::SetConsoleMode $WIN_OUTH [expr {$WIN_OUTMODE | 0x4}]}
    }
    fconfigure stdout -buffering none
    # Mode 0: no line input, no echo, no Ctrl+C signal processing.
    twapi::SetConsoleMode $WIN_INH 0
    return
}

# Replace: exec stty -raw -echo isig
proc ::TclReadLine::lineInput {} {
    variable WIN_INH
    variable WIN_INMODE
    win_init
    fconfigure stdout -buffering line
    if {$WIN_INMODE ne ""} {
	twapi::SetConsoleMode $WIN_INH $WIN_INMODE
    }
    return
}

# Replace: exec stty sane (full restore of both modes).
proc ::TclReadLine::win_sane {} {
    variable WIN_OUTH
    variable WIN_OUTMODE
    lineInput
    if {$WIN_OUTMODE ne ""} {
	catch {twapi::SetConsoleMode $WIN_OUTH $WIN_OUTMODE}
    }
    return
}

# Replace: stty size / stty -a parsing.
proc ::TclReadLine::getColumns {} {
    variable COLUMNS
    set cols 0
    if {![catch {twapi::get_console_screen_buffer_info stdout -windowsize} info]} {
	# info == {-windowsize {cols rows}}
	set cols [lindex $info 1 0]
    }
    if {$cols < 1} {
	set cols 80
    }
    set COLUMNS $cols
    return
}

# Replace vendor restore: also undo the `read` rename.
proc ::TclReadLine::restore {} {
    variable WIN_ACTIVE
    set WIN_ACTIVE 0
    lineInput
    catch {
	if {[llength [info commands ::TclReadLine::_origRead]]} {
	    rename ::read {}
	    rename ::TclReadLine::_origRead ::read
	}
    }
    return
}

# While the REPL owns the console, every key arrives through
# ReadConsoleInput; tclline()'s `read stdin` calls must come back empty
# instead of touching the channel (which would block or fight the raw
# console mode).
proc ::TclReadLine::win_setup_read {} {
    if {[llength [info commands ::TclReadLine::_origRead]] == 0} {
	rename ::read ::TclReadLine::_origRead
	proc ::read {args} {
	    if {$::TclReadLine::WIN_ACTIVE && [llength $args]
		    && [lindex $args 0] eq "stdin"} {
		return ""
	    }
	    tailcall ::TclReadLine::_origRead {*}$args
	}
    }
    return
}

# Translate one Win32 KEY_EVENT_RECORD (dict as returned by
# twapi::_console_read_input_records) into the byte sequence
# TclReadLine's key dispatcher understands.
proc ::TclReadLine::win_convert_key {rec} {
    dict with rec {}
    if {$keystate ne "down"} {
	return ""
    }
    set ctr [expr {("leftctrl" in $controls) || ("rightctrl" in $controls)}]
    set shf [expr {"shift" in $controls}]
    # Virtual-key codes (decimal): 9 Tab, 33-34 PgUp/PgDn, 35 End,
    # 36 Home, 37-40 arrows, 45 Insert, 46 Delete.
    switch -- $keycode {
	33 { return "\033\[5~" }
	34 { return "\033\[6~" }
	35 { return "\033\[F" }
	36 { return "\033\[H" }
	37 { return [::TclReadLine::win_csi D $ctr $shf] }
	38 { return [::TclReadLine::win_csi A $ctr $shf] }
	39 { return [::TclReadLine::win_csi C $ctr $shf] }
	40 { return [::TclReadLine::win_csi B $ctr $shf] }
	46 { return "\033\[3~" }
	45 { return "" }
	9  { if {$shf} { return "\033\[Z" } }
    }
    # Plain characters (incl. \r, \t, \x08, \x1b, Ctrl+letter) pass
    # through; handleControls/handleEscapes take it from there.
    return $char
}

proc ::TclReadLine::win_csi {letter ctr shf} {
    if {$ctr} {
	return "\033\[1;5$letter"
    }
    if {$shf} {
	return "\033\[1;2$letter"
    }
    return "\033\[$letter"
}

# Block until at least one key arrives, then drain any further pending
# key records without blocking (paste bursts, fast typing).
proc ::TclReadLine::win_read_keys {} {
    variable WIN_INH
    set out ""
    foreach rec [twapi::_console_read_input_records $WIN_INH -count 1] {
	if {[lindex $rec 0] eq "key"} {
	    append out [win_convert_key [lindex $rec 1]]
	}
    }
    while {1} {
	set pend [twapi::_console_read_input_records $WIN_INH -count 256 -peek]
	set n [llength $pend]
	if {$n == 0} {
	    break
	}
	foreach rec [twapi::_console_read_input_records $WIN_INH -count $n] {
	    if {[lindex $rec 0] eq "key"} {
		append out [win_convert_key [lindex $rec 1]]
	    }
	}
    }
    return $out
}

# Replace vendor doExit: same history persistence, console restore
# instead of `stty sane`.
proc ::TclReadLine::doExit {{code 0}} {
    variable HISTFILE
    variable HISTORY_SIZE

    restore
    win_sane

    set hlist [getHistory]
    # Don't remember the exit command itself:
    set hlist [lsearch -all -not -inline $hlist "TclReadLine::doExit"]
    set hlistlen [llength $hlist]
    if {$hlistlen > 0} {
	if {$hlistlen > $HISTORY_SIZE} {
	    set hlist [lrange $hlist [expr {($hlistlen - $HISTORY_SIZE - 1)}] end]
	}
	# History is a convenience: never fail the exit path.
	if {![catch {open $HISTFILE w} f]} {
	    foreach x $hlist {
		puts $f [string map {
		    \n "\\n"
		    "\\" "\\b"
		} $x]
	    }
	    close $f
	}
    }

    exit $code
}

# Replace vendor interact: synchronous Win32 console loop instead of
# fileevent + vwait (which never fire on Windows console channels).
proc ::TclReadLine::interact {} {
    variable RCFILE
    variable HISTFILE
    variable HISTORY_SIZE
    variable WIN_ACTIVE
    variable ThisScript
    variable keybuffer

    if {[file exists $RCFILE]} {
	source $RCFILE
    }

    # Load history:
    history keep $HISTORY_SIZE
    if {[file exists $HISTFILE]} {
	if {![catch {open $HISTFILE r} f]} {
	    set hlist [list]
	    foreach x [split [read $f] "\n"] {
		if {$x ne ""} {
		    # Undo newline escapes:
		    lappend hlist [string map {
			"\\n" \n
			"\\\\" "\\"
			"\\b" "\\"
		    } $x]
		}
	    }
	    setHistory $hlist
	    unset hlist
	    close $f
	}
    }

    win_init
    rawInput
    win_setup_read
    set WIN_ACTIVE 1

    getColumns
    # 'exit' must go through doExit (history save + console restore):
    alias exit TclReadLine::doExit
    set ThisScript [info script]

    tclline ;# emit the first prompt

    while {$WIN_ACTIVE} {
	# Cheap resize tracking (no SIGWINCH on Windows):
	getColumns
	set seq [win_read_keys]
	if {$seq eq ""} {
	    continue
	}
	if {![info exists keybuffer]} {
	    set keybuffer ""
	}
	append keybuffer $seq
	tclline
    }

    restore
    return
}
