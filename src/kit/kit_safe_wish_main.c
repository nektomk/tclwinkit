/*
 * kit_safe_wish_main.c --
 *
 *	GUI (wish-style) main for the SAFE variant of tclwinkit (tksafe.exe).
 *	A deliberate copy of kit_wish_main.c differing in three respects, all
 *	marked below: Tcl_AppInit publishes ::winkit::safe_mode so the startup
 *	script routes execution into a safe child interpreter; no console
 *	window is created; and the startup script is set explicitly to the GUI
 *	safe bootstrap rather than left to command-line processing.
 *
 *	Why a copy rather than a #ifdef in kit_wish_main.c: the two executables
 *	are linked from separate objects by scripts/build-msvc-kit.bat, and
 *	keeping the shipped GUI kit byte-identical means a defect in the safe
 *	variant cannot regress tkwin.exe. The cost is that a fix to the shared
 *	initialisation sequence has to be applied to both files; the divergences
 *	are confined to the blocks marked SAFE-MODE, SAFE-STARTUP and
 *	NO-CONSOLE so they stay greppable.
 *
 *	DEVIATION FROM THE PLAN, on evidence. plans/V0_3-PLAN.md section 2.7
 *	(last bullet) asks for Tk_MainEx(argc, argv, appInit, NULL, NULL) here
 *	"instead of Tk_Main", on the stated grounds that Tk_Main reaches
 *	Tk_CreateConsoleWindow via Tk_MainEx -> TkCreateMainWindow. That chain
 *	does not exist in Tk 9.0.4:
 *
 *	  - tk.h:1513 makes Tk_Main a MACRO, not a function:
 *	      #define Tk_Main(argc, argv, proc) Tk_MainEx(argc, argv, proc, \
 *	          (Tcl_FindExecutable(0), (Tcl_CreateInterp)()))
 *	    so Tk_Main and Tk_MainEx are the same call, and writing Tk_MainEx
 *	    by hand would mean open-coding Tcl_FindExecutable plus
 *	    Tcl_CreateInterp for no behavioural difference.
 *	  - Tk_MainEx is declared with FOUR parameters (tkDecls.h:1812,
 *	    Tcl_Size argc, char **argv, Tcl_AppInitProc *, Tcl_Interp *), not
 *	    five, and under UNICODE on Win32 it is #defined to Tk_MainExW taking
 *	    wchar_t **argv. The plan's argument list would not compile.
 *	  - grep for "CreateConsole" over generic/tkMain.c returns nothing, and
 *	    Tk_CreateConsoleWindow has no caller anywhere in generic/ or win/
 *	    apart from its own definition in generic/tkConsole.c. Tk_MainEx does
 *	    call Tk_InitConsoleChannels (tkMain.c:231), which redirects the
 *	    standard CHANNELS and creates no window.
 *
 *	The only console window in this kit is the one kit_wish_main.c creates
 *	explicitly, so suppressing it there is sufficient and this file keeps
 *	the Tk_Main macro. See the NO-CONSOLE block for the consequence.
 *
 *	The master interpreter stays fully privileged on purpose; isolation
 *	comes from safe::interpCreate in lib/winkit/safe_master.tcl. See
 *	plans/V0_3-PLAN.md section 3 (the bullet "the master stays a full
 *	kit -- deliberately").
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

/* ---- NO-CONSOLE (differs from kit_wish_main.c, which uses TRUE) --------
 *
 * The safe GUI kit gets no console window, so that launching tksafe.exe does
 * not pop one that takes focus away from the GUI the user asked for. The plan
 * carries no dedicated section for this choice; it is recorded through its
 * consequence in plans/V0_3-PLAN.md section 1 decision 21 -- tksafe.exe run
 * without a script name shows usage in a MessageBox precisely because there
 * is no console left to print it to.
 *
 * Consequence, stated plainly because it is not free: this is a
 * windows-subsystem executable, so with the console suppressed there is no
 * stdout/stderr sink and no interactive REPL for tksafe.exe. Script mode is
 * unaffected -- a Tk script draws its own windows, and B5 gives the safe
 * child its SafeTk host -- but an interactive safe shell on Windows would
 * need a REPL living in a window instead. That is deferred and tracked in
 * plans/V0_3-PLAN.md section 7. Flip this to TRUE to get tkwin.exe's
 * behaviour back; it is the single point of control and nothing else in this
 * file depends on it.
 */
static BOOL consoleRequired = FALSE;

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

    consoleRequired = FALSE;
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
 *	Application-specific initialization for the safe GUI kit.
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
    /*
     * Registering Tk with BOTH an unsafe and a safe init proc is what makes
     * ::safe::loadTk work in the child: safe.tcl's AliasLoad consults the
     * static library table and calls the Tk_SafeInit entry for a safe
     * interpreter. Without this line the child's `load {} Tk` has nothing to
     * resolve to. Already present in kit_wish_main.c; kept identical here.
     */
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

    /* ---- SAFE-MODE (one of the differences from kit_wish_main.c) ------
     *
     * Publish the flag the startup script branches on. Tcl_AppInit runs
     * before Tk_MainEx evaluates the startup script, so the script sees this
     * from its first line.
     *
     * A fully qualified name is used because Tcl_SetVar resolves it through
     * TclLookupVar, which creates the intermediate namespace: ::winkit need
     * not exist yet, and the startup script need not have run. Measured
     * rather than assumed -- tmp/b2-flagvar-probe.tcl shows `namespace exists`
     * going 0 -> 1 across such a set, and shows the consumer guard
     * [info exists ::ns::flag] && $::ns::flag taking the normal branch when
     * the flag was never set. That second half is what keeps tkwin.exe
     * (built from kit_wish_main.c, which does not set this) on its existing
     * path.
     */
    if (Tcl_SetVar(interp, "::winkit::safe_mode", "1",
	    TCL_GLOBAL_ONLY) == NULL) {
	return TCL_ERROR;
    }

    /* ---- SAFE-STARTUP (the third difference from kit_wish_main.c) -----
     *
     * Take over the startup script. Without this call Tk_MainEx would treat
     * argv[1] as the script to run and evaluate it HERE, in the fully
     * privileged master -- the exact opposite of what a kit called "safe"
     * must do. Setting the startup script to our own bootstrap means
     * Tk_MainEx evaluates that instead, and the bootstrap decides what
     * happens to the user's script (plan section 3.1, decision 20).
     *
     * Why this works, and why it is safe to do from here:
     *
     *   - Tk_MainEx parses argv[1] into the startup script slot ONLY when
     *     nothing is set yet (tkMain.c:245-267), and it does so BEFORE
     *     calling appInitProc -- so by the time we run, $argv0/$argc/$argv
     *     already carry the user's command line, script name in $argv0.
     *   - It then re-fetches the slot after appInitProc returns, with the
     *     comment "Must fetch it again, as the appInitProc might have reset
     *     it" (tkMain.c:317-322). Overriding it here is the documented
     *     extension point, not a race.
     *
     * The target is deliberately NOT <image>/main.tcl. TclZipfs_AppHook
     * promotes /main.tcl to the startup script for ANY exe carrying the
     * image (tclZipfs.c:6637-6641), and the GUI image is shared with
     * tkwin.exe, which must keep behaving exactly like stock wish. Living
     * under lib/winkit/ keeps it invisible to that mechanism: only this file
     * ever asks for it.
     *
     * Existence is deliberately NOT checked. If the file is missing the
     * bootstrap fails in Tcl_FSEvalFileEx, Tk_MainEx reports "Error in
     * startup script" and exits 1 -- loudly, on every run. Gating on
     * Tcl_FSAccess and falling through when absent would instead hand the
     * user's script to the unsandboxed master, i.e. turn a broken build into
     * a silent sandbox bypass. A missing file must be a hard failure.
     *
     * Tcl_SetStartupScript takes its own reference (tclMain.c:152-158: it
     * IncrRefCount's the new path and releases the previous one), so the
     * object is handed over rather than freed here.
     */
    Tcl_SetStartupScript(Tcl_NewStringObj(
	    "//zipfs:/app/lib/winkit/safe_main_gui.tcl", TCL_INDEX_NONE), NULL);

    /* NOTE: no tcl_rcFileName is set here on purpose. A per-user rc file
     * would execute untrusted script from the home directory on every
     * interactive start, reintroducing an environment dependency that the
     * portable runtime explicitly avoids. This matters more in the safe kit:
     * an rc file would run in the MASTER, which is not sandboxed at all. */
    return TCL_OK;
}
