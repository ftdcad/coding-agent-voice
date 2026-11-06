# Voice add-on for Claude Code (Windows)

Hear Claude Code's replies read aloud, with hotkeys to stop, pause, reread, or read
any highlighted text.

Built by a dyslexic developer who works by voice. It's a small, honest early release:
it works every day for me, it's rough around the edges, and I'd love help making it better.

> Not affiliated with or endorsed by Anthropic. "Claude" and "Claude Code" are Anthropic's names.

## What it does

Every Claude Code reply is read to you in Microsoft's "Ava" neural voice, falling back
to the built-in Windows "David" voice. Code blocks are replaced with "code block
omitted", markdown symbols are stripped, and very long replies stop after about 2,500
characters with "the rest is on screen." Sending your next message stops the current reading.

Hotkeys work from any app:

| Keys | What it does |
|---|---|
| Ctrl+Alt+S | Stop reading |
| Ctrl+Alt+P | Pause / resume |
| Ctrl+Alt+R | Reread the last reply |
| Ctrl+Alt+H | Read whatever text is highlighted |

Slash commands inside Claude Code:

| Command | What it does |
|---|---|
| `/voice-off` | Stop reading and shut the helper down; stays off until `/voice-on` |
| `/voice-on` | Turn read-aloud back on |

The helper is a small hidden PowerShell process. It shuts itself down about a minute
after your last Claude Code session closes, and starts again with the next reply.

For talking *to* Claude, I use Windows voice typing (Win+H) or Claude Code's built-in
voice mode. Both work fine while this reads.

## Privacy: read this

- **Reply text is sent to Microsoft.** The Ava voice comes from
  [`edge-tts`](https://github.com/rany2/edge-tts), an unofficial client for Microsoft
  Edge's online Read Aloud service. Each reply (up to ~2,500 characters) is sent there
  to be turned into audio. It may stop working if Microsoft changes the service.
  Don't want that? Don't install `edge-tts`, and the offline Windows "David" voice is used instead.
- Reply text is briefly written to `%TEMP%\claude-voice\` while it's being read, then deleted.

## Requirements

- Windows 10 or 11, Claude Code
- Optional, for the Ava voice: Python 3.13 at `%LOCALAPPDATA%\Programs\Python\Python313`
  and `pip install edge-tts`. Without it, the David voice is used.

## Install (manual, for now)

1. Copy the four files in `src/hooks/` to `C:\Users\<you>\.claude\hooks\`, and the two
   files in `src/commands/` to `C:\Users\<you>\.claude\commands\`.
2. Add the hooks to `C:\Users\<you>\.claude\settings.json`, using your real path:
   ```json
   "hooks": {
     "UserPromptSubmit": [{ "hooks": [{ "type": "command", "timeout": 10,
       "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"C:\\Users\\<you>\\.claude\\hooks\\stop-speaking.ps1\"" }] }],
     "Stop": [{ "hooks": [{ "type": "command", "async": true, "timeout": 300,
       "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"C:\\Users\\<you>\\.claude\\hooks\\speak-response.ps1\"" }] }]
   }
   ```
3. Optional: so the hotkeys work right after login, put a shortcut in your Startup
   folder (`Win+R`, `shell:startup`) that runs:
   `powershell -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Users\<you>\.claude\hooks\claude-voice.ps1"`.
   Otherwise the helper starts with the first reply.

## Uninstall / turn it off

To pause it for a while, just type `/voice-off`. To remove it completely:

1. Type `/voice-off`, then remove the two hook entries from `settings.json`.
2. Delete the four files from `.claude\hooks\`, the two from `.claude\commands\`, the
   `.claude\voice-off` file, the Startup shortcut if you made one, and the
   `%TEMP%\claude-voice` folder.

## Known shortcomings

- **Ctrl+Alt+letter is AltGr** on many non-US keyboards, so these hotkeys can block
  typing some characters. They aren't configurable yet.
- **Ctrl+Alt+H** copies the highlighted text. Windows Terminal, the classic console
  (cmd / PowerShell / conhost), WezTerm and Alacritty get Ctrl+Shift+C; every other app
  gets Ctrl+C. In other terminals (VS Code, mintty…), Ctrl+C with nothing selected can
  interrupt what's running. In apps that copy on
  highlight (Claude Code does), it reads whatever was copied in the last minute.
  It also replaces non-text clipboard contents (like an image).
- **One reader for all sessions.** Every Claude Code session on the PC feeds the same
  reader, so a reply from another window replaces the one you're hearing.
- Windows only, and install is manual.

## How it works

```
Claude Code ──Stop hook──────▶ speak-response.ps1 ──.say──▶ %TEMP%\claude-voice\inbox
            ──Prompt hook────▶ stop-speaking.ps1  ──.stop─▶            │
                                                                      ▼
                  claude-voice.ps1 (background: hotkeys, edge-tts, playback)

/voice-off, /voice-on ──▶ voice-toggle.ps1 (creates/removes .claude\voice-off, stops/starts the helper)
```

Logs: `%TEMP%\claude-voice\voice.log`.

## Experimental: hands-free microphone

`experimental/hands-free-mic/` has an always-on, echo-cancelled mic that types what you
say into Claude Code, and lets you talk over the reader to interrupt it. **It doesn't
work well enough yet**: echo leaks, room noise, and false messages. Its notes explain
what we tried and what's left. If voice activity detection or echo cancellation is your
thing, that's the best place to help.

## Thanks

[edge-tts](https://github.com/rany2/edge-tts) and the Windows speech APIs. The
experimental mic also uses [faster-whisper](https://github.com/SYSTRAN/faster-whisper)
with OpenAI's Whisper models, and the Windows Voice Capture DSP.

## License

MIT, see `LICENSE`. Use it, change it, ship it; just keep the copyright notice.
