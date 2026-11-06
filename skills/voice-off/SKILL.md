---
name: voice-off
description: Turn off read-aloud (stops the voice helper until /voice-on)
allowed-tools: Bash(powershell *) PowerShell(powershell *)
---
!`powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/voice-toggle.ps1" off`

Read-aloud has been turned off by the command above. Reply with exactly: Voice is off. Type /voice-on to turn it back on.
