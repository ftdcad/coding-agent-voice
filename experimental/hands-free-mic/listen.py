"""Hands-free listener: always-on dictation into Claude Code.

- Records the mic through Windows' echo canceller (EchoCancelMic.exe), so
  Claude's own voice from the speakers is mostly filtered out.
- Only listens while the one window you turned it on in (Ctrl+Alt+M) is in
  front. Other windows are ignored. Tabs inside that window share it.
- When you start talking, it pauses any reply being read aloud. If what you
  said turns out to be noise, or "resume / keep reading", reading picks back up.
  "Stop reading" stops it. Anything else is sent as a message.
- After ~1.8 seconds of quiet, it transcribes what you said (locally, with
  faster-whisper) and types it into the window, then presses Enter.
- Ctrl+Alt+M (handled by claude-voice.ps1) arms it for the window in front or
  turns it off; while off the microphone is fully released.
"""
import ctypes
import ctypes.wintypes as wt
import os
import re
import subprocess
import time
from collections import deque

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
STATE = os.path.join(os.environ["TEMP"], "claude-voice")
INBOX = os.path.join(STATE, "inbox")
MUTE_FLAG = os.path.join(STATE, "mic-muted")
TARGET_FILE = os.path.join(STATE, "mic-target")   # window handle chosen with Ctrl+Alt+M
LOG = os.path.join(STATE, "listen.log")
MIC_EXE = os.path.join(HERE, "EchoCancelMic.exe")

RATE = 16000
FRAME = 480                  # 30 ms
MIN_LEVEL = 0.015            # quietest frame that can count as speech
START_WINDOW = 20            # look at the last 20 frames (600 ms)...
START_FRAMES = 12            # ...and need 12 loud ones (~360 ms of sustained sound)
END_SILENCE = 60             # quiet frames that end an utterance (~1.8 s)
MIN_SPEECH_FRAMES = 15       # ignore blips shorter than ~0.45 s of speech
MAX_SECONDS = 90             # hard cap on one utterance
PREROLL = 25                 # keep ~0.75 s before speech starts so the first word isn't clipped

MODEL = "small.en"

# Spoken commands that control reading instead of being sent to Claude.
RESUME_RE = re.compile(r"^(ok(ay)?,? )?(please |can you |could you )?(resume|receive|re-?zoom|keep (reading|going)|continue|go on|carry on|go ahead)( reading| please)?[.!?]*$", re.I)
STOP_RE = re.compile(r"^(ok(ay)?,? )?(please |can you |could you )?(stop|stop reading|stop talking|be quiet|quiet|shut up)( please)?[.!?]*$", re.I)

# Phrases Whisper tends to invent from noise.
JUNK = {"", "you", "thank you", "thank you.", "thanks for watching", "thanks for watching!",
        "bye", "bye.", "you.", ".", "okay.", "uh", "um", "hmm"}

user32 = ctypes.WinDLL("user32", use_last_error=True)
user32.GetForegroundWindow.restype = ctypes.c_void_p


def log(msg):
    try:
        with open(LOG, "a", encoding="utf-8") as f:
            f.write(time.strftime("%Y-%m-%d %H:%M:%S ") + msg + "\n")
    except OSError:
        pass


_target = {"mtime": None, "hwnd": None}


def target_window():
    try:
        m = os.path.getmtime(TARGET_FILE)
    except OSError:
        return None
    if m != _target["mtime"]:
        try:
            with open(TARGET_FILE, encoding="utf-8-sig") as f:
                _target["hwnd"] = int(f.read().strip())
        except (OSError, ValueError):
            _target["hwnd"] = None
        _target["mtime"] = m
    return _target["hwnd"]


def claude_in_front():
    target = target_window()
    return target is not None and user32.GetForegroundWindow() == target


# ---- typing into the window ----
class KEYBDINPUT(ctypes.Structure):
    _fields_ = [("wVk", wt.WORD), ("wScan", wt.WORD), ("dwFlags", wt.DWORD),
                ("time", wt.DWORD), ("dwExtraInfo", ctypes.c_size_t)]


class INPUT(ctypes.Structure):
    class _U(ctypes.Union):
        _fields_ = [("ki", KEYBDINPUT), ("pad", ctypes.c_byte * 32)]
    _anonymous_ = ("u",)
    _fields_ = [("type", wt.DWORD), ("u", _U)]


def _send(inputs):
    arr = (INPUT * len(inputs))(*inputs)
    user32.SendInput(len(inputs), arr, ctypes.sizeof(INPUT))


def type_text(text):
    KEYEVENTF_UNICODE, KEYUP = 0x0004, 0x0002
    inputs = []
    for ch in text:
        code = ord(ch)
        units = [code] if code < 0x10000 else [0xD800 + ((code - 0x10000) >> 10), 0xDC00 + ((code - 0x10000) & 0x3FF)]
        for u in units:
            inputs.append(INPUT(type=1, ki=KEYBDINPUT(0, u, KEYEVENTF_UNICODE, 0, 0)))
            inputs.append(INPUT(type=1, ki=KEYBDINPUT(0, u, KEYEVENTF_UNICODE | KEYUP, 0, 0)))
    for i in range(0, len(inputs), 200):
        _send(inputs[i:i + 200])
        time.sleep(0.01)


def press_enter():
    _send([INPUT(type=1, ki=KEYBDINPUT(0x0D, 0, 0, 0, 0)),
           INPUT(type=1, ki=KEYBDINPUT(0x0D, 0, 0x0002, 0, 0))])


def tell_helper(cmd):  # cmd: "pause", "resume" or "stop"
    try:
        os.makedirs(INBOX, exist_ok=True)
        open(os.path.join(INBOX, f"{time.time_ns()}.{cmd}"), "w").close()
    except OSError:
        pass


# ---- main loop ----
def start_mic():
    return subprocess.Popen([MIC_EXE, "--stdout"], stdout=subprocess.PIPE,
                            creationflags=0x08000000)  # CREATE_NO_WINDOW


def main():
    os.makedirs(STATE, exist_ok=True)
    from faster_whisper import WhisperModel
    model = WhisperModel(MODEL, device="cpu", compute_type="int8")
    log("listener started")

    mic = None
    noise = 0.001
    recent = deque(maxlen=START_WINDOW)
    preroll = deque(maxlen=PREROLL)
    speaking = False
    utter, quiet, loud_count = [], 0, 0

    while True:
        if os.path.exists(MUTE_FLAG) or not os.path.exists(TARGET_FILE):
            if mic:
                mic.kill(); mic = None
                log("muted, mic released")
            speaking, utter = False, []
            time.sleep(0.3)
            continue
        if mic is None or mic.poll() is not None:
            mic = start_mic()
            log("mic opened")

        raw = mic.stdout.read(FRAME * 2)
        if len(raw) < FRAME * 2:
            mic.kill(); mic = None
            time.sleep(1)
            continue
        frame = np.frombuffer(raw, np.int16).astype(np.float32) / 32768
        level = float(np.sqrt(np.mean(frame ** 2)))

        if not claude_in_front():
            if speaking:
                tell_helper("resume")
            speaking, utter = False, []
            recent.clear(); preroll.clear()
            continue

        is_loud = level > max(MIN_LEVEL, noise * 8)
        if not is_loud:
            noise = noise * 0.995 + level * 0.005  # slowly track the room's background noise

        if not speaking:
            preroll.append(frame)
            recent.append(is_loud)
            if sum(recent) >= START_FRAMES:
                speaking = True
                utter, quiet, loud_count = list(preroll), 0, sum(recent)
                tell_helper("pause")  # talking over Claude pauses the reading
            continue

        utter.append(frame)
        if is_loud:
            quiet = 0; loud_count += 1
        else:
            quiet += 1
        if quiet < END_SILENCE and len(utter) * FRAME < MAX_SECONDS * RATE:
            continue

        # Utterance finished.
        speaking = False
        recent.clear(); preroll.clear()
        if loud_count < MIN_SPEECH_FRAMES:
            tell_helper("resume")
            continue
        audio = np.concatenate(utter)
        t0 = time.time()
        segs, _ = model.transcribe(audio, language="en", vad_filter=False, beam_size=5,
                                   condition_on_previous_text=False)
        text = " ".join(s.text.strip() for s in segs).strip()
        log(f"heard ({len(audio)/RATE:.1f}s audio, {time.time()-t0:.1f}s to transcribe): {text!r}")
        if text.lower() in JUNK or len(text) < 2:
            tell_helper("resume")
            continue
        if RESUME_RE.match(text):
            tell_helper("resume")
            continue
        if STOP_RE.match(text):
            tell_helper("stop")
            continue
        if not claude_in_front():
            log("window no longer in front; not typing")
            tell_helper("resume")
            continue
        type_text(text)
        time.sleep(0.3)
        press_enter()


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # keep a record; claude-voice.ps1 restarts us
        log(f"crashed: {e!r}")
        raise
    finally:
        # Never leave the mic recorder running if we die.
        subprocess.run(["taskkill", "/F", "/IM", "EchoCancelMic.exe"], capture_output=True,
                       creationflags=0x08000000)
