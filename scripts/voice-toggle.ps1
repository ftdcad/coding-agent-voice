# Turns read-aloud on or off. Used by the /voice-on and /voice-off commands.
#   voice-toggle.ps1 off   stop reading, stop the helper, and keep it off
#   voice-toggle.ps1 on    allow reading again and start the helper
param([ValidateSet('on', 'off')][string]$Mode = 'off')

$flag = Join-Path $env:USERPROFILE '.claude\voice-off'

if ($Mode -eq 'off') {
    New-Item -ItemType File -Force $flag | Out-Null
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
        Where-Object { $_.CommandLine -like '*claude-voice.ps1*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    'Voice is off.'
} else {
    Remove-Item $flag -Force -ErrorAction SilentlyContinue
    & (Join-Path $PSScriptRoot 'start-helper.ps1')
    'Voice is on.'
}
