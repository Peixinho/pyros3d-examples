#!/usr/bin/env python3
"""Picks what Topple uses out of Kenney's packs and lays it out for the project.

    python3 tools/make_assets.py /path/to/unzipped/kenney

where that folder holds the unzipped packs (all CC0, from kenney.nl/assets):

    physics-assets/  background-elements/  particle-pack/  ui-pack/
    impact-sounds/   interface-sounds/     sci-fi-sounds/  music-jingles/
    digital-audio/   rpg-audio/

It writes loose art into art/ (packed into atlases by tools/build_levels.py,
through the editor), textures the game loads by name into assets/textures/,
and sounds into assets/sounds/ (as .wav - needs ffmpeg). Needs Pillow.
Nothing is drawn here: every pixel is Kenney's. The script only chooses,
renames and resizes.
"""
import glob
import os
import shutil
import subprocess
import sys

from PIL import Image

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = sys.argv[1] if len(sys.argv) > 1 else sys.exit(__doc__)


def src(*parts):
    path = os.path.join(SRC, *parts)
    if "*" not in path and not os.path.exists(path):
        sys.exit("missing: " + path)
    return path


def out(*parts):
    path = os.path.join(PROJECT, *parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    return path


def copy(a, b):
    shutil.copyfile(a, b)


# ----- the pieces --------------------------------------------------------------
# Every material comes as the same shapes in the same order: per size, the
# solid ones sorted by number are whole, chipped, cracked - a block's three
# states of damage.
RECTS = {"sq": (70, 70), "block": (140, 70), "plank": (220, 70), "big": (140, 140), "slab": (220, 140),
         "post": (70, 220), "pillar": (70, 140)}
# What is not a rectangle, by file number: whole, chipped, cracked.
ROUND = {"wood": {"ball": (0, 6, 44), "tri": (54, 5, 43)},
         "stone": {"ball": (1, 7, 45), "tri": (0, 6, 44)},
         "metal": {"ball": (1, 7, 45), "tri": (0, 6, 44)},
         "tnt": {"ball": (1, 7, 45)}}
FOLDER = {"wood": "Wood", "stone": "Stone", "glass": "Glass", "metal": "Metal", "tnt": "Explosive"}


def pieces():
    n = 0
    for mat, folder in FOLDER.items():
        files = sorted(glob.glob(src("physics-assets", "PNG", folder + " elements", "*.png")))
        by_size = {}
        for f in files:
            by_size.setdefault(Image.open(f).size, []).append(f)
        for shape, size in RECTS.items():
            if mat == "tnt" and shape != "sq":
                continue
            # A size is shared with other shapes (a square's with balls,
            # rings and corners; a block's with triangles): the solid
            # rectangles are the three that fill it most. Glass is
            # see-through and fills less, but still more than its frames.
            def fill(f):
                alpha = Image.open(f).convert("RGBA").getchannel("A").histogram()
                return sum(alpha[64:]) / float(size[0] * size[1])
            picks = sorted(sorted(by_size[size], key=fill, reverse=True)[:3])
            for state, f in enumerate(picks):
                copy(f, out("art", "pieces", "%s_%s_%d.png" % (mat, shape, state)))
                n += 1
        prefix = "element" + folder
        for shape, numbers in ROUND.get(mat, {}).items():
            for state, number in enumerate(numbers):
                copy(src("physics-assets", "PNG", folder + " elements", "%s%03d.png" % (prefix, number)),
                     out("art", "pieces", "%s_%s_%d.png" % (mat, shape, state)))
                n += 1
    for mat in ("Wood", "Stone", "Glass"):
        for i in (1, 2, 3):
            copy(src("physics-assets", "PNG", "Debris", "debris%s_%d.png" % (mat, i)),
                 out("art", "pieces", "debris_%s_%d.png" % (mat.lower(), i)))
    for i, number in enumerate((46, 47, 48)):
        copy(src("physics-assets", "PNG", "Metal elements", "elementMetal%03d.png" % number),
             out("art", "pieces", "debris_metal_%d.png" % (i + 1)))
    for f in glob.glob(src("physics-assets", "PNG", "Aliens", "*.png")):
        name = os.path.basename(f).replace("alien", "alien_").lower()
        copy(f, out("art", "pieces", name))
    for name in ("starGold", "starSilver", "starBronze", "starDiamond", "coinGold", "coinSilver", "coinBronze",
                 "coinDiamond", "flagBlue", "flagGreen", "flagRed", "flagYellow", "bush", "cactus", "rock", "frozenBush"):
        copy(src("physics-assets", "PNG", "Other", name + ".png"), out("art", "pieces", name.lower() + ".png"))
    return n


# ----- ground, sky, scenery ------------------------------------------------------
def scenery():
    for name in ("grass", "dirt", "sand", "snow"):
        tile = src("physics-assets", "PNG", "Other", name + ".png")
        copy(tile, out("assets", "textures", "ground_%s.png" % name))
        # What is under the top row: the colour the tile ends on, as a small
        # flat picture to fill with. (The tile itself has a dark line along
        # its foot, which stacked would be a line every unit.)
        r, g, b, _ = Image.open(tile).convert("RGBA").getpixel((35, 58))
        Image.new("RGB", (8, 8), (r, g, b)).save(out("assets", "textures", "ground_%s_fill.png" % name))
    for name in ("colored_grass", "colored_desert", "colored_shroom", "colored_land",
                 "blue_grass", "blue_desert", "blue_shroom", "blue_land"):
        copy(src("physics-assets", "PNG", "Backgrounds", name + ".png"), out("assets", "textures", "bg_%s.png" % name))
    keep = ["cloud%d" % i for i in range(1, 10)] + ["tree%02d" % i for i in range(1, 36)]
    keep += ["castle_grey", "castle_beige", "castle_wall", "tower_grey", "tower_beige", "fence", "fence_piece",
             "house_grey_front", "house_grey_side", "house_beige_front", "house_beige_side", "moon_full", "moon_half",
             "sun", "piramid", "temple"] + ["grass%d" % i for i in range(1, 7)]
    for name in keep:
        copy(src("background-elements", "PNG", name + ".png"), out("art", "scenery", name + ".png"))
        # The same piece as it looks a long way off: washed towards the sky.
        # A tint can only darken, so the far rows of scenery get their own
        # pictures ("far_" + name in the same atlas).
        im = Image.open(src("background-elements", "PNG", name + ".png")).convert("RGBA")
        haze = Image.new("RGBA", im.size, (214, 240, 244, 255))
        far = Image.blend(im, haze, 0.62)
        far.putalpha(im.getchannel("A"))
        far.save(out("art", "scenery", "far_" + name + ".png"))


# ----- particles: white shapes on clear, 512 px in the pack, 128 here ---------------
FX = {"smoke_01": "smoke_a", "smoke_04": "smoke_b", "smoke_07": "smoke_c", "circle_05": "soft", "star_05": "glow",
      "star_06": "sparkle", "star_08": "glint", "spark_01": "bolt", "scorch_01": "burst", "fire_01": "fire",
      "flare_01": "flare", "light_01": "ring", "circle_02": "shock", "dirt_01": "dirt", "magic_05": "twinkle",
      "trace_01": "streak", "flame_05": "flame", "symbol_01": "heart"}


def particles():
    for name, to in FX.items():
        im = Image.open(src("particle-pack", "PNG (Transparent)", name + ".png")).convert("RGBA")
        im.resize((128, 128), Image.LANCZOS).save(out("assets", "textures", "fx", to + ".png"))


# ----- interface ---------------------------------------------------------------------
def interface():
    def ui(colour, name, to):
        copy(src("ui-pack", "PNG", colour, "Default", name + ".png"), out("assets", "textures", "ui", to + ".png"))
    for colour in ("Blue", "Green", "Red", "Yellow", "Grey"):
        ui(colour, "button_rectangle_depth_gloss", "button_" + colour.lower())
        ui(colour, "button_square_depth_gloss", "square_" + colour.lower())
        ui(colour, "button_round_depth_gloss", "round_" + colour.lower())
    ui("Grey", "button_rectangle_depth_flat", "panel")
    ui("Yellow", "star", "star")
    ui("Grey", "star_outline_depth", "star_empty")
    for name in ("icon_play_light", "icon_repeat_light", "icon_arrow_up_light", "icon_arrow_down_light"):
        copy(src("ui-pack", "PNG", "Extra", "Default", name + ".png"), out("assets", "textures", "ui", name[5:] + ".png"))
    copy(src("ui-pack", "Font", "Kenney Future.ttf"), out("assets", "fonts", "future.ttf"))
    copy(src("ui-pack", "Font", "Kenney Future Narrow.ttf"), out("assets", "fonts", "future_narrow.ttf"))


# ----- sounds ---------------------------------------------------------------------------
SOUNDS = {
    "wood_1": ("impact-sounds", "impactWood_light_000"), "wood_2": ("impact-sounds", "impactWood_medium_001"),
    "wood_3": ("impact-sounds", "impactWood_heavy_002"), "wood_break": ("impact-sounds", "impactPlank_medium_003"),
    "glass_1": ("impact-sounds", "impactGlass_light_001"), "glass_2": ("impact-sounds", "impactGlass_medium_002"),
    "glass_break": ("impact-sounds", "impactGlass_heavy_003"), "glass_break2": ("impact-sounds", "impactGlass_heavy_001"),
    "stone_1": ("impact-sounds", "impactMining_001"), "stone_2": ("impact-sounds", "impactMining_003"),
    "stone_break": ("impact-sounds", "impactPlate_heavy_002"),
    "metal_1": ("impact-sounds", "impactMetal_light_002"), "metal_2": ("impact-sounds", "impactMetal_medium_001"),
    "metal_3": ("impact-sounds", "impactMetal_heavy_003"), "metal_break": ("impact-sounds", "impactPlate_heavy_004"),
    "thud_1": ("impact-sounds", "impactSoft_medium_001"), "thud_2": ("impact-sounds", "impactSoft_heavy_002"),
    "pop": ("impact-sounds", "impactPunch_medium_002"), "bell": ("impact-sounds", "impactBell_heavy_001"),
    "boom_1": ("sci-fi-sounds", "explosionCrunch_000"), "boom_2": ("sci-fi-sounds", "explosionCrunch_002"),
    "boom_low": ("sci-fi-sounds", "lowFrequency_explosion_000"),
    "click": ("interface-sounds", "click_002"), "select": ("interface-sounds", "select_003"),
    "confirm": ("interface-sounds", "confirmation_002"), "back": ("interface-sounds", "back_002"),
    "open": ("interface-sounds", "open_002"), "pluck": ("interface-sounds", "pluck_001"),
    "tick": ("interface-sounds", "tick_002"), "drop": ("interface-sounds", "drop_003"),
    "stretch": ("rpg-audio", "creak1"), "whoosh": ("rpg-audio", "drawKnife2"), "cloth": ("rpg-audio", "cloth2"),
    "coins": ("rpg-audio", "handleCoins"),
    "star_1": ("digital-audio", "powerUp2"), "star_2": ("digital-audio", "powerUp5"), "star_3": ("digital-audio", "powerUp8"),
    "squeak": ("digital-audio", "pepSound3"), "ouch": ("digital-audio", "phaseJump2"),
    "win": ("music-jingles", "Pizzicato jingles", "jingles_PIZZI10"), "lose": ("music-jingles", "Pizzicato jingles", "jingles_PIZZI03"),
    "start": ("music-jingles", "Pizzicato jingles", "jingles_PIZZI07"),
}


def sounds():
    missing = []
    for to, where in SOUNDS.items():
        pack, name = where[0], where[-1]
        mid = ("Audio",) + tuple(where[1:-1])
        path = os.path.join(SRC, pack, *mid, name + ".ogg")
        if not os.path.exists(path):
            missing.append(path)
            continue
        subprocess.check_call(["ffmpeg", "-y", "-loglevel", "error", "-i", path, "-ac", "1", "-ar", "44100",
                               "-c:a", "pcm_s16le", out("assets", "sounds", to + ".wav")])
    return missing


if __name__ == "__main__":
    print("pieces:", pieces())
    scenery()
    particles()
    interface()
    missing = sounds()
    for m in missing:
        print("no such sound:", m)
    print("done")
