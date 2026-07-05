# DoomXR weapon MD3 → rigged-IQM + hotspot batch builder

Generalizes the one-off `hud/rifle/build_m16_iqm.py` into a **reusable, roster-driven** pipeline
that converts every VR weapon body from MD3 to a bind-pose IQM carrying the `hs_*` hotspot bones
that the native reload FSM + articulated two-hand subsystem read
(see `Documentation/VR_WEAPON_HANDLING_ENGINE_LEVEL.md`).

Each weapon's hotspots are **derived from its own frame-0 mesh geometry** the same way the m16's
were reasoned about — barrel span on the long axis, magazine at the low vertical axis, charging
area at the receiver top — with per-weapon config overrides for meshes the auto-detector mis-reads.

## Files

| File | Role | Runtime |
|---|---|---|
| `md3_hotspots.py` | Shared, **stdlib-only** MD3 reader + geometry analyzer + hotspot derivation + reload-style→bone map. Also a CLI. | system python **and** Blender python |
| `build_weapon_iqm.py` | The generalized Blender builder: MD3 → rigged IQM for ONE weapon, driven by a JSON/dict config. | headless Blender 4.4 |
| `validate_iqm.py` | **stdlib-only** IQM validator: parses `INTERQUAKEMODEL v2`, reads joints, resolves parent bind positions, diffs vs expected hotspots. | system python |
| `build_all_weapons.py` | Batch driver: reads `weapon_roster.json`, builds + validates the whole roster in one command. | system python (spawns Blender) |
| `weapon_roster.json` | The per-weapon config: `{weapon, md3, out, style, material, [hotspots|axis|knobs|overrides]}`. | data |

## Reload style → hotspot set

| style | bones | weapons |
|---|---|---|
| `boxmag` | `hs_grip, hs_foregrip, hs_magwell, hs_rack` | Pistol, SMG, Chaingun, PlasmaRifle, (Rifle/m16) |
| `shell` | `hs_grip, hs_foregrip, hs_port` | Shotgun (tube) |
| `break` | `hs_grip, hs_foregrip, hs_breech` | SuperShotgun, Revolver, M79 |
| `pod` | `hs_grip, hs_foregrip, hs_breech` | RocketLauncher, BFG9000 |
| `canister` | `hs_grip, hs_foregrip, hs_tank` | Flamethrower |
| `none` | `hs_grip` only | melee / VR tools (excluded from the roster) |

`hs_grip` is the non-deforming root that carries **100%** of the mesh weight (the gun renders
exactly like the MD3 bind pose); the other bones are weightless named data points.

## How the geometry derivation works

`md3_hotspots.analyze_geometry()` measures the mesh and, with **no per-weapon assumption**:
- **long axis** = biggest bbox extent (the barrel/length); **vertical** = larger of the other two
  (grip + magazine hang along it); **lateral** = the thin one.
- **muzzle end** = the shallow/thin end. The breech/grip end is the half that hangs **deepest below
  the bore** and has the **tallest cross-section** (grip + mag). This survives front sights / carry
  handles that a naive "thinner end" test gets wrong.
- **bore line** = median vertical/lateral of the barrel-only third nearest the muzzle.

`derive_hotspots()` then places each bone relative to that frame (foregrip forward on the bore,
magwell at the top of the hanging mag column, rack at the rear-top, etc.), and writes them back in
the MD3's **own (x,y,z) order** so modeldef `Scale`/`Offset`/`ZOffset` (incl. a negative-X mirror)
carry over 1:1. Hotspots only need to land inside the engine's **generous reload radii**.

When a mesh is authored diagonally or a scope dominates an extent, the roster entry supplies an
`axis` hint (`{"long":"X","vert":"Z","lat":"Y","muzzle_at_max":true}`) or explicit `hotspots`.

## Ready-frame bake

An IQM ships a **single** implicit bind frame. Early builds baked MD3 **frame 0**, but for most
weapons frame 0 is a **mid-draw / transition pose**, not the resting pose — so once a modeldef was
repointed at the IQM the gun rendered **frozen tilted / mispositioned** in the hand.

The fix: bake the mesh from each weapon's **`ready_frame`** — the MD3 frame the weapon's modeldef
maps its **ready/idle sprite state** to (the true resting pose). `weapon_roster.json` carries a
`ready_frame` per weapon (`Pistol=2, Shotgun=4, PlasmaRifle=4, Chaingun=4, BFG9000=6,
SuperShotgun=1, RocketLauncher=5, SMG=4, Revolver=0, M79=3, Flamethrower=0, Rifle=0`); default `0`
is correct for weapons whose rest pose really is frame 0 (e.g. the proven m16/rifle).

Mechanically:
- `md3_hotspots.read_md3(path, frame)` reads **any** frame (frame `f`'s XYZ block starts at
  `ofsXyz + f*nVerts*8`; `read_md3_frame0` is kept as a frame-0 wrapper).
- `build_weapon_iqm.py` reads `ready_frame`, bakes the **mesh** from that frame, and shifts explicit
  hotspots by the **frame-0 → ready-frame centroid delta** (they're authored in frame-0 model space,
  so they follow the mesh's whole-gun translation to stay on the resting model). `hs_grip` stays
  at origin — it's the non-deforming weight anchor whose position never affects the render.
- `build_all_weapons.py` passes `ready_frame` through and validates against the builder's **actual
  emitted** (post-shift) hotspots, so validation is a true round-trip rather than a compare against
  the roster's pre-shift frame-0 coords.

## Run it

```sh
# whole roster: build every IQM alongside its MD3, then validate each
python tools/weapon_iqm_build/build_all_weapons.py

# dry geometry/hotspot report — NO Blender, NO writes
python tools/weapon_iqm_build/build_all_weapons.py --analyze-only

# one weapon
python tools/weapon_iqm_build/build_all_weapons.py --only Pistol

# re-validate existing IQMs without rebuilding
python tools/weapon_iqm_build/build_all_weapons.py --validate-only
```

Blender is auto-located under `C:\Program Files\Blender Foundation\*\blender.exe` (override with
`--blender <path>` or `BLENDER=<path>`). The IQM exporter is the iqm-master addon at
`C:\Users\Command\Desktop\Documentation\iqm-master\blender-4.1` (path pinned in `build_weapon_iqm.py`).

### Single-weapon build (bypass the driver)

```sh
blender --background --python tools/weapon_iqm_build/build_weapon_iqm.py -- <config.json>
blender --background --python tools/weapon_iqm_build/build_weapon_iqm.py -- <in.md3> <out.iqm> [style] [material]
```

## Migration safety (from the engine-level handling doctrine)

- **KEEP every MD3. Delete nothing.** IQMs are written **alongside** the MD3s; the modeldef points
  at one or the other. Bail-out = point `Model 0` back at the `.md3` (never moved) + flip
  `vr_new_weapon_handling` off.
- The shipped, in-headset-proven `hud/rifle/m16.iqm` is the **reference** and is left untouched; the
  batch reproduces it (to scratch) from `pin`ned hotspots to prove the generalized pipeline matches
  the specialized one.
- Baked MD3 reload/fire frames are intentionally dropped — native `VR_UpdateWeaponReload` replaces
  them; the IQM ships a single implicit bind frame (`modelsareattachments` uploads it).
- **This is a pk3-only iteration** once the C++ foundation lands — re-running the batch needs no
  engine rebuild.

> Modeldef repoint (`Model 0 "<body>.md3"` → `"<body>.iqm"` + `modelsareattachments`) is **not** done
> by this tool — it's the per-weapon rollout step, gated behind `vr_new_weapon_handling`, done one
> weapon at a time after in-headset proof (exactly as the m16 was).
