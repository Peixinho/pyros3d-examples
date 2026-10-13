# Builds a low-poly dirt bike and rider, in parts a 2D physics rig can move:
#
#   Chassis      frame, engine, tank, seat, fenders, bars, upper fork tubes   (origin: the bike's own)
#   ForkLower    lower fork legs and axle clamps                              (origin: the front axle)
#   Swingarm     the two arms and the chain                                   (origin: its pivot)
#   WheelFront, WheelRear                                                     (origin: the axle)
#   Rider_Torso, Rider_Head, Rider_UpperArm, Rider_ForeArm, Rider_Thigh, Rider_Shin
#                each from its joint, lying along -Z, both sides in one object
#
# Side on: +X is forward, +Z up, Y across. Lengths are metres.
#
#   blender --background --python make_bike.py -- <out_dir> [render]
import bpy, bmesh, math, sys, os
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[0] if argv else "/tmp"
RENDER = len(argv) > 1 and argv[1] == "render"

bpy.ops.wm.read_factory_settings(use_empty=True)

# ----- what things are where (x, z) -----------------------------------------------
RA = (-0.72, 0.33)          # rear axle
FA = (0.76, 0.35)           # front axle
PIVOT = (-0.14, 0.44)       # swingarm pivot
HEAD_TOP = (0.40, 1.06)     # top of the steering head
HEAD_BOT = (0.47, 0.90)
GRIP = (0.36, 1.16)
PEG = (-0.16, 0.42)
R_FRONT, R_REAR = 0.345, 0.325

MATS = {}
def mat(name, rgb, metallic=0.0, rough=0.6):
    if name in MATS: return MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (rgb[0], rgb[1], rgb[2], 1)
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Roughness"].default_value = rough
    MATS[name] = m
    return m

def colour(var, default):
    v = os.environ.get(var)
    return tuple(float(x) for x in v.split(",")) if v else default
SUFFIX = os.environ.get("BIKE_SUFFIX", "")          # a rider's own set of parts: Chassis_1.glb ...
PAINT = mat("Paint", colour("BIKE_PAINT", (0.05, 0.25, 0.85)), 0.0, 0.35)       # the team colour: tinted per rider in the game
PAINT2 = mat("PaintTrim", (0.95, 0.95, 0.95), 0.0, 0.4)
BLACK = mat("Rubber", (0.03, 0.03, 0.035), 0.0, 0.85)
SEAT = mat("Seat", (0.06, 0.06, 0.07), 0.0, 0.7)
STEEL = mat("Steel", (0.62, 0.64, 0.68), 0.9, 0.35)
DARK = mat("Engine", (0.20, 0.21, 0.23), 0.7, 0.5)
GOLD = mat("Gold", (0.85, 0.62, 0.18), 0.9, 0.3)
PLATE = mat("Plate", (0.97, 0.97, 0.95), 0.0, 0.5)
JERSEY = mat("Jersey", colour("BIKE_JERSEY", (0.05, 0.25, 0.85)), 0.0, 0.7)       # also tinted per rider
PANTS = mat("Pants", (0.92, 0.92, 0.94), 0.0, 0.7)
BOOT = mat("Boot", (0.08, 0.08, 0.09), 0.0, 0.6)
VISOR = mat("Goggles", (0.95, 0.45, 0.08), 0.9, 0.12)

def new_obj(name, bm, material, smooth=False):
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons: p.use_smooth = smooth
    me.materials.append(material)
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    return o

def profile(name, pts, width, material, y=0.0, bevel=0.012):
    """A side-on outline (x, z), counter-clockwise, given a thickness across."""
    bm = bmesh.new()
    vs = [bm.verts.new((x, y - width / 2, z)) for x, z in pts]
    f = bm.faces.new(vs)
    ext = bmesh.ops.extrude_face_region(bm, geom=[f])
    bmesh.ops.translate(bm, vec=(0, width, 0), verts=[e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=min(bevel, width * 0.3), segments=2, affect='EDGES', profile=0.6)
    return new_obj(name, bm, material, smooth=False)

def tube(name, a, b, radius, material, radius2=None, verts=10):
    """A round bar from a to b (3D points)."""
    a, b = Vector(a), Vector(b)
    d = b - a
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=verts, radius1=radius, radius2=radius2 if radius2 is not None else radius, depth=d.length)
    rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=Matrix.Translation((a + b) / 2) @ rot, verts=bm.verts)
    return new_obj(name, bm, material, smooth=True)

def xz(p, y=0.0): return (p[0], y, p[1])

def cyl_y(name, centre, radius, width, material, verts=20, y=0.0):
    return tube(name, (centre[0], y - width / 2, centre[1]), (centre[0], y + width / 2, centre[1]), radius, material, verts=verts)

def box(name, centre, size, material, angle=0.0, y=0.0, bevel=0.008):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=(size[0], size[1], size[2]), verts=bm.verts)
    if bevel > 0: bmesh.ops.bevel(bm, geom=list(bm.edges), offset=min(bevel, min(size) * 0.3), segments=2, affect='EDGES')
    bmesh.ops.transform(bm, matrix=Matrix.Translation((centre[0], y, centre[1])) @ Matrix.Rotation(-angle, 4, 'Y'), verts=bm.verts)
    return new_obj(name, bm, material)

def ball(name, centre, scale, material, y=0.0, segs=14):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=segs // 2 + 2, radius=1.0)
    bmesh.ops.scale(bm, vec=scale, verts=bm.verts)
    bmesh.ops.translate(bm, vec=(centre[0], y, centre[1]), verts=bm.verts)
    return new_obj(name, bm, material, smooth=True)

def join(name, parts, origin):
    """The parts as one object whose own origin is `origin` (x, z)."""
    for o in bpy.context.scene.objects: o.select_set(False)
    for p in parts: p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    if len(parts) > 1: bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.name = name
    o.data.name = name
    shift = Vector((origin[0], 0, origin[1]))
    o.data.transform(Matrix.Translation(-shift))
    o.location = shift
    return o

# ----- wheels -------------------------------------------------------------------------
def wheel(name, radius, tyre, rim_r):
    parts = []
    bm = bmesh.new()
    # the tyre: a ring, squarer than a torus
    segs, ring = 40, [(-tyre, 0.0), (-tyre * 0.9, tyre * 0.75), (-tyre * 0.45, tyre), (tyre * 0.45, tyre), (tyre * 0.9, tyre * 0.75), (tyre, 0.0),
                      (tyre * 0.6, -tyre * 0.8), (-tyre * 0.6, -tyre * 0.8)]
    R = radius - tyre * 1.05
    rows = []
    for i in range(segs):
        a = 2 * math.pi * i / segs
        rows.append([bm.verts.new(((R + h) * math.cos(a), w, (R + h) * math.sin(a))) for w, h in ring])
    for i in range(segs):
        a, b = rows[i], rows[(i + 1) % segs]
        for k in range(len(ring)):
            bm.faces.new((a[k], a[(k + 1) % len(ring)], b[(k + 1) % len(ring)], b[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    parts.append(new_obj(name + "_tyre", bm, BLACK, smooth=True))
    # knobs: what makes it a dirt tyre
    bm = bmesh.new()
    n = 30
    for i in range(n):
        for row, w in enumerate((-tyre * 0.62, 0.0, tyre * 0.62)):
            a = 2 * math.pi * (i + (0.5 if row == 1 else 0.0)) / n
            g = bmesh.ops.create_cube(bm, size=1.0)
            bmesh.ops.scale(bm, vec=(0.032, tyre * 0.42, 0.036), verts=g["verts"])
            m = Matrix.Rotation(-a, 4, 'Y') @ Matrix.Translation((0, w, radius - 0.016 - (0.006 if row != 1 else 0.0)))
            bmesh.ops.transform(bm, matrix=m, verts=g["verts"])
    parts.append(new_obj(name + "_knobs", bm, BLACK))
    # rim
    bm = bmesh.new()
    rows = []
    rr = [(-0.030, -0.034), (-0.036, 0.006), (0.036, 0.006), (0.030, -0.034)]
    for i in range(segs):
        a = 2 * math.pi * i / segs
        rows.append([bm.verts.new(((rim_r + h) * math.cos(a), w, (rim_r + h) * math.sin(a))) for w, h in rr])
    for i in range(segs):
        a, b = rows[i], rows[(i + 1) % segs]
        for k in range(len(rr)):
            bm.faces.new((a[k], a[(k + 1) % len(rr)], b[(k + 1) % len(rr)], b[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    parts.append(new_obj(name + "_rim", bm, PAINT2 if False else GOLD, smooth=True))
    # spokes, laced a little off the radius so the turning shows
    for i in range(16):
        a = 2 * math.pi * i / 16
        side = 0.03 if i % 2 == 0 else -0.03
        a2 = a + (0.5 if i % 2 == 0 else -0.5)
        parts.append(tube(name + "_spoke", (0.04 * math.cos(a2), side, 0.04 * math.sin(a2)), (rim_r * math.cos(a), 0, rim_r * math.sin(a)), 0.004, STEEL, verts=5))
    parts.append(tube(name + "_hub", (0, -0.05, 0), (0, 0.05, 0), 0.045, STEEL, verts=14))
    parts.append(tube(name + "_disc", (0, 0.052, 0), (0, 0.058, 0), 0.115, STEEL, verts=24))
    return join(name, parts, (0, 0))

wf = wheel("WheelFront", R_FRONT, 0.045, 0.262)
wf.location = (FA[0], 0, FA[1])
wr = wheel("WheelRear", R_REAR, 0.06, 0.225)
wr.location = (RA[0], 0, RA[1])
# (the rear sprocket)
spr = tube("spr", (RA[0], -0.062, RA[1]), (RA[0], -0.056, RA[1]), 0.10, STEEL, verts=24)
for o in bpy.context.scene.objects: o.select_set(False)
spr.select_set(True); wr.select_set(True); bpy.context.view_layer.objects.active = wr; bpy.ops.object.join()

# ----- chassis -------------------------------------------------------------------------
c = []
# frame: steering head, twin spars down to the pivot, cradle under the engine, subframe
head_axis = Vector((HEAD_BOT[0] - HEAD_TOP[0], 0, HEAD_BOT[1] - HEAD_TOP[1])).normalized()
c.append(tube("head", xz(HEAD_TOP), xz(HEAD_BOT), 0.032, PAINT, verts=12))
for y in (-0.07, 0.07):
    c.append(tube("spar", (0.43, y * 0.4, 0.99), (-0.10, y, 0.74), 0.024, PAINT))
    c.append(tube("spar2", (-0.10, y, 0.74), (PIVOT[0], y, PIVOT[1] - 0.04), 0.024, PAINT))
    c.append(tube("down", (0.45, y * 0.4, 0.92), (0.22, y, 0.36), 0.02, PAINT))
    c.append(tube("cradle", (0.22, y, 0.36), (PIVOT[0], y, PIVOT[1] - 0.06), 0.02, PAINT))
    c.append(tube("sub1", (-0.10, y, 0.76), (-0.72, y * 0.8, 0.90), 0.014, STEEL))
    c.append(tube("sub2", (PIVOT[0] - 0.02, y, 0.52), (-0.60, y * 0.8, 0.86), 0.014, STEEL))
    c.append(tube("peg", (PEG[0], y, PEG[1]), (PEG[0], y * 3.0, PEG[1]), 0.012, STEEL, verts=6))
# engine
c.append(box("crank", (0.06, 0.50), (0.34, 0.20, 0.22), DARK, bevel=0.03))
c.append(cyl_y("clutch", (0.02, 0.50), 0.105, 0.24, STEEL, verts=18))
c.append(box("cyl", (0.14, 0.66), (0.15, 0.16, 0.20), DARK, angle=-0.25, bevel=0.015))
c.append(box("headc", (0.17, 0.77), (0.17, 0.17, 0.08), STEEL, angle=-0.25, bevel=0.015))
c.append(box("skid", (0.10, 0.365), (0.40, 0.20, 0.03), STEEL, bevel=0.01))
# exhaust: out of the front of the cylinder, round the side and back to a silencer
ex = [(0.24, 0.0, 0.74), (0.33, 0.06, 0.66), (0.30, 0.13, 0.55), (0.10, 0.15, 0.56), (-0.14, 0.15, 0.66), (-0.34, 0.14, 0.76)]
for i in range(len(ex) - 1): c.append(tube("pipe", ex[i], ex[i + 1], 0.026, STEEL, verts=8))
c.append(tube("silencer", (-0.34, 0.14, 0.76), (-0.70, 0.15, 0.86), 0.046, STEEL, verts=12))
c.append(tube("tip", (-0.70, 0.15, 0.86), (-0.74, 0.15, 0.87), 0.03, DARK, verts=10))
# bodywork
c.append(profile("tank", [(0.42, 1.00), (0.34, 1.07), (0.16, 1.05), (-0.06, 0.96), (-0.10, 0.90), (0.05, 0.80), (0.30, 0.82), (0.40, 0.90)], 0.22, PAINT, bevel=0.03))
for y in (-0.135, 0.135):     # radiator shrouds
    c.append(profile("shroud", [(0.44, 0.98), (0.30, 1.03), (0.10, 0.92), (0.20, 0.70), (0.34, 0.66), (0.50, 0.84)], 0.03, PAINT, y=y, bevel=0.01))
    c.append(profile("shroudstripe", [(0.42, 0.90), (0.24, 0.92), (0.28, 0.78), (0.40, 0.76)], 0.034, PAINT2, y=y, bevel=0.004))
    c.append(profile("sideplate", [(-0.20, 0.93), (-0.50, 0.95), (-0.55, 0.87), (-0.40, 0.74), (-0.22, 0.76)], 0.02, PLATE, y=y * 0.95, bevel=0.008))
c.append(profile("seat", [(0.12, 1.06), (-0.10, 0.99), (-0.40, 0.985), (-0.62, 1.02), (-0.62, 0.95), (-0.40, 0.92), (-0.10, 0.92), (0.06, 0.98)], 0.19, SEAT, bevel=0.03))
c.append(profile("rearfender", [(-0.56, 0.96), (-0.80, 1.01), (-1.06, 1.10), (-1.08, 1.085), (-0.82, 0.965), (-0.60, 0.90), (-0.50, 0.90)], 0.17, PAINT, bevel=0.012))
c.append(profile("frontfender", [(0.40, 0.84), (0.62, 0.86), (0.92, 0.80), (1.06, 0.72), (1.07, 0.735), (0.93, 0.835), (0.62, 0.90), (0.40, 0.89)], 0.16, PAINT, bevel=0.012))
c.append(profile("airbox", [(-0.10, 0.90), (-0.36, 0.90), (-0.30, 0.64), (-0.12, 0.58)], 0.18, SEAT, bevel=0.02))
# rear shock
c.append(tube("shock", (-0.16, 0, 0.84), (-0.24, 0, 0.50), 0.022, STEEL, verts=8))
c.append(tube("spring", (-0.17, 0, 0.80), (-0.22, 0, 0.58), 0.042, PAINT2, verts=10))
# front end that stays with the frame: clamps, upper tubes, bars, the number plate
ax = Vector((FA[0] - HEAD_TOP[0], 0, FA[1] - HEAD_TOP[1])).normalized()
top = Vector(xz(HEAD_TOP)) + Vector((0.035, 0, 0.0))
c.append(box("clampT", (top.x - 0.005, top.z + 0.01), (0.10, 0.26, 0.03), STEEL, angle=-0.42, bevel=0.008))
low = top + ax * 0.20
c.append(box("clampB", (low.x, low.z), (0.10, 0.26, 0.03), STEEL, angle=-0.42, bevel=0.008))
for y in (-0.105, 0.105):
    a = top + Vector((0, y, 0)) - ax * 0.03
    c.append(tube("forkU", a, a + ax * 0.50, 0.027, GOLD, verts=12))
c.append(tube("bar", (GRIP[0] + 0.05, -0.20, GRIP[1] - 0.03), (GRIP[0] + 0.05, 0.20, GRIP[1] - 0.03), 0.013, STEEL, verts=8))
for s in (-1, 1):
    c.append(tube("barR", (GRIP[0] + 0.05, s * 0.20, GRIP[1] - 0.03), (GRIP[0], s * 0.31, GRIP[1]), 0.013, STEEL, verts=8))
    c.append(tube("grip", (GRIP[0], s * 0.31, GRIP[1]), (GRIP[0] - 0.01, s * 0.41, GRIP[1]), 0.018, BLACK, verts=8))
    c.append(tube("riser", (top.x, s * 0.05, top.z + 0.02), (GRIP[0] + 0.05, s * 0.05, GRIP[1] - 0.03), 0.014, STEEL, verts=6))
c.append(profile("numberplate", [(0.50, 1.14), (0.54, 1.15), (0.60, 0.94), (0.56, 0.92)], 0.24, PLATE, bevel=0.01))
chassis = join("Chassis", c, (0, 0))

# ----- fork lowers, swingarm ---------------------------------------------------------------
f = []
for y in (-0.105, 0.105):
    a = Vector((FA[0], y, FA[1]))
    f.append(tube("forkL", a - ax * 0.52, a + ax * 0.02, 0.021, STEEL, verts=12))
    f.append(box("axleclamp", (FA[0], FA[1]), (0.07, 0.03, 0.09), DARK, y=y, bevel=0.01))
    f.append(profile("guard", [(FA[0] - 0.02, FA[1] + 0.04), (FA[0] + 0.035, FA[1] + 0.04), (FA[0] - 0.10, FA[1] + 0.36), (FA[0] - 0.15, FA[1] + 0.36)], 0.012, PAINT2, y=y * 1.25, bevel=0.004))
f.append(tube("axleF", (FA[0], -0.12, FA[1]), (FA[0], 0.12, FA[1]), 0.012, STEEL, verts=8))
fork = join("ForkLower", f, FA)

s = []
for y in (-0.085, 0.085):
    s.append(profile("arm", [(PIVOT[0] + 0.03, PIVOT[1] + 0.035), (PIVOT[0] - 0.03, PIVOT[1] + 0.04), (RA[0] - 0.04, RA[1] + 0.03), (RA[0] - 0.04, RA[1] - 0.03), (PIVOT[0] - 0.02, PIVOT[1] - 0.05), (PIVOT[0] + 0.03, PIVOT[1] - 0.035)], 0.03, STEEL, y=y, bevel=0.008))
s.append(profile("chain", [(PIVOT[0] + 0.10, PIVOT[1] + 0.05), (RA[0], RA[1] + 0.10), (RA[0], RA[1] + 0.085), (PIVOT[0] + 0.10, PIVOT[1] + 0.035)], 0.012, DARK, y=-0.062, bevel=0))
s.append(profile("chain2", [(PIVOT[0] + 0.10, PIVOT[1] - 0.045), (RA[0], RA[1] - 0.085), (RA[0], RA[1] - 0.10), (PIVOT[0] + 0.10, PIVOT[1] - 0.06)], 0.012, DARK, y=-0.062, bevel=0))
s.append(tube("axleR", (RA[0], -0.11, RA[1]), (RA[0], 0.11, RA[1]), 0.012, STEEL, verts=8))
swing = join("Swingarm", s, PIVOT)

# ----- the rider ------------------------------------------------------------------------------
# Each piece hangs from its joint along -Z; the game (and the pose below) turns it about Y.
L_TORSO, L_UPPER, L_FORE, L_THIGH, L_SHIN = 0.50, 0.29, 0.27, 0.42, 0.44
SHOULDER_Y, HIP_Y = 0.19, 0.105

def limb(name, length, r1, r2, material, y, extra=None, y_end=None):
    """Both sides of one bone, hanging from its joint. y is how far out the
    joint is, y_end how far out the far end is (arms splay to the bars)."""
    parts = []
    y_end = y if y_end is None else y_end
    for s_ in (-1, 1):
        parts.append(tube(name, (0, s_ * y, 0), (0, s_ * y_end, -length), r1, material, radius2=r2, verts=12))
        parts.append(ball(name + "j", (0, 0), (r1 * 1.03, r1 * 1.03, r1 * 1.03), material, y=s_ * y, segs=14))
        if extra: parts += extra(s_ * y_end)
    return join(name, parts, (0, 0))

# torso: from the hips up (+Z), since it is the one piece that stands on its joint
def loft(name, sections, material, segs=18):
    """Rounded sections (z, centre x, half depth, half width) joined into a body."""
    bm = bmesh.new()
    rings = []
    for z, cx, rx, ry in sections:
        ring = []
        for k in range(segs):
            a = 2 * math.pi * k / segs
            # (squarer than an ellipse: a chest, not a barrel)
            ca, sa = math.cos(a), math.sin(a)
            ex = abs(ca) ** 0.8 * (1 if ca >= 0 else -1)
            ey = abs(sa) ** 0.8 * (1 if sa >= 0 else -1)
            ring.append(bm.verts.new((cx + rx * ex, ry * ey, z)))
        rings.append(ring)
    for r in range(len(rings) - 1):
        for k in range(segs):
            bm.faces.new((rings[r][k], rings[r][(k + 1) % segs], rings[r + 1][(k + 1) % segs], rings[r + 1][k]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return new_obj(name, bm, material, smooth=True)

t = [loft("chest", [(0.03, -0.01, 0.105, 0.150), (0.14, -0.01, 0.105, 0.150), (0.30, 0.0, 0.125, 0.175), (0.42, -0.005, 0.120, 0.190),
                    (0.49, -0.01, 0.095, 0.175), (0.535, -0.01, 0.06, 0.09)], JERSEY),
     loft("hips", [(-0.11, -0.01, 0.10, 0.135), (-0.04, -0.01, 0.115, 0.150), (0.05, -0.01, 0.108, 0.152)], PANTS),
     loft("belt", [(0.025, -0.01, 0.110, 0.154), (0.055, -0.01, 0.110, 0.154)], BOOT),
     loft("chestplate", [(0.20, 0.035, 0.105, 0.130), (0.30, 0.04, 0.115, 0.150), (0.41, 0.03, 0.105, 0.150)], PAINT2),
     loft("backplate", [(0.16, -0.05, 0.095, 0.115), (0.30, -0.045, 0.110, 0.135), (0.43, -0.05, 0.095, 0.130)], PAINT2)]
torso = join("Rider_Torso", t, (0, 0))

def helmet():
    """A motocross helmet: a shell drawn out into a chin bar, an eye port with
    goggles and their strap, and a long peak. Centre a little above the neck."""
    C = Vector((0.025, 0.0, 0.150))
    A, B, Cz = 0.150, 0.122, 0.140
    def clamp(v): return max(0.0, min(1.0, v))
    def shell_point(d, grow=1.0):
        x, y, z = d
        p = Vector((x * A, y * B, z * Cz)) * grow
        # the chin bar: everything below the eyes and ahead of the ears is
        # carried forward to a broad, nearly flat front - as wide as the
        # cheeks, not a snout
        low = clamp((-z + 0.02) / 0.22) * clamp((z + 0.95) / 0.25)
        fwd = clamp((x + 0.10) / 0.45)
        f = low * fwd
        p.x += 0.075 * f
        p.x = min(p.x, 0.212)                       # the flat of its front
        p.y *= 1.0 + 0.06 * f                       # cheeks a little full
        p.z -= 0.018 * f
        # the back comes down straighter, and tucks in at the neck
        if x < 0: p.x *= 1.0 + 0.05 * clamp(-z)
        if z < -0.72: p *= 1.0 - 0.18 * clamp((-z - 0.72) / 0.28)
        # the eye port, set well into the shell
        port = clamp(1.0 - abs((z - 0.16) / 0.20)) * clamp((x - 0.30) / 0.25) * clamp(1.15 - abs(y))
        p.x -= 0.034 * clamp(port * 3.0)
        return p + C
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=28, v_segments=18, radius=1.0)
    for v in bm.verts: v.co = shell_point(v.co.normalized())
    parts = [new_obj("shell", bm, PAINT, smooth=True)]
    def patch(name, az0, az1, el0, el1, grow, material, nu=14, nv=4, thick=0.0):
        bm = bmesh.new()
        grid = []
        for iv in range(nv + 1):
            el = el0 + (el1 - el0) * iv / nv
            row = []
            for iu in range(nu + 1):
                az = az0 + (az1 - az0) * iu / nu
                d = Vector((math.cos(el) * math.cos(az), math.cos(el) * math.sin(az), math.sin(el)))
                q = Vector((d.x * A, d.y * B, d.z * Cz)) * grow + C
                row.append(bm.verts.new(q))
            grid.append(row)
        for iv in range(nv):
            for iu in range(nu):
                bm.faces.new((grid[iv][iu], grid[iv][iu + 1], grid[iv + 1][iu + 1], grid[iv + 1][iu]))
        if thick > 0:
            ext = bmesh.ops.extrude_face_region(bm, geom=list(bm.faces))
            for e in ext["geom"]:
                if isinstance(e, bmesh.types.BMVert): e.co += (e.co - C).normalized() * thick
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        return new_obj(name, bm, material, smooth=True)
    r = math.radians
    parts.append(patch("goggleframe", r(-66), r(66), r(-3), r(31), 0.93, PAINT2, thick=0.010))
    parts.append(patch("lens", r(-54), r(54), r(1), r(27), 0.955, VISOR, nu=18, nv=5, thick=0.008))
    parts.append(patch("strap", r(64), r(296), r(5), r(23), 1.012, BLACK, nu=30, nv=2, thick=0.005))
    # graphics: a white band over the crown, front to back, and a flash each side
    bm2 = bmesh.new(); rows = []
    for k in range(25):
        t = math.radians(-20 + 220 * k / 24.0)        # from the brow, over the top, down the back
        row = []
        for w in (-1, 0, 1):
            d = Vector((math.cos(t), w * 0.20, math.sin(t))).normalized()
            row.append(bm2.verts.new(shell_point(d) + (shell_point(d) - C).normalized() * 0.003))
        rows.append(row)
    for k in range(24):
        for w in range(2): bm2.faces.new((rows[k][w], rows[k][w + 1], rows[k + 1][w + 1], rows[k + 1][w]))
    bmesh.ops.recalc_face_normals(bm2, faces=bm2.faces)
    parts.append(new_obj("crownband", bm2, PAINT2, smooth=True))
    # the peak: it starts at the temples, wraps the brow, and sweeps forward and
    # up to a rounded front, arched across, with a rib down its middle
    def peak(name, v0, v1, lift, material, nu=8, nv=16):
        bm = bmesh.new()
        grid = []
        for iu in range(nu + 1):
            u = iu / nu
            row = []
            for iv in range(nv + 1):
                v = v0 + (v1 - v0) * iv / nv
                az, el = v * math.radians(52), math.radians(44)
                base = Vector((math.cos(el) * math.cos(az) * A, math.cos(el) * math.sin(az) * B, math.sin(el) * Cz)) * 0.97 + C
                tip = Vector((C.x + 0.232 - 0.030 * v * v, 0.086 * v, C.z + Cz * 0.70 + 0.018 - 0.010 * v * v))
                q = base.lerp(tip, u)
                q.z += 0.006 * math.sin(math.pi * u) + lift
                row.append(bm.verts.new(q))
            grid.append(row)
        for iu in range(nu):
            for iv in range(nv):
                bm.faces.new((grid[iu][iv], grid[iu][iv + 1], grid[iu + 1][iv + 1], grid[iu + 1][iv]))
        ext = bmesh.ops.extrude_face_region(bm, geom=list(bm.faces))
        bmesh.ops.translate(bm, vec=(0, 0, -0.013), verts=[e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        return new_obj(name, bm, material, smooth=False)
    parts.append(peak("peak", -1.0, 1.0, 0.0, PAINT))
    parts.append(peak("peakrib", -0.16, 0.16, 0.006, PAINT2, nv=4))
    # the chin bar's vent, and the neck
    for vy in (-0.035, 0.0, 0.035):       # three slots across the front of the chin bar
        parts.append(box("vent", (C.x + 0.212, C.z - 0.070), (0.012, 0.022, 0.050), BLACK, y=vy, bevel=0.003))
    parts.append(tube("neck", (0, 0, -0.03), (0.01, 0, 0.05), 0.062, BLACK, verts=14))
    return parts

h = helmet()
head = join("Rider_Head", h, (0, 0))

ELBOW_Y, HAND_Y = 0.27, 0.355
upper = limb("Rider_UpperArm", L_UPPER, 0.054, 0.044, JERSEY, SHOULDER_Y, y_end=ELBOW_Y)
fore = limb("Rider_ForeArm", L_FORE, 0.044, 0.036, JERSEY, ELBOW_Y, y_end=HAND_Y,
            extra=lambda y: [ball("glove", (0.0, -L_FORE - 0.035), (0.045, 0.042, 0.058), BOOT, y=y, segs=12),
                             tube("cuff", (0, y, -L_FORE + 0.05), (0, y, -L_FORE + 0.0), 0.040, PAINT2, verts=12)])
thigh = limb("Rider_Thigh", L_THIGH, 0.078, 0.060, PANTS, HIP_Y)
shin = limb("Rider_Shin", L_SHIN, 0.058, 0.050, PANTS, HIP_Y,
            extra=lambda y: [profile("boot", [(-0.06, -L_SHIN + 0.18), (0.055, -L_SHIN + 0.18), (0.06, -L_SHIN + 0.02), (0.19, -L_SHIN - 0.03), (0.19, -L_SHIN - 0.085), (-0.07, -L_SHIN - 0.085)], 0.105, BOOT, y=y, bevel=0.02),
                             profile("kneeguard", [(0.03, 0.05), (0.075, 0.03), (0.07, -0.16), (0.045, -0.16)], 0.09, PAINT2, y=y, bevel=0.01)])

# ----- a riding pose, as the game will make it ------------------------------------------------
def two_bone(root, target, l1, l2, bend):
    """Angles (from straight down, about Y, positive forward) of two bones from root reaching target."""
    dx, dz = target[0] - root[0], target[1] - root[1]
    d = max(1e-4, min(math.hypot(dx, dz), l1 + l2 - 1e-4))
    base = math.atan2(dx, -dz)                       # the direction root -> target, 0 = straight down
    a = math.acos((l1 * l1 + d * d - l2 * l2) / (2 * l1 * d))
    b = math.acos((l1 * l1 + l2 * l2 - d * d) / (2 * l1 * l2))
    first = base + bend * a
    second = first - bend * (math.pi - b)
    return first, second

def place(obj, joint, angle):
    obj.location = (joint[0], 0, joint[1])
    obj.rotation_euler = (0, -angle, 0)

def pose(lean=0.60, hip=(-0.40, 1.07)):
    torso.location = (hip[0], 0, hip[1]); torso.rotation_euler = (0, lean, 0)
    sh = (hip[0] + math.sin(lean) * L_TORSO * 0.94, hip[1] + math.cos(lean) * L_TORSO * 0.94)
    nk = (hip[0] + math.sin(lean) * (L_TORSO + 0.02), hip[1] + math.cos(lean) * (L_TORSO + 0.02))
    head.location = (nk[0], 0, nk[1]); head.rotation_euler = (0, lean * 0.35, 0)
    a1, a2 = two_bone(sh, (GRIP[0] - 0.02, GRIP[1] + 0.04), L_UPPER, L_FORE + 0.03, -1)
    place(upper, sh, a1)
    el = (sh[0] + math.sin(a1) * L_UPPER, sh[1] - math.cos(a1) * L_UPPER)
    place(fore, el, a2)
    ankle = (PEG[0] - 0.03, PEG[1] + 0.11)
    t1, t2 = two_bone(hip, ankle, L_THIGH, L_SHIN, 1)
    place(thigh, hip, t1)
    kn = (hip[0] + math.sin(t1) * L_THIGH, hip[1] - math.cos(t1) * L_THIGH)
    place(shin, kn, t2)
pose()

# What the game needs to know, beside the models.
import json
json.dump({"rearAxle": RA, "frontAxle": FA, "pivot": PIVOT, "headTop": HEAD_TOP, "grip": GRIP, "peg": PEG,
           "rFront": R_FRONT, "rRear": R_REAR, "forkAxis": [ax.x, ax.z],
           "torso": L_TORSO, "upperArm": L_UPPER, "foreArm": L_FORE, "thigh": L_THIGH, "shin": L_SHIN},
          open(os.path.join(OUT, "bike.json"), "w"), indent=1)

if RENDER:
    sc = bpy.context.scene
    bpy.ops.mesh.primitive_plane_add(size=30, location=(0, 0, 0))
    g = bpy.context.active_object; g.data.materials.append(mat("Dirt", (0.42, 0.30, 0.18), 0, 0.95))
    sun = bpy.data.lights.new("Sun", 'SUN'); sun.energy = 4.0; sun.angle = 0.2
    so = bpy.data.objects.new("Sun", sun); sc.collection.objects.link(so); so.rotation_euler = (math.radians(50), math.radians(10), math.radians(-35))
    fill = bpy.data.lights.new("Fill", 'SUN'); fill.energy = 1.2
    fo = bpy.data.objects.new("Fill", fill); sc.collection.objects.link(fo); fo.rotation_euler = (math.radians(60), 0, math.radians(140))
    w = bpy.data.worlds.new("W"); sc.world = w; w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.70, 0.95, 1); w.node_tree.nodes["Background"].inputs[1].default_value = 0.9
    cam = bpy.data.cameras.new("Cam"); co = bpy.data.objects.new("Cam", cam); sc.collection.objects.link(co); sc.camera = co
    sc.render.engine = 'BLENDER_EEVEE_NEXT'
    sc.render.resolution_x, sc.render.resolution_y = 1400, 900
    sc.view_settings.view_transform = 'Standard'
    def shoot(name, loc, lens=70):
        co.location = loc
        d = Vector((0.0, 0, 0.85)) - Vector(loc)
        co.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
        cam.lens = lens
        sc.render.filepath = os.path.join(OUT, name)
        bpy.ops.render.render(write_still=True)
    shoot("bike_side.png", (0.0, -6.6, 1.0))
    shoot("bike_34.png", (3.6, -5.2, 2.0))
    def close(name, loc):
        co.location = loc
        hp = Vector(head.location) + Vector((0.05, 0, 0.16))
        co.rotation_euler = (hp - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
        cam.lens = 90; sc.render.resolution_x, sc.render.resolution_y = 800, 700
        sc.render.filepath = os.path.join(OUT, name); bpy.ops.render.render(write_still=True)
    close("helmet_a.png", (1.6, -1.9, 1.9))
    close("helmet_b.png", (0.1, -2.6, 1.7))
    bpy.data.objects.remove(g)

# Each part as a file of its own, about its own origin, unposed.
os.makedirs(os.path.join(OUT, "parts"), exist_ok=True)
PARTS = [chassis, fork, swing, wf, wr, torso, head, upper, fore, thigh, shin]
rest = {}
for o in PARTS:
    rest[o.name] = [o.location.x, o.location.z]
    keep = (o.location.copy(), o.rotation_euler.copy())
    o.location = (0, 0, 0); o.rotation_euler = (0, 0, 0)
    for x in bpy.context.scene.objects: x.select_set(False)
    o.select_set(True); bpy.context.view_layer.objects.active = o
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "parts", o.name + SUFFIX + ".glb"), use_selection=True, export_format='GLB',
                              export_apply=True, export_yup=True, export_materials='EXPORT')
    o.location, o.rotation_euler = keep
json.dump(rest, open(os.path.join(OUT, "rest.json"), "w"), indent=1)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "bike.blend"))
print("BIKE OK")
