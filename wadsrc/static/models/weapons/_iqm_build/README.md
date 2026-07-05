# MOVED → `tools/weapon_iqm_build/`

This weapon MD3→rigged-IQM batch builder now lives (canonically) at:

    tools/weapon_iqm_build/

alongside the other authoring tools (`tools/sdf_authoring/`, `tools/testmaps/`), with a write-up at
`Documentation/WEAPON_IQM_BATCH_BUILDER.md`.

The `.py` / `weapon_roster.json` files in THIS folder are kept **in sync** with the canonical set in
`tools/weapon_iqm_build/` (they differ only in the roster's `md3`/`out` paths, which are relative to
this folder). **Edit the canonical set in `tools/weapon_iqm_build/`**, then re-sync here.

The built `.iqm` outputs are unaffected — they sit next to their `.md3` files under this
`models/weapons/` tree, exactly where the game loads them.

## Ready-frame bake

An IQM ships a **single** implicit bind frame. Early builds baked MD3 **frame 0**, but for most
weapons frame 0 is a **mid-draw / transition pose**, not the resting pose — so once a modeldef was
repointed at the IQM the gun rendered **frozen tilted / mispositioned** in the hand.

The fix: bake the mesh from each weapon's **`ready_frame`** — the MD3 frame the weapon's modeldef
maps its **ready/idle sprite state** to (the true resting pose). `weapon_roster.json` carries a
`ready_frame` per weapon; default `0` is correct where the rest pose really is frame 0 (e.g. the
proven m16/rifle). `md3_hotspots.read_md3(path, frame)` reads any frame (`read_md3_frame0` kept as a
wrapper); `build_weapon_iqm.py` bakes the mesh from `ready_frame` and shifts explicit hotspots by the
frame-0 → ready-frame **centroid delta** so they stay on the resting model (`hs_grip` stays at
origin). See `tools/weapon_iqm_build/README.md` for the full write-up.
