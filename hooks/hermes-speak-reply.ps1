# Hermes Agent post_llm_call hook: reads Hermes's final reply aloud through the same
# voice helper Claude Code and Codex use. Hermes pipes JSON on stdin; the reply is in
# extra.assistant_response (checked with Hermes Agent v0.23.1). Obeys /voice-off.
# Never blocks Hermes: any error is ignored. Setup: see "Hermes Agent" in README.md.
try {
    [Console]::InputEncoding = [Text.UTF8Encoding]::new($false)
    $data = [Console]::In.ReadToEnd() | ConvertFrom-Json
    $text = $null
    foreach ($candidate in @($data.extra.assistant_response, $data.assistant_response)) {
        if ($candidate -is [string] -and $candidate.Trim()) { $text = $candidate; break }
    }
    if (-not $text) { exit 0 }
    $OutputEncoding = [Text.UTF8Encoding]::new($false) # keep dashes and quotes intact
    $speak = Join-Path $PSScriptRoot '..\scripts\speak-response.ps1'
    @{ last_assistant_message = $text } | ConvertTo-Json -Compress | & powershell -NoProfile -ExecutionPolicy Bypass -File $speak
}
catch { }
exit 0
