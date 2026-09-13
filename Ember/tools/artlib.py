"""Shared helpers for Ember's procedural art.

Everything is drawn at SS x resolution and downsampled, so the thick cartoon
outlines the Pyros logo uses stay clean at 64-128 px cells.
"""
import math, random
from PIL import Image, ImageDraw, ImageFilter, ImageChops

SS = 4  # supersample factor


def new(w, h, rgba=(0, 0, 0, 0)):
    return Image.new("RGBA", (w, h), rgba)


def down(img, w, h):
    return img.resize((w, h), Image.LANCZOS)


def outline(img, px, color=(15, 10, 14, 255)):
    """Thick black cartoon outline around whatever is opaque in img."""
    a = img.split()[3]
    grown = a
    for _ in range(px):
        grown = grown.filter(ImageFilter.MaxFilter(3))
    ring = Image.new("RGBA", img.size, color)
    ring.putalpha(grown)
    out = Image.alpha_composite(ring, img)
    return out


_feather_cache = {}


def _feather(size, edge=0.12):
    """A mask that fades to nothing at the cell border."""
    key = (size, edge)
    if key in _feather_cache:
        return _feather_cache[key]
    w, h = size
    m = Image.new("L", (w, h), 255)
    px = m.load()
    ex, ey = max(1, int(w * edge)), max(1, int(h * edge))
    for y in range(h):
        fy = min(1.0, min(y, h - 1 - y) / ey)
        for x in range(w):
            fx = min(1.0, min(x, w - 1 - x) / ex)
            f = min(fx, fy)
            if f < 1.0:
                px[x, y] = int(255 * (f * f * (3 - 2 * f)))
    _feather_cache[key] = m
    return m


def glow(img, radius, color, strength=0.55):
    """Soft coloured halo behind img, sampled from its own silhouette.

    Feathered at the cell border: a blur wide enough to read as light spreads
    alpha all the way to the edge of the sprite, and a quad with a uniform
    0.1 alpha at its border draws as a glowing RECTANGLE around the flame.
    """
    a = img.split()[3].filter(ImageFilter.GaussianBlur(radius))
    a = a.point(lambda v: int(v * strength))
    a = ImageChops.multiply(a, _feather(img.size, 0.22))
    # Floor the tail to zero. A wide field of alpha 2-8 is invisible in an
    # image viewer and is NOT invisible on a lit quad in the engine - it
    # draws as a faint rectangle the size of the sprite, with a hard edge
    # where the quad ends.
    a = a.point(lambda v: 0 if v < 14 else v)
    h = Image.new("RGBA", img.size, color)
    h.putalpha(a)
    return Image.alpha_composite(h, img)


def vgrad(size, stops):
    """Vertical gradient. stops: [(t, (r,g,b)), ...] with t 0=top 1=bottom."""
    w, h = size
    g = Image.new("RGB", (1, h))
    px = g.load()
    for y in range(h):
        t = y / max(1, h - 1)
        lo = stops[0]
        hi = stops[-1]
        for i in range(len(stops) - 1):
            if stops[i][0] <= t <= stops[i + 1][0]:
                lo, hi = stops[i], stops[i + 1]
                break
        span = max(1e-6, hi[0] - lo[0])
        f = (t - lo[0]) / span
        px[0, y] = tuple(int(lo[1][c] + (hi[1][c] - lo[1][c]) * f) for c in range(3))
    return g.resize((w, h), Image.NEAREST)


def tint_mask(mask, grad):
    """Paint a gradient through an alpha mask."""
    out = grad.convert("RGBA")
    out.putalpha(mask)
    return out


def noise_layer(w, h, seed, scale=1, alpha=40, colors=((0, 0, 0),)):
    rnd = random.Random(seed)
    img = Image.new("RGBA", (w // scale + 1, h // scale + 1), (0, 0, 0, 0))
    px = img.load()
    for y in range(img.size[1]):
        for x in range(img.size[0]):
            if rnd.random() < 0.5:
                c = colors[rnd.randrange(len(colors))]
                px[x, y] = (c[0], c[1], c[2], rnd.randrange(alpha))
    return img.resize((w, h), Image.NEAREST if scale > 1 else Image.LANCZOS)


def flame_warp(img, phase, amp=0.055, waves=1.5, lean=0.0, sx=1.0, sy=1.0, bias=1.7):
    """Wave the upper part of a flame sideways; anchor the base.

    amp/lean are fractions of the image width. Rows above the base move most
    (bias shapes the falloff), so the tips lick and the feet stay planted.
    """
    w, h = img.size
    if sx != 1.0 or sy != 1.0:
        nw, nh = max(1, int(w * sx)), max(1, int(h * sy))
        scaled = img.resize((nw, nh), Image.LANCZOS)
        img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        img.paste(scaled, ((w - nw) // 2, h - nh))  # feet on the floor
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    for y in range(h):
        t = 1.0 - y / max(1, h - 1)          # 1 top, 0 bottom
        k = t ** bias
        dx = amp * w * k * (math.sin(2 * math.pi * (t * waves + phase))
                            + 0.45 * math.sin(2 * math.pi * (t * waves * 2.3 - phase * 1.7)))
        dx += lean * w * k
        row = img.crop((0, y, w, y + 1))
        out.paste(row, (int(round(dx)), y))
    return out


def draw_flame(size, phase, palette=None, tips=2, lick=0.16, seed=0, licks=True):
    """A teardrop flame: scanline-filled, pointed at the top, wobbling.

    Built row by row rather than as a polygon - a parametric outline kinks at
    the tip and the kink is all anyone sees.
    """
    W = H = size
    w, h = W * SS, H * SS
    rnd = random.Random(seed)
    pal = palette or [(0.0, (255, 248, 205)), (0.30, (255, 198, 66)),
                      (0.66, (244, 96, 32)), (1.0, (172, 24, 26))]
    mask = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(mask)
    top, bot = h * 0.04, h * 0.97

    def body(cx_off, scale, ph, hw_scale=1.0):
        for py in range(int(top), int(bot)):
            u = (py - top) / (bot - top)          # 0 tip .. 1 base
            hw = 0.52 * w * scale * (max(0.0, u) ** 1.7) * hw_scale
            if u > 0.86:  # round the base off rather than ending on a shelf
                hw *= math.sqrt(max(0.0, 1.0 - ((u - 0.86) / 0.15) ** 2))
            cx = w * (0.5 + cx_off) + lick * w * scale * ((1.0 - u) ** 2) * \
                math.sin(2 * math.pi * ((1.0 - u) * tips + ph))
            d.line([(cx - hw, py), (cx + hw, py)], fill=255, width=1)

    body(0.0, 1.0, phase)
    if licks:
        # two smaller tongues climbing the sides, half a beat out of phase
        for s in (-1, 1):
            for py in range(int(h * 0.34), int(bot)):
                u = (py - h * 0.34) / (bot - h * 0.34)
                hw = 0.17 * w * (max(0.0, u) ** 1.5)
                cx = w * (0.5 + s * (0.20 + 0.05 * math.sin(2 * math.pi * (phase + 0.25 * s))))
                cx += s * lick * 0.5 * w * ((1.0 - u) ** 2) * math.sin(2 * math.pi * (phase * 1.3 + 0.3 * s))
                d.line([(cx - hw, py), (cx + hw, py)], fill=255, width=1)
    mask = mask.filter(ImageFilter.GaussianBlur(w * 0.006))
    mask = mask.point(lambda v: 255 if v > 90 else 0)

    img = tint_mask(mask, vgrad((w, h), pal))
    # the bright heart, inset from the silhouette
    inner = Image.new("L", (w, h), 0)
    di = ImageDraw.Draw(inner)
    for py in range(int(h * 0.42), int(bot - h * 0.03)):
        u = (py - h * 0.42) / (bot - h * 0.45)
        hw = 0.26 * w * (max(0.0, u) ** 1.6)
        cx = w * 0.5 + lick * 0.4 * w * ((1.0 - u) ** 2) * math.sin(2 * math.pi * ((1.0 - u) * tips + phase))
        di.line([(cx - hw, py), (cx + hw, py)], fill=255, width=1)
    inner = inner.filter(ImageFilter.GaussianBlur(w * 0.012))
    img = Image.alpha_composite(img, tint_mask(inner, vgrad((w, h), [
        (0.0, (255, 252, 232)), (0.5, (255, 232, 150)), (1.0, (255, 168, 48))])))
    img = outline(img, max(2, int(w * 0.014)))
    return down(img, W, H)


def sheet(frames, cell_w, cell_h, cols=None):
    """Row-major sheet; the engine slices cols x rows the same way."""
    n = len(frames)
    cols = cols or n
    rows = (n + cols - 1) // cols
    s = Image.new("RGBA", (cols * cell_w, rows * cell_h), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        s.paste(f, ((i % cols) * cell_w, (i // cols) * cell_h))
    return s


def contact(frames, path, bg=(26, 22, 34, 255)):
    """Debug strip so I can look at what I generated."""
    w, h = frames[0].size
    s = Image.new("RGBA", (w * len(frames), h), bg)
    for i, f in enumerate(frames):
        s.alpha_composite(f, (i * w, 0))
    s.save(path)
