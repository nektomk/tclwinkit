# kit-license-check.tcl -- mandatory licence texts must survive staging.
#
# Regression guard for the defect found by the licence audit (R5): the kit
# staging prunes vendor trees for size (scripts/kit-prune.ps1), and it used to
# cut files by extension without distinguishing documentation from licence
# text. Several packages then shipped their code inside kit.vfs with the notice
# their own licence requires removed ("this notice is included verbatim in any
# distributions" -- the four Csaba Nemethi packages, tcllib snit/amazon-s3/
# textutil), and iwidgets 4.1.1 shipped 58 .itk/.itcl files with no licence file
# at all.
#
#   kit exe tests/kit-license-check.tcl                    # inside a built kit
#   tclsh   tests/kit-license-check.tcl //zipfs:/app        # explicit image root
#   tclsh   tests/kit-license-check.tcl <staged kit.vfs>    # a directory tree
#
# The second form lets the staging output be audited before it is zipped, and
# lets a plain directory stand in for the image in negative tests.
#
# Exit code 0 and the last line "KIT LICENSE CHECK OK" mean every required text
# is present AND readable from the zipfs image AND still contains the phrase
# the licence itself asks for. Run this against all four executables: the
# console kits carry no Tk layer, so tklib/iwidgets/tk_library paths are skipped
# there -- but only when the whole layer is absent, never per file, so a prune
# bug cannot hide behind that rule.
#
# The list below mirrors the tables in THIRD-PARTY-NOTICES.md sections 2.2, 2.3
# and 2.6; if a new module with its own licence text is added to the bundle,
# both places need the entry.
set want {
    lib/tcllib2.0/amazon-s3/LICENSE.txt
    lib/tcllib2.0/snit/license.txt
    lib/tcllib2.0/textutil/expander_license.txt
    lib/tcllib2.0/comm/comm.LICENSE
    lib/tcllib2.0/generator/license.terms
    lib/tcllib2.0/hook/license.terms
    lib/tcllib2.0/mkdoc/LICENSE
    lib/tklib0.9/mentry/COPYRIGHT.txt
    lib/tklib0.9/scrollutil/COPYRIGHT.txt
    lib/tklib0.9/tablelist/COPYRIGHT.txt
    lib/tklib0.9/wcb/COPYRIGHT.txt
    lib/tklib0.9/ctext/LICENSE
    lib/tklib0.9/shtmlview/LICENSE
    lib/tklib0.9/widgetl/icons/readme.txt
    lib/iwidgets4.1.1/license.terms
    tcl_library/license.terms
    tk_library/license.terms
}

# Phrases the licences themselves require to travel with the code. A text that
# is present but truncated or replaced by a placeholder must fail here too.
set probes {
    lib/tklib0.9/mentry/COPYRIGHT.txt           verbatim
    lib/tklib0.9/scrollutil/COPYRIGHT.txt       verbatim
    lib/tklib0.9/tablelist/COPYRIGHT.txt        verbatim
    lib/tklib0.9/wcb/COPYRIGHT.txt              verbatim
    lib/iwidgets4.1.1/license.terms             {DSC Technologies}
    lib/tcllib2.0/amazon-s3/LICENSE.txt         {Darren New}
    lib/tcllib2.0/snit/license.txt              {William H. Duquette}
    lib/tcllib2.0/textutil/expander_license.txt {William H. Duquette}
    lib/tcllib2.0/comm/comm.LICENSE             {Open Group Research Institute}
    lib/tcllib2.0/mkdoc/LICENSE                 {BSD}
    tcl_library/license.terms                   {Regents of the University}
}

set app //zipfs:/app
if {[llength $argv] > 0} { set app [lindex $argv 0] }
set tkLayer [expr {[file exists $app/tk_library] ? {yes} : {no}}]

proc img-read {p} {
    set ch [open $p]
    fconfigure $ch -encoding utf-8
    set d [read $ch]
    close $ch
    return $d
}

# A path is skipped only when its entire package layer is missing from the
# image (console kits are assembled without Tk, New-VfsTree -WithTk).
proc layer-missing {f} {
    upvar #0 app app
    foreach cand {lib/tklib0.9 lib/iwidgets4.1.1 tk_library} {
        if {[string match $cand/* $f] && ![file exists $app/$cand]} { return 1 }
    }
    return 0
}

set bad 0
set checked 0
set skipped 0
foreach f $want {
    if {[layer-missing $f]} {
        incr skipped
        continue
    }
    incr checked
    set p $app/$f
    if {![file exists $p]} {
        puts "  MISSING IN IMAGE: $f"
        incr bad
        continue
    }
    set data [img-read $p]
    # every text in the bundle is longer than this; a shorter one means the file
    # was truncated or replaced at staging time
    if {[string length $data] < 100} {
        puts "  TOO SHORT: $f ([string length $data] B)"
        incr bad
    }
}

set probed 0
foreach {f needle} $probes {
    if {[layer-missing $f]} { continue }
    set p $app/$f
    if {![file exists $p]} { continue }
    incr probed
    if {[string first $needle [img-read $p]] < 0} {
        puts "  REQUIRED PHRASE ABSENT ($needle): $f"
        incr bad
    }
}

puts "kit-license-check: Tk layer $tkLayer, $checked paths + $probed phrase probes checked, $skipped skipped (layer absent), $bad failures"
if {$bad == 0} {
    puts {KIT LICENSE CHECK OK}
    exit 0
}
exit 1
