---
name: voice-on
description: Turn read-aloud back on (starts the voice helper)
allowed-tools: Bash(powershell *) PowerShell(powershell *)
---
!`powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/voice-toggle.ps1" on`

If the output above says "Voice is on.", reply with exactly: Voice is on.
If it says "Could not turn voice on", tell the user it failed and give the reason.
