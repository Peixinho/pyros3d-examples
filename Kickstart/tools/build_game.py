#!/usr/bin/env python3
"""Builds Kickstart by driving a running PyrosBuilder.

    1. blender --background --python tools/make_bike.py -- <work> ; make_track.py -- <work> art/textures
    2. start PyrosBuilder
    3. python3 tools/build_game.py <work>           (every track)
       python3 tools/build_game.py <work> 1         (one)

<work> is the folder the two Blender scripts wrote into (parts/, tracks/,
bike.json, rest.json).

A track is a scene: its dirt (an Extrusion2D - an outline given depth, with
its collider; drag its points in the editor to reshape the track), a Start
and a Finish object, four bikes, a camera, the interface. A bike is three 2D bodies -
a chassis and two wheels on sprung wheel joints - with the 3D parts hung on
them; the script (assets/lua/kickstart/game.lua) does the rest: it turns the
rear wheel, leans the rider, and moves the fork, the swingarm and the rider's
limbs to where the bodies are.
"""
import json
import os
import socket
import sys

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK = sys.argv[1] if len(sys.argv) > 1 else sys.exit(__doc__)
BIKE = json.load(open(os.path.join(WORK, "bike.json")))
REST = json.load(open(os.path.join(WORK, "rest.json")))
RIDERS = [  # name, the paint, the jersey
    ("You", [0.05, 0.25, 0.85], [0.05, 0.25, 0.85]),
    ("Rojo", [0.85, 0.08, 0.06], [0.85, 0.08, 0.06]),
    ("Lima", [0.20, 0.72, 0.12], [0.95, 0.85, 0.10]),
    ("Kuro", [0.95, 0.55, 0.05], [0.12, 0.12, 0.14]),
]


def endpoint():
    tmp = os.environ.get("TMPDIR", "/tmp")
    for name in ("pyros3d-driver.json", "pyros3d-editor.json"):
        path = os.path.join(tmp, name)
        if os.path.exists(path):
            return json.load(open(path))
    sys.exit("PyrosBuilder is not running")


CFG = endpoint()


def call(cmd, **args):
    s = socket.create_connection(("127.0.0.1", CFG["port"]), timeout=300)
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
        sys.exit("%s failed: %s\n  args: %s" % (cmd, result.get("error") if isinstance(result, dict) else result, json.dumps(args)[:300]))
    return result


def model(name, source, at, parent=None):
    """A model in the scene. `source` is a .glb the editor imports (once) or a .p3dm already in the project."""
    stem = os.path.splitext(os.path.basename(source))[0]
    packed = os.path.join(PROJECT, "assets", "models", stem, stem + ".p3dm")
    # (imported again when the source is newer than what the project holds)
    fresh = os.path.exists(packed) and os.path.getmtime(packed) >= os.path.getmtime(source)
    args = dict(name=name, file=packed if fresh else source, position=list(at))
    if parent:
        args["parent"] = parent
    call("add_model", **args)


T = "assets/textures/"


# ----- interface -------------------------------------------------------------------------
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
    call("set_ui", object=name, properties={"referenceWidth": 1280, "referenceHeight": 720, "scaleMode": "Fit"})


PLATE = (0.10, 0.13, 0.22, 0.80)
INK = (0.20, 0.24, 0.32, 1)


def hud(track_name):
    canvas("HUD")
    image("PosPlate", "HUD", "panel.png", [0, 0], [16, 14], [196, 96], PLATE, [16, 16, 16, 20])
    text("Pos", "PosPlate", "1", [0, 0], [10, 2], [84, 78], 62, "center", (1.0, 0.82, 0.2, 1), "future")
    text("PosOf", "PosPlate", "/ 4", [0, 0], [84, 22], [170, 70], 30, "left", (1, 1, 1, 0.9))
    image("TimePlate", "HUD", "panel.png", [0.5, 0], [-150, 14], [150, 96], PLATE, [16, 16, 16, 20])
    text("Time", "TimePlate", "0:00.00", [0, 0], [0, 2], [300, 52], 38, "center", (1, 1, 1, 1), "future")
    text("Best", "TimePlate", "@nobest", [0, 0], [0, 48], [300, 78], 18, "center", (1, 1, 1, 0.75))
    image("ScorePlate", "HUD", "panel.png", [0, 0], [206, 14], [386, 66], PLATE, [16, 16, 16, 20])
    text("Score", "ScorePlate", "0", [0, 0], [0, 0], [180, 50], 30, "center", (1.0, 0.82, 0.2, 1), "future")
    # where everyone is along the track: a bar, and a dot a rider
    image("Bar", "HUD", "panel.png", [0.5, 0], [-260, 106], [260, 118], (1, 1, 1, 0.55), [5, 5, 5, 5])
    for i in (3, 2, 1, 0):
        rgb = RIDERS[i][1]
        image("Dot%d" % i, "Bar", "round_grey.png", [0, 0.5], [-9, -9], [9, 9], (rgb[0], rgb[1], rgb[2], 1))
    button("BtnMenu", "HUD", "round_grey.png", [1, 0], [-84, 16], [-24, 76], False)
    text("BtnMenu_Icon", "BtnMenu", "<", [0, 0], [-2, -4], [58, 56], 30, "center", INK)
    button("BtnRetry", "HUD", "round_blue.png", [1, 0], [-154, 16], [-94, 76], False)
    image("BtnRetry_Icon", "BtnRetry", "repeat_light.png", [0, 0], [13, 10], [47, 44])
    # the big words in the middle: the countdown, a flip
    text("BigShade", "HUD", "", [0.5, 0.5], [-500, -196], [500, -56], 120, "center", (0.05, 0.06, 0.10, 0.6), "future")
    text("Big", "HUD", "", [0.5, 0.5], [-500, -200], [500, -60], 120, "center", (1.0, 0.82, 0.2, 1), "future")
    text("Hint", "HUD", "@hint", [0.5, 1], [-600, -60], [600, -24], 22, "center", (1, 1, 1, 0.8))
    # for thumbs: lean on the left, brake and gas on the right. Shown once the screen has been touched.
    image("PadBack", "HUD", "round_grey.png", [0, 1], [30, -190], [180, -40], (1, 1, 1, 0.5))
    image("PadBack_Icon", "PadBack", "arrow_left_light.png", [0.5, 0.5], [-40, -40], [40, 40], (0.2, 0.24, 0.32, 0.9))
    image("PadFwd", "HUD", "round_grey.png", [0, 1], [200, -190], [350, -40], (1, 1, 1, 0.5))
    image("PadFwd_Icon", "PadFwd", "arrow_right_light.png", [0.5, 0.5], [-40, -40], [40, 40], (0.2, 0.24, 0.32, 0.9))
    image("PadBrake", "HUD", "round_blue.png", [1, 1], [-350, -170], [-220, -40], (1, 1, 1, 0.6))
    text("PadBrake_Label", "PadBrake", "@brake", [0.5, 0.5], [-60, -20], [60, 20], 20, "center", (1, 1, 1, 0.95))
    image("PadTrick", "HUD", "round_grey.png", [1, 1], [-330, -330], [-200, -200], (1.0, 0.85, 0.3, 0.75))
    text("PadTrick_Label", "PadTrick", "@trick", [0.5, 0.5], [-60, -20], [60, 20], 20, "center", (0.2, 0.24, 0.32, 1))
    image("PadGas", "HUD", "round_green.png", [1, 1], [-200, -210], [-30, -40], (1, 1, 1, 0.7))
    text("PadGas_Label", "PadGas", "@gas", [0.5, 0.5], [-70, -26], [70, 26], 30, "center", (1, 1, 1, 0.95), "future")
    # the card at the end. Saved showing; the script hides it.
    image("Card", "HUD", "panel.png", [0.5, 0.5], [-300, -190], [300, 190], (1, 1, 1, 0.97), [16, 16, 16, 20])
    text("CardTitle", "Card", "@finished", [0.5, 0], [-280, 20], [280, 96], 54, "center", INK, "future")
    text("CardTrack", "Card", track_name, [0.5, 0], [-280, 96], [280, 132], 22, "center", (0.2, 0.24, 0.32, 0.7))
    text("CardTime", "Card", "0:00.00", [0.5, 0], [-280, 136], [280, 206], 56, "center", (0.85, 0.2, 0.15, 1), "future")
    text("CardBest", "Card", "", [0.5, 0], [-280, 204], [280, 236], 22, "center", INK)
    text("CardScore", "Card", "", [0.5, 0], [-280, 238], [280, 272], 24, "center", (0.85, 0.55, 0.05, 1), "future")
    for name, texture, x, key, colour in (("CardMenu", "button_grey.png", -270, "@menu", INK),
                                           ("CardRetry", "button_blue.png", -85, "@again", (1, 1, 1, 1)),
                                           ("CardNext", "button_green.png", 100, "@next", (1, 1, 1, 1))):
        button(name, "Card", texture, [0.5, 1], [x, -92], [x + 170, -28])
        text(name + "_Label", name, key, [0, 0], [0, -3], [170, 61], 22, "center", colour)
    image("Fade", "HUD", "panel.png", [0, 0], [-40, -40], [40, 40], (0, 0, 0, 1), None, [1, 1])


def bike(index, lane_z, start_x, ground_y):
    """One bike: bodies, joints, and the parts hung on them."""
    name, paint, jersey = RIDERS[index]
    b = "Bike%d" % index
    layer = index + 1                       # a layer each: bikes pass through each other, and all of them ride the ground (layer 0)
    ox, oy = start_x, ground_y + 0.02
    ra, fa = BIKE["rearAxle"], BIKE["frontAxle"]
    call("add_object", name=b, position=[ox, oy, lane_z])
    # The chassis: the frame and the rider's weight, as one shape.
    call("add_physics2d", name=b, shape="polygon", polygon=[[-0.50, 0.50], [0.42, 0.46], [0.46, 0.98], [-0.58, 0.98]],
         density=1.6, friction=0.4, layer=layer, collidesWith=[0], angularDamping=0.6, fixedRotation=False, castsShadow=False)
    for wheel, axle, radius, axis in (("WR", ra, BIKE["rRear"], [0.12, 1.0]), ("WF", fa, BIKE["rFront"], [-BIKE["forkAxis"][0], -BIKE["forkAxis"][1]])):
        w = "%s_%s" % (b, wheel)
        call("add_object", name=w, position=[ox + axle[0], oy + axle[1], lane_z])
        call("add_physics2d", name=w, shape="circle", halfExtents=[radius, radius], density=0.9, friction=1.6 if wheel == "WR" else 1.1,
             layer=layer, collidesWith=[0], fixedRotation=False, castsShadow=False)
        # The suspension: a wheel joint lets the wheel turn, and slide along one line against a spring.
        call("add_joint2d", name=w, joint="wheel", connected=b, axis=axis, spring=True, hertz=4.2, damping=0.75,
             limit=True, lower=-0.16, upper=0.12)
        model("%s_Model" % w, os.path.join(WORK, "parts", "WheelRear_0.glb" if wheel == "WR" else "WheelFront_0.glb"), (0, 0, 0), parent=w)
    # What hangs on the chassis. The script moves the fork, the swingarm and the rider every frame.
    for part in ("Chassis", "ForkLower", "Swingarm", "Rider_Torso", "Rider_Head", "Rider_UpperArm", "Rider_ForeArm", "Rider_Thigh", "Rider_Shin"):
        rx, ry = REST[part]
        # (the painted parts are the rider's own: Chassis_2.glb is the third rider's)
        own = part not in ("Swingarm", "Rider_Thigh", "Rider_Shin")
        model("%s_%s" % (b, part), os.path.join(WORK, "parts", part + ("_%d" % index if own else "_0") + ".glb"), (rx, ry, 0), parent=b)
    # The dirt the rear wheel throws: a particle system the script turns up with the gas. Its
    # particles stop at the track (Collide 2D), so a roost lands instead of falling through.
    call("add_particles", name=b + "_Roost", parent=b + "_WR", position=[0, -0.2, 0], texture=T + "fx/soft.png", maxParticles=90,
         looping=True, emissionRate=0, minLifetime=0.5, maxLifetime=0.9, direction=[-0.7, 0.7, 0], spreadAngleDegrees=18,
         minSpeed=4, maxSpeed=8, gravity=[0, -16, 0], startSize=0.16, endSize=0.34, startColor=[0.50, 0.37, 0.24, 0.95],
         endColor=[0.50, 0.38, 0.26, 0.0], collide2D=True, bounce=0.15)
    call("add_audio", name=b + "_Engine", parent=b, file="assets/sounds/engine.wav", looping=True, volume=0.0)
    return b


def height_at(pts, x):
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        if a[0] <= x <= b[0]:
            return a[1] + (b[1] - a[1]) * (x - a[0]) / max(1e-6, b[0] - a[0])
    return pts[-1][1]


def title():
    """The menu: the first track's stadium behind it, and a button a track."""
    t = json.load(open(os.path.join(WORK, "tracks", "track1.json")))
    call("new_scene", kind="3d")
    call("set_renderer", type="forward")
    call("set_ambient", color=[0.42, 0.46, 0.60], intensity=1.0, background=[0.05, 0.07, 0.16])
    call("add_light", name="Floods", type="directional", direction=[-0.30, -1.0, -0.62], color=[1.0, 0.97, 0.90], intensity=1.05,
         castingShadows=True, shadowMapSize=2048, shadowFar=60.0)
    call("add_camera", name="Cam", fov=36.0, near=0.5, far=600.0, active=True, position=[66, 4.0, 15])
    call("add_object", name="Track", position=[0, 0, 0])
    call("add_extrusion2d", object="Track", points=[p for p in t["points"] if p[0] < 190], smooth=3, depth=t["depth"], floor=t["base"], tile=3.0,
         skin="assets/textures/dirt_top.jpg", face="assets/textures/dirt_side.jpg", skinColor=[1, 1, 1, 1], faceColor=[1, 1, 1, 1])
    model("Stadium", os.path.join(WORK, "tracks", "Stadium1.glb"), (0, 0, 0))
    st = json.load(open(os.path.join(WORK, "tracks", "stadium1.json")))
    call("add_object", name="Crowd")
    x, k = st["x0"], 0
    while x < 150:
        model("Crowd_%d" % k, os.path.join(WORK, "tracks", "CrowdBay%d.glb" % (k % 3)), (x, 0, 0), parent="Crowd")
        x += st["bay"]
        k += 1
    call("add_audio", name="CrowdAmb", file="assets/sounds/crowd.wav", looping=True, volume=0.25)
    canvas("Menu")
    text("LogoShade", "Menu", "KICKSTART", [0.5, 0], [-600, 36], [600, 166], 120, "center", (0.03, 0.04, 0.08, 0.7), "future")
    text("Logo", "Menu", "KICKSTART", [0.5, 0], [-600, 28], [600, 158], 120, "center", (1.0, 0.72, 0.1, 1), "future")
    for i in range(3):
        x = -470 + i * 320
        name = "Track%d" % (i + 1)
        button(name, "Menu", ("button_green.png", "button_yellow.png", "button_red.png")[i], [0.5, 1], [x, -230], [x + 300, -70])
        text(name + "_Name", name, "@track_%d" % (i + 1), [0, 0], [0, 14], [300, 70], 26, "center", INK if i == 1 else (1, 1, 1, 1))
        text(name + "_Best", name, "@nobest", [0, 0], [0, 82], [300, 126], 24, "center", INK if i == 1 else (1, 1, 1, 0.95), "future")
    button("Language", "Menu", "button_grey.png", [1, 0], [-150, 16], [-24, 66])
    text("Language_Label", "Language", "EN", [0, 0], [0, -3], [126, 47], 22, "center", INK)
    image("Fade", "Menu", "panel.png", [0, 0], [-40, -40], [40, 40], (0, 0, 0, 1), None, [1, 1])
    open(os.path.join(PROJECT, "scenes", "Title.lua"), "w").write(
        "-- The title: the same script, told it is the menu.\n"
        "return assert(loadfile(ASSETS_PATH .. \"lua/kickstart/game.lua\"))()({ menu = true })\n")
    call("set_scene_main_script", path="scenes/Title.lua")
    call("save_scene_as", path="scenes/Title.json")
    print("built scenes/Title.json")


def track(number):
    t = json.load(open(os.path.join(WORK, "tracks", "track%d.json" % number)))
    pts = t["points"]
    call("new_scene", kind="3d")
    call("set_renderer", type="forward")
    # An evening under floodlights: a dark sky, and one hard white light from high in front.
    call("set_ambient", color=[0.42, 0.46, 0.60], intensity=1.0, background=[0.05, 0.07, 0.16])
    call("add_light", name="Floods", type="directional", direction=[-0.30, -1.0, -0.62], color=[1.0, 0.97, 0.90], intensity=1.05,
         castingShadows=True, shadowMapSize=2048, shadowFar=60.0)
    call("add_camera", name="Cam", fov=36.0, near=0.5, far=600.0, active=True, position=[0, 3, 16])
    # The dirt: an outline given depth. Its points are what the track is - drag them in the
    # view (Edit Outline) and the mesh and the collider both follow. A static body of its own,
    # on layer 0, which is all the bikes collide with.
    call("add_object", name="Track", position=[0, 0, 0])
    call("add_physics2d", name="Track", bodyType="static", shape="chain", polygon=[[0, 0], [1, 0]], loop=False, friction=1.0, layer=0,
         castsShadow=False)
    call("add_extrusion2d", object="Track", points=pts, smooth=3, depth=t["depth"], floor=t["base"], tile=3.0,
         skin="assets/textures/dirt_top.jpg", face="assets/textures/dirt_side.jpg", skinColor=[1, 1, 1, 1], faceColor=[1, 1, 1, 1])
    # Where the race starts and ends: two objects, each with its board. Move one and the race moves with it.
    half = t["depth"] / 2.0
    for name, x, board in (("Start", 0.0, "BoardStart"), ("Finish", float(t["length"]), "BoardFinish")):
        y = height_at(pts, x)
        call("add_object", name=name, position=[x, y, 0])
        model(name + "_Board", os.path.join(WORK, "tracks", board + ".glb"), (0, 0, -half - 0.35), parent=name)
    model("Stadium", os.path.join(WORK, "tracks", "Stadium%d.glb" % number), (0, 0, 0))
    # The crowd, a bay at a time: three bays' worth of people, set side by side along the stand.
    st = json.load(open(os.path.join(WORK, "tracks", "stadium%d.json" % number)))
    call("add_object", name="Crowd")
    x, k = st["x0"], 0
    while x < st["x1"] - 2:
        model("Crowd_%d" % k, os.path.join(WORK, "tracks", "CrowdBay%d.glb" % (k % 3)), (x, 0, 0), parent="Crowd")
        x += st["bay"]
        k += 1
    half = t["depth"] / 2.0
    for i in range(len(RIDERS)):
        lane_z = half - (i + 0.5) * t["depth"] / t["lanes"]          # the player nearest the camera
        bike(i, lane_z, -1.6, 0.0)
    call("add_audio", name="CrowdAmb", file="assets/sounds/crowd.wav", looping=True, volume=0.22)
    hud(t["name"].upper())
    script = os.path.join(PROJECT, "scenes", "Track%d.lua" % number)
    open(script, "w").write("-- A track: its scene is the stage; the rules are in assets/lua/kickstart/game.lua.\n"
                            "return assert(loadfile(ASSETS_PATH .. \"lua/kickstart/game.lua\"))()({ track = %d, name = %s })\n" % (number, json.dumps(t["name"])))
    call("set_scene_main_script", path="scenes/Track%d.lua" % number)
    call("save_scene_as", path="scenes/Track%d.json" % number)
    print("built scenes/Track%d.json  (%s, %d m)" % (number, t["name"], t["length"]))


def main():
    call("open_project", path=PROJECT)
    numbers = [int(a) for a in sys.argv[2:] if a.isdigit()] or [1, 2, 3]
    if len(sys.argv) <= 2 or "title" in sys.argv:
        title()
    for n in numbers:
        if "title" in sys.argv and len(sys.argv) == 3:
            break
        track(n)


if __name__ == "__main__":
    main()
