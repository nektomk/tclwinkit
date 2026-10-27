# iwidgets-demo.tcl -- run an Iwidgets demo from the docs artifact.
#
# The kit's zipfs image deliberately has no demos in it, so the demo scripts
# ship in this archive (demos/iwidgets/) and were repointed at their own
# directory by scripts/build-docs-artifact.ps1. All this wrapper adds is a
# catalogue and a convenient way to start one demo by name:
#
#   winkitwish-msvc.exe iwidgets-demo.tcl <name>   -- one demo, e.g. combobox
#   winkitwish-msvc.exe iwidgets-demo.tcl --all    -- print the catalogue
#   winkitwish-msvc.exe iwidgets-demo.tcl          -- usage + catalogue
#
# <name> is a demo file name without extension, as found in demos/iwidgets/.

set here [file normalize [file dirname [info script]]]
set root [file dirname $here]
set demoDir [file join $root demos iwidgets]

proc die {msg} {
    puts "iwidgets-demo: $msg"
    exit 1
}

if {![file isdirectory $demoDir]} {
    die "demos not found at $demoDir (keep tools/ next to demos/)"
}

set avail {}
foreach f [lsort [glob -nocomplain -directory $demoDir -type f *]] {
    if {[file extension $f] eq {} || [file extension $f] eq {.tcl}} {
	lappend avail [file rootname [file tail $f]]
    }
}

proc catalogue {} {
    global avail demoDir
    puts "[llength $avail] demos in $demoDir:"
    puts "  [join $avail {, }]"
}

if {[llength $argv] == 0} {
    puts {usage: winkitwish-msvc.exe [file] iwidgets-demo.tcl <name>|--all}
    catalogue
    exit 0
}

set want [lindex $argv 0]
if {$want eq "--all"} {
    catalogue
    exit 0
}
if {$want ni $avail} {
    die "no demo '$want'; [llength $avail] available (see --all)"
}

if {[catch {package require Iwidgets} ver]} {
    die "package require Iwidgets failed: $ver"
}
puts "iwidgets-demo: Iwidgets $ver, demo '$want'"

set script [file join $demoDir $want]
if {![file exists $script]} { set script [file join $demoDir $want.tcl] }

set oldwd [pwd]
cd $demoDir
if {[catch {source $script} err]} {
    cd $oldwd
    puts "iwidgets-demo: error running '$want':"
    puts $err
    exit 1
}
cd $oldwd
