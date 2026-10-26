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

chk "package Registry"   {package require Registry}
chk "package Dde"        {package require Dde}
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
    set f [file join [file tempfile] kitdb.sqlite]
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
    set f [file join [file tempfile] kittdbc.sqlite]
    tdbc::sqlite3::connection create db $f
    db allrows {CREATE TABLE q(a)}
    db insert q {a 42}
    set r [db allrows {SELECT a FROM q}]
    db close
    file delete -force $f
    lindex $r 0 a
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
    "$v ([twapi::get_temp_path] ne {})"
}
chk "twapi COM (dyncall)" {
    package require twapi_com
    set wsh [twapi::comobj -create WScript.Shell]
    set name [$wsh ExpandEnvironmentStrings {%COMPUTERNAME%}]
    $wsh -destroy
    expr {$name ne "" && $name ne "%COMPUTERNAME%"}
}

# tcllib samples
chk "tcllib base64" {
    package require base64
    base64::encode {kit}
}
chk "tcllib struct::queue" {
    package require struct::queue
    struct::queue q
    q put a b
    set r [q get]
    q destroy
    set r
}
chk "tcllib textutil" {
    package require textutil
    textutil::unduplicate {a a b}
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
	set f [file join [file tempfile] kitimg.png]
	image create photo p1
	p1 put {{red green} {blue black}}
	p1 write $f -format png
	image create photo p2 -file $f
	set r "[p2 width]x[p2 height] [p2 get 0 0]"
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
}

puts ""
if {[llength $::failures]} {
    puts "SMOKE FAILED: [join $::failures {, }]"
    exit 1
}
puts "SMOKE OK"
exit 0
