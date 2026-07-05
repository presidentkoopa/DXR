"""
build_all_weapons.py -- batch driver for the DoomXR weapon MD3 -> rigged IQM pipeline.

Reads weapon_roster.json and, for every entry, runs build_weapon_iqm.py headlessly in
Blender to produce a rigged IQM (mesh + hs_* hotspot bones) ALONGSIDE the source MD3, then
validates each output with validate_iqm.py (INTERQUAKEMODEL v2, joints present, parent-
resolved bind positions match the intended hotspots). One command rebuilds the whole roster.

Per the VR_WEAPON_HANDLING_ENGINE_LEVEL.md migration doctrine this is a PK3-ONLY iteration
once the C++ foundation has landed -- no engine rebuild is needed to re-run it.

Usage:
  python build_all_weapons.py                         # build + validate the whole roster
  python build_all_weapons.py --only Pistol,Shotgun   # just these weapons
  python build_all_weapons.py --analyze-only          # geometry/hotspot report, NO Blender, NO writes
  python build_all_weapons.py --validate-only         # re-validate existing IQMs, no rebuild
  python build_all_weapons.py --blender "C:/path/blender.exe"
  python build_all_weapons.py --roster other_roster.json --keep-going

Roster entry keys (see weapon_roster.json):
  weapon, md3, out, style, material, and OPTIONAL hotspots | overrides | knobs | axis.
  Paths may be absolute or relative to the roster file's directory.

SAFETY: never modifies or deletes any MD3. Writes only the out IQMs and temp configs under
_iqm_build/_build_tmp/. Skips (with a warning) any entry whose MD3 is missing.
"""

import os, sys, json, subprocess, glob, argparse

TOOL_DIR = os.path.dirname(os.path.abspath(__file__))
BUILDER = os.path.join(TOOL_DIR, "build_weapon_iqm.py")
VALIDATOR = os.path.join(TOOL_DIR, "validate_iqm.py")
TMP_DIR = os.path.join(TOOL_DIR, "_build_tmp")


def find_blender(explicit=None):
    if explicit and os.path.exists(explicit):
        return explicit
    env = os.environ.get("BLENDER")
    if env and os.path.exists(env):
        return env
    cands = []
    for pf in (r"C:\Program Files\Blender Foundation", r"C:\Program Files (x86)\Blender Foundation"):
        cands += glob.glob(os.path.join(pf, "*", "blender.exe"))
    cands += glob.glob("/usr/bin/blender") + glob.glob("/usr/local/bin/blender")
    cands.sort(reverse=True)  # newest version first
    return cands[0] if cands else "blender"  # fall back to PATH


def resolve(path, base):
    return path if os.path.isabs(path) else os.path.normpath(os.path.join(base, path))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--roster", default=os.path.join(TOOL_DIR, "weapon_roster.json"))
    ap.add_argument("--only", default="")
    ap.add_argument("--blender", default=None)
    ap.add_argument("--analyze-only", action="store_true")
    ap.add_argument("--validate-only", action="store_true")
    ap.add_argument("--keep-going", action="store_true")
    ap.add_argument("--include-reference", action="store_true",
                    help="also (re)build entries marked \"reference\": true (e.g. the proven m16); "
                         "skipped by default so a full run never touches the shipped reference asset")
    args = ap.parse_args()

    with open(args.roster, "r") as f:
        roster = json.load(f)
    if isinstance(roster, dict) and "weapons" in roster:
        roster = roster["weapons"]
    rdir = os.path.dirname(os.path.abspath(args.roster))
    only = set(x.strip() for x in args.only.split(",") if x.strip())
    blender = find_blender(args.blender)
    os.makedirs(TMP_DIR, exist_ok=True)

    if not args.analyze_only:
        print("Blender: %s" % blender)
    print("Roster : %s  (%d entries)\n" % (args.roster, len(roster)))

    sys.path.insert(0, TOOL_DIR)
    import md3_hotspots as MH
    import validate_iqm as VI

    summary = []
    for e in roster:
        name = e.get("weapon", os.path.basename(e.get("out", "?")))
        if only and name not in only:
            continue
        if e.get("reference") and not args.include_reference and name not in only:
            print(".. %-16s SKIP (reference asset; --include-reference to build)" % name)
            summary.append((name, "SKIP", "reference"))
            continue
        md3 = resolve(e["md3"], rdir)
        out = resolve(e["out"], rdir)
        style = e.get("style", "boxmag")
        if not os.path.exists(md3):
            print("!! %-16s SKIP (MD3 missing: %s)" % (name, md3))
            summary.append((name, "SKIP", "md3 missing"))
            continue

        # ---- analyze-only: geometry/hotspot report, no Blender, no writes ----------
        if args.analyze_only:
            verts = MH._flatten_verts(MH.read_md3_frame0(md3))
            if e.get("hotspots"):
                hs = {k: tuple(v) for k, v in e["hotspots"].items()}
                geo = MH.analyze_geometry(verts, force=e.get("axis"))
                src = "config"
            else:
                hs, geo = MH.derive_hotspots(verts, style, overrides=e.get("overrides"),
                                             knobs=e.get("knobs"), axis=e.get("axis"))
                src = "derived"
            AXN = "XYZ"
            print("== %-16s style=%-9s [%s] long=%s muzzle@%s" % (
                name, style, src, AXN[geo["long_ax"]], "MAX" if geo["muzzle_at_max"] else "MIN"))
            for k in sorted(hs):
                print("     %-13s (%8.3f, %8.3f, %8.3f)" % (k, hs[k][0], hs[k][1], hs[k][2]))
            summary.append((name, "ANALYZED", src))
            continue

        # ---- build (unless validate-only) ------------------------------------------
        if not args.validate_only:
            cfg = dict(md3=md3, out=out, style=style, material=e.get("material", name))
            for k in ("hotspots", "overrides", "knobs", "axis", "ready_frame"):
                if e.get(k) is not None:
                    cfg[k] = e[k]
            cfg_path = os.path.join(TMP_DIR, "cfg_%s.json" % name)
            with open(cfg_path, "w") as f:
                json.dump(cfg, f, indent=2)
            print(">> building %-16s -> %s" % (name, out))
            r = subprocess.run([blender, "--background", "--python", BUILDER, "--", cfg_path],
                               capture_output=True, text=True)
            if ("RESULT_JSON:" not in r.stdout) or (not os.path.exists(out)):
                print("   BUILD FAILED for %s" % name)
                print("   " + "\n   ".join((r.stdout + r.stderr).splitlines()[-12:]))
                summary.append((name, "BUILD-FAIL", ""))
                if not args.keep_going:
                    break
                continue
            # Capture the builder's ACTUAL emitted hotspots (post ready-frame shift) so validation
            # is a true round-trip check (does the IQM bake the bones where the builder placed them?)
            # rather than comparing against the roster's pre-shift frame-0 authored coords.
            try:
                rj = [ln for ln in r.stdout.splitlines() if ln.startswith("RESULT_JSON:")][-1]
                e["_built_hotspots"] = json.loads(rj[len("RESULT_JSON:"):]).get("hotspots")
            except Exception:
                e["_built_hotspots"] = None

        # ---- validate --------------------------------------------------------------
        # Prefer the builder's actual output hotspots (round-trip integrity); fall back to the
        # roster's authored coords for a validate-only run where no build just happened.
        expect = None
        if e.get("_built_hotspots"):
            expect = {k: [float(c) for c in v] for k, v in e["_built_hotspots"].items()}
        elif e.get("hotspots") and not e.get("ready_frame"):
            expect = {k: [float(c) for c in v] for k, v in e["hotspots"].items()}
        v = VI.validate(out, expect=expect)
        tag = "PASS" if v["ok"] else "FAIL"
        print("   %-4s %-16s joints=%d verts=%d tris=%d maxBindErr=%s" % (
            tag, name, v.get("num_joints", 0), v.get("num_vertexes", 0),
            v.get("num_triangles", 0), v.get("max_bind_error")))
        for iss in v.get("issues", []):
            print("        !! " + iss)
        summary.append((name, tag, "joints=%d" % v.get("num_joints", 0)))

    print("\n===== SUMMARY =====")
    for name, tag, extra in summary:
        print("  %-6s %-16s %s" % (tag, name, extra))
    n_pass = sum(1 for _, t, _ in summary if t == "PASS")
    n_fail = sum(1 for _, t, _ in summary if t in ("FAIL", "BUILD-FAIL"))
    print("  ---- %d PASS, %d FAIL/BUILD-FAIL, %d total ----" % (n_pass, n_fail, len(summary)))
    sys.exit(1 if n_fail else 0)


if __name__ == "__main__":
    main()
