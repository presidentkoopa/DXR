"""
validate_iqm.py -- STDLIB-ONLY validator for the rigged weapon IQMs.

Parses an IQM the way GZDoom's IQMModel loader does (header + text + joints) and confirms:
  * magic == "INTERQUAKEMODEL\0" and version == 2
  * mesh/vertex/triangle counts are non-zero (the gun geometry survived)
  * the expected hotspot joints are present by NAME
  * each joint's PARENT-RESOLVED bind position (walk translate/rotate/scale down the parent
    chain -- exactly IQMModel's baseframe) lands where the builder placed the hotspot.

The parent-resolved position is the value GetBoneBindPos() returns natively, so validating it
here proves the reload FSM / two-hand subsystem will read the right world points.

Run:
  python validate_iqm.py <a.iqm> [b.iqm ...]                 # structural report
  python validate_iqm.py --expect <config.json> <a.iqm>      # + diff bind pos vs config hotspots
  python validate_iqm.py --json <a.iqm>                      # machine-readable RESULT_JSON line

SAFETY: read-only.
"""

import struct, sys, os, json, math

MAGIC = b"INTERQUAKEMODEL\0"


def _mat_ident():
    return [1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0]


def _mat_mul(a, b):
    r = [0.0] * 16
    for i in range(4):
        for j in range(4):
            r[i * 4 + j] = sum(a[i * 4 + k] * b[k * 4 + j] for k in range(4))
    return r


def _trs_matrix(t, q, s):
    """4x4 column-applied matrix = Translate(t) * Rotate(quat x,y,z,w) * Scale(s)."""
    x, y, z, w = q
    n = math.sqrt(x * x + y * y + z * z + w * w) or 1.0
    x, y, z, w = x / n, y / n, z / n, w / n
    # rotation 3x3
    r00 = 1 - 2 * (y * y + z * z); r01 = 2 * (x * y - w * z);     r02 = 2 * (x * z + w * y)
    r10 = 2 * (x * y + w * z);     r11 = 1 - 2 * (x * x + z * z); r12 = 2 * (y * z - w * x)
    r20 = 2 * (x * z - w * y);     r21 = 2 * (y * z + w * x);     r22 = 1 - 2 * (x * x + y * y)
    sx, sy, sz = s
    return [
        r00 * sx, r01 * sy, r02 * sz, t[0],
        r10 * sx, r11 * sy, r12 * sz, t[1],
        r20 * sx, r21 * sy, r22 * sz, t[2],
        0, 0, 0, 1,
    ]


def parse_iqm(path):
    with open(path, "rb") as f:
        d = f.read()
    if d[0:16] != MAGIC:
        raise ValueError("bad magic %r (not INTERQUAKEMODEL)" % d[0:16])
    # header: 27 uint32 after the 16-byte magic
    hv = struct.unpack_from("<27I", d, 16)
    (version, filesize, flags,
     num_text, ofs_text,
     num_meshes, ofs_meshes,
     num_vertexarrays, num_vertexes, ofs_vertexarrays,
     num_triangles, ofs_triangles, ofs_adjacency,
     num_joints, ofs_joints,
     num_poses, ofs_poses,
     num_anims, ofs_anims,
     num_frames, num_framechannels, ofs_frames, ofs_bounds,
     num_comment, ofs_comment,
     num_extensions, ofs_extensions) = hv

    text = d[ofs_text:ofs_text + num_text] if num_text else b""

    def s_at(off):
        e = text.find(b"\0", off)
        return text[off:e].decode("latin1") if e >= 0 else text[off:].decode("latin1")

    joints = []
    for i in range(num_joints):
        base = ofs_joints + i * 48  # iqmjoint v2 = name(u) parent(i) translate3 rotate4 scale3
        name_off = struct.unpack_from("<I", d, base)[0]
        parent = struct.unpack_from("<i", d, base + 4)[0]
        tx, ty, tz = struct.unpack_from("<3f", d, base + 8)
        rx, ry, rz, rw = struct.unpack_from("<4f", d, base + 20)
        sx, sy, sz = struct.unpack_from("<3f", d, base + 36)
        joints.append(dict(index=i, name=s_at(name_off), parent=parent,
                           translate=(tx, ty, tz), rotate=(rx, ry, rz, rw), scale=(sx, sy, sz)))

    # parent-resolved (world) bind matrices -> head position, exactly like baseframe[]
    world = [None] * num_joints
    for j in joints:
        local = _trs_matrix(j["translate"], j["rotate"], j["scale"])
        if j["parent"] >= 0 and world[j["parent"]] is not None:
            m = _mat_mul(world[j["parent"]], local)
        else:
            m = local
        world[j["index"]] = m
        j["world_pos"] = (m[3], m[7], m[11])

    return dict(
        version=version, filesize=filesize,
        num_meshes=num_meshes, num_vertexes=num_vertexes, num_triangles=num_triangles,
        num_joints=num_joints, num_anims=num_anims, num_frames=num_frames,
        joints=joints,
    )


def validate(path, expect=None):
    issues = []
    info = parse_iqm(path)
    if info["version"] != 2:
        issues.append("version %d != 2" % info["version"])
    if info["num_vertexes"] <= 0 or info["num_triangles"] <= 0:
        issues.append("empty geometry (verts=%d tris=%d)" % (info["num_vertexes"], info["num_triangles"]))
    if info["num_meshes"] <= 0:
        issues.append("no meshes")
    names = [j["name"] for j in info["joints"]]
    if "hs_grip" not in names:
        issues.append("missing hs_grip joint")

    bind = {j["name"]: j["world_pos"] for j in info["joints"]}
    max_err = 0.0
    if expect:
        for name, xyz in expect.items():
            if name not in bind:
                issues.append("expected joint '%s' absent" % name)
                continue
            wp = bind[name]
            err = math.sqrt(sum((wp[k] - xyz[k]) ** 2 for k in range(3)))
            max_err = max(max_err, err)
            if err > 0.5:  # >0.5 map units off = a real placement bug (export rounding is <<0.01)
                issues.append("joint '%s' bind %s != expected %s (err=%.3f)" % (
                    name, tuple(round(c, 3) for c in wp), tuple(round(c, 3) for c in xyz), err))

    return dict(
        out=os.path.abspath(path), ok=(len(issues) == 0),
        version=info["version"], num_meshes=info["num_meshes"],
        num_vertexes=info["num_vertexes"], num_triangles=info["num_triangles"],
        num_joints=info["num_joints"], joint_names=names,
        bind_positions={n: [round(c, 4) for c in p] for n, p in bind.items()},
        max_bind_error=round(max_err, 4), issues=issues,
    )


if __name__ == "__main__":
    args = sys.argv[1:]
    as_json = False
    expect = None
    paths = []
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--json":
            as_json = True
        elif a == "--expect":
            i += 1
            with open(args[i], "r") as f:
                cfg = json.load(f)
            expect = {k: [float(c) for c in v] for k, v in cfg.get("hotspots", cfg).items()}
        else:
            paths.append(a)
        i += 1

    for p in paths:
        try:
            r = validate(p, expect=expect)
        except Exception as e:
            r = dict(out=os.path.abspath(p), ok=False, issues=["parse error: %s" % e])
        if as_json:
            print("RESULT_JSON: " + json.dumps(r), flush=True)
        else:
            print("=" * 78)
            print("%s  ->  %s" % (os.path.basename(p), "OK" if r["ok"] else "FAIL"))
            if "num_joints" in r:
                print("   v%d  meshes=%d verts=%d tris=%d joints=%d  maxBindErr=%s" % (
                    r["version"], r["num_meshes"], r["num_vertexes"], r["num_triangles"],
                    r["num_joints"], r.get("max_bind_error")))
                for j in r["joint_names"]:
                    print("     joint %-13s bind=%s" % (j, r["bind_positions"][j]))
            for iss in r["issues"]:
                print("   !! " + iss)
