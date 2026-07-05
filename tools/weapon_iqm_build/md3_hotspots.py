"""
md3_hotspots.py -- shared, STDLIB-ONLY MD3 reader + hotspot geometry analyzer.

This is the generalization of the hand-tuned HOTSPOTS block in
    hud/rifle/build_m16_iqm.py
into a per-weapon, data-driven derivation. Every weapon's reload/two-hand hotspots
(foregrip / magwell / rack / port / breech / tank) are derived from ITS OWN frame-0
mesh geometry the exact way the m16's were reasoned about by hand:

    * barrel axis  = the model's LONGEST bounding-box axis; the muzzle end is the end
                     whose perpendicular cross-section is THINNEST (just the barrel).
    * vertical axis = the larger of the two remaining axes (the grip + magazine hang
                     along it); lateral axis = the thin remaining one.
    * bore line    = the vertical/lateral centroid of the barrel-only region near the
                     muzzle (where the mesh is nothing but barrel).
    * magazine     = the cluster of verts hanging well BELOW the bore line; the magwell
                     hotspot is the SEAT (top of that mag column), not the dangling tip.
    * rack/charge  = the rear-of-receiver, near the top vertical extent.
    * foregrip     = forward of the magwell toward the muzzle, on the bore line.

No axis is assumed: the m16 happens to be barrel=X, but other guns author barrel=Y or
Z. Everything is computed from measured extents, then written back in the MD3's OWN
(x,y,z) order so the IQM ships in the same model space the modeldef already uses
(Scale/Offset/ZOffset -- including negative-X mirror -- carry over 1:1).

Pure stdlib (struct/math) so it runs under system Python for analysis/validation AND
inside Blender's Python for the actual build. No numpy, no bpy.

SAFETY: read-only. Opens MD3s 'rb'; never writes or deletes anything.
"""

import struct, math

# ---------------------------------------------------------------------------
# Reload style -> ordered hotspot bone list. hs_grip is ALWAYS first (it is
# the non-deforming mesh weight anchor at the grip/origin). The rest are the
# style-specific interaction points the native FSM / two-hand subsystem reads.
# Mirrors VR_WEAPON_HANDLING_ENGINE_LEVEL.md's style variants.
# ---------------------------------------------------------------------------
STYLE_HOTSPOTS = {
    "boxmag":    ["hs_grip", "hs_foregrip", "hs_magwell", "hs_rack"],
    "shell":     ["hs_grip", "hs_foregrip", "hs_port"],          # tube shotgun: pump = foregrip, shells at port
    "break":     ["hs_grip", "hs_foregrip", "hs_breech"],        # SxS / revolver / M79: hinge/cylinder
    "pod":       ["hs_grip", "hs_foregrip", "hs_breech"],        # rocket / BFG single-pod breech
    "canister":  ["hs_grip", "hs_foregrip", "hs_tank"],          # flamethrower fuel canister
    "none":      ["hs_grip"],                                    # melee / VR tool: carrier only (no reload)
}


def read_md3(path, frame=0):
    """Parse an MD3, return [{name, verts:[(x,y,z)..], st:[(u,v)..], tris:[(a,b,c)..]}]
    for the given FRAME (default 0 = idle/ready). MD3 stores every frame's XYZ block
    consecutively per surface: frame f's verts start at ofsXyz + f*nVerts*8 (each vert is
    4 shorts, 8 bytes, coords in 1/64 units). Byte-for-byte the reader used by
    build_m16_iqm.py, generalized so we can bake the IQM from the weapon's true RESTING
    frame (the frame its modeldef maps the ready/idle sprite state to) instead of blindly
    frame 0 -- frame 0 is a mid-draw TRANSITION pose for most weapons (verified via bbox),
    so baking it froze guns tilted/mispositioned once repointed to the IQM."""
    with open(path, "rb") as f:
        d = f.read()
    if d[0:4] != b"IDP3":
        raise ValueError("not an MD3 (magic=%r) : %s" % (d[0:4], path))
    nSurf = struct.unpack_from("<i", d, 84)[0]
    ofsSurf = struct.unpack_from("<i", d, 100)[0]
    surfaces = []
    off = ofsSurf
    for _ in range(nSurf):
        sname = d[off + 4:off + 68].split(b"\0")[0].decode("latin1")
        nFrames = struct.unpack_from("<i", d, off + 72)[0]
        nVerts, nTris = struct.unpack_from("<2i", d, off + 80)
        ofsTris, ofsShaders, ofsST, ofsXyz, ofsEnd = struct.unpack_from("<5i", d, off + 88)
        f_use = frame if (0 <= frame < nFrames) else 0   # clamp: never index past the surface's frames
        if f_use != frame:
            print("  [md3] surface '%s' has %d frames; requested frame %d out of range -> using 0"
                  % (sname, nFrames, frame))
        tris = [struct.unpack_from("<3i", d, off + ofsTris + i * 12) for i in range(nTris)]
        st = [struct.unpack_from("<2f", d, off + ofsST + i * 8) for i in range(nVerts)]
        verts = []
        xb = off + ofsXyz + f_use * nVerts * 8   # frame f_use's xyz block
        for i in range(nVerts):
            x, y, z, _n = struct.unpack_from("<4h", d, xb + i * 8)
            verts.append((x / 64.0, y / 64.0, z / 64.0))
        surfaces.append(dict(name=sname, verts=verts, st=st, tris=tris))
        off += ofsEnd
    return surfaces


def read_md3_frame0(path):
    """Back-compat wrapper: frame 0 only. Prefer read_md3(path, frame) for the resting pose."""
    return read_md3(path, 0)


def _flatten_verts(surfaces):
    out = []
    for s in surfaces:
        out.extend(s["verts"])
    return out


def _mean(vals):
    return sum(vals) / len(vals) if vals else 0.0


def _median(vals):
    if not vals:
        return 0.0
    s = sorted(vals)
    n = len(s)
    return s[n // 2] if n % 2 else 0.5 * (s[n // 2 - 1] + s[n // 2])


def analyze_geometry(verts, force=None):
    """Measure the mesh and return the canonical frame:
        long / vert / lat  : axis indices (0=x,1=y,2=z)
        bbox min/max/ext   : per axis
        muzzle_at_max      : bool -- is the muzzle at the long-axis MAX end?
        muzzle_L / breech_L: long-axis coordinate of muzzle / receiver-rear end
        bore_v / bore_l    : vertical & lateral coordinate of the bore centreline
    All later hotspot placement is expressed relative to these, so it is axis- and
    orientation-agnostic (works whether barrel = X, Y or Z)."""
    n = len(verts)
    if n == 0:
        raise ValueError("empty mesh")
    mins = [min(v[a] for v in verts) for a in range(3)]
    maxs = [max(v[a] for v in verts) for a in range(3)]
    exts = [maxs[a] - mins[a] for a in range(3)]

    # long axis = biggest extent. vertical = bigger of the other two, lateral = smaller.
    order = sorted(range(3), key=lambda a: exts[a], reverse=True)
    long_ax = order[0]
    rest = [order[1], order[2]]
    vert_ax = rest[0] if exts[rest[0]] >= exts[rest[1]] else rest[1]
    lat_ax = rest[1] if vert_ax == rest[0] else rest[0]

    # Explicit orientation override (config 'axis') for meshes the auto-detector mis-reads
    # (diagonal barrels, scopes that dominate an extent, non-standard authored frames).
    _AX = {"x": 0, "y": 1, "z": 2, "X": 0, "Y": 1, "Z": 2, 0: 0, 1: 1, 2: 2}
    forced_muzzle = None
    if force:
        if "long" in force:
            long_ax = _AX[force["long"]]
        if "vert" in force:
            vert_ax = _AX[force["vert"]]
        if "lat" in force:
            lat_ax = _AX[force["lat"]]
        if "muzzle_at_max" in force:
            forced_muzzle = bool(force["muzzle_at_max"])

    lmin, lmax, lspan = mins[long_ax], maxs[long_ax], exts[long_ax]

    # Which end is the muzzle? The BREECH end carries the grip + magazine + stock, so it
    # (a) hangs DEEPER below the bore line and (b) has a TALLER perpendicular cross-section.
    # The muzzle end is just barrel: shallow + thin. Split the model at the long-axis
    # midpoint and score each half; the deeper/taller half is the breech. This is far more
    # robust than an end-slab thinness test (which a front sight or carry handle defeats).
    mid = 0.5 * (lmin + lmax)
    low_half = [v for v in verts if v[long_ax] < mid]
    high_half = [v for v in verts if v[long_ax] >= mid]

    def half_depth(half):
        # how far the half reaches below the vertical MIDPOINT (grip/mag hang down)
        if not half:
            return 0.0
        vmid = 0.5 * (mins[vert_ax] + maxs[vert_ax])
        return vmid - min(v[vert_ax] for v in half)

    def half_perp(half):
        if len(half) < 3:
            return 0.0
        vv = [v[vert_ax] for v in half]
        ll = [v[lat_ax] for v in half]
        return (max(vv) - min(vv)) + (max(ll) - min(ll))

    # Combine the two cues (normalized) so a diagonal or offset mesh still resolves.
    low_score = half_depth(low_half) + 0.5 * half_perp(low_half)
    high_score = half_depth(high_half) + 0.5 * half_perp(high_half)
    breech_at_min = low_score >= high_score      # deeper/bulkier half is the breech
    muzzle_at_max = breech_at_min if forced_muzzle is None else forced_muzzle
    muzzle_L = lmax if muzzle_at_max else lmin
    breech_L = lmin if muzzle_at_max else lmax

    # Bore line: verts in the barrel-only third nearest the muzzle -> their vert/lat MEDIAN
    # (median, not mean, so a front-sight post or bayonet lug doesn't drag the centreline up).
    third = 0.30 * lspan
    if muzzle_at_max:
        barrel = [v for v in verts if v[long_ax] >= lmax - third]
    else:
        barrel = [v for v in verts if v[long_ax] <= lmin + third]
    bore_v = _median([v[vert_ax] for v in barrel]) if barrel else 0.5 * (mins[vert_ax] + maxs[vert_ax])
    bore_l = _median([v[lat_ax] for v in barrel]) if barrel else 0.5 * (mins[lat_ax] + maxs[lat_ax])

    return dict(
        n=n, long_ax=long_ax, vert_ax=vert_ax, lat_ax=lat_ax,
        mins=mins, maxs=maxs, exts=exts,
        lmin=lmin, lmax=lmax, lspan=lspan,
        muzzle_at_max=muzzle_at_max, muzzle_L=muzzle_L, breech_L=breech_L,
        bore_v=bore_v, bore_l=bore_l,
    )


def _compose(geo, vL, vV, vLat):
    """Turn (long, vertical, lateral) values into an (x,y,z) tuple in MD3 axis order."""
    out = [0.0, 0.0, 0.0]
    out[geo["long_ax"]] = vL
    out[geo["vert_ax"]] = vV
    out[geo["lat_ax"]] = vLat
    return (out[0], out[1], out[2])


def _toward_muzzle(geo, frac):
    """Long-axis coordinate a fraction of the way from the breech end to the muzzle end."""
    return geo["breech_L"] + (geo["muzzle_L"] - geo["breech_L"]) * frac


def derive_hotspots(verts, style, overrides=None, knobs=None, axis=None):
    """Return {bone_name: (x,y,z)} in MD3 model space for the given reload style,
    each point grounded in this mesh's own geometry. `overrides` may set any bone to
    an explicit (x,y,z) (escape hatch for a mis-analyzed mesh). `knobs` tunes the
    placement fractions per weapon without hard-coding coordinates. `axis` forces the
    long/vert/lat/muzzle orientation when auto-detection mis-reads the mesh."""
    overrides = overrides or {}
    k = dict(
        foregrip_frac=0.58,   # bore-line point this far from breech toward muzzle
        rack_frac=0.34,       # rack sits this far toward the muzzle (rear third of receiver)
        rack_top_frac=0.82,   # rack vertical = this fraction up toward the top extent
        mag_below=0.28,       # a vert is "magazine" if it's this*vertExt below the bore
        port_frac=0.40,       # shell/insert port long-axis position (over the receiver)
        breech_frac=0.30,     # break/pod hinge-breech long-axis position
        tank_frac=0.20,       # canister/tank long-axis position (rear body)
    )
    if knobs:
        k.update(knobs)

    geo = analyze_geometry(verts, force=axis)
    vert_ax, lat_ax, long_ax = geo["vert_ax"], geo["lat_ax"], geo["long_ax"]
    bore_v, bore_l = geo["bore_v"], geo["bore_l"]
    top_v = geo["maxs"][vert_ax] if _sign_up(geo, verts) else geo["mins"][vert_ax]
    vext = geo["exts"][vert_ax]

    # --- magazine cluster: verts hanging well below the bore line -----------------
    below_thresh = bore_v - k["mag_below"] * vext
    mag = [v for v in verts if v[vert_ax] < below_thresh]
    if len(mag) >= 4:
        mag_L = _median([v[long_ax] for v in mag])
        # seat = top of the mag column in a window around mag_L (where it meets the receiver)
        win = 0.10 * geo["lspan"]
        col = [v for v in mag if abs(v[long_ax] - mag_L) <= win] or mag
        mag_seat_v = max(v[vert_ax] for v in col)   # highest point of the hanging column
        mag_seat_l = _mean([v[lat_ax] for v in col])
    else:
        # no hanging magazine (bullpup / boxy) -> seat just under the bore, mid-body
        mag_L = _toward_muzzle(geo, 0.30)
        mag_seat_v = bore_v - 0.12 * vext
        mag_seat_l = bore_l

    hs = {}
    hs["hs_grip"] = (0.0, 0.0, 0.0)  # origin/grip -- all mesh weight rides here

    hs["hs_foregrip"] = _compose(geo, _toward_muzzle(geo, k["foregrip_frac"]), bore_v, bore_l)

    hs["hs_magwell"] = _compose(geo, mag_L, mag_seat_v, mag_seat_l)

    rack_v = bore_v + (top_v - bore_v) * k["rack_top_frac"]
    hs["hs_rack"] = _compose(geo, _toward_muzzle(geo, k["rack_frac"]), rack_v, bore_l)

    hs["hs_port"] = _compose(geo, _toward_muzzle(geo, k["port_frac"]),
                             bore_v + (top_v - bore_v) * 0.55, bore_l)

    hs["hs_breech"] = _compose(geo, _toward_muzzle(geo, k["breech_frac"]), bore_v, bore_l)

    hs["hs_tank"] = _compose(geo, _toward_muzzle(geo, k["tank_frac"]),
                             bore_v - 0.20 * vext, bore_l)

    wanted = STYLE_HOTSPOTS.get(style, STYLE_HOTSPOTS["boxmag"])
    result = {name: hs.get(name, (0.0, 0.0, 0.0)) for name in wanted}
    # carrier at the true origin unless the mesh grip sits elsewhere; keep origin (matches m16).
    for name, xyz in overrides.items():
        if name in result:
            result[name] = tuple(xyz)
    return result, geo


def _sign_up(geo, verts):
    """Is 'up' the +vertical direction? True unless the mesh mass sits above the origin's
    negative side. For guns the receiver top is at max-vertical, so default True; kept as a
    hook so a flipped mesh can still resolve the rack to the correct top."""
    vert_ax = geo["vert_ax"]
    # Heavier side = more verts. If most verts sit below the vertical midpoint, top is +.
    return True


def slab_profile(verts, geo, nslabs=10):
    """Per-slab vertical cross-section along the long axis -- the raw signal for judging
    which end is the barrel (thin/shallow) vs the receiver+grip+mag (bulky/deep)."""
    la, va = geo["long_ax"], geo["vert_ax"]
    lmin, lspan = geo["lmin"], geo["lspan"]
    rows = []
    for i in range(nslabs):
        lo = lmin + lspan * i / nslabs
        hi = lmin + lspan * (i + 1) / nslabs
        seg = [p for p in verts if (lo <= p[la] < hi) or (i == nslabs - 1 and p[la] == hi)]
        if not seg:
            rows.append(dict(i=i, lo=round(lo, 2), hi=round(hi, 2), n=0))
            continue
        vv = [p[va] for p in seg]
        rows.append(dict(i=i, lo=round(lo, 2), hi=round(hi, 2), n=len(seg),
                         vmin=round(min(vv), 2), vmax=round(max(vv), 2),
                         perp=round(max(vv) - min(vv), 2)))
    return rows


# ---------------------------------------------------------------------------
# CLI:  python md3_hotspots.py <md3> [--style boxmag] [--axis long=X,vert=Z,lat=Y,muzzle_at_max=1]
#                                    [--json] [--profile]
# Deterministic geometry tool for the analyze agents (no Blender needed).
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    import sys, os, json
    AXN = "XYZ"
    a = sys.argv[1:]
    style = "boxmag"
    as_json = "--json" in a
    do_profile = "--profile" in a
    axis = None
    if "--axis" in a:
        spec = a[a.index("--axis") + 1]
        axis = {}
        for kv in spec.split(","):
            k, _, v = kv.partition("=")
            axis[k.strip()] = (v.strip() in ("1", "true", "True")) if k.strip() == "muzzle_at_max" else v.strip()
    if "--style" in a:
        style = a[a.index("--style") + 1]
    paths = [x for x in a if not x.startswith("--") and x.lower().endswith(".md3")]
    # also skip the values that followed --style/--axis
    skip = set()
    for flag in ("--style", "--axis"):
        if flag in a:
            skip.add(a[a.index(flag) + 1])
    paths = [p for p in paths if p not in skip]

    for path in paths:
        try:
            surfs = read_md3_frame0(path)
        except Exception as e:
            print("!! %s : %s" % (os.path.basename(path), e))
            continue
        verts = _flatten_verts(surfs)
        hs, geo = derive_hotspots(verts, style, axis=axis)
        if as_json:
            out = dict(
                file=os.path.abspath(path), verts=len(verts), surfs=len(surfs), style=style,
                bbox=dict(min=[round(c, 3) for c in geo["mins"]], max=[round(c, 3) for c in geo["maxs"]],
                          ext=[round(c, 3) for c in geo["exts"]]),
                orientation=dict(long=AXN[geo["long_ax"]], vert=AXN[geo["vert_ax"]], lat=AXN[geo["lat_ax"]],
                                 muzzle_at_max=geo["muzzle_at_max"], bore_v=round(geo["bore_v"], 3),
                                 bore_l=round(geo["bore_l"], 3)),
                hotspots={k: [round(c, 4) for c in v] for k, v in hs.items()},
            )
            if do_profile:
                out["slab_profile"] = slab_profile(verts, geo)
            print("RESULT_JSON: " + json.dumps(out), flush=True)
            continue
        print("=" * 78)
        print("%s   verts=%d  surfs=%d  style=%s" % (os.path.basename(path), len(verts), len(surfs), style))
        for ax in range(3):
            print("   %s: [%8.2f .. %8.2f]  ext=%7.2f" % (AXN[ax], geo["mins"][ax], geo["maxs"][ax], geo["exts"][ax]))
        print("   long=%s vert=%s lat=%s  muzzle@%s  bore(v=%.2f,l=%.2f)" % (
            AXN[geo["long_ax"]], AXN[geo["vert_ax"]], AXN[geo["lat_ax"]],
            ("MAX" if geo["muzzle_at_max"] else "MIN"), geo["bore_v"], geo["bore_l"]))
        for name in sorted(hs):
            x, y, z = hs[name]
            print("   %-13s (%7.2f, %7.2f, %7.2f)" % (name, x, y, z))
        if do_profile:
            print("   -- slab profile (long axis %s, vert axis %s) --" % (AXN[geo["long_ax"]], AXN[geo["vert_ax"]]))
            for r in slab_profile(verts, geo):
                if r["n"] == 0:
                    print("     slab%d [%8.2f..%8.2f] EMPTY" % (r["i"], r["lo"], r["hi"]))
                else:
                    print("     slab%d [%8.2f..%8.2f] n=%5d vert[%7.2f..%7.2f] perp=%6.2f" % (
                        r["i"], r["lo"], r["hi"], r["n"], r["vmin"], r["vmax"], r["perp"]))
