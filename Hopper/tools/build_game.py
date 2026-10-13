#!/usr/bin/env python3
"""Builds Hopper by driving a running PyrosBuilder.

    1. python3 tools/make_assets.py /path/to/kenney /path/to/music   (once)
    2. start PyrosBuilder
    3. python3 tools/build_game.py                 (everything)
       python3 tools/build_game.py stages          (the title and the five worlds)
       python3 tools/build_game.py levels          (the fifty level prefabs)
       python3 tools/build_game.py levels 11 20    (some of them)

A world is a scene: its sky, the hero, the interface, its music
(scenes/World1..5.json). A level is a prefab (assets/prefabs/H001..H050):
a tile map painted by TERRAIN - the map picks each corner and edge piece -
a second, one-way, for the bridges, and what stands on them. The game puts
a level's prefab into its world's scene. All of it is made with the commands
the editor's own panels issue, and opens in the editor.

A level is drawn here from pieces a dozen columns wide (CHUNKS, below), each
a picture in text; which pieces, and in what order, comes from the level's
number. The rules are in assets/lua/hopper/game.lua and read a level by its
objects' names.
"""
import json
import os
import random
import socket
import sys

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
T = "assets/textures/"
TILES = json.load(open(os.path.join(PROJECT, "tools", "tiles.json")))
INDEX = TILES["index"]
TERRAINS = TILES["terrains"]
PPU = 64.0


def endpoint():
    tmp = os.environ.get("TMPDIR", "/tmp")
    for name in ("pyros3d-driver.json", "pyros3d-editor.json"):
        path = os.path.join(tmp, name)
        if os.path.exists(path):
            return json.load(open(path))
    sys.exit("PyrosBuilder is not running (no pyros3d-editor.json in $TMPDIR)")


CFG = endpoint()


def call(cmd, **args):
    s = socket.create_connection(("127.0.0.1", CFG["port"]), timeout=240)
    s.sendall((json.dumps({"id": 1, "token": CFG["token"], "cmd": cmd, "args": args}) + "\n").encode())
    buf = b""
    while not buf.endswith(b"\n"):
        chunk = s.recv(1 << 20)
        if not chunk:
            break
        buf += chunk
    s.close()
    reply = json.loads(buf.decode())
    result = reply.get("result", reply)
    if reply.get("ok") is False or (isinstance(result, dict) and result.get("ok") is False):
        sys.exit("%s failed: %s\n  args: %s" % (cmd, result.get("error") if isinstance(result, dict) else result, json.dumps(args)[:400]))
    return result


def sprite(name, source, at, parent, **kw):
    call("add_sprite", name=name, source=source, position=list(at), parent=parent, **kw)


# ----- the worlds --------------------------------------------------------------------
WORLDS = [
    dict(name="MEADOW", terrain="grass", bg="hills", sky=[0.80, 0.93, 1.0], ambient=[1, 1, 1], night=False, music="stage_1"),
    dict(name="DUNES", terrain="sand", bg="desert", sky=[0.86, 0.94, 1.0], ambient=[1, 1, 1], night=False, music="stage_2"),
    dict(name="CAVERN", terrain="stone", bg="trees", sky=[0.05, 0.06, 0.12], ambient=[0.22, 0.24, 0.36], night=True, music="stage_1"),
    dict(name="FROST", terrain="snow", bg="hills", sky=[0.84, 0.92, 1.0], ambient=[1, 1, 1], night=False, music="stage_2"),
    dict(name="GLOOM", terrain="purple", bg="mushrooms", sky=[0.07, 0.05, 0.14], ambient=[0.26, 0.22, 0.38], night=True, music="stage_1"),
]
PER_WORLD = 10
HEIGHT = 14          # rows in a level
GROUND = 2           # of them, under everyone's feet


def atlases():
    for folder in ("characters", "enemies", "things"):
        call("pack_sprite_atlas", folder="art/" + folder, output=T + folder, padding=4, trim=False, pixelsPerUnit=PPU,
             filter="linear", clipFps=0, overwrite=True)
    # The hero's clips: each a name the script plays. Frames are named after
    # their files, so a clip is said by name and survives a re-pack.
    for colour in ("green",):
        clips = [{"name": "idle", "frames": [colour + "_idle"], "fps": 1},
                 {"name": "walk", "frames": [colour + "_walk_a", colour + "_walk_b"], "fps": 9},
                 {"name": "jump", "frames": [colour + "_jump"], "fps": 1},
                 {"name": "hit", "frames": [colour + "_hit"], "fps": 1},
                 {"name": "duck", "frames": [colour + "_duck"], "fps": 1},
                 {"name": "climb", "frames": [colour + "_climb_a", colour + "_climb_b"], "fps": 6},
                 {"name": "front", "frames": [colour + "_front"], "fps": 1}]
    info = call("spritesheet_info", path=T + "characters.p3ds")
    names = [f["name"] for f in info["frames"]]
    for clip in clips:
        clip["frames"] = [names.index(n) for n in clip["frames"]]
    call("edit_spritesheet", path=T + "characters.p3ds", clips=clips)
    call("save_spritesheet")
    info = call("spritesheet_info", path=T + "enemies.p3ds")
    names = [f["name"] for f in info["frames"]]
    pairs = (("slime", "slime_normal_walk_a", "slime_normal_walk_b"), ("fire", "slime_fire_walk_a", "slime_fire_walk_b"),
             ("snail", "snail_walk_a", "snail_walk_b"), ("mouse", "mouse_walk_a", "mouse_walk_b"), ("bee", "bee_a", "bee_b"),
             ("fly", "fly_a", "fly_b"), ("ladybug", "ladybug_walk_a", "ladybug_walk_b"), ("saw", "saw_a", "saw_b"))
    call("edit_spritesheet", path=T + "enemies.p3ds",
         clips=[{"name": n, "frames": [names.index(a), names.index(b)], "fps": 6} for n, a, b in pairs])
    call("save_spritesheet")


def tileset():
    """The tile set: which tiles are solid, which are a terrain the map fits
    by itself, which are slopes, and what the game should know of the rest."""
    call("create_tileset", image=T + "tiles.png", tileWidth=64, tileHeight=64)
    call("open_tileset", path=T + "tiles.p3dt")
    solid = [INDEX["%s_%d" % (t, m)] for t in TERRAINS for m in range(16)]
    solid += [INDEX[n] for n in ("block_plank", "bricks_brown", "bricks_grey", "block_empty", "brick_brown", "brick_grey")]
    call("set_tile_solid", tiles=solid, solid=True)
    for t in TERRAINS:
        call("edit_tileset", terrain={"base": INDEX[t + "_0"], "name": t})
        # the pack's ramp is high on the left; the mirrored one rises to the right
        call("set_tile_shape", tiles=[INDEX[t + "_ramp_left"]], shape="slope_bl")
        call("set_tile_shape", tiles=[INDEX[t + "_ramp_right"]], shape="slope_br")
    call("edit_tileset", tag={"tiles": [INDEX["ladder_top"], INDEX["ladder_middle"], INDEX["ladder_bottom"]], "name": "ladder", "on": True})
    call("edit_tileset", tag={"tiles": [INDEX["spikes"], INDEX["lava_top"], INDEX["lava"]], "name": "hazard", "on": True})
    call("edit_tileset", tag={"tiles": [INDEX["water_top"], INDEX["water"]], "name": "water", "on": True})
    call("save_tileset")
    # What the script needs of all that, as a table it can read.
    lua = ["-- Written by tools/build_game.py from tools/tiles.json: which tile is which.", "return {"]
    for key in ("ladder_top", "ladder_middle", "ladder_bottom", "spikes", "lava_top", "lava", "water_top", "water", "bridge", "bridge_logs"):
        lua.append("    %s = %d," % (key, INDEX[key]))
    lua.append("}")
    os.makedirs(os.path.join(PROJECT, "assets", "lua", "hopper"), exist_ok=True)
    open(os.path.join(PROJECT, "assets", "lua", "hopper", "tiles.lua"), "w").write("\n".join(lua) + "\n")


# ----- interface ------------------------------------------------------------------------
def text(name, parent, value, anchor, omin, omax, size, align="center", colour=(1, 1, 1, 1), font="future_narrow"):
    call("add_object", name=name, parent=parent)
    call("add_ui", object=name, kind="text", font="assets/fonts/%s.ttf" % font)
    call("set_ui", object=name, properties={"anchorMin": anchor, "anchorMax": anchor, "offsetMin": omin, "offsetMax": omax,
                                            "text": value, "size": size, "align": align, "verticalAlign": "middle",
                                            "color": list(colour), "sdf": True})


def image(name, parent, texture, anchor, omin, omax, tint=(1, 1, 1, 1), border=None, anchor_max=None):
    call("add_object", name=name, parent=parent)
    call("add_ui", object=name, kind="image")
    props = {"anchorMin": anchor, "anchorMax": anchor_max or anchor, "offsetMin": omin, "offsetMax": omax,
             "texture": T + "ui/" + texture, "tint": list(tint)}
    if border:
        props["border"] = border
    call("set_ui", object=name, properties=props)


def button(name, parent, texture, anchor, omin, omax, border=True):
    call("add_object", name=name, parent=parent)
    call("add_ui", object=name, kind="button")
    props = {"anchorMin": anchor, "anchorMax": anchor, "offsetMin": omin, "offsetMax": omax, "texture": T + "ui/" + texture,
             "tint": [1, 1, 1, 1], "hoverTint": [1.0, 1.0, 0.85, 1], "pressedTint": [0.8, 0.8, 0.8, 1], "pressedOffset": [0, 3]}
    if border:
        props["border"] = [14, 14, 14, 18]
    call("set_ui", object=name, properties=props)


def canvas(name):
    call("add_object", name=name)
    call("add_ui", object=name, kind="canvas")
    # Fit: the whole layout is on any shape of screen - a phone is wide.
    call("set_ui", object=name, properties={"referenceWidth": 1280, "referenceHeight": 720, "scaleMode": "Fit"})


def hud(world):
    canvas("HUD")
    # Words authored "@key" are looked up in assets/lang/<language>.json by
    # the script when the scene starts.
    image("HudPlate", "HUD", "panel.png", [0, 0], [16, 14], [330, 86], (0.10, 0.13, 0.20, 0.55), [16, 16, 16, 20])
    for i in range(3):
        image("Heart%d" % (i + 1), "HudPlate", "hud_heart.png", [0, 0], [14 + i * 46, 12], [58 + i * 46, 56])
    image("CoinIcon", "HudPlate", "hud_coin.png", [0, 0], [166, 14], [206, 54])
    text("CoinCount", "HudPlate", "0", [0, 0], [208, 8], [304, 60], 34, "left", (1, 1, 1, 1))
    text("HudTitle", "HUD", world["name"], [0.5, 0], [-260, 14], [260, 56], 26, "center",
         (1, 1, 1, 0.9) if world["night"] else (0.22, 0.28, 0.40, 1))
    for i in range(3):
        image("Gem%d" % (i + 1), "HUD", "gem_blue.png", [0.5, 0], [-72 + i * 48, 56], [-24 + i * 48, 104], (1, 1, 1, 1))
    button("BtnMenu", "HUD", "round_grey.png", [1, 0], [-84, 16], [-24, 76], False)
    text("BtnMenu_Icon", "BtnMenu", "<", [0, 0], [-2, -4], [58, 56], 30, "center", (0.25, 0.28, 0.35, 1))
    button("BtnRetry", "HUD", "round_blue.png", [1, 0], [-154, 16], [-94, 76], False)
    image("BtnRetry_Icon", "BtnRetry", "repeat_light.png", [0, 0], [13, 10], [47, 44])

    # For thumbs. Left: a stick (its knob follows the thumb). Right: jump.
    # Shown by the script once a finger has touched the screen.
    image("Stick", "HUD", "round_grey.png", [0, 1], [34, -214], [214, -34], (1, 1, 1, 0.35))
    image("StickKnob", "Stick", "round_blue.png", [0.5, 0.5], [-42, -42], [42, 42], (1, 1, 1, 0.8))
    image("PadJump", "HUD", "round_green.png", [1, 1], [-204, -204], [-44, -44], (1, 1, 1, 0.6))
    image("PadJump_Icon", "PadJump", "arrow_up_light.png", [0.5, 0.5], [-40, -44], [40, 36], (1, 1, 1, 0.95))

    # The card at the end of a level. Saved showing; the script hides it.
    image("Card", "HUD", "panel.png", [0.5, 0.5], [-300, -200], [300, 200], (1, 1, 1, 0.97), [16, 16, 16, 20])
    text("CardTitle", "Card", "@level_clear", [0.5, 0], [-280, 22], [280, 78], 40, "center", (0.22, 0.26, 0.34, 1))
    for i in range(3):
        x = -150 + i * 100
        image("CardStarBack%d" % (i + 1), "Card", "star_empty.png", [0.5, 0], [x, 96], [x + 100, 192], (1, 1, 1, 0.9))
        image("CardStar%d" % (i + 1), "Card", "star.png", [0.5, 0], [x + 12, 108], [x + 88, 180])
    image("CardCoinIcon", "Card", "hud_coin.png", [0.5, 0], [-70, 204], [-22, 252])
    text("CardCoins", "Card", "0 / 0", [0.5, 0], [-16, 200], [200, 256], 34, "left", (0.22, 0.26, 0.34, 1))
    for name, texture, x, key, colour in (("CardMenu", "button_grey.png", -270, "@menu", (0.25, 0.28, 0.35, 1)),
                                           ("CardRetry", "button_blue.png", -85, "@again", (1, 1, 1, 1)),
                                           ("CardNext", "button_green.png", 100, "@next", (1, 1, 1, 1))):
        button(name, "Card", texture, [0.5, 1], [x, -92], [x + 170, -28])
        text(name + "_Label", name, key, [0, 0], [0, -3], [170, 61], 22, "center", colour)
    # Over everything: black, clear when the level is showing. The script
    # eases its tint - a fade out of one level and into the next.
    image("Fade", "HUD", "panel.png", [0, 0], [-40, -40], [40, 40], (0, 0, 0, 0), None, [1, 1])


def backdrop(world):
    """The pack's backdrop is a stack of bands, each a picture repeated
    sideways: sky, a band of clouds, a band of hills, and the hills' colour
    on down. The bands slide at their own speeds as the view moves along."""
    for name, parallax in (("Sky", [0.0, 0.0]), ("Far", [0.15, 1.0]), ("Mid", [0.45, 1.0]), ("World", [1, 1])):
        call("add_object", name=name)
        call("add_layer2d", name=name)
        call("set_layer2d", name=name, parallax=parallax, automatic=(name != "World"))
    night = world["night"]
    tint = [0.16, 0.19, 0.36, 1] if night else [1, 1, 1, 1]
    under = "dirt" if world["bg"] == "mushrooms" else ("sand" if world["bg"] == "desert" else "grass")
    sprite("SkyFill", T + "bg_solid_sky.png", (0, 0, -30), "Sky", drawMode="tiled", size=[80, 46], pixelsPerUnit=64, color=tint)
    sprite("Clouds", T + "bg_clouds.png", (0, 8.0, -26), "Far", drawMode="tiled", size=[400, 4], pixelsPerUnit=64, color=tint)
    sprite("Hills", T + "bg_color_%s.png" % world["bg"], (0, 4.0, -16), "Mid", drawMode="tiled", size=[480, 4], pixelsPerUnit=64, color=tint)
    sprite("HillsFill", T + "bg_solid_%s.png" % under, (0, -6.0, -16), "Mid", drawMode="tiled", size=[480, 16], pixelsPerUnit=64, color=tint)
    call("set_ambient", color=world["ambient"], intensity=1.0, background=world["sky"])


def stage(number):
    """A world's scene: the stage every one of its levels is put on."""
    w = WORLDS[number - 1]
    backdrop(w)
    lighting = "2d" if w["night"] else "unlit"
    # The hero. The frame is 128 px and the figure 80 by 97: the capsule is
    # the figure, and the sheet's pivot - the object's origin - is its feet.
    sprite("Hero", T + "characters.p3ds", (2, 3, 0.5), "World", autoPlay="idle", pivot=[0.5, 0.0], lighting=lighting, sortOrder=6)
    call("add_physics2d", name="Hero", shape="capsule", halfExtents=[0.42, 0.72], offset=[0, 0.74], friction=0.0,
         fixedRotation=True, castsShadow=False)
    if w["night"]:
        # In the dark the hero carries a little light; the torches do the rest.
        call("add_light", name="HeroLight", type="point", parent="Hero", position=[0, 1.0, 1.5], color=[0.75, 0.85, 1.0],
             intensity=0.55, radius=7.0)
    # What the script borrows: text that floats up off a pickup, and sparkles.
    for i in range(6):
        call("add_object", name="Float_%d" % (i + 1), parent="World", position=[-40, -40, 2.0])
        call("add_text2d", object="Float_%d" % (i + 1), font="assets/fonts/future_narrow.ttf", text="+1", size=0.7,
             color=[1, 0.9, 0.3, 1])
    call("add_audio", name="Music", file="assets/music/%s.ogg" % w["music"], looping=True, volume=0.45)
    hud(w)
    call("set_game_view_2d", center=[6, 5], zoom=6.0, follow="Hero", lag=0.12, followOffset=[0, 2.0], deadZone=[1.2, 1.0],
         lookAhead=[2.0, 0], gravity=[0, -42], autoParallax=True)
    call("set_scene_main_script", path="scenes/World%d.lua" % number)
    call("save_scene_as", path="scenes/World%d.json" % number)
    print("built scenes/World%d.json" % number)


def title():
    w = WORLDS[0]
    backdrop(w)
    sprite("Mascot", T + "characters.p3ds", (-8.6, 2.0, 0.5), "World", autoPlay="walk", pivot=[0.5, 0.0], sortOrder=6)
    call("set_transform", name="Mascot", transform={"scale": [1.4, 1.4, 1]})
    call("add_object", name="TitleGround", parent="World", position=[-20, 0, 0])
    call("add_tilemap", object="TitleGround", tileset=T + "tiles.p3dt", tileSize=[1, 1])
    call("paint_terrain", object="TitleGround", group=0, cells=[[x, y] for x in range(0, 40) for y in range(-6, 2)])
    call("add_audio", name="Music", file="assets/music/menu.ogg", looping=True, volume=0.45)
    canvas("Menu")
    text("LogoShade", "Menu", "HOPPER", [0.5, 0], [-500, 38], [500, 178], 130, "center", (0.16, 0.2, 0.3, 0.55), "future")
    text("Logo", "Menu", "HOPPER", [0.5, 0], [-500, 30], [500, 170], 130, "center", (1.0, 0.82, 0.2, 1), "future")
    call("add_object", name="Home", parent="Menu")
    call("add_ui", object="Home", kind="rect")
    call("set_ui", object="Home", properties={"anchorMin": [0, 0], "anchorMax": [1, 1], "offsetMin": [0, 0], "offsetMax": [0, 0]})
    image("StarsPlate", "Home", "panel.png", [0.5, 0], [-150, 180], [150, 228], (0.10, 0.13, 0.20, 0.62), [16, 16, 16, 20])
    image("StarsIcon", "StarsPlate", "star.png", [0, 0], [22, 6], [58, 42])
    text("StarsTotal", "StarsPlate", "0 / 150", [0, 0], [60, 0], [290, 46], 26, "center", (1, 1, 1, 0.95))
    button("Play", "Home", "button_green.png", [0.5, 0], [-170, 250], [170, 350])
    text("Play_Label", "Play", "@play", [0, 0], [0, -4], [340, 96], 52, "center", (1, 1, 1, 1), "future")
    colours = ("green", "yellow", "grey", "blue", "red")
    for i, world in enumerate(WORLDS):
        x = -490 + i * 198
        name = "World%d" % (i + 1)
        button(name, "Home", "button_%s.png" % colours[i], [0.5, 0], [x, 384], [x + 188, 516])
        text(name + "_Name", name, "@world_%d" % (i + 1), [0, 0], [0, 10], [188, 52], 26, "center",
             (0.25, 0.28, 0.35, 1) if colours[i] == "grey" else (1, 1, 1, 1))
        image(name + "_StarIcon", name, "star.png", [0, 0], [44, 72], [72, 100])
        text(name + "_Stars", name, "0 / 30", [0, 0], [70, 70], [170, 102], 20, "left",
             (0.25, 0.28, 0.35, 1) if colours[i] == "grey" else (1, 1, 1, 0.95))
    button("Language", "Home", "button_grey.png", [1, 0], [-150, 16], [-24, 66])
    text("Language_Label", "Language", "EN", [0, 0], [0, -3], [126, 47], 22, "center", (0.25, 0.28, 0.35, 1))
    call("add_object", name="Grid", parent="Menu")
    call("add_ui", object="Grid", kind="rect")
    call("set_ui", object="Grid", properties={"anchorMin": [0, 0], "anchorMax": [1, 1], "offsetMin": [0, 0], "offsetMax": [0, 0]})
    image("GridPlate", "Grid", "panel.png", [0.5, 0], [-560, 190], [560, 520], (0.10, 0.13, 0.20, 0.72), [16, 16, 16, 20])
    text("GridTitle", "GridPlate", "MEADOW", [0.5, 0], [-300, 8], [300, 56], 34, "center", (1, 1, 1, 1))
    button("GridBack", "GridPlate", "button_grey.png", [0, 0], [18, 10], [150, 58])
    text("GridBack_Label", "GridBack", "@back", [0, 0], [0, -3], [132, 46], 22, "center", (0.25, 0.28, 0.35, 1))
    for i in range(PER_WORLD):
        col, row = i % 5, i // 5
        x, y = 34 + col * 212, 76 + row * 118
        name = "Cell%d" % (i + 1)
        button(name, "GridPlate", "button_blue.png", [0, 0], [x, y], [x + 200, y + 106])
        text(name + "_Number", name, str(i + 1), [0, 0], [0, 2], [200, 60], 40, "center", (1, 1, 1, 1), "future")
        for k in range(3):
            sx = 46 + k * 38
            image(name + "_StarBack%d" % (k + 1), name, "star_empty.png", [0, 0], [sx, 58], [sx + 32, 90], (1, 1, 1, 0.5))
            image(name + "_Star%d" % (k + 1), name, "star.png", [0, 0], [sx + 2, 60], [sx + 30, 88])
    image("Fade", "Menu", "panel.png", [0, 0], [-40, -40], [40, 40], (0, 0, 0, 0), None, [1, 1])
    call("set_game_view_2d", center=[0, 5.6], zoom=6.0, gravity=[0, -42], autoParallax=True)
    call("set_scene_main_script", path="scenes/Title.lua")
    call("save_scene_as", path="scenes/Title.json")
    print("built scenes/Title.json")


# ----- the levels ------------------------------------------------------------------------
# A piece of a level, as a picture. The last two rows are the ground; rows
# above the first given are air. Every piece begins and ends on the ground,
# so any two fit together.
#
#   #  terrain            =  a bridge (stood on, jumped up through)    R  a plank that drops when stood on
#   /  ramp up            \  ramp down                                 H  ladder
#   ^  spikes             ~  water                                     S  a spring
#   o  coin               *  a place a gem may be                      c  checkpoint
#   s  slime   n  snail   b  bee   f  fly   m  mouse (it comes after you)
#   M  a platform that goes side to side      V  one that goes up and down
#   K  key     L  lock    T  torch            >  a sign
CHUNKS = {
    "flat": ["..........", "..........", "..........", "..........", "...ooo....", "..........", "##########", "##########"],
    "gap": ["..........", "..........", "..........", "....oo....", "..........", "..........", "####~~####", "####~~####"],
    "steps": ["............", "............", ".........*..", ".......###..", "....###.....", ".o..........", "############", "############"],
    "slime": ["............", "............", "............", "............", "...o.o.o....", "......s.....", "############", "############"],
    "bridge": ["............", "............", "............", "....oooo....", "............", "............", "###======###", "###^^^^^^###"],
    "ladder": ["...*........", "..####H.....", "......H.....", "......H.....", "......H.....", "......H.....", "############", "############"],
    "spring": [".......*....", "......###...", "............", "............", "............", "...S........", "############", "############"],
    "ferry": ["..............", "..............", "..............", ".....ooo......", "..............", "...M..........", "###~~~~~~~~###", "###~~~~~~~~###"],
    "bees": ["............", "............", "....b...b...", "............", "..o..o..o...", "............", "############", "############"],
    "planks": ["............", "............", "............", "....oooo....", "............", "............", "###RRRRRR###", "###^^^^^^###"],
    "hill": ["..............", "..............", "..............", ".......oo.....", "....../##\\....", "...../####\\...", "##############", "##############"],
    "lock": ["..............", "..............", "..........L...", "...K......L...", "..###.....L...", "..........L...", "##############", "##############"],
    "mouse": ["..............", "..............", "..............", "..............", "...o..o..o....", ".........m....", "##############", "##############"],
    "lift": [".........*..", "........###.", "............", "............", "............", ".....V......", "############", "############"],
    "snail": ["............", "............", "............", "............", "....ooo.....", ".....n......", "############", "############"],
    "towers": ["..............", "..............", "......*.......", "..............", "...#..#..#....", "...#.o#.o#....", "##############", "##############"],
    "flies": ["............", "............", "............", "...f....f...", ".....oo.....", "............", "############", "############"],
    "pits": ["..............", "..............", "..............", "...oo...oo....", "..............", "..............", "###~~###~~####", "###~~###~~####"],
    "shelf": ["............", "............", "............", "...o.*.o....", "...=====....", "............", "############", "############"],
    "check": ["........", "........", "........", "........", "........", "...c....", "########", "########"],
}
START = ["........", "........", "........", "........", "........", "..P..>..", "########", "########"]
END = ["..........", "..........", "..........", "..........", "..........", "......F...", "##########", "##########"]
# Which pieces a level may be built from, by how far into its world it is.
EASY = ["flat", "gap", "steps", "slime", "bridge", "shelf", "snail", "flat"]
MIDDLE = EASY + ["ladder", "spring", "bees", "hill", "towers", "pits", "flies"]
LATE = MIDDLE + ["ferry", "planks", "lock", "mouse", "lift"]


def design(number):
    """Level `number` (1-50) as rows of text, top row first."""
    world = (number - 1) // PER_WORLD
    k = (number - 1) % PER_WORLD
    rnd = random.Random(900 + number)
    pool = EASY if k < 3 else (MIDDLE if k < 6 else LATE)
    count = 4 + k // 2 + (1 if world >= 2 else 0)
    names, last = [], None
    for i in range(count):
        pick = rnd.choice([n for n in pool if n != last and not (n == "lock" and "lock" in names)])
        names.append(pick)
        last = pick
    names.insert(len(names) // 2, "check")
    if k == 0 and world == 0:
        names = ["flat", "steps", "check", "gap", "slime"]      # the first level of all: one of each idea, gently
    parts = [START] + [CHUNKS[n] for n in names] + [END]
    rows = ["" for _ in range(HEIGHT)]
    for part in parts:
        pad = HEIGHT - len(part)
        for r in range(HEIGHT):
            rows[r] += part[r - pad] if r >= pad else "." * len(part[0])
    # Three gems a level: of the places one may be, three are; the rest coins.
    spots = [(r, c) for r in range(HEIGHT) for c in range(len(rows[0])) if rows[r][c] == "*"]
    rnd.shuffle(spots)
    grid = [list(row) for row in rows]
    for r, c in spots[3:]:
        grid[r][c] = "o"
    if len(spots) < 3:
        coins = [(r, c) for r in range(HEIGHT) for c in range(len(rows[0])) if grid[r][c] == "o"]
        rnd.shuffle(coins)
        for r, c in coins[:3 - len(spots)]:
            grid[r][c] = "*"
    # In the dark, a torch every so often along the ground.
    if WORLDS[world]["night"]:
        for c in range(5, len(grid[0]) - 3, 9):
            for r in range(HEIGHT - GROUND - 1, 2, -1):
                if grid[r][c] == "." and grid[r + 1][c] == "#":
                    grid[r][c] = "T"
                    break
    return ["".join(row) for row in grid], world


def level(number):
    rows, world = design(number)
    w = WORLDS[world]
    width = len(rows[0])
    lighting = "2d" if w["night"] else "unlit"
    call("add_object", name="Level")
    for parent in ("Things", "Enemies", "Movers"):
        call("add_object", name=parent, parent="Level")

    # The ground: one tile map, painted by terrain - the map picks the pieces -
    # with a body made from its solid cells, slopes included.
    call("add_object", name="Ground", parent="Level", position=[0, 0, 0])
    call("add_tilemap", object="Ground", tileset=T + "tiles.p3dt", tileSize=[1, 1], lit=w["night"])
    cell = lambda r, c: (c, HEIGHT - 1 - r)
    terrain = [list(cell(r, c)) for r in range(HEIGHT) for c in range(width) if rows[r][c] in "#L" and rows[r][c] == "#"]
    call("paint_terrain", object="Ground", group=TERRAINS.index(w["terrain"]), cells=terrain)
    loose = []
    for r in range(HEIGHT):
        for c in range(width):
            ch, (x, y) = rows[r][c], cell(r, c)
            above = rows[r - 1][c] if r > 0 else "."
            if ch == "/":
                loose.append([x, y, INDEX[w["terrain"] + "_ramp_right"]])
            elif ch == "\\":
                loose.append([x, y, INDEX[w["terrain"] + "_ramp_left"]])
            elif ch == "^":
                loose.append([x, y, INDEX["spikes"]])
            elif ch == "~":
                loose.append([x, y, INDEX["water_top" if above != "~" else "water"]])
            elif ch == "H":
                below = rows[r + 1][c] if r + 1 < HEIGHT else "#"
                loose.append([x, y, INDEX["ladder_top" if above != "H" else ("ladder_bottom" if below != "H" else "ladder_middle")]])
    if loose:
        call("set_tiles", object="Ground", tiles=loose)
    call("add_physics2d", name="Ground", bodyType="static", friction=0.0, castsShadow=w["night"])

    # The bridges: a second map over the first, with a body that is solid
    # from above and open from below.
    bridges = [[cell(r, c)[0], cell(r, c)[1], INDEX["bridge"]] for r in range(HEIGHT) for c in range(width) if rows[r][c] == "="]
    if bridges:
        call("add_object", name="Bridges", parent="Level", position=[0, 0, 0.05])
        call("add_tilemap", object="Bridges", tileset=T + "tiles.p3dt", tileSize=[1, 1], lit=w["night"])
        call("set_tiles", object="Bridges", tiles=bridges)
        call("set_solid_cells", object="Bridges", cells=[[b[0], b[1], 1] for b in bridges])
        call("add_physics2d", name="Bridges", bodyType="static", oneWay=True, layer=2, friction=0.0, castsShadow=False)

    count = {}

    def named(kind):
        count[kind] = count.get(kind, 0) + 1
        return "%s_%d" % (kind, count[kind])

    things = T + "things.p3ds"
    enemies = T + "enemies.p3ds"
    for r in range(HEIGHT):
        for c in range(width):
            ch, (x, y) = rows[r][c], cell(r, c)
            cx, base = x + 0.5, float(y)        # the cell's middle, and its floor
            if ch == "P":
                call("add_object", name="Start", parent="Level", position=[cx, base, 0])
            elif ch == "o":
                sprite(named("Coin"), things, (cx, base + 0.5, 0.2), "Things", frame="coin_gold", sortOrder=4)
            elif ch == "*":
                sprite(named("Gem"), things, (cx, base + 0.5, 0.2), "Things", frame="gem_blue", sortOrder=4)
            elif ch == "S":
                sprite(named("Spring"), things, (cx, base + 0.5, 0.1), "Things", frame="spring", lighting=lighting, sortOrder=3)
            elif ch == "c":
                sprite(named("Check"), things, (cx, base + 0.5, 0.1), "Things", frame="flag_off", lighting=lighting, sortOrder=3)
            elif ch == "F":
                sprite("Goal", things, (cx, base + 0.5, 0.1), "Things", frame="flag_green_a", lighting=lighting, sortOrder=3)
            elif ch == ">":
                name = named("Sign")
                sprite(name, things, (cx, base + 0.5, 0.05), "Things", frame="sign", lighting=lighting, sortOrder=2)
                # What a sign says floats over it: words in the world, by key.
                call("add_object", name=name + "_Words", parent=name, position=[0, 1.25, 0.6])
                call("add_text2d", object=name + "_Words", font="assets/fonts/future_narrow.ttf",
                     text="@sign_%d" % number if number <= 3 else "@sign_go", size=0.42,
                     color=[1, 1, 1, 1] if w["night"] else [0.22, 0.28, 0.40, 1])
            elif ch == "K":
                sprite("Key", things, (cx, base + 0.5, 0.2), "Things", frame="key_yellow", sortOrder=4)
            elif ch == "L":
                name = named("Lock")
                sprite(name, things, (cx, base + 0.5, 0.1), "Things", frame="lock_yellow", lighting=lighting, sortOrder=3)
                call("add_physics2d", name=name, bodyType="static", shape="box", halfExtents=[0.5, 0.5], friction=0.0,
                     castsShadow=w["night"])
            elif ch == "T":
                name = named("Torch")
                sprite(name, things, (cx, base + 0.5, -0.1), "Things", frame="torch_on_a", sortOrder=2)
                call("add_light", name=name + "_Light", type="point", parent=name, position=[0, 0.2, 1.4],
                     color=[1.0, 0.7, 0.35], intensity=1.0, radius=9.0)
                sprite(name + "_Glow", T + "fx/glow.png", (0, 0.2, 0.05), name, blend="additive", pixelsPerUnit=40,
                       color=[1.0, 0.7, 0.3, 0.55], sortOrder=3)
            elif ch in "snbfm":
                kind = {"s": "Slime", "n": "Snail", "b": "Bee", "f": "Fly", "m": "Mouse"}[ch]
                clip = {"s": "slime", "n": "snail", "b": "bee", "f": "fly", "m": "mouse"}[ch]
                up = 1.6 if ch in "bf" else 0.5
                sprite(named(kind), enemies, (cx, base + up, 0.3), "Enemies", autoPlay=clip, lighting=lighting, sortOrder=5)
            elif ch in "MV":
                # A platform the script carries back and forth: a kinematic
                # body, so what stands on it is carried too.
                name = named("Ferry" if ch == "M" else "Lift")
                sprite(name, things, (cx + 0.5, base + 0.75, 0.1), "Movers", frame="bridge_logs", lighting=lighting, sortOrder=3)
                call("set_transform", name=name, transform={"scale": [2.0, 1.0, 1]})
                call("add_physics2d", name=name, bodyType="kinematic", shape="box", halfExtents=[1.0, 0.2], offset=[0, 0.22],
                     friction=0.0, castsShadow=False)
            elif ch == "R":
                # A plank welded to a point in the air by a joint that
                # gives way under more than its own weight: it holds until
                # something stands on it.
                name = named("Plank")
                sprite(name, things, (cx, base + 0.5, 0.1), "Movers", frame="block_plank", lighting=lighting, sortOrder=3)
                call("set_transform", name=name, transform={"scale": [1.0, 0.5, 1]})
                call("add_physics2d", name=name, shape="box", halfExtents=[0.5, 0.25], density=1.0, friction=0.0,
                     fixedRotation=False, castsShadow=False)
                call("add_joint2d", name=name, joint="weld", breakForce=60)
    stem = "H%03d" % number
    path = os.path.join(PROJECT, "assets", "prefabs", stem + ".prefab")
    if os.path.exists(path):
        os.remove(path)
    call("create_prefab", name="Level", prefabName=stem)
    call("delete_object", name="Level")
    return width


def main():
    call("open_project", path=PROJECT)
    what = sys.argv[1] if len(sys.argv) > 1 else "all"
    if what == "all" or not os.path.exists(os.path.join(PROJECT, T + "tiles.p3dt")):
        atlases()
        tileset()
    if what in ("all", "stages"):
        call("new_scene", kind="2d")
        title()
        for n in range(1, len(WORLDS) + 1):
            call("new_scene", kind="2d")
            stage(n)
    if what in ("all", "levels"):
        first = int(sys.argv[2]) if len(sys.argv) > 2 else 1
        last = int(sys.argv[3]) if len(sys.argv) > 3 else len(WORLDS) * PER_WORLD
        call("new_scene", kind="2d")
        for number in range(first, last + 1):
            print("H%03d: %d wide" % (number, level(number)))


if __name__ == "__main__":
    main()
