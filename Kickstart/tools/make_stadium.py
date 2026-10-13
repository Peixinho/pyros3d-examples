# The stadium round a track: the floor, the barrier with its boards, the
# stands and the crowd in them, the roof and its lights, light towers, the
# scoreboard, tuff blocks along the dirt, the start gate and the finish arch.
#
#   blender --background --python make_stadium.py -- <work> <textures_dir> [track numbers...]
#
# Reads <work>/tracks/track<n>.json (make_track.py wrote it), writes
# <work>/tracks/Stadium<n>.glb and Crowd<n>.glb. +X along the track, +Z up,
# +Y away from the camera.
import bpy, bmesh, math, sys, os, json, random

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
WORK, TEX = argv[0], argv[1]
WHICH = [int(a) for a in argv[2:]] or [1, 2, 3]

SY, RISE, TREAD, ROWS, BASE, BAY, AISLE = 11.0, 0.42, 0.85, 22, 1.7, 17.0, 1.6

def flat(name, rgb, rough=0.8, metal=0.0):
    m = bpy.data.materials.get(name)
    if m: return m
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (rgb[0], rgb[1], rgb[2], 1)
    b.inputs["Roughness"].default_value = rough; b.inputs["Metallic"].default_value = metal
    return m

def image(name, file):
    m = bpy.data.materials.get(name)
    if m: return m
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree
    tex = nt.nodes.new("ShaderNodeTexImage"); tex.image = bpy.data.images.load(os.path.join(TEX, file))
    nt.links.new(tex.outputs["Color"], nt.nodes["Principled BSDF"].inputs["Base Color"])
    nt.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.8
    return m

class Mesh:
    """Boxes and quads gathered into one mesh, a material each."""
    def __init__(self, name):
        self.name, self.bm, self.mats = name, bmesh.new(), []
        self.uv = self.bm.loops.layers.uv.new("UVMap")
    def slot(self, material):
        if material not in self.mats: self.mats.append(material)
        return self.mats.index(material)
    def quad(self, pts, material, uvs=None):
        f = self.bm.faces.new([self.bm.verts.new(p) for p in pts])
        f.material_index = self.slot(material)
        for loop, t in zip(f.loops, uvs or [(0, 0), (1, 0), (1, 1), (0, 1)]): loop[self.uv].uv = t
    def box(self, lo, hi, material, top=None, front_only=False):
        x0, y0, z0 = lo; x1, y1, z1 = hi
        self.quad([(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)], material)                  # towards the camera
        self.quad([(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)], top or material)           # top
        if front_only: return                                                                          # (a crowd is only ever seen from the front)
        self.quad([(x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1)], material)
        self.quad([(x0, y1, z0), (x0, y0, z0), (x0, y0, z1), (x0, y1, z1)], material)
        self.quad([(x1, y1, z0), (x0, y1, z0), (x0, y1, z1), (x1, y1, z1)], material)
    def finish(self):
        me = bpy.data.meshes.new(self.name)
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        self.bm.to_mesh(me); self.bm.free()
        for m in self.mats: me.materials.append(m)
        o = bpy.data.objects.new(self.name, me); bpy.context.scene.collection.objects.link(o)
        return o

def export(obj, stem):
    for x in bpy.context.scene.objects: x.select_set(False)
    obj.select_set(True); bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(filepath=os.path.join(WORK, "tracks", stem + ".glb"), use_selection=True, export_format='GLB',
                              export_apply=True, export_yup=True, export_materials='EXPORT')

def build(number):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    t = json.load(open(os.path.join(WORK, "tracks", "track%d.json" % number)))
    pts, length, half = t["points"], t["length"], t["depth"] / 2.0
    def h(x):
        f = (x - pts[0][0]) / (pts[1][0] - pts[0][0]); i = max(0, min(len(pts) - 2, int(f)))
        return pts[i][1] + (pts[i + 1][1] - pts[i][1]) * (f - i)
    x0, x1 = pts[0][0], pts[-1][0]
    rnd = random.Random(40 + number)

    concrete = flat("Concrete", (0.36, 0.37, 0.40))
    step_m = flat("Steps", (0.25, 0.26, 0.29))
    dark = flat("Dark", (0.08, 0.09, 0.11))
    steel = flat("Steel", (0.55, 0.57, 0.62), 0.4, 0.8)
    lamp = flat("Lamp", (1.0, 0.98, 0.90), 0.2)
    floor = image("Floor", "dirt_diff.jpg")
    boards = [image("Board%d" % i, "board_%d.png" % i) for i in range(5)]
    blocks = [flat("TuffRed", (0.80, 0.10, 0.08)), flat("TuffWhite", (0.93, 0.93, 0.90)), flat("TuffBlue", (0.08, 0.20, 0.70)), flat("TuffYellow", (0.95, 0.78, 0.10))]

    s = Mesh("Stadium")
    # the floor behind the dirt
    s.quad([(x0, half, -0.02), (x1, half, -0.02), (x1, 70.0, -0.02), (x0, 70.0, -0.02)], floor,
           [(x0 / 6, 0), (x1 / 6, 0), (x1 / 6, 11), (x0 / 6, 11)])
    # tuff blocks along the back of the dirt, on it
    x = 2.0
    while x < length - 2:
        z = h(x) - 0.05
        s.box((x - 0.55, half - 0.55, z), (x + 0.55, half - 0.05, z + 0.5), blocks[int(x / 2.4) % 4])
        x += 2.4
    # the barrier, with a board to each stretch
    by = 9.0
    x = x0
    k = 0
    while x < x1:
        s.box((x, by, 0.0), (x + 6.0, by + 0.25, 1.25), concrete)
        s.quad([(x + 0.15, by - 0.01, 0.12), (x + 5.85, by - 0.01, 0.12), (x + 5.85, by - 0.01, 1.15), (x + 0.15, by - 0.01, 1.15)], boards[k % 5])
        x += 6.0; k += 1
    # the stands: tiers stepping up and back, cut by stairways
    sy, rise, tread, rows, base = SY, RISE, TREAD, ROWS, BASE
    bay, aisle = BAY, AISLE
    s.box((x0, sy - 0.3, 0.0), (x1, sy, base + 0.9), concrete)                     # the front wall of the stand
    for r in range(rows):
        s.box((x0, sy + r * tread, 0.0), (x1, sy + (r + 1) * tread, base + r * rise), concrete, top=step_m)
    top_y, top_z = sy + rows * tread, base + rows * rise
    s.box((x0, top_y, 0.0), (x1, top_y + 0.4, top_z + 3.2), dark)                 # the back wall
    # the roof, over the upper rows, and its lamps
    s.box((x0, top_y - 9.0, top_z + 3.0), (x1, top_y + 0.4, top_z + 3.3), dark)
    x = x0 + 4
    while x < x1:
        s.box((x - 1.2, top_y - 9.1, top_z + 2.75), (x + 1.2, top_y - 8.7, top_z + 3.0), lamp)
        s.box((x - 0.08, top_y - 9.0, 0.0), (x + 0.08, top_y - 8.8, top_z + 3.0), steel) if int(x) % 24 < 8 else None
        x += 8.0
    # light towers behind, a bank of lamps on each
    x = x0 + 20
    while x < x1:
        s.box((x - 0.25, top_y + 1.0, 0.0), (x + 0.25, top_y + 1.5, top_z + 12.0), steel)
        s.box((x - 3.0, top_y + 0.6, top_z + 11.0), (x + 3.0, top_y + 1.1, top_z + 13.4), dark)
        for i in range(5):
            for j in range(2):
                s.box((x - 2.7 + i * 1.12, top_y + 0.5, top_z + 11.25 + j * 1.05), (x - 1.8 + i * 1.12, top_y + 0.62, top_z + 12.05 + j * 1.05), lamp)
        x += 62.0
    # the scoreboard, over the middle of the stand
    mid = length * 0.5
    s.box((mid - 9, top_y - 1.0, top_z + 4.2), (mid + 9, top_y - 0.4, top_z + 10.2), dark)
    s.quad([(mid - 8.5, top_y - 1.02, top_z + 4.7), (mid + 8.5, top_y - 1.02, top_z + 4.7), (mid + 8.5, top_y - 1.02, top_z + 9.7), (mid - 8.5, top_y - 1.02, top_z + 9.7)],
           image("Scoreboard", "scoreboard.png"))
    # the start and the finish: a board on two posts at the back of the dirt, facing the camera
    for at, pic in ((0.0, "start.png"), (float(length), "finish.png")):
        z = h(at)
        y = half + 0.35
        for px in (at - 4.0, at + 4.0):
            s.box((px - 0.12, y - 0.12, z - 0.5), (px + 0.12, y + 0.12, z + 5.0), steel)
        s.box((at - 4.1, y - 0.05, z + 3.9), (at + 4.1, y + 0.05, z + 5.0), dark)
        s.quad([(at - 4.0, y - 0.07, z + 3.95), (at + 4.0, y - 0.07, z + 3.95), (at + 4.0, y - 0.07, z + 4.95), (at - 4.0, y - 0.07, z + 4.95)], image("Banner_" + pic, pic))
    # flags on the dirt at the top of every jump
    for o in t["obstacles"]:
        if o[0] in ("table", "kicker"):
            fx = o[1] + (o[2] if o[0] == "kicker" else o[2] + o[3] * 0.5)
            z = h(fx)
            s.box((fx - 0.03, half - 0.9, z), (fx + 0.03, half - 0.84, z + 2.2), steel)
            s.quad([(fx + 0.03, half - 0.87, z + 1.6), (fx + 0.75, half - 0.87, z + 1.85), (fx + 0.03, half - 0.87, z + 2.15), (fx + 0.03, half - 0.87, z + 2.15)], blocks[1])
    stadium = s.finish()
    export(stadium, "Stadium%d" % number)
    print("STADIUM", number, len(stadium.data.polygons), "faces")
    json.dump({"x0": x0, "x1": x1, "bay": bay + aisle}, open(os.path.join(WORK, "tracks", "stadium%d.json" % number), "w"))


def crowd(variant):
    """One bay of the stand's crowd - someone on most seats, in whatever they came in.
    The scene sets bays side by side; three of them, so no two neighbours match."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    rnd = random.Random(700 + variant)
    c = Mesh("Crowd")
    shirts = [flat("Shirt%d" % i, col, 0.9) for i, col in enumerate([(0.80, 0.12, 0.10), (0.10, 0.25, 0.75), (0.95, 0.80, 0.15), (0.92, 0.92, 0.90),
                                                                       (0.15, 0.55, 0.25), (0.10, 0.10, 0.12), (0.90, 0.45, 0.10), (0.55, 0.20, 0.60)])]
    skin = [flat("Skin%d" % i, col, 0.9) for i, col in enumerate([(0.85, 0.65, 0.50), (0.60, 0.42, 0.30), (0.95, 0.78, 0.64)])]
    for r in range(ROWS):
        y = SY + r * TREAD + 0.30
        z = BASE + r * RISE
        x = 0.5
        while x < BAY - 0.3:
            if rnd.random() < 0.78:
                w = 0.40 + rnd.random() * 0.08
                up = 0.55 + rnd.random() * 0.12 + (0.25 if rnd.random() < 0.08 else 0.0)        # a few on their feet
                c.box((x - w / 2, y, z), (x + w / 2, y + 0.30, z + up), rnd.choice(shirts), front_only=True)
                c.box((x - 0.11, y + 0.04, z + up), (x + 0.11, y + 0.26, z + up + 0.24), rnd.choice(skin), front_only=True)
            x += 0.62
    o = c.finish()
    export(o, "CrowdBay%d" % variant)
    print("CROWD", variant, len(o.data.polygons), "faces")

for n in WHICH:
    build(n)
for v in range(3):
    crowd(v)
