# VR Two-Hand Grip + Determinism Spec

> Single-player only (no netplay) — so **none** of the net-sanitize / grip-bit-drop / consoleplayer-gate
> concerns apply. This is pure gameplay-feel work. The grip must be **deterministic**: one squeeze → one
> action, decided by the arbiter, never a double-fire.

---

## Part 1 — Deterministic grip (the keystone)

**Problem (confirmed by reading `VR_ResolveGripOwner`, p_user.cpp:1465):** the arbiter *computes* the correct
owner every tic — priority **CLIMB > WHIP > GLOVE > HARDPOINT** (+ Schmitt commit gate) — and publishes it to
`vr_grip_owner[hand]`. But it's **dormant**: only the whip rope-pump and the new foregrip two-hand actually
*obey* it. **Climb, gravity gloves, and hardpoints still read the raw grip independently and act on their own**
(p_user.cpp: gloves 1700, climb ~3518, hardpoints in `VR_UpdateHardpoints`). So two systems can fire off one
squeeze (e.g. holster-draw AND glove-snatch).

**Fix:** gate each consumer on ownership. Before a consumer acts on grip, require
`vr_grip_owner[hand] == GRIP_<SELF> || vr_grip_owner[hand] == GRIP_NONE`. Bootstrapping is fine because the
arbiter grants `GRIP_NONE` until a consumer latches, then locks to that consumer. Master escape hatch already
exists (`vr_grip_arbiter`), so a regression is one CVar away from disabled.
- Gloves: only scan/lock/pull when owner ∈ {GLOVE, NONE}.
- Climb: only latch a climb when owner ∈ {CLIMB, NONE}.
- Hardpoints: only draw/holster when owner ∈ {HARDPOINT, NONE}.
Care: each consumer uses grip in *several* places (press, hold, release/throw) — gate all of them coherently,
don't just gate the press. Owner is 1-tic-latent by construction (documented, harmless for these).

---

## Part 2 — Per-weapon two-hand FEEL (the design)

Two engage paths today: **legacy capsule** (default) = off-hand near the barrel axis line, length
`vr_twohand_length` = 30u ("shotgun-sized", one-size-fits-all); **hotspot** (`vr_new_weapon_handling` on) =
off-hand within `vr_foregrip_radius` of the authored `hs_foregrip` bone. Neither is tuned per weapon yet.
Target feel:

| Weapon | Desired two-hand | Mechanism |
|---|---|---|
| **Pistol** | Two hands **cupped** like a normal pistol grip — support hand *under/at* the main grip, NOT out on a barrel | `hs_foregrip` at/just-below the grip; short per-weapon length (~8u) so the capsule can't engage way out front |
| **Chaingun** | Off-hand on the **side handle**, not the bore line | Re-place `hs_foregrip` onto the side-handle geometry (roster override) |
| **SMG** | Like a **shorter rifle** — foregrip forward but tighter reach | `hs_foregrip` mid-body; per-weapon length ~18u (vs rifle 30u) |
| **Rifle / Rocket / Shotgun / BFG** | Standard forward foregrip on the barrel/tube | Geometric `hs_foregrip` is already fine |
| **Sword** | Held **right** — two hands on the **hilt** (like a greatsword), NOT a forward "foregrip" | New two-hand mode: off-hand grabs the hilt zone → grip locks blade orientation to the two-hand line |
| **Whip** | Two-hand by grabbing the **~second bone** of the chain to **twirl** it | Whip-specific: off-hand grabs `seg_01` → becomes a second constraint point the Verlet sim twirls around |

**Per-weapon two-hand length** is the missing data. Options: (a) read it from the weapon's Keywords
(`GetWeaponOffsets` already returns a radius — extend it to a length), or (b) an archetype default
(pistol/smg/rifle/heavy). (a) is cleaner and mod-friendly.

---

## Part 3 — IQM coverage gaps

All 12 firearms + Sword/Whip/IceHook have IQMs. **Missing (weapon bodies): Chainsaw, ShieldSaw, HandGrenade**
(Fist has no model). **MARKED FOR CONVERSION (later, per user): Chainsaw + ShieldSaw** — convert via the batch
builder (`tools/weapon_iqm_build/`: roster entry, run `build_all_weapons.py`, validate). Chainsaw wants a
foregrip hotspot (it can two-hand); ShieldSaw is off-hand (`grip:none`) so minimal hotspots. Non-destructive
(alongside the MD3), do NOT repoint the modeldef — the native model-format swap auto-renders the `.iqm`
sibling on rebuild. HandGrenade stays MD3 (thrown, no two-hand). Coordinate with the IQM-builder lane.
Tracked as session task #13.

---

## Ownership / who does what
- **C++ (p_user.cpp):** Part 1 arbiter-consumer rewiring; per-weapon two-hand length; sword-hilt two-hand mode.
- **IQM lane (`tools/weapon_iqm_build/` roster):** re-place `hs_foregrip` per Part 2 (chaingun side-handle,
  pistol-at-grip, smg mid-body); convert the Chainsaw.
- **Whip lane (`vr_whip.zs`):** the `seg_01` twirl two-hand.
- **Sword (`vr_sword.zs` + C++):** hilt two-hand orientation lock.

Related: `VR_UNIVERSAL_WEAPON_HANDLING_ATTACK_PLAN.md`, `VR_WEAPON_HANDLING_ENGINE_LEVEL.md`.
Memory: `dxr-grip-arbiter-implemented`, `dxr-weapon-iqm-batch-builder`.
