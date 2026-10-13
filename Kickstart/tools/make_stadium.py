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
    length, half = t["length"], t["depth"] / 2.0
    x0, x1 = t["x0"], t["x1"]
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
    # tuff blocks in a row on the floor behind the dirt (not on it: the dirt is the scene's to reshape)
    x = x0 + 2.0
    while x < x1 - 2:
        s.box((x - 0.55, half + 0.9, 0.0), (x + 0.55, half + 1.4, 0.5), blocks[int(x / 2.4) % 4])
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

def board(name, pic):
    """The start's and the finish's board, on two posts: a model of its own, so the scene can stand it where the line is."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    b = Mesh(name)
    steel = flat("Steel", (0.55, 0.57, 0.62), 0.4, 0.8)
    dark = flat("Dark", (0.08, 0.09, 0.11))
    for px in (-4.0, 4.0):
        b.box((px - 0.12, -0.12, -8.0), (px + 0.12, 0.12, 5.0), steel)
    b.box((-4.1, -0.05, 3.9), (4.1, 0.05, 5.0), dark)
    b.quad([(-4.0, -0.07, 3.95), (4.0, -0.07, 3.95), (4.0, -0.07, 4.95), (-4.0, -0.07, 4.95)], image("Banner_" + pic, pic))
    export(b.finish(), name)

for n in WHICH:
    build(n)
board("BoardStart", "start.png")
board("BoardFinish", "finish.png")
for v in range(3):
    crowd(v)
