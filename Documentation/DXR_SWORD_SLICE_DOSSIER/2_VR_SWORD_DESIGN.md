I have everything I need from the grounding and the three facet designs. This is a synthesis task â€” no further file reads required since the facets already cite the engine surfaces. Let me write the decision-ready doc.

# VR Sword â€” Weapon / Blade-Profile Design Doc

*Engine: DoomXR (presidentkoopa/DoomXR-2.0-The-Wired), repo root `E:/DoomXR-work/DOOM_FRESH`. All file:line cites are read-only references; shader/model-lane items are flagged.*

---

## 1. Concept & the split

There is exactly **ONE** sword weapon â€” a `VRSword : Weapon` subclass â€” that owns everything about **motion, gating, collision, damage application, and feel**. It never knows what blade it is wearing. What it *is* wearing is a **`BladeProfile`**: a plain data object (`extends Object`, held by reference, zero actor overhead) that supplies only **data** â€” model, length, glow, trail, sounds, damage type/curve, and behavior-flag bits â€” plus **one** virtual code hook for irreducible damage math. Swapping a steel SWORD for a LIGHTSABER for the Dragon's TOOTH is done by changing a single `Class<BladeProfile>` reference (CVar-backed) and re-binding; **adding a new blade = author one data subclass in a mod .pk3, zero edits to `VRSword`**. The cut-surface VFX (how a sliced monster renders) is *not* in this weapon â€” it is an integration seam (`OnBladeContact` / `onSliceCallback`) handed to a separate cut-render track.

---

## 2. Swing â†’ hit pipeline

**Where it runs.** The hit scan lives in `VRSword.Tick()` (per-gametic, animation-independent), **not** in PSprite attack frames â€” a long anim frame must never starve the swept-collision check. PSprite states are cosmetic pose + which sounds/flashes fire; the HIT SCAN is a `Tick()`-driven thinker. VR swings are physical, so there is no button-driven attack frame required (a button may still trigger a scripted flourish).

**The per-tic blade segment.** Each tic the weapon reconstructs the blade as a world-space segment:
- `base = bOffhandWeapon ? owner.OffhandPos : owner.AttackPos`  â€” `actor.zs:272` / `:276`
- `dir` from `AttackAngle/AttackPitch/AttackRoll` (`actor.zs:273-275`), or the `AttackDir()` callback (`actor.zs:861`)
- `tip  = base + dir * profile.effectiveLength`

These are readonly, **VR-updated every gametic** in the VR SetUp path â€” `src/common/rendering/hwrenderer/data/hw_vrmodes.cpp:893-920` (per-tic AttackPos/AttackDir/AttackAngle write). Our `Tick()` reads them post-update.

**Swing velocity â€” DERIVED, not native.** Hand/swing velocity is **NOT exposed to ZScript**. `actor.zs:272-279` exposes only `AttackPos/OffhandPos` + angles â€” no velocity field. (It *does* exist in C++ via `OpenVRMode::GetHandVelocity()` at `src/rendering/gl/stereo3d/gl_openvr.cpp:3034-3048`, reading `pose.vVelocity`, but is not bridged to ZScript.) So we cache `prevBase/prevTip` each tic and difference:
```
baseVel  = base - prevBase
tipVel   = tip  - prevTip          // TIP moves fastest â†’ the true "sword speed"
tipSpeed = tipVel.Length()          // u/tic; Ã— TICRATE(35) â†’ u/sec
swingDir = tipVel.Unit()
```
**Gate on TIP speed, not hand/base speed** â€” a wrist flick barely moves the hand but whips the tip. First-tic guard: seed `prev = cur`, skip scan. Discontinuity guard (teleport/level-change/weapon-swap): if `tipSpeed > TELEPORT_CLAMP` (~400 u/tic) reseed and skip.

**Swing-speed gate (hysteresis).** Two thresholds on tip speed so a mid-arc slowdown doesn't drop the cut:
- `SWING_ON` (~35 u/tic â‰ˆ 1225 u/s) arms a cut â†’ `SWINGING`
- `SWING_OFF` (~18 u/tic) stays live until tip speed falls below â†’ `IDLE`

Both are CVars (`vr_sword_swingon` / `vr_sword_swingoff`) â€” felt values are tuned in-headset by the user, not hand-edited. Taps/pokes below `SWING_ON` never cut. A **thrust/pierce gate** (`dot(tipVel, bladeDir) > THRUST_ON`) exists in the model but ships **OFF by default** (swing-only) per the no-unprompted-balance rule.

**Continuous (swept) collision â€” no tunneling.** `tipSpeed` can exceed a monster's radius in one tic, so a point-in-time check tunnels. Three layers:

- **(A) Broad phase** â€” `BlockThingsIterator.CreateFromPos(cx,cy,cz, checkh, checkradius, false)` (`doombase.zs:225`) **anchored at the blade segment midpoint** (an arbitrary world point) â€” *not* the player actor, because the hand is decoupled from the body. `checkradius = segmentHalfLength + tipTravel*0.5 + bladeRadius`. Filter: `bIsMonster || bShootable`, `!bCorpse` (unless a `carveCorpses` profile flag), `health>0`, not already in this swing's hit set.
- **(B) Narrow phase** â€” conservative **tic substepping**: `N = clamp(ceil(tipSpeed / (minMonsterRadius*0.5)), 1, 8)`. Lerp base/tip between prev and cur at each substep; test closest-point distance(segment, actor cylinder axis) `<= actor.radius + bladeRadius`. Pure ZScript, no engine patch. First satisfying substep = contact substep.
- **(C) Optional precision ray** â€” `Actor.LineTrace(...)` (`actor.zs:808`) from the interpolated base along `bladeDir` for `effectiveLength`; read `FLineTraceData.HitLocation/HitActor/HitDir` (`actor.zs:49-56`). Gives the exact contact point **and cleanly rejects monsters behind walls** (trace stops on geometry). Falls back to (B)'s closest-point if it disagrees.

**Contact â†’ cut position + cut-plane (the slice-track seam).** For each newly-hit actor this swing, emit a `BladeHitContact`:
```
hitPos        = LineTrace.HitLocation (if valid) else closest-point on blade at contact substep
bladeDir      = (tip - base).Unit()               // blade long axis
swingDir      = tipVel.Unit()                      // direction the edge travels
cutNormal     = (swingDir CROSS bladeDir).Unit()   // SLICE-PLANE normal
                // degenerate |cross|~0 (pure thrust) â†’ cutNormal = swingDir, tag PIERCE
cutPlanePoint = hitPos
incomingSpeed = tipSpeed                            // drives severance strength
contactKind   = KIND_SLICE | KIND_PIERCE
hand          = 0 main / 1 offhand
```
This record is the **only** thing handed to the slice/VFX track, via `virtual void OnBladeContact(Actor victim, BladeHitContact c)`. The weapon guarantees all six fields are correct and in world space; the slice track owns voxel/model-swap/shader.

**Damage + per-target cooldown.** On confirmed contact: `victim.DamageMobj(owner, owner, dmg, profile.damageType, dmgFlags)`, where `dmg = base * speed-scale (clamped)` then `dmg = profile.ModifyDamage(victim, dmg, hand)`. A per-swing "already hit" set (+ tic-stamped re-arm window, ~10 tics) stops machine-gun multi-hits on one pass while allowing a deliberate re-cut. Special behaviors (armor-ignore, energy type) ride entirely on the profile's `damageType` + `DMG_*` flags + `DoSpecialDamage` override (`actor.zs:520`) â€” the pipeline just forwards them.

**Per-hand state machine:** `IDLE â†’ (tipSpeed>SWING_ON) â†’ SWINGING â†’ (tipSpeed<SWING_OFF) â†’ IDLE`; `DISCONTINUITY â†’ reseed, force IDLE, no scan`. Trail/hum cosmetics gate on `SWINGING`.

---

## 3. Blade Profile schema

Reconciled from the two facet schemas into one shipping schema. `extends Object`; held by reference on `VRSword`; read every tic. One virtual (`ModifyDamage`) plus the optional `DoSpecialDamage`-routing fields; everything else is data.

```cpp
class BladeProfile   // extends Object â€” pure data + one virtual; lives on VRSword by ref
{
    // ---- IDENTITY ----
    string profileName;          // menu/HUD label
    string profileTag;           // localizable ($BLADE_*)
    Color  rarityColor;

    // ---- VISUAL ----
    name   bladeModel;           // MODELDEF entry, swapped via A_ChangeModel(name, modelindex)
    name   billboardSprite;      // fallback / energy bloom for non-model blades
    double bladeLength;          // map units â€” drives BOTH visual scale AND reach
    double bladeWidth;           // sweep radius contribution
    Color  glowColor;            // neon emission (NO dynamic light â€” GITD constraint)
    double glowRadius;
    int    trailStyle;           // TRAIL_NONE | STEEL_ARC | ENERGY_RIBBON | PARTICLE_STREAK
    Color  trailColor;
    class<Actor> trailActor;     // optional per-tic spawned trail actor
    name   extendAnim, retractAnim;  // MODELDEF named anims via SetAnimation (IQM named-anim path)
    int    growTimeTics;         // 0 = instant show; >0 = grow-on-draw ramp

    // ---- AUDIO (SNDINFO FULL paths â€” DoomXR full-path trap; must be MONO â€” stereo silent on desktop) ----
    string sndIdleHum;           // CHANF_LOOPING on CHAN_BODY while ready
    string sndSwing;             // whoosh, gated on swing speed (pitch/vol scalable)
    string sndHitFlesh, sndHitHard;
    string sndIgnite, sndRetract;
    string sndCut, sndKill;

    // ---- COMBAT ----
    name   damageType;           // 'Melee' | 'Energy'/'Fire' | 'Nano'
    int    baseDamage;
    // swingSpeedCurve: two points, weapon lerps derived tipSpeed between them
    double minSwingSpeed, speedDamageFloor;
    double maxSwingSpeed, speedDamageCeil;
    int    segmentSamples;       // LineAttack samples hilt->tip (fallback path)
    int    cutMode;              // CUT_SLASH | CUT_PIERCE | CUT_ENERGY
    double reach;                // 0 => use bladeLength
    class<Actor> puffType;
    class<Actor> impactPuffFlesh, impactPuffHard;
    class<Actor> bloodOverride;  // None = no blood

    // ---- SPECIAL-BEHAVIOR FLAGS (bitfield) ----
    int    behaviorFlags;        // BF_DEFLECT|BF_IGNOREARMOR|BF_CAUTERIZE|BF_IGNITE|BF_GROWSONDRAW|BF_SCORCHWALLS|BF_DISMEMBER
    double armorPierceFrac;      // 0..1 (consumed by DoSpecialDamage routing)
    double instaKillHealthFrac;  // >0 => below this target HP frac, guaranteed kill (non-boss)
    name   dismemberStyle;       // 'gib' | 'burn' | 'clean' -> 748 viscera / HF_ReactionHandler
    name   onSliceCallback;      // seam name handed to the cut-render track

    // ---- THE ONLY CODE A PROFILE MAY ADD ----
    virtual int ModifyDamage(Actor target, int damage, int hand) { return damage; }
}

// enums / flag consts
const BF_DEFLECT=1; const BF_IGNOREARMOR=2; const BF_CAUTERIZE=4;
const BF_IGNITE=8; const BF_GROWSONDRAW=16; const BF_SCORCHWALLS=32; const BF_DISMEMBER=64;
enum ECutMode { CUT_SLASH, CUT_PIERCE, CUT_ENERGY };
enum ETrail   { TRAIL_NONE, TRAIL_STEEL_ARC, TRAIL_ENERGY_RIBBON, TRAIL_PARTICLE_STREAK };
```

**Worked example â€” Dragon's Tooth:**
```cpp
class Blade_DragonsTooth : BladeProfile
{
    override void Init()
    {
        profileName="Dragon's Tooth"; profileTag="$BLADE_DTOOTH";
        rarityColor=Color(255,60,140,255);
        bladeModel='DTOOTH_KATANA'; bladeLength=46; bladeWidth=3;
        glowColor=Color(255,70,140,255); glowRadius=10;
        trailStyle=TRAIL_ENERGY_RIBBON; trailColor=glowColor;
        extendAnim='Grow'; growTimeTics=24;                 // ~0.7s molecule-by-molecule unfurl
        sndIdleHum="";                                       // silent, eerie
        sndSwing="weapons/dtooth/hiss"; sndHitFlesh="weapons/dtooth/cut";
        sndIgnite="weapons/dtooth/grow"; sndKill="weapons/dtooth/kill_chime";
        damageType='Nano'; baseDamage=200; segmentSamples=5;
        minSwingSpeed=8;  speedDamageFloor=1.0;              // speed-INDEPENDENT (both 1.0)
        maxSwingSpeed=40; speedDamageCeil=1.0;
        cutMode=CUT_SLASH; reach=0;                          // reach = bladeLength
        armorPierceFrac=1.0; instaKillHealthFrac=1.0; dismemberStyle='clean';
        behaviorFlags = BF_IGNOREARMOR | BF_GROWSONDRAW | BF_DISMEMBER;
    }
    override int ModifyDamage(Actor t, int dmg, int hand)
    {
        if (t.health > 0 && !t.bBoss && !t.bNoDamage) return t.health + 1; // one-touch kill, non-boss
        return dmg;
    }
}
```

---

## 4. The three blades as pure data

| Field | **Steel Sword** | **Lightsaber** | **Dragon's Tooth** |
|---|---|---|---|
| `bladeModel` | `BladeSteel` | `BladePlasma` (Add, +BRIGHT) | `BladeNanoCrystal` (translucent blue) |
| `bladeLength` / reach | 40 | 52 | 46 |
| `bladeWidth` (radius) | 6 | 4 | 3 (razor-thin) |
| `growTimeTics` | 0 | 10 (~0.3s ignite) | 24 (~0.7s grow-on-draw) |
| `damageType` | `Melee` | `Fire` (energy) | `Nano` |
| `baseDamage` | 18 | 45 | 200 |
| swingSpeedCurve | **wide** 0.6â†’2.4 (HEFT) | flat 1.0â†’1.6 | flat 1.0â†’1.0 (speed-independent) |
| `armorPierceFrac` / `ignoreArmor` | 0 / false | 0.5 / false | 1.0 / **true** |
| `instaKillHealthFrac` | 0 | 0 | 1.0 (non-boss) |
| `glowColor` / radius | none / 0 | ~(60,160,255) / 28 | (70,140,255) subtle / 10 |
| `trailStyle` | STEEL_ARC (thin smear) | ENERGY_RIBBON (bright) | ENERGY_RIBBON (faint whisper) |
| `sndIdleHum` | none | `saber/hum` (looping) | none (silent) |
| `dismemberStyle` | `gib` | `burn` | `clean` |
| behavior flags | DISMEMBER | DEFLECT+CAUTERIZE+IGNITE+SCORCH+DISMEMBER | IGNOREARMOR+GROWSONDRAW+DISMEMBER |
| **Signature special** | Material-branch clang: hard/wall contact â†’ spark puff + `sndHitHard` shove-back | **Projectile deflection**: manual segment-vs-`+MISSILE` scan reverses velocity + reassigns source | **Armor-ignore one-touch kill** via `ModifyDamage`/`DoSpecialDamage`; molecule grow-on-draw |
| **VR feel** | **HEFT** â€” must physically commit a fast full-arm chop; lazy waves whiff | **PRESENCE + AGENCY** â€” living hum shifts with hand motion; swat a fireball out of the air with your own hand | **RITUAL LETHALITY** â€” watch blue shards assemble the blade, then calmly *touch* an enemy and they drop |

All three are **pure data instances of the one schema.** Only Dragon's Tooth needs the `ModifyDamage`/`DoSpecialDamage` override; Steel and Saber are flags + fields only.

---

## 5. Feel & feedback

- **Damage curve** â€” `dmg = lerp(speedDamageFloor..speedDamageCeil, invlerp(tipSpeed, minSwingSpeed..maxSwingSpeed))`, clamped, computed by the weapon from **derived tip speed** (Â§2). Steel's wide curve gives the "you must swing it" heft; Saber/Tooth flatten it (energy/contact weapons don't care about force).
- **Material branch** â€” flesh hit â†’ `impactPuffFlesh` + `sndHitFlesh`; wall/`+NOBLOOD` hit â†’ `impactPuffHard` + `sndHitHard` (+ scorch/scratch decal). Uses the LineAttack return + hit-wall detection already in the melee path.
- **Trail / glow** â€” `trailStyle` spawns `A_SpawnParticleEx` (`actor.zs:1229`) or `trailActor` along the swept path per tic. Glow uses the GITD-safe path â€” additive particles + `level.AddGlowPanel(...)` (pattern at `engine/vr_weapon_logic.zs:84`). **No dynamic lights** (hard GITD constraint). **No shader file edits required** for any of the three blades â€” flagged clean against the reserved shader lane.
- **Sound** â€” looping hum: `A_StartSound(sndIdleHum, CHAN_BODY, CHANF_LOOPING)` (`actor.zs:1202`), stopped on lower. **Two DoomXR audio traps apply:** SNDINFO must resolve by **full path** (`"weapons/dtooth/hum"`), and all these SFX must be **MONO** â€” stereo downmix is `__MOBILE__`-only, so a stereo hum is silent on the user's desktop `xr shader\doomxr.exe`.
- **Saber projectile-deflect** â€” each tic, scan the swept blade segment via `BlockThingsIterator`; for any `+MISSILE` within `bladeWidth` of the segment, reflect velocity (about `cutNormal`, or bounce toward shooter), set `target = player` as new source, play deflect SFX. **No native reflect exists** â€” this is a manual weapon-side test the profile only toggles with `BF_DEFLECT`. *Decision needed: reflect all missiles vs enemy-only, mirror vs bounce-to-shooter (see Â§7).*
- **Hit-stop / haptics** â€” **no native ZScript VR rumble hook exists** (confirmed gap). `ApplyContact` should emit a haptic **request** via the same channel the offhand-reload / recoil path uses (CVar or netevent). Crisp per-contact rumble would want a small **C++ `A_VRRumble(intensity, dur)` patch** â€” flag for the engine lane. Hit-stop (brief tip-speed damping / a 1-tic freeze feel) is a cosmetic add, deferrable.

---

## 6. MVP build order

Shortest path to *swing â†’ damage â†’ swap cosmetic*, cheapest first. **All ZScript, no shader-lane edits, no C++ required for MVP.**

1. **`VRSword : Weapon` with a Tick() segment scan** â€” file `wadsrc/static/zscript/weapons/vr_sword.zs` (new, my lane). Build base/tip from `AttackPos`+angles (`actor.zs:272-279`), derive `tipSpeed`, apply the `SWING_ON/SWING_OFF` gate, run **broad phase only** (`BlockThingsIterator.CreateFromPos`, `doombase.zs:225`) + a single closest-point test, `DamageMobj` on contact with a per-swing hit set. PSprite = a simple Ready-loop. *Result: swinging a bare segment damages a monster in VR.*
2. **`BladeProfile` data class + `BindBlade()`** â€” same file or `vr_blade_profile.zs`. Hardcode `Blade_Steel` first; read `bladeLength/baseDamage/damageType`. *Result: the blade's reach/damage now come from data.*
3. **Cosmetic swap** â€” `A_ChangeModel(activeBlade.bladeModel, modelindex:1)` (`actor.zs:1235`) + `sndIdleHum` loop on bind. Add `Blade_Saber` and `Blade_DragonsTooth` as data instances; wire a CVar `vr_sword_blade` + re-`BindBlade()`. *Result: same weapon wears steel / saber / tooth by changing one CVar.* **âš  Reserved model-lane check:** confirm the psprite supports a second `modelindex` for the blade vs needing a separate attached actor â€” verify with the model/shader-lane owner before committing to `modelindex:1` (needs MODELDEF entries for the three blades authored in that lane).
4. **Swept substepping + LineTrace precision** â€” upgrade narrow phase to N-substep closest-point (Â§2B) and optional `LineTrace` (`actor.zs:808`) for the contact point; emit the `BladeHitContact` record and call `OnBladeContact`. *Result: no tunneling on fast swings + the slice-track seam is live.*
5. **Feel pass** â€” swing-speed damage curve, material-branch puffs/sounds, trail spawns, and the two per-profile specials (Saber deflect scan; Tooth `ModifyDamage` one-touch + `DoSpecialDamage` armor-ignore at `actor.zs:520`).

**Dependencies flagged for other lanes:**
- **Model/MODELDEF + shader lane (RESERVED â€” read-only for me):** the three blade MODELDEF entries, the `Grow` extend animation ladder, and any custom crystalline/scorch **slice shader** if the cut-render track wants one (that *would* touch `.fp` â€” flag then).
- **C++ engine lane:** native hand velocity is **not** bridged (we derive from `AttackPos` deltas â€” works today); native **VR haptics** hook is absent (`A_VRRumble` patch wanted for crisp feedback); a true **per-molecule voxel grow** would need a C++/voxel-assembly patch (the model-scale + accretion-particle version ships in pure ZScript now, reusing `VoxelParticle` at `effects/vr_voxel_assembly.zs:1-37`).
- **IQM:** named animations only (`Grow`/`Ignite`/`Retract` via `SetAnimation`) â€” **no ZScript bone read/write**, so no procedural blade bending.
- **Cut-render / gore lane:** consumes `OnBladeContact` + `dismemberStyle` ('gib'/'burn'/'clean') through the existing 748 viscera / `HF_ReactionHandler` pipeline â€” not built here.

---

## 7. Open questions / risks

1. **Tic-phase ordering (verification build).** Does `AttackPos/OffhandPos` update on the **same** gametic phase as `Actor.Tick()`, or could our `Tick()` read a 1-tic-stale pose? Needs an in-engine confirm of ordering between `hw_vrmodes` SetUp (`hw_vrmodes.cpp:893-920`) and `Actor.Tick()` in `P_PlayerThink`. If stale, the cache is off by one tic (consistent, just latent) â€” acceptable but worth knowing.
2. **Substep cap vs ultra-fast swings.** `N=8` may not cover a Mach1-class tip (memory references ~333 u/tic). If playtest shows tunneling on the fastest human swings, switch narrow phase to an analytic swept-capsule-vs-cylinder solve instead of sampling. **Verify in headset.**
3. **Felt thresholds are tuning, not spec.** `SWING_ONâ‰ˆ35` / `SWING_OFFâ‰ˆ18` u/tic, `dmgscale`, and `bladeWidth` (esp. Tooth=3, may whiff on hand tremor) are **starting estimates** the user dials in-headset via CVars â€” not balance decisions I make.
4. **Saber deflection scope (decision).** Reflect **all** `+MISSILE` (incl. player's own) or **enemy-only**? Reflect-**back-to-shooter** vs **mirror-about-blade-normal**? Friendly-fire + target reassignment need a call.
5. **Dragon's Tooth one-touch scope (decision).** `instaKillHealthFrac=1.0` = kill-everything-on-contact. Confirm **non-boss only** (exclude `+BOSS`/`+NODAMAGE`) and whether it needs a cooldown so it isn't a room-wide instant-clear.
6. **Grow-on-draw fidelity (decision + possible engine patch).** Is the **model-scale + accretion-particle** version (ships now, pure ZScript) sufficient for the "molecule-by-molecule" read, or does the user want the true **per-voxel C++ assembly** patch (the one item that needs engine work)?
7. **Model-attach path (reserved-lane confirm).** Does a weapon psprite support a **second model index** for the blade, or must the blade be a **separate attached actor**? Confirm with the model/shader-lane owner before `modelindex:1`.
8. **Haptics scope (decision + possible patch).** Per-contact rumble now or deferred? If now, likely a small **C++ `A_VRRumble`** patch since no ZScript hook exists.
9. **Dual-wield / persistence.** One blade per hand (main vs offhand `VRSword` instance) or a single global choice? Determines whether `BindBlade` reads a **hand-indexed** CVar.
10. **Blade definition format (decision).** Ship blades as ZScript subclasses (keeps the `ModifyDamage` virtual) or a JSON/data-lump like `doomxr_weapons.json` (add blades with *zero* ZScript, but lose the virtual)? Recommend **ZScript subclass** â€” the one code hook is worth it, and only Dragon's Tooth actually uses it.

---

**Bottom line for the MVP:** steps 1â€“3 above (one new ZScript file, `AttackPos`-derived swing, `BlockThingsIterator` broad phase, `A_ChangeModel` cosmetic swap) get a working VR blade that damages a monster and swaps between steel/saber/tooth **with no shader edits, no C++, no IQM bone work**. Everything harder (substepping, deflection, grow-on-draw voxels, haptics, the slice-render seam) layers on top without touching the core split.
