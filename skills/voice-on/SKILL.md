---
name: voice-on
description: Turn read-aloud back on (starts the voice helper)
allowed-tools: Bash(powershell *) PowerShell(powershell *)
---
!`powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/voice-toggle.ps1" on`

Read-aloud has been turned back on by the command above. Reply with exactly: Voice is on.
