# DoomXR — VR Reload Canon + Physics: BUILD STATUS

> Definitive manifest of everything built for the VR reload canon, the mass/impact physics, and the
> grapple-beatdown, as of 2026-07-04. **Nothing here is compile-verified** (no headless compiler for this
> tree) — it all activates on **ONE full rebuild** (exe + pk3 together, because new `actor.zs` native decls
> must match the compiled exe). Companion refs: `VR_RELOAD_SYSTEM_REFERENCE.md`, `RELOAD_JUICE_SPEC.md`.

## The one action
**Full rebuild (cmake, exe + repacked pk3), then headset-test.** If the build fails, check the C++ edits in
`p_user.cpp` / `d_player.h` / `vmthunks_actors.cpp` / `hw_vrmodes.cpp` / `p_interaction.cpp` first.

---

## A. Core reload (built earlier, foundation)
| Feature | File(s) | Status |
|---|---|---|
| Native reload FSM (READY→EMPTY/MAG_OUT→MAG_IN→RACKED) | `p_user.cpp` `VR_UpdateWeaponReload` | ✅ |
| Chest ammo pouch (spawn mag → `vr_held_items` → FSM seats) | `vr_ammo_pouch.zs` | ✅ |
| 14 weapons wired (fire-gate + eject/reload) | weapon `.zs` + `XR_ManualReload` mixin | ✅ |
| Options menus (`VRReloadOptions` + `VRReloadAdvanced`) | `menudef.txt` | ✅ |

## B. Reload styles (native, workflow build)
| Style | Weapons | File | Status |
|---|---|---|---|
| `RS_BOXMAG` | rifle/pistol/smg/etc. | `p_user.cpp` | ✅ |
| `RS_SHELL` shell-by-shell + pump | Shotgun, SuperShotgun | `p_user.cpp` + `weaponshotgun/ssg.zs` | ✅ |
| `RS_INTERNAL` cylinder + speed-loader | Revolver | `p_user.cpp` + `weaponrevolver.zs` | ✅ |
| `RS_CANISTER` heat-vent | PlasmaRifle, BFG9000 | `p_user.cpp` + `hw_vrmodes.cpp` heat cvars | ✅ |

## C. Reload juice (feel)
| Feature | File | CVars | Status |
|---|---|---|---|
| Real per-mag mass tiers | `vr_manual_reload.zs` eject | — | ✅ |
| Physical spent mags (fall/litter/glow/fade) | `vr_reload_juice.zs` `XRSpentMag` | `vr_reload_mag_life` | ✅ |
| **Throw the mag / eject-into-face damage** | `XRSpentMag` + native momentum | `vr_reload_mag_throw/_damage/_eject_speed` | ✅ |
| Eject flair spark (ammo-colored) | eject | — | ✅ |
| **Mag glow-TRAIL (carry/slam streak)** | `XRMagTrail` handler | `vr_reload_mag_trail` | ✅ |
| PERFECT-reload timing + neon popup | `p_user.cpp` + `XRReloadPerfectFX` | `vr_reload_perfect_fx/_window/_life` | ✅ |
| Tactical 1-in-the-barrel eject | `p_user.cpp` `VR_BeginTacticalEject` + eject | `vr_reload_tactical` | ✅ |
| Fumble-under-fire (drop mag) | `XRReloadFumble` + `VR_AbortReload` | `vr_reload_fumble/_damage/_chance` | ✅ |
| Toss-catch (inverted-gun seat) | `p_user.cpp` EMPTY loop | `vr_reload_toss_catch` | ✅ |
| **Off-hand-throw (catch ejected mag, throw it)** | `XRSpentMag` heldOff + eject | `vr_reload_mag_to_offhand`, `vr_reload_mag_throw_mult` | ✅ |
| **Chaingun ammo-box SLAM** (two-hand down-slam) | `XRChaingunSlam` handler | `vr_reload_chaingun_slam/_speed` | ✅ |
| **Variable ammo in dropped enemy guns** | `XRDroppedAmmo` handler + `XRChamberPreset` | `vr_reload_dropped_ammo` | ✅ |
| **Whip-yank ammo → catch = instant reload** | `vr_whip.zs` `TryAmmoCatch`/`InstantRefillChamber` | `vr_whip_ammo_catch` | ✅ |
| Speed-loader (revolver bulk-load) | `RS_INTERNAL` | — | ✅ |

## D. Physics
| Feature | File | CVars | Status |
|---|---|---|---|
| **Impact-momentum system** — moving body shoves target `mass×vel/targetMass`, ALL masses incl. player; hooks `ApplyKickback` | `p_interaction.cpp` (native, self-built) | `vr_impact_momentum`, `_scale`, `_max` | ✅ |

## E. Debug
| Feature | File | CVars | Status |
|---|---|---|---|
| Wireframe boxes (hands/clips/pouch/hotspots) | `vr_reload_debug.zs` + `models/debug/wirebox.obj` | `vr_reload_debug*` | ✅ hotspots now live via `VR_GetWeaponHotspot` |

## F. VR Grapple & Beatdown (new epic)
| Feature | File | CVars | Status |
|---|---|---|---|
| Grab monster (off-hand) → punch (main hand) → throw body → area-stun | `vr_grapple.zs` `XRGrapple` + `XRGrappleThrownWatcher` | `vr_grapple`, `_range`, `_punch_speed`, `_punch_damage`, `_throw_mult`, `_stun_radius`, `_grab_heavy` | ✅ |

---

## Native functions exposed to ZScript (need actor.zs decls + rebuild — all present)
`VR_GetWeaponHotspot` · `VR_GetReloadState` · `VR_GetReloadPerfect` · `VR_BeginTacticalEject` · `VR_AbortReload`
· `VR_AddReloadHeat` · `VR_GetReloadHeat`

## Verification done (by inspection — no compiler)
- C++ audit: CLEAN (macros/params/fields/enums consistent).
- FSM logic: PASS (no crashes/loops/gate-leaks; box-mag path byte-identical).
- Cross-lane: no regressions to IK / grip arbiter / hardpoints / two-hand.
- ZScript landmine sweep: no `IntVar`/`StringVar`/`FloatVar` in any touched file; no action-funcs from
  StaticEventHandlers; concrete casts throughout; particles → glow panels.
- The workflow's 5 "blockers" were verified **false positives** (ZScript global class resolution; M79's own
  self-contained reload; C++ cvars must NOT go in CVARINFO or boot crashes).

## Known headset-tuning knobs (feel, not bugs)
- `vr_impact_momentum_scale` (global shove strength) — it also nudges the player from enemy projectiles; a
  one-line MF_MISSILE exclusion scopes it to thrown-only if desired.
- Grapple: `vr_grapple_range` (grabby in crowds), `vr_grapple_punch_speed` (phantom punches if too low).
- Whip ammo-catch: an `xr_mag` catch reloads the ready gun regardless of the mag's visual type (no reflective
  reader); fine in practice since mags only exist as the ready gun's own.
- Chaingun slam threshold, off-hand-throw multiplier, dropped-gun ammo ranges.

## Cut / deferred (honest)
- Perfect-STREAK "Gunslinger" hand-glow (PERFECT popup exists; streak does not).
- Dark Reload, gore-fueled auto-load, body-map pouch zones, rhythm reload, reload finisher — Tier 2-3
  signature ideas from the original spec, not built.
