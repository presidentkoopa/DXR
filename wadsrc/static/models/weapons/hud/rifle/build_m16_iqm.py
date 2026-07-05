"""
DoomXR m16 (Rifle) MD3 -> rigged IQM with reload/two-hand HOTSPOT bones.
Headless, Blender 4.4, reuses the iqm-master exporter (same as build_whip.py).

WHY a custom loader: Blender ships NO MD3 importer, and none is installed. But the
MD3 format is trivial (int16*1/64 verts + float ST), so this file parses m16.md3 in
pure Python (stdlib struct only), rebuilds the mesh + UVs in bmesh, then attaches a
tiny 3-bone armature whose bones are the reload/two-hand HOTSPOTS the native engine
reads. Every mesh vert is skinned 100% to a single non-deforming carrier bone
(hs_carrier) so the mesh renders IDENTICALLY to the MD3 bind pose -- the hotspot bones
(hs_foregrip / hs_magwell / hs_rack) carry ZERO mesh weight; they exist purely so
IQMModel::Joints[] exposes their names + bind-local Translate for GetBoneIndex/
GetBoneBindPos. collectBones() in iqm_export.py walks data.bones.values(), so
weightless bones ARE exported as joints (verified).

Run (from the rifle model dir, so relative m16.md3 resolves):
  blender --background --python build_m16_iqm.py -- [m16.md3] [m16.iqm]

Output: m16.iqm  -- a single-frame (idle/ready = MD3 frame 0) rigged INTERQUAKEMODEL v2
carrying 4 joints (hs_carrier + 3 hotspots). The 40 baked reload/fire MD3 frames are
INTENTIONALLY dropped: native VR_UpdateWeaponReload replaces them (spec section B/4).
The MD3 stays untouched next to it -- modeldef points at either per the toggle.

SAFETY: reads m16.md3 read-only; writes ONLY m16.iqm (or the argv path). Never deletes.
"""

import bpy, bmesh, math, os, sys, struct
from mathutils import Vector, Matrix

# ---------------------------------------------------------------------------
# 0. ARGV: <in.md3> <out.iqm>
# ---------------------------------------------------------------------------
def _parse_argv():
    argv = sys.argv
    args = argv[argv.index("--") + 1:] if "--" in argv else []
    here = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else os.getcwd()
    in_md3  = os.path.abspath(args[0]) if len(args) >= 1 else os.path.join(here, "m16.md3")
    out_iqm = os.path.abspath(args[1]) if len(args) >= 2 else os.path.join(here, "m16.iqm")
    os.makedirs(os.path.dirname(out_iqm) or here, exist_ok=True)
    return in_md3, out_iqm

IN_MD3, OUT_IQM = _parse_argv()
IQM_ADDON_DIR = r"C:\Users\Command\Desktop\Documentation\iqm-master\blender-4.1"

def STEP(m): print("STEP: " + m, flush=True)

# ---------------------------------------------------------------------------
# 1. Pure-python MD3 reader -- FRAME 0 only (idle/ready), all surfaces
#    MD3 header:  magic4 ver4 name64 flags4 nFrames4 nTags4 nSurf4 nSkins4
#                 ofsFrames4 ofsTags4 ofsSurf4 ofsEof4
#    surface hdr: magic4 name64 flags4 nFrames4 nShaders4 nVerts4 nTris4
#                 ofsTris4 ofsShaders4 ofsST4 ofsXyz4 ofsEnd4
#    vert = int16 x,y,z (unit = 1/64) + int16 packed normal
#    ST   = float u,v
# ---------------------------------------------------------------------------
def read_md3(path):
    with open(path, "rb") as f:
        d = f.read()
    assert d[0:4] == b"IDP3", "not an MD3 (%r)" % d[0:4]
    nSurf = struct.unpack_from("<i", d, 84)[0]
    ofsSurf = struct.unpack_from("<i", d, 100)[0]
    surfaces = []
    off = ofsSurf
    for _ in range(nSurf):
        sname = d[off+4:off+68].split(b"\0")[0].decode("latin1")
        nVerts, nTris = struct.unpack_from("<2i", d, off+80)  # after nFrames,nShaders
        ofsTris, ofsShaders, ofsST, ofsXyz, ofsEnd = struct.unpack_from("<5i", d, off+88)
        # triangles (indices)
        tris = [struct.unpack_from("<3i", d, off+ofsTris+i*12) for i in range(nTris)]
        # ST (per vert, frame-independent)
        st = [struct.unpack_from("<2f", d, off+ofsST+i*8) for i in range(nVerts)]
        # xyz frame 0 (int16 * 1/64)
        verts = []
        xb = off + ofsXyz  # frame 0
        for i in range(nVerts):
            x, y, z, _n = struct.unpack_from("<4h", d, xb+i*8)
            verts.append((x/64.0, y/64.0, z/64.0))
        surfaces.append(dict(name=sname, verts=verts, st=st, tris=tris))
        off += ofsEnd
    return surfaces

STEP("reading MD3 frame 0 (idle/ready): " + IN_MD3)
SURFS = read_md3(IN_MD3)
TOTV = sum(len(s["verts"]) for s in SURFS)
print("  surfaces=%d totalVerts=%d" % (len(SURFS), TOTV))

# ---------------------------------------------------------------------------
# 2. Clean scene
# ---------------------------------------------------------------------------
STEP("clearing scene")
bpy.ops.wm.read_factory_settings(use_empty=True)

# ---------------------------------------------------------------------------
# 3. Rebuild the mesh (all surfaces merged into one object) + UVs, in bmesh.
#    Kept in the MD3's own coordinate frame (no axis swap) so the IQM ships in the
#    SAME model space the MD3 modeldef already uses -- Scale/Offset/ZOffset carry over
#    1:1 (X=barrel axis, Z=vertical, Y=lateral; verified from the mesh).
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
            continue  # dupe face across surfaces -- skip, harmless
        for loop, vidx in zip(f.loops, (a, b, c)):
            u_, v_ = s["st"][vidx]
            loop[uv].uv = (u_, 1.0 - v_)   # MD3 V is top-down; flip to Blender/GL bottom-up
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
bm.normal_update()
mesh = bpy.data.meshes.new("M16Mesh")
bm.to_mesh(mesh); bm.free()
gun = bpy.data.objects.new("M16", mesh)
bpy.context.collection.objects.link(gun)
bpy.context.view_layer.objects.active = gun
gun.select_set(True)
bpy.ops.object.shade_smooth()
print("  mesh verts=%d faces=%d" % (len(mesh.vertices), len(mesh.polygons)))

# ---------------------------------------------------------------------------
# 4. HOTSPOT positions (MODEL space, grounded in the mesh vert analysis):
#      X = barrel axis   [0.2 rear/stock .. 62.0 muzzle]
#      Z = vertical       [-12.3 mag tip .. +4.1 top], bore centerline Z~0.1
#      Y = lateral thin   [-1.5 .. 3.3], center ~0.9
#    hs_foregrip : handguard, forward of the mag toward the muzzle, on the bore line.
#    hs_magwell  : the magazine SEAT (top of the mag column), not the dangling tip.
#    hs_rack     : charging handle, rear-top of the receiver.
#    hs_carrier  : root, at the grip/origin -- ALL mesh weight rides here (non-deforming).
#    ALL values are tunable knobs; they only need to land inside the generous reload radii.
# ---------------------------------------------------------------------------
Y_CENTER = 0.9
HOTSPOTS = {
    "hs_carrier":  (0.0,  Y_CENTER,  0.0),   # origin/grip carrier (mesh weight anchor)
    "hs_foregrip": (35.0, Y_CENTER,  0.1),   # handguard on the bore line, mid-forward
    "hs_magwell":  (9.9,  Y_CENTER, -1.5),   # magazine SEAT (top of mag column)
    "hs_rack":     (20.0, Y_CENTER,  3.0),   # charging handle, rear-top of receiver
}

# ---------------------------------------------------------------------------
# 5. Armature: hs_carrier root + 3 hotspot children. Bones are 1-unit stubs along
#    +Y (their orientation is irrelevant -- only the HEAD position is read as the
#    bind-local Translate). Children parented to carrier but NOT connected (so each
#    keeps its own head position).
# ---------------------------------------------------------------------------
STEP("building 4-bone hotspot armature (hs_carrier + hs_foregrip/hs_magwell/hs_rack)")
arm_data = bpy.data.armatures.new("M16Arm")
arm_obj  = bpy.data.objects.new("M16Armature", arm_data)
bpy.context.collection.objects.link(arm_obj)
bpy.context.view_layer.objects.active = arm_obj
bpy.ops.object.mode_set(mode='EDIT')
root_eb = arm_data.edit_bones.new("hs_carrier")
rc = Vector(HOTSPOTS["hs_carrier"])
root_eb.head = rc
root_eb.tail = rc + Vector((0.0, 1.0, 0.0))
for name in ("hs_foregrip", "hs_magwell", "hs_rack"):
    eb = arm_data.edit_bones.new(name)
    h = Vector(HOTSPOTS[name])
    eb.head = h
    eb.tail = h + Vector((0.0, 1.0, 0.0))
    eb.parent = root_eb
    eb.use_connect = False
bpy.ops.object.mode_set(mode='OBJECT')

# ---------------------------------------------------------------------------
# 6. Skin: EVERY mesh vert -> hs_carrier at weight 1.0. Non-deforming: the carrier
#    bind matrix is identity-ish (a pure translation), so the mesh renders exactly as
#    the MD3 bind pose. The 3 hotspot bones stay weightless (pure data points).
# ---------------------------------------------------------------------------
STEP("skinning all verts to hs_carrier (non-deforming) + Armature modifier")
vg = gun.vertex_groups.new(name="hs_carrier")
vg.add([v.index for v in mesh.vertices], 1.0, 'REPLACE')
mod = gun.modifiers.new("Armature", 'ARMATURE')
mod.object = arm_obj
mod.use_vertex_groups = True
gun.parent = arm_obj

# ---------------------------------------------------------------------------
# 7. Material named to match the MD3 skin. exportIQM's matfun returns this name;
#    the modeldef 'Skin 0 "WPN-M16.png"' line supplies the actual texture in-engine
#    (same as the whip: the IQM stores a material NAME, gldefs/modeldef bind the PNG).
# ---------------------------------------------------------------------------
STEP("assigning material name 'ContraGun' (skin bound by modeldef Skin 0)")
mat = bpy.data.materials.new("ContraGun")
gun.data.materials.clear()
gun.data.materials.append(mat)

# ---------------------------------------------------------------------------
# 8. Export via the iqm-master exporter (same call shape as build_whip.py).
#    scale=1.0: the MD3 is ALREADY in map-unit model space; modeldef Scale 1.35 is
#    applied in-engine identically to the MD3, so we must NOT pre-scale here.
#    useskel=True bakes the 4 joints; no animspecs => single implicit bind frame.
# ---------------------------------------------------------------------------
STEP("exporting rigged IQM via iqm-master exporter (scale 1.0, bind pose only)")
if IQM_ADDON_DIR not in sys.path:
    sys.path.append(IQM_ADDON_DIR)
import iqm_export

bpy.ops.object.mode_set(mode='OBJECT')
bpy.ops.object.select_all(action='DESELECT')
gun.select_set(True)
arm_obj.select_set(True)
bpy.context.view_layer.objects.active = arm_obj   # armature ACTIVE (required by exporter)

iqm_export.exportIQM(
    bpy.context, OUT_IQM,
    usemesh=True, usemods=False, useskel=True, usebbox=False, usecol=False,
    scale=1.0, matfun=(lambda prefix, image: "ContraGun"))

def _sz(p):
    try: return os.path.getsize(p)
    except Exception: return 0
print("  iqm -> %s exists=%s size=%d" % (OUT_IQM, os.path.exists(OUT_IQM), _sz(OUT_IQM)))
print("HOTSPOTS (model space): " + ", ".join("%s=%s" % (k, v) for k, v in HOTSPOTS.items()))
print("DONE iqm=%d" % _sz(OUT_IQM), flush=True)
