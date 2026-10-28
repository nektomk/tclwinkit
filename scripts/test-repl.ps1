# test-repl.ps1 --
#   Automated interactive-REPL smoke for the console kits.
#
#   Launches the kit exe in its own console, attaches to that console
#   from this process, injects keystrokes with WriteConsoleInput
#   (records go straight into the console input buffer, exactly like
#   real typing), captures the screen buffer text, then sends `exit`.
#
#   Command strings may contain special-key tokens:
#     @UP@ @DOWN@ @LEFT@ @RIGHT@ @HOME@ @END@ @DEL@ @TAB@ @STAB@
#     @CTRLA@ @CTRLE@ @CTRLC@ @PGUP@ @PGDN@
#   Each -Commands entry is sent followed by Enter.
#
#   Usage: scripts\test-repl.ps1 [-Exe path] [-Commands ...] [-Markers ...]

param(
    [string]$Exe = '',
    [string[]]$Commands = @(
        'set histkey test123',
        '@UP@',
        'info patc@STAB@',
        'set a 5@LEFT@X',
        'exit'
    ),
    [string[]]$Markers = @('test123', '9.0.4', 'X5')
)

$ErrorActionPreference = 'Stop'

# $PSScriptRoot is not populated during parameter binding on Windows
# PowerShell 5.1, so the default is resolved in the body, not in param().
if (-not $Exe) {
    $repo = Split-Path -Parent $PSScriptRoot
    $Exe = Join-Path $repo 'dist\tclwinkit-msvc.exe'
}

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
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

# Launch the kit in its own console window
$proc = Start-Process -FilePath $Exe -PassThru
Write-Host "launched pid $($proc.Id): $Exe"
Start-Sleep -Milliseconds 2500

[ConDrv]::Attach([uint32]$proc.Id)
try {
    foreach ($cmd in $Commands) {
        if ($cmd -eq 'exit') { continue }
        [ConDrv]::SendSeq($cmd)
        Start-Sleep -Milliseconds 500
    }
    # Capture the screen while the REPL is still alive
    Start-Sleep -Milliseconds 500
    $screen = [ConDrv]::CaptureScreen()
    # Now terminate the REPL
    [ConDrv]::SendSeq('exit')
} finally {
    [ConDrv]::FreeConsole() | Out-Null
}

if (-not $proc.WaitForExit(5000)) {
    Write-Host "WARN: process did not exit after 'exit' command - killing"
    $proc | Stop-Process -Force
    $exitCode = -1
} else {
    $exitCode = $proc.ExitCode
}

Write-Host "=== captured screen (exit=$exitCode) ==="
Write-Host $screen
Write-Host "=== end capture ==="

$fail = 0
foreach ($m in $Markers) {
    if ($screen -notlike "*$m*") { Write-Host "MISSING MARKER: $m"; $fail = 1 }
    else { Write-Host "marker ok: $m" }
}
if ($exitCode -ne 0) { Write-Host "BAD EXIT CODE: $exitCode"; $fail = 1 }
if ($fail) { Write-Host 'REPL TEST FAILED'; exit 1 }
Write-Host 'REPL TEST OK'
exit 0
