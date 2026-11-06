"""Claude Voice listener: always-on, hands-free dictation into Claude Code.

- Records the mic through Windows' echo canceller (EchoCancelMic.exe), so
  Claude's own voice from the speakers is filtered out.
- Only listens while the one window you turned it on in (Ctrl+Alt+M) is in
  front. Other terminals are ignored. Tabs inside that window share it.
- When you start talking, it pauses any reply being read aloud. If what you
  said turns out to be noise, or "resume / keep reading", reading picks back up.
  "Stop reading" stops it. Anything else is sent as a message.
- After ~1.8 seconds of quiet, it transcribes what you said (locally, with
  faster-whisper) and types it into the Claude window, then presses Enter.
- Ctrl+Alt+M (handled by claude-voice.ps1) creates/removes the mute flag file;
  while muted the microphone is fully released.
"""
import ctypes
import ctypes.wintypes as wt
import os
import re
import subprocess
import sys
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
START_FRAMES = 12            # ...and need 12 loud ones (~360 ms of sustained sound).
                             # Measured: stray noises peak at 6, real speech 16-20.
# While Claude is reading, faint echo scraps leak past the echo canceller,
# so it takes a clearly louder, longer sound to interrupt.
READING_MIN_LEVEL = 0.02     # 0.03 needed yelling (2026-11-06)
READING_START_FRAMES = 13
READING_FLAG = os.path.join(STATE, "reading")      # exists while the helper is reading
READING_TEXT = os.path.join(STATE, "reading.txt")  # what the helper is (or was last) reading
ECHO_GRACE = 6.0             # seconds after reading stops that echo can still be in the buffer
END_SILENCE = 100            # quiet frames that end an utterance (~3 s, room to pause and think)
MIN_SPEECH_FRAMES = 15       # ignore blips shorter than ~0.45 s of speech
MAX_SECONDS = 90             # hard cap on one utterance
PREROLL = 25                 # keep ~0.45 s before speech starts so first word isn't clipped

MODEL = "small.en"

# Spoken commands that control reading instead of being sent to Claude.
RESUME_RE = re.compile(r"^(ok(ay)?,? )?(please |can you |could you )?(resume|receive|re-?zoom|keep (reading|going)|continue|go on|carry on|go ahead)( reading| please)?[.!?]*$", re.I)
STOP_RE = re.compile(r"^(ok(ay)?,? )?(please |can you |could you )?(stop|stop reading|stop talking|be quiet|quiet|shut up)( please)?[.!?]*$", re.I)

# Phrases Whisper tends to invent from noise.
JUNK = {"", "you", "thank you", "thank you.", "thanks for watching", "thanks for watching!",
        "bye", "bye.", "you.", ".", "okay.", "uh", "um", "hmm"}

user32 = ctypes.WinDLL("user32", use_last_error=True)
kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
user32.GetForegroundWindow.restype = ctypes.c_void_p


def log(msg):
    try:
        with open(LOG, "a", encoding="utf-8") as f:
            f.write(time.strftime("%Y-%m-%d %H:%M:%S ") + msg + "\n")
    except OSError:
        pass


def foreground_app():
    hwnd = user32.GetForegroundWindow()
    pid = wt.DWORD()
    user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
    h = kernel32.OpenProcess(0x1000, False, pid.value)  # QUERY_LIMITED_INFORMATION
    if not h:
        return "", hwnd
    try:
        buf = ctypes.create_unicode_buffer(1024)
        size = wt.DWORD(1024)
        kernel32.QueryFullProcessImageNameW(h, 0, buf, ctypes.byref(size))
        return os.path.basename(buf.value).lower(), hwnd
    finally:
        kernel32.CloseHandle(h)


_target = {"mtime": None, "hwnd": None, "title": None}


def target_window():
    try:
        m = os.path.getmtime(TARGET_FILE)
    except OSError:
        return None
    if m != _target["mtime"]:
        try:
            with open(TARGET_FILE, encoding="utf-8-sig") as f:
                _target["hwnd"] = int(f.read().strip())
            # Remember the title showing right when the mic was turned on.
            _target["title"] = window_title(_target["hwnd"])
            log(f"armed for window titled {_target['title']!r}")
        except (OSError, ValueError):
            _target["hwnd"] = None
        _target["mtime"] = m
    return _target["hwnd"]


def window_title(hwnd):
    buf = ctypes.create_unicode_buffer(512)
    user32.GetWindowTextW(ctypes.c_void_p(hwnd), buf, 512)
    # Claude Code puts a spinner symbol in front of the topic; ignore it.
    return re.sub(r"^\W+", "", buf.value).strip()


def claude_in_front():
    target = target_window()
    return target is not None and user32.GetForegroundWindow() == target


def armed_title_matches():
    """The window's title (Claude Code's conversation topic) must still be the one
    showing when the mic was turned on, so another tab or session never gets typed into."""
    target = target_window()
    if target is None or user32.GetForegroundWindow() != target:
        return False
    return window_title(target) == _target.get("title")


def modifiers_released(timeout=2.0):
    end = time.time() + timeout
    while time.time() < end:
        if not any(user32.GetAsyncKeyState(k) & 0x8000 for k in (0x10, 0x11, 0x12, 0x5B, 0x5C)):
            return True
        time.sleep(0.05)
    return False


def words(text):
    return re.findall(r"[a-z0-9']+", text.lower())


def is_echo(heard, reading_text):
    """True if what was heard is mostly Claude's own words coming back through the mic."""
    h, r = words(heard), words(reading_text)
    if not h or not r:
        return False
    rset = set(r)
    if len(h) <= 3:
        return all(w in rset for w in h)
    rbig = set(zip(r, r[1:]))
    hbig = list(zip(h, h[1:]))
    return sum(b in rbig for b in hbig) / len(hbig) >= 0.5


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
    levels = deque(maxlen=START_WINDOW)   # for logging how loud triggers / near-misses were
    last_near_log = 0.0
    preroll = deque(maxlen=PREROLL)
    speaking = False
    utter, quiet, loud_count = [], 0, 0
    last_reading = 0.0          # last time the helper was reading
    started_near_reading = False

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
            recent.clear(); preroll.clear(); levels.clear()
            continue

        reading = os.path.exists(READING_FLAG)
        if reading:
            last_reading = time.time()
        min_level = READING_MIN_LEVEL if reading else MIN_LEVEL
        start_frames = READING_START_FRAMES if reading else START_FRAMES
        bar = max(min_level, min(noise * 4, 0.04))
        is_loud = level > bar
        if level < MIN_LEVEL * 0.5:
            # Only near-silent frames update the room-noise estimate; quiet tails of
            # speech used to push the bar up until you had to yell.
            noise = noise * 0.995 + level * 0.005

        if not speaking:
            preroll.append(frame)
            recent.append(is_loud)
            levels.append(level)
            # Log sounds that got halfway to triggering, so thresholds can be tuned from real numbers.
            if sum(recent) >= start_frames // 2 and sum(recent) < start_frames and time.time() - last_near_log > 2:
                last_near_log = time.time()
                log(f"near miss: {sum(recent)}/{START_WINDOW} loud frames (needed {start_frames}), "
                    f"peak {max(levels):.3f}, median {sorted(levels)[len(levels)//2]:.3f}, "
                    f"bar {bar:.3f}, reading={reading}")
            if sum(recent) >= start_frames:
                speaking = True
                started_near_reading = time.time() - last_reading < ECHO_GRACE
                log(f"triggered: {sum(recent)}/{START_WINDOW} loud frames, peak {max(levels):.3f}, "
                    f"median {sorted(levels)[len(levels)//2]:.3f}, bar {bar:.3f}, reading={reading}")
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
        segs, _ = model.transcribe(audio, language="en", vad_filter=True, beam_size=5,
                                   condition_on_previous_text=False)
        # Drop pieces Whisper itself thinks are not speech (it invents "Thank you." from noise).
        kept = [s for s in segs if s.no_speech_prob < 0.6 and s.avg_logprob > -1.0]
        text = " ".join(s.text.strip() for s in kept).strip()
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
        if started_near_reading or time.time() - last_reading < ECHO_GRACE:
            try:
                with open(READING_TEXT, encoding="utf-8-sig") as f:
                    reading_text = f.read()
            except OSError:
                reading_text = ""
            if is_echo(text, reading_text):
                log("ignored: matches what Claude was reading (echo)")
                tell_helper("resume")
                continue
        if not modifiers_released() or not armed_title_matches():
            log(f"not typing: window/title changed (now {window_title(user32.GetForegroundWindow() or 0)!r}) or keys held")
            tell_helper("resume")
            continue
        type_text(text)
        time.sleep(0.3)
        if modifiers_released() and armed_title_matches():
            press_enter()
        else:
            log("typed but did not press Enter: window/title changed or keys held")


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
