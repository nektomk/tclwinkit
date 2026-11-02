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
int Tcl_AppInit(Tcl_Interp *interp);	/* defined below */
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
    /*
     * Pin tcl_library to our own VFS copy of the Tcl script library
     * (//zipfs:/app/tcl_library, mounted by TclZipfs_AppHook before
     * Tcl_Main). Per tclInterp.c's [tclInit] search order, an explicitly
     * set $tcl_library is authoritative: Tcl_Init will NOT consult
     * $env(TCL_LIBRARY) or any on-disk location, so a machine with an
     * installed Tcl (or a tampered TCL_LIBRARY) cannot inject its own
     * init.tcl / libraries into our runtime.
     *
     * Additionally, remove TCL_LIBRARY from the process's OS environment
     * block BEFORE any interpreter (console, slave, or exec'd child) gets
     * its own env array. New interpreters seed their $env from the process
     * environment (tclEnv.c EnvTraceProc/tenviron), not from a sibling
     * interpreter, so a leftover TCL_LIBRARY in the process block would
     * make the console-interp and slave-interp [tclInit] pick the external
     * (installed/tampered) init.tcl even though THIS interp has a valid
     * pinned $tcl_library. exec'd children inherit the same block, so a
     * stale TCL_LIBRARY would leak into them too. SetEnvironmentVariable
     * (W, UNICODE) with a NULL value deletes the variable from the block.
     */
    if (!SetEnvironmentVariableW(L"TCL_LIBRARY", NULL)) {
	return TCL_ERROR;
    }
    if (Tcl_SetVar(interp, "tcl_library", "//zipfs:/app/tcl_library",
	    TCL_GLOBAL_ONLY) == NULL) {
	return TCL_ERROR;
    }
    if (Tcl_Init(interp) == TCL_ERROR) {
	return TCL_ERROR;
    }
    /*
     * After Tcl_Init, (re)declare $env(TCL_LIBRARY) for Tcl-level scripts
     * that query it. Tcl_SetVar on the env array writes back into the
     * process environment (tclEnv.c EnvTraceProc), so this both reads
     * correctly and keeps the block consistent for exec'd children.
     */
    if (Tcl_SetVar(interp, "env(TCL_LIBRARY)", "//zipfs:/app/tcl_library",
	    TCL_GLOBAL_ONLY) == NULL) {
	return TCL_ERROR;
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
