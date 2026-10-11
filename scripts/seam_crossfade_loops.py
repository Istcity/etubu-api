#!/usr/bin/env python3
"""Equal-power cosine micro-crossfade for seamless WAV loops (~72 ms).

Reads virgin `.preseam.bak` when present so re-runs do not double-shorten.
Shortens each loop by the fade length so wrap continuity equals natural
adjacent-sample delta (seam jump → ~0 for practical listening).
"""
from __future__ import annotations

import math
import struct
import sys
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOOP_DIRS = [
    ROOT / "public" / "assets" / "audio" / "loops",
    ROOT / "public" / "assets" / "audio" / "loops" / "bands",
]
CROSSFADE_MS = 72.0
MIN_DURATION_S = 0.4


def read_wav(path: Path):
    with wave.open(str(path), "rb") as w:
        nch = w.getnchannels()
        sw = w.getsampwidth()
        rate = w.getframerate()
        nframes = w.getnframes()
        raw = w.readframes(nframes)
    if sw != 2:
        raise ValueError(f"unsupported sample width {sw} in {path}")
    samples = list(struct.unpack("<" + "h" * (nframes * nch), raw))
    return samples, nch, rate


def write_wav(path: Path, samples, nch: int, rate: int) -> None:
    with wave.open(str(path), "wb") as w:
        w.setnchannels(nch)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(struct.pack("<" + "h" * len(samples), *samples))


def process(samples, nch: int, rate: int, ms: float = CROSSFADE_MS):
    frames = len(samples) // nch
    fade = max(128, min(int(rate * (ms / 1000.0)), frames // 6))
    if frames < fade * 4:
        return samples, False
    out_frames = frames - fade
    out = [0] * (out_frames * nch)
    for i in range(fade):
        t = i / max(1, fade - 1)
        w_end = math.cos(t * math.pi * 0.5)
        w_start = math.sin(t * math.pi * 0.5)
        for c in range(nch):
            end_s = samples[(frames - fade + i) * nch + c] / 32768.0
            start_s = samples[i * nch + c] / 32768.0
            mixed = end_s * w_end + start_s * w_start
            out[i * nch + c] = int(max(-32767, min(32767, round(mixed * 32768.0))))
    for i in range(fade, out_frames):
        for c in range(nch):
            out[i * nch + c] = samples[i * nch + c]
    return out, True


def main() -> int:
    n_ok = 0
    for d in LOOP_DIRS:
        if not d.is_dir():
            continue
        for path in sorted(d.glob("*.wav")):
            bak = Path(str(path) + ".preseam.bak")
            if not bak.exists():
                bak.write_bytes(path.read_bytes())
            samples, nch, rate = read_wav(bak)
            if (len(samples) // nch) / rate < MIN_DURATION_S:
                print(f"short {path.name}")
                continue
            out, ok = process(samples, nch, rate)
            if not ok:
                print(f"skip {path.name}")
                continue
            write_wav(path, out, nch, rate)
            n_ok += 1
            print(f"ok {path.name}")
    print(f"done {n_ok} files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
