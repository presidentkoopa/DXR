# DoomXR — VR Reload System Reference

> **Authoritative reference for how reloading works in this engine.** Grounded in the actual source as of
> 2026-07-04. Covers the two-layer architecture, the native state machine, the C++↔ZScript seam, every
> tuning knob, how to wire a new weapon, the landmines, and the roadmap.
>
> Companion docs: `RELOAD_JUICE_SPEC.md` (the canon feature roadmap), `VR_WEAPON_HANDLING_ENGINE_LEVEL.md`
> (the broader weapon-handling mandate), `VR_TWOHAND_GRIP_DETERMINISM_SPEC.md` (grip arbiter + two-hand).

---

## 0. TL;DR

Reloading in DoomXR is **physical**: in VR you reach to a neon pouch on your chest, grip to pull a magazine
into your hand, carry it to the gun, grip again to seat it, then yank the charging handle to chamber a round.
On flatscreen it falls back to a timed button-press reload.

It is built as **two cooperating layers**:

| Layer | Lives in | Owns |
|---|---|---|
| **Native FSM** (C++) | `src/playsim/p_user.cpp` → `VR_UpdateWeaponReload` | the *physical gesture* — where the mag is, seating, racking, chambering, timing, haptics |
| **ZScript** (mixin + pouch) | `zscript/engine/vr_manual_reload.zs`, `zscript/engine/vr_ammo_pouch.zs`, per-weapon `.zs` | the *fire-gate*, the *chamber count*, spawning mags, the eject bind, per-weapon states |

They meet at a small, well-defined **seam** (§3). Neither layer reaches past it.

**Two master toggles gate the whole thing:**
- `vr_new_weapon_handling` — gates the **native FSM** (the physical gesture). Off ⇒ the C++ never runs.
- `vr_manual_reload` — gates the **ZScript** (the chamber fire-gate, the pouch, the eject). Off ⇒ vanilla reload.

Both default **on**. Turn either off and you get progressively more-vanilla behavior with zero crashes.

---

## 1. Why two layers?

The split follows the DoomXR engine-level mandate: **anything that needs runtime C++ (hand transforms, per-tic
gesture tracking, writing engine state) is native; everything content-shaped (what a mag *is*, what firing
costs, per-weapon flavor) is ZScript.**

- The FSM needs the **VR hand transforms** every tic (`vrm->GetWeaponTransform`) and reads **weapon hotspot
  bones** — neither is cheaply or safely doable from ZScript. So the gesture is native.
- The chamber count, the dry-click, the eject bind, and "which magazine model does this gun pull" are pure
  content decisions that mods will want to override — so they're ZScript on the weapon.

The payoff: the ZScript layer can ship and change **without a rebuild** (it only feeds the already-compiled
FSM), while the gesture physics stay fast and authoritative in C++.

---

## 2. The native FSM (the heart)

**Function:** `VR_UpdateWeaponReload(player_t*)` — `src/playsim/p_user.cpp:2504`, called once per tic from
`P_PlayerThink` (`p_user.cpp:1668`), a peer of `VR_UpdateHardpoints`.

### 2.1 Entry gates (in order, all must pass)
1. `vr_new_weapon_handling` on (else return — master toggle).
2. `player && player->mo`.
3. `(player - players) == consoleplayer` — **local player only** (single-player; desync guard).
4. `VRMode::IsVR()` — **flatscreen bails here** (flatscreen uses the classic ZScript button reload instead).
5. On weapon switch, the runtime resets and **clears the handling style to `RS_NONE`** so a non-reload weapon
   can never inherit `RS_BOXMAG` and read a chamber field it doesn't have (crash-fix, §8).
6. `player->vr_weapon_handling.style == RS_BOXMAG` — **only a weapon that called
   `AssignWeaponHandling("boxmag")` proceeds.** Everything else returns immediately.
7. `magSize = weap->IntVar(NAME_XRMagSize)` must be `> 0`.

### 2.2 The states — `EVReloadState` (`d_player.h:525`)

```
VRRL_READY  →  VRRL_EMPTY / VRRL_MAG_OUT  →  VRRL_MAG_IN  →  VRRL_RACKED  →  VRRL_READY
```

| State | Meaning | Leaves when |
|---|---|---|
| `VRRL_READY` | loaded, idle | `chamber <= 0` → `VRRL_EMPTY` |
| `VRRL_EMPTY` | chamber dry, waiting for a mag at the gun | a held `xr_mag` item is within `hs_magwell` radius **and** you grip (rising edge) → seat |
| `VRRL_MAG_OUT` | **reserved hook** — a mag ejected but a round still chambered (tactical); shares EMPTY's seat logic | *(nothing sets this yet — it's the pre-built slot for tactical 1-in-barrel, §9)* |
| `VRRL_MAG_IN` | mag seated, waiting for a rack | grab within `hs_rack` radius + pull back along the barrel ≥ `vr_reload_rack_travel` → chamber |
| `VRRL_RACKED` | round chambered | one-tic settle → `VRRL_READY` |

### 2.3 Per-state logic (what actually happens, and why)

Each tic the FSM looks at *which state you're in* and runs only that one state's block. Every gesture is
**edge-triggered** — it fires on the moment a grip goes from released→pressed, not while it's held — so one
squeeze is exactly one action and holding a button never repeats or double-fires.

**A full reload, tic by tic (the happy path):**
1. You fire the last round → `A_XR_TryFire` drops `XRChamber` to 0. The next tic, `VRRL_READY` sees
   `chamber <= 0` and flips to `VRRL_EMPTY`.
2. `VRRL_EMPTY` starts watching both hands for a magazine. You reach to your chest, the pouch spawns one into
   your hand (§5), and you carry it to the gun.
3. The instant the mag enters the magwell's radius **and** you squeeze grip, it **seats**: the mag actor is
   destroyed, a `reload_seat` haptic thumps, state → `VRRL_MAG_IN`.
4. `VRRL_MAG_IN` waits for you to grab the charging handle (`hs_rack`) and pull it *back along the barrel*.
   Pull far enough and the round **chambers**: `VR_ReloadRefill` re-arms `XRChamber`, a hard `reload_chamber`
   haptic fires, state → `VRRL_RACKED`.
5. `VRRL_RACKED` is a single settling tic → `VRRL_READY`. You're loaded.

Now the per-state detail:

**`VRRL_EMPTY` / `VRRL_MAG_OUT` — the seat.**
- Resolve the magwell's world position from the weapon (`VR_WeaponHotspotWorld(weap, NAME_hs_magwell, …)`).
- **Magnetic assist (forgiveness aid):** if a held `xr_mag` item is in the *outer ring* — twice the seat
  radius — and `vr_reload_assist > 0`, the FSM gently lerps the mag toward the magwell each tic. VR reach is
  imprecise, so this soft magnet makes seating feel *reliable* without feeling *automatic*. It only ever moves
  the **mag** (an item); it never touches your pawn's position.
- **The seat itself:** once the mag is inside the inner `vr_reload_magwell_radius` **and** grip crosses a
  *rising edge* (a fresh press), the FSM destroys the mag, sets `vr_reload_mag_seated`, advances to
  `VRRL_MAG_IN`, and fires the `reload_seat` haptic (70). The rising-edge requirement is why the grip you were
  already holding to *carry* the mag from the pouch doesn't instantly seat it — you have to re-squeeze at the gun.
- **Auto-chamber shortcut:** if `vr_reload_chamber` is **off**, seating alone finishes the reload — the FSM
  calls `VR_ReloadRefill` and jumps straight to `VRRL_READY`, skipping the rack. That's the one-motion reload
  for players who don't want the two-beat rack.

**`VRRL_MAG_IN` — the rack.** The rack is a *directional* gesture, not just "move your hand":
- The FSM computes `back` = the reverse of your main hand's forward vector (i.e. straight back down the barrel).
- When you grab within `vr_reload_rack_radius` of `hs_rack` on a grip rising edge, it **latches** that hand as
  the rack hand (anchoring where you grabbed) and fires the `reload_rack` haptic (40). Let go and it unlatches.
- While latched it measures how far your hand has moved *in the backward direction* via a dot product,
  `(handPos − anchor) · back`, and keeps the **maximum** reached. Using the projected distance is what makes a
  sideways wiggle *not* count — only genuine backward pull along the barrel accumulates — and keeping the max
  means a single smooth pull still registers even if tracking jitters mid-motion.
- Hit `vr_reload_rack_travel` and the round goes live: `VR_ReloadRefill`, `vr_reload_chambered = true`,
  advance to `VRRL_RACKED`, fire the hard `reload_chamber` haptic (90).

**`VRRL_RACKED`.** A single settling tic → `VRRL_READY`. It exists so the transition is clean and the chamber
haptic gets its own frame to land before the gun is "ready" again.

### 2.4 The refill — `VR_ReloadRefill` (`p_user.cpp:2486`)
```cpp
reserve = ammo->IntVar(NAME_Amount);           // the player's total rounds (the ONE true resource)
loaded  = min(reserve, magSize);
weap->IntVar(NAME_XRChamber)    = loaded;       // C++ WRITES the ZScript field
weap->BoolVar(NAME_XRReloading) = false;
```
No reserve deduction — reserve already counts the loaded rounds; the chamber is just a sub-limit re-armed to
whatever total you still have.

### 2.5 Haptic beats (already native)
Three of the four "rhythm" beats fire inside the FSM via `VR_HapticEvent`:
`reload_seat` (70) · `reload_rack` (40, on grab) · `reload_chamber` (90). The fourth (the **eject clunk**) is
the ZScript side (§4.3). Position arg is `hand==0 ? 1 : 2` (1=left, 2=right).

---

## 3. The seam — how C++ and ZScript talk

The two layers are deliberately kept at arm's length: they share **no objects and make no direct calls into
each other's code.** Everything passes through the tiny, fixed set of touchpoints below. That narrowness is the
whole point — as long as these ~8 touchpoints stay stable, the ZScript half can be rewritten and shipped
*without recompiling the engine*, and the C++ half can change internally without breaking the weapons.

The mechanism that makes it work is **`IntVar` / `BoolVar` / `PointerVar`** — a C++-only reflection API that
lets native code read *and write* a ZScript object's fields by name at runtime (e.g. `weap->IntVar(NAME_XRChamber)`).
ZScript cannot go the other way like this — those accessors don't exist in ZScript, and trying to use them
there is a boot crash (§8) — so ZScript reaches back into C++ through purpose-built native functions instead
(`AssignWeaponHandling`, `VR_TrySetHeldItem`). Net: **C++ pokes ZScript fields by reflection; ZScript pokes C++
through named natives.** Nothing else crosses the line.

Read the three tables below as the *complete wiring diagram* — if a wire isn't here, it doesn't exist. Both
directions:

### 3.1 C++ **reads** ZScript (via `AActor::IntVar`/`BoolVar`/`PointerVar` — a C++-only reflection API)
| Read | From | Purpose |
|---|---|---|
| `weap->IntVar(NAME_XRMagSize)` | the mixin field | magazine capacity + the "is this a reload weapon" gate |
| `weap->IntVar(NAME_XRChamber)` | the mixin field | how many rounds the fire-gate believes are loaded |
| `weap->PointerVar<AActor>(NAME_Ammo1)` | the weapon | the reserve ammo actor (the true resource) |
| `held->Keywords.IndexOf("xr_mag")` | the spawned mag | recognizing a held item as a magazine |

### 3.2 C++ **writes** ZScript
| Write | Effect |
|---|---|
| `weap->IntVar(NAME_XRChamber) = loaded` | re-arm the chamber after a physical reload |
| `weap->BoolVar(NAME_XRReloading) = false` | clear the reloading flag |

### 3.3 ZScript **feeds** C++
| Call | Effect |
|---|---|
| `AssignWeaponHandling("boxmag")` | sets `vr_weapon_handling.style = RS_BOXMAG` — **the gate that lets the FSM run for this weapon** |
| `VR_TrySetHeldItem(hand, mag)` | puts a mag into `player_t::vr_held_items[hand]` — the **exact slot** the FSM's seat loop scans |
| the mixin sets `XRChamber` / `XRReloading` | the fire-gate + eject state the FSM reads |
| the `"xr_mag"` keyword on the mag actor | the recognition token the seat loop matches |

**That's it.** No other coupling. If you understand this table you understand the system.

---

## 4. The ZScript mixin — `XR_ManualReload`

File: `zscript/engine/vr_manual_reload.zs`. A weapon gets the whole reload contract by adding
`mixin XR_ManualReload;` at the top of its class.

**What a mixin buys us.** The arsenal doesn't share a common "reloadable weapon" base class — Pistol, BFG,
Flamethrower, etc. all descend from stock `DoomWeapon`/`Weapon`, and we don't want to fork that hierarchy. A
`mixin` solves exactly that: it's a reusable block of fields + methods *grafted* onto any class that names it,
with no inheritance relationship required. So one `mixin XR_ManualReload;` line stamps the same chamber state
and the same fire/reload/eject hooks onto all 14 weapons — and any **mod** weapon that adds the same line
inherits the whole system for free. It's the unit of reuse that makes "wire a new weapon" (§10) a five-line job.

### 4.1 Fields
| Field | Meaning |
|---|---|
| `int XRChamber` | rounds currently loaded (the fire-gate resource) |
| `int XRMagSize` | capacity |
| `bool XRReloading` | true while a reload is running |
| `string XRMagClass` | which pouch magazine class this weapon pulls (unused by the current pouch, which maps by `w is`) |

### 4.2 The ammo model (important, subtle)
- **`Ammo1` (reserve) is the only true resource** — it drains normally per shot via the weapon's existing
  `DepleteAmmo`, unchanged.
- **`XRChamber` is a sub-limit** — how many of those reserve rounds can fire before a reload is required.
- Firing drops **both** together; reload just re-arms the chamber from the current total. **No separate reserve
  deduction, no refund logic** — the rounds were always counted in the total. This is what keeps the existing
  fire code correct and makes the toggle-off path exactly vanilla.

**Worked example.** A rifle with a 30-round mag and 90 rounds in reserve (`Ammo1.Amount = 90`, which *includes*
the 30 loaded). Fire 30 shots — each shot drops both counters — and you land at `XRChamber = 0`, `reserve = 60`.
Reload: `VR_ReloadRefill` sets `XRChamber = min(30, 60) = 30` and does **not** touch reserve, because those 30
were always part of the 60. Empty it again → `XRChamber = 0`, `reserve = 30`; reload → `XRChamber = 30`,
`reserve = 30`. Reload with only 12 rounds left → `XRChamber = min(30, 12) = 12`, a partial mag, exactly as
you'd expect. The chamber never invents or destroys ammo — it only caps how much of the reserve is firable
*right now*.

### 4.3 Methods
| Method | Kind | What it does |
|---|---|---|
| `XR_InitChamber(magSize)` | fn | set capacity + fill chamber to `min(magSize, reserve)`. Call once from `Ready`/`Select`. |
| `XR_ManualReloadEnabled()` | fn | reads `vr_manual_reload`; default true |
| `A_XR_CheckChamber(stateReload)` | action state | if chamber empty & not reloading, return the `Reload` state (auto-route). Call as a 0-tic action in `Ready`. |
| `A_XR_TryFire()` | action bool | **the fire-gate.** Chamber>0 → decrement, return true. Empty → dry-click, return false. Toggle-off → always true (vanilla). Weapons gate their `Fire` state on this. |
| `A_XR_StartReload()` | action | set `XRReloading = true` (on-demand reload entry) |
| `A_XR_RefillChamber()` | action | flatscreen/fallback refill: chamber = `min(magSize, reserve)`, clear reloading. Call near the END of a timed `Reload` state. |
| `A_XR_EjectToPouch()` | action state | **the VR eject.** See below. |

### 4.4 `A_XR_EjectToPouch` — the reload bind in VR
Called as the **first line** of a weapon's `Reload` state. Branches on context:
- Toggle off, **or flatscreen** (`!player.PlayInVR`), **or** `vr_pouch_eject` off → returns `null` ⇒ the
  weapon's own **timed** `Reload` beat runs (with `A_XR_RefillChamber` at the end).
- In VR with eject on → sets `XRChamber = 0` (mag out ⇒ FSM enters `VRRL_EMPTY` ⇒ the pouch opens), plays the
  eject clunk, fires the **eject haptic** (`VR_HapticPulse`, strength × `vr_reload_haptic`), and returns the
  `Ready` state. The physical grab from the pouch finishes the reload — **not** this state.

So one bind does the right thing in both modes: eject-and-go-physical in VR, timed-beat on flatscreen.

---

## 5. The chest pouch — the keystone

File: `zscript/engine/vr_ammo_pouch.zs`. `XRAmmoPouch : StaticEventHandler` (`WorldTick`).

**Why it's the keystone:** the FSM only *seats* a mag you're already holding. Nothing else ever puts one in
your hand. The pouch is the front half — reach your chest, grip, and it spawns the right mag straight into
`vr_held_items[hand]`, the exact slot the FSM reads. Pure ZScript, feeds the compiled FSM, **no rebuild.**

**The mental model:** think of a reload as *spawner → carrier → seater*. The pouch is the **spawner** — a
world-level handler that runs every tic, independent of any weapon. Your hand is the **carrier**. The FSM is the
**seater**. The two halves never call each other; they meet at one shared array, `vr_held_items[hand]` — the
pouch writes a mag into it, the FSM reads a mag out of it. That single slot is the *entire* handoff, which is
exactly why the spawner can be pure ZScript while the seater is compiled C++.

### 5.1 Flow each tic
1. Local VR player only; gated on `vr_manual_reload`.
2. Pick the magazine class from the ready weapon via safe **runtime** checks (`w is "Chaingun"` etc. — never
   `IntVar`/`StringVar`, which don't exist in ZScript, §8):
   - Chaingun → `XRMag_Chaingun` · PlasmaRifle → `XRMag_Plasma` · Shotgun/SSG → `XRMag_Shell` ·
     BFG/RocketLauncher → `XRMag_Pod` · Incinerator/CalamityBlade/Flamethrower → `XRMag_Can` ·
     Rifle/SMG/Pistol/Revolver → generic `XRReloadMag` · anything else → **not a pouch weapon, bail.**
3. Compute a **body-relative chest anchor** from `pmo.pos` + facing, tunable via `vr_pouch_height` (40),
   `vr_pouch_forward` (0), `vr_pouch_radius` (18).
4. Draw a neon marker there (`AddGlowPanel`, wgType 14) unless `vr_pouch_marker` is off.
   *(Particles are invisible in the VR stereo pass — glow panels are the correct VR-visible primitive.)*
5. For each hand: get `AttackPos`/`OffhandPos`, check `GetGripValue(hand) > 0.5` on a **rising edge**; if the
   hand is in the pouch radius, `Spawn(magCls)` and `VR_TrySetHeldItem(hand, mag)` (destroy on full hand),
   then a pouch-grab haptic (`VR_HapticPulse`, × `vr_reload_haptic`).

**Why these choices:** the grip is checked on a *rising edge* so holding the button doesn't spawn a stream of
mags every tic — one squeeze, one mag. The anchor is *body-relative* (recomputed from your pawn's position and
facing each tic) so the pouch travels with you and sits at your chest rather than a fixed point in the world;
it's fully CVar-tunable because every player's headset height and arm length differ, so you dial the reach-in
zone to your own body from inside the headset. And the marker is a **glow panel, not a particle**, because
particles don't render in the VR stereo pass (§8) — a glow panel is the correct VR-visible primitive.

### 5.2 The magazine actors
`XRReloadMag : Actor` — invisible base sprite (`TNT1`), visible body from `modeldef.txt`, flags
`+NOGRAVITY +NOBLOCKMAP +NOINTERACTION +DONTSPLASH`, **`Keywords "xr_mag"`** (the load-bearing token).
Subclasses per ammo type: `XRMag_Chaingun`, `XRMag_Plasma`, `XRMag_Shell`, `XRMag_Pod`, `XRMag_Can` — each
binds its own model in modeldef.

---

## 6. Hotspots

The FSM reads three named points on the weapon via `VR_WeaponHotspotWorld(weap, NAME_hs_*, out)`:
- **`hs_magwell`** — where a mag seats (EMPTY state).
- **`hs_rack`** — where you grab to rack (MAG_IN state).
- **`hs_foregrip`** — the two-hand support point (used by the two-hand system, not reload).

Resolution: if the weapon's IQM model has an authored bone of that name, the world transform of the bone is
used; otherwise a **geometric default** is computed. **Gotcha:** `VR_WeaponHotspotWorld` writes `out` even
when it returns `false` (the geometric fallback), and the reload FSM does **not** check the return — so
MD3-only weapons still get sensible seat/rack points. (Only the two-hand foregrip checks the `false` return.)
Hotspot bones are authored by the IQM batch builder (`tools/weapon_iqm_build/`).

---

## 7. Tuning — the CVar reference

### 7.1 Master toggles
| CVar | Default | Gates |
|---|---|---|
| `vr_new_weapon_handling` | on | the **native FSM** (physical gesture) + the keyword two-hand |
| `vr_manual_reload` | on | the **ZScript** chamber fire-gate + the pouch + the eject bind |

### 7.2 Pouch (ZScript, `CVARINFO`)
| CVar | Default | Meaning |
|---|---|---|
| `vr_pouch_height` | 40.0 | chest anchor height above pawn origin |
| `vr_pouch_forward` | 0.0 | forward offset along facing |
| `vr_pouch_radius` | 18.0 | reach-in radius + marker size |
| `vr_pouch_marker` | true | draw the neon chest marker |
| `vr_pouch_eject` | true | reload bind ejects (pouch reloads) vs. full timed auto-reload |
| `vr_reload_haptic` | 1.0 | rumble strength multiplier for seat/rack/eject (0 = off) |

### 7.3 FSM gesture (native, `EXTERN_CVAR` in `p_user.cpp:139-143`; tuned via the VR menu)
| CVar | Meaning |
|---|---|
| `vr_reload_magwell_radius` | how close the mag must be to `hs_magwell` to seat |
| `vr_reload_assist` | 0–1 magnetic pull of the mag toward the magwell in the outer ring (0 = off) |
| `vr_reload_chamber` | **on** = require a rack to chamber; **off** = auto-chamber on seat (no rack) |
| `vr_reload_rack_radius` | how close a hand must be to `hs_rack` to grab it |
| `vr_reload_rack_travel` | backward pull distance required to chamber |

### 7.4 Debug overlay (ZScript, `CVARINFO`; `vr_reload_debug.zs`)
| CVar | Default | Meaning |
|---|---|---|
| `vr_reload_debug` | off | MASTER — draw 3D wireframe debug boxes at the reload reach zones |
| `vr_reload_debug_hands` | on | green boxes on both controllers |
| `vr_reload_debug_clips` | on | cyan boxes on every held magazine |
| `vr_reload_debug_pouch` | on | white box at the chest pouch anchor |
| `vr_reload_debug_hotspots` | on | magenta/yellow/orange magwell/rack/foregrip boxes (needs the hotspot getter — §9, §13) |
| `vr_reload_debug_scale` | 1.0 | size multiplier for the debug boxes |

All of the above are exposed in the **`VRReloadOptions`** menu (`menudef.txt`), linked from VR Weapon Options,
with the full tuning + debug set on its **`VRReloadAdvanced`** sub-page (see §13).

---

## 8. Landmines (read before touching this)

- **ZScript has NO `IntVar`/`StringVar`/`FloatVar`.** Those are C++ `AActor` reflection only. Using them in
  ZScript is a **hard boot-compile crash** (this exact bug crashed the pouch once). Read a mixin field off a
  base `Weapon` ref via a concrete cast (`Rifle(w).XRChamber`) or gate with `w is "Name"`. The pouch uses
  `w is` for exactly this reason.
- **The style gate must run before the field read.** The FSM checks `style == RS_BOXMAG` *before*
  `IntVar(NAME_XRMagSize)`, and clears the style to `RS_NONE` on weapon switch — otherwise a non-mixin weapon
  would read a field it doesn't have and crash. Keep that ordering.
- **Don't call action functions from the pouch handler.** A `StaticEventHandler` isn't a state context;
  `A_StartSound` etc. will fault. Use `VR_HapticPulse` (safe, non-action) and `Level.AddGlowPanel`.
- **Particles are invisible in VR.** Any reload FX must be a glow panel / SDF / sprite actor, never
  `P_SpawnParticle`.
- **The pk3 does not auto-rebuild on a ZScript change** (CMake DEPENDS gap). Force `zipdir` or a clean build,
  or the packaged pk3 keeps stale script.
- **`consoleplayer`-gated:** the FSM is local-player-only by design (single-player). Fine here; relevant only
  if netplay is ever revisited.

---

## 9. Roadmap — the canon juice + what's reserved

The full feature roadmap is `RELOAD_JUICE_SPEC.md`. Architecture notes for it:

**Already reserved in the enum** (`EReloadStyle`, `d_player.h:524`), name-mapped and FSM-wired only for
`boxmag` so far:
```
RS_NONE, RS_BOXMAG, RS_SHELL, RS_BREAK, RS_INTERNAL, RS_POD, RS_CANISTER
```
Adding a style = (a) map its name in `vmthunks_actors.cpp` (§ `AssignWeaponHandling`), (b) add its sub-machine
to the FSM switch, (c) `AssignWeaponHandling("<style>")` on the weapon. `VRRL_MAG_OUT` is likewise a **pre-built
state hook** waiting for the tactical "1-in-the-barrel" eject (push state to `MAG_OUT`, keep chamber at 1).

**Build order (C++ first, then ZScript — the low-rework path):**
- **A. State-observation getters** — expose `vr_reload_state` / a perfect-timing flag / the last beat to
  ZScript. *The keystone:* the whole ZScript juice layer reads these to know when to flair/pop/glow.
- **B. New styles** — `RS_SHELL` (shell-by-shell), cylinder + speedloader, `RS_POD`, heat-vent. Each is its
  own sub-state-machine; design the gesture contract on paper first.
- **C. Perfect-timing window** — timestamp seat→rack, set a flag.
- **D. Abort hook** — `VR_AbortReload` for fumble-under-damage + reload-cancel.
- **E. Toss-catch** — inverted-gun ∩ falling-mag seat branch in EMPTY.
- **then** the ZScript juice (mag mass, eject-glow, trails, PERFECT popup, throw-the-mag) hangs off the frozen
  contract and just decorates known beats.

Tactical-1-in-barrel and whip-catch are *mostly ZScript* riding on the `MAG_OUT` hook and the existing seat
loop (whip drops an `xr_mag` item into `vr_held_items` → the FSM seats it).

---

## 10. Wire a new weapon for reload (recipe)

1. `mixin XR_ManualReload;` at the top of the weapon class.
2. In `Ready`: init the chamber once, and gate the auto-route:
   ```
   Ready:
       XXXX A 0 { if (invoker.XRMagSize == 0) invoker.XR_InitChamber(<capacity>); }
       XXXX A 1 A_WeaponReady(WRF_ALLOWRELOAD);
       Loop;
   ```
3. In `Select`: declare the native style so the FSM runs for this weapon:
   ```
   Select:
       XXXX A 1 { A_Raise(); AssignWeaponHandling("boxmag"); }
       Loop;
   ```
4. Gate the `Fire` state on the chamber:
   ```
   Fire:
       TNT1 A 0 A_JumpIf(!A_XR_TryFire(), "Ready");   // dry-click when empty
       ... normal fire frames ...
   ```
5. Add the `Reload` state (VR eject → pouch; flatscreen → timed beat):
   ```
   Reload:
       XXXX A 0 A_XR_EjectToPouch();   // VR: eject → Ready (pouch reloads); flatscreen: falls through
       XXXX A 30;                      // flatscreen timed beat
       XXXX A 15 A_XR_RefillChamber(); // flatscreen refill
       Goto Ready;
   ```
6. (Optional) Keywords: `grip:<style>` for two-hand feel; the pouch already maps common classes to mag models.
7. Force a pk3 rebuild (§8). No C++ change needed — the FSM is already compiled.

`weaponbfg.zs` is the canonical worked example.

---

## 11. Weapon roster (14 wired, as of 2026-07-04)

Carry the mixin + fire-gate + `AssignWeaponHandling("boxmag")` + a `Reload` state:

Rifle · Pistol · SMG · Chaingun · PlasmaRifle · Shotgun · SuperShotgun · Revolver · BFG9000 · RocketLauncher ·
Flamethrower · ID24Incinerator · ID24CalamityBlade · M79 (keeps its own break-open anim reload; uses the
fire-gate but not `A_XR_EjectToPouch`).

Not wired (no magazine concept / no IQM): Chainsaw, ShieldSaw, HandGrenade, Fist, and the melee/tool weapons
(Sword, Whip, IceHook).

---

## 12. File map

| Path | Role |
|---|---|
| `src/playsim/p_user.cpp:2504` | `VR_UpdateWeaponReload` — the native FSM |
| `src/playsim/p_user.cpp:2486` | `VR_ReloadRefill` — the chamber write |
| `src/playsim/d_player.h:524-541` | `EReloadStyle`, `EVReloadState`, the `vr_weapon_handling` + `vr_reload_*` fields |
| `src/scripting/vmthunks_actors.cpp:2360` | `AssignWeaponHandling` — style-name → enum |
| `zscript/engine/vr_manual_reload.zs` | the `XR_ManualReload` mixin |
| `zscript/engine/vr_ammo_pouch.zs` | the chest pouch + `XRReloadMag` mag actors |
| `zscript/actors/doom/weapon*.zs`, `id24/*.zs` | the 14 wired weapons |
| `wadsrc/static/CVARINFO` | pouch + haptic CVars |
| `wadsrc/static/menudef.txt` → `VRReloadOptions` / `VRReloadAdvanced` | user-facing options + the Advanced debug/tuning page |
| `wadsrc/static/modeldef.txt` | mag + weapon + debug wirebox model bindings |
| `zscript/engine/vr_reload_debug.zs` | the debug wireframe-box overlay (§13) |
| `wadsrc/static/models/debug/wirebox.obj` + `wirebox_*.png` | the debug box model + 6 colour skins |

---

## 13. Debug overlay — seeing the reach zones

The reach targets are invisible, so `vr_reload_debug.zs` draws **real 3D wireframe-cube models** at them to line
up gestures in the headset. (`AddGlowPanel` shapes are flat *camera-facing billboards* — glow, not geometry — so
a model is used instead.)

**The model.** `models/debug/wirebox.obj` — a unit cube built from 12 thin edge-tubes (true wireframe). Six
solid-colour skins (`wirebox_{green,cyan,magenta,yellow,orange,white}.png`) give one modeldef class per colour
(`XRWireBoxGreen` …), each an invisible `TNT1` actor with the model bound, rendered `+BRIGHT` / additive.

**The handler.** `XRReloadDebug : StaticEventHandler` (mirrors the `vr_hardpoint_markers.zs` persist +
`bDestroyed`-check pattern) spawns/moves one box per target each tic and scales it (`Scale=(edge,edge)`, uniform).

| Box | Target | Source | Status |
|---|---|---|---|
| 🟢 green | both hands | `AttackPos` / `OffhandPos` | works now |
| 🔵 cyan | held clips | `ThinkerIterator` over `XRReloadMag` | works now |
| ⚪ white | chest pouch anchor | mirrors `vr_ammo_pouch.zs` math | works now |
| 🟣 magenta | `hs_magwell` | native `VR_GetWeaponHotspot` | staged |
| 🟡 yellow | `hs_rack` | native `VR_GetWeaponHotspot` | staged |
| 🟠 orange | `hs_foregrip` | native `VR_GetWeaponHotspot` | staged |

**Why hotspots are staged:** ZScript can't read a hotspot's world position (§6, §8) — only the C++ FSM can. The
unlock is a ~12-line `VR_GetWeaponHotspot(name)` native, written + commented at the bottom of
`vr_reload_debug.zs`; uncomment the draw block once it lands in the Phase-1 rebuild.

**Data-only.** Hands/clips/pouch are pure ZScript + model — they ride in on a pk3 repack, no C++ compile.

**Menu — `VRReloadAdvanced`** (`VR Options → Manual Reload & Ammo Pouch → Advanced`): a power page with all debug
toggles + box size, every reach-assist/forgiveness slider (assist, magwell/rack/hotspot/foregrip radii, rack
travel), pouch-fit sliders, haptics, and **Forgiving / Realistic** one-tap presets (multi-CVar `SafeCommand`).

---

## 14. Glossary

- **FSM** — Finite State Machine. The reload is always in exactly one state (READY/EMPTY/MAG_IN/RACKED) and
  moves between them when a specific gesture happens. `VR_UpdateWeaponReload` is it.
- **Chamber** — `XRChamber`: rounds currently loaded and firable before a reload is required. A sub-limit of
  the reserve, not a separate resource.
- **Reserve** — `Ammo1`: the player's total round count, the only true resource, drains per shot as vanilla.
- **Seat** — bringing a magazine to `hs_magwell` and gripping to insert it.
- **Rack** — grabbing `hs_rack` and pulling back along the barrel to chamber a round.
- **Style** — `EReloadStyle`: which reload sub-machine a weapon uses. Only `RS_BOXMAG` is wired today.
- **Hotspot** — a named point on the weapon (`hs_magwell`/`hs_rack`/`hs_foregrip`), from an IQM bone or a
  geometric default.
- **The seam** — the ~8 calls/reads in §3 that are the entire contract between the C++ and ZScript layers.
