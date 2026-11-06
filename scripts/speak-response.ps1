# Stop hook: hands Claude's last reply to the background voice helper
# (claude-voice.ps1), starting the helper if it isn't running.
# Hook JSON arrives on stdin. Does nothing while voice is off (/voice-off).
param([switch]$JsonOutput)

# Codex Stop hooks expect JSON on stdout. Claude keeps its existing silent behavior.
if ($JsonOutput) { Write-Output '{}' }
if (Test-Path (Join-Path $env:USERPROFILE '.claude\voice-off')) { exit 0 }
try {
    [Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
    $raw = [Console]::In.ReadToEnd()
    $data = $raw | ConvertFrom-Json

    $text = $null
    if ($data.PSObject.Properties.Name -contains 'last_assistant_message' -and $data.last_assistant_message) {
        $text = [string]$data.last_assistant_message
    }
    elseif ($data.transcript_path -and (Test-Path $data.transcript_path)) {
        $lines = @(Get-Content -LiteralPath $data.transcript_path -Encoding UTF8)
        for ($i = $lines.Count - 1; $i -ge 0 -and -not $text; $i--) {
            try { $entry = $lines[$i] | ConvertFrom-Json } catch { continue }
            if ($entry.type -ne 'assistant' -or -not $entry.message) { continue }
            $parts = @($entry.message.content | Where-Object { $_.type -eq 'text' } | ForEach-Object { $_.text })
            if ($parts.Count -gt 0) { $text = $parts -join "`n" }
        }
    }
    if (-not $text) { exit 0 }

    $inbox = Join-Path $env:TEMP 'claude-voice\inbox'
    New-Item -ItemType Directory -Force $inbox | Out-Null
    # Write outside the inbox, then move in, so the helper never sees a half-written file.
    $name = [DateTime]::UtcNow.Ticks
    $tmp = Join-Path (Split-Path $inbox) "$name.tmp"
    [IO.File]::WriteAllText($tmp, $text, [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tmp -Destination (Join-Path $inbox "$name.say")

    & (Join-Path $PSScriptRoot 'start-helper.ps1')
}
catch { }
exit 0
