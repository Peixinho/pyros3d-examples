"""The world of Ember: basalt slabs with a cooling-lava crust, a dead sky,
frostlings, pickups, torches and the brazier at the end.

Everything shares the logo's language: thick black outlines, hot gradients,
and nothing that needs a texture artist.
"""
import os, sys, math, random
from PIL import Image, ImageDraw, ImageFilter
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from artlib import *

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "textures")
SCRATCH = os.environ.get("TMPDIR", "/tmp")
PPU = 64  # pixels per world unit


# ---------------------------------------------------------------- slabs ----
def slab(uw, uh, seed=1, crust=True, name=None):
    """A block of basalt uw x uh world units. Crust glows along the top edge."""
    W, H = int(uw * PPU), int(uh * PPU)
    w, h = W * 2, H * 2
    rnd = random.Random(seed)
    img = vgrad((w, h), [(0.0, (84, 70, 96)), (0.35, (58, 47, 70)),
                         (1.0, (30, 24, 40))]).convert("RGBA")

    d = ImageDraw.Draw(img, "RGBA")
    # facets: big angular shards, the way cooled basalt breaks
    for _ in range(max(6, int(uw * uh * 5))):
        cx, cy = rnd.uniform(0, w), rnd.uniform(h * 0.08, h)
        r = rnd.uniform(w * 0.03, w * 0.11)
        pts = []
        for k in range(rnd.randint(4, 6)):
            a = 2 * math.pi * k / 5 + rnd.uniform(-0.3, 0.3)
            pts.append((cx + math.cos(a) * r * rnd.uniform(0.6, 1.3),
                        cy + math.sin(a) * r * rnd.uniform(0.6, 1.3)))
        v = rnd.randint(-14, 12)
        d.polygon(pts, fill=(max(0, 40 + v), max(0, 33 + v), max(0, 50 + v), 90))
    # cracks
    for _ in range(max(3, int(uw * 2))):
        x, y = rnd.uniform(0, w), rnd.uniform(h * 0.15, h)
        pts = [(x, y)]
        for _ in range(rnd.randint(3, 6)):
            x += rnd.uniform(-w * 0.05, w * 0.05)
            y += rnd.uniform(h * 0.05, h * 0.18)
            pts.append((x, y))
        d.line(pts, fill=(16, 12, 22, 190), width=max(2, int(h * 0.012)))

    if crust:
        band = int(h * 0.17)
        cg = vgrad((w, band), [(0.0, (96, 44, 36)), (0.55, (60, 32, 38)),
                               (1.0, (44, 34, 50))]).convert("RGBA")
        img.paste(cg, (0, 0))
        cd = ImageDraw.Draw(img, "RGBA")
        # a hot rim, then embers cooling into the rock below it
        cd.rectangle([0, 0, w, max(2, int(h * 0.022))], fill=(255, 136, 52, 235))
        cd.rectangle([0, 0, w, max(1, int(h * 0.008))], fill=(255, 206, 128, 255))
        for _ in range(int(uw * 26)):
            ex = rnd.uniform(0, w)
            ey = rnd.uniform(h * 0.02, band * 1.35)
            er = rnd.uniform(w * 0.002, w * 0.008) * (2.0 if uw < 3 else 1.0)
            fade = max(0.0, 1.0 - ey / (band * 1.4))
            col = (255, int(120 + 90 * fade), int(40 + 40 * fade), int(60 + 180 * fade))
            cd.ellipse([ex - er, ey - er, ex + er, ey + er], fill=col)
        # glow spilling up off the crust
        halo = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        hd = ImageDraw.Draw(halo)
        hd.rectangle([0, 0, w, band], fill=(255, 120, 40, 120))
        halo = halo.filter(ImageFilter.GaussianBlur(band * 0.5))
        img = Image.alpha_composite(img, halo)

    # Force the slab opaque. ImageDraw in "RGBA" mode writes the shape's
    # alpha into the destination, so every facet and crack drawn with a
    # translucent fill punched a hole in a block that is meant to be solid
    # rock - measured at alpha 148 over most of the body.
    r, g, b, _ = img.split()
    img = Image.merge("RGBA", (r, g, b, Image.new("L", img.size, 255)))
    out = down(img, W, H)
    if name:
        out.save(f"{OUT}/{name}.png")
    return out


# ----------------------------------------------------------- frostling ----
def frostling(phase, size=112, seed=3):
    """A frostling: a grumpy lump of ice that patrols in your way."""
    W = H = size
    w, h = W * SS, H * SS
    m = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(m)
    squash = 1.0 + 0.11 * math.sin(2 * math.pi * phase)
    bw = w * 0.74 / squash
    bh = h * 0.66 * squash
    cx, cy = w * 0.5, h - bh * 0.5 - h * 0.05
    d.ellipse([cx - bw / 2, cy - bh / 2, cx + bw / 2, cy + bh / 2], fill=255)
    # three crystal shards on the crown, breathing with the squash
    for k, t in enumerate((0.26, 0.5, 0.74)):
        sx = cx - bw * 0.5 + bw * t
        sh = h * (0.13 + 0.05 * math.sin(2 * math.pi * (phase + t)))
        sw = bw * 0.085 * (1.25 if k == 1 else 1.0)
        d.polygon([(sx - sw, cy - bh * 0.34), (sx + sw, cy - bh * 0.34),
                   (sx + sw * 0.2, cy - bh * 0.46 - sh)], fill=255)
    # icicle teeth under the chin
    for t in (0.3, 0.5, 0.7):
        sx = cx - bw * 0.5 + bw * t
        d.polygon([(sx - bw * 0.06, cy + bh * 0.30), (sx + bw * 0.06, cy + bh * 0.30),
                   (sx, cy + bh * 0.30 + h * 0.09)], fill=255)

    img = tint_mask(m, vgrad((w, h), [(0.0, (236, 252, 255)), (0.40, (156, 226, 255)),
                                      (0.78, (86, 168, 236)), (1.0, (46, 104, 190))]))
    d2 = ImageDraw.Draw(img, "RGBA")
    # facets, so it reads as ice and not jelly
    for k in range(4):
        t = k / 4
        d2.line([(cx - bw * 0.38 + bw * 0.9 * t, cy - bh * 0.30),
                 (cx - bw * 0.22 + bw * 0.9 * t, cy + bh * 0.34)],
                fill=(255, 255, 255, 55), width=int(w * 0.012))
    d2.ellipse([cx - bw * 0.34, cy - bh * 0.30, cx - bw * 0.10, cy - bh * 0.06],
               fill=(255, 255, 255, 120))
    # eyes: white, with a pupil and a heavy brow. Cartoon, like the logo.
    er = bw * 0.15
    for s in (-1, 1):
        ex = cx + s * bw * 0.19
        ey = cy - bh * 0.04
        d2.ellipse([ex - er, ey - er, ex + er, ey + er], fill=(250, 253, 255, 255))
        px_ = ex + s * er * 0.25
        d2.ellipse([px_ - er * 0.46, ey - er * 0.30, px_ + er * 0.46, ey + er * 0.62],
                   fill=(22, 34, 62, 255))
        d2.polygon([(ex - er * 1.25, ey - er * 1.15), (ex + er * 1.25, ey - er * 0.35),
                    (ex + er * 1.25, ey - er * 0.95), (ex - er * 1.25, ey - er * 1.75)],
                   fill=(22, 34, 62, 255))
    d2.arc([cx - bw * 0.17, cy + bh * 0.10, cx + bw * 0.17, cy + bh * 0.36], 200, 340,
           fill=(22, 34, 62, 255), width=int(w * 0.014))
    img = outline(img, int(w * 0.017), color=(14, 22, 40, 255))
    img = glow(img, w * 0.035, (120, 205, 255, 255), 0.40)
    return down(img, W, H)


# ------------------------------------------------------------- pickup -----
def ember_shard(phase, size=72):
    """A dropped ember: a four-point star that turns and pulses."""
    W = H = size
    hi = W * SS
    star = Image.new("RGBA", (hi, hi), (0, 0, 0, 0))
    m = Image.new("L", (hi, hi), 0)
    d = ImageDraw.Draw(m)
    pts = []
    for i in range(4 * 32):
        a = 2 * math.pi * i / (4 * 32)
        k = abs(math.cos(2 * a)) ** 2.6
        r = hi * (0.10 + 0.36 * k)
        pts.append((hi / 2 + math.cos(a) * r, hi / 2 + math.sin(a) * r))
    d.polygon(pts, fill=255)
    star = tint_mask(m, vgrad((hi, hi), [(0.0, (255, 246, 202)), (0.45, (255, 180, 60)),
                                         (1.0, (238, 88, 26))]))
    star = outline(star, int(hi * 0.012))
    core = Image.new("RGBA", (hi, hi), (0, 0, 0, 0))
    ImageDraw.Draw(core).ellipse([hi * 0.42, hi * 0.42, hi * 0.58, hi * 0.58],
                                 fill=(255, 253, 236, 255))
    star = Image.alpha_composite(star, core.filter(ImageFilter.GaussianBlur(hi * 0.012)))
    pulse = 1.0 + 0.12 * math.sin(2 * math.pi * phase * 2)
    star = star.rotate(-phase * 360.0, resample=Image.BICUBIC)
    s2 = int(hi * pulse)
    star = star.resize((s2, s2), Image.LANCZOS)
    canvas = Image.new("RGBA", (hi, hi), (0, 0, 0, 0))
    canvas.paste(star, ((hi - s2) // 2, (hi - s2) // 2))
    canvas = glow(canvas, hi * 0.06, (255, 165, 55, 255), 0.85)
    return down(canvas, W, H)


# -------------------------------------------------------------- props -----
def torch_post(name="torch_post"):
    W, H = 48, 128
    w, h = W * SS, H * SS
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img, "RGBA")
    d.polygon([(w * 0.38, h), (w * 0.62, h), (w * 0.60, h * 0.30), (w * 0.40, h * 0.30)],
              fill=(58, 44, 38, 255))
    d.polygon([(w * 0.22, h * 0.34), (w * 0.78, h * 0.34), (w * 0.68, h * 0.02), (w * 0.32, h * 0.02)],
              fill=(84, 66, 52, 255))
    d.rectangle([w * 0.24, h * 0.28, w * 0.76, h * 0.36], fill=(40, 30, 26, 255))
    for i in range(9):
        y = h * (0.36 + i * 0.07)
        d.line([(w * 0.40, y), (w * 0.60, y)], fill=(34, 25, 22, 160), width=int(h * 0.006))
    img = outline(img, int(w * 0.03))
    down(img, W, H).save(f"{OUT}/{name}.png")


def brazier(name="brazier"):
    W, H = 192, 144
    w, h = W * SS, H * SS
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img, "RGBA")
    # bowl
    d.polygon([(w * 0.14, h * 0.42), (w * 0.86, h * 0.42), (w * 0.70, h * 0.86), (w * 0.30, h * 0.86)],
              fill=(70, 56, 62, 255))
    d.rectangle([w * 0.10, h * 0.34, w * 0.90, h * 0.46], fill=(96, 76, 72, 255))
    # legs
    for s in (-1, 1):
        d.polygon([(w * (0.5 + s * 0.16), h * 0.84), (w * (0.5 + s * 0.28), h * 0.99),
                   (w * (0.5 + s * 0.16), h * 0.99), (w * (0.5 + s * 0.06), h * 0.84)],
                  fill=(58, 46, 52, 255))
    d.rectangle([w * 0.30, h * 0.95, w * 0.70, h * 1.0], fill=(58, 46, 52, 255))
    # coals in the bowl
    rnd = random.Random(9)
    for _ in range(70):
        cx = rnd.uniform(w * 0.16, w * 0.84)
        cy = rnd.uniform(h * 0.34, h * 0.46)
        r = rnd.uniform(w * 0.006, w * 0.022)
        f = rnd.random()
        d.ellipse([cx - r, cy - r, cx + r, cy + r],
                  fill=(255, int(90 + 120 * f), int(30 + 50 * f), int(120 + 135 * f)))
    img = outline(img, int(w * 0.012))
    down(img, W, H).save(f"{OUT}/{name}.png")


def pillar(name="pillar"):
    W, H = 96, 384
    w, h = W * SS, H * SS
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img, "RGBA")
    d.rectangle([w * 0.18, h * 0.05, w * 0.82, h], fill=(52, 42, 60, 255))
    d.rectangle([w * 0.06, 0, w * 0.94, h * 0.06], fill=(66, 54, 74, 255))
    rnd = random.Random(21)
    for i in range(9):
        y = h * (0.10 + i * 0.098)
        d.line([(w * 0.18, y), (w * 0.82, y + rnd.uniform(-h * 0.004, h * 0.004))],
               fill=(28, 22, 34, 210), width=int(h * 0.005))
    for _ in range(26):
        cx, cy = rnd.uniform(w * 0.2, w * 0.8), rnd.uniform(h * 0.08, h)
        r = rnd.uniform(w * 0.01, w * 0.05)
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(40, 32, 48, 140))
    img = outline(img, int(w * 0.035))
    down(img, W, H).save(f"{OUT}/{name}.png")


def frost_pool(phase, uw=4, size_h=48):
    """The cold at the bottom of a pit. Not water - something worse."""
    W, H = uw * PPU, size_h
    w, h = W * 2, H * 2
    img = vgrad((w, h), [(0.0, (150, 214, 246)), (0.22, (74, 140, 208)),
                         (1.0, (18, 40, 86))]).convert("RGBA")
    d = ImageDraw.Draw(img, "RGBA")
    for i in range(int(uw * 7)):
        t = i / (uw * 7)
        x = t * w + math.sin(2 * math.pi * (phase + t * 3)) * w * 0.01
        d.ellipse([x - w * 0.012, h * 0.06, x + w * 0.012, h * 0.16],
                  fill=(226, 246, 255, 150))
    d.rectangle([0, 0, w, h * 0.05], fill=(214, 242, 255, 230))
    r, g, b, _ = img.split()
    img = Image.merge("RGBA", (r, g, b, Image.new("L", img.size, 255)))
    return down(img, W, H)


# ---------------------------------------------------------- particles -----
def radial(size, color, power=2.2, name=None):
    w = size * 2
    m = Image.new("L", (w, w), 0)
    px = m.load()
    c = (w - 1) / 2
    for y in range(w):
        for x in range(w):
            r = math.hypot(x - c, y - c) / c
            v = max(0.0, 1.0 - r) ** power
            px[x, y] = int(255 * v)
    img = Image.new("RGBA", (w, w), color)
    img.putalpha(m)
    out = down(img, size, size)
    if name:
        out.save(f"{OUT}/{name}.png")
    return out


def puff(size, color, seed, name=None):
    w = size * 2
    img = Image.new("RGBA", (w, w), (0, 0, 0, 0))
    d = ImageDraw.Draw(img, "RGBA")
    rnd = random.Random(seed)
    for _ in range(9):
        cx, cy = rnd.uniform(w * 0.3, w * 0.7), rnd.uniform(w * 0.3, w * 0.7)
        r = rnd.uniform(w * 0.16, w * 0.28)
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=color)
    img = img.filter(ImageFilter.GaussianBlur(w * 0.05))
    out = down(img, size, size)
    if name:
        out.save(f"{OUT}/{name}.png")
    return out


# -------------------------------------------------------- backgrounds -----
def sky(name="bg_sky"):
    # Wide on purpose: a 64 px column stretched over a hundred world units
    # needs a scale factor in the hundreds, and a quad that extreme is culled.
    W, H = 1024, 512
    # Painted for how it lands AFTER ambient multiplies it - the sky is the
    # only thing in the scene no light ever touches.
    img = vgrad((W, H), [(0.0, (54, 38, 96)), (0.38, (104, 56, 122)),
                         (0.66, (176, 82, 112)), (0.85, (236, 124, 88)),
                         (1.0, (255, 176, 104))]).convert("RGBA")
    img.save(f"{OUT}/{name}.png")


def ridge(W, H, base_y, amp, colour, seed, spikes=7, glowline=None):
    w, h = W, H
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img, "RGBA")
    rnd = random.Random(seed)
    n = spikes
    pts = [(0, h), (0, base_y)]
    for i in range(n + 1):
        x = w * i / n
        peak = base_y - amp * (0.45 + 0.55 * rnd.random())
        if i == 0 or i == n:
            peak = base_y - amp * 0.5      # the seam sits mid-slope, not in a hole
        pts.append((x - w / (n * 2.4), base_y))
        pts.append((x, peak))
    pts.append((w, base_y))
    pts.append((w, h))
    d.polygon(pts, fill=colour)
    if glowline:
        d.line(pts[1:-2], fill=glowline, width=max(1, int(h * 0.006)))
    return img


def bg_far(name="bg_far"):
    W, H = 2048, 640
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    rnd = random.Random(5)
    # stars
    d = ImageDraw.Draw(img, "RGBA")
    for _ in range(220):
        x, y = rnd.uniform(0, W), rnd.uniform(0, H * 0.55)
        r = rnd.uniform(0.6, 2.0)
        a = rnd.randrange(60, 200)
        d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 250, 255, min(255, int(a * 1.6))))
    # a distant volcano, still burning
    vx = W * 0.68
    d.polygon([(vx - 340, H), (vx, H * 0.20), (vx + 360, H)], fill=(40, 27, 58, 255))
    d.polygon([(vx - 60, H * 0.28), (vx, H * 0.17), (vx + 62, H * 0.28)], fill=(190, 70, 40, 255))
    smoke = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(smoke)
    for i in range(26):
        t = i / 26
        r = 30 + 110 * t
        sd.ellipse([vx - r + 130 * t, H * 0.17 - 300 * t - r, vx + r + 130 * t, H * 0.17 - 300 * t + r],
                   fill=(120, 60, 70, int(70 * (1 - t))))
    img = Image.alpha_composite(img, smoke.filter(ImageFilter.GaussianBlur(14)))
    img = Image.alpha_composite(img, ridge(W, H, H * 0.62, H * 0.30, (38, 26, 60, 255), 7, 9,
                                           glowline=(126, 70, 92, 150)))
    img.save(f"{OUT}/{name}.png")


def bg_mid(name="bg_mid"):
    W, H = 2048, 640
    img = ridge(W, H, H * 0.74, H * 0.34, (20, 14, 32, 255), 11, 13,
                glowline=(186, 92, 70, 190))
    d = ImageDraw.Draw(img, "RGBA")
    rnd = random.Random(17)
    # dead trees and broken arches along the ridgeline
    for i in range(13):
        x = W * (i + 0.5) / 13 + rnd.uniform(-40, 40)
        base = H * 0.76
        ht = rnd.uniform(H * 0.10, H * 0.20)
        d.line([(x, base), (x, base - ht)], fill=(12, 8, 20, 255), width=9)
        for b in range(3):
            bt = rnd.uniform(0.35, 0.9)
            dxx = rnd.choice([-1, 1]) * rnd.uniform(20, 60)
            d.line([(x, base - ht * bt), (x + dxx, base - ht * bt - rnd.uniform(20, 50))],
                   fill=(12, 8, 20, 255), width=6)
    # a few lit windows in a ruin, so the mid ground has a heartbeat
    for i in range(5):
        x = rnd.uniform(W * 0.05, W * 0.95)
        y = rnd.uniform(H * 0.78, H * 0.92)
        d.rectangle([x, y, x + 9, y + 13], fill=(255, 190, 110, 220))
    img.save(f"{OUT}/{name}.png")


def fore_rock(name, seed=41):
    """Foreground silhouette: near-black, it only has to read as a shape."""
    W, H = 256, 384
    w, h = W * SS // 2, H * SS // 2
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img, "RGBA")
    rnd = random.Random(seed)
    pts = [(0, h)]
    x = 0
    while x < w:
        x += rnd.uniform(w * 0.10, w * 0.24)
        pts.append((min(x, w), rnd.uniform(h * 0.05, h * 0.55)))
    pts.append((w, h))
    d.polygon(pts, fill=(16, 11, 24, 255))
    down(img, W, H).save(f"{OUT}/{name}.png")


def dim_backdrops(factor=0.55):
    """Backdrops are lit by the Moon as well as by ambient - they face +z and
    a directional light lands on them square. Painted for ambient alone they
    come out twice as bright as intended and start competing with the level,
    so the art is scaled back here rather than the light being weakened
    (which is what keeps the 2D-lit sprites readable)."""
    for name in ("bg_sky", "bg_far", "bg_mid", "fore_rock_a", "fore_rock_b"):
        f = f"{OUT}/{name}.png"
        im = Image.open(f).convert("RGBA")
        r, g, b, a = im.split()
        scale = lambda c: c.point(lambda v: int(v * factor))
        Image.merge("RGBA", (scale(r), scale(g), scale(b), a)).save(f)


if __name__ == "__main__":
    # --- slabs at the widths the level uses, so nothing is stretched -------
    for uw in (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 14, 20):
        slab(uw, 1, seed=100 + uw, name=f"slab_{uw}x1")
    for uw in (2, 3, 4, 5):
        slab(uw, 0.5, seed=200 + uw, name=f"ledge_{uw}")
    slab(2, 2, seed=301, name="block_2x2")
    slab(1, 3, seed=302, name="block_1x3")

    fr = [frostling(i / 6) for i in range(6)]
    sheet(fr, 112, 112).save(f"{OUT}/frostling.png")

    sh = [ember_shard(i / 8) for i in range(8)]
    sheet(sh, 72, 72).save(f"{OUT}/ember_shard.png")

    tf = [draw_flame(96, i / 6, seed=i) for i in range(6)]
    tf = [glow(f, 6, (255, 150, 50, 255), 0.55) for f in tf]
    sheet(tf, 96, 96).save(f"{OUT}/torch_flame.png")

    bf = [draw_flame(192, i / 8, tips=4, lick=0.26, seed=10 + i) for i in range(8)]
    bf = [glow(f, 14, (255, 150, 50, 255), 0.7) for f in bf]
    sheet(bf, 192, 192).save(f"{OUT}/brazier_flame.png")

    pool = [frost_pool(i / 4) for i in range(4)]
    sheet(pool, 4 * PPU, 48).save(f"{OUT}/frost_pool.png")

    torch_post(); brazier(); pillar(); sky(); bg_far(); bg_mid()
    fore_rock("fore_rock_a", 41); fore_rock("fore_rock_b", 77)
    radial(64, (255, 210, 140, 255), 2.0, "p_spark")
    radial(64, (150, 220, 255, 255), 2.4, "p_frost")
    puff(64, (210, 160, 140, 60), 4, "p_smoke")
    puff(64, (220, 240, 255, 55), 7, "p_steam")

    dim_backdrops()

    contact([slab(4, 1, 104), slab(2, 0.5, 202).resize((256, 64)),
             frost_pool(0).resize((256, 48))], f"{SCRATCH}/preview_slabs.png")
    print("world art written")
