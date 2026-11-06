# Build notes — 2026-11-06

What we built, what we learned, and what's still open. Written for anyone picking this up.

## Timeline

1. **Read-aloud via Stop hook** (existed before): edge-tts Ava, David fallback, Ctrl+Alt+S
   via a Start Menu shortcut hotkey that killed the speaking process.
2. **Background helper** (`claude-voice.ps1`): owns playback via MCI so pause/resume works;
   global hotkeys via `RegisterHotKey`; hooks talk to it through an inbox folder.
3. **Read highlighted (Ctrl+Alt+H).** Gotchas:
   - `SendKeys ^{INSERT}` isn't a copy in Windows Terminal.
   - Claude Code **copies on highlight** itself, so a sent copy keystroke changes nothing.
     Fix: if the clipboard changed in the last 60 s, read it.
   - Plain Ctrl+C in a terminal would interrupt the running program; terminals get Ctrl+Shift+C.
4. **Echo-cancelled mic** (`EchoCancelMic.cs`, Windows Voice Capture DSP, `CWMAudioAEC`,
   SINGLE_CHANNEL_AEC). Test on laptop speakers: the raw mic transcribed every word the
   reader said; the echo-cancelled mic transcribed none of them and still caught the user.
   - The DSP fails after ~4 s with `0x87CC000A` if nothing is playing on the speakers.
     Fix: loop a silent sound for the whole session.
5. **Listener** (`listen.py`): energy-based voice detection, faster-whisper `small.en`
   (`base.en` was ~3x faster but less accurate), SendInput Unicode typing + Enter.
6. **Tuning** from a recording: background noise ~0.0003–0.001 RMS, speech 0.03–0.18.
   Stray noises never had more than 6 loud frames in a 20-frame window; speech had 16–20,
   so the trigger needs 12 of 20.
7. **Incident:** the listener typed the user's speech into a *second* terminal running
   another Claude session, which ran commands. Fix (kept): mic starts off at login,
   Ctrl+Alt+M ties it to the window in front.
8. **Stricter version** (now in `stricter-variant/`), after review: echo check against
   the text being read, window-title lock, Whisper confidence filter, longer end pause,
   higher bar while reading. **Rolled back:** it was safer but noticeably worse to use.
   Interrupting required yelling, and in a noisy room the confidence filter silently
   dropped most of a minute of real speech.

## Adversarial review findings, still open in the mic version

Most severe first.

1. **Self-feedback.** Echo scraps can be transcribed and sent as prompts (seen live: the
   reader said "Hi Frank! …" and the listener sent "Hi, Frank."). Sending a prompt also
   stops the reading. With permission prompts skipped, that text is acted on.
   Ideas: echo check against the reading text (in experimental), require a spoken
   "send" for utterances that started during playback, lower the reader volume while armed.
2. **Enter is sent blindly** into the armed window. Tabs share a window handle, and a
   permission prompt would accept Enter. Ideas: title check (in experimental), abort if
   modifier keys are held.
3. **Whisper hallucinations** from noise get through; the blacklist is short.
   Ideas: `no_speech_prob` / `avg_logprob` filters, tuned so they don't drop real speech in noise.
4. **Process lifecycle.** If the helper dies, the listener keeps typing. Ideas: Job object
   with kill-on-close, the listener exits when its parent is gone.
5. **Multi-session crosstalk.** All sessions share one inbox; hooks ignore `session_id`.
6. **Inbox ordering.** The listener names files with `time_ns()`, hooks use .NET `Ticks`,
   so sorting by name isn't chronological. Use one clock.
7. **Pause ignored before playback starts.** A reply that arrives while the user is
   talking starts reading over them.
8. ~~**`.tmp` race.**~~ Fixed: the reply hook now writes outside the inbox, then moves the file in.
9. **Ctrl+Alt = AltGr** on many layouts. Make hotkeys configurable.
10. **Read-Highlighted** sends Ctrl+C to unknown terminals (VS Code, mintty…), which is a
    SIGINT risk. Non-text clipboard contents get discarded. The 60 s "recent" rule can read stale text.
11. **Portability.** Hardcoded Python 3.13 paths; no installer; first model download is silent;
    `listen.log` stores every utterance with no size limit (privacy).
12. **Noise floor** adapts on any frame below the bar, including speech tails, so the bar
    creeps up during conversation (measured 0.015 → 0.033). Fix in experimental:
    update only on near-silent frames.

Plausible, unverified: Claude Code's own hold-to-talk voice may contend for the mic; a
broken pipe may not stop `EchoCancelMic --stdout`; AGC in the DSP may amplify breathing;
a recycled window handle could re-arm a different window.

## Ideas

- Wake word ("Claude, …") so room conversation is never sent.
- Push-to-talk fallback mode for noisy rooms.
- A proper installer and a Claude Code plugin package.
