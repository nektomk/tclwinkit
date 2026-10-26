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

# itcl smoke
chk "itcl class" {
    itcl::class Foo { method bar {} { return baz } }
    Foo f
    set r [f bar]
    itcl::delete object f
    itcl::delete class Foo
    set r
}

if {$::tcl_platform(platform) eq "windows"} {
    chk "twapi (if present)" {
	if {[catch {package require twapi} v]} { set v "not included ($v)" }
	set v
    }
}

puts ""
if {[llength $::failures]} {
    puts "SMOKE FAILED: [join $::failures {, }]"
    exit 1
}
puts "SMOKE OK"
exit 0
