---
name: voice-off
description: Turn off read-aloud (stops the voice helper until voice-on)
---
Resolve `../../scripts/voice-toggle.ps1` relative to this SKILL.md file in the
installed plugin (not the working directory). Run it with the shell tool:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<resolved-script-path>" off
```

This turns off the shared reader for both Claude Code and Codex.
After the command succeeds, reply: Voice is off. Use voice-on to turn it back on.
If the output says "Could not turn voice", or the command fails or is denied, tell the
user it failed and why; do not claim it worked.
