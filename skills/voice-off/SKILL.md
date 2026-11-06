---
name: voice-off
description: Turn off read-aloud (stops the voice helper until /voice-on)
allowed-tools: Bash(powershell *) PowerShell(powershell *)
---
!`powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/voice-toggle.ps1" off`

If the output above says "Voice is off.", reply with exactly: Voice is off. Type /voice-on to turn it back on.
If it says "Could not turn voice off", tell the user it failed and give the reason.
