---
description: Turn off read-aloud (stops the voice helper until /voice-on)
allowed-tools: Bash(powershell:*)
---
!`powershell -NoProfile -ExecutionPolicy Bypass -File "$HOME/.claude/hooks/voice-toggle.ps1" off`

Read-aloud has been turned off by the command above. Reply with exactly: Voice is off. Type /voice-on to turn it back on.
