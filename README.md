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

(Their full names are `/voice:voice-off` and `/voice:voice-on`; the short forms work
unless another command already uses the name.)

The helper is a small hidden PowerShell process. It starts when you open a Claude Code
session, so the hotkeys work right away, and shuts itself down about a minute after your
last Claude Code session closes.

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

- Windows 10 or 11, and a recent Claude Code (plugins; tested on 2.1.319)
- Optional, for the Ava voice: Python 3 with `pip install edge-tts`. The helper looks
  for Python in this order and uses the first one where `import edge_tts` works:
  the python.org install at `%LOCALAPPDATA%\Programs\Python\Python313`, the `py -3`
  launcher, then `python` on PATH. Without it, the David voice is used.

## Install

Inside Claude Code, type these two commands:

```
/plugin marketplace add ftdcad/claude-code-voice
/plugin install voice@claude-code-voice
```

The second one opens the plugin's details; pick **Install for you (user scope)**. If it
says to run `/reload-plugins`, do that (or just start a new session). The next reply is
read aloud.

On Claude Code 2.1.275 or later this one line does both steps:
`/plugin install voice --marketplace ftdcad/claude-code-voice`.

From a terminal instead: `claude plugin marketplace add ftdcad/claude-code-voice` then
`claude plugin install voice@claude-code-voice`.

### Upgrading from the manual install

If you installed an earlier version by hand, remove it first, or every reply is read twice:

1. In `C:\Users\<you>\.claude\settings.json`, delete the `UserPromptSubmit` and `Stop`
   hook entries that run `stop-speaking.ps1` and `speak-response.ps1`.
2. Delete `claude-voice.ps1`, `speak-response.ps1`, `stop-speaking.ps1` and
   `voice-toggle.ps1` from `C:\Users\<you>\.claude\hooks\`, and `voice-off.md` and
   `voice-on.md` from `C:\Users\<you>\.claude\commands\`.
3. If you made a Startup shortcut for `claude-voice.ps1`, delete it.

Then install the plugin as above and start a new session. If the old helper is still
running, `/voice-off` then `/voice-on` switches to the new one.

### Update

Updates aren't automatic for this marketplace. In Claude Code, run `/plugin`, open the
**Marketplaces** tab, select `claude-code-voice` and choose **Update marketplace**; or
from a terminal run `claude plugin update voice@claude-code-voice`. Then `/reload-plugins`
or start a new session.

### Uninstall / turn it off

To pause it for a while, just type `/voice-off`. To remove it completely:

1. Type `/plugin uninstall voice@claude-code-voice` (or `/plugin marketplace remove claude-code-voice`,
   which removes the marketplace and the plugin together).
2. The helper exits on its own about a minute after your last session closes. Optionally
   delete `C:\Users\<you>\.claude\voice-off` (if you ever used `/voice-off`) and the
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
- **Python from the Microsoft Store isn't detected** (its `python` lives behind the
  Store's launcher stub, which the helper skips). Use the python.org installer.
- Windows only.

## How it works

```
Claude Code ──SessionStart hook─▶ start-helper.ps1 ─────────────────────┐
            ──Stop hook─────────▶ speak-response.ps1 ──.say──▶ %TEMP%\claude-voice\inbox
            ──Prompt hook───────▶ stop-speaking.ps1  ──.stop─▶            │
                                                                         ▼
                     claude-voice.ps1 (background: hotkeys, edge-tts, playback)

/voice-off, /voice-on ──▶ voice-toggle.ps1 (creates/removes .claude\voice-off, stops/starts the helper)
```

The hooks are declared in `hooks/hooks.json`, the slash commands in `skills/`, and the
scripts live in `scripts/`; Claude Code runs them from the plugin's install folder.

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
