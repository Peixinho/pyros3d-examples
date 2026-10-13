#!/usr/bin/env python3
"""Kickstart's sounds.

    python3 tools/make_sounds.py /path/to/kenney

The engine is made here: a single-cylinder motor is a pulse a firing, and a
loop of exactly so many firings repeats without a seam - the game plays one
loop and changes its pitch with the revs. The rest are Kenney's (CC0):
impact-sounds, digital-audio, music-jingles, interface-sounds. Needs numpy.
"""
import os
import shutil
import sys
import wave

import numpy as np

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(HERE, "assets", "sounds")
RATE = 44100


def write(name, samples):
    samples = np.clip(samples, -1, 1)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes((samples * 32767).astype(np.int16).tobytes())


def engine(name, firing_hz, seconds, rasp):
    """A loop of whole firings. Each is a sharp bang that rings down - the exhaust -
    over a low thump - the crank - with a little grit that is the same every firing, so it loops."""
    cycles = int(round(firing_hz * seconds))
    n = int(round(cycles * RATE / firing_hz))
    t = np.arange(n) / RATE
    phase = (t * firing_hz) % 1.0
    rnd = np.random.RandomState(7)
    bang = np.exp(-phase * 9.0) * np.sin(2 * np.pi * phase * 6.0)
    ring = np.exp(-phase * 4.0) * np.sin(2 * np.pi * phase * 11.0 + 0.7) * 0.5
    thump = np.sin(2 * np.pi * phase) * 0.55 + np.sin(4 * np.pi * phase + 0.4) * 0.25
    one = rnd.uniform(-1, 1, int(RATE / firing_hz) + 2)                 # one firing's worth of grit
    idx = np.minimum((phase * (len(one) - 1)).astype(int), len(one) - 1)
    grit = one[idx] * np.exp(-phase * 6.0) * rasp
    # every other firing a touch stronger: the lope of a single at low revs
    lope = 1.0 + 0.12 * np.sign(np.sin(np.pi * t * firing_hz))
    s = (bang * 0.9 + ring + thump + grit) * lope
    s = np.tanh(s * 1.6) * 0.62                                          # a little bite
    write(name, s)


def crowd(name, seconds):
    """A stadium's murmur: many voices are noise with the voice's shape, swelling and falling.
    The swell is whole cycles of the loop, so it has no seam."""
    n = int(RATE * seconds)
    rnd = np.random.RandomState(3)
    spec = np.fft.rfft(rnd.normal(0, 1, n))
    f = np.fft.rfftfreq(n, 1 / RATE)
    shape = np.exp(-((np.log(np.maximum(f, 1)) - np.log(700)) ** 2) / 0.9) + 0.35 * np.exp(-((np.log(np.maximum(f, 1)) - np.log(2400)) ** 2) / 0.5)
    s = np.fft.irfft(spec * shape, n)
    s /= np.abs(s).max()
    t = np.arange(n) / n
    swell = 0.75 + 0.15 * np.sin(2 * np.pi * t * 3) + 0.10 * np.sin(2 * np.pi * t * 7 + 1.0)
    write(name, s * swell * 0.5)


def tone(name, hz, seconds):
    t = np.arange(int(RATE * seconds)) / RATE
    env = np.minimum(1, t * 200) * np.minimum(1, (seconds - t) * 30)
    write(name, np.sin(2 * np.pi * hz * t) * env * 0.6 + np.sin(4 * np.pi * hz * t) * env * 0.15)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    kenney = sys.argv[1]
    os.makedirs(OUT, exist_ok=True)
    engine("engine", 52.0, 1.0, 0.35)
    crowd("crowd", 6.0)
    tone("beep", 660, 0.22)
    tone("go", 990, 0.55)
    for src, to in (("impact-sounds/Audio/impactSoft_heavy_001.ogg", "land"), ("impact-sounds/Audio/impactSoft_heavy_003.ogg", "land2"),
                    ("impact-sounds/Audio/impactPlate_heavy_002.ogg", "crash"), ("impact-sounds/Audio/impactPunch_heavy_001.ogg", "thud"),
                    ("digital-audio/Audio/powerUp7.ogg", "flip"), ("interface-sounds/Audio/click_002.ogg", "click"),
                    ("interface-sounds/Audio/confirmation_002.ogg", "confirm"),
                    ("music-jingles/Audio/Pizzicato jingles/jingles_PIZZI10.ogg", "win"), ("music-jingles/Audio/Pizzicato jingles/jingles_PIZZI03.ogg", "lose")):
        path = os.path.join(kenney, src)
        if os.path.exists(path):
            shutil.copyfile(path, os.path.join(OUT, to + ".ogg"))
        else:
            print("missing", src)
    print("sounds in", OUT)
