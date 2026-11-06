# Turns read-aloud on or off. Used by the voice-on and voice-off commands.
#   voice-toggle.ps1 off   stop reading, stop the helper, and keep it off
#   voice-toggle.ps1 on    allow reading again and start the helper
# Prints "Voice is off." / "Voice is on." only when it actually worked; otherwise
# prints "Could not turn voice ..." with the reason and exits with code 1.
param([ValidateSet('on', 'off')][string]$Mode = 'off')

$flag = Join-Path $env:USERPROFILE '.claude\voice-off'

try {
    if ($Mode -eq 'off') {
        New-Item -ItemType Directory -Force (Split-Path $flag) -ErrorAction Stop | Out-Null
        New-Item -ItemType File -Force $flag -ErrorAction Stop | Out-Null
        Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction Stop |
            Where-Object { $_.CommandLine -like '*claude-voice.ps1*' } |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        'Voice is off.'
    } else {
        if (Test-Path $flag) { Remove-Item $flag -Force -ErrorAction Stop }
        & (Join-Path $PSScriptRoot 'start-helper.ps1')
        'Voice is on.'
    }
} catch {
    "Could not turn voice $Mode`: $($_.Exception.Message)"
    exit 1
}
