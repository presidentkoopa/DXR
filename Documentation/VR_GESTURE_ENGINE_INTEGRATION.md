# VR Gesture Engine — Integration Seams & Current State

**Audience:** the Gestures lane. **Purpose:** everything the gesture system can read from and
drive in the engine *today*, verified against source (file:line), plus the lane boundaries and
the deploy process so gesture work lands cleanly in the one shared build.

Project root: `E:\DoomXR-work\DOOM_FRESH` (the ONE real project — src + wadsrc\static + build all
live here; ignore `MASTER_BUILD`, `DoomXR\`, and the D: Steam copy — stale).

---

## 1. The gesture engine already exists (native scaffold)

- `src/playsim/vr_gesture.h` / `vr_gesture.cpp` — the native gesture engine.
  - Reads gesture defs, evaluates a per-hand recipe each tic, and when satisfied calls
    `Fire(player, def, hand)` → emits **`gesture_fired("<id>")`** to ZScript (`vr_gesture.h:138`).
- **Architecture (committed):** build ONE native detector; gestures themselves are **data**
  (`vr_gestures.json`). ZScript owns an action table keyed by the fired id. Target = 90 gestures
  as a data-driven build tree, not 90 code paths.
- **Your integration point:** a ZScript `StaticEventHandler` (or the existing gesture handler)
  that receives `gesture_fired(id)` and dispatches to the action for that id. Keep the actions in
  ZScript; keep detection in the JSON + native engine.

---

## 2. Engine INPUT seams — what a gesture can read (all native, ZScript-callable, VERIFIED)

| Call | Where | Returns / use |
|------|-------|---------------|
| `owner.GetHandVelocity(hand)` | `p_actionfunctions.cpp:5861` | per-hand velocity vector — **flicks / swings / thrusts** (tick deltas). |
| `pmo.GetGripValue(hand)` | `vmthunks_actors.cpp:2589` | grip trigger 0..1 — the **TRIGGER** half of a gesture (proximity filters, grip confirms). |
| `pmo.AttackPos` / `pmo.OffhandPos` | native fields | per-hand world position — **proximity FILTER** (near chest / hip / shoulder / other hand). |
| `pmo.OffhandDir` / `OffhandPitch` / `OffhandAngle` / `OffhandRoll` | native | off-hand orientation — **palm-out / palm-up pose gates** (e.g. cast gate on OffhandRoll). |
| `w.VR_GetWeaponHotspot(name)` | `p_user.cpp:2996` | world vec3 of an authored weapon bone: `hs_grip` `hs_foregrip` `hs_magwell` `hs_rack` `hs_port` `hs_breech` `hs_tank`. Gestures near a hotspot = weapon-relative gestures. |
| `player.vr_foregrip_engaged` / `vr_foregrip_world[3]` | `d_player.h:563-564` | off-hand is foregripping the weapon this tic + where. Use to **suppress** hand-gestures while two-handing. |
| `actor.LastHitZone` / `LastHitHand` | native `actor.h` fields | last damage zone (0 torso /1 head /2 chest /3 legs) + which hand dealt it — **hit-reaction gestures / combo triggers**. |
| `actor.GetHitZoneName()` / `GetHitHandName()` | `zscript/engine/vr_locational_damage.zs` | string form of the above. |
| Hardpoint queries: `IsHardpointNear`, `GetHardpointWorldPos`, `VR_HolsterHand` | native hardpoint system | shoulder/hip/wrist mount proximity — holster & draw gestures. |

**Grip / gesture ARBITER (critical — do not bypass):** hands are a shared resource. The native
grip arbiter publishes ownership per physical hand in `player.vr_grip_owner[hand]`
(`GRIP_NONE` / `GRIP_TWOHAND` / climb / whip / glove / hardpoint). A gesture that consumes a hand
MUST check the hand is free (or owned by a yielding system) before claiming it, and publish its
own ownership so two systems can't fire on the same squeeze. **Per design: the gesture arbiter is
an EXPANSION of this grip arbiter — reuse it, don't invent a parallel one.**

---

## 3. Engine OUTPUT seams — what a gesture can DRIVE (feedback, VERIFIED)

| Call | Where | Use |
|------|-------|-----|
| `level.SpawnSDFText(x,y,z,text,scale)` | `vmthunks.cpp:1214` | crisp MSDF world text — combo callouts, gesture-name popups. **Opt-in visual; keep gated.** |
| `level.AddGlowPanel(color,radius,x,y,z,type,...)` | `doombase.zs:429` | billboard glow primitive (type 14 neon). Particles are invisible in VR stereo — use this or sprite actors, NOT `A_SpawnParticle`. |
| `pmo.VR_HapticPulse(hand, strength, duration)` | native | controller rumble — gesture-confirm feedback. |

---

## 4. Recently landed (this session) that gestures can build on

- **Hand-to-hotspot IK pin** (`p_user.cpp`, `VR_UpdateArmIK`): the off-hand now snaps onto
  `hs_foregrip` when `vr_foregrip_engaged`. Gestures reading `vr_foregrip_engaged` get an
  authoritative "the support hand is committed to the gun" signal.
- **IQM weapon roster with hotspot bones**: all 12 weapons now carry `hs_grip` + `hs_foregrip`
  (+ per-style `hs_magwell`/`hs_rack`/`hs_port`/`hs_breech`/`hs_tank`). `VR_GetWeaponHotspot`
  returns real bone world positions — weapon-relative gestures are now possible.
- **Native locational damage** (`p_interaction.cpp`): 4 zones + `LastHitZone`/`LastHitHand`
  fields → hit-reaction and precision-bonus gestures.
- **Chest ammo pouch** (`vr_ammo_pouch.zs`): reach-to-chest keystone gesture is live (the pouch
  marker is now a wireframe box; toggle `vr_pouch_marker`).

---

## 5. Lane boundaries (so we don't clobber each other in the one folder)

**Gestures OWNS:** `vr_gesture.cpp/.h`, `vr_gestures.json`, and the gesture action-table zscript
(gesture handler). SDF/score/"party" presentation → the **Radiance** pk3, not the engine.

**Do NOT edit (other lanes, live):**
- `vr_ammo_pouch.zs`, the modeldef pouch section, the IK body path (`VR_UpdateArmIK`) — **my lane**.
- weapon `.zs`, weapon modeldef blocks, weapon `.iqm` (`hs_*`) — **Weapons lane**.
- the reload FSM (`VR_UpdateWeaponReload` in `p_user.cpp`) — **Reloadin' lane**.

**Shared, single-owner:** ONE `doomxr.pk3` and ONE `doomxr.exe`. **Do not repack the pk3 yourself**
— a concurrent repack truncated it once already. Hand pk3/exe deploys to the lane that owns the
repack, or coordinate first.

---

## 6. Deploy / rebuild (the one build)

- **Data** (json / zscript / assets) → lives in `wadsrc\static\`. Repack:
  `build\tools\zipdir\Release\zipdir.exe -f build\Release\doomxr.pk3 wadsrc\static`
  (`-f` forces a full clean archive; a partial/racing write leaves a truncated zip).
- **Engine** (C++ gesture detector) → `wadsrc\static`'s sibling `src\`. Rebuild:
  `cmake --build build --config Release --target zdoom --parallel`
  (cmake at `...\Microsoft Visual Studio\18\Community\...\CMake\bin\cmake.exe`).
- **Play:** the Radiance bat → `E:\DoomXR-work\DOOM_FRESH\build\Release\doomxr.exe`
  `-file <Radiance>.pk3 +vr_mode 15 +vid_preferbackend 1`.

---

*Verified seams carry a file:line. Architecture/design items (JSON-driven detector, arbiter
expansion, 90-gesture tree) are from the committed gesture-engine design + DoomXR_Design doc set.*
