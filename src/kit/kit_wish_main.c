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
int Tcl_AppInit(Tcl_Interp *interp);	/* defined below */
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
    /*
     * Pin tcl_library to our own VFS copy of the Tcl script library
     * (//zipfs:/app/tcl_library, mounted by TclZipfs_AppHook before
     * Tk_Main). Per tclInterp.c's [tclInit] search order, an explicitly
     * set $tcl_library is authoritative: Tcl_Init will NOT consult
     * $env(TCL_LIBRARY) or any on-disk location, so a machine with an
     * installed Tcl (or a tampered TCL_LIBRARY) cannot inject its own
     * init.tcl / libraries into our runtime.
     *
     * Additionally, strip TCL_LIBRARY from the process's OS environment
     * block BEFORE any interpreter is asked to initialize.
     * Tk_CreateConsoleWindow creates a second interpreter (consoleInterp)
     * and slave interpreters (interp create) each seed their $env array
     * from the process environment block (tclEnv.c tenviron), not from a
     * sibling interpreter; a leftover TCL_LIBRARY would make their
     * [tclInit] pick the external (installed/tampered) init.tcl even though
     * THIS interp has a valid pinned $tcl_library. exec'd children inherit
     * the same block, so a stale value would leak into them too. After
     * Tcl_Init we re-declare $env(TCL_LIBRARY) for Tcl-level scripts:
     * writing through the env array propagates back into the process block
     * (EnvTraceProc), so it reads correctly and the block stays consistent
     * for exec'd children.
     */
    if (!SetEnvironmentVariableW(L"TCL_LIBRARY", NULL)) {
	return TCL_ERROR;
    }
    if (Tcl_SetVar(interp, "tcl_library", "//zipfs:/app/tcl_library",
	    TCL_GLOBAL_ONLY) == NULL) {
	return TCL_ERROR;
    }
    if ((Tcl_Init)(interp) == TCL_ERROR) {
	return TCL_ERROR;
    }
    if (Tcl_SetVar(interp, "env(TCL_LIBRARY)", "//zipfs:/app/tcl_library",
	    TCL_GLOBAL_ONLY) == NULL) {
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

    /* NOTE: no tcl_rcFileName is set here on purpose. A per-user rc file
     * would execute untrusted script from the home directory on every
     * interactive start, reintroducing an environment dependency that the
     * portable runtime explicitly avoids. */
    return TCL_OK;
}
