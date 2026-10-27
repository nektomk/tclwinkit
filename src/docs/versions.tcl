# versions.tcl -- print "<package>\t<version>" for everything the kit carries.
#
# Used by scripts/build-docs-artifact.ps1 to write VERSIONS.txt, so the docs
# archive records exactly which build it belongs to. Run with the console kit:
#
#   tclwinkit-msvc.exe versions.tcl
#
# Packages that fail to load are reported as "MISSING <error>" rather than
# aborting: the docs build must not depend on a green kit.

set pkgs {
    itcl Thread tdbc sqlite3 {tdbc::sqlite3} {tdbc::odbc} rl_json Mpexpr
    twapi twapi_base twapi_com twapi_evt twapi_file twapi_job twapi_mem
    twapi_net twapi_prc twapi_reg twapi_sec twapi_svc twapi_thread twapi_time
    twapi_token twapi_tray twapi_win
    Img Itk Iwidgets tkdnd treectrl {img::png} {img::jpeg} {img::tiff}
    {img::bmp} {img::gif} {img::ico} {img::pixmap} {img::raw} {img::sgi}
    {img::sun} {img::tga} {img::xbm} {img::xpm} {img::dted} {img::flir}
    {img::pcx} {img::ppm} {img::ps} {img::window}
    base64 markdown htmlparse json struct tree graphn objdef page
    doctools doctools_lang nroff mpeg4ip critcl tcom twapi_dde registry dde
    http sha1 md5 zlib report uri textutil lexer vim clock
}

# tklib modules ship as plain packages too
lappend pkgs tilebench tilescale canvas::zoomedpanel ctext autocomplete \
    colour::gimp colour::request form menu::simple optiondb pagetable \
    tooltip undo bc bgerror bubble chart cvtable dimlet editer entryform \
    fileselector fwatch ipwidget itk::blt itk::itktable lcda ntrees \
    obfdialog tclopts tkcon tkined tkscale tksnp toolbar truncwp widget

puts "Tcl\t[info patchlevel]"
foreach p $pkgs {
    if {[catch {package require $p} v]} {
	continue    ;# not every listed module exists in this build; skip quietly
    }
    puts "$p\t$v"
}
if {[info exists ::tk_version]} {
    puts "Tk\t$::tk_version"
} else {
    # console kit has no Tk; report from the GUI kit instead when available
    puts "Tk\t(console kit: not loaded)"
}
exit 0
