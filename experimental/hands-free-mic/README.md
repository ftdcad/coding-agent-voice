# Experimental: hands-free microphone (not working well yet)

An always-on mic for Claude Code: talk over the reader to pause it, stop talking and
your words are transcribed locally and sent. It works sometimes, but on laptop speakers
it is not reliable. **Read `NOTES.md` before trying it.**

## Warnings

- It **presses Enter for you**, and Claude acts on what was typed. It can also answer a
  permission prompt. **Never use it with permission prompts turned off.**
- It sends anything said in the room while the armed window is in front: other people,
  videos, phone calls. Scraps of the reader's own voice have been sent as messages.
- `listen.log` keeps a transcript of everything it heard.
- If the helper dies, Ctrl+Alt+M stops working. Emergency off: kill `pythonw.exe` and
  `EchoCancelMic.exe` in Task Manager.

## Files

| File | What it is |
|---|---|
| `claude-voice-with-mic.ps1` | The main helper plus mic support (Ctrl+Alt+M arms the window in front). Install it **as** `claude-voice.ps1`. |
| `listen.py` | Listener: loudness-based speech detection, faster-whisper `small.en`, types + Enter. |
| `EchoCancelMic.cs` | Records through the Windows Voice Capture DSP echo canceller; streams PCM to stdout. |
| `echo-test.ps1`, `transcribe.py` | Records with and without echo cancelling while the reader talks, then transcribes both. |
| `stricter-variant/` | Echo check, window-title lock, confidence filter. Safer, but worse to use (see NOTES). Both files go together. |

## Setup

`pip install faster-whisper numpy` (plus `edge-tts`). Put `listen.py`, `EchoCancelMic.cs`,
`echo-test.ps1` and `transcribe.py` in `C:\Users\<you>\.claude\voice\`, then compile there:

```
%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe /nologo /optimize /out:EchoCancelMic.exe EchoCancelMic.cs
```

The Whisper `small.en` model (~480 MB) downloads silently on first start.

## Most promising next step

Windows voice typing (Win+H) on the same laptop does **not** pick up the reader's voice
at all. It probably uses the audio driver's own echo cancelling (for example Intel Smart
Sound), which is turned on for "communications" capture streams. Capturing with WASAPI
using `AudioCategory_Communications` instead of the generic Voice Capture DSP might fix
the echo leak, which is the root of most problems in `NOTES.md`. Untested.
