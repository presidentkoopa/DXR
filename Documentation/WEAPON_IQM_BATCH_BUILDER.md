# Weapon MD3 → rigged-IQM batch builder — write-up

**What it is.** A reusable, roster-driven Python toolchain that converts DoomXR weapon body models
from `.md3` to bind-pose `.iqm` carrying the `hs_*` **hotspot bones** the native VR reload FSM +
articulated two-hand subsystem read (`hs_carrier / hs_foregrip / hs_magwell / hs_rack / hs_port /
hs_breech / hs_tank`). It generalizes the one-off `wadsrc/static/models/weapons/hud/rifle/build_m16_iqm.py`
so the whole weapon roster can be rigged with one command instead of hand-authoring each gun.

**Where it lives.** `tools/weapon_iqm_build/` (alongside `tools/sdf_authoring/`, `tools/testmaps/`).
Dev/authoring tool — **not** shipped in the pk3; the outputs (`.iqm`) sit next to their `.md3`
under `wadsrc/static/models/weapons/`.

```
tools/weapon_iqm_build/
  md3_hotspots.py       stdlib MD3 reader + geometry analyzer + hotspot derivation + CLI
  build_weapon_iqm.py   headless-Blender builder (one weapon, JSON-config driven)
  validate_iqm.py       stdlib IQM v2 validator (parent-resolved bind-pos check)
  build_all_weapons.py  batch driver: reads the roster, builds + validates the lot
  weapon_roster.json    per-weapon config (paths, style, material, baked hotspots, axis, confidence)
  README.md             usage reference
```

## How hotspots are derived from geometry

Each weapon's hotspots come from **its own frame-0 mesh**, no per-weapon assumption:
- **long axis** = biggest bbox extent (the barrel/length); **vertical** = larger of the other two
  (grip + magazine hang along it); **lateral** = the thin one.
- **muzzle end** = the shallow/thin end; the **breech/grip** end is the half that hangs deepest
  below the bore and has the tallest cross-section. Robust to front sights / carry handles.
- **bore line** = median vertical/lateral of the barrel-only third nearest the muzzle.

Points are written back in the MD3's own (x,y,z) order, so modeldef `Scale`/`Offset`/`ZOffset`
(incl. a negative-X mirror) carry over 1:1. Hotspots only need to land inside the engine's generous
reload radii, and every one is a one-line tunable knob in the roster.

For meshes the auto-detector mis-reads (a scope dominating an extent, a diagonally-authored barrel),
the roster entry supplies an `axis` hint or explicit `hotspots`.

## Results (2026-07-04)

Built + validated via a 36-agent analyze→build→validate swarm; **11 weapon bodies converted,
all PASS** `INTERQUAKEMODEL v2`, joints present, parent-resolved bind error **0.0**:

| Weapon | Style | Joints | Confidence |
|---|---|---|---|
| Pistol, SMG, Chaingun, PlasmaRifle | boxmag | 4 | high |
| Shotgun | shell | 3 | high |
| SuperShotgun, Revolver, M79 | break | 3 | high |
| RocketLauncher, BFG9000 | pod | 3 | **medium — diagonal mesh, eyeball in headset** |
| Flamethrower | canister | 3 | high |
| Rifle (m16) | reference | 4 | reproduced to scratch; shipped `m16.iqm` untouched |

6/12 needed an axis override (PlasmaRifle long=Z→X via named surfaces; Revolver caught 6 degenerate
surfaces on a Colt Python mesh; SMG/Shotgun muzzle flipped to X-MIN). **BFG9000 + RocketLauncher**
are the two to sanity-check in headset — both authored diagonally, so their cardinal-axis hotspots
are approximations (safe defaults, tunable).

## Run it

```sh
python tools/weapon_iqm_build/build_all_weapons.py                 # build + validate the whole roster
python tools/weapon_iqm_build/build_all_weapons.py --analyze-only  # geometry report, no Blender, no writes
python tools/weapon_iqm_build/build_all_weapons.py --only BFG9000  # one weapon
python tools/weapon_iqm_build/build_all_weapons.py --validate-only # re-validate existing IQMs
```

Blender 4.4 auto-located under `C:\Program Files\Blender Foundation\*\` (`--blender <path>` to override).
IQM exporter = iqm-master addon (path pinned in `build_weapon_iqm.py`).

## Safety / status

- **Nothing destructive.** Every `.md3` is untouched; `.iqm` files are written *alongside* them.
  The shipped, in-headset-proven `hud/rifle/m16.iqm` is left as-is (roster marks it `reference:true`,
  skipped by default).
- **Modeldefs are NOT repointed** by this tool. The IQMs just exist, staged for the per-weapon
  rollout: `Model 0 "<body>.md3" → "<body>.iqm"` + `modelsareattachments`, gated on
  `vr_new_weapon_handling`, one weapon at a time after in-headset proof (as the m16 was).
- Repointing trades the MD3's baked recoil/fire frames (IQM is bind-pose only) for precise authored
  `hs_foregrip` (the articulated two-hand needs it) — a deliberate per-weapon decision, not automatic.
- **Not yet in-headset tested.** Related: `VR_WEAPON_HANDLING_ENGINE_LEVEL.md`.

Sibling model-build scripts (same export contract): `wadsrc/.../hud/rifle/build_m16_iqm.py` (the
ancestor), `wadsrc/.../xrwhip/build_whip.py`.
