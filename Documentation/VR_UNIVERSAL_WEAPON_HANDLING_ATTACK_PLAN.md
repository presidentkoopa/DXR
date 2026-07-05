# VR Universal Weapon Handling — Attack Plan

> **The vision, one line:** turn DoomXR into a VR-ification *layer* — load **any** Doom mod and its
> weapons get a 3D model in your hands + physical manual reload + two-hand grip + chest-pouch ammo,
> **mod-agnostically, without editing the mod**, degrading gracefully when the archetype match is imperfect.

Status: **roadmap / not started** (the per-weapon system it generalizes IS built — see
`VR_WEAPON_HANDLING_ENGINE_LEVEL.md` and the 14-weapon wiring). This doc is the plan to go from
"our 14 weapons" to "near-universal on anything that loads."

---

## 1. What "done" looks like

- Load a wacky laser-gun mod → every gun renders as the **closest 3D archetype model** (hotspot-rigged),
  reloads by that archetype's **gesture from the chest pouch**, grips two-handed — all automatic. If the
  match is loose (laser → shotgun model + generic box-mag), **that's fine** — near-universal, not perfect.
- Mods that **already reload** (Ashes 2063, Hideous Destructor, most modern weapon mods) are **detected and
  deferred to** — we hand them the grip + pouch-as-ammo-source, but we never fight their own reload logic.
- **Zero per-weapon ZScript edits.** The ~13 base-weapon `.zs` forks we hand-wired get **reverted** →
  clean vanilla weapons, zero upstream-merge burden. Reload becomes a property of the *engine*, not the *weapon*.

---

## 2. Current state — the foundation is ~70% built

| Piece | Status | Where |
|---|---|---|
| 3D model on **every** weapon, mod-agnostic (archetype class-substitution) | **SHIPS, ON by default** | `FVRWeaponResolver`, `hw_weapon.cpp` |
| Native reload FSM (seat → rack → chamber) | **compiled** | `VR_UpdateWeaponReload`, `p_user.cpp` |
| Chest ammo pouch (spawns mags → FSM) | **built (ZScript)** | `vr_ammo_pouch.zs` |
| Per-archetype hotspot IQM builder (box-mag/shell/cylinder/break/pod/canister) | **built** | `tools/weapon_iqm_build/` |
| Native MD3→IQM render swap (auto-renders hotspot IQMs) | **coded** | `vr_weapon_model_format`, `VR_ApplyWeaponModelFormat`, `hw_weapon.cpp` |
| Haptics (native + ZScript `VR_HapticPulse`) | **works** | `hw_vrmodes.cpp`, `actor.zs` |
| Reload wired on 14 DoomXR weapons (the thing to eventually revert) | **done, hand-wired** | `mixin XR_ManualReload`, `vr_manual_reload.zs` |

**The gap:** reload is currently *opt-in per weapon* (mixin hand-edited into each `.zs`). Everything else already
generalizes across mods. Universalizing = moving the reload trigger off the weapon and into the engine.

---

## 3. Design principles (do not violate)

1. **Decoupled:** model library ⟂ reload logic ⟂ classifier. Grow each independently; never cross-couple.
2. **Detect-and-defer:** *never* impose a chamber on a weapon that already reloads itself. This is the
   difference between "enhances Ashes" and "wrecks Ashes."
3. **Imperfection-tolerant:** a close-enough archetype is acceptable. Optimize for coverage, not accuracy.
4. **Native-first:** the fire-gate + chamber state live in C++; ZScript stays thin (or disappears entirely).
5. **No-rebuild growth:** new models + new classifier rules extend the system without recompiling the engine.

---

## 4. The phased plan

### Phase 0 — Validate the base (DO THIS FIRST)
Prove the **14 hand-wired weapons feel right in-headset** before universalizing anything.
- Tune: pouch position/reach (`vr_pouch_height/forward/radius`), eject timing, mag magnetism
  (`vr_reload_assist`), auto-chamber vs rack (`vr_reload_chamber`), haptic strength (`vr_reload_haptic`).
- **Exit criteria:** the reload gesture feels good on the 14. Do NOT generalize an unvalidated feel — a bad
  pouch reach discovered across every mod at once is 50× harder to diagnose than on 14 known weapons.

### Phase 1 — The self-reload DETECTOR (the safety keystone) — *build this first of the real work*
Decide, per weapon at tag time: does it **already reload itself**?
- Signals: has a `Reload` state? has a magazine/ammo-per-shot field? uses a known reload-mod base or keyword?
  matches Hideous-Destructor / Ashes / Doom-RL-Arsenal patterns?
- Output: tag each weapon `RELOAD_DEFER` (leave its logic alone; only add grip + pouch-as-ammo) or
  `RELOAD_IMPOSE` (apply the archetype box-mag chamber).
- Where: extend the archetype resolver's tag pass (`hw_weapon.cpp` / the keyword dispatcher), or a ZScript
  weapon-inspection at pickup.
- **Risk: LOW. Effort: SMALL.** This is what makes "universal" *safe* instead of destructive. Ship nothing
  that imposes reload until this is reliable.

### Phase 2 — Native FIRE-GATE (the hard part — the ballgame)
For `RELOAD_IMPOSE` weapons only: intercept "fire" **generically in C++**, *before* the weapon's Fire state
spends ammo, check a **natively-tracked per-weapon chamber**, and dry-click if empty.
- Why native: ZScript can't cleanly veto an arbitrary mod's Fire state; the interception has to sit in the
  psprite/weapon fire dispatch (`p_pspr.cpp` / the weapon fire path).
- Chamber state: tracked **natively per-weapon** (a map keyed on the weapon instance), NOT the ZScript mixin.
  Must serialize for save/load.
- **Risk: HIGH** — generic interception across MBF21 / DECORATE / ACS / projectile / hitscan / charge weapons
  is fragile; some weird weapon *will* fight it (that's the "near" in near-universal). **Effort: LARGE.**
- **Payoff:** once this works, **revert the 14 ZScript forks** → clean base weapons, zero merge burden.

### Phase 3 — Keyword CLASSIFIER (route to the right archetype)
Read each weapon's keywords / class name / `DamageType` / projectile type ("laser", "plasma", "smg",
"revolver", "cell", "shell") → pick the **best archetype bucket** (which model + which reload style).
- More buckets = finer match = the model shelf actually gets used (else everything maps to "rifle").
- Where: extend the resolver's tagging (`KEYWORDS.json` + `hw_weapon.cpp`).
- **Risk: LOW. Effort: MEDIUM, ongoing.** This is the multiplier that turns a big model library into value.

### Phase 4 — Model LIBRARY (fill the shelf, forever)
Keep adding hotspot IQMs via the batch builder; each new model carries its own reload style automatically.
- Pipeline: `tools/weapon_iqm_build/build_weapon_iqm.py` auto-derives `hs_*` hotspots from mesh geometry, so
  adding a model is "drop mesh + run," not "hand-place magwell/rack."
- **Ship a fat pk3** — models are load-on-demand + cached; cost is disk/load-time, not runtime. VR wants 3D in
  hand anyway.
- **Risk: NONE. Effort: incremental, forever.** No rebuild needed to add a model.

---

## 5. Dependencies & ordering

```
Phase 0 (validate)  ──►  Phase 1 (detector)  ──►  Phase 2 (native fire-gate)  ──►  revert the 14 forks
                                   │
                                   └──►  Phase 3 (classifier)  ◄──►  Phase 4 (model library, ongoing)
```
Phase 1 gates everything (safety). Phase 2 is the hard native unlock. Phases 3–4 are the extend-forever tail
and can proceed in parallel once the classifier hook exists.

---

## 6. Risks & open questions

- **Generic fire interception** is the real unknown — validate early against MBF21, projectile, charge, and
  continuous-fire weapons (flamethrower-likes) from real mods.
- **Detector reliability is safety-critical:** a false `IMPOSE` on a self-reloading weapon = two reload systems
  fighting = broken mod. Bias the detector toward DEFER when unsure.
- **Chamber save/load serialization** on the native side (the current mixin's `XRChamber` serialization is also
  unverified — see `dxr-reload-modcompat-native-migration`).
- **Perf:** classification must be cached per weapon-class (the model swap already memoizes per
  `FSpriteModelFrame*` — copy that pattern).
- **Model-swap desirability:** some mods have their own nice 3D/voxel weapons; forcing our archetype model may
  be unwanted. Consider a "only swap 2D-sprite weapons" guard.

---

## 7. The payoff

When Phase 2 lands and the forks are reverted:
- Base Doom weapons are **clean vanilla** again (no `mixin`, no gate) — zero upstream-merge burden.
- Manual reload + pouch + two-hand become a property of the **engine**, applied by **archetype**, to
  **anything that loads** — the same way the 3D-model swap already works today.
- DoomXR stops being "a VR game with 14 reloading guns" and becomes **"the VR layer you run the whole Doom
  modding ecosystem through."**

---

## 8. Key code pointers

- Archetype resolver / model swap: `src/rendering/hwrenderer/scene/hw_weapon.cpp` (`FVRWeaponResolver`,
  `VR_ApplyWeaponModelFormat`)
- Reload FSM: `src/playsim/p_user.cpp` (`VR_UpdateWeaponReload`, hotspot reads ~`VR_WeaponHotspotWorld`)
- Chest pouch: `wadsrc/static/zscript/engine/vr_ammo_pouch.zs`
- Per-weapon reload layer (to be superseded): `wadsrc/static/zscript/engine/vr_manual_reload.zs` (`XR_ManualReload`)
- Hotspot IQM builder: `tools/weapon_iqm_build/` (`build_weapon_iqm.py`, `md3_hotspots.py`, `weapon_roster.json`)
- Haptics: `src/common/rendering/hwrenderer/data/hw_vrmodes.cpp` (`VR_HapticEvent`); ZScript `VR_HapticPulse` (`actor.zs`)
- Options: `wadsrc/static/menudef.txt` → `OptionMenu VRReloadOptions`
- Related docs: `VR_WEAPON_HANDLING_ENGINE_LEVEL.md`, `NATIVE_WEAPON_MODEL_FORMAT_SWAP.md`
- Related memory: `dxr-manual-reload-arsenal-complete`, `dxr-reload-modcompat-native-migration`,
  `dxr-weapon-archetype-model-swap`, `dxr-weapon-iqm-batch-builder`
