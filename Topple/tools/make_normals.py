#!/usr/bin/env python3
"""Makes assets/textures/pieces_n.png: a normal map for the packed pieces.

Kenney's pieces are flat drawings. Lit by the game's 2D lights they want to
know which way each texel faces, so this reads the atlas and its sheet and
gives every frame a rounded rim (from how far a texel is from the frame's
edge) and a little relief from the drawing itself (its darker lines sit
lower). Run after the atlas is packed. Needs Pillow and numpy.
"""
import json
import os

import numpy as np
from PIL import Image

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
T = os.path.join(PROJECT, "assets", "textures")
RIM = 7          # texels the rounded edge is wide
RELIEF = 0.55    # how much the drawing's own light and dark count
STRENGTH = 2.2


def blur(a, n):
    for _ in range(n):
        p = np.pad(a, 1, mode="edge")
        a = (p[:-2, 1:-1] + p[2:, 1:-1] + p[1:-1, :-2] + p[1:-1, 2:] + 4 * p[1:-1, 1:-1]) / 8.0
    return a


def frame_normals(rgba):
    alpha = rgba[..., 3] / 255.0
    solid = alpha > 0.5
    # How many texels in from the edge, up to RIM: wear the shape away a
    # texel at a time and count how long each one lasts.
    depth = np.zeros(alpha.shape)
    left = np.pad(solid, 1, mode="constant")
    for _ in range(RIM):
        left = left[1:-1, 1:-1] & left[:-2, 1:-1] & left[2:, 1:-1] & left[1:-1, :-2] & left[1:-1, 2:]
        depth += left
        left = np.pad(left, 1, mode="constant")
    rim = np.sin(np.clip(depth / RIM, 0, 1) * np.pi / 2)
    lum = (rgba[..., :3].astype(float).mean(axis=2) / 255.0)
    inner = blur(lum, 1)
    height = blur(rim * RIM * 0.35 + (inner - inner[solid].mean() if solid.any() else 0) * RELIEF * RIM, 1)
    gy, gx = np.gradient(height)
    nx, ny, nz = -gx * STRENGTH, gy * STRENGTH, np.ones(alpha.shape)
    length = np.sqrt(nx * nx + ny * ny + nz * nz)
    out = np.stack([nx / length, ny / length, nz / length], axis=2)
    out[~solid] = (0, 0, 1)
    return out


def main():
    atlas = np.asarray(Image.open(os.path.join(T, "pieces.png")).convert("RGBA"))
    sheet = json.load(open(os.path.join(T, "pieces.p3ds")))
    normals = np.zeros(atlas.shape[:2] + (3,))
    normals[...] = (0, 0, 1)
    for frame in sheet["frames"]:
        x, y, w, h = frame["rect"]
        normals[y:y + h, x:x + w] = frame_normals(atlas[y:y + h, x:x + w])
    rgb = ((normals * 0.5 + 0.5) * 255).round().astype(np.uint8)
    Image.fromarray(rgb).save(os.path.join(T, "pieces_n.png"))
    print("wrote assets/textures/pieces_n.png", rgb.shape[1], "x", rgb.shape[0])


if __name__ == "__main__":
    main()
