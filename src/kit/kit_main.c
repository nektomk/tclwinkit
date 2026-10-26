/*
 * kit_main.c --
 *
 *	Console (tclsh-style) main for tclwinkit. Modeled on Tcl 9's
 *	win/tclAppInit.c; adds static package registration from
 *	kit_register.c. Build WITHOUT UNICODE issues: Tcl 9 requires
 *	UNICODE on Windows for TclZipfs_AppHook.
 */

#undef USE_TCL_STUBS
#include "tcl.h"

#define WIN32_LEAN_AND_MEAN
#define STRICT
#include <windows.h>
#undef STRICT
#undef WIN32_LEAN_AND_MEAN
#include <locale.h>
#include <stdlib.h>
#include <tchar.h>

#if defined(__GNUC__)
int _CRT_glob = 0;	/* Disable globbing of argv (MinGW) */
#endif

#ifdef __cplusplus
extern "C" {
#endif
extern int Kit_RegisterPackages(Tcl_Interp *interp);
#ifdef __cplusplus
}
#endif

/*
 *----------------------------------------------------------------------
 *
 * main --
 *
 *	Main entry (console subsystem).
 *
 *----------------------------------------------------------------------
 */

int
_tmain(
    int argc,			/* Number of command-line arguments. */
    TCHAR *argv[])		/* Values of command-line arguments. */
{
    TCHAR *p;

    setlocale(LC_ALL, "C");

    /* Forward slashes substituted for backslashes. */
    for (p = argv[0]; *p != '\0'; p++) {
	if (*p == '\\') {
	    *p = '/';
	}
    }

    TclZipfs_AppHook(&argc, &argv);
    Tcl_Main(argc, argv, Tcl_AppInit);
    return 0;
}

/*
 *----------------------------------------------------------------------
 *
 * Tcl_AppInit --
 *
 *	Application-specific initialization for the console kit.
 *
 *----------------------------------------------------------------------
 */

int
Tcl_AppInit(
    Tcl_Interp *interp)		/* Interpreter for application. */
{
    if (Tcl_Init(interp) == TCL_ERROR) {
	return TCL_ERROR;
    }
    if (Kit_RegisterPackages(interp) == TCL_ERROR) {
	return TCL_ERROR;
    }

    /* User startup file for interactive sessions */
    (void) Tcl_EvalEx(interp,
	    "set tcl_rcFileName [file tildeexpand ~/winkitrc.tcl]",
	    TCL_AUTO_LENGTH, TCL_EVAL_GLOBAL);
    return TCL_OK;
}
