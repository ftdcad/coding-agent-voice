# Asks the background voice helper (claude-voice.ps1) to stop reading.
# Runs when you send Claude a new message.
$inbox = Join-Path $env:TEMP 'claude-voice\inbox'
New-Item -ItemType Directory -Force $inbox | Out-Null
New-Item -ItemType File -Force (Join-Path $inbox ("{0}.stop" -f [DateTime]::UtcNow.Ticks)) | Out-Null
exit 0
