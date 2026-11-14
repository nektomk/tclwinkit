/*
 * kit_safe_main.c --
 *
 *	Console (tclsh-style) main for the SAFE variant of tclwinkit
 *	(tclsafe.exe). A deliberate copy of kit_main.c differing in exactly one
 *	respect: Tcl_AppInit publishes ::winkit::safe_mode so that the VFS
 *	startup script routes execution into a safe child interpreter instead
 *	of running it in the master.
 *
 *	Why a copy rather than a #ifdef in kit_main.c: the two executables are
 *	linked from separate objects by scripts/build-msvc-kit.bat, and keeping
 *	the shipped console kit byte-identical means a defect in the safe
 *	variant cannot regress tclwin.exe. The cost is that a fix to the shared
 *	initialisation sequence has to be applied to both files; the divergence
 *	is confined to the block marked SAFE-MODE below so it stays greppable.
 *
 *	The master interpreter stays fully privileged on purpose. Making the
 *	master itself safe is neither publicly possible in Tcl 9 (Tcl_MakeSafe
 *	is absent from tclDecls.h, MakeSafe() is static in tclBasic.c) nor
 *	useful: the REPL, TclReadLine and the console plumbing all live in the
 *	master. Isolation comes from safe::interpCreate in
 *	lib/winkit/safe_master.tcl. See plans/V0_3-PLAN.md section 2.6.
 *
 *	Build WITHOUT UNICODE issues: Tcl 9 requires UNICODE on Windows for
 *	TclZipfs_AppHook.
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
 *	Application-specific initialization for the safe console kit.
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

    /* ---- SAFE-MODE (the only difference from kit_main.c) --------------
     *
     * Publish the flag main.tcl branches on. Tcl_AppInit runs before
     * Tcl_Main evaluates the VFS startup script, so main.tcl sees this from
     * its first line.
     *
     * A fully qualified name is used because Tcl_SetVar resolves it through
     * TclLookupVar, which creates the intermediate namespace: ::winkit need
     * not exist yet, and main.tcl need not have run. Measured rather than
     * assumed -- tmp/b2-flagvar-probe.tcl shows `namespace exists` going
     * 0 -> 1 across such a set, and shows the consumer guard
     * [info exists ::ns::flag] && $::ns::flag taking the normal branch when
     * the flag was never set. That second half is what keeps tclwin.exe
     * (built from kit_main.c, which does not set this) on its existing path.
     *
     * Value "1" rather than a boolean object: main.tcl tests truth, and the
     * string keeps the C side free of Tcl_Obj lifetime questions.
     */
    if (Tcl_SetVar(interp, "::winkit::safe_mode", "1",
	    TCL_GLOBAL_ONLY) == NULL) {
	return TCL_ERROR;
    }

    /* NOTE: no tcl_rcFileName is set here on purpose. A per-user rc file
     * would execute untrusted script from the home directory on every
     * interactive start, reintroducing an environment dependency that the
     * portable runtime explicitly avoids. This matters more in the safe kit:
     * an rc file would run in the MASTER, which is not sandboxed at all. */
    return TCL_OK;
}
