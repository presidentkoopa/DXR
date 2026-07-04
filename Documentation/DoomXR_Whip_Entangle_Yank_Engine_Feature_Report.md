# DoomXR — Whip Entangle/Yank as an Engine-Level Physics Feature
### Feasibility report · 2026-07-03 · grounded in a 4-agent parallel audit of Keywords, Mass, Climbing, and the VR Weapon Options convention

---

## 0. What was asked, plainly

1. **Contextual yank-the-player** — replace the old unconditional "fly straight to whatever you hit" REEL with something that only pulls you when it makes sense, player-controllable, not automatic.
2. **Entangle an enemy, yank it toward the player with roll and physics**, gated on a real **mass-vs-player-velocity check** — heavier enemies resist more, harder whip-swings pull harder.
3. **The Bulletstorm fantasy** — whip an enemy in, follow up with a melee kill (chainsaw). The yank needs to land them in a state where that combo actually works.
4. **Extensive, highly customizable VR Weapon Options** for all of this.
5. **Examine this as a genuine engine-level feature** — built on the existing Keywords/Mass/Climbing systems, not bolted onto one weapon file as a one-off.

Everything below is grounded in source I (and four parallel research agents) actually read this session — file:line citations throughout, not recalled from memory.

---

## 1. Verified engine facts (the grounding)

### 1.1 Mass — the real convention, not guesswork

**Throw formula** (`p_user.cpp:1509-1513`, confirmed live):
```cpp
double itemMass  = heldItem->Mass > 0 ? heldItem->Mass : 100.0;
double massScale = 100.0 / itemMass;
double throwForce = vr_throw_force * massScale;
heldItem->Vel = handVelocity * (vr_scale_meters_to_units / 35.0) * throwForce;
```
**Inverse-linear**: double the mass, half the resulting velocity. This is the one canonical "force meets mass" formula already in the engine, and it's the template the yank formula below directly copies.

**Calibration baseline** — a comment at `p_mobj.cpp:3073` states explicitly: *"100 being equivalent to a player."* Mass values aren't kg; they're a designer-feel scale anchored at **100 = one player**.

**Confirmed defaults**: generic `Actor` = 100 (`actor.zs:422`), `DoomPlayer` = 100, `DoomImp` = 100 (inherited, no override found), `Cyberdemon` = **1000** — a boss is a flat 10× a player's mass, by design.

**Every other place Mass already gates physics** (full list from the audit): explosion thrust (`points*0.5/Mass`, inverse), collision damage (`Mass/100+1`), blast damage (`Mass>>5`), vertical push-blocking (`otherMass > myMass`), MBF bounce threshold (`Mass*gravity/64`), water sink speed (`Mass/100` linear). Mass is a real, load-bearing physics variable all over this engine — the whip yank isn't introducing a new concept, it's the first *weapon* to use one.

**My own existing whip code already has a mass gate** — `vr_whip.zs`'s YANK mode checks `grappleVictim.Mass > 400 || bBoss` and falls back to "reel the player toward it instead." What it's missing: everything *below* that cutoff pulls at one flat constant speed (`WHIP_YANK_SPEED = 18.0`), with zero scaling. That's the gap this report closes.

### 1.2 Keywords — what exists, what doesn't

`KeywordProfile` (`keyword_dispatcher.h:7-66`) already carries ~30 driven properties across color/pulse, mass, climbable/climb_speed, throwable/primable, weapon params (recoil, parry extents), ballistics, gore colors, vulnerability multipliers, stun duration, and haptics. `KEYWORDS.json` organizes these into namespaces (`"mass": {"heavy": {"mass": 800}}`, `"climb": {"LADDER": {"climb_speed": 1.2}}`, etc.) parsed once at startup into a static C++ map.

**What does NOT exist anywhere in the engine, confirmed by targeted search:** entangle, tether, leash, snare, grabbed — zero hits. **No precedent for one actor's velocity being authoritatively set by another actor's action** — gravity gloves move items via `SetPos`, not `Vel`; climbing only ever moves the *player*. My existing whip YANK code (`grappleVictim.Vel += ...`) is, as far as this audit found, **the first thing in this codebase that does this at all.**

**ZScript↔Keywords boundary**: `Actor.Keywords` (the raw FString) is directly readable/writable from ZScript (`DEFINE_FIELD`, `vmthunks_actors.cpp:2065`). But the dispatcher's *query* methods (`KeywordDispatcher::IsClimbable()`, etc.) are C++-only — never exported as native thunks. ZScript can see the tag string but can't ask the dispatcher what it means, today.

**Reusable ZScript-native state slots for a temporary "entangled" condition, with zero new fields**: `reactiontime` (already used elsewhere in my own whip code for stagger), `special1`/`special2` (general-purpose int), `specialf1`/`specialf2` (general-purpose double) — all actor.h fields, all already exposed to ZScript.

### 1.3 Climbing — confirmed, and confirmed *not* reusable as-is

`VR_UpdateClimbing` (`p_user.cpp:1864`, exact re-verified formula):
```cpp
DVector3 mapVel(handVel.X, handVel.Z, handVel.Y);          // coordinate remap
DVector3 move = mapVel * (double)speedMult;                 // keyword-driven multiplier
climbDelta -= move;
player->mo->flags |= MF_NOGRAVITY;                          // while gripping
player->mo->Vel = climbDelta * vr_climb_speed_mult;          // global tuning CVar
// on release: flags &= ~MF_NOGRAVITY
```
CVars: `vr_climb_radius` (32.0, also the kill-switch — ≤0 disables climbing entirely), `vr_climb_speed_mult` (1.0).

**Confirmed NOT directly reusable**: this function is saturated with player-only state (`player_t::vr_climbing_lines[hand][]`, VR grip-button reads, hand-tracking transforms) and has **zero concept of a moving/dynamic anchor** — climbable surfaces are static `line_t*` geometry only. "Climb the rope while it's swinging" is genuinely new capability, not an extension of an existing one. The *formula* (hand-velocity-driven `Vel` assignment, `NOGRAVITY` toggle) is trivially copyable into pure ZScript; the *function* is not callable for this purpose.

### 1.4 VR Weapon Options — the real house convention (corrects an earlier wrong assumption of mine)

I'd assumed `vr_weapon_menu.zs` was a per-weapon options screen. It isn't — it's a debug weapon-archetype scanner (`vr_weapon_menu.zs:3-32`), irrelevant here.

**The actual convention, confirmed with working examples:**
- Declare in **CVARINFO** with `user` scope: `user float vr_sword_swing_on = 35.0;` (`CVARINFO:178-180`, real, already shipping for the sword).
- Expose in **MENUDEF** via an `OptionMenu` block using `Slider`/`Option`/`ColorPicker`/`Submenu` controls and `TFLV_Tooltip` hover text (a real, established tooltip convention already used throughout `menudef.txt`).
- Read in ZScript via `CVar.FindCVar(name).GetFloat()/.GetInt()/.GetBool()` with a null-check fallback — exactly the pattern my own `CheckWhipCVar()` already uses.

**The gap worth knowing**: Sword (3 CVars) and ShieldSaw (8 CVars) both have real CVARINFO entries **with zero MENUDEF exposure** — console-only today. Nothing in this engine currently gives a player full in-headset slider control over a melee/VR weapon's feel. The whip can be the first.

---

## 2. Design: contextual player-yank

Kill the height-based REEL/SWING mode split from the last pass (auto-fly-to-anchor regardless of context). Replace with:

| Context at catch (geometry, not an enemy) | What happens | Why |
|---|---|---|
| **Airborne** (`!player.onground`, confirmed real native field, `player.zs:3170`) | Automatic pendulum: self-applied gravity + taut-line constraint (the existing SWING math) | Nothing else is holding you up — this is just what standing under a taut rope with no floor *does*. No special-casing needed; it falls out of the physics. |
| **Grounded, idle** | Nothing. Rope attaches, floor holds you, taut-line constraint never fires because you haven't gone anywhere. | Matches your exact ask: whip into the ceiling while standing on ground should not yank you. |
| **Grounded or airborne, Fire held while a line is attached** | A deliberate, player-triggered fast reel toward the anchor (the old REEL behavior, but now opt-in, not automatic) | Gives you the snappy, arcade "yank me across the gap NOW" option without it happening by accident every time you crack the whip at a wall. `Fire` is already free during an active grapple (it's not doing anything else while AltFire is held). |
| **Climbing** (off-hand grip + hand velocity, any time while attached) | Moves you along the rope, exactly the native climb formula, reused in pure ZScript since (§1.3) the native function itself can't be called here | The SAME mechanic naturally does two different jobs: lifts you off the ground when grounded, or shortens/lengthens the swing radius when airborne (see §2.1) |

**Release, at any point, in any of the above states**: momentum carries forward untouched — this is the property you just asked about, confirmed already true and preserved by construction (`EndGrapple` never mutates `Vel`).

### 2.1 The swing-pump physics (from the prior theory pass, restated with the numbers)

Real angular momentum conservation, not a game-y fudge: for a mass on a line, `m·v·L ≈ const`. Shortening the rope length `L` while swinging (climbing toward the anchor) scales tangential speed up by `L_old/L_new` — the figure-skater effect. One line of math added to the existing per-tic swing update whenever `grappleDist` changes via climbing.

---

## 3. Design: entangle + yank an enemy, with roll, gated on mass vs. hand velocity

This is the part that needed the Mass-system audit. Grounded directly in the verified throw formula's `100/Mass` convention:

```
handSpeed        = owner.GetHandVelocity(hand).Length()      // "the player velocity check," literally
massRatio         = 100.0 / max(1, target.Mass)                // same inverse-linear shape as the throw formula
pullSpeed         = handSpeed * WHIP_YANK_FORCE_SCALE * massRatio

if target.bBoss:
    pullSpeed = 0        // bosses never get pulled, same convention as today -- but the CRACK still hits/damages them
elif pullSpeed < MIN_ENTANGLE_SPEED:
    "whip cracks across them, no catch" -- damage/stagger only, no movement
else:
    ENTANGLED
```

Worked example with real confirmed numbers: an Imp (Mass ≈ 100, `massRatio = 1.0`) gets pulled hard by almost any real swing. A Cyberdemon (Mass = 1000, `massRatio = 0.1`) needs a swing **10× as fast** to move it at all by the same formula — and its `bBoss` flag blocks a full yank outright regardless, matching the existing convention exactly. This directly satisfies "if enemy mass passes player velocity check" — it's not a binary pass/fail, it's a continuous force-vs-resistance relationship, so whipping *harder* visibly matters.

**Entangle duration (the "wrapped up," not-instant part)**: use the confirmed-free `special1` as a tic countdown, set on catch, ticked down each frame, gates the pull duration and can also suppress the target's attack state via the same `reactiontime` field my code already uses for stagger. No new AActor fields — zero C++ required for this part.

**Roll**: confirmed real and settable (`native double Roll`, `A_SetRoll`, `actor.zs:111,1291`). Drive it during the entangle window, rate scaled by `pullSpeed` — harder yank, faster tumble. **Honest caveat, not yet verified**: whether vanilla sprite-based monsters render roll by default or need a `RFF_ROLLSPRITES`-family flag set (the constant exists, `constants.zs:1253`; I have not confirmed the default state or whether it needs a per-actor override). This is a one-grep verification item before relying on it, not a blocker — models would likely respect Roll regardless since it's a real transform component.

### 3.1 The Bulletstorm-into-chainsaw window

Two things make the follow-up combo actually work, not just look right:
1. **Aim the stop point in front of the player, not at the player's origin** — `owner.pos + ownerForwardDir * meleeRange`, so the enemy lands in swingable space instead of overlapping or landing behind you.
2. **A guaranteed vulnerability beat** — extend `reactiontime` on landing so there's a real window (tunable) where the entangled enemy can't immediately fight back, long enough to swing the chainsaw. This is the same mechanism Bulletstorm's leash gun depends on: the pull isn't just repositioning, it's *setting up a kill*, which requires the enemy be genuinely open for a beat, not just physically close.

---

## 4. VR Weapon Options — making the whip the first fully-tunable weapon

Following the confirmed real convention (§1.4), not inventing a new one. A dedicated `VRWhipOptions` submenu (via `Submenu` from the existing `VRWeaponOptions` menu, the same pattern already used at `menudef.txt:3332`), covering every tunable this report introduces plus what already existed:

```
// CVARINFO (user-scope, matches Sword/ShieldSaw convention exactly)
user int   vr_whip_profile          = 0;      // 0 Leather / 1 Ember / 2 Tesla
user float vr_whip_yank_force_scale = 1.0;     // entangle-yank strength multiplier
user float vr_whip_entangle_minspeed= 4.0;     // min pull speed to catch at all
user int   vr_whip_entangle_duration= 12;      // tics an enemy stays entangled
user float vr_whip_roll_speed_scale = 1.0;     // tumble rate multiplier
user bool  vr_whip_contextual_yank  = true;    // Fire-while-attached fast reel, on/off
user float vr_whip_reel_speed       = 22.0;
user float vr_whip_swing_pump       = 1.0;     // climb-to-pump-the-swing strength
user float vr_whip_crack_threshold  = 95.0;
user bool  vr_whip_two_hand_boost   = true;
```
Each backed by a `Slider`/`Option` MENUDEF entry with a `TFLV_Tooltip`, matching the working template the audit already produced. This is a genuinely large but entirely mechanical piece of work — no design risk, pure house-convention plumbing.

---

## 5. Engine-level feature — two honest tiers

**Tier A — ship today, pure ZScript, zero C++, zero rebuild risk.** Everything in §2, §3, §4 above uses only already-exposed APIs: `Actor.Mass`, `GetHandVelocity`, `special1`/`reactiontime`, `Roll`/`A_SetRoll`, `player.onground`, `Vel`. This can go straight into `vr_whip.zs` the same way every other feature this session has, and be in your hands the next time the build lane is clear.

**Tier B — the actual "engine-level feature" you asked to examine.** Right now this is one weapon's private logic. To make it a genuine *engine* capability other weapons/abilities could use:
- New `KEYWORDS.json` namespace `"entangle"` (mirrors the existing `"mass"`/`"climb"` namespace shape exactly — `keyword_dispatcher.cpp` already has the parser pattern to copy) with per-monster overrides like `entangle_resist` (so, say, incorporeal or flying enemies could be tagged immune) and `entangle_break_time`.
- Extend `KeywordProfile` with those fields (small, additive struct change, same shape as the existing `mass`/`climbable` fields).
- Export the **first** ZScript-facing Keywords query thunk — today literally none exist. This one addition (`DEFINE_ACTION_FUNCTION` wrapping a dispatcher query) would retroactively unblock every future system that wants to ask "what does this actor's keyword tag mean" from ZScript, not just entangle.

Tier B is a small, quiet-lane C++ patch (same risk profile as the Tier-2 model-bone patch already written and build-verified this session) — but it should come **after** Tier A is proven fun in-headset, not before. Building the generalized engine feature for a mechanic that hasn't been played yet is the wrong order of operations.

---

## 6. Recommendation

Build Tier A now — it's fully specified above, uses only proven-working APIs, and is genuinely less code than what's currently in `vr_whip.zs` (deleting the old unconditional REEL, not adding a parallel system). Get it in-headset. If the entangle-yank-into-melee combo feels as good as Bulletstorm's leash gun, *then* formalize Tier B so it stops being whip-only.

---

## 7. The reverse direction — getting hit, and catching what hits you

Follow-up ask: "I want to be kinetically affected when hit by monster attacks — does that need Mass/Keywords added to monster attacks? And is a 'grab bullet/monster projectile' thing wise to build?" Grounded in two more parallel research agents (2026-07-03) plus a direct verification grep of my own.

### 7.1 The kinetic-hit system already exists, engine-wide, unconditionally

`ApplyKickback` (`wadsrc/static/zscript/actors/interaction.zs:4-76`), `virtual` and called from every `DamageMobj` event (`p_interaction.cpp:1317-1321`, no exceptions found short of `DMG_THRUSTLESS`/`NODMGTHRUST` flags):

```
thrust = clamp((damage * 0.125 * kickback) / Mass, 0, 32)     // 32 u/tic hard ceiling, already built in
Vel += thrust in the direction of the hit
```

**The player gets identical treatment to monsters** — no dampening, no special-casing, no CVar reduction found anywhere (`p_interaction.cpp`, `player.zs` both checked). Mass=100 for the player, same value already verified in §1.1. **You are already being kinetically shoved by every hit, right now, with a hard cap already in place.** Nothing to invent for the base mechanic.

**One thing NOT verified — flagged honestly**: whether that `Vel` nudge is actually *perceptible* to a room-scale VR player, or gets silently absorbed/overridden by the VR locomotion pipeline before it registers. Needs an in-headset check, not assumed either way.

### 7.2 What's actually missing: attacks don't differentiate

`kickback` in the formula above comes from `inflictor.ProjectileKickback` if set, else `ReadyWeapon.Kickback`, else a single global `gameinfo.defKickback` (`interaction.zs:10-13`). **Direct grep confirms: zero monster attack classes in `wadsrc/static/zscript/actors/doom` set `ProjectileKickback`.** Every monster projectile in the game — Imp fireball, Cacodemon fireball, Revenant rocket, Mancubus blast — falls back to the same global default. A Revenant rocket and an Imp fireball push you with identical force per point of damage today.

**This answers the Mass/Keywords question directly: Mass — already there, nothing to add. Keywords — not in this pipeline at all, no new tagging system needed.** The actual gap is a **data-filling pass**: real infrastructure (`ProjectileKickback`), sitting unused, waiting for someone to put per-attack values in it. Small, low-risk, not a new system.

### 7.3 The pinball safeguard — where it actually lives

`ApplyKickback` is shared by every actor in the game — monsters hit each other through it too. **Do not touch it.** The velocity-ceiling/per-hit-clamp/diminishing-returns/damage-aware-taper safeguard (designed in response to: *"if I'm on the rope and take a fireball I wanna swing a little, but I don't want to pinball if I'm getting destroyed"*) belongs entirely inside `vr_whip.zs`'s own per-tic swing update, as a **re-clamp layer applied after** the native system does its normal thing:

- **Velocity ceiling while grappled** — clamp total `Vel` magnitude every tic while attached, independent of hit count.
- **Per-hit impulse cap** — clamp each individual hit's contribution before it's added, so one big hit can't single-handedly redline the swing.
- **Diminishing returns on rapid repeat hits** — a short window where a second impulse landing soon after the first contributes only partial force (standard anti-juggle-lock pattern).
- **Damage-aware taper** — scale the kinetic response down the more cumulative recent damage the player has taken; getting wrecked should read in the health bar, not as loss of physical control. This is a VR-comfort/safety design choice as much as a balance one — uncontrolled externally-forced motion is one of the worst things to do to a headset player.

The taut-line distance constraint already in the swing code (§ swing physics, prior sections) gives a first safeguard for free — a fireball can make you swing harder, but the rope's own max length already bounds how far you can ever be flung from the anchor, no extra code needed for that part.

### 7.4 "Grab a bullet/projectile" — already built, already on by default

The native gravity-glove system (`VR_UpdateGravityGloves`, `p_user.cpp:1767-1788` catch, `1498-1523` throw) **already lets the player snatch any live projectile out of the air with a hand grip, right now**:

- Catch gate: `actor.flags & MF_MISSILE` — universal, no whitelist, no Keywords, no per-type opt-out. Catches rockets, plasma, fireballs, BFG balls, archvile fire — anything missile-flagged.
- On catch: velocity zeroed, `NOGRAVITY` set, held in `vr_held_items[hand]`, optional haptic pulse + spark FX.
- On release: re-thrown using the same mass-scaled throw formula as any held item (§1.1's formula, reused directly).
- **CVars, all default ON**: `vr_allow_bullet_snatching` (true), `vr_catch_radius` (24 units), `vr_catch_haptic` (true), `vr_catch_spark` (true) — and it's already menu-exposed (`menudef.txt:3582,3588`).

**This needs zero new code to work with the whip** — it's a hand/glove mechanic, entirely independent of what weapon you're holding. If you're not already feeling this in-headset, it's worth explicitly checking it's not somehow disabled, since by every code path traced it should already be live.

**What it does NOT do**: no automatic "throw back at the original shooter" (release re-throws in your hand's motion direction, not at the source — the `target` field is set to the player for tracking, not redirection), and **zero ZScript exposure** — it's pure native C++, no hooks, no per-weapon customization, no way to intercept the catch event from a mod. A commented-out "Deflect!" branch exists in the source (`p_user.cpp:1805-1858`, explicit `Vel = -Vel`) but is dead, not shipping.

### 7.5 The better-fit extension point, if the whip should *actively* deflect (not just passively catch)

Catch/snatch is a **hand** mechanic — it works regardless of weapon. If the ask is instead "the whip itself should bat away incoming fire as a combat move" (closer to the sword's existing parry than to gravity-glove catching), that's a **different, already-proven system**: the weapon PARRY mechanic (`p_interaction.cpp:1638-1662`), which reverses projectile velocity (`Vel = -Vel * vr_parry_reflect_speed_mult`, default 1.5×) and — unlike catch — **is already Keywords-driven and ZScript-extensible**, per this session's earlier sword work (`parry_extent`, `parry_sound` per weapon via Keywords). Giving the whip a fast defensive crack that parries a projectile mid-flight would ride this existing, proven, mod-facing system rather than the closed native catch system. Flagging this as a related, not-yet-requested option — worth a decision, not assumed.

### 7.6 Tier A for this section

Everything in §7.3 (the rope-specific pinball safeguards) is pure ZScript inside `vr_whip.zs`, zero C++, ready to build now. §7.2 (differentiating attack kickback) is a small ZScript data pass over monster attack classes, also zero C++. §7.4 needs nothing built — verify it's live in-headset. §7.5 (whip parry) is a new design decision, not yet scoped.
