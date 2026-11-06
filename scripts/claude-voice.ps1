# Claude Voice helper: runs in the background, owns all read-aloud playback,
# and listens for global hotkeys.
#   Ctrl+Alt+S  stop
#   Ctrl+Alt+P  pause / resume
#   Ctrl+Alt+R  reread the last reply
#   Ctrl+Alt+H  read whatever text is highlighted (in any app)
# The Stop hook (speak-response.ps1) drops replies into the inbox folder;
# stop-speaking.ps1 drops a stop request. Only one copy runs at a time.
# It shuts itself down about a minute after the last Claude Code session closes,
# and never runs while voice is turned off (/voice-off).

$dir   = Join-Path $env:TEMP 'claude-voice'
$inbox = Join-Path $dir 'inbox'
New-Item -ItemType Directory -Force $inbox | Out-Null

if (Test-Path (Join-Path $env:USERPROFILE '.claude\voice-off')) { exit 0 }

$created = $false
$script:mutex = New-Object System.Threading.Mutex($true, 'Local\ClaudeVoiceHelper', [ref]$created)
if (-not $created) { exit 0 }

$script:log = Join-Path $dir 'voice.log'
function Log([string]$m) { try { Add-Content -LiteralPath $script:log ("{0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $m) } catch {} }

Add-Type -AssemblyName System.Windows.Forms, System.Speech
Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition @"
using System;
using System.Collections.Concurrent;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;
public class VoiceHotkeys : NativeWindow {
    [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr h, int id, uint mods, uint vk);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vk);
    [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetClipboardSequenceNumber();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("winmm.dll", CharSet = CharSet.Unicode)] static extern int mciSendString(string cmd, StringBuilder ret, int len, IntPtr cb);
    public ConcurrentQueue<int> Pressed = new ConcurrentQueue<int>();
    public VoiceHotkeys() { CreateHandle(new CreateParams()); }
    // 0x4000 = MOD_NOREPEAT so holding the keys doesn't fire repeatedly.
    public bool Register(int id, uint mods, uint vk) { return RegisterHotKey(Handle, id, mods | 0x4000, vk); }
    protected override void WndProc(ref Message m) {
        if (m.Msg == 0x0312) Pressed.Enqueue(m.WParam.ToInt32());
        base.WndProc(ref m);
    }
    public static string Mci(string cmd) {
        var sb = new StringBuilder(256);
        int r = mciSendString(cmd, sb, 256, IntPtr.Zero);
        return r == 0 ? sb.ToString() : "ERR" + r;
    }
    public static long ForegroundWindow() { return GetForegroundWindow().ToInt64(); }
    public static int ForegroundPid() { uint pid; GetWindowThreadProcessId(GetForegroundWindow(), out pid); return (int)pid; }
    // Press Ctrl (+Shift) + C as real key events.
    public static void SendCopy(bool shift) {
        keybd_event(0x11, 0, 0, UIntPtr.Zero);
        if (shift) keybd_event(0x10, 0, 0, UIntPtr.Zero);
        keybd_event(0x43, 0, 0, UIntPtr.Zero);
        keybd_event(0x43, 0, 2, UIntPtr.Zero);
        if (shift) keybd_event(0x10, 0, 2, UIntPtr.Zero);
        keybd_event(0x11, 0, 2, UIntPtr.Zero);
    }
    public static bool ModifiersDown() {
        return (GetAsyncKeyState(0x10) & 0x8000) != 0 || (GetAsyncKeyState(0x11) & 0x8000) != 0 || (GetAsyncKeyState(0x12) & 0x8000) != 0;
    }
}
"@

# ---------- Python (for the Ava voice) ----------
# First interpreter where `import edge_tts` works: the python.org 3.13 install,
# then the `py -3` launcher, then `python` on PATH. None found = David voice.
function Find-Python {
    $candidates = @(
        @{ File = (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python313\python.exe'); Args = @() },
        @{ File = 'py';     Args = @('-3') },
        @{ File = 'python'; Args = @() }
    )
    foreach ($c in $candidates) {
        $cmd = Get-Command $c.File -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $cmd) { continue }
        # Skip the Microsoft Store "python" stub, which opens the Store instead of running.
        if ($cmd.Source -like '*\Microsoft\WindowsApps\*') { continue }
        try {
            $p = Start-Process -FilePath $cmd.Source -WindowStyle Hidden -PassThru -Wait -ArgumentList ($c.Args + @('-c', '"import edge_tts"'))
            if ($p.ExitCode -eq 0) { return @{ File = $cmd.Source; Args = $c.Args } }
        } catch {}
    }
    return $null
}

# ---------- state ----------
$script:python   = Find-Python
$script:useAva   = $null -ne $script:python
$script:chunks   = @()
$script:idx      = 0
$script:state    = 'idle'      # idle | waiting | ava | david
$script:paused   = $false
$script:procs    = @{}
$script:retried  = @{}
$script:waitFrom = Get-Date
$script:session  = 0
$script:last     = ''
$script:copyAt   = $null
$script:clipSeq  = [uint32]0
$script:clipChangedAt = [datetime]::MinValue
$script:sp = New-Object System.Speech.Synthesis.SpeechSynthesizer
try { $script:sp.SelectVoice('Microsoft David Desktop') } catch {}
$script:sp.Rate = 1

function Clean-Text([string]$text) {
    $text = [regex]::Replace($text, '(?s)```.*?```', ' (code block omitted) ')
    $text = [regex]::Replace($text, '\[([^\]]+)\]\([^)]+\)', '$1')
    $text = [regex]::Replace($text, '(?m)^\s*\|?[\s:|-]+\|[\s:|-]*$', '')
    $text = $text -replace '[`*_#>|]', ' '
    $text = [regex]::Replace($text, '(?m)^\s*[-+]\s+', '')
    $text = [regex]::Replace($text, '\s+', ' ').Trim()
    if ($text.Length -gt 2500) { $text = $text.Substring(0, 2500) + ' ... the rest is on screen.' }
    return $text
}

function Split-Chunks([string]$text) {
    $sentences = [regex]::Split($text, '(?<=[.!?])\s+') | Where-Object { $_.Trim() }
    $list = New-Object System.Collections.Generic.List[string]
    $buf = ''
    foreach ($s in $sentences) {
        $limit = if ($list.Count -eq 0) { 160 } else { 450 }
        if ($buf -and ($buf.Length + $s.Length + 1) -gt $limit) { $list.Add($buf); $buf = $s }
        else { $buf = ($buf + ' ' + $s).Trim() }
    }
    if ($buf) { $list.Add($buf) }
    return ,$list.ToArray()
}

function Piece-Path([int]$i, [string]$ext) { Join-Path $dir ("piece-{0}-{1}.{2}" -f $script:session, $i, $ext) }

function Start-Piece([int]$i) {
    if (-not $script:useAva -or $i -ge $script:chunks.Count -or $script:procs.ContainsKey($i)) { return }
    $txt = Piece-Path $i 'txt'; $mp3 = Piece-Path $i 'mp3'
    [IO.File]::WriteAllText($txt, $script:chunks[$i], [Text.UTF8Encoding]::new($false))
    $script:procs[$i] = Start-Process -FilePath $script:python.File -WindowStyle Hidden -PassThru -ArgumentList ($script:python.Args + @(
        '-m', 'edge_tts', '--voice', 'en-US-AvaNeural', '--file', "`"$txt`"", '--write-media', "`"$mp3`""))
}

function Stop-Reading {
    [void][VoiceHotkeys]::Mci('stop clip'); [void][VoiceHotkeys]::Mci('close clip')
    try { if ($script:sp.State -eq 'Paused') { $script:sp.Resume() }; $script:sp.SpeakAsyncCancelAll() } catch {}
    foreach ($p in $script:procs.Values) { try { if (-not $p.HasExited) { $p.Kill() } } catch {} }
    $script:procs = @{}; $script:retried = @{}
    Get-ChildItem $dir -Filter 'piece-*' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    $script:state = 'idle'; $script:paused = $false; $script:chunks = @(); $script:idx = 0
}

function Start-Reading([string]$raw) {
    Stop-Reading
    $text = Clean-Text $raw
    if (-not $text) { return }
    $script:session++
    $script:chunks = Split-Chunks $text
    $script:idx = 0
    $script:state = 'waiting'; $script:waitFrom = Get-Date
    Start-Piece 0; Start-Piece 1
}

function Say-David([string]$t) {
    $script:state = 'david'
    [void]$script:sp.SpeakAsync($t)
}

function Toggle-Pause {
    if ($script:state -eq 'idle') { return }
    if ($script:paused) {
        if ($script:state -eq 'ava')   { [void][VoiceHotkeys]::Mci('resume clip') }
        if ($script:state -eq 'david') { $script:sp.Resume() }
        $script:paused = $false
    } else {
        if ($script:state -eq 'ava')   { [void][VoiceHotkeys]::Mci('pause clip') }
        if ($script:state -eq 'david') { $script:sp.Pause() }
        $script:paused = $true
    }
}

function Read-Highlighted {
    $saved = $null
    try { if ([Windows.Forms.Clipboard]::ContainsText()) { $saved = [Windows.Forms.Clipboard]::GetText() } } catch {}
    $seq = [VoiceHotkeys]::GetClipboardSequenceNumber()
    # Terminals: Ctrl+Shift+C (plain Ctrl+C there would interrupt the running program).
    # Everything else: Ctrl+C.
    $app = ''
    try { $app = (Get-Process -Id ([VoiceHotkeys]::ForegroundPid())).ProcessName } catch {}
    $terminals = 'WindowsTerminal','OpenConsole','conhost','cmd','powershell','pwsh','wezterm-gui','alacritty'
    [VoiceHotkeys]::SendCopy($terminals -contains $app)
    # Some apps (Claude Code included) copy slowly, so wait up to 3 seconds for the clipboard to change.
    $start = Get-Date
    $maxWait = if (((Get-Date) - $script:clipChangedAt).TotalSeconds -lt 60) { 0.6 } else { 3 }
    while ([VoiceHotkeys]::GetClipboardSequenceNumber() -eq $seq -and ((Get-Date) - $start).TotalSeconds -lt $maxWait) {
        Start-Sleep -Milliseconds 50
    }
    Start-Sleep -Milliseconds 100
    $sel = $null
    # Apps that copy on highlight (like Claude Code) already put the text on the
    # clipboard, so use it if it was copied in the last minute.
    $recent = ((Get-Date) - $script:clipChangedAt).TotalSeconds -lt 60
    if ([VoiceHotkeys]::GetClipboardSequenceNumber() -ne $seq -or $recent) {
        for ($w = 0; $w -lt 5 -and -not $sel; $w++) {
            try { if ([Windows.Forms.Clipboard]::ContainsText()) { $sel = [Windows.Forms.Clipboard]::GetText() } } catch {}
            if (-not $sel) { Start-Sleep -Milliseconds 100 }
        }
    }
    Log ("Highlight from '{0}': recent={4} clipboard changed={1} after {2:N1}s, got {3} chars" -f $app, ([VoiceHotkeys]::GetClipboardSequenceNumber() -ne $seq), ((Get-Date) - $start).TotalSeconds, ("$sel").Length, $recent)
    try { if ($saved -and $sel) { [Windows.Forms.Clipboard]::SetText($saved) } } catch {}
    if ($sel -and $sel.Trim()) { Start-Reading $sel } else { Start-Reading 'Nothing is highlighted.' }
}

function Advance {
    if ($script:paused) { return }
    switch ($script:state) {
        'waiting' {
            if ($script:idx -ge $script:chunks.Count) { Stop-Reading; return }
            $i = $script:idx
            if (-not $script:useAva) { Say-David $script:chunks[$i]; return }
            $mp3 = Piece-Path $i 'mp3'
            $p = $script:procs[$i]
            if (-not $p) { Start-Piece $i; return }
            if (-not $p.HasExited) {
                if (((Get-Date) - $script:waitFrom).TotalSeconds -gt 30) { try { $p.Kill() } catch {}; Say-David $script:chunks[$i] }
                return
            }
            if ((Test-Path $mp3) -and (Get-Item $mp3).Length -gt 0) {
                [void][VoiceHotkeys]::Mci('close clip')
                $r = [VoiceHotkeys]::Mci("open `"$mp3`" type mpegvideo alias clip")
                if ($r -like 'ERR*') { Log "mci open failed $r"; Say-David $script:chunks[$i]; return }
                [void][VoiceHotkeys]::Mci('play clip')
                $script:state = 'ava'
                Start-Piece ($i + 1); Start-Piece ($i + 2)
            } elseif (-not $script:retried[$i]) {
                $script:retried[$i] = $true; $script:procs.Remove($i); Start-Piece $i; $script:waitFrom = Get-Date
            } else {
                Say-David $script:chunks[$i]
            }
        }
        'ava' {
            $mode = [VoiceHotkeys]::Mci('status clip mode')
            if ($mode -ne 'playing') {
                [void][VoiceHotkeys]::Mci('close clip')
                Remove-Item (Piece-Path $script:idx '*') -ErrorAction SilentlyContinue
                $script:idx++; $script:state = 'waiting'; $script:waitFrom = Get-Date
            }
        }
        'david' {
            if ($script:sp.State -eq 'Ready') { $script:idx++; $script:state = 'waiting'; $script:waitFrom = Get-Date }
        }
    }
}

# ---------- hotkeys ----------
$script:hk = New-Object VoiceHotkeys
# Modifier bits: Alt = 1, Ctrl = 2.
$keys = @{ 1 = @('Stop', 0x53); 2 = @('Pause', 0x50); 3 = @('Reread', 0x52); 4 = @('Highlighted', 0x48) }
foreach ($id in $keys.Keys) {
    if (-not $script:hk.Register($id, 3, $keys[$id][1])) { Log "Could not register Ctrl+Alt hotkey for $($keys[$id][0]) (another app may own it)" }
}

# Throw away stale requests left from before a restart.
Get-ChildItem $inbox -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt (Get-Date).AddMinutes(-2) } | Remove-Item -Force -ErrorAction SilentlyContinue
Log ("Helper started; Ava voice: {0}" -f $(if ($script:useAva) { "$($script:python.File) $($script:python.Args -join ' ')".Trim() } else { 'no (edge_tts not found, using David)' }))

# Claude Code's command-line program is claude.exe outside WindowsApps (the Claude
# desktop app lives in WindowsApps), or node.exe running the npm package.
function Test-ClaudeCodeRunning {
    $procs = Get-CimInstance Win32_Process -Filter "Name='claude.exe' OR Name='node.exe'" -ErrorAction SilentlyContinue
    foreach ($p in $procs) {
        if ($p.Name -eq 'claude.exe' -and $p.ExecutablePath -notlike '*\WindowsApps\*') { return $true }
        if ($p.Name -eq 'node.exe' -and $p.CommandLine -like '*claude-code*') { return $true }
    }
    return $false
}
$script:nextCheck  = (Get-Date).AddSeconds(20)
$script:lastSeenCC = Get-Date

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 150
$timer.add_Tick({
    try {
        foreach ($f in (Get-ChildItem $inbox -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in '.say', '.stop' } | Sort-Object Name)) {
            try {
                if ($f.Extension -eq '.say') {
                    $t = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
                    $script:last = $t
                    Start-Reading $t
                } elseif ($f.Extension -eq '.stop') {
                    Stop-Reading
                }
            } finally { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue }
        }
        $id = 0
        while ($script:hk.Pressed.TryDequeue([ref]$id)) {
            switch ($id) {
                1 { Stop-Reading }
                2 { Toggle-Pause }
                3 { if ($script:last) { Start-Reading $script:last } }
                4 { $script:copyAt = Get-Date }
            }
        }
        # Wait until Ctrl/Alt are let go before copying, or the copy keystroke gets mixed with them.
        if ($script:copyAt) {
            if (-not [VoiceHotkeys]::ModifiersDown()) { $script:copyAt = $null; Read-Highlighted }
            elseif (((Get-Date) - $script:copyAt).TotalSeconds -gt 3) { $script:copyAt = $null }
        }
        $cs = [VoiceHotkeys]::GetClipboardSequenceNumber()
        if ($cs -ne $script:clipSeq) { if ($script:clipSeq) { $script:clipChangedAt = Get-Date }; $script:clipSeq = $cs }
        Advance
        if ((Get-Date) -ge $script:nextCheck) {
            $script:nextCheck = (Get-Date).AddSeconds(20)
            if (Test-ClaudeCodeRunning) { $script:lastSeenCC = Get-Date }
            elseif ($script:state -eq 'idle' -and ((Get-Date) - $script:lastSeenCC).TotalSeconds -ge 60) {
                Log 'No Claude Code session for a minute; shutting down'
                [System.Windows.Forms.Application]::Exit()
            }
        }
    } catch { Log "tick error: $_" }
})
$timer.Start()
[System.Windows.Forms.Application]::Run()
