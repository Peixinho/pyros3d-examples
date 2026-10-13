#!/usr/bin/env python3
"""A motocross track from a list of obstacles, as the points its ground is drawn from.

    python3 tools/make_track.py <work> [track numbers...]

Writes <work>/tracks/track<n>.json: the outline's points (what the scene's
Extrusion2D is given - few enough to drag about in the editor afterwards) and
where things are along it. A track is a starting point: once it is in a scene
it is edited there, point by point. Lengths are metres.
"""
import json
import math
import os
import sys

WORK = sys.argv[1] if len(sys.argv) > 1 else sys.exit(__doc__)
WHICH = [int(a) for a in sys.argv[2:]]

DEPTH = 7.0            # how wide the dirt is, across
BASE = -6.0            # how far down its cut face goes
LANES = 4

# ----- obstacles: each adds height over a stretch -------------------------------------
def smooth(t): t = max(0.0, min(1.0, t)); return t * t * (3 - 2 * t)

def roller(x, at, length, height):                 # one rounded hump
    t = (x - at) / length
    return height * 0.5 * (1 - math.cos(2 * math.pi * t)) if 0 <= t <= 1 else 0.0

def table(x, at, up, top, down, height):           # a tabletop: face, flat, landing
    if x < at or x > at + up + top + down: return 0.0
    if x < at + up: return height * smooth((x - at) / up)
    if x < at + up + top: return height
    return height * (1 - smooth((x - at - up - top) / down))

def kicker(x, at, up, height, drop=1.2):           # a launch ramp with a steep back
    if x < at or x > at + up + drop: return 0.0
    if x < at + up:
        t = (x - at) / up
        return height * t * t
    return height * (1 - smooth((x - at - up) / drop))

def landing(x, at, drop, down, height):            # the hill a jump comes down onto
    if x < at or x > at + drop + down: return 0.0
    if x < at + drop: return height * smooth((x - at) / drop)
    return height * (1 - smooth((x - at - drop) / down))

def step(x, at, up, height):                       # the ground rises and stays risen
    return height * smooth((x - at) / up)

# A track is (name, length, [obstacle...]); an obstacle is (kind, x, ...).
TRACKS = {
    1: ("Rookie Park", 420, [
        ("roller", 26, 10, 1.2), ("roller", 40, 10, 1.2),
        ("kicker", 60, 9, 2.8), ("landing", 75, 9, 14, 2.6),
        ("whoops", 108, 5, 3.6, 0.5),
        ("table", 136, 9, 12, 12, 3.2),
        ("kicker", 182, 10, 3.4), ("landing", 200, 9, 16, 3),
        ("roller", 236, 12, 1.6),
        ("kicker", 262, 10, 3.8), ("landing", 282, 10, 18, 3.4),
        ("whoops", 320, 5, 3.6, 0.5),
        ("table", 348, 9, 10, 12, 3.0),
        ("roller", 392, 10, 1.2),
    ]),
    2: ("Rhythm Section", 500, [
        ("roller", 24, 8, 1.3), ("roller", 35, 8, 1.3), ("roller", 46, 8, 1.3),
        ("kicker", 66, 9, 3.2), ("landing", 82, 9, 15, 3),
        ("kicker", 116, 9, 3.2), ("landing", 132, 9, 15, 3),
        ("whoops", 166, 8, 3.4, 0.55),
        ("step", 204, 12, 3.0),
        ("kicker", 228, 10, 3.6), ("landing", 247, 10, 18, 3.6),
        ("stepdown", 286, 14, 3.0),
        ("table", 312, 10, 14, 13, 3.8),
        ("kicker", 362, 10, 4.2), ("landing", 383, 10, 20, 3.8),
        ("whoops", 424, 6, 3.6, 0.55),
        ("kicker", 456, 9, 3.0), ("landing", 471, 9, 14, 2.6),
    ]),
    3: ("Big Air", 600, [
        ("roller", 24, 12, 1.6),
        ("kicker", 48, 12, 5.0), ("landing", 73, 11, 24, 4.6),
        ("whoops", 118, 6, 3.6, 0.6),
        ("table", 150, 11, 16, 15, 4.6),
        ("kicker", 206, 12, 5.6), ("landing", 233, 11, 26, 5.2),
        ("step", 282, 14, 4.0),
        ("kicker", 310, 11, 4.6), ("landing", 333, 11, 22, 4.6),
        ("stepdown", 378, 16, 4.0),
        ("roller", 404, 9, 1.5), ("roller", 416, 9, 1.5), ("roller", 428, 9, 1.5),
        ("kicker", 452, 13, 6.4), ("landing", 483, 12, 30, 6),
        ("table", 536, 10, 12, 14, 3.6),
    ]),
}

def height(obstacles, x):
    h = 0.0
    for o in obstacles:
        k = o[0]
        if k == "roller": h += roller(x, o[1], o[2], o[3])
        elif k == "table": h += table(x, o[1], o[2], o[3], o[4], o[5])
        elif k == "kicker": h += kicker(x, o[1], o[2], o[3])
        elif k == "landing": h += landing(x, o[1], o[2], o[3], o[4])
        elif k == "step": h += step(x, o[1], o[2], o[3])
        elif k == "stepdown": h -= step(x, o[1], o[2], o[3])
        elif k == "whoops":
            for i in range(o[2]): h += roller(x, o[1] + i * o[3], o[3], o[4])
    return h


def outline(obstacles, x0, x1):
    """The profile as points an editor can hold: one every metre and a half where it
    curves, and only the two ends of anything flat."""
    step = 1.5
    xs = [x0 + i * step for i in range(int((x1 - x0) / step) + 1)]
    if xs[-1] < x1: xs.append(x1)
    pts = [[x, height(obstacles, x)] for x in xs]
    keep = [pts[0]]
    for i in range(1, len(pts) - 1):
        a, b, c = keep[-1], pts[i], pts[i + 1]
        # (on the line from the last kept point to the next: it adds nothing)
        t = (b[0] - a[0]) / (c[0] - a[0])
        if abs(a[1] + (c[1] - a[1]) * t - b[1]) > 0.004 or b[0] - a[0] > 12.0:
            keep.append(b)
    keep.append(pts[-1])
    return [[round(x, 3), round(y, 3)] for x, y in keep]


def build(number):
    name, length, obstacles = TRACKS[number]
    x0, x1 = -30.0, length + 40.0
    pts = outline(obstacles, x0, x1)
    os.makedirs(os.path.join(WORK, "tracks"), exist_ok=True)
    json.dump({"name": name, "length": length, "depth": DEPTH, "lanes": LANES, "base": BASE, "points": pts,
               "x0": x0, "x1": x1, "obstacles": [list(o) for o in obstacles]},
              open(os.path.join(WORK, "tracks", "track%d.json" % number), "w"))
    print("TRACK", number, name, len(pts), "points")


for number in (WHICH or sorted(TRACKS)):
    build(number)
