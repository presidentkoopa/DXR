"""
DoomXR XRWhip -- gorgeous braided Indiana-Jones leather bullwhip, rigged IQM builder.
Single-file, self-contained, Blender 4.4 headless. Merges four domain specs
(anatomy / geometry / material / lighting) into one runnable pipeline.

Run:
  blender --background --python make_whip.py -- <out.iqm> <hero_render.png> <skin.png> [<out.blend>]

Produces, in order:
  1. a straight-REST 21-bone rigged IQM (whip_root + seg_00..seg_19 along local +Y),
  2. a cinematic coiled hero render PNG (coil is POSE-mode-only; exporter forces REST),
  3. a braided-leather skin PNG (pure stdlib: zlib+struct, no PIL/numpy).

HARD CONSTRAINTS honored:
  * Exported rig is a STRAIGHT +Y chain (physics-sim rest requirement). The dramatic
    coil exists only in POSE mode for the beauty shot -- the iqm-master exporter forces
    the armature to REST during export, so the coil never ships.
  * Mesh is skinned: vertex groups named EXACTLY whip_root / seg_00..seg_19 + Armature mod.
  * Round >=16-gon tube, belly taper, braid baked in texture, fat handle + pommel knob +
    collar, thin fall + frayed popper tuft.
"""

import bpy, bmesh, math, os, sys, struct, zlib
from mathutils import Vector, Euler

# ============================================================================
# 0. ARGV CONTRACT:  <out.iqm> <hero_render.png> <skin.png> [<out.blend>]
# ============================================================================
def _parse_argv():
    argv = sys.argv
    args = argv[argv.index("--") + 1:] if "--" in argv else []
    cwd = os.getcwd()
    out_iqm  = os.path.abspath(args[0]) if len(args) >= 1 else os.path.join(cwd, "whip_rigged.iqm")
    out_hero = os.path.abspath(args[1]) if len(args) >= 2 else os.path.join(cwd, "whip_hero.png")
    out_skin = os.path.abspath(args[2]) if len(args) >= 3 else os.path.join(cwd, "xrwhip_skin.png")
    out_blend = os.path.abspath(args[3]) if len(args) >= 4 else None
    for p in (out_iqm, out_hero, out_skin, out_blend):
        if p:
            os.makedirs(os.path.dirname(p) or cwd, exist_ok=True)
    return out_iqm, out_hero, out_skin, out_blend

OUT_IQM, OUT_HERO, OUT_SKIN, OUT_BLEND = _parse_argv()
IQM_ADDON_DIR = r"C:\Users\Command\Desktop\iqm-master\blender-4.1"

# ---- geometry / anatomy constants ------------------------------------------
N_SEG   = 20                 # seg_00..seg_19
N_BONES = N_SEG + 1          # + whip_root  == 21 bones
WHIP_LEN = 4.0               # total length in Blender units along +Y (mesh space)
SEG_LEN  = WHIP_LEN / N_SEG  # 0.2 u per bone
RADIAL   = 24                # cross-section verts (>=16; 24 = 3x the 8 braid strands)

R_HANDLE  = 0.085            # fat grip
R_BELLY   = 0.105            # belly bulge (fattest point of the thong)
R_FALL    = 0.020           # thin fall near the tip
R_POPPER  = 0.006           # popper cross-section
BELLY_AT  = 0.18            # where along length (0..1) the belly peaks
HANDLE_FRAC = 0.16          # first 16% is the rigid handle

BRAID_STRANDS = 8           # plaited strands around circumference
BRAID_AMP     = 0.035       # very subtle geo ripple; the visible plait lives in the texture
BRAID_TWIST   = 9.0         # spirals over full length

POMMEL_BULGE = 0.055        # pommel knob swell at the butt
COLLAR_BULGE = 0.030        # collar ring at handle/thong seam
COLLAR_AT    = HANDLE_FRAC

def STEP(msg): print("STEP: " + msg, flush=True)

def bone_name(i):
    return "whip_root" if i == 0 else "seg_%02d" % (i - 1)

def smoothstep(a, b, x):
    if b == a:
        return 0.0
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3.0 - 2.0 * t)

# ============================================================================
# 1. Clean scene
# ============================================================================
STEP("clearing scene to empty factory settings")
bpy.ops.wm.read_factory_settings(use_empty=True)

# ============================================================================
# 2. ARMATURE: straight +Y connected chain, whip_root + seg_00..seg_19 (REST)
# ============================================================================
STEP("building straight +Y 21-bone armature (bind/REST pose)")
arm_data = bpy.data.armatures.new("WhipArm")
arm_obj  = bpy.data.objects.new("WhipArmature", arm_data)
bpy.context.collection.objects.link(arm_obj)
bpy.context.view_layer.objects.active = arm_obj

bpy.ops.object.mode_set(mode='EDIT')
prev = None
for i in range(N_BONES):
    eb = arm_data.edit_bones.new(bone_name(i))
    y0 = i * SEG_LEN
    eb.head = Vector((0.0, y0, 0.0))
    eb.tail = Vector((0.0, y0 + SEG_LEN, 0.0))   # long axis = +Y (matches physics chain)
    eb.roll = 0.0
    if prev is not None:
        eb.parent = prev
        eb.use_connect = True
    prev = eb
bpy.ops.object.mode_set(mode='OBJECT')

# ============================================================================
# 3. RADIUS PROFILE (convex belly) + pommel knob + collar
# ============================================================================
def base_radius(t):
    """t in [0,1]. Fat handle -> convex belly -> long convex decay -> fall -> popper."""
    if t <= HANDLE_FRAC:                       # handle: gentle swell into the collar
        u = t / HANDLE_FRAC
        return R_HANDLE + (R_BELLY - R_HANDLE) * smoothstep(0.0, 1.0, u) * 0.6
    if t <= BELLY_AT:                          # rise to the belly peak
        u = (t - HANDLE_FRAC) / (BELLY_AT - HANDLE_FRAC)
        lo = R_HANDLE + (R_BELLY - R_HANDLE) * 0.6
        return lo + (R_BELLY - lo) * smoothstep(0.0, 1.0, u)
    u = (t - BELLY_AT) / (1.0 - BELLY_AT)      # convex taper (pow>1 keeps the belly fat)
    r = R_FALL + (R_BELLY - R_FALL) * math.pow(1.0 - u, 2.4)
    if t > 0.94:                               # last 6% collapses to the popper
        v = (t - 0.94) / 0.06
        r = r * (1.0 - v) + R_POPPER * v
    return r

def pommel_add(t):
    if t >= 0.06:
        return 0.0
    u = t / 0.06
    return POMMEL_BULGE * math.sqrt(max(0.0, 1.0 - (u - 0.15) ** 2 / 0.85))

def collar_add(t):
    d = abs(t - COLLAR_AT)
    if d > 0.04:
        return 0.0
    return COLLAR_BULGE * math.exp(-(d * d) / (2 * 0.014 * 0.014))

def braid_mod(theta, v):
    """Plait ridge modulation; twist INSIDE the cosine -> continuous spiral matching the
    skin texture. Handle stays smooth via the gate."""
    gate = smoothstep(HANDLE_FRAC * 0.6, HANDLE_FRAC + 0.05, v)
    return 1.0 + BRAID_AMP * gate * math.cos(BRAID_STRANDS * theta - BRAID_TWIST * 2.0 * math.pi * v)

# ============================================================================
# 4. MESH: rings of RADIAL verts bridged into quads, UV-mapped, along +Y
# ============================================================================
STEP("generating braided bullwhip mesh (belly taper, pommel, collar, popper)")
ring_ys = []
# dense pommel rings
n_pommel = 6
for k in range(n_pommel):
    ring_ys.append((k / n_pommel) * (HANDLE_FRAC * 0.5) * WHIP_LEN)
# handle up to collar
n_handle = 8
for k in range(1, n_handle + 1):
    ring_ys.append((HANDLE_FRAC * 0.5 + (k / n_handle) * (HANDLE_FRAC * 0.5)) * WHIP_LEN)
# thong: bone boundary + 3 interior rings per segment
for i in range(1, N_BONES + 1):
    y = i * SEG_LEN
    if y > HANDLE_FRAC * WHIP_LEN + 1e-5 and y <= WHIP_LEN:
        for f in (0.0, 0.25, 0.5, 0.75):
            ring_ys.append(y - SEG_LEN * (1.0 - f))
        ring_ys.append(y)
# tip densification
tip_start = 0.92 * WHIP_LEN
n_tip = 5
for k in range(1, n_tip + 1):
    ring_ys.append(tip_start + (k / n_tip) * (WHIP_LEN - tip_start))

ring_ys = sorted(set(round(y, 6) for y in ring_ys if 0.0 <= y <= WHIP_LEN))

bm = bmesh.new()
uv_layer = bm.loops.layers.uv.new("UVMap")
rings = []
for y in ring_ys:
    t = y / WHIP_LEN
    r0 = base_radius(t) + pommel_add(t) + collar_add(t)
    verts = []
    for j in range(RADIAL):
        theta = 2.0 * math.pi * j / RADIAL
        r = r0 * braid_mod(theta, t)
        verts.append(bm.verts.new((r * math.cos(theta), y, r * math.sin(theta))))
    rings.append((verts, y, r0))
bm.verts.ensure_lookup_table()

# clean cylindrical UV: U around, V along length (single long strip -> no braid zipper)
for ri in range(len(rings) - 1):
    va, ya, _ = rings[ri]
    vb, yb, _ = rings[ri + 1]
    v_a = ya / WHIP_LEN
    v_b = yb / WHIP_LEN
    for j in range(RADIAL):
        j2 = (j + 1) % RADIAL
        f = bm.faces.new((va[j], va[j2], vb[j2], vb[j]))
        u0 = j / RADIAL
        u1 = (j + 1) / RADIAL
        L = f.loops
        L[0][uv_layer].uv = (u0, v_a)
        L[1][uv_layer].uv = (u1, v_a)
        L[2][uv_layer].uv = (u1, v_b)
        L[3][uv_layer].uv = (u0, v_b)

# cap the pommel base with a rounded DOME (2 shrinking rings + pole) so the butt reads
# as a knob, not a cut hexagon.
base_ring = rings[0][0]
base_y = rings[0][1]
base_r = rings[0][2]
dome_depth = R_HANDLE * 0.9
prev = base_ring
n_dome = 2
for dr in range(1, n_dome + 1):
    a = dr / (n_dome + 1)                      # 0..1 toward the pole
    ry = base_y - dome_depth * math.sin(a * math.pi * 0.5)
    rr = base_r * math.cos(a * math.pi * 0.5)  # shrink radius toward pole
    cur = [bm.verts.new((rr * math.cos(2*math.pi*j/RADIAL), ry, rr * math.sin(2*math.pi*j/RADIAL)))
           for j in range(RADIAL)]
    for j in range(RADIAL):
        j2 = (j + 1) % RADIAL
        # wind so the outward normal faces -Y/away (recalc below guarantees consistency)
        bm.faces.new((prev[j2], cur[j2], cur[j], prev[j]))
    prev = cur
pole = bm.verts.new((0.0, base_y - dome_depth, 0.0))
for j in range(RADIAL):
    j2 = (j + 1) % RADIAL
    bm.faces.new((prev[j], pole, prev[j2]))

# cap the tip
tip_ring = rings[-1][0]
tip_y = rings[-1][1]
tip_center = bm.verts.new((0.0, tip_y, 0.0))
for j in range(RADIAL):
    j2 = (j + 1) % RADIAL
    bm.faces.new((tip_center, tip_ring[j], tip_ring[j2]))

# frayed POPPER: thin splayed tapered strands past the tip (solid geo, no alpha needed)
popper_strands = 5
popper_len = SEG_LEN * 0.9
popper_root_r = R_POPPER * 1.4
for s in range(popper_strands):
    ang = 2.0 * math.pi * s / popper_strands + 0.3
    splay = 0.10 + 0.05 * (s % 2)
    dirx = math.cos(ang) * splay
    dirz = math.sin(ang) * splay
    seg_rings = 3
    prev_r = None
    for k in range(seg_rings + 1):
        f = k / seg_rings
        yy = tip_y + popper_len * f
        rr = popper_root_r * (1.0 - f) * 0.7 + 0.0008
        cx = dirx * popper_len * f
        cz = dirz * popper_len * f
        cur = []
        for a in range(3):
            th = 2.0 * math.pi * a / 3 + ang
            cur.append(bm.verts.new((cx + rr * math.cos(th), yy, cz + rr * math.sin(th))))
        if prev_r:
            for a in range(3):
                a2 = (a + 1) % 3
                bm.faces.new((prev_r[a], prev_r[a2], cur[a2], cur[a]))
        prev_r = cur

# make every face's normal point consistently outward (caps + popper included)
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
bm.normal_update()
mesh = bpy.data.meshes.new("WhipMesh")
bm.to_mesh(mesh)
bm.free()
whip_obj = bpy.data.objects.new("Whip", mesh)
bpy.context.collection.objects.link(whip_obj)
print("  mesh verts=%d rings=%d bones=%d" % (len(mesh.vertices), len(rings), N_BONES))

# ============================================================================
# 5. SMOOTH SHADING (Blender 4.4: mesh.use_auto_smooth REMOVED)
# ============================================================================
STEP("applying smooth shading (no sharp edges on the tube)")
bpy.context.view_layer.objects.active = whip_obj
whip_obj.select_set(True)
bpy.ops.object.shade_smooth()
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.mark_sharp(clear=True)     # clear stray sharp flags
bpy.ops.mesh.select_all(action='DESELECT')
bpy.ops.object.mode_set(mode='OBJECT')

# ============================================================================
# 6. SKINNING: vertex groups named EXACTLY as bones + smooth 2-bone Y blend
# ============================================================================
STEP("skinning: vertex groups whip_root/seg_00..seg_19 + Armature modifier")
vgroups = {i: whip_obj.vertex_groups.new(name=bone_name(i)) for i in range(N_BONES)}

def bone_weights_for_y(y):
    yc = max(0.0, min(WHIP_LEN - 1e-6, y))
    seg = max(0, min(N_BONES - 1, int(yc / SEG_LEN)))
    center = (seg + 0.5) * SEG_LEN
    if yc >= center:
        nb = min(N_BONES - 1, seg + 1)
        w = smoothstep(0.0, 1.0, (yc - center) / SEG_LEN) * 0.5
        return {seg: 1.0 - w, nb: w}
    nb = max(0, seg - 1)
    w = smoothstep(0.0, 1.0, (center - yc) / SEG_LEN) * 0.5
    return {seg: 1.0 - w, nb: w}

for v in mesh.vertices:
    w = bone_weights_for_y(v.co.y)
    tot = sum(w.values())
    for bi, wt in w.items():
        if wt > 1e-5:
            vgroups[bi].add([v.index], wt / tot, 'REPLACE')

mod = whip_obj.modifiers.new("Armature", 'ARMATURE')
mod.object = arm_obj
mod.use_vertex_groups = True
whip_obj.parent = arm_obj

# ============================================================================
# 7. BRAIDED-LEATHER SKIN PNG -- pure stdlib (zlib+struct). Diamond plait.
#    Tiles along V (length), wraps around U. 8 strands around, pitch 6 along.
# ============================================================================
STEP("baking braided-leather skin PNG (stdlib zlib+struct)")
def write_whip_skin(path, W=256, H=1024):
    base   = (0.431, 0.267, 0.149)   # saddle-brown body
    hi     = (0.659, 0.471, 0.290)   # worn strand-crown highlight
    groove = (0.239, 0.137, 0.071)   # plait-groove shadow
    handle = (0.361, 0.204, 0.118)   # hand-oiled darker/redder grip
    dusty  = (0.588, 0.455, 0.322)   # paler dusty tip/fall
    N_around, pitch = 8.0, 6.0

    def lerp(a, b, t):
        return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))

    def s255(c):
        return bytes(max(0, min(255, int(round(v * 255.0)))) for v in c)

    raw = bytearray()
    two_pi = 2.0 * math.pi
    for y in range(H):
        v = y / H
        raw.append(0)                             # PNG filter byte (None) per scanline
        # zone tint: darker/redder handle at low V, paler dusty toward the tip (high V)
        for x in range(W):
            u = x / W
            a = math.sin(two_pi * (u * N_around + v * pitch))
            b = math.sin(two_pi * (u * N_around - v * pitch))
            ridge = max(0.5 + 0.5 * a, 0.5 + 0.5 * b)
            ridge = ridge * ridge * (3.0 - 2.0 * ridge)          # smoothstep-round crown
            gmask = 1.0 - min(1.0, (abs(a) + abs(b)) * 0.9)      # groove valleys
            h = math.sin(x * 12.9898 + y * 78.233) * 43758.5453   # deterministic grain
            grain = (h - math.floor(h)) - 0.5

            t_hi = max(0.0, ridge - 0.55) / 0.45
            col = lerp(base, hi, min(1.0, t_hi) * 0.85)
            col = lerp(col, groove, min(1.0, gmask * 1.1))

            # zone re-tint (kept subtle so the plait still reads everywhere)
            if v < HANDLE_FRAC:                                   # oiled grip zone
                z = smoothstep(HANDLE_FRAC, HANDLE_FRAC * 0.4, v) # 1 at butt -> 0 at seam
                col = lerp(col, handle, 0.45 * z)
            elif v > 0.86:                                        # fall + popper zone
                z = smoothstep(0.86, 1.0, v)
                col = lerp(col, dusty, 0.40 * z)

            col = tuple(max(0.0, min(1.0, c * (1.0 + 0.10 * grain))) for c in col)
            raw.extend(s255(col))

    def chunk(typ, data):
        return struct.pack(">I", len(data)) + typ + data + \
               struct.pack(">I", zlib.crc32(typ + data) & 0xffffffff)

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0)))  # 8-bit truecolor
        f.write(chunk(b"IDAT", zlib.compress(bytes(raw), 9)))
        f.write(chunk(b"IEND", b""))
    return path

write_whip_skin(OUT_SKIN)
print("  skin ->", OUT_SKIN, "exists:", os.path.exists(OUT_SKIN))

# ============================================================================
# 8. HERO LEATHER MATERIAL 'xrwhip' (Principled BSDF, 4.4-safe by NAME)
# ============================================================================
STEP("building worn braided-leather hero material 'xrwhip'")
def set_in(node, name, value, index_fallback=None):
    sock = node.inputs.get(name)
    if sock is None and index_fallback is not None:
        try:
            sock = node.inputs[index_fallback]
        except Exception:
            sock = None
    if sock is not None:
        try:
            sock.default_value = value
            return True
        except Exception:
            return False
    return False

mat = bpy.data.materials.new("xrwhip")
mat.use_nodes = True
nt = mat.node_tree
nt.nodes.clear()
out  = nt.nodes.new("ShaderNodeOutputMaterial"); out.location = (900, 0)
bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled"); bsdf.location = (600, 0)
tc   = nt.nodes.new("ShaderNodeTexCoord"); tc.location = (-1200, 0)
mapp = nt.nodes.new("ShaderNodeMapping"); mapp.location = (-1000, 0)
# Tile the plait several times along the length (V) so diamonds are dense enough to
# read as a braid at camera distance; the PNG tiles seamlessly along V (integer pitch).
mapp.inputs["Scale"].default_value = (1.0, 7.0, 1.0)
nt.links.new(tc.outputs["UV"], mapp.inputs["Vector"])

# The baked braid PNG drives Base Color so the hero matches what ships in-engine.
tex = nt.nodes.new("ShaderNodeTexImage"); tex.location = (-700, 250)
tex.image = bpy.data.images.load(OUT_SKIN)
tex.extension = 'REPEAT'
try:
    tex.image.colorspace_settings.name = 'sRGB'
except Exception:
    pass
nt.links.new(mapp.outputs["Vector"], tex.inputs["Vector"])

# Handle mask from the UNSCALED UV V (0=butt .. 1=tip): the braid stops on the rigid
# grip, which stays smooth oiled leather. Separate the V channel, ramp it to a mask.
sep = nt.nodes.new("ShaderNodeSeparateXYZ"); sep.location = (-700, 500)
nt.links.new(tc.outputs["UV"], sep.inputs["Vector"])   # unscaled UV: Y = length V
hramp = nt.nodes.new("ShaderNodeValToRGB"); hramp.location = (-500, 500)
hramp.color_ramp.interpolation = 'EASE'
hramp.color_ramp.elements[0].position = HANDLE_FRAC * 0.7
hramp.color_ramp.elements[0].color = (1, 1, 1, 1)      # handle -> mask 1
hramp.color_ramp.elements[1].position = HANDLE_FRAC + 0.02
hramp.color_ramp.elements[1].color = (0, 0, 0, 1)      # thong -> mask 0
nt.links.new(sep.outputs["Y"], hramp.inputs["Fac"])
handle_col = nt.nodes.new("ShaderNodeRGB"); handle_col.location = (-500, 650)
handle_col.outputs[0].default_value = (0.085, 0.05, 0.03, 1.0)   # dark oiled grip (deepened)
basemix = nt.nodes.new("ShaderNodeMixRGB"); basemix.location = (-250, 350)
basemix.blend_type = 'MIX'
nt.links.new(hramp.outputs["Color"], basemix.inputs["Fac"])   # 0=braid, 1=handle
nt.links.new(tex.outputs["Color"], basemix.inputs[1])
nt.links.new(handle_col.outputs[0], basemix.inputs[2])
nt.links.new(basemix.outputs["Color"], bsdf.inputs["Base Color"])

# Noise -> roughness variation (Musgrave is GONE in 4.4; use Noise)
noise = nt.nodes.new("ShaderNodeTexNoise"); noise.location = (-700, -50)
set_in(noise, "Scale", 8.0); set_in(noise, "Detail", 4.0); set_in(noise, "Roughness", 0.6)
nt.links.new(mapp.outputs["Vector"], noise.inputs["Vector"])
rr = nt.nodes.new("ShaderNodeValToRGB"); rr.location = (-400, -50)
rr.color_ramp.elements[0].position = 0.2; rr.color_ramp.elements[0].color = (0.60,)*3 + (1,)
rr.color_ramp.elements[1].position = 0.9; rr.color_ramp.elements[1].color = (0.82,)*3 + (1,)
nt.links.new(noise.outputs["Fac"], rr.inputs["Fac"])
nt.links.new(rr.outputs["Color"], bsdf.inputs["Roughness"])

# Bump driven by the SAME baked braid texture so raised plait strands and diffuse
# diamonds line up. Flatten it on the handle (mix bump height toward mid-gray there).
bumpmix = nt.nodes.new("ShaderNodeMixRGB"); bumpmix.location = (100, -400)
bumpmix.blend_type = 'MIX'
bumpmix.inputs[2].default_value = (0.5, 0.5, 0.5, 1.0)     # flat height on the handle
nt.links.new(hramp.outputs["Color"], bumpmix.inputs["Fac"])
nt.links.new(tex.outputs["Color"], bumpmix.inputs[1])
bump = nt.nodes.new("ShaderNodeBump"); bump.location = (300, -400)
set_in(bump, "Strength", 0.28); set_in(bump, "Distance", 0.02)
nt.links.new(bumpmix.outputs["Color"], bump.inputs["Height"])
nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])

# leather feel: semi-matte, low spec, soft sheen, thin coat, no metal
set_in(bsdf, "Metallic", 0.0)
set_in(bsdf, "Specular IOR Level", 0.14, 13)
set_in(bsdf, "Sheen Weight", 0.0, 24)
set_in(bsdf, "Sheen Roughness", 0.40, 25)
set_in(bsdf, "Coat Weight", 0.0)
set_in(bsdf, "Coat Roughness", 0.35)
nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

# clear any auto-material then apply ours
whip_obj.data.materials.clear()
whip_obj.data.materials.append(mat)

# ============================================================================
# 9. EXPORT IQM FIRST (rig is straight; exporter also forces REST -> belt+braces)
# ============================================================================
STEP("exporting straight-REST rigged IQM via iqm-master exporter")
if IQM_ADDON_DIR not in sys.path:
    sys.path.append(IQM_ADDON_DIR)
import iqm_export

bpy.ops.object.mode_set(mode='OBJECT')
bpy.ops.object.select_all(action='DESELECT')
whip_obj.select_set(True)
arm_obj.select_set(True)
bpy.context.view_layer.objects.active = arm_obj    # armature ACTIVE (required)

iqm_export.exportIQM(
    bpy.context, OUT_IQM,
    usemesh=True, usemods=False, useskel=True, usebbox=False, usecol=False,
    scale=1.0, matfun=(lambda prefix, image: "xrwhip"))
print("  iqm ->", OUT_IQM, "exists:", os.path.exists(OUT_IQM))

# ============================================================================
# 10. HERO POSE: coil the whip in POSE mode ONLY (never exported)
#     21 bones compound -> per-bone angles MUST stay tiny (~0.05-0.14 rad).
# ============================================================================
STEP("posing a graceful coil in POSE mode (render-only, not exported)")
bpy.ops.object.select_all(action='DESELECT')
arm_obj.select_set(True)
bpy.context.view_layer.objects.active = arm_obj
bpy.ops.object.mode_set(mode='POSE')
pb = arm_obj.pose.bones
# The chain bends in the X-Z plane (each bone's local-Z rotation curls it around the
# world +Z axis while it advances along +Y). A near-constant per-bone curl builds ~2.5
# overlapping loops = the classic laid-down bullwhip coil, read broadside from -Z (top).
# 21 bones compound, so the curl per bone is TINY. Total curl target ~ 2.5*360deg spread
# over the ~17 thong bones -> ~53deg/bone is far too much (closed hoop); instead a gentle
# curl that grows toward the tip (tighter inner loops) reads as a real coil.
for i in range(N_BONES):
    b = pb[bone_name(i)]
    b.rotation_mode = 'XYZ'
    t = i / (N_BONES - 1)
    if t < HANDLE_FRAC:                       # rigid grip, angled up slightly out of the coil
        rx, ry, rz = -0.06, 0.0, 0.0
    else:
        u = (t - HANDLE_FRAC) / (1.0 - HANDLE_FRAC)   # 0..1 along the thong
        # steady in-plane curl (local-Z) that tightens toward the tip -> nested loops
        rz = 0.16 + 0.16 * u                          # ~0.16..0.32 rad/bone, compounds to loops
        # gentle lift so the coil is a shallow spiral, not a flat pancake -> reads 3D
        rx = 0.05 * math.sin(u * math.pi * 2.0)
        ry = 0.0
    b.rotation_euler = Euler((rx, ry, rz), 'XYZ')
bpy.context.view_layer.update()
bpy.context.evaluated_depsgraph_get().update()
bpy.ops.object.mode_set(mode='OBJECT')        # deformation persists via Armature modifier

# ============================================================================
# 11. CINEMATIC SCENE: engine + color mgmt + world + ground + lights + camera
# ============================================================================
scene = bpy.context.scene

STEP("configuring render engine (Cycles GPU w/ CPU fallback)")
try:
    scene.render.engine = 'CYCLES'
    prefs = bpy.context.preferences.addons['cycles'].preferences
    chosen = 'NONE'
    for backend in ('OPTIX', 'CUDA', 'HIP', 'ONEAPI'):
        try:
            prefs.compute_device_type = backend
            prefs.get_devices()
            if any(d.type == backend for d in prefs.devices):
                for d in prefs.devices:
                    d.use = (d.type == backend)
                scene.cycles.device = 'GPU'; chosen = backend; break
        except Exception:
            continue
    if chosen == 'NONE':
        scene.cycles.device = 'CPU'
    scene.cycles.samples = 128
    scene.cycles.use_denoising = True
    try:
        scene.cycles.denoiser = 'OPENIMAGEDENOISE'
    except Exception:
        pass
    scene.cycles.use_adaptive_sampling = True
    scene.cycles.adaptive_threshold = 0.01
    print("  Cycles device backend:", chosen)
except Exception as e:
    # last-resort: EEVEE Next so we ALWAYS produce a render
    try:
        scene.render.engine = 'BLENDER_EEVEE_NEXT'
    except Exception:
        pass
    print("  Cycles unavailable, using", scene.render.engine, "(", e, ")")

STEP("color management: AgX + Medium High Contrast + slight underexpose")
vs = scene.view_settings
try:
    vs.view_transform = 'AgX'
except Exception:
    try: vs.view_transform = 'Filmic'
    except Exception: pass
try:
    vs.look = 'AgX - Medium High Contrast'
except Exception:
    try: vs.look = 'Medium High Contrast'
    except Exception: pass
try:
    vs.exposure = -0.5
    vs.gamma = 1.0
except Exception:
    pass

r = scene.render
r.resolution_x = 1600
r.resolution_y = 1000
r.resolution_percentage = 100
r.film_transparent = False
r.image_settings.file_format = 'PNG'
r.image_settings.color_mode = 'RGBA'
try:
    r.image_settings.color_depth = '16'
except Exception:
    pass

STEP("world: warm->black spherical gradient dome")
world = bpy.data.worlds.new("HeroWorld"); scene.world = world
world.use_nodes = True
wn = world.node_tree; wn.nodes.clear()
bg    = wn.nodes.new('ShaderNodeBackground')
grad  = wn.nodes.new('ShaderNodeTexGradient'); grad.gradient_type = 'SPHERICAL'
wmapp = wn.nodes.new('ShaderNodeMapping')
wtex  = wn.nodes.new('ShaderNodeTexCoord')
wramp = wn.nodes.new('ShaderNodeValToRGB')
wramp.color_ramp.elements[0].position = 0.0
wramp.color_ramp.elements[0].color = (0.09, 0.055, 0.03, 1.0)
wramp.color_ramp.elements[1].position = 1.0
wramp.color_ramp.elements[1].color = (0.008, 0.006, 0.005, 1.0)
wout = wn.nodes.new('ShaderNodeOutputWorld')
wn.links.new(wtex.outputs['Window'], wmapp.inputs['Vector'])
wn.links.new(wmapp.outputs['Vector'], grad.inputs['Vector'])
wn.links.new(grad.outputs['Fac'], wramp.inputs['Fac'])
wn.links.new(wramp.outputs['Color'], bg.inputs['Color'])
bg.inputs['Strength'].default_value = 1.0
wn.links.new(bg.outputs['Background'], wout.inputs['Surface'])

# --- auto-fit to the DEFORMED (posed) mesh world bounds ---
STEP("auto-fitting camera & lights to the coiled silhouette")
dg = bpy.context.evaluated_depsgraph_get()
eo = whip_obj.evaluated_get(dg)
em = eo.to_mesh()
mw = eo.matrix_world
mn = Vector((1e9, 1e9, 1e9)); mx = Vector((-1e9, -1e9, -1e9))
for v in em.vertices:
    wc = mw @ v.co
    for a in range(3):
        mn[a] = min(mn[a], wc[a]); mx[a] = max(mx[a], wc[a])
eo.to_mesh_clear()
center = (mn + mx) * 0.5
extent = (mx - mn)
radius = max(extent.x, extent.y, extent.z) * 0.5 + 1e-4
print("  coil bounds extent=(%.2f,%.2f,%.2f) center=(%.2f,%.2f,%.2f)" %
      (extent.x, extent.y, extent.z, center.x, center.y, center.z))

# dusty ground plane for a soft contact shadow
STEP("ground plane (dusty stone/leather-shop floor)")
gm = bpy.data.materials.new("GroundMat"); gm.use_nodes = True
gnt = gm.node_tree; gbsdf = gnt.nodes.get("Principled BSDF")
if gbsdf:
    set_in(gbsdf, "Base Color", (0.05, 0.04, 0.032, 1.0))
    set_in(gbsdf, "Roughness", 0.92)
    nz = gnt.nodes.new('ShaderNodeTexNoise')
    set_in(nz, "Scale", 8.0); set_in(nz, "Detail", 6.0)
    gbmp = gnt.nodes.new('ShaderNodeBump'); set_in(gbmp, "Strength", 0.12)
    gnt.links.new(nz.outputs['Fac'], gbmp.inputs['Height'])
    gnt.links.new(gbmp.outputs['Normal'], gbsdf.inputs['Normal'])
bpy.ops.mesh.primitive_plane_add(size=max(20.0, radius * 20.0),
                                 location=(center.x, center.y, mn.z - radius * 0.06))
ground = bpy.context.active_object; ground.name = "Ground"
ground.data.materials.append(gm)

# three-point lighting, energy scaled by distance^2
STEP("three-point lighting: warm key / cool rim / soft fill")
def add_area(name, offset, energy, color, size):
    ld = bpy.data.lights.new(name, 'AREA')
    ld.energy = energy; ld.color = color; ld.size = size
    lo = bpy.data.objects.new(name, ld)
    loc = center + Vector(offset).normalized() * (radius * 2.4 + 0.6)
    lo.location = loc
    lo.rotation_euler = (center - loc).to_track_quat('-Z', 'Y').to_euler()
    bpy.context.collection.objects.link(lo)
    return lo

p = (radius * 2.4 + 0.6) ** 2
add_area("Key",  (-1.0, -0.8, 1.0), 19.0 * p, (1.00, 0.92, 0.82), radius * 3.0)   # warm-WHITE key (was too orange)
add_area("Rim",  ( 1.0,  1.0, 0.9), 13.0 * p, (0.60, 0.72, 1.00), radius * 1.6)   # cool rim, behind-right
add_area("Fill", ( 1.0, -1.0, 0.5),  3.0 * p, (0.96, 0.94, 0.92), radius * 5.0)   # lifted neutral fill

# camera: cinematic low 3/4, shallow DoF, framed so the WHOLE coil fits.
# The coil is broadest in its two largest-extent axes and thin along the third
# (the least-extent axis = the natural viewing direction). We view down that thin
# axis with a slight 3/4 tilt, and compute the distance from the FOV so the whole
# bounding sphere fits with margin (robust for a long thin object, unlike a fixed mult).
STEP("camera: 65mm 3/4 framed to the full coil via FOV fit")
cam_data = bpy.data.cameras.new("HeroCam")
cam_data.lens = 65
cam_data.dof.use_dof = True
cam_data.dof.aperture_fstop = 2.8
cam = bpy.data.objects.new("HeroCam", cam_data)
bpy.context.collection.objects.link(cam)

# viewing direction = down the axis of LEAST extent (look at the broad face of the coil)
dims = [extent.x, extent.y, extent.z]
thin_axis = dims.index(min(dims))
view_dir = [0.0, 0.0, 0.0]
view_dir[thin_axis] = -1.0                          # look along -thin toward center
# add a cinematic 3/4 tilt in the two broad axes so it's not a dead-flat orthographic feel
broad = [a for a in (0, 1, 2) if a != thin_axis]
view_dir[broad[0]] += 0.35
view_dir[broad[1]] += 0.28
view = Vector(view_dir).normalized()

# fit distance: bounding-sphere radius / tan(half-fov), using the NARROWER sensor fit
half_diag = 0.5 * math.sqrt(extent.x**2 + extent.y**2 + extent.z**2)
aspect = scene.render.resolution_x / scene.render.resolution_y
# vertical FOV from lens+sensor (sensor_fit AUTO -> sensor_width is the fit dim on wide frames)
sensor = cam_data.sensor_width
hfov = 2.0 * math.atan((sensor * 0.5) / cam_data.lens)
vfov = 2.0 * math.atan(math.tan(hfov / 2.0) / aspect)
fit_fov = min(hfov, vfov)
dist = (half_diag * 1.5) / math.tan(fit_fov / 2.0)  # 1.5 = comfy margin around the coil

cam.location = center - view * dist                 # camera sits back along -view
direction = (center - cam.location)
cam.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()
cam_data.dof.focus_distance = direction.length
scene.camera = cam
print("  thin_axis=%d view=(%.2f,%.2f,%.2f) dist=%.2f" % (thin_axis, view.x, view.y, view.z, dist))

# ============================================================================
# 12. RENDER the hero PNG
# ============================================================================
STEP("rendering hero PNG -> " + OUT_HERO)
scene.render.filepath = OUT_HERO
bpy.ops.render.render(write_still=True)
print("  hero ->", OUT_HERO, "exists:", os.path.exists(OUT_HERO))

# optional .blend save
if OUT_BLEND:
    STEP("saving .blend -> " + OUT_BLEND)
    try:
        bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
    except Exception as e:
        print("  blend save failed:", e)

# ============================================================================
# 13. Report
# ============================================================================
def _sz(p):
    try:
        return os.path.getsize(p)
    except Exception:
        return 0

print("DONE iqm=%d render=%d skin=%d" % (_sz(OUT_IQM), _sz(OUT_HERO), _sz(OUT_SKIN)), flush=True)
