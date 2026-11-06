# Starts the background voice helper (claude-voice.ps1) if voice isn't turned off
# (/voice-off) and it isn't already running. Used by the SessionStart hook, the
# Stop hook (speak-response.ps1) and /voice-on (voice-toggle.ps1). Prints nothing.
if (Test-Path (Join-Path $env:USERPROFILE '.claude\voice-off')) { exit 0 }
$m = $null
if ([System.Threading.Mutex]::TryOpenExisting('Local\ClaudeVoiceHelper', [ref]$m)) { $m.Dispose(); exit 0 }
$helper = Join-Path $PSScriptRoot 'claude-voice.ps1'
Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @(
    '-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
    '-File', "`"$helper`"")
exit 0
