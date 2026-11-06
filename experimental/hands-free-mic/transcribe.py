import sys, wave
import numpy as np
from faster_whisper import WhisperModel


def load(path):
    with wave.open(path, "rb") as w:
        rate, ch, width = w.getframerate(), w.getnchannels(), w.getsampwidth()
        data = w.readframes(w.getnframes())
    if width == 2:
        a = np.frombuffer(data, np.int16).astype(np.float32) / 32768
    else:
        a = (np.frombuffer(data, np.uint8).astype(np.float32) - 128) / 128
    if ch > 1:
        a = a.reshape(-1, ch).mean(axis=1)
    if rate != 16000:
        n = int(len(a) * 16000 / rate)
        a = np.interp(np.linspace(0, len(a) - 1, n), np.arange(len(a)), a).astype(np.float32)
    return a, rate, width


model = WhisperModel("base.en", device="cpu", compute_type="int8")
for path in sys.argv[1:]:
    audio, rate, width = load(path)
    print(f"=== {path}  ({len(audio)/16000:.1f}s, {rate} Hz, {8*width}-bit, loudness {np.sqrt(np.mean(audio**2)):.4f})")
    segs, _ = model.transcribe(audio, vad_filter=False)
    for s in segs:
        print(f"[{s.start:5.1f}-{s.end:5.1f}] {s.text.strip()}")
