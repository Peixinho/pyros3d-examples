"""Ember the player: the Pyros logo, alive.

The hero is not a drawing of a flame - it is the editor's own logo, warped per
frame so the tips lick and the body squashes. That is why he has those eyes.
"""
import os, sys, math
from PIL import Image, ImageFilter
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from artlib import *

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "textures")
LOGO = os.environ.get("PYROS_LOGO", os.path.join(os.path.dirname(os.path.abspath(__file__)), "pyros.png"))
CELL = 128
HI = CELL * 3   # work big, downsample once at the end

def base_logo():
    src = Image.open(LOGO).convert("RGBA")
    src = src.crop(src.split()[3].getbbox())
    # square canvas, flame standing on the floor of the cell with a little air
    w, h = src.size
    th = int(HI * 0.90)
    tw = int(w * th / h)
    src = src.resize((tw, th), Image.LANCZOS)
    img = Image.new("RGBA", (HI, HI), (0, 0, 0, 0))
    img.paste(src, ((HI - tw) // 2, HI - th - int(HI * 0.02)))
    return img

BASE = base_logo()

def frame(phase, amp=0.05, waves=1.4, lean=0.0, sx=1.0, sy=1.0, halo=0.5):
    f = flame_warp(BASE, phase, amp=amp, waves=waves, lean=lean, sx=sx, sy=sy)
    if halo > 0:
        f = glow(f, HI * 0.055, (255, 138, 40, 255), halo)
    return down(f, CELL, CELL)

# --- idle: breathing, licking, feet planted ---------------------------------
idle = []
for i in range(8):
    p = i / 8.0
    b = math.sin(2 * math.pi * p)
    idle.append(frame(p, amp=0.10, waves=2.1,
                      sx=1.0 - 0.06 * b, sy=1.0 + 0.085 * b, halo=0.55 + 0.12 * b))

# --- run: leaning forward, bobbing, licking hard ----------------------------
run = []
for i in range(8):
    p = i / 8.0
    b = math.sin(2 * math.pi * p)
    run.append(frame(p * 2.0, amp=0.13, waves=2.4, lean=0.10 + 0.045 * b,
                     sx=1.03 - 0.07 * b, sy=0.95 + 0.10 * b, halo=0.6))

# --- air: 0-1 rising (stretched), 2-3 falling (squat, tips blown up) --------
air = [
    frame(0.10, amp=0.09, waves=1.9, lean=0.05, sx=0.78, sy=1.30, halo=0.62),
    frame(0.35, amp=0.11, waves=2.1, lean=0.06, sx=0.83, sy=1.20, halo=0.62),
    frame(0.60, amp=0.15, waves=2.6, lean=-0.06, sx=1.12, sy=0.90, halo=0.55),
    frame(0.85, amp=0.17, waves=2.9, lean=-0.08, sx=1.16, sy=0.86, halo=0.55),
]

# --- hurt: guttering out, cold and small ------------------------------------
def chill(img, amount=0.55):
    r, g, b, a = img.split()
    r = r.point(lambda v: int(v * (1 - 0.45 * amount)))
    g = g.point(lambda v: int(v * (1 - 0.10 * amount) + 30 * amount))
    b = b.point(lambda v: min(255, int(v + 150 * amount)))
    return Image.merge("RGBA", (r, g, b, a))

hurt = []
for i in range(4):
    p = i / 4.0
    f = flame_warp(BASE, p * 3.0, amp=0.19, waves=3.1, sx=0.86 - 0.05 * i, sy=0.82 - 0.06 * i)
    f = glow(f, HI * 0.05, (90, 170, 255, 255), 0.5)
    hurt.append(chill(down(f, CELL, CELL)))

sheet(idle, CELL, CELL).save(f"{OUT}/ember_idle.png")
sheet(run, CELL, CELL).save(f"{OUT}/ember_run.png")
sheet(air, CELL, CELL).save(f"{OUT}/ember_air.png")
sheet(hurt, CELL, CELL).save(f"{OUT}/ember_hurt.png")

SCRATCH = os.environ.get("TMPDIR", "/tmp")
print("player sheets written")
