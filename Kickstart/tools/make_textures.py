#!/usr/bin/env python3
"""The flat pictures the stadium wears: sponsor boards, the finish banner, the scoreboard.
Words set in Kenney Future (CC0), on plain colours. Needs Pillow.

    python3 tools/make_textures.py
"""
import os
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(HERE, "art", "textures")
FONT = os.path.join(HERE, "art", "fonts", "future.ttf")


def board(name, words, back, ink, size=(512, 128)):
    im = Image.new("RGB", size, back)
    d = ImageDraw.Draw(im)
    f = ImageFont.truetype(FONT, int(size[1] * 0.50))
    w = d.textlength(words, font=f)
    while w > size[0] * 0.9:
        f = ImageFont.truetype(FONT, f.size - 2)
        w = d.textlength(words, font=f)
    box = d.textbbox((0, 0), words, font=f)
    d.text(((size[0] - w) / 2, (size[1] - (box[3] - box[1])) / 2 - box[1]), words, font=f, fill=ink)
    d.rectangle([0, 0, size[0] - 1, size[1] - 1], outline=ink, width=4)
    im.save(os.path.join(OUT, name + ".png"))


def chequer(name, words=None):
    im = Image.new("RGB", (1024, 128), (255, 255, 255))
    d = ImageDraw.Draw(im)
    for x in range(0, 1024, 32):
        for y in range(0, 128, 32):
            if (x // 32 + y // 32) % 2 == 0:
                d.rectangle([x, y, x + 31, y + 31], fill=(12, 12, 14))
    if words:
        f = ImageFont.truetype(FONT, 72)
        w = d.textlength(words, font=f)
        d.rectangle([(1024 - w) / 2 - 24, 16, (1024 + w) / 2 + 24, 112], fill=(200, 30, 24))
        d.text(((1024 - w) / 2, 26), words, font=f, fill=(255, 255, 255))
    im.save(os.path.join(OUT, name + ".png"))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    board("board_0", "KICKSTART", (200, 30, 24), (255, 255, 255))
    board("board_1", "PYROS3D", (18, 28, 60), (255, 200, 40))
    board("board_2", "MUD & CO", (250, 200, 30), (20, 20, 24))
    board("board_3", "BRAAP!", (20, 130, 70), (255, 255, 255))
    board("board_4", "DIRT CUP", (240, 240, 236), (200, 30, 24))
    board("scoreboard", "KICKSTART", (10, 12, 18), (255, 170, 30), size=(512, 256))
    chequer("finish", "FINISH")
    chequer("start", "START")
    print("textures written to", OUT)
