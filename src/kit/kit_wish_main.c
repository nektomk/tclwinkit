/*
 * kit_wish_main.c --
 *
 *	GUI (wish-style) main for tclwinkit. Modeled on Tk 9's
 *	win/winMain.c; adds static package registration from
 *	kit_register.c. Linked as a Windows-subsystem executable.
 */

#undef USE_TCL_STUBS
#include "tk.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
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

static BOOL consoleRequired = TRUE;

/*
 *----------------------------------------------------------------------
 *
 * _tWinMain --
 *
 *	Main entry point from Windows (GUI subsystem).
 *
 *----------------------------------------------------------------------
 */

int APIENTRY
_tWinMain(
    HINSTANCE hInstance,
    HINSTANCE hPrevInstance,
    LPTSTR lpszCmdLine,
    int nCmdShow)
{
    TCHAR **argv;
    int argc;
    TCHAR *p;
    (void)hInstance;
    (void)hPrevInstance;
    (void)lpszCmdLine;
    (void)nCmdShow;

    consoleRequired = TRUE;
    setlocale(LC_ALL, "C");

    /* Get our args from the c-runtime. Ignore lpszCmdLine. */
    argc = __argc;
    argv = __targv;

    for (p = argv[0]; *p != '\0'; p++) {
	if (*p == '\\') {
	    *p = '/';
	}
    }

    TclZipfs_AppHook(&argc, &argv);
    Tk_Main(argc, argv, Tcl_AppInit);
    return 0;
}

/*
 *----------------------------------------------------------------------
 *
 * Tcl_AppInit --
 *
 *	Application-specific initialization for the GUI kit.
 *
 *----------------------------------------------------------------------
 */

int
Tcl_AppInit(
    Tcl_Interp *interp)		/* Interpreter for application. */
{
    if ((Tcl_Init)(interp) == TCL_ERROR) {
	return TCL_ERROR;
    }
    if (Tk_Init(interp) == TCL_ERROR) {
	return TCL_ERROR;
    }
    Tcl_StaticLibrary(interp, "Tk", Tk_Init, Tk_SafeInit);

    /* Console emulation widget when running interactively */
    if (consoleRequired) {
	if (Tk_CreateConsoleWindow(interp) == TCL_ERROR) {
	    return TCL_ERROR;
	}
    }

    if (Kit_RegisterPackages(interp) == TCL_ERROR) {
	return TCL_ERROR;
    }

    (void) Tcl_EvalEx(interp,
	    "set tcl_rcFileName [file tildeexpand ~/winkitwishrc.tcl]",
	    TCL_AUTO_LENGTH, TCL_EVAL_GLOBAL);
    return TCL_OK;
}
