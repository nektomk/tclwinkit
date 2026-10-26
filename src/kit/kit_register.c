/*
 * kit_register.c --
 *
 *	Common package registration for tclwinkit (console & GUI variants).
 *	Statically linked binary extensions are registered via
 *	Tcl_StaticLibrary(); mixed (C+Tcl) packages use thin wrappers that
 *	source their Tcl part from the attached zipfs image (//zipfs:/app).
 *
 *	Prefixes registered here must match EXACTLY (case-sensitive) the
 *	`load {} <Prefix>` calls in the staged pkgIndex/kit_init.tcl scripts.
 *
 * Build defines:
 *   KIT_GUI            - build the Tk (wish-style) variant
 *   KIT_HAVE_ITCL      - link itcl4        (bundled)
 *   KIT_HAVE_THREAD    - link thread       (bundled)
 *   KIT_HAVE_TDBC      - link tdbc         (bundled)
 *   KIT_HAVE_SQLITE3   - link sqlite3      (bundled)
 *   KIT_HAVE_TDBCODBC  - link tdbc::odbc   (bundled)
 *   KIT_HAVE_TWAPI     - link twapi 5.2    (external; Tcl side via vendor
 *                        pkgIndex staged in zipfs: lib/twapi/)
 *   KIT_HAVE_IMG       - link Img 2.1.2    (external; GUI variant only:
 *                        img::base + zlibtcl/pngtcl/jpegtcl/tifftcl +
 *                        19 format handlers)
 *
 * Pure-Tcl packages (tcllib, tklib, cawt 3.1.1, TclReadLine, tdbc::sqlite3,
 * ttrace) need no registration here - they live in the zipfs image and are
 * wired up by lib/kit_init.tcl.
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
/* img::base + stub-table support packages */
extern Tcl_LibraryInitProc Tkimg_Init;
extern Tcl_LibraryInitProc Zlibtcl_Init;
extern Tcl_LibraryInitProc Pngtcl_Init;
extern Tcl_LibraryInitProc Jpegtcl_Init;
extern Tcl_LibraryInitProc Tifftcl_Init;
/* format handlers (init.c template: Tkimg<type>_Init) */
extern Tcl_LibraryInitProc Tkimgbmp_Init;
extern Tcl_LibraryInitProc Tkimgdted_Init;
extern Tcl_LibraryInitProc Tkimgflir_Init;
extern Tcl_LibraryInitProc Tkimggif_Init;
extern Tcl_LibraryInitProc Tkimgico_Init;
extern Tcl_LibraryInitProc Tkimgjpeg_Init;
extern Tcl_LibraryInitProc Tkimgpcx_Init;
extern Tcl_LibraryInitProc Tkimgpixmap_Init;
extern Tcl_LibraryInitProc Tkimgpng_Init;
extern Tcl_LibraryInitProc Tkimgppm_Init;
extern Tcl_LibraryInitProc Tkimgps_Init;
extern Tcl_LibraryInitProc Tkimgraw_Init;
extern Tcl_LibraryInitProc Tkimgsgi_Init;
extern Tcl_LibraryInitProc Tkimgsun_Init;
extern Tcl_LibraryInitProc Tkimgtga_Init;
extern Tcl_LibraryInitProc Tkimgtiff_Init;
extern Tcl_LibraryInitProc Tkimgwindow_Init;
extern Tcl_LibraryInitProc Tkimgxbm_Init;
extern Tcl_LibraryInitProc Tkimgxpm_Init;
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
    /*
     * Bare C init; the vendor pkgIndex.tcl (staged in lib/twapi/) provides
     * twapi_base/twapi_<mod>/twapi and falls back to `load {} Twapi`
     * exactly for this static case, sourcing twapi.tcl itself.
     */
    Tcl_StaticLibrary(NULL, "Twapi", Twapi_Init, NULL);
#endif
#ifdef KIT_HAVE_IMG
    Tcl_StaticLibrary(NULL, "Tkimg", Tkimg_Init, NULL);
    Tcl_StaticLibrary(NULL, "Zlibtcl", Zlibtcl_Init, NULL);
    Tcl_StaticLibrary(NULL, "Pngtcl", Pngtcl_Init, NULL);
    Tcl_StaticLibrary(NULL, "Jpegtcl", Jpegtcl_Init, NULL);
    Tcl_StaticLibrary(NULL, "Tifftcl", Tifftcl_Init, NULL);
    Tcl_StaticLibrary(NULL, "Tkimgbmp", Tkimgbmp_Init, NULL);
    Tcl_StaticLibrary(NULL, "Tkimgdted", Tkimgdted_Init, NULL);
    Tcl_StaticLibrary(NULL, "Tkimgflir", Tkimgflir_Init, NULL);
    Tcl_StaticLibrary(NULL, "Tkimggif", Tkimggif_Init, NULL);
    Tcl_StaticLibrary(NULL, "Tkimgico", Tkimgico_Init, NULL);
    Tcl_StaticLibrary(NULL, "Tkimgjpeg", Tkimgjpeg_Init, NULL);
    Tcl_StaticLibrary(NULL, "Tkimgpcx", Tkimgpcx_Init, NULL);
    Tcl_StaticLibrary(NULL, "Tkimgpixmap", Tkimgpixmap_Init, NULL);
    Tcl_StaticLibrary(NULL, "Tkimgpng", Tkimgpng_Init, NULL);
    Tcl_StaticLibrary(NULL, "Tkimgppm", Tkimgppm_Init, NULL);
    Tcl_StaticLibrary(NULL, "Tkimgps", Tkimgps_Init, NULL);
    Tcl_StaticLibrary(NULL, "Tkimgraw", Tkimgraw_Init, NULL);
    Tcl_StaticLibrary(NULL, "Tkimgsgi", Tkimgsgi_Init, NULL);
    Tcl_StaticLibrary(NULL, "Tkimgsun", Tkimgsun_Init, NULL);
    Tcl_StaticLibrary(NULL, "Tkimgtga", Tkimgtga_Init, NULL);
    Tcl_StaticLibrary(NULL, "Tkimgtiff", Tkimgtiff_Init, NULL);
    Tcl_StaticLibrary(NULL, "Tkimgwindow", Tkimgwindow_Init, NULL);
    Tcl_StaticLibrary(NULL, "Tkimgxbm", Tkimgxbm_Init, NULL);
    Tcl_StaticLibrary(NULL, "Tkimgxpm", Tkimgxpm_Init, NULL);
#endif

    /*
     * Tcl-side kit bootstrap living inside the attached zip image:
     * extends auto_path with package directories, declares pure-Tcl
     * drivers (tdbc::sqlite3), static `load {}` package indices, aliases.
     */
    if (Tcl_EvalEx(interp,
	    "if {[file exists {//zipfs:/app/lib/kit_init.tcl}]} {"
	    " source -encoding utf-8 {//zipfs:/app/lib/kit_init.tcl}"
	    "}", TCL_AUTO_LENGTH, TCL_EVAL_GLOBAL) == TCL_ERROR) {
	return TCL_ERROR;
    }
    return TCL_OK;
}
