# smoke.tcl — базовая проверка кита: tclwinkit <exe> smoke.tcl
proc chk {label script} {
    if {[catch {uplevel 1 $script} res]} {
	puts "FAIL  $label: $res"
	lappend ::failures $label
    } else {
	puts "ok    $label: $res"
    }
}
set ::failures {}

chk "tcl version"        {info patchlevel}
chk "zipfs app mounted"  {expr {[file isdirectory //zipfs:/app/tcl_library] ? {yes} : {no}} }
chk "exe path"           {file normalize [info nameofexecutable]}

chk "package registry"   {package require registry}
chk "package dde"        {package require dde}
chk "package itcl"       {package require itcl}
chk "package Thread"     {package require Thread}
chk "package tdbc"       {package require tdbc}
chk "package sqlite3"    {package require sqlite3}
chk "package tdbc::sqlite3" {package require tdbc::sqlite3}
chk "package tdbc::odbc" {package require tdbc::odbc}
chk "package http"       {package require http}
chk "package zlib cmd"   {expr {[llength [info commands zlib]] > 0}}

# sqlite round-trip
chk "sqlite3 db" {
    set f [file join [file normalize $::env(TEMP)] kitdb-[pid].sqlite]
    file delete -force $f
    sqlite3 db $f
    db eval {CREATE TABLE t(x INTEGER PRIMARY KEY, y TEXT)}
    db eval {INSERT INTO t(y) VALUES('привет'), ('kit')}
    set rows [db eval {SELECT y FROM t ORDER BY x}]
    db close
    file delete -force $f
    expr {$rows eq {привет kit} ? $rows : "mismatch: $rows"}
}

# tdbc round-trip
chk "tdbc sqlite3" {
    package require tdbc::sqlite3
    set f [file join [file normalize $::env(TEMP)] kittdbc-[pid].sqlite]
    file delete -force $f
    tdbc::sqlite3::connection create db $f
    db allrows {CREATE TABLE q(a)}
    db allrows {INSERT INTO q(a) VALUES(42)}
    set r [db allrows {SELECT a FROM q}]
    db close
    file delete -force $f
    dict get [lindex $r 0] a
}

# thread round-trip
chk "thread create/join" {
    set t [thread::create {thread::wait}]
    thread::release -wait $t
    expr {$t > 0}
}

# itcl smoke (also proves itcl.tcl was found in the zipfs image)
chk "itcl class" {
    itcl::class Foo { method bar {} { return baz } }
    Foo f
    set r [f bar]
    itcl::delete object f
    itcl::delete class Foo
    set r
}

# registry real call
chk "registry keys" {
    expr {[llength [registry keys HKEY_CURRENT_USER]] > 0}
}

# twapi: package + real call + COM via dyncall FFI
chk "twapi" {
    package require twapi
    set v [twapi::get_os_version]
    expr {$v ne "" ? $v : "empty"}
}
chk "twapi COM (dyncall)" {
    package require twapi_com
    set wsh [twapi::comobj WScript.Shell]
    set name [$wsh ExpandEnvironmentStrings {%COMPUTERNAME%}]
    $wsh -destroy
    expr {$name ne "" && $name ne "%COMPUTERNAME%"}
}

# tcllib samples
chk "tcllib base64" {
    package require base64
    base64::encode {kit}
}

# rl_json: get/set round-trip (ensemble-style rl_json::json)
chk "rl_json" {
    package require rl_json
    set j {{"name":"kit","n":[1,2,3],"ok":true}}
    set name [rl_json::json get $j name]
    set sum 0
    foreach v [rl_json::json get $j n] { incr sum $v }
    set j2 [rl_json::json set $j added 42]
    expr {$name eq {kit} && $sum == 6 && [rl_json::json get $j2 added] == 42 \
	    ? "$name/$sum/[rl_json::json type $j2]" : "mismatch: $name $sum"}
}

# mpexpr: arbitrary precision beyond 64 bit + mpformat
# (mpexpr 1.2 is pre-8.5: no ** operator, use pow(); results are MP floats)
chk "mpexpr bigint" {
    package require Mpexpr
    set r [mpexpr {pow(2,100)}]
    expr {$r eq {1267650600228229401496703205376.0} ? {ok} : "got $r"}
}
chk "mpformat" {
    set r [mpformat {%d} [mpexpr {pow(2,62) + 1}]]
    expr {$r eq {4611686018427387905} ? $r : "got $r"}
}

# twapi system tray: add/modify/remove notification-area icon
# (system icons come back typed HICON_SHARED — cast to HICON for addicon
#  and do NOT free_icon a shared handle)
chk "twapi system tray" {
    set hshared [twapi::load_icon_from_system INFORMATION]
    set hico [twapi::cast_handle $hshared HICON]
    set id [twapi::systemtray::addicon $hico]
    twapi::systemtray::modifyicon $id -tip {tclwinkit smoke}
    twapi::systemtray::removeicon $id
    expr {[string is integer -strict $id] ? "id=$id" : "bad id $id"}
}
chk "tcllib struct::queue" {
    package require struct::queue
    struct::queue q
    q put a b
    set r [q get]
    q destroy
    set r
}
chk "tcllib fileutil" {
    package require fileutil
    fileutil::fullnormalize [info nameofexecutable]
}

# TclReadLine (pure-Tcl REPL helper)
chk "TclReadLine" {package require TclReadLine}

# CAWT core (pure Tcl over twapi COM; no Office is touched)
chk "cawtcore" {
    package require cawtcore
    package provide cawtcore
}

# GUI-only checks
if {[package provide Tk] ne ""} {
    chk "package Img" {package require Img}
    chk "Img png round-trip" {
	set f [file join [file normalize $::env(TEMP)] kitimg-[pid].png]
	file delete -force $f
	image create photo p1
	p1 put {{red green} {blue black}}
	p1 write $f -format png
	image create photo p2 -file $f
	set r "[image width p2]x[image height p2] [p2 get 0 0]"
	image delete p1 p2
	file delete -force $f
	set r
    }
    chk "tklib canvas::zoom" {package require canvas::zoom}
    chk "tk widgets" {
	destroy .smoke
	toplevel .smoke
	label .smoke.l -text tclwinkit
	pack .smoke.l
	update
	set r [.smoke.l cget -text]
	destroy .smoke
	set r
    }

    # Itk: dual spelling provided by C init + itk.tcl found in zipfs
    chk "Itk" {
	package require Itk
	set v1 [package provide Itk]
	set v2 [package provide itk]
	expr {$v1 ne "" && $v2 ne "" && [llength [info commands itk::usual]] > 0 \
		? "$v1/$v2" : "missing: '$v1' '$v2'"}
    }

    # Iwidgets: real megawidget on top of Itcl/Itk (autoload from generic/tclIndex)
    chk "Iwidgets entryfield" {
	package require Iwidgets
	destroy .smokeiw
	toplevel .smokeiw
	iwidgets::entryfield .smokeiw.ef -labeltext Name
	pack .smokeiw.ef
	update
	.smokeiw.ef insert end kit
	set r [.smokeiw.ef get]
	destroy .smokeiw
	set r
    }

    # tkdnd: static C part + win32 OleDND Tcl scripts
    chk "tkdnd drop_target" {
	package require tkdnd
	destroy .smokednd
	toplevel .smokednd
	label .smokednd.l -text drop
	pack .smokednd.l
	update
	tkdnd::drop_target register .smokednd.l DND_Text
	tkdnd::drag_source register .smokednd.l DND_Text
	set tmp [tkdnd::GetDropFileTempDirectory]
	tkdnd::drop_target unregister .smokednd.l
	destroy .smokednd
	expr {$tmp ne "" ? "[package provide tkdnd] tmp=$tmp" : "no temp dir"}
    }

    # Treectrl: widget creation + treectrl.tcl bindings loaded via ::treectrl_library
    chk "treectrl widget" {
	package require treectrl
	destroy .smoketc
	toplevel .smoketc
	treectrl .smoketc.tc
	pack .smoketc.tc
	.smoketc.tc column create -text Col -width 80
	set i [.smoketc.tc item create]
	update
	set r "[package provide treectrl] item=$i cmds=[llength [info commands TreeCtrl::*]]"
	destroy .smoketc
	set r
    }
}

puts ""
if {[llength $::failures]} {
    puts "SMOKE FAILED: [join $::failures {, }]"
    exit 1
}
puts "SMOKE OK"
exit 0
