#!/usr/bin/env python3
"""Builds Topple's scenes by driving a running PyrosBuilder.

    1. python3 tools/make_assets.py /path/to/kenney     (once)
    2. start PyrosBuilder
    3. python3 tools/build_levels.py                    (all scenes)
       python3 tools/build_levels.py Meadow             (one)

Everything in a scene is made with the commands the editor's own panels
issue, so each can be opened and changed by hand afterwards; this script is
only the quick way to lay four levels out the same way. The game's rules are
in assets/lua/topple/game.lua and read the scene by name:

    B_<material>_<shape>_<n>    a block      (under Blocks)
    T_<colour>_<n>              a target     (under Targets)
    A_<colour>_<n>              a shot       (under Ammo, fired in order)

Stdlib only; make_normals.py (run from here) needs Pillow and numpy.
"""
import json
import math
import os
import random
import socket
import subprocess
import sys

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
T = "assets/textures/"
PIECES = T + "pieces.p3ds"
SCENERY = T + "scenery.p3ds"
PPU = 70.0
U = 220 / 70.0      # a plank's length: the pack's long pieces are 220 px


def endpoint():
    tmp = os.environ.get("TMPDIR", "/tmp")
    for name in ("pyros3d-driver.json", "pyros3d-editor.json"):
        path = os.path.join(tmp, name)
        if os.path.exists(path):
            return json.load(open(path))
    sys.exit("PyrosBuilder is not running (no pyros3d-editor.json in $TMPDIR)")


CFG = endpoint()


def call(cmd, **args):
    s = socket.create_connection(("127.0.0.1", CFG["port"]), timeout=180)
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
        sys.exit("%s failed: %s\n  args: %s" % (cmd, result.get("error") if isinstance(result, dict) else result, json.dumps(args)))
    return result


# ----- the pieces ----------------------------------------------------------------
SIZE = {"sq": (1, 1), "block": (2, 1), "plank": (U, 1), "big": (2, 2), "slab": (U, 2), "post": (1, U),
        "pillar": (1, 2), "ball": (1, 1), "tri": (2, 1)}
#            density friction bounce
MATERIAL = {"wood": (0.55, 0.65, 0.05), "glass": (0.40, 0.45, 0.02), "stone": (1.30, 0.80, 0.02),
            "metal": (2.00, 0.55, 0.08), "tnt": (0.60, 0.70, 0.05)}
COUNT = {}
SHADOWS = [False]     # whether this level's blocks stand in the way of its lights


def nth(kind):
    COUNT[kind] = COUNT.get(kind, 0) + 1
    return COUNT[kind]


def sprite(name, source, at, parent, **kw):
    call("add_sprite", name=name, source=source, position=list(at), parent=parent, **kw)


def turn(name, degrees):
    if degrees:
        call("set_transform", name=name, transform={"rotation": [0, 0, math.radians(degrees)]})


def piece(mat, shape, x, y, rot=0):
    """A block: whole, lit, with the body its outline wants. x, y is its
    centre; rot turns it (a plank stood on end is rot=90)."""
    name = "B_%s_%s_%d" % (mat, shape, nth("B"))
    w, h = SIZE[shape]
    sprite(name, PIECES, (x, y, 0), "Blocks", frame="%s_%s_0" % (mat, shape), lighting="2d", sortOrder=3)
    turn(name, rot)
    density, friction, bounce = MATERIAL[mat]
    common = dict(name=name, density=density, friction=friction, bounciness=bounce, fixedRotation=False,
                  castsShadow=SHADOWS[0])
    if shape == "ball":
        call("add_physics2d", shape="circle", halfExtents=[0.5, 0.5], **common)
    elif shape == "tri":
        call("add_physics2d", shape="polygon", polygon=[[-0.97, -0.5], [0.97, -0.5], [0, 0.47]], **common)
    else:
        # A hair inside the drawing: the art has rounded corners, and
        # blocks that touch along their whole side look glued together.
        call("add_physics2d", shape="box", halfExtents=[w / 2 - 0.02, h / 2 - 0.02], **common)
    return name


def target(colour, x, y):
    name = "T_%s_%d" % (colour, nth("T"))
    sprite(name, PIECES, (x, y, 0.05), "Targets", frame="alien_%s_suit" % colour, lighting="2d", sortOrder=4)
    call("add_physics2d", name=name, shape="box", halfExtents=[0.46, 0.46], density=0.35, friction=0.6,
         bounciness=0.1, fixedRotation=False, castsShadow=False)
    return name


def ammo(colours, sling):
    """The shots, standing in a queue behind the sling. Kinematic until the
    script fires one: it is carried to the pouch, not pushed there."""
    sx, sy = sling
    for i, colour in enumerate(colours):
        name = "A_%s_%d" % (colour, i + 1)
        sprite(name, PIECES, (sx - 2.2 - i * 1.15, 0.5, 0.3), "Ammo", frame="alien_%s_round" % colour,
               lighting="2d", sortOrder=5)
        call("add_physics2d", name=name, bodyType="kinematic", shape="circle", halfExtents=[0.48, 0.48],
             density=1.6 if colour == "beige" else 1.0, friction=0.5, bounciness=0.25, fixedRotation=False,
             bullet=True, linearDamping=0.02, angularDamping=0.6, castsShadow=False)
        call("add_object", name=name + "_Trail", parent=name)
        call("add_line2d", object=name + "_Trail", trail=True, lifetime=0.9, minDistance=0.18, width=[0.34, 0.0],
             colorStart=[1, 1, 1, 0.75], colorEnd=[1, 1, 1, 0.0], sortOrder=2)
        if colour == "blue":
            # A blue shot splits in three: the other two wait out of sight.
            for k in (1, 2):
                spare = "S_blue_%d_%d" % (i + 1, k)
                sprite(spare, PIECES, (LEFT - 10 - k * 2, -12 - i * 2, 0.3), "Spares", frame="alien_blue_round",
                       lighting="2d", sortOrder=5)
                call("add_physics2d", name=spare, bodyType="kinematic", shape="circle", halfExtents=[0.48, 0.48],
                     density=1.0, friction=0.5, bounciness=0.25, fixedRotation=False, bullet=True,
                     linearDamping=0.02, angularDamping=0.6, castsShadow=False)
                call("add_object", name=spare + "_Trail", parent=spare)
                call("add_line2d", object=spare + "_Trail", trail=True, lifetime=0.9, minDistance=0.18,
                     width=[0.34, 0.0], colorStart=[1, 1, 1, 0.75], colorEnd=[1, 1, 1, 0.0], sortOrder=2)


# ----- what every level has ---------------------------------------------------------
THEMES = {
    "meadow": dict(bg="bg_colored_grass.png", ground="ground_grass.png",
                   ambient=[0.78, 0.80, 0.84], back=[0.82, 0.95, 0.97], sun=[1.0, 0.95, 0.82], sun_power=0.75,
                   tint=[1, 1, 1, 1], far=[0.80, 0.93, 0.90, 1.0]),
    "dunes": dict(bg="bg_colored_desert.png", ground="ground_sand.png",
                  ambient=[0.80, 0.74, 0.66], back=[0.83, 0.95, 0.97], sun=[1.0, 0.86, 0.62], sun_power=0.9,
                  tint=[1.0, 0.96, 0.9, 1], far=[0.95, 0.90, 0.80, 1.0]),
    "grove": dict(bg="bg_blue_shroom.png", ground="ground_dirt.png",
                  ambient=[0.20, 0.24, 0.40], back=[0.05, 0.07, 0.16], sun=[0.55, 0.65, 1.0], sun_power=0.35,
                  tint=[0.22, 0.27, 0.48, 1], far=[0.16, 0.20, 0.38, 1.0], shadows=True),
    "keep": dict(bg="bg_blue_land.png", ground="ground_snow.png",
                 ambient=[0.62, 0.66, 0.80], back=[0.80, 0.90, 0.97], sun=[1.0, 0.80, 0.70], sun_power=0.8,
                 tint=[0.92, 0.94, 1.0, 1], far=[0.80, 0.86, 0.96, 1.0]),
}
LEFT, RIGHT = -19.0, 27.0      # the ends of every level
SLING = (-9.0, 3.25)           # where a shot rests in the pouch


def backdrop(theme):
    th = THEMES[theme]
    SHADOWS[0] = th.get("shadows", False)
    # Five layers, each scrolled by the engine as the view moves: the sky
    # barely, the clouds a little, two rows of scenery, the level itself
    # one for one, and a strip of grass in front that moves faster still.
    for name, parallax in (("Sky", [0.06, 0.5]), ("Clouds", [0.18, 0.6]), ("Far", [0.35, 0.8]), ("Mid", [0.62, 0.95]),
                           ("World", [1, 1]), ("Front", [1.25, 1.0])):
        call("add_object", name=name)
        call("add_layer2d", name=name)
        call("set_layer2d", name=name, parallax=parallax, automatic=(name != "World"))
    # The pack's backdrop is 1024 px square and repeats sideways.
    sprite("Backdrop", T + th["bg"], (4, 7.5, -30), "Sky", drawMode="tiled", size=[96, 24], pixelsPerUnit=1024 / 24.0,
           color=th["tint"])
    for parent in ("Blocks", "Targets", "Ammo", "Spares", "Debris", "Decor", "Ropes"):
        call("add_object", name=parent, parent="World")
    w = RIGHT - LEFT + 24
    cx = (LEFT + RIGHT) / 2
    sprite("Ground", T + th["ground"], (cx, -0.5, 0), "World", drawMode="tiled", size=[w, 1], lighting="2d", sortOrder=1,
           pixelsPerUnit=PPU)
    call("add_physics2d", name="Ground", bodyType="static", shape="box", halfExtents=[w / 2, 0.5], offset=[0, -0.08],
         friction=0.9, castsShadow=False)
    sprite("Under", T + th["ground"].replace(".png", "_fill.png"), (cx, -5.95, -0.01), "World", drawMode="tiled",
           size=[w, 10], lighting="2d", pixelsPerUnit=8)
    for name, x in (("WallLeft", LEFT - 6), ("WallRight", RIGHT + 6)):
        call("add_object", name=name, parent="World", position=[x, 20, 0])
        call("add_physics2d", name=name, bodyType="static", halfExtents=[0.5, 24], castsShadow=False)
    call("set_ambient", color=th["ambient"], intensity=1.0, background=th["back"])
    call("add_light", name="Sun", type="point", parent="World", position=[-6, 22, 9], color=th["sun"],
         intensity=th["sun_power"], radius=90.0)


def scatter(layer, frames, xs, y, z, scale, colour, rnd, jitter=0.25, far=False):
    for i, x in enumerate(xs):
        frame = ("far_" if far else "") + frames[rnd.randrange(len(frames))]
        s = scale * (1 + rnd.uniform(-jitter, jitter))
        name = "%s_%d" % (layer, i)
        sprite(name, SCENERY, (round(x, 2), y, z), layer, frame=frame, pivot=[0.5, 0.0], color=colour,
               flipX=bool(rnd.getrandbits(1)))
        call("set_transform", name=name, transform={"scale": [round(s, 2), round(s, 2), 1]})


def sling():
    """A fork of three wooden pieces. The far arm and its band are drawn
    behind the shot, the near arm and band in front of it."""
    x, y = SLING
    parts = (("SlingTrunk", "wood_post_0", (x, 1.18, 0.1), (0.5, 0.75), 0, 2),
             ("SlingFar", "wood_pillar_0", (x - 0.42, 2.85, 0.1), (0.42, 0.72), 24, 2),
             ("SlingNear", "wood_pillar_0", (x + 0.42, 2.85, 0.45), (0.42, 0.72), -24, 8))
    for name, frame, at, scale, rot, order in parts:
        sprite(name, PIECES, at, "World", frame=frame, lighting="2d", sortOrder=order)
        call("set_transform", name=name, transform={"rotation": [0, 0, math.radians(rot)], "scale": [scale[0], scale[1], 1]})
    # Two bands, each a line of two points: the arm's tip, and the pouch -
    # which the script moves.
    for name, tip, z, order in (("BandFar", (x - 0.72, y + 0.3), 0.12, 2), ("BandNear", (x + 0.72, y + 0.3), 0.4, 7)):
        call("add_object", name=name, parent="World", position=[0, 0, z])
        call("add_line2d", object=name, points=[list(tip), [x, y]], width=[0.2, 0.26],
             colorStart=[0.36, 0.17, 0.12, 1], colorEnd=[0.30, 0.13, 0.10, 1], sortOrder=order)
    call("add_object", name="Pouch", parent="World", position=[x, y, 0.3])


def machinery():
    """What the script borrows while a level runs, parked out of sight: the
    pieces a broken block throws, the dots of the aiming line, and the ring
    and the light of an explosion."""
    for i in range(22):
        name = "D_%d" % (i + 1)
        sprite(name, PIECES, (LEFT - 12 - (i % 8) * 1.5, -20 - (i // 8) * 1.5, 0.2), "Debris", frame="debris_wood_1",
               lighting="2d", sortOrder=6)
        call("add_physics2d", name=name, bodyType="kinematic", shape="box", halfExtents=[0.3, 0.3], density=0.12,
             friction=0.6, bounciness=0.2, fixedRotation=False, castsShadow=False)
    call("add_object", name="Dots", parent="World")
    call("add_sprite_batch", object="Dots")
    for i in range(16):
        sprite("Dot_%d" % (i + 1), T + "fx/soft.png", (LEFT - 12, -16, 0.25), "Dots", pixelsPerUnit=420,
               color=[1, 1, 1, 0.9], sortOrder=6)
    sprite("Shock", T + "fx/shock.png", (LEFT - 12, -14, 0.6), "World", blend="additive", pixelsPerUnit=128, sortOrder=9)
    call("add_light", name="Flash", type="point", parent="World", position=[LEFT - 12, -14, 2], color=[1.0, 0.72, 0.4],
         intensity=0.0, radius=16.0)


def rope(name, points, width=0.12, colour=(0.33, 0.24, 0.18, 1), order=2):
    """A line the script keeps tied to things. R_<Object>: its last point
    follows that object. RR_<A>__<B>: its first follows A and its last B."""
    call("add_object", name=name, parent="Ropes", position=[0, 0, 0.08])
    call("add_line2d", object=name, points=[list(p) for p in points], width=[width, width],
         colorStart=list(colour), colorEnd=list(colour), sortOrder=order)


def lantern(n, x, top, length, colour=(1.0, 0.72, 0.38), power=2.2, radius=13.0):
    """A lamp on a rope: a small body hung from a point in the air, the light
    it carries, and a glow. Knock it and the shadows swing."""
    name = "Lamp_%d" % n
    y = top - length
    sprite(name, PIECES, (x, y, 0.2), "World", frame="metal_sq_0", sortOrder=6, color=[1.0, 0.86, 0.6, 1])
    call("set_transform", name=name, transform={"scale": [0.42, 0.5, 1]})
    call("add_physics2d", name=name, shape="box", halfExtents=[0.21, 0.25], density=0.8, fixedRotation=False,
         linearDamping=0.25, angularDamping=1.0, castsShadow=False)
    call("add_object", name=name + "_Pin", parent="World", position=[x, top, 0])
    call("add_physics2d", name=name + "_Pin", bodyType="static", shape="circle", halfExtents=[0.05, 0.05], sensor=True,
         castsShadow=False)
    call("add_joint2d", name=name, joint="distance", connected=name + "_Pin", anchor=[0, 0.25], lower=0, upper=length - 0.25)
    call("add_light", name=name + "_Light", type="point", parent=name, position=[0, -0.2, 1.2], color=list(colour),
         intensity=power, radius=radius)
    sprite(name + "_Glow", T + "fx/glow.png", (0, 0, 0.05), name, blend="additive", pixelsPerUnit=9,
           color=[colour[0], colour[1], colour[2], 0.55], sortOrder=7)
    rope("R_" + name, [(x, top), (x, y + 0.25)], 0.07, (0.2, 0.18, 0.2, 1))


def glow(parent, size, colour, alpha=0.5, order=2):
    sprite(parent + "_Glow", T + "fx/glow.png", (0, 0, -0.05), parent, blend="additive", pixelsPerUnit=128.0 / size,
           color=[colour[0], colour[1], colour[2], alpha], sortOrder=order)


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


def button(name, parent, texture, label, anchor, omin, omax, size=26):
    call("add_object", name=name, parent=parent)
    call("add_ui", object=name, kind="button")
    call("set_ui", object=name, properties={"anchorMin": anchor, "anchorMax": anchor, "offsetMin": omin, "offsetMax": omax,
                                            "texture": T + "ui/" + texture, "border": [14, 14, 14, 18],
                                            "tint": [1, 1, 1, 1], "hoverTint": [1.0, 1.0, 0.85, 1], "pressedTint": [0.8, 0.8, 0.8, 1],
                                            "pressedOffset": [0, 3]})
    if label:
        w, h = omax[0] - omin[0], omax[1] - omin[1]
        text(name + "_Label", name, label, [0, 0], [0, -3], [w, h - 3], size)


def hud(title):
    call("add_object", name="HUD")
    call("add_ui", object="HUD", kind="canvas")
    call("set_ui", object="HUD", properties={"referenceWidth": 1280, "referenceHeight": 720})
    # Text sits on dark plates: the same interface has to read over a pale
    # sky, a desert and a night.
    image("HudPlate", "HUD", "panel.png", [0, 0], [16, 14], [300, 118], (0.10, 0.13, 0.20, 0.62), [16, 16, 16, 20])
    text("HudTitle", "HudPlate", title, [0, 0], [18, 8], [280, 40], 24, "left", (1, 1, 1, 0.9))
    text("HudScore", "HudPlate", "0", [0, 0], [18, 40], [280, 96], 46, "left", (1.0, 0.84, 0.25, 1))
    image("HudHintPlate", "HUD", "panel.png", [0.5, 1], [-380, -84], [380, -28], (0.10, 0.13, 0.20, 0.62), [16, 16, 16, 20])
    text("HudHint", "HudHintPlate", "DRAG THE ALIEN BACK AND LET GO", [0, 0], [0, 0], [760, 52], 26, "center",
         (1, 1, 1, 0.95))
    button("BtnRetry", "HUD", "round_blue.png", "", [1, 0], [-84, 16], [-24, 76])
    image("BtnRetry_Icon", "BtnRetry", "repeat_light.png", [0, 0], [13, 10], [47, 44])
    button("BtnMenu", "HUD", "round_grey.png", "", [1, 0], [-154, 16], [-94, 76])
    text("BtnMenu_Icon", "BtnMenu", "<", [0, 0], [-2, -4], [58, 56], 30, "center", (0.25, 0.28, 0.35, 1))

    # The end-of-level card. Saved showing - the script hides it when the
    # level starts - because an element saved hidden cannot be shown later.
    image("Card", "HUD", "panel.png", [0.5, 0.5], [-300, -200], [300, 200], (1, 1, 1, 0.97), [16, 16, 16, 20])
    text("CardTitle", "Card", "LEVEL CLEAR", [0.5, 0], [-280, 22], [280, 78], 40, "center", (0.22, 0.26, 0.34, 1))
    for i in range(3):
        x = -150 + i * 100
        image("CardStarBack%d" % (i + 1), "Card", "star_empty.png", [0.5, 0], [x, 96], [x + 100, 192], (1, 1, 1, 0.9))
        image("CardStar%d" % (i + 1), "Card", "star.png", [0.5, 0], [x + 8, 104], [x + 92, 184])
    text("CardScore", "Card", "0", [0.5, 0], [-280, 200], [280, 252], 36, "center", (0.22, 0.26, 0.34, 1))
    text("CardBest", "Card", "BEST 0", [0.5, 0], [-280, 250], [280, 282], 18, "center", (0.4, 0.44, 0.52, 1))
    button("CardMenu", "Card", "button_grey.png", "", [0.5, 1], [-270, -92], [-100, -28], 22)
    text("CardMenu_Label", "CardMenu", "MENU", [0, 0], [0, -3], [170, 61], 22, "center", (0.25, 0.28, 0.35, 1))
    button("CardRetry", "Card", "button_blue.png", "AGAIN", [0.5, 1], [-85, -92], [85, -28], 22)
    button("CardNext", "Card", "button_green.png", "NEXT", [0.5, 1], [100, -92], [270, -28], 22)


def finish(scene, theme):
    call("set_game_view_2d", center=[0, 6.2], zoom=8.0, bounds=[LEFT, -2.5, RIGHT, 30], gravity=[0, -22],
         autoParallax=True)
    call("set_scene_main_script", path="scenes/%s.lua" % scene)
    call("save_scene_as", path="scenes/%s.json" % scene)
    print("built scenes/%s.json" % scene)


# ----- the levels --------------------------------------------------------------------
def meadow():
    rnd = random.Random(3)
    backdrop("meadow")
    th = THEMES["meadow"]
    scatter("Clouds", ["cloud1", "cloud3", "cloud5", "cloud7", "cloud8"], [-22, -9, 3, 14, 27, 40], 11.5, -24, 2.2,
            [1, 1, 1, 0.95], rnd)
    scatter("Far", ["tree05", "tree08", "tree10", "tree20", "tree23", "tree31"], [-34 + i * 4.3 for i in range(19)], 1.6,
            -18, 1.25, [1, 1, 1, 1], rnd, far=True)
    scatter("Mid", ["tree05", "tree09", "tree11", "tree21", "tree25", "tree32", "tree34"], [-30 + i * 7.5 for i in range(10)],
            -0.1, -9, 1.35, [1, 1, 1, 1], rnd)
    sling()
    machinery()

    # A hut: two posts, a plank across, a target under it and glass on top.
    piece("wood", "pillar", 6.0, 1.0)
    piece("wood", "pillar", 8.14, 1.0)
    piece("wood", "plank", 7.07, 2.5)
    target("green", 7.07, 0.5)
    piece("glass", "sq", 6.2, 3.5)
    piece("glass", "sq", 7.94, 3.5)
    piece("wood", "tri", 7.07, 4.5)
    # A second, taller, with a stone floor between its storeys.
    piece("wood", "pillar", 12.0, 1.0)
    piece("wood", "pillar", 14.14, 1.0)
    piece("stone", "plank", 13.07, 2.5)
    target("pink", 13.07, 0.5)
    piece("glass", "pillar", 12.1, 4.0)
    piece("glass", "pillar", 14.04, 4.0)
    piece("wood", "plank", 13.07, 5.5)
    target("green", 13.07, 3.5)
    piece("wood", "ball", 13.07, 6.5)
    # Something loose between them.
    piece("wood", "block", 10.07, 0.5)
    piece("wood", "sq", 10.07, 1.5)

    ammo(["green", "green", "green", "green"], SLING)
    for i, x in enumerate((-15.5, -12.2, -4.0, 2.5, 17.5, 21.0)):
        sprite("Bush_%d" % i, PIECES, (x, 0.42, -0.2), "Decor", frame="bush", flipX=bool(i % 2))
    scatter("Front", ["grass1", "grass2", "grass3", "grass4", "grass5", "grass6"],
            [LEFT - 4 + i * 1.7 + rnd.uniform(-0.5, 0.5) for i in range(34)], -1.15, 2.0, 2.6, [0.55, 0.78, 0.25, 1], rnd, 0.3)
    hud("1  MEADOW")
    finish("Meadow", "meadow")


def dunes():
    rnd = random.Random(11)
    backdrop("dunes")
    th = THEMES["dunes"]
    scatter("Clouds", ["cloud2", "cloud4", "cloud6", "cloud9"], [-18, -2, 16, 33], 12.2, -24, 2.0, [1, 1, 1, 0.9], rnd)
    scatter("Far", ["piramid", "piramid", "temple"], [-22, -3, 13, 30], 2.0, -18, 2.6, [1, 0.97, 0.9, 1], rnd, 0.35, far=True)
    scatter("Mid", ["tree16", "tree17", "tree18", "tree19"], [-27 + i * 8.2 for i in range(9)], -0.1, -9, 1.5,
            [0.95, 0.95, 0.85, 1], rnd)
    sling()
    machinery()

    # A bunker with a crate of explosive in its doorway.
    piece("stone", "pillar", 4.0, 1.0)
    piece("stone", "pillar", 6.14, 1.0)
    piece("tnt", "sq", 5.07, 0.5)
    piece("wood", "plank", 5.07, 2.5)
    target("pink", 5.07, 3.5)
    piece("glass", "sq", 4.0, 3.5)
    piece("glass", "sq", 6.14, 3.5)

    # A catapult: a plank on a pin, its far end down with a target sitting
    # on it. A stone ball waits on a pillar above the near end - knock it
    # off, and what comes down on one end goes up at the other.
    piece("stone", "tri", 10.6, 0.5)
    lever = piece("wood", "plank", 10.6, 1.28)
    call("set_transform", name=lever, transform={"scale": [1.7, 0.46, 1], "rotation": [0, 0, math.radians(-10)]})
    call("set_physics2d", name=lever, halfExtents=[U * 1.7 / 2 - 0.02, 0.21], density=0.4)
    call("add_joint2d", name=lever, joint="hinge", lowerDegrees=-3, upperDegrees=26)
    target("green", 12.7, 1.45)
    sprite("Perch", PIECES, (7.2, 2.2, -0.1), "World", frame="stone_post_0", lighting="2d", sortOrder=2)
    call("set_transform", name="Perch", transform={"scale": [1.0, 1.4, 1]})
    call("add_physics2d", name="Perch", bodyType="static", shape="box", halfExtents=[0.48, 2.2], friction=0.8,
         castsShadow=False)
    piece("stone", "ball", 7.3, 4.9)

    # A tower, two storeys, with more explosive at its foot.
    piece("stone", "big", 16.0, 1.0)
    piece("tnt", "ball", 17.6, 0.5)
    piece("wood", "pillar", 15.5, 3.0)
    piece("wood", "pillar", 16.5, 3.0)
    piece("stone", "block", 16.0, 4.5)
    target("pink", 16.0, 5.5)
    piece("wood", "tri", 16.0, 6.5)
    piece("stone", "pillar", 19.0, 1.0)
    piece("wood", "block", 19.0, 2.5)
    target("green", 19.0, 3.5)

    ammo(["green", "yellow", "pink", "yellow"], SLING)
    for i, (x, frame) in enumerate(((-15.0, "cactus"), (-5.0, "rock"), (1.8, "cactus"), (22.5, "cactus"), (24.5, "rock"))):
        sprite("Decor_%d" % i, PIECES, (x, 0.45, -0.2), "Decor", frame=frame, flipX=bool(i % 2))
    scatter("Front", ["grass1", "grass3"], [LEFT - 4 + i * 3.1 + rnd.uniform(-1, 1) for i in range(19)], -0.35, 2.0, 1.6,
            [0.85, 0.7, 0.45, 1], rnd, 0.3)
    hud("2  DUNES")
    finish("Dunes", "dunes")


def grove():
    rnd = random.Random(21)
    backdrop("grove")
    th = THEMES["grove"]
    sprite("Moon", SCENERY, (15, 15.5, -28), "Sky", frame="moon_full", color=[0.95, 0.97, 1.0, 1])
    call("set_transform", name="Moon", transform={"scale": [2.2, 2.2, 1]})
    glow("Moon", 5.5, (0.6, 0.7, 1.0), 0.55, 0)
    scatter("Clouds", ["cloud2", "cloud5", "cloud8"], [-20, 0, 22], 12.5, -24, 2.2, [0.35, 0.42, 0.7, 0.55], rnd)
    scatter("Far", ["tree29", "tree30", "tree02", "tree04", "house_grey_front", "tree03"], [-33 + i * 5.1 for i in range(16)],
            1.6, -18, 1.35, th["far"], rnd)
    scatter("Mid", ["tree29", "tree03", "tree30", "tree02", "tree21"], [-30 + i * 8.2 for i in range(9)], -0.1, -9, 1.55,
            [0.20, 0.25, 0.40, 1], rnd)
    sling()
    machinery()

    # Three lamps on ropes. Everything in this level is lit by them and by
    # the moon, and every block stands in their way.
    lantern(1, -5.5, 8.6, 4.2)
    lantern(2, 9.0, 9.6, 3.2, power=1.6, radius=11.0)
    lantern(3, 15.2, 9.4, 4.6, colour=(0.55, 0.9, 1.0))
    lantern(4, 21.5, 8.2, 4.0, colour=(1.0, 0.6, 0.75))

    # A wrecking ball on a chain, pulled back and tied to a wooden block
    # nailed to the top of a pillar. Break the block and the ball swings.
    call("add_object", name="Hook", parent="World", position=[9.0, 9.6, 0])
    call("add_physics2d", name="Hook", bodyType="static", shape="circle", halfExtents=[0.05, 0.05], sensor=True,
         castsShadow=False)
    ball = piece("metal", "ball", 3.9, 4.55)
    call("set_transform", name=ball, transform={"scale": [1.5, 1.5, 1]})
    call("set_physics2d", name=ball, halfExtents=[0.75, 0.75], density=3.0)
    call("add_joint2d", name=ball, joint="distance", connected="Hook", length=7.18, lower=7.18, upper=7.18)
    rope("R_" + ball, [(9.0, 9.6), (3.9, 4.55)], 0.1, (0.55, 0.6, 0.66, 1))
    sprite("Pillar", PIECES, (1.6, 2.2, -0.1), "World", frame="stone_post_0", lighting="2d", sortOrder=2)
    call("set_transform", name="Pillar", transform={"scale": [1.0, 1.4, 1]})
    call("add_physics2d", name="Pillar", bodyType="static", shape="box", halfExtents=[0.48, 2.2], friction=0.8)
    nail = piece("wood", "sq", 1.6, 4.9)
    call("set_physics2d", name=nail, bodyType="static")
    # The tie is the ball's second joint, so it sits on a child of the ball
    # (an object holds one): a rope no longer than it is now.
    call("add_object", name="Tie", parent=ball)
    call("add_joint2d", name="Tie", joint="distance", connected=nail, lower=0, upper=2.33)
    rope("RR_%s__%s" % (nail, ball), [(1.6, 4.9), (3.9, 4.55)], 0.07, (0.5, 0.4, 0.3, 1))

    # What it swings into.
    piece("stone", "pillar", 11.0, 1.0)
    piece("stone", "pillar", 13.14, 1.0)
    piece("wood", "plank", 12.07, 2.5)
    target("green", 12.07, 0.5)
    piece("glass", "pillar", 11.2, 4.0)
    piece("glass", "pillar", 12.94, 4.0)
    piece("wood", "plank", 12.07, 5.5)
    target("blue", 12.07, 3.5)
    piece("wood", "tri", 12.07, 6.5)

    piece("stone", "sq", 17.0, 0.5)
    piece("stone", "sq", 19.0, 0.5)
    piece("wood", "plank", 18.0, 1.5)
    piece("glass", "big", 18.0, 3.0)
    target("yellow", 18.0, 4.5)
    piece("tnt", "sq", 21.0, 0.5)
    target("blue", 22.6, 0.5)

    ammo(["green", "blue", "pink", "blue"], SLING)
    # Fireflies: sprites the script wanders about.
    call("add_object", name="Fireflies", parent="World")
    for i in range(14):
        sprite("Firefly_%d" % i, T + "fx/glow.png", (rnd.uniform(-16, 24), rnd.uniform(1.2, 7.5), 0.9), "Fireflies",
               blend="additive", pixelsPerUnit=260, color=[0.75, 1.0, 0.45, 0.9], sortOrder=9)
    scatter("Front", ["grass2", "grass4", "grass6"], [LEFT - 4 + i * 1.9 + rnd.uniform(-0.5, 0.5) for i in range(30)], -1.0,
            2.0, 2.4, [0.05, 0.08, 0.16, 1], rnd, 0.3)
    hud("3  GROVE")
    finish("Grove", "grove")


def keep():
    rnd = random.Random(31)
    backdrop("keep")
    th = THEMES["keep"]
    scatter("Clouds", ["cloud1", "cloud3", "cloud6", "cloud7"], [-24, -8, 10, 28, 42], 12.0, -24, 2.3, [1, 1, 1, 0.95], rnd)
    scatter("Far", ["castle_grey", "tower_grey", "tree12", "tree22", "tower_grey", "tree33"], [-30 + i * 6.4 for i in range(12)],
            1.6, -18, 1.5, [1, 1, 1, 1], rnd, far=True)
    scatter("Mid", ["tree04", "tree12", "tree15", "tree22", "tree33", "tree35"], [-28 + i * 7.6 for i in range(10)], -0.1, -9,
            1.5, [0.95, 0.97, 1, 1], rnd)
    sling()
    machinery()

    # A mill in the way: two beams on one pin with a motor. A shot has to be
    # timed through it - or thrown over.
    for i, rot in enumerate((0, 90)):
        name = piece("metal", "plank", 2.0, 6.0, rot)
        call("set_transform", name=name, transform={"rotation": [0, 0, math.radians(rot)], "scale": [1.5, 0.42, 1]})
        call("set_physics2d", name=name, halfExtents=[U * 1.5 / 2, 0.2], density=4.0, gravityScale=0)
        call("add_joint2d", name=name, joint="hinge", motorSpeedDegrees=-55, maxMotorForce=1000000)
        if i == 1:
            # Two beams, one pin: they would fight each other, so a third
            # joint (on a child - an object holds one) says they do not touch.
            call("add_object", name="MillLink", parent=name)
            call("add_joint2d", name="MillLink", joint="ignore", connected=first)
        first = name
    sprite("MillHub", PIECES, (2.0, 6.0, 0.3), "World", frame="metal_ball_0", lighting="2d", sortOrder=5)
    call("set_transform", name="MillHub", transform={"scale": [0.8, 0.8, 1]})
    sprite("MillMast", PIECES, (2.0, 2.9, -0.3), "World", frame="stone_post_0", lighting="2d", sortOrder=1)
    call("set_transform", name="MillMast", transform={"scale": [0.6, 1.95, 1]})

    # The gatehouse.
    piece("stone", "pillar", 9.0, 1.0)
    piece("stone", "pillar", 11.14, 1.0)
    piece("stone", "plank", 10.07, 2.5)
    target("blue", 10.07, 0.5)
    piece("wood", "pillar", 9.3, 4.0)
    piece("wood", "pillar", 10.84, 4.0)
    piece("stone", "plank", 10.07, 5.5)
    target("blue", 10.07, 3.5)
    piece("stone", "tri", 10.07, 6.5)

    # A trap: a slab of metal hangs over two targets on a rope that runs
    # over two wheels to a weight. A block of metal sits on the weight and
    # keeps it down. Shift that block and the slab comes down.
    slab = piece("metal", "plank", 15.6, 6.2)
    call("set_physics2d", name=slab, density=2.6, fixedRotation=True, linearDamping=0.1)
    sprite("Weight", PIECES, (20.0, 0.5, 0), "World", frame="stone_sq_0", lighting="2d", sortOrder=3,
           color=[0.8, 0.85, 1.0, 1])
    call("add_physics2d", name="Weight", shape="box", halfExtents=[0.48, 0.48], density=0.6, fixedRotation=True,
         friction=0.8, castsShadow=False)
    call("add_joint2d", name=slab, joint="pulley", connected="Weight", anchor=[0, 0.5], connectedAnchor=[0, 0.5],
         groundAnchor=[15.6, 11.5], connectedGroundAnchor=[20.0, 11.5])
    for name, x in (("WheelA", 15.6), ("WheelB", 20.0)):
        sprite(name, PIECES, (x, 11.5, 0.2), "World", frame="metal_ball_0", lighting="2d", sortOrder=5)
        call("set_transform", name=name, transform={"scale": [0.7, 0.7, 1]})
    rope("RR_%s__Weight" % slab, [(15.6, 6.7), (15.6, 11.5), (20.0, 11.5), (20.0, 1.0)], 0.1, (0.45, 0.36, 0.28, 1))
    piece("metal", "big", 20.0, 2.0)
    piece("tnt", "sq", 21.6, 0.5)
    # under the slab
    piece("glass", "sq", 14.4, 0.5)
    piece("glass", "sq", 16.8, 0.5)
    target("yellow", 15.2, 0.5)
    target("pink", 16.0, 0.5)

    ammo(["green", "yellow", "blue", "pink", "green"], SLING)
    for i, x in enumerate((-15.5, -12.0, -3.5, 5.5, 23.5, 25.5)):
        sprite("Decor_%d" % i, PIECES, (x, 0.42, -0.2), "Decor", frame="frozenbush", flipX=bool(i % 2))
    scatter("Front", ["grass5", "grass6"], [LEFT - 4 + i * 2.4 + rnd.uniform(-0.6, 0.6) for i in range(24)], -0.6, 2.0, 2.0,
            [0.86, 0.92, 1.0, 1], rnd, 0.3)
    hud("4  KEEP")
    finish("Keep", "keep")


def title():
    rnd = random.Random(5)
    backdrop("meadow")
    scatter("Clouds", ["cloud1", "cloud3", "cloud5", "cloud7", "cloud8"], [-22, -9, 3, 14, 27, 40], 12.0, -24, 2.2,
            [1, 1, 1, 0.95], rnd)
    scatter("Far", ["tree05", "tree08", "tree10", "tree20", "tree23", "tree31"], [-34 + i * 4.3 for i in range(19)], 1.6,
            -18, 1.25, [1, 1, 1, 1], rnd, far=True)
    scatter("Mid", ["tree05", "tree09", "tree11", "tree21", "tree25", "tree32", "tree34"], [-30 + i * 7.5 for i in range(10)],
            -0.1, -9, 1.35, [1, 1, 1, 1], rnd)
    sling()
    sprite("Mascot", PIECES, (SLING[0], SLING[1], 0.3), "World", frame="alien_green_round", lighting="2d", sortOrder=5)
    # Something to watch behind the menu: a tower the script keeps
    # dropping things on. The same rules as a level run it - the script
    # finds Blocks and Targets here just as it does there.
    machinery()
    for x in (9.0, 11.14):
        piece("wood", "pillar", x, 1.0)
    piece("wood", "plank", 10.07, 2.5)
    target("green", 10.07, 0.5)
    for x in (9.3, 10.84):
        piece("glass", "pillar", x, 4.0)
    piece("stone", "plank", 10.07, 5.5)
    target("pink", 10.07, 3.5)
    piece("wood", "tri", 10.07, 6.5)
    piece("wood", "block", 13.5, 0.5)
    piece("wood", "sq", 13.5, 1.5)
    target("yellow", 13.5, 2.5)
    for i, colour in enumerate(("blue", "yellow", "pink")):
        name = "Drop_%d" % (i + 1)
        sprite(name, PIECES, (LEFT - 12 - i * 2, -26, 0.3), "World", frame="alien_%s_round" % colour, lighting="2d",
               sortOrder=5)
        call("add_physics2d", name=name, bodyType="kinematic", shape="circle", halfExtents=[0.48, 0.48], density=1.4,
             friction=0.5, bounciness=0.3, fixedRotation=False, castsShadow=False)
    for i, x in enumerate((-15.5, -12.2, -4.0, 2.5, 17.5, 21.0)):
        sprite("Bush_%d" % i, PIECES, (x, 0.42, -0.2), "Decor", frame="bush", flipX=bool(i % 2))
    scatter("Front", ["grass1", "grass2", "grass3", "grass4", "grass5", "grass6"],
            [LEFT - 4 + i * 1.7 + rnd.uniform(-0.5, 0.5) for i in range(34)], -1.15, 2.0, 2.6, [0.55, 0.78, 0.25, 1], rnd, 0.3)

    call("add_object", name="Menu")
    call("add_ui", object="Menu", kind="canvas")
    call("set_ui", object="Menu", properties={"referenceWidth": 1280, "referenceHeight": 720})
    text("LogoShade", "Menu", "TOPPLE", [0.5, 0], [-500, 66], [500, 226], 150, "center", (0.16, 0.2, 0.3, 0.55), "future")
    text("Logo", "Menu", "TOPPLE", [0.5, 0], [-500, 58], [500, 218], 150, "center", (1.0, 0.82, 0.2, 1), "future")
    image("TagPlate", "Menu", "panel.png", [0.5, 0], [-330, 226], [330, 274], (0.10, 0.13, 0.20, 0.62), [16, 16, 16, 20])
    text("Tag", "TagPlate", "A PHYSICS TOY BUILT WITH PYROS3D", [0, 0], [0, 0], [660, 44], 22, "center", (1, 1, 1, 0.95))
    names = ("MEADOW", "DUNES", "GROVE", "KEEP")
    colours = ("green", "yellow", "blue", "red")
    for i in range(4):
        x = -438 + i * 222
        button("Level%d" % (i + 1), "Menu", "button_%s.png" % colours[i], "", [0.5, 0.5], [x, 4], [x + 210, 178])
        text("Level%d_Number" % (i + 1), "Level%d" % (i + 1), str(i + 1), [0, 0], [0, 6], [210, 86], 64, "center", (1, 1, 1, 1), "future")
        text("Level%d_Name" % (i + 1), "Level%d" % (i + 1), names[i], [0, 0], [0, 84], [210, 114], 22, "center", (1, 1, 1, 0.95))
        for k in range(3):
            sx = 36 + k * 48
            image("Level%d_StarBack%d" % (i + 1, k + 1), "Level%d" % (i + 1), "star_empty.png", [0, 0], [sx, 116], [sx + 42, 158],
                  (1, 1, 1, 0.55))
            image("Level%d_Star%d" % (i + 1, k + 1), "Level%d" % (i + 1), "star.png", [0, 0], [sx + 3, 119], [sx + 39, 155])
    call("set_game_view_2d", center=[3.0, 6.2], zoom=8.0, bounds=[LEFT, -2.5, RIGHT, 30], gravity=[0, -22],
         autoParallax=True)
    call("set_scene_main_script", path="scenes/Title.lua")
    call("save_scene_as", path="scenes/Title.json")
    print("built scenes/Title.json")


LEVELS = {"Title": title, "Meadow": meadow, "Dunes": dunes, "Grove": grove, "Keep": keep}


def atlases():
    """One picture and one sheet for the pieces, another for the scenery; the
    pieces get a normal map so the 2D lights have something to shade."""
    for folder, output, trim in (("art/pieces", T + "pieces", False), ("art/scenery", T + "scenery", True)):
        call("pack_sprite_atlas", folder=folder, output=output, padding=4, trim=trim, pixelsPerUnit=PPU,
             filter="linear", clipFps=0, overwrite=True)
    subprocess.check_call([sys.executable, os.path.join(PROJECT, "tools", "make_normals.py")])
    call("edit_spritesheet", path=PIECES, normalImage=T + "pieces_n.png")
    call("save_spritesheet")


def main():
    call("open_project", path=PROJECT)
    wanted = sys.argv[1:] or list(LEVELS)
    if not sys.argv[1:] or not os.path.exists(os.path.join(PROJECT, PIECES)):
        atlases()
    for name in wanted:
        COUNT.clear()
        call("new_scene", kind="2d")
        LEVELS[name]()


if __name__ == "__main__":
    main()
