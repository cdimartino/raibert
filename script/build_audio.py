#!/usr/bin/env python3
"""Render Rai*bert's original ambient score and soft cues, using only Python stdlib."""

from array import array
from functools import lru_cache
from math import cos, exp, pi, sin, sqrt
from pathlib import Path
import re
import sys
import wave

ROOT = Path(__file__).resolve().parents[1]
RATE = 22050


@lru_cache(maxsize=128)
def tone(midi, duration, gain, attack=0.012, pad=False, slide=0):
    frequency = 440 * 2 ** ((midi - 69) / 12)
    count = round(duration * RATE)
    samples = array("f")
    for i in range(count):
        t = i / RATE
        phase = 2 * pi * frequency * (t + slide * t * t / (2 * duration))
        if pad:
            envelope = sin(pi * t / duration) ** 2
            value = sin(phase) + 0.12 * sin(2 * phase)
        else:
            envelope = (1 - exp(-t / attack)) * exp(-5 * t / duration)
            envelope *= min(1, (count - 1 - i) / (RATE * 0.035))
            # A rounded mallet transient, with upper partials dying away first.
            value = sin(phase + 0.35 * sin(2 * phase) * exp(-t * 35))
            value += 0.16 * sin(3 * phase) * exp(-t * 18)
        samples.append(gain * envelope * value)
    return samples


def mix(output, samples, start, gain=1, wrap=False):
    offset = round(start * RATE)
    for i, value in enumerate(samples):
        index = offset + i
        if wrap:
            index %= len(output)
        if 0 <= index < len(output):
            output[index] += value * gain


def write(path, channels):
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = array("h")
    peak = max(abs(value) for channel in channels for value in channel)
    assert 0 < peak < 0.85, f"Unexpected headroom: {path}: {peak}"
    for frame in zip(*channels):
        pcm.extend(round(value * 32767) for value in frame)
    if sys.byteorder != "little":
        pcm.byteswap()
    with wave.open(str(path), "wb") as output:
        output.setparams((len(channels), 2, RATE, 0, "NONE", "not compressed"))
        output.writeframes(pcm.tobytes())


def music(index):
    # 60 BPM, eight bars. Dmaj9 / Bm7 / Gmaj9 / Asus: no drums or busy ostinato.
    channels = [array("f", [0]) * (RATE * 32) for _ in range(2)]
    chords = [(50, 57, 61, 64), (47, 54, 57, 62), (43, 54, 57, 62), (45, 52, 57, 62)]
    motifs = [(74, 69, 66, 64), (69, 66, 62, 64), (66, 64, 69, 62), (62, 69, 64, 66)]
    for bar, chord in enumerate(chords):
        for voice, note in enumerate(chord):
            samples = tone(note, 10, 0.047 if voice else 0.055, pad=True)
            pan = (voice - 1.5) * 0.14
            for side, channel in enumerate(channels):
                mix(channel, samples, bar * 8 - 1, sqrt((1 + (-1 if side == 0 else 1) * pan) / 2), True)
        # Different phrases per stage; all share a calm palette and musical key.
        note = motifs[index % 4][bar] + (12 if index % 5 == 4 and bar == 2 else 0)
        start = bar * 8 + 2.5 + (index // 4) * 0.22
        samples = tone(note, 2.8, 0.075, attack=0.025)
        for side, channel in enumerate(channels):
            mix(channel, samples, start, 0.8, True)
            mix(channel, samples, start + 0.31 + side * 0.09, 0.16, True)
    # Tiny boundary fades keep native start/stop and the loop splice click-free.
    for channel in channels:
        for i in range(round(RATE * 0.02)):
            gain = (1 - cos(pi * i / (RATE * 0.02))) / 2
            channel[i] *= gain
            channel[-1 - i] *= gain
    return channels


def effects():
    # name: notes, spacing, decay, amplitude, pitch glide. The frequent cues are shortest/quietest.
    return {
        "select": ([74], 0, 0.12, 0.18, 0),
        "start": ([62, 69, 74], 0.14, 0.65, 0.27, 0),
        "hop": ([57], 0, 0.12, 0.20, 0.18),
        "land": ([50], 0, 0.14, 0.22, -0.12),
        "tile": ([69, 74], 0.035, 0.26, 0.22, 0),
        "debugger": ([81, 74, 69], 0.10, 0.5, 0.24, 0),
        "gc": ([50, 62, 69], 0.07, 0.4, 0.26, 0),
        "life": ([66, 69, 78], 0.13, 0.7, 0.27, 0),
        "shield": ([62, 69, 76], 0.055, 0.85, 0.23, 0),
        "patch": ([62, 66, 69], 0.085, 0.35, 0.25, 0),
        "rescue": ([57, 62, 69, 74], 0.075, 0.5, 0.24, 0),
        "stage_clear": ([62, 66, 69, 76], 0.15, 0.9, 0.27, 0),
        "victory": ([62, 66, 69, 74, 78, 81], 0.19, 1.3, 0.26, 0),
        "fall": ([57], 0, 0.48, 0.28, -0.5),
        "hit": ([38, 50], 0.018, 0.27, 0.27, -0.18),
    }


if __name__ == "__main__":
    names = re.findall(r'music: "([a-z]+)"', (ROOT / "game.rb").read_text())
    assert len(names) == 20
    for index, name in enumerate(names):
        write(ROOT / f"assets/music/{name}.wav", music(index))
        print(f"Rendered {name}", flush=True)
    for name, (notes, spacing, duration, gain, slide) in effects().items():
        output = array("f", [0]) * round((duration + spacing * (len(notes) - 1)) * RATE)
        for index, note in enumerate(notes):
            mix(output, tone(note, duration, gain, slide=slide), index * spacing)
        write(ROOT / f"assets/sounds/{name}.wav", [output])
    print("Rendered 15 effects")
