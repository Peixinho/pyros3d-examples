#!/usr/bin/env python3
"""Picks what Hopper uses out of two public-domain packs and lays it out.

    python3 tools/make_assets.py /path/to/kenney /path/to/music

    /path/to/kenney   holds the unzipped packs (kenney.nl/assets, CC0):
                      new-platformer-pack/  interface-sounds/  music-jingles/
    /path/to/music    holds Juhani Junkala's "Chiptune Adventures" (OGG),
                      from opengameart.org/content/4-chiptunes-adventure (CC0)

It writes
    assets/textures/tiles.png      one picture of every tile, 64 px each,
                                   and tools/tiles.json saying which is where
    art/characters, art/enemies, art/things   loose sprites, packed into
                                   atlases by tools/build_game.py
    assets/textures/bg_*.png       the backdrops
    assets/sounds/*.ogg, assets/music/*.ogg
Nothing is drawn here: every pixel and every note is theirs. Needs Pillow.
"""
import json
import os
import shutil
import sys

from PIL import Image, ImageOps

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if len(sys.argv) < 3:
    sys.exit(__doc__)
KENNEY, MUSIC = sys.argv[1], sys.argv[2]
PACK = os.path.join(KENNEY, "new-platformer-pack")
TILE = 64
COLUMNS = 16


def tile(name):
    return Image.open(os.path.join(PACK, "Sprites", "Tiles", "Default", name + ".png")).convert("RGBA")


def out(*parts):
    path = os.path.join(PROJECT, *parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    return path


# ----- the tile set ------------------------------------------------------------
# A terrain is sixteen tiles in a row, one for each way its four neighbours
# can be the same terrain or not: bit 0 the one above, 1 to the right, 2
# below, 3 to the left. The engine picks among them as a level is painted,
# and the pack has a piece for every one.
TERRAINS = ["grass", "sand", "snow", "stone", "purple", "dirt"]
PIECE = {
    0: "block", 1: "vertical_bottom", 2: "horizontal_left", 4: "vertical_top", 8: "horizontal_right",
    5: "vertical_middle", 10: "horizontal_middle",
    6: "block_top_left", 12: "block_top_right", 3: "block_bottom_left", 9: "block_bottom_right",
    14: "block_top", 7: "block_left", 13: "block_right", 11: "block_bottom", 15: "block_center",
}
# After the terrains: everything else a level is painted with.
EXTRA = ["bridge", "bridge_logs", "spikes", "ladder_top", "ladder_middle", "ladder_bottom", "water_top", "water",
         "lava_top", "lava", "block_plank", "bricks_brown", "bricks_grey", "block_empty", "brick_brown", "brick_grey"]


def tileset():
    names = []
    for terrain in TERRAINS:
        for mask in range(16):
            names.append(("terrain_%s_%s" % (terrain, PIECE[mask]), False, "%s_%d" % (terrain, mask)))
    for name in EXTRA:
        names.append((name, False, name))
    # A ramp, and the same ramp the other way (the pack draws one).
    for terrain in TERRAINS:
        names.append(("terrain_%s_ramp_short_b" % terrain, False, "%s_ramp_left" % terrain))
        names.append(("terrain_%s_ramp_short_b" % terrain, True, "%s_ramp_right" % terrain))
    rows = (len(names) + COLUMNS - 1) // COLUMNS
    sheet = Image.new("RGBA", (COLUMNS * TILE, rows * TILE), (0, 0, 0, 0))
    index = {}
    for i, (name, flip, key) in enumerate(names):
        im = tile(name)
        if flip:
            im = ImageOps.mirror(im)
        sheet.paste(im, ((i % COLUMNS) * TILE, (i // COLUMNS) * TILE))
        index[key] = i
    sheet.save(out("assets", "textures", "tiles.png"))
    json.dump({"columns": COLUMNS, "tile": TILE, "terrains": TERRAINS, "index": index},
              open(out("tools", "tiles.json"), "w"), indent=1)
    return len(names)


# ----- sprites --------------------------------------------------------------------
THINGS = ["coin_gold", "coin_gold_side", "gem_blue", "gem_green", "gem_red", "gem_yellow", "heart", "star",
          "flag_green_a", "flag_green_b", "flag_yellow_a", "flag_yellow_b", "flag_off", "key_yellow", "lock_yellow",
          "spring", "spring_out", "torch_on_a", "torch_on_b", "torch_off", "sign", "sign_right", "sign_exit", "bush",
          "cactus", "rock", "mushroom_red", "mushroom_brown", "grass", "grass_purple", "fence", "snow", "bridge_logs",
          "block_plank", "block_coin", "block_empty", "chain", "weight", "door_closed", "door_closed_top", "door_open",
          "door_open_top", "hud_heart", "hud_heart_empty", "hud_coin", "hud_key_yellow", "hud_player_green",
          "hill", "hill_top", "hill_top_smile", "window", "fireball", "bomb"]
ENEMIES = ["slime_normal_walk_a", "slime_normal_walk_b", "slime_normal_flat", "slime_normal_rest",
           "slime_fire_walk_a", "slime_fire_walk_b", "slime_fire_flat", "snail_walk_a", "snail_walk_b", "snail_shell",
           "mouse_walk_a", "mouse_walk_b", "mouse_rest", "bee_a", "bee_b", "bee_rest", "fly_a", "fly_b", "fly_rest",
           "frog_idle", "frog_jump", "frog_rest", "ladybug_walk_a", "ladybug_walk_b", "ladybug_rest", "saw_a", "saw_b",
           "block_idle", "block_fall", "block_rest", "worm_normal_move_a", "worm_normal_move_b"]
POSES = ["idle", "walk_a", "walk_b", "jump", "hit", "duck", "climb_a", "climb_b", "front"]


def sprites():
    for name in THINGS:
        shutil.copyfile(os.path.join(PACK, "Sprites", "Tiles", "Default", name + ".png"), out("art", "things", name + ".png"))
    for name in ENEMIES:
        shutil.copyfile(os.path.join(PACK, "Sprites", "Enemies", "Default", name + ".png"), out("art", "enemies", name + ".png"))
    for colour in ("green", "pink", "yellow", "purple", "beige"):
        for pose in POSES:
            shutil.copyfile(os.path.join(PACK, "Sprites", "Characters", "Default", "character_%s_%s.png" % (colour, pose)),
                            out("art", "characters", "%s_%s.png" % (colour, pose)))
    for name in ("background_solid_sky", "background_clouds", "background_color_hills", "background_color_trees",
                 "background_color_desert", "background_color_mushrooms", "background_fade_hills", "background_fade_trees",
                 "background_fade_desert", "background_fade_mushrooms", "background_solid_dirt", "background_solid_grass",
                 "background_solid_sand", "background_solid_cloud"):
        shutil.copyfile(os.path.join(PACK, "Sprites", "Backgrounds", "Default", name + ".png"),
                        out("assets", "textures", name.replace("background_", "bg_") + ".png"))
    # the interface's pieces, as loose pictures a canvas names
    for name in ("hud_heart", "hud_heart_empty", "hud_coin", "hud_key_yellow", "star", "gem_blue"):
        shutil.copyfile(os.path.join(PACK, "Sprites", "Tiles", "Default", name + ".png"), out("assets", "textures", "ui", name + ".png"))
    ui = os.path.join(KENNEY, "ui-pack", "PNG")
    for colour in ("Blue", "Green", "Red", "Yellow", "Grey"):
        shutil.copyfile(os.path.join(ui, colour, "Default", "button_rectangle_depth_gloss.png"),
                        out("assets", "textures", "ui", "button_%s.png" % colour.lower()))
        shutil.copyfile(os.path.join(ui, colour, "Default", "button_round_depth_gloss.png"),
                        out("assets", "textures", "ui", "round_%s.png" % colour.lower()))
    shutil.copyfile(os.path.join(ui, "Grey", "Default", "button_rectangle_depth_flat.png"), out("assets", "textures", "ui", "panel.png"))
    shutil.copyfile(os.path.join(ui, "Grey", "Default", "star_outline_depth.png"), out("assets", "textures", "ui", "star_empty.png"))
    for name in ("icon_arrow_up_light", "icon_repeat_light", "icon_play_light"):
        shutil.copyfile(os.path.join(ui, "Extra", "Default", name + ".png"), out("assets", "textures", "ui", name[5:] + ".png"))
    shutil.copyfile(os.path.join(KENNEY, "ui-pack", "Font", "Kenney Future Narrow.ttf"), out("assets", "fonts", "future_narrow.ttf"))
    shutil.copyfile(os.path.join(KENNEY, "ui-pack", "Font", "Kenney Future.ttf"), out("assets", "fonts", "future.ttf"))
    soft = Image.open(os.path.join(KENNEY, "particle-pack", "PNG (Transparent)", "circle_05.png")).convert("RGBA")
    soft.resize((64, 64), Image.LANCZOS).save(out("assets", "textures", "fx", "soft.png"))
    spark = Image.open(os.path.join(KENNEY, "particle-pack", "PNG (Transparent)", "star_06.png")).convert("RGBA")
    spark.resize((64, 64), Image.LANCZOS).save(out("assets", "textures", "fx", "sparkle.png"))
    glow = Image.open(os.path.join(KENNEY, "particle-pack", "PNG (Transparent)", "star_05.png")).convert("RGBA")
    glow.resize((128, 128), Image.LANCZOS).save(out("assets", "textures", "fx", "glow.png"))


# ----- sound: .ogg as it comes (the engine decodes it) --------------------------------
def sounds():
    for name in ("bump", "coin", "disappear", "gem", "hurt", "jump-high", "jump", "magic", "select", "throw"):
        shutil.copyfile(os.path.join(PACK, "Sounds", "sfx_%s.ogg" % name), out("assets", "sounds", name.replace("-", "_") + ".ogg"))
    for name, to in (("click_002", "click"), ("confirmation_002", "confirm"), ("back_002", "back")):
        shutil.copyfile(os.path.join(KENNEY, "interface-sounds", "Audio", name + ".ogg"), out("assets", "sounds", to + ".ogg"))
    shutil.copyfile(os.path.join(KENNEY, "music-jingles", "Audio", "Pizzicato jingles", "jingles_PIZZI10.ogg"), out("assets", "sounds", "win.ogg"))
    tracks = {"1. Stage 1": "stage_1", "2. Stage 2": "stage_2", "4. Stage Select": "menu"}
    found = 0
    for root, _, files in os.walk(MUSIC):
        for f in files:
            for key, to in tracks.items():
                if f.endswith(key + ".ogg"):
                    shutil.copyfile(os.path.join(root, f), out("assets", "music", to + ".ogg"))
                    found += 1
    return found


if __name__ == "__main__":
    print("tiles:", tileset())
    sprites()
    print("music tracks:", sounds())
