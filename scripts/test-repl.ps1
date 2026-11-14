# test-repl.ps1 -- interactive REPL test for the console kit.
#
#   Launches the kit exe in a private working directory, attaches to its
#   console, injects real keystrokes with WriteConsoleInput (records go into the
#   console input buffer exactly like typing), captures the screen buffer, then
#   sends `exit`.
#
#   Special-key tokens inside a sent string:
#     @UP@ @DOWN@ @LEFT@ @RIGHT@ @HOME@ @END@ @DEL@ @TAB@ @STAB@
#     @CTRLA@ @CTRLE@ @CTRLC@ @PGUP@ @PGDN@
#   Every sent string is followed by Enter.
#
# WHY THE CHECKS LOOK CONTRIVED. The previous version asserted three substrings
# against the captured screen: 'test123', '9.0.4' and 'X5'. All three could be
# satisfied with history, cursor editing and completion ALL BROKEN:
#   * '9.0.4'  is in the startup banner ("Tcl 9.0.4 interactive shell");
#   * 'test123' is in the typed command itself (`set histkey test123`);
#   * 'X5'     is in the redraw artifact of the edited line -- the screen showed
#              `set a 5X5` while the command actually run was `set a X5`.
# Its completion case was vacuous for a second reason: `info patc@STAB@` probes
# FILENAME completion (from the repo root it expands to `info patches/` and
# errors), and when nothing matches, the line stays `info patc` and Tcl's own
# unique-prefix resolution prints 9.0.4 anyway. Command-name prefixes can never
# test completion, because Tcl resolves any unique prefix by itself -- measured:
# `strin@STAB@ repeat ab 3` ran as `strin repeat ab 3`, uncompleted, and still
# printed `ababab`.
#
# So every check below asserts an observable that cannot appear unless the
# feature ran, and prefers a before/after delta over mere presence:
#
#   history    `set hkey [string repeat q 7]` prints qqqqqqq, which is NOT in
#              the typed text; @UP@ + Enter must ADD a second occurrence, so the
#              check is "count grew", not "present".
#   editing    the keystrokes are `expr 7`, @LEFT@, `123*`, Enter. With a
#              working @LEFT@ the buffer becomes `expr 123*7` and prints 861;
#              without it the buffer stays `expr 7123*`, a syntax error, and 861
#              cannot appear anywhere. Only the RESULT is asserted, never the
#              echoed line: the redraw does not erase the characters an insert
#              displaced, so the screen reads `expr 7123*7` while what actually
#              executed was `expr 123*7` -- and `7123` is a substring of both the
#              working and the broken rendering. Asserting on the echo therefore
#              fails on a WORKING cursor; that is the trap the old 'X5' marker
#              fell into (screen showed `set a 5X5`, executed was `set a X5`).
#   completion `source wkpalpha<rand>@STAB@` must expand to a probe file this
#              script wrote into a private working directory. The marker is the
#              token that file PRINTS -- absent from the banner, from the typed
#              text and from the file name -- asserted absent immediately before
#              the command and present after. A second probe file with a
#              different token sits in the same directory and its token must NOT
#              appear, which is what proves completion picked the right file.
#   no-match   a prefix matching nothing must reach `source` uncompleted and
#              fail there, so "completed correctly" stays distinguishable from
#              "silently did nothing".
#
# A real console is required (AttachConsole + CONIN$/CONOUT$). A shell whose
# stdout is redirected has none -- GetConsoleWindow returns 0 and AttachConsole
# fails with win32 error 6. Launch through `start`, which allocates one:
#   cmd /c start "repl" /wait cmd /c "cd /d <repo> && pwsh -NoProfile -File scripts\test-repl.ps1 > out.txt 2>&1"
#
# Usage: scripts\test-repl.ps1 [-Exe path] [-KeepWorkDir]
#
# Exit code = number of failed checks.

param(
    [string]$Exe = '',
    [switch]$KeepWorkDir
)
$ErrorActionPreference = 'Stop'

# $PSScriptRoot is not populated during parameter binding on Windows
# PowerShell 5.1, so the default is resolved in the body, not in param().
if (-not $Exe) {
    $repo = Split-Path -Parent $PSScriptRoot
    $Exe = Join-Path $repo 'dist\msvc\tclwin.exe'
}
if (-not (Test-Path -LiteralPath $Exe)) { throw ('no such executable: ' + $Exe) }

$fail = 0
function Chk([bool]$ok, [string]$what) {
    if (-not $ok) { $script:fail = $script:fail + 1 }
    Write-Output ('  ' + $(if ($ok) { 'ok   ' } else { 'FAIL ' }) + $what)
}
function Say([string]$what) { Write-Output ('  info  ' + $what) }

# Count non-overlapping occurrences. Presence is not enough for the history
# check: the recalled line is echoed as well as executed, so what proves recall
# is the count GROWING between two captures.
function CountIn([string]$hay, [string]$needle) {
    $n = 0
    $i = 0
    while (($i = $hay.IndexOf($needle, $i, [System.StringComparison]::Ordinal)) -ge 0) {
        $n = $n + 1
        $i = $i + $needle.Length
    }
    return $n
}

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Collections.Generic;

public static class ConDrv {
    [StructLayout(LayoutKind.Sequential)]
    public struct KEY_EVENT_RECORD {
        public int bKeyDown;
        public ushort wRepeatCount;
        public ushort wVirtualKeyCode;
        public ushort wVirtualScanCode;
        public char UnicodeChar;
        public uint dwControlKeyState;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct INPUT_RECORD {
        public ushort EventType;
        public ushort pad1;          // Event union aligns to 4: total size 20
        public KEY_EVENT_RECORD KeyEvent;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct COORD { public short X; public short Y; }
    [StructLayout(LayoutKind.Sequential)]
    public struct SMALL_RECT { public short Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)]
    public struct CONSOLE_SCREEN_BUFFER_INFO {
        public COORD dwSize; public COORD dwCursorPosition;
        public ushort wAttributes; public SMALL_RECT srWindow;
        public COORD dwMaximumWindowSize;
    }

    [DllImport("kernel32.dll", SetLastError=true)] public static extern bool FreeConsole();
    [DllImport("kernel32.dll", SetLastError=true)] public static extern bool AttachConsole(uint pid);
    [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    public static extern IntPtr CreateFileW(string name, uint access, uint share, IntPtr sec, uint disp, uint flags, IntPtr tmpl);
    [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    public static extern bool WriteConsoleInputW(IntPtr h, INPUT_RECORD[] recs, uint n, out uint written);
    [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    public static extern bool ReadConsoleOutputCharacterW(IntPtr h, StringBuilder buf, uint len, COORD pos, out uint nread);
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool GetConsoleScreenBufferInfo(IntPtr h, out CONSOLE_SCREEN_BUFFER_INFO info);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern short VkKeyScanW(char c);
    [DllImport("user32.dll")] public static extern uint MapVirtualKeyW(uint vk, uint type);

    const uint GENERIC_WRITE = 0x40000000, GENERIC_READ = 0x80000000;
    const uint FILE_SHARE_READ = 1, FILE_SHARE_WRITE = 2;
    const uint OPEN_EXISTING = 3;

    // Control-key-state bits
    const uint SHIFT = 0x10, LCTRL = 0x8, ENHANCED = 0x100;

    public static void Attach(uint pid) {
        FreeConsole();
        if (!AttachConsole(pid)) throw new Exception("AttachConsole failed: " + Marshal.GetLastWin32Error());
    }

    static INPUT_RECORD Rec(ushort vk, char c, uint ctrl, ushort scan) {
        INPUT_RECORD r = new INPUT_RECORD();
        r.EventType = 1;
        r.KeyEvent.bKeyDown = 1;
        r.KeyEvent.wRepeatCount = 1;
        r.KeyEvent.wVirtualKeyCode = vk;
        r.KeyEvent.wVirtualScanCode = scan;
        r.KeyEvent.UnicodeChar = c;
        r.KeyEvent.dwControlKeyState = ctrl;
        return r;
    }

    static INPUT_RECORD CharRec(char c) {
        if (c == '\r') return Rec(13, '\r', 0, 28);
        short vk = VkKeyScanW(c);
        ushort code = (ushort)(vk & 0xFF);
        return Rec(code, c, 0, (ushort)MapVirtualKeyW(code, 0));
    }

    static readonly HashSet<string> Specials = new HashSet<string>(new string[] {
        "@UP@","@DOWN@","@LEFT@","@RIGHT@","@HOME@","@END@","@DEL@","@PGUP@","@PGDN@",
        "@TAB@","@STAB@","@CTRLA@","@CTRLE@","@CTRLC@"
    });
    static bool IsSpecial(string tok) { return Specials.Contains(tok); }

    static INPUT_RECORD Special(string tok) {
        switch (tok) {
            case "@UP@":    return Rec(38, '\0', ENHANCED, 72);
            case "@DOWN@":  return Rec(40, '\0', ENHANCED, 80);
            case "@LEFT@":  return Rec(37, '\0', ENHANCED, 75);
            case "@RIGHT@": return Rec(39, '\0', ENHANCED, 77);
            case "@HOME@":  return Rec(36, '\0', ENHANCED, 71);
            case "@END@":   return Rec(35, '\0', ENHANCED, 79);
            case "@DEL@":   return Rec(46, '\0', ENHANCED, 83);
            case "@PGUP@":  return Rec(33, '\0', ENHANCED, 73);
            case "@PGDN@":  return Rec(34, '\0', ENHANCED, 81);
            case "@TAB@":   return Rec(9, '\t', 0, 15);
            case "@STAB@":  return Rec(9, '\t', SHIFT, 15);
            case "@CTRLA@": return Rec(65, '\x01', LCTRL, 30);
            case "@CTRLE@": return Rec(69, '\x05', LCTRL, 18);
            case "@CTRLC@": return Rec(67, '\x03', LCTRL, 46);
        }
        throw new Exception("unknown token " + tok);
    }

    public static void SendSeq(string s) {
        List<INPUT_RECORD> recs = new List<INPUT_RECORD>();
        int i = 0;
        while (i < s.Length) {
            if (s[i] == '@') {
                int j = s.IndexOf('@', i + 1);
                if (j > i) {
                    string tok = s.Substring(i, j - i + 1);
                    if (IsSpecial(tok)) {
                        recs.Add(Special(tok));
                        i = j + 1;
                        continue;
                    }
                }
            }
            recs.Add(CharRec(s[i]));
            i++;
        }
        recs.Add(CharRec('\r'));
        IntPtr h = CreateFileW("CONIN$", GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero);
        if (h == new IntPtr(-1)) throw new Exception("CONIN$ open failed: " + Marshal.GetLastWin32Error());
        uint written;
        if (!WriteConsoleInputW(h, recs.ToArray(), (uint)recs.Count, out written))
            throw new Exception("WriteConsoleInput failed: " + Marshal.GetLastWin32Error());
    }

    public static string CaptureScreen() {
        IntPtr h = CreateFileW("CONOUT$", GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero);
        if (h == new IntPtr(-1)) throw new Exception("CONOUT$ open failed: " + Marshal.GetLastWin32Error());
        CONSOLE_SCREEN_BUFFER_INFO info;
        if (!GetConsoleScreenBufferInfo(h, out info)) throw new Exception("GetConsoleScreenBufferInfo failed");
        int w = info.dwSize.X, hgt = info.dwSize.Y;
        StringBuilder sb = new StringBuilder();
        uint nread;
        for (int y = 0; y < hgt; y++) {
            StringBuilder line = new StringBuilder(w);
            COORD pos = new COORD(); pos.X = 0; pos.Y = (short)y;
            if (!ReadConsoleOutputCharacterW(h, line, (uint)w, pos, out nread)) break;
            sb.Append(line.ToString(0, (int)nread).TrimEnd());
            sb.Append('\n');
        }
        return sb.ToString().TrimEnd();
    }
}
'@

# --- private working directory and probe files -------------------------------
# The kit is started in its own empty directory so that filename completion has
# exactly two candidates, both written here. Running it in the caller's cwd
# instead would make the result depend on whatever happens to be there -- which
# is how the old `info patc@STAB@` case came to complete to `patches/`.
$rnd  = [guid]::NewGuid().ToString('n').Substring(0, 8)
$Work = Join-Path $env:TEMP ('winkit-repl-' + $rnd)
[void](New-Item -ItemType Directory -Force -Path $Work)

$nameA = 'wkpalpha' + $rnd + '.tcl'
$nameB = 'wkpbeta' + $rnd + '.tcl'
$tokA  = 'WKRPLTOKA' + $rnd
$tokB  = 'WKRPLTOKB' + $rnd
$prefixA = 'wkpalpha'

$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $Work $nameA), ('puts ' + $tokA + "`n"), $utf8)
[System.IO.File]::WriteAllText((Join-Path $Work $nameB), ('puts ' + $tokB + "`n"), $utf8)

Write-Output ('exe     : ' + $Exe)
Write-Output ('workdir : ' + $Work)
Write-Output ('probe A : ' + $nameA + ' -> ' + $tokA)
Write-Output ('probe B : ' + $nameB + ' -> ' + $tokB)

$proc = Start-Process -FilePath $Exe -WorkingDirectory $Work -PassThru
Write-Output ('launched pid ' + $proc.Id)
Start-Sleep -Milliseconds 2500

$screen = ''
$exitCode = -1
$attachErr = ''
try {
    $attached = $false
    try {
        [ConDrv]::Attach([uint32]$proc.Id)
        $attached = $true
    } catch { $attachErr = $_.Exception.Message }
    Chk $attached ('attached to the kit console, pid ' + $proc.Id + $(if ($attached) { '' } else { ' -- ' + $attachErr }))

    if ($attached) {
        # --- 0. we are really looking at the REPL, and the marker is not yet
        #        on screen: without this baseline a token left over from
        #        anything else would pass the completion check.
        $s0 = [ConDrv]::CaptureScreen()
        Chk ($s0.Contains('interactive shell')) 'REPL banner captured from the screen buffer'
        Chk ((CountIn $s0 $tokA) -eq 0) 'probe token A absent before any command is sent'

        # --- 1. history: qqqqqqq is printed, never typed
        [ConDrv]::SendSeq('set hkey [string repeat q 7]')
        Start-Sleep -Milliseconds 700
        $s1 = [ConDrv]::CaptureScreen()
        $c1 = CountIn $s1 'qqqqqqq'
        Chk ($c1 -ge 1) ('set printed its value, "qqqqqqq" seen ' + $c1 + 'x')

        [ConDrv]::SendSeq('@UP@')
        Start-Sleep -Milliseconds 700
        $s2 = [ConDrv]::CaptureScreen()
        $c2 = CountIn $s2 'qqqqqqq'
        Chk ($c2 -gt $c1) ('@UP@ recalled and re-ran the line: "qqqqqqq" ' + $c1 + 'x -> ' + $c2 + 'x')

        # --- 2. cursor editing: only a real @LEFT@ makes this 123*7
        [ConDrv]::SendSeq('expr 7@LEFT@123*')
        Start-Sleep -Milliseconds 700
        $s3 = [ConDrv]::CaptureScreen()
        Chk ($s3.Contains('861')) '@LEFT@ moved the cursor: expr 7@LEFT@123* evaluated to 861'

        # --- 3. completion, with a before/after delta on a printed token
        $s4 = [ConDrv]::CaptureScreen()
        Chk ((CountIn $s4 $tokA) -eq 0) ('token A still absent immediately before "source ' + $prefixA + '@STAB@"')
        [ConDrv]::SendSeq('source ' + $prefixA + '@STAB@')
        Start-Sleep -Milliseconds 900
        $s5 = [ConDrv]::CaptureScreen()
        Chk ((CountIn $s5 $tokA) -ge 1) 'Shift-Tab completed the file name and the probe ran (token A present)'
        Chk ((CountIn $s5 $tokB) -eq 0) ('  and it completed to the RIGHT file: token B of ' + $nameB + ' absent')

        # --- 4. a prefix that matches nothing must not be silently accepted
        [ConDrv]::SendSeq('source wkpnomatch@STAB@')
        Start-Sleep -Milliseconds 900
        $s6 = [ConDrv]::CaptureScreen()
        Chk ($s6.Contains("couldn't read file")) 'an unmatched prefix stays uncompleted and fails at source'

        $screen = $s6
        [ConDrv]::SendSeq('exit')
    }

    if (-not $proc.WaitForExit(8000)) {
        Write-Output 'WARN: process did not exit after the exit command - killing it'
        try { $proc | Stop-Process -Force } catch { }
        $exitCode = -1
    } else {
        $exitCode = $proc.ExitCode
    }
    Chk ($exitCode -eq 0) ('exit code 0 after the exit command (got ' + $exitCode + ')')
} finally {
    try { [ConDrv]::FreeConsole() | Out-Null } catch { }
    if (-not $proc.HasExited) { try { $proc.Kill() } catch { } }
    if ($KeepWorkDir) { Say ('workdir kept: ' + $Work) }
    else { Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Output ''
Write-Output '=== captured screen ==='
Write-Output $screen
Write-Output '=== end capture ==='
Write-Output ('RESULT: failures ' + $fail)
if ($fail -eq 0) { Write-Output 'REPL TEST OK' } else { Write-Output 'REPL TEST FAILED' }
exit $fail
