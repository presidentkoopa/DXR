#!/usr/bin/env python3
# Generates GRAVCOASTER.pk3 - a DoomXR VR test course: an aerial "laser rollercoaster"
# made entirely of placed gravity-path planks, to stress-test the GravityDir + Rail Guard
# guardrails (flat -> flat turn -> climb ramp -> full vertical LOOP -> run-out).
#
# Self-contained pk3 that loads on the CURRENT engine build (no rebuild): the plank actor
# subclasses the already-baked XR_GravityPathNode and registers itself into the player's
# existing XR_GravityPath.nodes, so the REAL capture/gravity/rail code drives it.
#
# Usage:  python build_gravcoaster.py  GRAVCOASTER.pk3
#         doomxr.exe -file GRAVCOASTER.pk3 +map GRAVCOASTER
import struct, sys, math, zipfile, io

# ============================================================================
#  COURSE = a 3D "turtle" carrying an orthonormal frame (Forward=tangent, Up=normal).
#  Each step drops a plank at P facing Up, running along Forward, then advances +
#  yaws/pitches the frame. No roll (banking) in v1 -- floor/turn/ramp/wall/ceiling
#  is already the full gravity range worth testing.
# ============================================================================
def unit(v):
    l = math.sqrt(v[0]*v[0]+v[1]*v[1]+v[2]*v[2]) or 1.0
    return (v[0]/l, v[1]/l, v[2]/l)
def cross(a,b):
    return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])
def rot(v, k, deg):                       # Rodrigues: rotate v about unit axis k by deg
    k = unit(k); t = math.radians(deg); c = math.cos(t); s = math.sin(t)
    kv = cross(k, v); kd = k[0]*v[0]+k[1]*v[1]+k[2]*v[2]
    return (v[0]*c + kv[0]*s + k[0]*kd*(1-c),
            v[1]*c + kv[1]*s + k[1]*kd*(1-c),
            v[2]*c + kv[2]*s + k[2]*kd*(1-c))

planks = []   # each: dict(pos, normal, tangent, length)
def place(P, U, F, length):
    planks.append(dict(pos=P, normal=unit(U), tangent=unit(F), length=length))

SEG = 80.0        # spacing between planks
TLEN = 100.0      # plank length along tangent (>SEG so tiles overlap -> no gaps)

# start: on the pad, flat, running +Y
P = (0.0, 0.0, 64.0)
F = (0.0, 1.0, 0.0)   # forward / tangent
U = (0.0, 0.0, 1.0)   # up / surface normal (floor)

def run(steps, yaw_per, pitch_per):
    global P, F, U
    for _ in range(steps):
        place(P, U, F, TLEN)
        P = (P[0]+F[0]*SEG, P[1]+F[1]*SEG, P[2]+F[2]*SEG)
        R = unit(cross(F, U))
        if yaw_per:   F = rot(F, U, yaw_per)
        if pitch_per:
            F = rot(F, R, pitch_per)
            U = rot(U, R, pitch_per)
        F = unit(F); U = unit(U)

run(6,   0.0,   0.0)     # 1) flat lead-in
run(12,  7.5,   0.0)     # 2) flat 90-deg left turn (tests rail-guard through a curve)
run(8,   0.0,   6.0)     # 3) climb ramp (normal tilts back -> tilted gravity)
run(4,   0.0,  -6.0)     # 3b) level back out onto a short shelf before the loop
run(24,  0.0,  15.0)     # 4) FULL vertical loop 360 (up the wall, upside-down over the top)
run(8,   0.0,   0.0)     # 5) flat run-out

# ================= encode planks -> thing args =================
# normal & tangent each -> (polar from +Z, azimuth). Angle field hijacked = course order.
def to_polar_azim(v):
    v = unit(v)
    polar = math.degrees(math.acos(max(-1.0, min(1.0, v[2]))))
    azim  = math.degrees(math.atan2(v[1], v[0])) % 360.0
    return int(round(polar)), int(round(azim))

things = []
# player 1 start on the pad (slightly behind the first plank), facing +Y (north = angle 90)
things.append(dict(x=0, y=-140, z=0, angle=90, typ=1, args=(0,0,0,0,0), height=0))
for i, pk in enumerate(planks):
    npol, nazi = to_polar_azim(pk["normal"])
    tpol, tazi = to_polar_azim(pk["tangent"])
    things.append(dict(x=round(pk["pos"][0],3), y=round(pk["pos"][1],3),
                       z=round(pk["pos"][2],3), angle=i,           # angle == seq
                       typ=30500,                                   # XR_GravPlank editor num
                       args=(npol, nazi, tpol, tazi, int(pk["length"])),
                       height=round(pk["pos"][2],3)))

# ================= geometry: one big void room + a start pad =================
verts=[]; lines=[]; sides=[]; sectors=[]
def V(x,y): verts.append((float(x),float(y))); return len(verts)-1
def SEC(fh,ch,ft,ct,light): sectors.append(dict(fh=fh,ch=ch,ft=ft,ct=ct,light=light)); return len(sectors)-1
def SD(sec,mid="-",top="-",bot="-"): sides.append(dict(sec=sec,mid=mid,top=top,bot=bot)); return len(sides)-1
def LN(v1,v2,front,back=-1,block=False): lines.append(dict(v1=v1,v2=v2,front=front,back=back,block=block))
def signed_area(pts):
    a=0.0
    for i in range(len(pts)):
        x1,y1=pts[i]; x2,y2=pts[(i+1)%len(pts)]; a+=x1*y2-x2*y1
    return a*0.5
def loop(coords, want_cw):
    if (signed_area(coords)<0)!=want_cw: coords=list(reversed(coords))
    return [V(x,y) for (x,y) in coords]

# big void room: floor far below, SKY ceiling (open-air feel), tall.
VOID = SEC(0, 4096, "FLOOR0_1", "F_SKY1", 150)
mnx,mxx,mny,mxy = -2048, 2048, -1024, 3072
outer = loop([(mnx,mny),(mnx,mxy),(mxx,mxy),(mxx,mny)], want_cw=True)
for i in range(4):
    LN(outer[i], outer[(i+1)%4], SD(VOID, mid="SP_HOT1"), back=-1, block=True)

# start pad: a small raised sector so the player spawns up near the first plank.
pad = SEC(48, 4096, "FLOOR4_8", "F_SKY1", 190)
px0,px1,py0,py1 = -120,120,-220,60
q = loop([(px0,py0),(px0,py1),(px1,py1),(px1,py0)], want_cw=False)   # CCW: front=void, back=pad
for i in range(4):
    LN(q[i], q[(i+1)%4], SD(VOID, bot="METAL"), back=SD(pad), block=False)

# ================= emit UDMF TEXTMAP =================
o=['namespace = "zdoom";\n']
for (x,y) in verts: o.append("vertex{x=%.3f;y=%.3f;}\n"%(x,y))
for L in lines:
    s=["v1=%d;v2=%d;sidefront=%d;"%(L["v1"],L["v2"],L["front"])]
    if L["back"]>=0: s.append("sideback=%d;twosided=true;"%L["back"])
    if L["block"]: s.append("blocking=true;")
    o.append("linedef{%s}\n"%"".join(s))
for S in sides:
    o.append('sidedef{sector=%d;texturemiddle="%s";texturetop="%s";texturebottom="%s";}\n'%(S["sec"],S["mid"],S["top"],S["bot"]))
for S in sectors:
    o.append('sector{heightfloor=%d;heightceiling=%d;texturefloor="%s";textureceiling="%s";lightlevel=%d;}\n'%(S["fh"],S["ch"],S["ft"],S["ct"],S["light"]))
for T in things:
    a=T["args"]
    o.append(("thing{x=%.3f;y=%.3f;height=%.3f;angle=%d;type=%d;"
              "arg0=%d;arg1=%d;arg2=%d;arg3=%d;arg4=%d;"
              "skill1=true;skill2=true;skill3=true;skill4=true;skill5=true;single=true;coop=true;dm=true;}\n")
             %(T["x"],T["y"],T["height"],T["angle"],T["typ"],a[0],a[1],a[2],a[3],a[4]))
textmap="".join(o).encode("ascii")

# ================= assemble the map WAD (PWAD with one UDMF map) =================
def wad(lumps):
    data=b""; dirent=[]; off=12
    for name,b in lumps:
        dirent.append((off,len(b),name)); data+=b; off+=len(b)
    dirt=b""
    for (fp,sz,name) in dirent:
        nm=name.encode("ascii")[:8]; nm=nm+b"\x00"*(8-len(nm)); dirt+=struct.pack("<ii",fp,sz)+nm
    return b"PWAD"+struct.pack("<ii",len(lumps),12+len(data))+data+dirt
mapwad = wad([("GRAVCOASTER",b""),("TEXTMAP",textmap),("ENDMAP",b"")])

# ================= ZSCRIPT: placeable plank + linker =================
ZSCRIPT = r'''version "4.10"

// A map-placed gravity-path plank. Subclasses the baked XR_GravityPathNode (reuses its
// flat-tile render + orient math) but is spawned from the map instead of hand-painted.
// Orientation comes from thing args (normal + tangent as polar/azimuth), and the spawn
// ANGLE is hijacked to carry the course-order index so the linker can push them in order
// (Rail Guard blends nodes[idx +/- 1], so order == coaster sequence).
class XR_GravPlank : XR_GravityPathNode
{
    int seq;

    // ZScript trig is in DEGREES.
    static Vector3 SphDir(double polarDeg, double azimDeg)
    {
        return (sin(polarDeg) * cos(azimDeg), sin(polarDeg) * sin(azimDeg), cos(polarDeg));
    }

    override void PostBeginPlay()
    {
        Super.PostBeginPlay();
        seq = int(Angle + 0.5);                      // spawn angle carried the course order

        SurfaceNormal = SphDir(double(args[0]), double(args[1]));
        Vector3 tan   = SphDir(double(args[2]), double(args[3]));
        // re-orthogonalize tangent against the normal
        double d = tan.x*SurfaceNormal.x + tan.y*SurfaceNormal.y + tan.z*SurfaceNormal.z;
        tan = (tan.x - SurfaceNormal.x*d, tan.y - SurfaceNormal.y*d, tan.z - SurfaceNormal.z*d);
        double tl = tan.Length();
        Tangent = (tl > 0.0001) ? tan / tl : (1.0, 0.0, 0.0);

        TileLength   = (args[4] > 0) ? double(args[4]) : 100.0;
        TileWidth    = 46.0;
        Growing      = false;
        GrowDuration = 0;
        BaseAlpha    = 0.92;
        Alpha        = 0.92;
        msdf_enabled = 512;                          // flat rectangular TILE mode
        msdf_glitch  = 0.10;
        msdf_color   = (0.20, 0.85, 1.0);            // laser cyan
        XR_Orient();                                 // sets Angle/Pitch/Roll/Scale to render the tile
    }
}

// Once per level: wait for the player + the (auto-given) XR_GravityPath power to exist,
// then push every placed plank into that power's nodes IN COURSE ORDER. From then on the
// engine's own capture-box -> GravityDir -> Rail Guard code drives the whole coaster.
class XR_GravCoasterHandler : EventHandler
{
    bool linked;
    override void WorldTick()
    {
        if (linked) return;
        if (consoleplayer < 0) return;
        let pmo = players[consoleplayer].mo;
        if (!pmo) return;
        let path = XR_GravityPath(pmo.FindInventory("XR_GravityPath"));
        if (!path) return;

        Array<Actor> planks;
        ThinkerIterator it = ThinkerIterator.Create("XR_GravPlank");
        Actor a;
        while ((a = it.Next()) != null) planks.Push(a);
        if (planks.Size() == 0) return;              // planks not spawned yet -> wait a tic

        // insertion sort by seq (course order)
        for (int i = 1; i < planks.Size(); i++)
        {
            Actor p = planks[i]; int j = i - 1;
            while (j >= 0 && XR_GravPlank(planks[j]).seq > XR_GravPlank(p).seq)
            { planks[j+1] = planks[j]; j--; }
            planks[j+1] = p;
        }
        for (int i = 0; i < planks.Size(); i++)
            path.nodes.Push(XR_GravityPathNode(planks[i]));

        linked = true;
        Console.Printf("\cdGravCoaster: linked %d planks into the gravity path. Enable xr_gp_railguard 1.", planks.Size());
    }
}
'''

MAPINFO = r'''DoomEdNums
{
    30500 = XR_GravPlank
}

map GRAVCOASTER "XR GRAV COASTER"
{
    sky1 = "SKY1"
    music = "D_RUNNIN"
    cluster = 1
}
'''

# ================= zip into a pk3 (forward-slash paths) =================
out = sys.argv[1] if len(sys.argv) > 1 else "GRAVCOASTER.pk3"
buf = io.BytesIO()
with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr("zscript.txt", ZSCRIPT)
    z.writestr("mapinfo.txt", MAPINFO)
    z.writestr("maps/GRAVCOASTER.wad", mapwad)
open(out, "wb").write(buf.getvalue())

print("planks=%d things=%d verts=%d lines=%d pk3bytes=%d -> %s"
      % (len(planks), len(things), len(verts), len(lines), len(buf.getvalue()), out))
