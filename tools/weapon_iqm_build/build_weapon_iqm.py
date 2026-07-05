"""
build_weapon_iqm.py -- generalized DoomXR weapon MD3 -> rigged IQM + hotspot bones.
Headless Blender 4.4. The reusable, per-weapon successor to hud/rifle/build_m16_iqm.py.

Instead of the m16's hard-coded HOTSPOTS block, it reads a per-weapon CONFIG and derives
each weapon's hotspots from ITS OWN frame-0 mesh geometry via md3_hotspots.derive_hotspots
(barrel span on the long axis, magazine at the low vertical axis, charging area at the
receiver top) -- with optional explicit coordinates / axis hints / tuning knobs in the config.

Run (config form -- preferred, used by the batch driver):
  blender --background --python build_weapon_iqm.py -- <config.json>
Run (positional quick form):
  blender --background --python build_weapon_iqm.py -- <in.md3> <out.iqm> [style] [material]

CONFIG JSON keys:
  md3        (str, REQUIRED)  source MD3 path (opened read-only, NEVER modified/deleted)
  out        (str, REQUIRED)  output IQM path (the ONLY thing written)
  style      (str)            reload style -> hotspot set: boxmag|shell|break|pod|canister|none (default boxmag)
  material   (str)            IQM material NAME (the modeldef 'Skin 0' binds the real texture). default = out stem
  hotspots   (dict)           explicit {bone:[x,y,z]} in MD3 model space -> baked VERBATIM (skips derivation)
  overrides  (dict)           {bone:[x,y,z]} -> override just those derived points
  knobs      (dict)           placement-fraction tuning passed to derive_hotspots
  axis       (dict)           {long,vert,lat:0|1|2, muzzle_at_max:bool} -> force orientation (mis-analyzed mesh)

Export contract is IDENTICAL to build_m16_iqm.py (verified working in-headset):
  * MD3 frame-0 mesh rebuilt in its OWN coordinate frame (no axis swap) so modeldef
    Scale/Offset/ZOffset -- including a negative-X mirror -- carry over 1:1.
  * every vert skinned 100% to a single NON-DEFORMING hs_grip bone (mesh renders exactly
    like the MD3 bind pose); the hotspot bones carry ZERO weight (pure named data points).
  * scale 1.0 (do NOT pre-scale; modeldef Scale is applied in-engine), useskel=True, a single
    implicit bind frame. The MD3's baked reload/fire frames are dropped on purpose -- native
    VR_UpdateWeaponReload replaces them (VR_WEAPON_HANDLING_ENGINE_LEVEL.md section B/4).

SAFETY: reads the MD3 read-only; writes ONLY the out IQM. Never deletes anything.
"""

import bpy, bmesh, os, sys, json, struct
from mathutils import Vector

THIS_DIR = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else os.getcwd()
if THIS_DIR not in sys.path:
    sys.path.append(THIS_DIR)
import md3_hotspots as MH

IQM_ADDON_DIR = r"C:\Users\Command\Desktop\Documentation\iqm-master\blender-4.1"


def STEP(m):
    print("STEP: " + m, flush=True)


# ---------------------------------------------------------------------------
# 0. CONFIG: single .json arg, or positional <in.md3> <out.iqm> [style] [material]
# ---------------------------------------------------------------------------
def parse_config():
    argv = sys.argv
    args = argv[argv.index("--") + 1:] if "--" in argv else []
    if len(args) == 1 and args[0].lower().endswith(".json"):
        with open(args[0], "r") as f:
            cfg = json.load(f)
    else:
        cfg = {}
        if len(args) >= 1:
            cfg["md3"] = args[0]
        if len(args) >= 2:
            cfg["out"] = args[1]
        if len(args) >= 3:
            cfg["style"] = args[2]
        if len(args) >= 4:
            cfg["material"] = args[3]
    if "md3" not in cfg or "out" not in cfg:
        raise SystemExit("config needs 'md3' and 'out' (or positional <in.md3> <out.iqm>)")
    cfg["md3"] = os.path.abspath(cfg["md3"])
    cfg["out"] = os.path.abspath(cfg["out"])
    cfg.setdefault("style", "boxmag")
    cfg.setdefault("material", os.path.splitext(os.path.basename(cfg["out"]))[0])
    os.makedirs(os.path.dirname(cfg["out"]) or THIS_DIR, exist_ok=True)
    return cfg


CFG = parse_config()
STYLE = CFG["style"]
MAT = CFG["material"]

# ready_frame = the MD3 frame the weapon's modeldef maps its READY/idle sprite state to.
# The IQM ships ONE bind frame, so it must be the RESTING pose -- baking frame 0 (a mid-draw
# transition for most weapons) froze guns tilted once repointed to the IQM. Default 0 (correct
# for weapons whose rest pose IS frame 0, e.g. the proven m16/rifle).
RF = int(CFG.get("ready_frame", 0))
STEP("reading MD3: MESH from ready frame %d, hotspot basis from frame 0: %s" % (RF, CFG["md3"]))
SURFS = MH.read_md3(CFG["md3"], RF)          # MESH baked at the RESTING pose
VERTS = MH._flatten_verts(SURFS)
VERTS0 = VERTS if RF == 0 else MH._flatten_verts(MH.read_md3(CFG["md3"], 0))
print("  surfaces=%d totalVerts=%d readyFrame=%d" % (len(SURFS), len(VERTS), RF))


def _centroid(vs):
    n = len(vs)
    if not n:
        return (0.0, 0.0, 0.0)
    return (sum(v[0] for v in vs) / n, sum(v[1] for v in vs) / n, sum(v[2] for v in vs) / n)


# Whole-gun translation from frame 0 to the ready frame. Explicit hotspots are authored in
# frame-0 model space; the mesh now sits at the ready frame, so shift the (non-carrier) hotspots
# by the same centroid delta to keep magwell/rack/etc ON the resting model (well within the
# native reload radii). hs_grip stays at origin: it's the non-deforming weight anchor whose
# position never affects the render (verts are baked in place).
_c0 = _centroid(VERTS0)
_cR = _centroid(VERTS)
DELTA = (_cR[0] - _c0[0], _cR[1] - _c0[1], _cR[2] - _c0[2])
if RF != 0:
    print("  ready-frame centroid delta vs frame0: (%.3f, %.3f, %.3f)" % DELTA)

# ---------------------------------------------------------------------------
# 1. Resolve HOTSPOTS: explicit config wins; else derive from THIS mesh's geometry.
#    Analysis/derivation runs on the READY-frame verts so hotspots match the baked mesh.
# ---------------------------------------------------------------------------
if CFG.get("hotspots"):
    HS = {name: tuple(float(c) for c in xyz) for name, xyz in CFG["hotspots"].items()}
    HS.setdefault("hs_grip", (0.0, 0.0, 0.0))
    if RF != 0:
        for name in HS:
            if name == "hs_grip":
                continue
            HS[name] = (HS[name][0] + DELTA[0], HS[name][1] + DELTA[1], HS[name][2] + DELTA[2])
    geo = MH.analyze_geometry(VERTS)
    STEP("using EXPLICIT hotspots from config (%d)%s" % (len(HS), " (shifted to ready frame)" if RF != 0 else ""))
else:
    HS, geo = MH.derive_hotspots(VERTS, STYLE,
                                 overrides=CFG.get("overrides"),
                                 knobs=CFG.get("knobs"),
                                 axis=CFG.get("axis"))
    STEP("DERIVED hotspots from ready-frame geometry for style '%s' (%d)" % (STYLE, len(HS)))

AXN = "XYZ"
print("  orientation: long=%s vert=%s lat=%s muzzle@%s bore(v=%.2f,l=%.2f)" % (
    AXN[geo["long_ax"]], AXN[geo["vert_ax"]], AXN[geo["lat_ax"]],
    ("MAX" if geo["muzzle_at_max"] else "MIN"), geo["bore_v"], geo["bore_l"]))
for name in sorted(HS):
    print("  %-13s (%8.3f, %8.3f, %8.3f)" % (name, HS[name][0], HS[name][1], HS[name][2]))

# ---------------------------------------------------------------------------
# 2. Clean scene
# ---------------------------------------------------------------------------
STEP("clearing scene")
bpy.ops.wm.read_factory_settings(use_empty=True)

# ---------------------------------------------------------------------------
# 3. Rebuild mesh (all surfaces merged) + UVs, in the MD3's own coordinate frame.
# ---------------------------------------------------------------------------
STEP("rebuilding mesh + UVs from MD3 surfaces")
bm = bmesh.new()
uv = bm.loops.layers.uv.new("UVMap")
for s in SURFS:
    bverts = [bm.verts.new(v) for v in s["verts"]]
    bm.verts.ensure_lookup_table()
    for (a, b, c) in s["tris"]:
        try:
            f = bm.faces.new((bverts[a], bverts[b], bverts[c]))
        except ValueError:
            continue  # duplicate face across surfaces -- harmless
        for loop, vidx in zip(f.loops, (a, b, c)):
            u_, v_ = s["st"][vidx]
            loop[uv].uv = (u_, 1.0 - v_)  # MD3 V is top-down; flip to GL/Blender bottom-up
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
bm.normal_update()
mesh = bpy.data.meshes.new("WMesh")
bm.to_mesh(mesh)
bm.free()
gun = bpy.data.objects.new("Weapon", mesh)
bpy.context.collection.objects.link(gun)
bpy.context.view_layer.objects.active = gun
gun.select_set(True)
bpy.ops.object.shade_smooth()
print("  mesh verts=%d faces=%d" % (len(mesh.vertices), len(mesh.polygons)))

# ---------------------------------------------------------------------------
# 4. Armature: hs_grip root + style hotspot children (1-unit +Y stubs; only the HEAD
#    position matters -- it is read as the bind-local Translate). Children parented to the
#    carrier but NOT connected, so each keeps its own head position.
# ---------------------------------------------------------------------------
STEP("building hotspot armature: " + ", ".join(sorted(HS)))
arm_data = bpy.data.armatures.new("WArm")
arm_obj = bpy.data.objects.new("WArmature", arm_data)
bpy.context.collection.objects.link(arm_obj)
bpy.context.view_layer.objects.active = arm_obj
bpy.ops.object.mode_set(mode='EDIT')
carrier_xyz = HS.get("hs_grip", (0.0, 0.0, 0.0))
root_eb = arm_data.edit_bones.new("hs_grip")
rc = Vector(carrier_xyz)
root_eb.head = rc
root_eb.tail = rc + Vector((0.0, 1.0, 0.0))
for name in sorted(HS):
    if name == "hs_grip":
        continue
    eb = arm_data.edit_bones.new(name)
    h = Vector(HS[name])
    eb.head = h
    eb.tail = h + Vector((0.0, 1.0, 0.0))
    eb.parent = root_eb
    eb.use_connect = False
bpy.ops.object.mode_set(mode='OBJECT')

# ---------------------------------------------------------------------------
# 5. Skin EVERY vert -> hs_grip @ 1.0 (non-deforming). Hotspot bones stay weightless.
# ---------------------------------------------------------------------------
STEP("skinning all verts to hs_grip (non-deforming) + Armature modifier")
vg = gun.vertex_groups.new(name="hs_grip")
vg.add([v.index for v in mesh.vertices], 1.0, 'REPLACE')
mod = gun.modifiers.new("Armature", 'ARMATURE')
mod.object = arm_obj
mod.use_vertex_groups = True
gun.parent = arm_obj

# ---------------------------------------------------------------------------
# 6. Material NAME (skin bound by modeldef 'Skin 0'); exporter's matfun returns it.
# ---------------------------------------------------------------------------
STEP("assigning material name '%s' (texture bound by modeldef Skin 0)" % MAT)
mat = bpy.data.materials.new(MAT)
gun.data.materials.clear()
gun.data.materials.append(mat)

# ---------------------------------------------------------------------------
# 7. Export via the iqm-master exporter (same call shape as build_m16_iqm.py).
# ---------------------------------------------------------------------------
STEP("exporting rigged IQM (scale 1.0, bind pose only) -> " + CFG["out"])
if IQM_ADDON_DIR not in sys.path:
    sys.path.append(IQM_ADDON_DIR)
import iqm_export

bpy.ops.object.mode_set(mode='OBJECT')
bpy.ops.object.select_all(action='DESELECT')
gun.select_set(True)
arm_obj.select_set(True)
bpy.context.view_layer.objects.active = arm_obj  # armature ACTIVE (required by exporter)

iqm_export.exportIQM(
    bpy.context, CFG["out"],
    usemesh=True, usemods=False, useskel=True, usebbox=False, usecol=False,
    scale=1.0, matfun=(lambda prefix, image: MAT))


def _sz(p):
    try:
        return os.path.getsize(p)
    except Exception:
        return 0


ok = os.path.exists(CFG["out"]) and _sz(CFG["out"]) > 0
result = dict(
    weapon=os.path.splitext(os.path.basename(CFG["out"]))[0],
    md3=CFG["md3"], out=CFG["out"], style=STYLE, material=MAT,
    built=ok, size=_sz(CFG["out"]),
    orientation=dict(long=AXN[geo["long_ax"]], vert=AXN[geo["vert_ax"]],
                     lat=AXN[geo["lat_ax"]], muzzle_at_max=geo["muzzle_at_max"]),
    hotspots={k: [round(c, 4) for c in v] for k, v in HS.items()},
)
print("RESULT_JSON: " + json.dumps(result), flush=True)
print("DONE built=%s size=%d out=%s" % (ok, _sz(CFG["out"]), CFG["out"]), flush=True)
