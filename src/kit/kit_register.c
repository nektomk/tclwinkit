/*
 * kit_register.c --
 *
 *	Common package registration for tclwinkit (console & GUI variants).
 *	Statically linked binary extensions are registered via
 *	Tcl_StaticLibrary(); mixed (C+Tcl) packages use thin wrappers that
 *	source their Tcl part from the attached zipfs image (//zipfs:/app).
 *
 * Build defines:
 *   KIT_GUI            - build the Tk (wish-style) variant
 *   KIT_HAVE_ITCL      - link itcl4        (bundled, default on)
 *   KIT_HAVE_THREAD    - link thread       (bundled, default on)
 *   KIT_HAVE_TDBC      - link tdbc         (bundled, default on)
 *   KIT_HAVE_SQLITE3   - link sqlite3      (bundled, default on)
 *   KIT_HAVE_TDBCODBC  - link tdbc::odbc   (bundled, default on)
 *   KIT_HAVE_TWAPI     - link twapi        (external)
 *   KIT_HAVE_IMG       - link Img          (external)
 *   KIT_HAVE_TCLREADLINE - link tclreadline (external)
 *   KIT_HAVE_CAWT      - link cawt         (external)
 */

#undef USE_TCL_STUBS
#include "tcl.h"
#ifdef KIT_GUI
#include "tk.h"
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* Core Windows extensions (static build of Tcl provides these) */
extern Tcl_LibraryInitProc Registry_Init;
extern Tcl_LibraryInitProc Dde_Init;
extern Tcl_LibraryInitProc Dde_SafeInit;

#ifdef KIT_HAVE_ITCL
extern Tcl_LibraryInitProc Itcl_Init;
extern Tcl_LibraryInitProc Itcl_SafeInit;
#endif
#ifdef KIT_HAVE_THREAD
extern Tcl_LibraryInitProc Thread_Init;
#endif
#ifdef KIT_HAVE_TDBC
extern Tcl_LibraryInitProc Tdbc_Init;
#endif
#ifdef KIT_HAVE_SQLITE3
extern Tcl_LibraryInitProc Sqlite3_Init;
#endif
#ifdef KIT_HAVE_TDBCODBC
extern Tcl_LibraryInitProc Tdbcodbc_Init;
#endif
#ifdef KIT_HAVE_TWAPI
extern Tcl_LibraryInitProc Twapi_Init;
#endif
#ifdef KIT_HAVE_IMG
extern Tcl_LibraryInitProc Img_Init;
/* Individual image format handlers */
extern Tcl_LibraryInitProc Png_Init;
extern Tcl_LibraryInitProc Jpeg_Init;
extern Tcl_LibraryInitProc Gif_Init;
extern Tcl_LibraryInitProc Bmap_Init;
extern Tcl_LibraryInitProc Ppm_Init;
extern Tcl_LibraryInitProc Xpm_Init;
extern Tcl_LibraryInitProc Tiff_Init;
extern Tcl_LibraryInitProc Ps_Init;
extern Tcl_LibraryInitProc Window_Init;
#endif
#ifdef KIT_HAVE_TCLREADLINE
extern Tcl_LibraryInitProc Tclreadline_Init;
#endif
#ifdef KIT_HAVE_CAWT
extern Tcl_LibraryInitProc Cawt_Init;
#endif

#ifdef __cplusplus
}
#endif

/*
 * Wrappers for mixed C+Tcl packages: run C init, then source the Tcl part
 * from the zipfs image attached to this executable.
 */

#ifdef KIT_HAVE_TDBC
static int
TdbcKit_Init(Tcl_Interp *interp)
{
    if (Tdbc_Init(interp) == TCL_ERROR) {
	return TCL_ERROR;
    }
    return Tcl_EvalEx(interp,
	    "if {[file exists {//zipfs:/app/lib/tdbc/tdbc.tcl}]} {"
	    " source -encoding utf-8 {//zipfs:/app/lib/tdbc/tdbc.tcl}"
	    "}", TCL_AUTO_LENGTH, TCL_EVAL_GLOBAL);
}
#endif

#ifdef KIT_HAVE_TDBCODBC
static int
TdbcOdbcKit_Init(Tcl_Interp *interp)
{
    /* tdbc::odbc builds on the tdbc OO framework */
    if (Tcl_EvalEx(interp, "package require tdbc", TCL_AUTO_LENGTH,
	    TCL_EVAL_GLOBAL) == TCL_ERROR) {
	return TCL_ERROR;
    }
    return Tdbcodbc_Init(interp);
}
#endif

#ifdef KIT_HAVE_TCLREADLINE
static int
TclreadlineKit_Init(Tcl_Interp *interp)
{
    if (Tclreadline_Init(interp) == TCL_ERROR) {
	return TCL_ERROR;
    }
    return Tcl_EvalEx(interp,
	    "if {[file exists {//zipfs:/app/lib/tclreadline/tclreadline.tcl}]} {"
	    " source -encoding utf-8 {//zipfs:/app/lib/tclreadline/tclreadline.tcl}"
	    "}", TCL_AUTO_LENGTH, TCL_EVAL_GLOBAL);
}
#endif

#ifdef KIT_HAVE_TWAPI
static int
TwapiKit_Init(Tcl_Interp *interp)
{
    if (Twapi_Init(interp) == TCL_ERROR) {
	return TCL_ERROR;
    }
    return Tcl_EvalEx(interp,
	    "if {[file exists {//zipfs:/app/lib/twapi/twapi.tcl}]} {"
	    " source -encoding utf-8 {//zipfs:/app/lib/twapi/twapi.tcl}"
	    "}", TCL_AUTO_LENGTH, TCL_EVAL_GLOBAL);
}
#endif

#ifdef KIT_HAVE_CAWT
static int
CawtKit_Init(Tcl_Interp *interp)
{
    if (Cawt_Init(interp) == TCL_ERROR) {
	return TCL_ERROR;
    }
    return Tcl_EvalEx(interp,
	    "if {[file exists {//zipfs:/app/lib/cawt/cawt.tcl}]} {"
	    " source -encoding utf-8 {//zipfs:/app/lib/cawt/cawt.tcl}"
	    "}", TCL_AUTO_LENGTH, TCL_EVAL_GLOBAL);
}
#endif

/*
 *----------------------------------------------------------------------
 *
 * Kit_RegisterPackages --
 *
 *	Registers all statically linked packages and sources the kit
 *	Tcl-side bootstrap from zipfs. Called from the variant AppInit
 *	after Tcl_Init (and Tk_Init for the GUI variant).
 *
 *----------------------------------------------------------------------
 */

int
Kit_RegisterPackages(
    Tcl_Interp *interp)
{
    /* Core Windows pieces */
    Tcl_StaticLibrary(NULL, "Registry", Registry_Init, NULL);
    Tcl_StaticLibrary(NULL, "Dde", Dde_Init, Dde_SafeInit);

#ifdef KIT_HAVE_ITCL
    Tcl_StaticLibrary(NULL, "itcl", Itcl_Init, Itcl_SafeInit);
#endif
#ifdef KIT_HAVE_THREAD
    Tcl_StaticLibrary(NULL, "Thread", Thread_Init, NULL);
#endif
#ifdef KIT_HAVE_TDBC
    Tcl_StaticLibrary(NULL, "tdbc", TdbcKit_Init, NULL);
#endif
#ifdef KIT_HAVE_SQLITE3
    Tcl_StaticLibrary(NULL, "sqlite3", Sqlite3_Init, NULL);
#endif
#ifdef KIT_HAVE_TDBCODBC
    Tcl_StaticLibrary(NULL, "tdbc::odbc", TdbcOdbcKit_Init, NULL);
#endif
#ifdef KIT_HAVE_TWAPI
    Tcl_StaticLibrary(NULL, "twapi", TwapiKit_Init, NULL);
#endif
#ifdef KIT_HAVE_IMG
    Tcl_StaticLibrary(NULL, "Img", Img_Init, NULL);
    Tcl_StaticLibrary(NULL, "img::png", Png_Init, NULL);
    Tcl_StaticLibrary(NULL, "img::jpeg", Jpeg_Init, NULL);
    Tcl_StaticLibrary(NULL, "img::gif", Gif_Init, NULL);
    Tcl_StaticLibrary(NULL, "img::bmp", Bmap_Init, NULL);
    Tcl_StaticLibrary(NULL, "img::ppm", Ppm_Init, NULL);
    Tcl_StaticLibrary(NULL, "img::xpm", Xpm_Init, NULL);
    Tcl_StaticLibrary(NULL, "img::tiff", Tiff_Init, NULL);
    Tcl_StaticLibrary(NULL, "img::ps", Ps_Init, NULL);
    Tcl_StaticLibrary(NULL, "img::window", Window_Init, NULL);
#endif
#ifdef KIT_HAVE_TCLREADLINE
    Tcl_StaticLibrary(NULL, "tclreadline", TclreadlineKit_Init, NULL);
#endif
#ifdef KIT_HAVE_CAWT
    Tcl_StaticLibrary(NULL, "cawt", CawtKit_Init, NULL);
#endif

    /*
     * Tcl-side kit bootstrap living inside the attached zip image:
     * extends auto_path with tcllib/tklib directories, declares
     * pure-Tcl drivers (tdbc::sqlite3), package name aliases, etc.
     */
    if (Tcl_EvalEx(interp,
	    "if {[file exists {//zipfs:/app/lib/kit_init.tcl}]} {"
	    " source -encoding utf-8 {//zipfs:/app/lib/kit_init.tcl}"
	    "}", TCL_AUTO_LENGTH, TCL_EVAL_GLOBAL) == TCL_ERROR) {
	return TCL_ERROR;
    }
    return TCL_OK;
}
