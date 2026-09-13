"""Every sound in Ember, synthesised. No samples, no library.

A tiny mono synth (oscillators, one-pole filters, a delay line) plus the
arrangement of one 8-bar loop. 22.05 kHz is plenty for this palette and keeps
the whole soundtrack under a megabyte.
"""
import math, random, struct, wave, os

SR = 22050
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sounds")
os.makedirs(OUT, exist_ok=True)


def buf(seconds):
    return [0.0] * int(SR * seconds)


def save(name, data, peak=0.85):
    m = max(1e-9, max(abs(v) for v in data))
    k = peak / m
    frames = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, v * k)) * 32000)) for v in data)
    with wave.open(f"{OUT}/{name}.wav", "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(frames)
    print(f"{name}.wav  {len(data)/SR:.2f}s")


def env(n, a, d, s=0.0, r=None, sus=0.0):
    """Attack/decay to sustain level, then release. Times in seconds."""
    r = r if r is not None else 0.0
    out = [0.0] * n
    ai, di, si, ri = int(a * SR), int(d * SR), int(sus * SR), int(r * SR)
    i = 0
    for k in range(ai):
        if i < n: out[i] = k / max(1, ai); i += 1
    for k in range(di):
        if i < n: out[i] = 1.0 + (s - 1.0) * (k / max(1, di)); i += 1
    for k in range(si):
        if i < n: out[i] = s; i += 1
    for k in range(ri):
        if i < n: out[i] = s * (1.0 - k / max(1, ri)); i += 1
    return out


def expdec(n, tau):
    return [math.exp(-i / (tau * SR)) for i in range(n)]


def osc(n, f0, f1=None, kind="sine", phase=0.0, duty=0.5):
    f1 = f0 if f1 is None else f1
    out = [0.0] * n
    p = phase
    for i in range(n):
        t = i / max(1, n - 1)
        f = f0 * (f1 / f0) ** t if f0 > 0 and f1 > 0 else f0 + (f1 - f0) * t
        p += f / SR
        x = p % 1.0
        if kind == "sine":
            v = math.sin(2 * math.pi * x)
        elif kind == "saw":
            v = 2 * x - 1
        elif kind == "square":
            v = 1.0 if x < duty else -1.0
        elif kind == "tri":
            v = 4 * abs(x - 0.5) - 1
        else:
            v = 0.0
        out[i] = v
    return out


def noise(n, seed=0):
    rnd = random.Random(seed)
    return [rnd.uniform(-1, 1) for _ in range(n)]


def lp(sig, cutoff0, cutoff1=None):
    """One-pole low pass with an optional sweep."""
    c1 = cutoff0 if cutoff1 is None else cutoff1
    out = [0.0] * len(sig)
    y = 0.0
    for i, x in enumerate(sig):
        t = i / max(1, len(sig) - 1)
        fc = cutoff0 * (c1 / cutoff0) ** t if cutoff0 > 0 and c1 > 0 else cutoff0
        a = 1.0 - math.exp(-2 * math.pi * fc / SR)
        y += a * (x - y)
        out[i] = y
    return out


def hp(sig, cutoff):
    lo = lp(sig, cutoff)
    return [x - y for x, y in zip(sig, lo)]


def mul(a, b):
    return [x * y for x, y in zip(a, b)]


def mix(dst, src, at=0.0, gain=1.0):
    o = int(at * SR)
    for i, v in enumerate(src):
        j = o + i
        if 0 <= j < len(dst):
            dst[j] += v * gain
    return dst


def delay(sig, time, feedback=0.35, wet=0.35):
    d = int(time * SR)
    out = list(sig)
    for i in range(d, len(out)):
        out[i] += out[i - d] * feedback
    return [s * (1 - wet) + o * wet for s, o in zip(sig, out)]


# ------------------------------------------------------------------ sfx ----
def sfx_jump():
    n = int(0.28 * SR)
    body = mul(osc(n, 300, 760, "square", duty=0.35), expdec(n, 0.07))
    air = mul(lp(noise(n, 1), 1200, 4200), expdec(n, 0.05))
    return [b * 0.7 + a * 0.35 for b, a in zip(body, air)]


def sfx_flare():
    """The mid-air flare jump: a gasp of fuel going up at once."""
    n = int(0.45 * SR)
    whoosh = mul(hp(lp(noise(n, 2), 600, 5200), 250), expdec(n, 0.12))
    tone = mul(osc(n, 420, 1180, "tri"), expdec(n, 0.09))
    spark = [0.0] * n
    rnd = random.Random(9)
    for _ in range(14):
        at = rnd.uniform(0.0, 0.22)
        m = int(0.05 * SR)
        mix(spark, mul(osc(m, rnd.uniform(1400, 3000), rnd.uniform(900, 2200), "sine"),
                       expdec(m, 0.012)), at, 0.5)
    return [w * 0.8 + t * 0.45 + s * 0.5 for w, t, s in zip(whoosh, tone, spark)]


def sfx_land():
    n = int(0.30 * SR)
    thud = mul(osc(n, 150, 55, "sine"), expdec(n, 0.06))
    grit = mul(lp(noise(n, 3), 2400, 500), expdec(n, 0.045))
    return [t * 0.9 + g * 0.4 for t, g in zip(thud, grit)]


def sfx_pickup():
    n = int(0.42 * SR)
    out = [0.0] * n
    for k, f in enumerate((880, 1174.7, 1760)):          # A5 - D6 - A6
        m = int(0.22 * SR)
        v = mul(osc(m, f, f, "sine"), expdec(m, 0.07))
        v2 = mul(osc(m, f * 2, f * 2, "sine"), expdec(m, 0.04))
        mix(out, [a + b * 0.3 for a, b in zip(v, v2)], 0.045 * k, 0.8)
    return delay(out, 0.09, 0.3, 0.28)


def sfx_melt():
    n = int(0.55 * SR)
    steam = mul(lp(noise(n, 5), 5000, 700), expdec(n, 0.16))
    pop = mul(osc(n, 640, 180, "sine"), expdec(n, 0.05))
    return [s * 0.85 + p * 0.5 for s, p in zip(steam, pop)]


def sfx_hurt():
    n = int(0.40 * SR)
    growl = mul(osc(n, 240, 90, "saw"), expdec(n, 0.11))
    wob = osc(n, 18, 9, "sine")
    growl = [g * (0.7 + 0.3 * w) for g, w in zip(growl, wob)]
    ice = mul(hp(noise(n, 6), 2600), expdec(n, 0.06))
    return [g * 0.8 + i * 0.35 for g, i in zip(growl, ice)]


def sfx_out():
    """Going out. A flame drowning."""
    n = int(1.1 * SR)
    hiss = mul(lp(noise(n, 7), 4200, 300), expdec(n, 0.30))
    fall = mul(osc(n, 520, 70, "tri"), expdec(n, 0.35))
    return [h * 0.8 + f * 0.6 for h, f in zip(hiss, fall)]


def sfx_torch():
    """Lighting a torch: it catches, then settles."""
    n = int(0.9 * SR)
    catch = mul(lp(noise(n, 8), 900, 3600), env(n, 0.02, 0.10, 0.25, 0.6, 0.05))
    chord = [0.0] * n
    for f in (261.6, 392.0, 523.3):                       # C - G - C
        mix(chord, mul(osc(n, f, f, "tri"), expdec(n, 0.32)), 0.0, 0.4)
    return [c * 0.7 + ch * 0.5 for c, ch in zip(catch, chord)]


def sfx_win():
    n = int(2.4 * SR)
    out = [0.0] * n
    notes = [(0.00, 392.0), (0.13, 523.3), (0.26, 659.3), (0.39, 784.0),
             (0.55, 1046.5), (0.80, 784.0), (0.80, 1046.5), (0.80, 1318.5)]
    for at, f in notes:
        m = int(1.3 * SR)
        v = mul(osc(m, f, f, "square", duty=0.42), expdec(m, 0.30))
        v2 = mul(osc(m, f * 1.005, f * 1.005, "tri"), expdec(m, 0.36))
        mix(out, [a * 0.5 + b * 0.5 for a, b in zip(v, v2)], at, 0.55)
    bass = [0.0] * n
    for at, f in ((0.0, 98.0), (0.55, 130.8), (0.8, 196.0)):
        m = int(0.9 * SR)
        mix(bass, mul(osc(m, f, f, "saw"), expdec(m, 0.25)), at, 0.6)
    out = [o + b * 0.5 for o, b in zip(out, bass)]
    return delay(out, 0.17, 0.30, 0.25)


def sfx_step():
    n = int(0.12 * SR)
    return mul(hp(lp(noise(n, 11), 3000, 1200), 400), expdec(n, 0.022))


def loop_fire(seconds=3.0):
    """Room tone for a living flame: rumble plus crackle, loops cleanly."""
    n = int(seconds * SR)
    rumble = lp(noise(n, 13), 220)
    breath = osc(n, 0.7, 0.7, "sine")
    body = [r * (0.55 + 0.45 * b) for r, b in zip(rumble, breath)]
    crack = [0.0] * n
    rnd = random.Random(17)
    t = 0.0
    while t < seconds - 0.12:
        m = int(rnd.uniform(0.01, 0.05) * SR)
        mix(crack, mul(hp(noise(m, rnd.randrange(9999)), 1800), expdec(m, 0.006)),
            t, rnd.uniform(0.3, 1.0))
        t += rnd.uniform(0.02, 0.16)
    out = [b * 0.9 + c * 0.5 for b, c in zip(body, crack)]
    # crossfade the tail into the head so the loop has no seam
    x = int(0.25 * SR)
    for i in range(x):
        f = i / x
        out[i] = out[i] * f + out[n - x + i] * (1 - f)
    return out[:n - x]


# ---------------------------------------------------------------- music ----
def music():
    """Eight bars in D minor at 144 - bass, arp, pad stabs, and a kit."""
    BPM = 144.0
    beat = 60.0 / BPM
    bar = 4 * beat
    bars = 8
    total = bar * bars
    n = int(total * SR)
    out = [0.0] * n

    def note(t, f, dur, kind, gain, tau=None, duty=0.5, detune=0.0):
        m = int(dur * SR)
        v = mul(osc(m, f, f, kind, duty=duty), expdec(m, tau or dur * 0.45))
        if detune:
            v2 = mul(osc(m, f * (1 + detune), f * (1 + detune), kind, duty=duty),
                     expdec(m, tau or dur * 0.45))
            v = [(a + b) * 0.5 for a, b in zip(v, v2)]
        mix(out, v, t, gain)

    N = {"D2": 73.4, "F2": 87.3, "G2": 98.0, "A2": 110.0, "Bb2": 116.5, "C3": 130.8,
         "D3": 146.8, "F3": 174.6, "G3": 196.0, "A3": 220.0, "Bb3": 233.1, "C4": 261.6,
         "D4": 293.7, "F4": 349.2, "G4": 392.0, "A4": 440.0, "Bb4": 466.2, "C5": 523.3,
         "D5": 587.3, "F5": 698.5, "A5": 880.0}

    # i - VI - III - VII, the whole engine of the thing
    roots = ["D2", "Bb2", "F2", "C3", "D2", "Bb2", "G2", "A2"]
    chords = [("D4", "F4", "A4"), ("Bb3", "D4", "F4"), ("F4", "A4", "C5"), ("C4", "F4", "A4"),
              ("D4", "F4", "A4"), ("Bb3", "D4", "F4"), ("G3", "Bb3", "D4"), ("A3", "C4", "F4")]
    arps = [["D4", "A4", "F4", "A4"], ["Bb3", "F4", "D4", "F4"], ["F4", "C5", "A4", "C5"],
            ["C4", "G4", "F4", "G4"], ["D4", "A4", "D5", "A4"], ["Bb3", "F4", "Bb4", "F4"],
            ["G3", "D4", "Bb3", "D4"], ["A3", "F4", "C5", "F4"]]

    for b in range(bars):
        t0 = b * bar
        root = N[roots[b]]
        # driving eighth-note bass, with the offbeats ducked
        for e in range(8):
            t = t0 + e * beat / 2
            f = root * (2.0 if e in (5, 7) and b % 2 == 1 else 1.0)
            note(t, f, beat * 0.46, "saw", 0.50 if e % 2 == 0 else 0.34, tau=beat * 0.16)
        # sixteenth arpeggio on top
        seq = arps[b]
        for s in range(16):
            t = t0 + s * beat / 4
            f = N[seq[s % 4]] * (2.0 if (b >= 4 and s % 8 >= 4) else 1.0)
            note(t, f, beat * 0.30, "square", 0.16, tau=beat * 0.08, duty=0.30, detune=0.004)
        # chord stabs on 2 and 4, tri so they sit under the arp
        for e in (1, 3):
            for f in chords[b]:
                note(t0 + e * beat, N[f], beat * 0.55, "tri", 0.10, tau=beat * 0.20)
        # kit
        for e in range(4):
            t = t0 + e * beat
            if e in (0, 2):
                m = int(0.16 * SR)
                mix(out, mul(osc(m, 160, 48, "sine"), expdec(m, 0.05)), t, 0.65)   # kick
            if e in (1, 3):
                m = int(0.18 * SR)
                sn = mul(hp(noise(m, 100 + b * 4 + e), 1400), expdec(m, 0.045))
                tn = mul(osc(m, 220, 160, "tri"), expdec(m, 0.03))
                mix(out, [s * 0.8 + t2 * 0.4 for s, t2 in zip(sn, tn)], t, 0.5)    # snare
            for h in range(2):
                m = int(0.05 * SR)
                mix(out, mul(hp(noise(m, 500 + b * 8 + e * 2 + h), 5000), expdec(m, 0.010)),
                    t + h * beat / 2, 0.22 if h == 0 else 0.13)                    # hats
        if b in (3, 7):  # a fill to hand the loop back to bar one
            for k in range(4):
                m = int(0.10 * SR)
                mix(out, mul(hp(noise(m, 900 + k), 900), expdec(m, 0.03)),
                    t0 + 3 * beat + k * beat / 4, 0.30 + 0.10 * k)

    out = delay(out, beat / 2, 0.22, 0.18)
    # seam: fold the last beat into the first so the loop point is inaudible
    x = int(beat * 0.5 * SR)
    for i in range(x):
        f = i / x
        out[i] = out[i] * f + out[n - x + i] * (1 - f)
    return out[:n - x]


if __name__ == "__main__":
    save("jump", sfx_jump())
    save("flare", sfx_flare())
    save("land", sfx_land())
    save("pickup", sfx_pickup())
    save("melt", sfx_melt())
    save("hurt", sfx_hurt())
    save("out", sfx_out())
    save("torch", sfx_torch())
    save("win", sfx_win())
    save("step", sfx_step(), peak=0.55)
    save("fire_loop", loop_fire(), peak=0.7)
    save("music", music(), peak=0.80)
