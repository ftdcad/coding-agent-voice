---
name: voice-on
description: Turn read-aloud back on (starts the voice helper)
---
Resolve `../../scripts/voice-toggle.ps1` relative to this SKILL.md file in the
installed plugin (not the working directory). Run it with the shell tool:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<resolved-script-path>" on
```

After the command succeeds, reply: Voice is on.
If the output says "Could not turn voice", or the command fails or is denied, tell the
user it failed and why; do not claim it worked.
