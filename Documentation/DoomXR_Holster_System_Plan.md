# DoomXR - VR Holster System: Robust Implementation Plan

> Target engine: DoomXR 4.14.2 (active VR path = **OpenXR**, `src/gl/stereo3d/gl_openxrdevice.cpp` â€” NOT the legacy OpenVR sibling).
> Deliverable: documentation only. Every load-bearing claim below is grounded to `file:line` from a source-level audit and adversarially re-verified by a red-team pass. Where the red-team found a fatal issue, it is folded into the plan, not papered over.

---

## 1. Vision + the two hard requirements

**Vision.** The player reaches to a body/head-anchored zone (default: two shoulder slots, one per hand), grips, and a weapon is **drawn into that hand**; reaching back and gripping **stows** it. Holster locations are shown as **in-world billboard markers** that highlight as a hand approaches. The whole thing is tunable live, in-headset, by the player.

**Two hard requirements (non-negotiable):**

1. **Toggle-visible.** The player can turn holster markers on/off at will (`vr_holster_show` / per-slot `hol_<n>_visible`). Cosmetic-only; never affects sim.
2. **Player-adjustable placement.** The player can move/resize/re-angle each holster live via menu sliders **and** a physical grip-drag calibration, and the values persist across sessions.

Everything else (draw/stow payload, throw-draw) is built on top of these two, but the two requirements are what the architecture is optimized to satisfy first and cleanly.

---

## 2. Engine grounding â€” what already exists

| Capability | Where | State |
|---|---|---|
| **Holster config tag** `FVRTaxonomy::holster_slot` | `src/playsim/vr_config.h:21`; parsed `vr_config.cpp:103` from `keywords.db.json` | **Inert.** Written into the taxonomy struct, **read nowhere** in `src/`. A bare string tag. |
| Taxonomy attach-at-spawn | `src/playsim/p_mobj.cpp:5058` (`actor->vr_taxonomy = FVRConfig::GetTaxonomy(...)`), field `actor.h:793` | Populated, **never consumed**. `FVRTaxonomy` is an opaque forward-decl (`actor.h:785`), no `DEFINE_FIELD` â†’ **invisible to ZScript**. |
| Per-hand world pose | `AttackPos`/`OffhandPos` written per tic `gl_openxrdevice.cpp:622-638`; ZScript native readonly `actor.zs:273,277` | **Reachable in play-scope ZScript.** |
| Per-hand orientation | `AttackAngle/Pitch/Roll`, `OffhandAngle/Pitch/Roll` `actor.zs:274-280` | Reachable. |
| Hand velocity binding | `DEFINE_ACTION_FUNCTION(AActor, GetHandVelocity)` `p_actionfunctions.cpp:5748`; decl `actor.zs:866` | Reachable â€” the **template** for any new pose thunk. |
| Grip bits â†’ input | `BT_VR_LGRIP=1<<29`,`BT_VR_RGRIP=1<<30` `d_event.h:78-79`; ORed into `ucmd.buttons` `g_game.cpp:851-852` | Readable via `player.cmd.buttons` (`usercmd_t.buttons`@0 inside `ticcmd_t.ucmd`@0, `d_protocol.h:64-73,241-245`). |
| C++ grip ladder | `VR_UpdateClimbing`/`GravityGloves`/`CalculateTwoHanding` `p_user.cpp:1435-1449`; grab pipeline `1461-1670` | **C++-only.** `vr_held_items`/`vr_grab_candidate`/`vr_hand_state`/`vr_is_climbing` are `player_t` fields `d_player.h:473-488` with **no ZScript binding**. |
| ZScript PlayerThink seam | invoked `p_user.cpp:1426-1430` **before** the grip ladder (`1435`) | The tic-order hook point. |
| Dual-wield per-hand weapons | `ReadyWeapon`/`OffhandWeapon` native writable `player.zs:3137-3139`; `BringUpWeapon` routes by `bOffhandWeapon` `player.zs:1977-1988`; `DropWeapon(hand)` `player.zs:2082-2097` | **Draw/stow is pure ZScript.** |
| In-world billboard marker | `VRDamageCounter`/`VRDamageHandler` `vr_damage_counters.zs:1-110` â€” shipping proof of a `+FORCEXYBILLBOARD` actor glued per-tic via `SetOrigin`, managed by a `StaticEventHandler` | Reusable 1:1. |
| VR menus + CVAR persistence | `VRWeaponOptions` `menudef.txt:3064-3105`; slider auto-write `OptionMenuSliderCVar.SetSliderValue â†’ SetFloat` `optionmenuitems.zs:934-940`; `CVAR_ARCHIVE\|CVAR_GLOBALCONFIG` auto-persist `hw_vrmodes.cpp:435-443` | Reusable 1:1. |
| ZScript CVAR write | `CVar.GetCVar(name, players[consoleplayer]).SetFloat(...)` `gitd_presets.zs:50-62` | Proven. |
| Net-safe menuâ†’play seam | `EventHandler.SendNetworkEvent` `events.zs:225` â†’ `NetworkProcess/NetworkCommandProcess` `events.zs:201-202` | Proven. |
| Play-scope eye Z? | `player.viewz` native `player.zs:3116` **BUT** set by `CalcHeight` (flatscreen height) `player.zs:707`, **never** by the VR device | **NOT the VR eye Z** â€” see Red-Team RT-1. |

**Bottom line on the existing scaffolding:** `holster_slot` is a dead string tag, unreachable from ZScript, keyed by class name, reloaded once at init (`d_main.cpp:4048`). It is a poor home for per-player live placement. The plan therefore treats the holster system as **greenfield** and puts placement in **CVARs**, keeping `holster_slot` only as an optional "which slot does this weapon prefer" hint if we later bind it.

---

## 3. Architecture

### 3.1 Zone model â€” recommendation: **body-anchored first, head-pose thunk as the accurate upgrade**

Two candidate anchors:

- **Head-anchored via C++ thunk (accurate, deferred).** A `GetHeadPos()`/`GetHeadAngles()` thunk returns the real HMD world point (`r_viewpoint.CenterEyePos` remapped `(X,Z,Y)` + `vr_vunits_per_meter` scale, mirroring `GetHandVelocity`). This is the only way to get a zone that tracks the head independent of body/turn yaw and sits at the true eye Z.
- **Body-anchored fallback (ships day one, pure ZScript).** Anchor = `(player.mo.pos.XY, Z-anchor)` with yaw = `player.mo.Angles.Yaw`. Justified because **body XY already tracks the HMD**: room-scale positional movement drives `mo.Vel` â†’ `P_XYMovement` every tic (`gl_openxrdevice.cpp:695-716`). So `player.mo.pos.XY` *is* the HMD ground position. Zone yaw = torso yaw, which is what you want for **shoulder** holsters anyway.

**Recommendation:** ship **body-anchored**, add the head thunk only if in-headset testing shows the shoulder drifts when the player turns their head without turning their body. This is captured in Build Order.

**Zone geometry (both anchors):** sphere test, orientation-free â€” `inZone = (handPos - center).Length() < radius`, using `AttackPos`/`OffhandPos` **directly** (they are already remapped and scaled, which sidesteps the axis-swap/unit-scale traps). Slot center = `anchorXY + yaw-rotated(sideOff, backOff)` and `Z = anchor.Z - downOff`.

**Critical Z-frame rule (RT-1, folded in):** do **not** trust `player.viewz` as VR eye Z. To keep the highlight self-consistent, **derive the marker Z and the hand-test Z from the same reference frame.** Concretely: place `markerPos` with a body Z plus a player-tunable `downOff`, and test `|AttackPos âˆ’ markerPos|`. Absolute height is then a *tuned offset*, not a physically exact eye height â€” but marker and hand live in one frame, so the highlight never mis-fires vertically. The head thunk (`GetHeadPos`) is the only exact fix and is optional v1.

### 3.2 Detection / draw / stow

State machine per hand in a `PlayerPawn.PlayerThink` override (`player.zs:1734`, runs before the C++ ladder at `p_user.cpp:1426-1430`):

- `holsterState[2] âˆˆ {IDLE, ARMED, DRAWN}`, `wasGrip[2]`, `drawnWeapon[2]`.
- Grip read: local consts `BT_VR_LGRIP=(1<<29)`, `BT_VR_RGRIP=(1<<30)` (not in the ZScript `BT_` enum); `grip = (player.cmd.buttons & bit) != 0`; edge = `grip && !wasGrip[h]`.
- **DRAW** (pure ZScript, confirmed): `weapon.bOffhandWeapon = (h==1)`; `player.PendingWeapon = weapon`; `player.mo.BringUpWeapon()` â€” routes to `OffhandWeapon`/`ReadyWeapon` (`player.zs:1977-1988`), mirroring the existing draw-into-hand pattern `player.zs:1015-1016`.
- **STOW** (pure ZScript, confirmed): `DropWeapon(h)` (`player.zs:2082-2097`) kicks the down-state; for instant stow, null `player.OffhandWeapon`/`ReadyWeapon` after (writable, `player.zs:1012`). Weapon stays in inventory; no `CreateTossable` needed for an abstract holster. *(Caveat: instant null skips the down animation â€” defer the null until the psprite bottoms out if animation is wanted.)*
- **Throw-draw variant:** on in-zone grip-edge, if `GetHandVelocity(h).Length() > threshold`, tag the draw for the throw subsystem.

### 3.3 The VISIBLE-toggle mechanism

- `HolsterVisibilityHandler : StaticEventHandler` holding `Array<HolsterMarker>`, mirroring `VRDamageHandler` (`vr_damage_counters.zs:58-110`), incl. `WorldTick` null-cleanup.
- Read `CVar.GetCVar("vr_holster_show", players[consoleplayer]).GetBool()` (`vr_sdf_procedural.zs:55-56`). True + empty â†’ spawn N markers; false â†’ `Destroy()` them.
- `HolsterMarker : Actor`, `+NOBLOCKMAP +NOGRAVITY +DONTSPLASH +NOINTERACTION +NOTIMEFREEZE +FORCEXYBILLBOARD`, `RenderStyle "Add"`. Sprite via `GetSpriteIndex("HOLS")`, frame 0 (`actor.zs:701`). Each `Tick()`: recompute slot point, `SetOrigin(pos, true)`, scale from `vr_holster_scale`, highlight when `min(|AttackPosâˆ’pos|,|OffhandPosâˆ’pos|) < vr_holster_highlight_dist` via `SetShade` (`actor.zs:712`) + alpha/scale bump.
- **Spawn markers for `players[consoleplayer]` only.** Markers are cosmetic; they never touch the sim (no `MF_SOLID`/`MF_SHOOTABLE`, no touch/pickup).

### 3.4 The player-ADJUST mechanism â€” recommendation: **sliders + physical grip-drag calibration**, both writing one CVAR store

**Slot model.** A slot = one holster (default 2: shoulder L/R). Per slot, archived user-scoped floats: `hol_<n>_ox/oy/oz` (offset meters, anchor-relative), `hol_<n>_radius`, `hol_<n>_yaw/pitch`, plus bool `hol_<n>_visible`; global bool `hol_show_all` and `vr_holster_show`.

- **Path A â€” live sliders (zero code beyond decls).** `VRHolsterOptions` OptionMenu cloned 1:1 from `VRWeaponOptions` (`menudef.txt:3064-3105`). Each `Slider "...","hol_0_oy",...` auto-writes via `SetSliderValue â†’ SetFloat` (`optionmenuitems.zs:934-940`); `CVAR_ARCHIVE|CVAR_GLOBALCONFIG` auto-persists. `Option "Visible","hol_0_visible","OnOff"` + `Option "Show Holsters","hol_show_all","OnOff"` satisfy requirement 1. A `resetcvar` `SafeCommand` row resets a slot.
- **Path B â€” physical grip-drag calibration (marquee).** A play-scope holster `EventHandler`. Menu `Command` fires `SendNetworkEvent("hol_calibrate", N)` â†’ arrives at `NetworkCommandProcess`. In calibrate mode, wait for an off-hand grip near the slot anchor; each held tic compute `offset = rotate(OffhandPos âˆ’ headAnchor, âˆ’yaw)`, converting map-unitsâ†’meters by `/vr_vunits_per_meter` (=34) and undoing `/pixelstretch` on Z, mirroring `gl_openxrdevice.cpp:622-624`; on release commit the floats via `CVar...SetFloat` into the **same** cvars Path A drives, so both paths compose.

### 3.5 Persistence

**Tier A (all player-adjustable values):** `CVAR_ARCHIVE|CVAR_GLOBALCONFIG` user-scoped cvars, one set per slot. Auto-persist to config on write; auto-reload at launch. **Zero new C++**, no save/load call. Declared in **CVARINFO** with greenfield names (`hol_*`, `vr_holster_*`) to avoid the fatal "cvar already exists" redeclare trap (`CVARINFO:9-13`). This is the entire persistence loop for both requirements.

**Tier B (per-weapon "preferred slot" tag, optional):** stays in `holster_slot`/`keywords.db.json`, C++-read-only, reloaded once at init â€” used only to name *which* slot a weapon defaults to, never for live placement. Only touched if we later bind a `GetHolsterSlot` menu accessor (template exists: `DEFINE_ACTION_FUNCTION(DMenu, GetVRWeaponArchetype)` `vr_weapon.cpp:247`).

---

## 4. Per-subsystem feasibility

| Subsystem | Badge | Smallest patch |
|---|---|---|
| **Visibility toggle + markers** | ðŸŸ© **FREE ZSCRIPT** | New CVARINFO decls + `HolsterMarker`/`HolsterVisibilityHandler` + `menudef` page + **a `HOLS` sprite lump** (required deliverable, else nothing renders). No `src/` change. |
| **Player-adjust â€” sliders (Path A)** | ðŸŸ© **FREE ZSCRIPT** | CVARINFO decls + cloned `VRHolsterOptions` menu. Sliders auto-write/persist. |
| **Player-adjust â€” calibration (Path B)** | ðŸŸ¨ **HYBRID** | ZScript EventHandler + `SendNetworkEvent` seam. Free in ZScript for a **body-yaw** anchor; the *only* reason it's hybrid is the optional `GetHeadAngles` thunk for true head-yaw tracking. |
| **Detect / draw / stow (single-player)** | ðŸŸ© **FREE ZSCRIPT** | `PlayerThink` override state machine. Draw/stow are pure ZScript (`BringUpWeapon`/`DropWeapon`). |
| **Grip conflict-free draw/stow** | ðŸŸ¨ **HYBRID** | Needs the 1-line C++ grip-consume (RT perf pass proved this is **not** optional â€” see Â§7). |
| **True eye-anchored zone** | ðŸŸ¨ **HYBRID** | Needs `GetHeadPos` thunk. Body-Z + `downOff` ships without it. |
| **Netplay-safe holster (peer play)** | ðŸŸ¥ **BLOCKED** (as designed) | Requires routing sim-mutation through replicated events **and** first making the underlying VR grab/climb pipeline deterministic. SP and shared-screen are fine; true peer netplay is not until Â§7 RT-6/RT-7 are addressed. |

---

## 5. C++ THUNK SHOPPING LIST

| # | Thunk / patch | Where | Why ZScript can't do it | Needed for |
|---|---|---|---|---|
| **T1** | `DEFINE_ACTION_FUNCTION(AActor, VRConsumeGrip(int hand))` â†’ `player->cmd.ucmd.buttons &= ~(hand?BT_VR_RGRIP:BT_VR_LGRIP)` (call it, or clear inline, **between `p_user.cpp:1430` and `1435`**) | `src/playsim/p_user.cpp` + decl `actor.zs` | The grip bit is never cleared between the ZScript `PlayerThink` and the C++ grab ladder; `vr_*` `player_t` fields have **no ZScript binding**, so ZScript cannot suppress `VR_UpdateGravityGloves` re-reading the same bit (`VR_IsGripPressed` `p_user.cpp:1335-1342`). | Conflict-free draw/stow (**mandatory**, per RT perf pass). See RT-4/RT-8 for the *deterministic* form. |
| **T2** | `DEFINE_ACTION_FUNCTION(AActor, GetHeadPos)` / `GetHeadAngles` â†’ `r_viewpoint.CenterEyePos` remapped `(X,Z,Y)` + `vr_vunits_per_meter` scale; `hmdorientation[YAW]` | `src/playsim/p_actionfunctions.cpp` (mirror `GetHandVelocity` `:5748`) + decl `actor.zs:~866` | HMD transform (`hmdPosition`/`hmdorientation`) is C++-global (`qzdoom_common.cpp:10-16`), unbound; `CenterEyePos` has **0 ZScript accessors**; `player.viewz` is flatscreen height, not VR eye Z. | True head-anchored zone + exact eye Z. **Optional** (body anchor ships first). ~1 hr, one file. |

Both thunks are small, single-file, and modeled on an existing binding. Nothing else in `src/` is required for requirements 1 and 2.

---

## 6. RED-TEAM â€” kill-shots and their mitigations (folded into the plan)

### RT-1 (serious) â€” `player.viewz` is NOT VR eye Z â†’ wrong zone height + mis-firing highlight
`AttackPos.Z` is `CenterEyePos.Z`-anchored with `/pixelstretch` + `vr_height_adjust` (`gl_openxrdevice.cpp:624`); `player.viewz` is `pos.Z + viewheight + bob` (`player.zs:707`), a **different vertical frame**. Marker (viewz-based) and tested hand (CenterEyePos-based) would live in different frames â†’ vertical highlight mis-fire.
**Mitigation (in Â§3.1):** put marker Z **and** zone-test Z in **one frame** â€” body Z + tunable `downOff`, test against the hand fields directly. Absolute height becomes a tuned offset; self-consistency is guaranteed. Exact fix = **T2 `GetHeadPos`**, deferred.

### RT-2 (minor) â€” hand pose is render-thread, sampled per frame vs 35 Hz tics
`AttackPos`/`OffhandPos` written in `SetUp` per frame (`gl_openxrdevice.cpp:600-639`); consumed on the game thread â†’ up to one tic stale at low FPS â†’ highlight jitter.
**Mitigation:** accept for the cosmetic highlight. If it ever matters for the *zone edge*, move that test C++-side (the grab ladder already reads `GetWeaponTransform` live, `p_user.cpp:1478`); do **not** add a second ZScript sampling path (none is exposed).

### RT-3 (minor) â€” `+CLIENTSIDEONLY` is a no-op
`DEFINE_DUMMY_FLAG(CLIENTSIDEONLY, false)` (`thingdef_data.cpp:468`) â€” parses, zero effect. Does **not** make the marker local/desync-safe.
**Mitigation:** drop the desync-safety rationale. Gate spawn on `players[consoleplayer]` (in a `native play` `StaticEventHandler`, `events.zs:147`); keep the flag only as inert annotation.

### RT-4 (serious) â†’ RT-8 (serious) â€” the "optional 1-line grip-consume" can make desync **worse** if naive
`ucmd.buttons` is the **network-replicated** input (`g_game.cpp:851-852`). Clearing bits based on a **local render** zone decision corrupts the deterministic input stream per-peer.
**Mitigation:** the grip-consume (T1) must be driven by a **non-replicated per-player flag consumed after the sim reads input**, or derived from replicated state only â€” never from a local-render zone decision on someone else's ticcmd. In SP this is moot; the constraint binds only for netplay.

### RT-5 / RT-6 / RT-7 (FATAL for peer netplay) â€” the whole VR-pose input pipeline is non-deterministic
`GetWeaponTransform`/`GetHandTransform` hardcode `players[consoleplayer]` (`hw_vrmodes.cpp:979`); `AttackPos`/`OffhandPos`/`vr_hand_vel_buffer` are filled only from **local** headset globals. But `PlayerThink` (and the grab/climb ladder, `p_user.cpp:1434-1449`) runs for **every** player on **every** peer. So each peer decides, from its own headset pose, whether *any* player drew/stowed/threw â†’ `ReadyWeapon`/`OffhandWeapon`/psprite diverge â†’ hard desync. The holster **inherits and compounds** a pre-existing VR-aim leak; it does not create an isolated bug.
**Mitigation (scoped honestly):**
1. Gate **all** holster sim-mutation on the local player: `if (self.PlayerNumber() == consoleplayer)`. Never run holster logic for remote players.
2. Do **not** mutate shared weapon state directly from the local zone test. Route draw/stow through a **replicated channel** â€” `SendNetworkEvent` â†’ perform the `BringUpWeapon`/`DropWeapon` inside `NetworkProcess` so every peer applies it on the same gametic. Local pose decides *when to send*; the sim mutation happens from the networked event.
3. Keep all placement/visibility CVARs `user`-scoped and markers cosmetic-only.
4. **Ship SP and shared-screen now; do NOT claim peer-netplay support** until the underlying VR grab/climb pipeline is made deterministic (or local-only + event-replicated). This is stated up front as a dependency, not hidden.

### RT-P1 (serious) â€” grip double-read is common, not rare
The grab candidate is **locked, not searched**, at grip-press: search runs only in the `!isGripPressed` branch (`p_user.cpp:1562`) and **persists** in `vr_grab_candidate[hand]` (`:1593-1599`); the grip-edge locks/snatches that persisted candidate (`:1762-1793`). With `vr_grab_max_dist=500` (~14.7 m) and a 30Â° cone (`hw_vrmodes.cpp:489-490`), a hand reaching **back** to a shoulder sweeps a large volume that in a live arena frequently contains a dropped weapon / `MF_SPECIAL` pickup / in-flight `MF_MISSILE`. So one holster grip can **both** draw *and* snatch a world item â€” routinely.
**Mitigation:** **T1 is mandatory** (Â§4 badge corrected to HYBRID; the pure-ZScript v1 is honestly labeled "single-player, may double-fire" â€” it is NOT "conflict-free"). ZScript alone **cannot** stop `VR_UpdateGravityGloves` from locking a world item; only the C++ grip-consume can.

### RT-P2 (serious) â€” two-handing corrupts same-tic
`VR_CalculateTwoHanding` recomputes every tic and hard-returns on `!ReadyWeapon` (`p_user.cpp:1305-1316`), running at `:1437` **after** the ZScript `PlayerThink` at `:1426`. A stow that nulls `ReadyWeapon`, or a draw that sets it, is seen the same tic â†’ stabilization silently drops or re-evaluates against new keyword offsets.
**Mitigation:** when stowing/drawing the main-hand weapon, explicitly re-assert/clear two-hand intent in the same override *after* the pointer change, and account for `BringUpWeapon` nulling `ReadyWeapon` on a two-handed offhand draw (`player.zs:1980-1984`). Prefer offhand-only holsters for v1 to avoid touching `ReadyWeapon`.

### RT-P3 (serious) â€” climb gate is one tic stale
`vr_is_climbing[hand]` is written in `VR_UpdateClimbing` at `p_user.cpp:1969` (runs `:1435`, **after** `PlayerThink` `:1426`), so the holster gate reads **last** tic's climb state â†’ a first-grip on a climbable surface overlapping a holster zone can fire a spurious draw.
**Mitigation:** require the holster zone and climbable-surface detection to be mutually exclusive by geometry (shoulder zones sit off any wall), and add a one-tic debounce on `ARMEDâ†’DRAWN`. The clean fix rides on T1 (arbiter runs identically before both).

---

## 7. BUILD ORDER

**Slice 0 â€” Minimal first playable (body-anchored, invisible, cvar-adjust).** Pure ZScript.
- CVARINFO: `hol_0/1_ox/oy/oz/radius`, `hol_show_all`.
- `PlayerThink` override: per-hand state machine, sphere zone from body anchor + `downOff`, grip-edge DRAW via `BringUpWeapon`, STOW via `DropWeapon`+null. **Gate on `consoleplayer`.** Offhand-only to dodge RT-P2.
- Adjust via console `set hol_0_oy ...` (no menu yet). Verifies the core loop with zero art and zero `src/` change.

**Slice 1 â€” Add visibility.** Pure ZScript + one sprite.
- `HolsterMarker` + `HolsterVisibilityHandler`; ship the `HOLS` sprite lump. Toggle `vr_holster_show`. Highlight in a single Z-frame (RT-1). Register handler like `VRDamageHandler`.

**Slice 2 â€” Add menu + calibration.** Pure ZScript + defs.
- `VRHolsterOptions` cloned from `VRWeaponOptions`: sliders (offset/radius/yaw/pitch), `Visible`/`Show Holsters` toggles, `resetcvar` row, `Calibrate` `Command` â†’ `SendNetworkEvent`. Path B EventHandler commits into the same cvars.

**Slice 3 â€” Grip-consume hardening (T1).** First `src/` touch.
- Add the mandatory grip-consume between `p_user.cpp:1430` and `1435`, driven by a per-player non-replicated flag (RT-8-safe). Removes the RT-P1 double-fire. Promotes draw/stow from "SP, may double-fire" to conflict-free.

**Slice 4 â€” Head-pose thunk (T2), only if needed.** `src/` touch.
- Add `GetHeadPos`/`GetHeadAngles` mirroring `GetHandVelocity`; swap the zone/marker anchor from body-Z to true eye-anchored. Only if in-headset testing shows unacceptable body-vs-head-yaw drift.

**Netplay (separate track, gated).** Only after the VR grab/climb pipeline is made deterministic: route all draw/stow through `SendNetworkEvent`â†’`NetworkProcess`. Do not advertise peer netplay before this.

---

## 8. Open risks

1. **Netplay determinism (fatal-as-designed).** The holster reuses the same local-render-pose inputs as the already-non-deterministic grab/climb pipeline. Peer netplay is out of scope until that pipeline is fixed. SP / shared-screen unaffected.
2. **Two unit scales.** Position math must use `vr_vunits_per_meter` (=34); velocity-gated throw uses `vr_scale_meters_to_units` (=40). Prefer reading `AttackPos`/`OffhandPos` directly (already remapped) to sidestep both the scale and the mandatory `(X,Z,Y)` swap + `/pixelstretch` (`gl_openxrdevice.cpp:623-624`).
3. **Sprite asset dependency.** No `HOLS` lump â†’ markers render nothing. Required deliverable, not an engine limit.
4. **Missing-cvar VM abort.** Reading a `hol_*` cvar before registration aborts `WorldTick` (`CVARINFO:22-29`). Every read must go through a `FindCVar`-with-default guard.
5. **CVARINFO redeclare trap.** `hol_*`/`vr_holster_*` must be greenfield (fatal collision otherwise, `CVARINFO:9-13`) â€” safe as chosen.
6. **Death/morph guards.** The `PlayerThink` override must guard holster logic behind `player != null` and alive/not-morphed, mirroring existing guards, to avoid drawing weapons during `DeathThink`.
7. **Body-vs-head yaw.** Body-anchored shoulders track the torso, not raw HMD yaw. Usually desired; if not, T2 is the fix.

---

### Files that will change / be created

- **New ZScript:** `HolsterMarker` + `HolsterVisibilityHandler` (in a new `zscript/ui/vr_holster*.zs`); `PlayerPawn.PlayerThink` override; holster calibration `EventHandler`.
- **New defs:** `CVARINFO` (`hol_*`, `vr_holster_*`); `menudef.txt` `VRHolsterOptions` page + `AddOptionMenu`/`VROptions` entry; `HOLS` sprite lump.
- **C++ (only when reached):** `src/playsim/p_user.cpp` (T1 grip-consume, Slice 3); `src/playsim/p_actionfunctions.cpp` + `wadsrc/static/zscript/actors/actor.zs` (T2 head thunk, Slice 4, optional).
