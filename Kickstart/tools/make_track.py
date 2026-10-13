# A motocross track from a list of obstacles: the dirt as a mesh (its top, the
# cut face towards the camera, lane lines), and its outline for the 2D physics.
#
#   blender --background --python make_track.py -- <out_dir> <textures_dir> [track numbers...]
#
# The game is side on: +X along the track, +Z up here (Y up once exported),
# and the track is DEPTH wide across. Lengths are metres.
import bpy, bmesh, math, sys, os, json

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT, TEX = argv[0], argv[1]
WHICH = [int(a) for a in argv[2:]]

DEPTH = 7.0            # how wide the dirt is, across
BASE = -6.0            # how far down the cut face goes
STEP = 0.25            # a slice of mesh
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

def image_material(name, file, scale):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(os.path.join(TEX, file))
    b = nt.nodes["Principled BSDF"]
    nt.links.new(tex.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 0.95
    return m

def flat(name, rgb, rough=0.8):
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (rgb[0], rgb[1], rgb[2], 1); b.inputs["Roughness"].default_value = rough
    return m

def build(number):
    name, length, obstacles = TRACKS[number]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    top = image_material("DirtTop", "brown_mud_dry_diff.jpg", 3.0)
    side = image_material("DirtSide", "dirt_diff.jpg", 3.0)
    chalk = flat("Chalk", (0.92, 0.90, 0.84))
    x0, x1 = -30.0, length + 40.0
    n = int((x1 - x0) / STEP) + 1
    xs = [x0 + i * STEP for i in range(n)]
    hs = [height(obstacles, x) for x in xs]

    me = bpy.data.meshes.new("Track")
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    half = DEPTH / 2
    def quad(a, b, c, d, mat, uvs):
        f = bm.faces.new((a, b, c, d)); f.material_index = mat; f.smooth = (mat == 0)
        for loop, t in zip(f.loops, uvs): loop[uv].uv = t
    prev = None
    for i in range(n):
        x, h = xs[i], hs[i]
        row = (bm.verts.new((x, half, h)), bm.verts.new((x, -half, h)), bm.verts.new((x, -half, BASE)))      # back top, front top, front base
        if prev:
            xa, xb = xs[i - 1], x
            # the top, seen from above: +Z
            quad(prev[1], row[1], row[0], prev[0], 0, [(xa / 3, 0), (xb / 3, 0), (xb / 3, DEPTH / 3), (xa / 3, DEPTH / 3)])
            # the cut face, towards the camera: -Y
            quad(prev[2], row[2], row[1], prev[1], 1, [(xa / 4, BASE / 4), (xb / 4, BASE / 4), (xb / 4, hs[i] / 4), (xa / 4, hs[i - 1] / 4)])
        prev = row
    bm.normal_update()
    bm.to_mesh(me); bm.free()
    me.materials.append(top); me.materials.append(side)
    track = bpy.data.objects.new("Track", me); bpy.context.scene.collection.objects.link(track)

    # lane lines: thin strips of chalk a finger above the dirt
    bm = bmesh.new()
    for lane in range(1, LANES):
        y = -half + DEPTH * lane / LANES
        prev = None
        for i in range(n):
            if xs[i] < 0 or xs[i] > length: prev = None; continue
            dashed = int(xs[i] / 2.0) % 2 == 0
            row = (bm.verts.new((xs[i], y + 0.04, hs[i] + 0.012)), bm.verts.new((xs[i], y - 0.04, hs[i] + 0.012)))
            if prev and dashed: bm.faces.new((prev[1], row[1], row[0], prev[0]))
            prev = row
    # start and finish lines, solid, right across
    for at in (0.0, float(length)):
        hh = height(obstacles, at)
        a = [bm.verts.new((at - 0.15, half, hh + 0.014)), bm.verts.new((at - 0.15, -half, hh + 0.014)), bm.verts.new((at + 0.15, -half, hh + 0.014)), bm.verts.new((at + 0.15, half, hh + 0.014))]
        bm.faces.new((a[1], a[2], a[3], a[0]))
    lm = bpy.data.meshes.new("Lines"); bm.normal_update(); bm.to_mesh(lm); bm.free(); lm.materials.append(chalk)
    lines = bpy.data.objects.new("Lines", lm); bpy.context.scene.collection.objects.link(lines)

    os.makedirs(os.path.join(OUT, "tracks"), exist_ok=True)
    for o, stem in ((track, "Track%d" % number), (lines, "Lines%d" % number)):
        for x in bpy.context.scene.objects: x.select_set(False)
        o.select_set(True); bpy.context.view_layer.objects.active = o
        bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "tracks", stem + ".glb"), use_selection=True, export_format='GLB',
                                  export_apply=True, export_yup=True, export_materials='EXPORT')
    # the outline the wheels run on: a point every half metre, and what the game needs to know
    pts = [[round(xs[i], 3), round(hs[i], 3)] for i in range(0, n, 2)]
    json.dump({"name": name, "length": length, "depth": DEPTH, "lanes": LANES, "base": BASE, "points": pts,
               "obstacles": [list(o) for o in obstacles]},
              open(os.path.join(OUT, "tracks", "track%d.json" % number), "w"))
    print("TRACK", number, name, len(pts), "points")

for number in (WHICH or sorted(TRACKS)):
    build(number)
