# DoomXR Weapon Mass System — Design Prototype (NOT YET IMPLEMENTED)

*Saints & Sinners-style weapon heft. A paper prototype: the full system on the page, no engine code
committed. Everything below is a spec to review/tune before a line ships.*

Status: **DESIGN ONLY.** Nothing here is built. The whip verlet (`vr_whip.zs`) is the one existing
piece of this idea (the floppy extreme of the same spectrum) and is referenced as the proof the
mass approach works.

---

## 0. The problem

Right now a weapon rigidly tracks the controller 1:1. `GetWeaponTransform` (hw_vrmodes.cpp) hands the
render the raw controller matrix; the gun is a prop glued to your hand with **zero mass**. That's why
it reads as weightless and why "recoil" and "heft" have nowhere to live. Saints & Sinners feels good
because every weapon has **weight**: it lags, swings with momentum, resists fast reorientation, and
settles. We want that, uniformly, from one system.

---

## 1. Core model: a mass-spring-damper between controller and weapon

Interpose a per-weapon, per-hand **critically-damped spring** between the raw controller pose
(`target`) and the *rendered* weapon pose (`pose`). The weapon chases your hand, but with inertia.

```
# per hand, per tic (dt = 1 tic):
posAccel = k * (targetPos - pose.pos)   -  c * pose.vel          # spring toward hand, damped
pose.vel += posAccel * dt
pose.pos += pose.vel * dt

# rotation: same idea on orientation (quaternion), torque from the shortest-arc error
qErr      = target.rot * pose.rot.Conjugate()        # rotation needed to reach the hand
axisAngle = qErr.ToAxisAngle()                        # error as axis * radians
angAccel  = k_rot * axisAngle  -  c_rot * pose.angVel
pose.angVel += angAccel * dt
pose.rot     = Integrate(pose.rot, pose.angVel, dt)   # quaternion integrate, renormalize
```

Two intuitive knobs, NOT raw k/c:
- **ωₙ (natural frequency)** = responsiveness. Light gun = high ωₙ (snappy). Heavy = low ωₙ (sluggish).
  `k = m·ωₙ²`.
- **ζ (damping ratio)** = wobble. `c = 2·ζ·m·ωₙ`.
  - Guns: **ζ ≈ 1.0** (critically damped — heavy but NO wobble; wobble reads as nausea, not weight).
  - Melee: **ζ ≈ 0.7–0.85** (slight overshoot → the head follows through on a swing = heft).

So per weapon you author **(ωₙ, ζ)**, derived from its mass. Mass → ωₙ via a simple curve
(`ωₙ = ωₙ_base / sqrt(mass/mass_ref)`), so designers can just set mass and get sensible defaults.

---

## 2. Mass source

Actors already carry `Mass`. Use it, with a per-weapon `vr_weapon_mass` override (Keywords or a
mixin field) for feel-tuning independent of gameplay mass. Rough tiers:

| Class | feel | ωₙ | ζ |
|---|---|---|---|
| Pistol / SMG | snappy | high | 1.0 |
| Rifle / Shotgun | planted | mid | 1.0 |
| Chaingun / BFG / RPG | heavy, deliberate | low | 1.0 |
| Sword / Chainsaw (melee) | swings, follows through | mid | 0.75 |
| Whip | fully floppy (verlet, already built) | — | — |

---

## 3. Recoil falls out for FREE (answers the "do I need a recoil IQM?" question)

Once a weapon is a mass on a spring, **recoil is just an impulse into that spring** — no baked
frames, no new IQM:

```
OnFire():
  pose.vel    += -muzzleDir * (recoilImpulse / m)      # kickback (heavier gun kicks less)
  pose.angVel += pitchUpAxis * (recoilTorque / m)      # muzzle rise
  # the damper settles it over the next ~10-15 tics automatically
```

Recoil, sway, and heft become **one system** instead of three. This is the recommended answer to the
earlier "static IQM has no recoil" problem: don't bake recoil, impulse the mass.

---

## 4. THE make-or-break detail: aim comes from the SETTLED pose

If the visible gun lags the controller, the **fire/aim direction MUST come from the settled weapon
pose, not the raw controller** — otherwise shots go where your hand points while the gun visibly
points elsewhere = broken and infuriating.

Ordering per tic MUST be:
1. Update the mass spring → `pose` (settled weapon transform).
2. Derive `AttackPos` / `AttackDir` from `pose`'s **muzzle/barrel axis** (not the controller).
3. Feed the SAME `pose` to the render AND to the hotspot resolvers (reload, two-hand, IK).

This is the single thing that decides whether the system feels deliberate (S&S) or floaty-broken.
Currently `AttackPos/Dir` come straight from the controller (OpenXR thread) — that seam must instead
read the settled pose.

---

## 5. Two-hand bracing

When the off-hand grips near `hs_foregrip` (existing two-hand detection), **stiffen the spring**:
raise ωₙ and ζ → less sway, steadier heavy guns. Bracing a chaingun with two hands should visibly
plant it. Ties directly into the existing two-hand system and the grip arbiter.

---

## 6. The spectrum (why the whip is the proof)

This is ONE continuum, "how floppy is the mass":

```
rigid gun  ──────────  melee (sword/chainsaw)  ──────────  whip
stiff crit-damped        softer, under-damped,               infinite-segment verlet
spring (subtle lag       head lags + follows through         (already built, vr_whip.zs)
+ recoil settle)
```

The whip already runs a **mass-tapered verlet** (nodes with `mass = radius²`, inverse-mass-weighted
constraints, handle heavy/pinned → tip light) — it proves the mass approach behaves. A rigid gun is
the same idea collapsed to a 1-node stiff spring. Melee sits between. So the system generalizes what
the whip already does to the whole arsenal.

> Caveat carried from the whip: its mass SIM is sound, but its rigged-model RENDER (procedural bone
> posing on a world actor) shows a rigid bind pose in-headset — a render-path bug, NOT a physics bug.
> The gun mass system renders through `GetWeaponTransform` (the HUD-weapon path, known-good), so it
> does NOT inherit that bug. Confirm with the Reloadin'/IK lanes before relying on world-actor
> procedural pose anywhere.

---

## 7. Where it lives

Native C++ at the weapon-transform seam so it's uniform + physics-rate:
- **State:** per-player, per-hand `{pose.pos, pose.vel, pose.rot, pose.angVel}` (new fields near the
  VR hand state in `d_player.h`).
- **Update:** a `VR_UpdateWeaponMass(player)` peer to `VR_UpdateHardpoints`/`VR_UpdateWeaponReload`,
  run once per tic BEFORE aim/hotspot resolution.
- **Consume:** `GetWeaponTransform` returns the settled `pose` instead of the raw controller matrix;
  the OpenXR `AttackPos/Dir` writer reads the settled `pose`'s muzzle.
- **Config:** cvars below; per-weapon `(mass, ωₙ, ζ, recoilImpulse, recoilTorque)`.

---

## 8. Cvars (all with safe rigid-fallback defaults)

```
vr_weapon_mass          bool   1     # master: 0 = current rigid 1:1 behaviour (instant revert)
vr_weapon_mass_scale    float  1.0   # 0..1 global heft amount (0 = rigid, 1 = full authored feel)
vr_weapon_mass_maxlag   float  ...   # comfort clamp: max positional lag (units) before it's capped
vr_weapon_mass_maxtilt  float  ...   # comfort clamp: max angular lag (deg)
vr_weapon_recoil        bool   1     # impulse-based recoil on/off
vr_weapon_recoil_scale  float  1.0
vr_weapon_twohand_brace float  1.0   # how much two-handing stiffens the spring
```

Comfort is non-negotiable: too much lag/wobble = disconnect + nausea. The clamps + `_scale` let a
sensitive player dial it toward rigid without losing recoil.

---

## 9. Phasing (when we build it)

1. **P0 — prototype one weapon (pistol):** spring-damper on position+rotation, aim-from-settled,
   impulse recoil. Feel-tune ωₙ/ζ in-headset. No roster changes.
2. **P1 — mass tiers:** author (mass, ωₙ, ζ) per weapon class; validate light vs heavy contrast.
3. **P2 — two-hand bracing + comfort clamps + cvars.**
4. **P3 — melee under-damping (sword/chainsaw follow-through);** unify the whip as the floppy limit
   (shared "weapon mass" vocabulary, not necessarily shared code).

---

## 10. Dependencies / cross-lane

- **IK/body lane:** their hand-pin to `hs_grip` must read the SETTLED weapon pose (§4), so the hand
  follows the mass-lagged gun — hand+weapon move as one weighted unit. Mass update runs BEFORE IK.
- **Reloadin' lane:** reload hotspots (`hs_magwell`/`hs_rack`) are resolved from the weapon transform;
  they must use the settled pose too, or the mag seats where the gun *was*, not where it *is*.
- **Aim/netcode:** `AttackPos/Dir` now derive from the settled pose — the net-sanitize work must
  sample the same settled values, not the raw controller.

---

## 11. Open questions (decide before P0)

1. **ωₙ↔mass curve** — expose ωₙ directly per weapon, or derive from Mass with one global curve?
   (Leaning: derive default from Mass, allow per-weapon override.)
2. **Positional lag magnitude** — how much cm-equivalent lag reads as "heavy" without reading as
   "broken tracking"? Headset-only tuning call.
3. **Does the settled-pose aim break existing laser-sight / hotspot code** that assumes controller ==
   weapon? Audit every reader of `AttackPos/Dir` before flipping the seam.
4. **Melee (sword) already swings via its own code** — unify under the mass model, or leave melee as
   its own thing and only mass-ify guns? (Leaning: guns first; melee later, P3.)
5. **Whip stays separate** (verlet is the right tool for a rope) — the mass system is for RIGID
   weapons; the whip just shares the vocabulary.

---

*Review this, then say go and I'll prototype P0 (pistol only) so you can feel it before we commit the
roster.*
