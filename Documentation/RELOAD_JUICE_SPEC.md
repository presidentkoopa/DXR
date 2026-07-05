# RELOAD JUICE — Spec Sheet

> **CANON (locked by user 2026-07-04).** The core idea: **eject → the mag is a real physical object → what you
> do with it is a choice with consequences.** Reloading is a verb with a skill ceiling, tension, and a neon payoff.
> Everything rides systems that already exist (glow panels / SDF / haptics / combo meter / body zones / GITD dark).
> Single-player, no net constraints.

## Confirmed engine capabilities (verified)
- **FX on held 3D models: YES.** (a) `A_ChangeModel` swaps model/skin at runtime (sword+whip already do it) →
  swap to a glowing/hot skin for the reload beat, swap back. ZScript-only. (b) `AddGlowPanel`/`SpawnSDFText` draw
  neon/crackle/trails/popups at the gun's world pos. ZScript-only. (c) real emissive materials via gldefs (IceHook
  PBR pattern) = SHADER LANE, coordinate.
- **Mag physicality:** drop `+NOINTERACTION` on the SPENT mag so it falls/throws/collides.

## v1 FEEL CALLS (assistant's call, per user delegation "you're the player" 2026-07-04 — dial in on headset)
- **Mag mass (widest spread = biggest fun):** pistol/SMG ~4 · rifle ~8 · shells ~2 (juggle several) · chaingun box ~40 (two-hand heave) · BFG/rocket pod ~70 · revolver speedloader ~6.
- **Fumble-under-fire:** default **OFF**, opt-in; when on ~15% on a big hit, only *loosens* the mag (re-grab), never voids ammo.
- **Perfect-reload reward:** mag glows + PERFECT pop + ~1.5s +15% handling + feeds combo; chained perfects → "in the zone" hand glow. Flashy, not build-defining.
- **Throw-the-mag:** ~5–8 dmg, big stagger + chunky haptic. Distraction/flex, not DPS.
- **Speed-loader gesture:** SLAM (up under the open cylinder), NOT twist — big unambiguous motion reads better in VR.
- **Heat-vent:** default **ON** for plasma + BFG (overheat → rack hot sink → slap cold one); mag-reload = fallback toggle.

**Build sequencing (get to "fun" fastest):** Phase 1 = tiny C++ (state getters + perfect-timing flag). Phase 2 = ZScript juice (mass, haptic rhythm, eject-glow, PERFECT popup+combo, throw). Phase 3 = extra styles + abort/fumble + toss-catch, by appetite.

## CANON MECHANICS (locked)
- **Real per-mag mass** · **layered haptic rhythm (4 beats)** · **spent mags eject, fall, live** (glow+fade).
- **Toss-mag-up + catch with inverted gun = seat** — the SHOWOFF reload; always grants the perfect bonus. Optional.
- **Combat-reload timing window** — eject/insert-shell/.357-load opens a window → hit it = PERFECT reload bonus.
- **Tactical = 1 in the barrel** — drop a partial mag → lose the mag's rounds, KEEP the chambered round (1 shot in
  the pipe). "Keep chambered" is default; dropped-mag ammo recovery = toggle.
- **Fumble under pressure** — taking > X damage in a 3-tic window has a % chance to drop the clip. Tunable/optional.
- **Mag glow + trails** — options; can tie intensity/color to a perfect reload.
- **Per-weapon flair** — skin-swap + glow-panel FX (BFG charge, plasma crackle, shotgun chunk).
- **Throw the mag** — eject into the OFF-HAND, throw for dmg+stun; OR momentum-eject straight into a face (dmg+stun).
- **Speed-loader** — revolver reload (our model HAS a speedloader); one slam loads all 6.
- **Chaingun ammo-box slam** — two-hand, grab the box, slam it on top.
- **Reload-cancel = free** — firing allowed whenever chamber ≥1; no forced ammo loss (cost is only a mag you already
  committed to dropping).
- **Whip-yank ammo → catch with the correct gun = instant reload;** wrong gun = just bank the ammo for later.
- **Heat-vent (energy weapons)** — OPTIONAL, replaces mag reload: rack out a hot heat-sink, slap in a cold one.
- **Variable ammo in dropped enemy guns** — dropped weapons carry a random chamber count (sometimes 0 = cruel click).
  Grab them with whip / gravity glove. (This REPLACES "loot-the-corpse" — CUT.)

## RELATED EPIC (separate feature, shares the grab/throw plumbing)
- **VR Grapple & Beatdown** — grab a monster with the off-hand (extends the gravity-glove hold), punch it repeatedly
  with the main hand (weapon or fist), then **throw the body into a crowd for an area-stun.** Not reload, but reuses:
  glove grab/hold/throw, whip yank, keyword stun. Spec separately.

---

> Original brainstorm board below (kept for the effort/tier estimates).

Effort key: **S** = ZScript/config only, hours · **M** = ZScript + a small native hook · **L** = real C++/asset work.
Every feature ships behind a CVar so it's tunable / disable-able.

---

## TIER 0 — Baseline juice (build first; cheap, huge payoff)

| # | Feature | What it does | Fun | Effort | Systems / notes |
|---|---|---|---|---|---|
| 0.1 | **Real per-mag mass** | pistol mag `mass:4`, chaingun box `mass:40`, BFG pod `mass:70` — heavy lobs slow, light flicks fast | heft | **S** | remove `+NOINTERACTION` on the *spent* mag; set `Mass`/`mass:N` keyword per XRMag_* |
| 0.2 | **Spent mags eject + fall + glow** | old mag drops with weight, bounces, glows neon, fades ~3s; brass litters the floor | "I did that" | **S** | a `XRSpentMag` actor (gravity on, `AddGlowPanel` fade) spawned at eject |
| 0.3 | **4-beat haptic rhythm** | grab=soft tap · seat=deep THUNK · rack=SNAP · chamber=click — learn it blind | feel | **S** | tune the existing `VR_HapticPulse` seat/rack/chamber calls into distinct envelopes |
| 0.4 | **Per-weapon reload flair** | BFG pod whines+glows as it seats · plasma cell crackles · shotgun *pump-cha-CHUNK* | personality | **S–M** | per-archetype sound + a glow-panel cue keyed off the reload FSM state |

## TIER 1 — Skill layer (make it a mini-game)

| # | Feature | What it does | Fun | Effort | Systems / notes |
|---|---|---|---|---|---|
| 1.1 | **Combat-reload bonus** | fast+clean reload → brief +fire-rate OR next mag loads glowing **tracer/overcharge** rounds | reward the motion | **M** | time seat→chamber; grant a short powerup / tag the chamber |
| 1.2 | **Tactical vs emergency** | reload with rounds left → *stow* the partial mag (back to pouch); empty → it drops | mag discipline | **M** | preserve `XRChamber` remainder; re-add to reserve on stow |
| 1.3 | **Perfect-reload streak** | consecutive perfects build a "Gunslinger" state (faster everything, hands glow) | skill loop | **M** | streak counter → temp powerup + hand glow panel |
| 1.4 | **Fumble under pressure** (toggle, default off) | low health / point-blank → small chance the mag slips | white-knuckle | **M** | RNG gate in the seat step; drops a live `XRSpentMag` |

## TIER 2 — DoomXR SIGNATURE (the stuff only we can do)

| # | Feature | What it does | Fun | Effort | Systems / notes |
|---|---|---|---|---|---|
| 2.1 | **The Dark Reload** | in GITD black, pouch+mags glow; reloading lights you up (beacon) — glow can draw aggro | tension + beauty | **M** | glow intensity scales with ambient darkness; optional aggro ping |
| 2.2 | **Gore-fueled auto-load** | glory-kill / kill-streak slams a fresh mag; flamethrower refuels from a burning corpse | violence = ammo | **M–L** | hook the kill/glory events (HF_ReactionHandler-style) → `A_XR_RefillChamber` |
| 2.3 | **Whip / glove-yank reload** | yank an ammo box across the room into your hand, then slam it | traversal combo | **M** | reuse whip grapple + `VR_TrySetHeldItem` into the pouch pipeline |
| 2.4 | **Heat-vent (energy guns)** | plasma/BFG *overheat* instead of mag; rack out a glowing heat sink, slap a cold one (or cool it in a cold spot) | physical thermals | **L** | new reload STYLE in the FSM (`RS_HEATVENT`); heat meter as a glow bar |
| 2.5 | **Body-map pouch zones** | chest=rifle · hip=pistol · shoulder=shells · wrist=grenades — reach the right place | muscle memory | **M** | extend the pouch handler to multiple body-relative zones (hardpoint system already maps these) |
| 2.6 | **Reload finisher** | reload beside a stunned demon → slam the mag through its skull, then rack | glory-kill fusion | **L** | proximity + stunned check → canned finisher anim + damage |
| 2.7 | **Rhythm reload** | hit the 4 beats on the music downbeat → bonus | Doom-to-the-beat | **L** | needs a beat clock; niche but *very* on-brand |
| 2.8 | **Loot-the-corpse** | no pouch mag? grab one off a dead enemy / pull a dropped mag from the air | diegetic scavenging | **M** | drop `XRMag_*` on death; the grab pipeline already handles pickup |

## TIER 3 — Spectacle & loadout

| # | Feature | What it does | Fun | Effort | Systems / notes |
|---|---|---|---|---|---|
| 3.1 | **PERFECT-reload popup + combo** | neon SDF "PERFECT +50" off the gun, feeds the combo meter | score fantasy | **S–M** | `SpawnSDFText` + the existing combo/netevent bridge |
| 3.2 | **Mag glow-trail** | fresh mag leaves a neon streak as you slam it home | flourish | **S** | `AddGlowPanel` trail on the held mag (whip-rope path) |
| 3.3 | **Mag mods / speed-loaders** | extended (more/slower), drum (heavy), revolver speed-loader (6 at once), tied to loot rarity | build variety | **L** | per-mag class variants + a loadout picker; hooks the rarity/color system |
| 3.4 | **Throw the spent mag** | fling the empty at a demon's face — light stagger/distraction | reload = offense | **S** | spent mag is already a throwable actor (Tier 0.2) — add a stagger on hit |
| 3.5 | **Chaingun ammo-box slam-dunk** | two-hand the chaingun, grab the box off your chest, *slam* it on top | boss-energy | **M** | two-hand-gated reload variant + a big haptic + glow |

---

## Recommended build order
1. **Tier 0 whole row** — the free win; makes reloading *feel* good immediately (mass, eject-glow, haptic beat, per-weapon flair).
2. **3.1 + 3.2** (PERFECT popup + trail) — ties reloading into the score loop; cheap, high wow.
3. **1.1 + 1.3** (combat reload + streak) — turns it into a skill you *want* to nail.
4. **2.1 (Dark Reload)** — the signature DoomXR moment.
5. Then cherry-pick the big ones (2.2 gore-load, 2.4 heat-vent, 2.5 body-map) by appetite.

## Dependencies / notes
- Tiers 0, 3.1, 3.2, 3.4 need **no C++** — pure ZScript/asset, land anytime.
- Heat-vent (2.4), finishers (2.6), mag-mods (3.3) want new **reload STYLES** in the native FSM (`VR_UpdateWeaponReload`) — same C++ that currently only knows box-mag. Batch them with the archetype reload-style work (shotgun-shell / cylinder / break already flagged).
- Body-map pouch (2.5) reuses the **hardpoint** body-zone math already in `VR_UpdateHardpoints`.
- Everything CVar-gated under a `VRReloadJuiceOptions` menu section.

Related: `VR_WEAPON_HANDLING_ENGINE_LEVEL.md`, `dxr-manual-reload-arsenal-complete`, the combo/neon-display + gore-death memories.
