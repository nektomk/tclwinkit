# man.tcl -- render a nroff/troff man page as plain text, using the kit only.
#
# The docs archive ships upstream *.n / *.3 / *.1 / *.man pages, which are
# troff source. groff is not always present on Windows, so this script gives a
# readable plain-text rendering straight from the kit:
#
#   tclwinkit-msvc.exe man.tcl <page>            [-width N]   -> stdout
#   tclwinkit-msvc.exe man.tcl <page> -o out.txt [-width N]
#
# Handles the request subset Tcl/Tk/itcl/tcllib pages actually use: section
# headings (.SH/.SS), paragraphs (.PP/.IP/.TP/.HP), indentation (.RS/.RE/.in),
# fills (.nf/.fi), breaks (.br/.sp), macro definitions (.de/.. -- skipped),
# file inclusions (.so -- followed), font escapes, backspace overstriking and
# the \(xx special-character escapes. Tables (.TS) pass through verbatim.
#
# Not a troff engine; it is a reader, best-effort by design.

proc usage {} {
    puts "usage: tclwinkit-msvc.exe \[ticket\] man.tcl <page> ?-width N? ?-o file?"
    exit 2
}

set page {}
set width 78
set outfile {}
set argv0 $argv
while {[llength $argv0] > 0} {
    set a [lindex $argv0 0]; set argv0 [lrange $argv0 1 end]
    switch -- $a {
	-width  { set width  [lindex $argv0 0]; set argv0 [lrange $argv0 1 end] }
	-o      { set outfile [lindex $argv0 0]; set argv0 [lrange $argv0 1 end] }
	--      { set page [lindex $argv0 0]; set argv0 {} }
	default { if {$page eq {}} { set page $a } }
    }
}
if {$page eq {}} usage
if {![file exists $page]} {
    puts stderr "man.tcl: no such page: $page"
    exit 1
}

# ---------------------------------------------------------------- specials ---
array set ::SP {
    em {--}   hy {-}    \- {-}    bu {*}    sq {\[aq]}
    lq {``}   rq {''}   aq {'}    ld {...}  rp {)}
    ri {|}    la {<=>}  le {<=}   ge {>=}   ne {!=}
    mu {x}    Mi {u}    Mo {o}    * {}      dollar {\$}
    sc {(c)}  reg {(R)} tm {(TM)} 1/4 {1/4} 1/2 {1/2} 3/4 {3/4}
}

proc dequote {s} {
    # Order matters: font escapes first, then \(xx, then \<char>, then
    # backspace overstriking (which must see the surviving text).
    regsub -all -- {\\f\([^)]*\)} $s {} s
    regsub -all -- {\\f.} $s {} s
    regsub -all -- {\\\((..)} $s {~\1~} s
    set out {}
    foreach part [split $s ~] {
	if {[info exists ::SP($part)]} {
	    append out $::SP($part)
	} else {
	    append out $part
	}
    }
    set s $out
    # \<char> -> char  (covers \$ \\ \  \n \c ...)
    regsub -all -- {\\(.)} $s {\1} s
    # backspace overstrike: A\bB -> B (bold), keep meaning for o\b/ -> /
    while {[regexp {(.)\x08(.)} $s -> a b]} {
	set rep $b
	if {$a ne $b} {
	    # overstruck glyph: caret-ish rendering that stays readable
	    set rep "$a/$b"
	    if {$b eq {|} || $b eq "/"} { set rep $a }
	}
	regsub -- {(.)\x08(.)} $s $rep s
    }
    regsub -all -- {\x08} $s {} s
    return [string trimright $s]
}

# Read a page. .so inclusions are NOT expanded: in Tcl/Tk pages they pull in
# man.macros, which is nothing but macro definitions and comments -- pure
# noise for a plain-text reader.
proc read_page {path} {
    set f [open $path r]
    fconfigure $f -encoding iso8859-1
    set txt [read $f]
    close $f
    set out {}
    foreach line [split $txt "\n"] {
	set l [string trimright $line]
	if {[string match {.so *} $l]} { continue }
	lappend out $l
    }
    return $out
}

set lines [read_page $page]
set pageDir [file dirname $page]

# ------------------------------------------------------------------ render ---
set indent 0
set fill 1
set skipDef 0            ;# >0 while swallowing a .de/.am/.rm body
set out {}
set para {}

proc push {txt} {
    global out indent
    lappend out [string repeat " " $indent]$txt
}
proc flushp {} {
    global para out indent width
    if {$para eq {}} return
    set txt [string trim [join $para " "]]
    set para {}
    if {$txt eq {}} return
    set pad [string repeat " " $indent]
    set cur $pad
    foreach w [split $txt " "] {
	if {[string length [string trimright $cur]] > $indent \
		&& [string length [string trimright $cur]] + [string length $w] + 1 > $width} {
	    lappend out [string trimright $cur]
	    set cur $pad
	}
	append cur $w " "
    }
    lappend out [string trimright $cur]
}
proc blankp {} {
    global out
    flushp
    lappend out {}
}

foreach raw $lines {
    set line [string trimright $raw]

    # troff comments: .\"  '\"  \"  (leading . or ' are no-op leaders)
    set probe [string trimleft $line {.'}]
    if {[string match {\\"*} $probe]} { continue }

    if {$skipDef} {
	if {$line eq ".." || $line eq ".!" || [string match {.* ..} $line]} {
	    set skipDef 0
	}
	continue
    }

    if {[string index $line 0] eq {.}} {
	set req [string range $line 0 2]
	set body [string trim [string range $line 3 end]]
	switch -- $req {
	    .de - .am - .df - .rm - .aln - .if - .ie - .ig {
		# macro definitions and conditionals: swallow to the terminator
		if {$req eq ".de" || $req eq ".am" || $req eq ".df" || $req eq ".rm"} {
		    set skipDef 1
		}
		continue
	    }
	    .TH - .ti - .ft - .ta - .tl - .tr - .mc - .hy - .nx - .ps - .vs - .ll - .ce - .ul - .cflags - .G1 - .G2 - .X1 - .X2 - .lg - .width - .let - .RCS {
		continue
	    }
	    .SH - .SS {
		blankp
		set t [string toupper [dequote $body]]
		lappend out $t
		lappend out [string repeat = [string length $t]]
		continue
	    }
	    .PP - .P - .LP - .sp - .Sp { blankp; continue }
	    .br { flushp; continue }
	    .nf { flushp; set fill 0; continue }
	    .fi { set fill 1; continue }
	    .RS { flushp; set indent [expr {$indent + 3}]; continue }
	    .RE { set indent [expr {max(0, $indent - 3)}]; flushp; continue }
	    .in - .ind {
		if {[regexp -- {-?[0-9]+} $body n]} { set indent [expr {abs(int($n))}] }
		flushp
		continue
	    }
	    .IP {
		flushp
		set tag [dequote [lindex $body 0]]
		if {[string match {*[0-9][0-9]*} $tag] || $tag in {-o {}}} { set tag {} }
		if {$tag ne {}} { push $tag }
		set rest [string range $body [expr {[string length [lindex $body 0]]}] end]
		set rest [string trim $rest]
		if {$rest ne {}} { lappend para [dequote $rest] }
		continue
	    }
	    .TP {
		flushp
		push [dequote [lindex $body 0]]
		set indent [expr {$indent + 3}]
		set rest [string trim [string range $body [expr {[string length [lindex $body 0]]}] end]]
		if {$rest ne {}} { lappend para [dequote $rest] }
		continue
	    }
	    .HP { flushp; set indent [expr {$indent + 3}]; continue }
	    .TS - .TE - .T& { flushp; push [dequote $body]; continue }
	    default {
		# unknown request: ignore the request, keep any trailing text
		if {$body ne {} && ![string match {[-a-zA-Z]*} $body]} {
		    lappend para [dequote $body]
		}
		continue
	    }
	}
    }

    if {$line eq {}} { blankp; continue }
    if {[string index $line 0] eq {\\}} { continue }
    set txt [dequote $line]
    if {!$fill} {
	flushp
	push $txt
    } else {
	lappend para $txt
    }
}
flushp

# collapse repeated blank lines
set res {}
set prevBlank 0
foreach l $out {
    if {[string trim $l] eq {} && $prevBlank} continue
    set prevBlank [expr {[string trim $l] eq {}}]
    lappend res $l
}
set text [join $res "\n"]
if {$outfile ne {}} {
    set f [open $outfile w]
    fconfigure $f -encoding utf-8
    puts $f $text
    close $f
    puts "man.tcl: wrote $outfile ([llength $res] lines)"
} else {
    fconfigure stdout -encoding utf-8
    puts $text
}
exit 0
