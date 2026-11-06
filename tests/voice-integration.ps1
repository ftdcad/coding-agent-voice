# Isolated integration checks: no audio, global hotkeys, or user config changes.
$ErrorActionPreference = 'Stop'
$OutputEncoding = [Text.UTF8Encoding]::new($false)
$root = Split-Path $PSScriptRoot
$sandbox = Join-Path ([IO.Path]::GetTempPath()) ('voice-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $sandbox | Out-Null
$originalProfile = $env:USERPROFILE
$originalTemp = $env:TEMP
function Assert($condition, [string]$message) {
    if (-not $condition) { throw $message }
}
try {
    $env:USERPROFILE = Join-Path $sandbox 'user'
    $env:TEMP = Join-Path $sandbox 'temp'
    New-Item -ItemType Directory $env:USERPROFILE, $env:TEMP | Out-Null
    Copy-Item (Join-Path $root 'scripts') $sandbox -Recurse
    $scripts = Join-Path $sandbox 'scripts'
    # Stub only the background launcher; exercise real reply extraction and inbox writes.
    Set-Content (Join-Path $scripts 'start-helper.ps1') 'exit 0'
    $speak = Join-Path $scripts 'speak-response.ps1'
    $inbox = Join-Path $env:TEMP 'claude-voice\inbox'
    $reply = "Codex says: caf$([char]0xe9), with a quoted `"path`"."
    $payload = @{ last_assistant_message = $reply; hook_event_name = 'Stop' } | ConvertTo-Json -Compress
    $output = $payload | & powershell.exe -NoProfile -File $speak -JsonOutput
    Assert ($LASTEXITCODE -eq 0) 'Codex Stop failed'
    Assert (($output | ConvertFrom-Json) -is [pscustomobject]) 'Codex Stop must return JSON'
    $files = @(Get-ChildItem $inbox -Filter '*.say')
    Assert ($files.Count -eq 1) 'Codex reply was not queued exactly once'
    Assert ((Get-Content $files[0].FullName -Raw -Encoding UTF8) -eq $reply) 'Unicode reply text changed'
    Remove-Item $files[0].FullName

    $output = $payload | & powershell.exe -NoProfile -File $speak
    Assert (-not $output) 'Claude hook should stay silent'
    Assert (@(Get-ChildItem $inbox -Filter '*.say').Count -eq 1) 'Claude reply was not queued'
    Get-ChildItem $inbox -Filter '*.say' | Remove-Item

    $transcript = Join-Path $sandbox 'transcript.jsonl'
    @{ type = 'assistant'; message = @{ content = @(@{type='text'; text='Transcript reply'}) } } | ConvertTo-Json -Depth 5 -Compress | Set-Content $transcript
    @{transcript_path=$transcript} | ConvertTo-Json -Compress | & powershell.exe -NoProfile -File $speak
    $files = @(Get-ChildItem $inbox -Filter '*.say')
    Assert ($files.Count -eq 1) 'Claude transcript fallback failed'
    Assert ((Get-Content $files[0].FullName -Raw) -eq 'Transcript reply') 'Wrong transcript reply'
    Remove-Item $files[0].FullName

    foreach ($invalid in @('not JSON', '{}', '{"last_assistant_message":""}')) {
        $invalid | & powershell.exe -NoProfile -File $speak -JsonOutput | Out-Null
    }
    Assert (@(Get-ChildItem $inbox -Filter '*.say').Count -eq 0) 'Empty or malformed input queued speech'

    # Prevent the toggle from touching real helper processes.
    function Get-CimInstance { @() }
    & (Join-Path $scripts 'voice-toggle.ps1') off | Out-Null
    Assert (Test-Path (Join-Path $env:USERPROFILE '.claude\voice-off')) 'Off flag missing for Codex-only user'
    $payload | & powershell.exe -NoProfile -File $speak -JsonOutput | Out-Null
    Assert (@(Get-ChildItem $inbox -Filter '*.say').Count -eq 0) 'Off flag did not suppress speech'
    & (Join-Path $scripts 'voice-toggle.ps1') on | Out-Null
    Assert (-not (Test-Path (Join-Path $env:USERPROFILE '.claude\voice-off'))) 'On did not remove flag'
    & (Join-Path $scripts 'stop-speaking.ps1')
    Assert (@(Get-ChildItem $inbox -Filter '*.stop').Count -eq 1) 'Prompt did not queue stop'

    # Load just the process-detection function, without starting the GUI helper.
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'scripts/claude-voice.ps1'), [ref]$tokens, [ref]$errors)
    $fn = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Test-VoiceClientRunning' }, $true)
    Invoke-Expression $fn.Extent.Text
    foreach ($process in @(
        @{Name='codex.exe'},
        @{Name='node.exe'; CommandLine='node C:\npm\node_modules\@openai\codex\bin\codex.js'},
        @{Name='claude.exe'; ExecutablePath='C:\bin\claude.exe'}
    )) {
        $script:mockProcess = [pscustomobject]$process
        function Get-CimInstance { $script:mockProcess }
        Assert (Test-VoiceClientRunning) "Client not detected: $($process.Name)"
    }
    $script:mockProcess = [pscustomobject]@{Name='node.exe'; CommandLine='node other-app.js'}
    Assert (-not (Test-VoiceClientRunning)) 'Unrelated Node process kept helper alive'
    'Voice integration checks passed.'
} finally {
    $env:USERPROFILE = $originalProfile
    $env:TEMP = $originalTemp
    # Delete only the unique, absolute test directory created above.
    if ([IO.Path]::GetFileName($sandbox) -like 'voice-test-*' -and [IO.Path]::IsPathRooted($sandbox)) {
        Remove-Item -LiteralPath $sandbox -Recurse -Force
    }
}
