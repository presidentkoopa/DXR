# DoomXR — VR Arsenal UI Suite (design package)

**Status: gold-tier design, source-grounded, NOT built. The native pipeline it needs is real.**
Team pass: research → 5 concepts designed/critiqued/refined → synthesis. Neon HTML mockups in
`C:\Users\Command\Desktop\DoomXR_Arsenal_UI\`. Shader work is spec-only (shader-lane owner implements).

North star: a player rips the headset off and says **"THAT is DOOM?!"** Optimize functionality + looks
+ amazement; scale back later.

---

## The suite — one spine, four faces (tiered by ACCESS COST)

All surfaces read the SAME weapon-data model and draw through the SAME world-UI layer. You never build a
UI twice; latency = design (the Half-Life Alyx lever).

| Tier | Surface | Job | Feel |
|------|---------|-----|------|
| FAST | **Check Your Watch / Wrist Slate** | daily driver, 50×/match | glance at your bracer; touch-select; mass-weighted haptic detents; never freezes combat |
| MEDIUM | **Radial Classic to 11** (existing wheel enhanced) | dependable fallback + reference impl | neon-SDF rings, vector icons, on-hover stat card, spinning 3D model, dual per-hand wheels, time-freeze |
| DEEP / FLAGSHIP | **Seam Reveal / Coat of Holding** | the showpiece | rip your own chest open into a weapon vault; **pull a dual-wield PAIR in one reach** |
| OPT-IN DEEP | **Hip Rift** & **Arsenal Tarot** (2 wild) | cvar-selectable alternatives | Excalibur-draw from a hip tear / deal your arsenal as a fan of neon tarot cards |

**Why Seam Reveal is gold:** it's stripped of double duty (the Wrist Slate owns fast swaps), so it can
afford a two-handed belly-tear, deep time-crunch, real motion-parallax depth, and the one thing nothing
else can do — **pull LEFT=offhand + RIGHT=main in a single coat-open reach.** You only rip it open when
earned, so the first rip stays a jaw-dropper and the hundredth never happens (one scoping decision kills
gorilla-arm and flow-shatter at once).

---

## Shared engine architecture — THREE native C++ pillars

Design these to become engine features. Build the spine once; every surface rides it.

**PILLAR 1 — `hw_vrworldui.{h,cpp}` — the one world-UI render layer (ship FIRST, standalone).**
Today `DrawWorldQuad`/`DrawWorldDisc`/`DrawWheelModel` are PRIVATE statics in the anon namespace of
`hw_vrwheel.cpp` (≈lines 904/941/1000). Extract them into a shared TU; expose public
`VRWorldUI_DrawQuad/DrawDisc/DrawModel`. **Acceptance: the wheel renders byte-identical through them.**
Head-locked anchoring (`CaptureHeadLockedAnchor`/`GetHeadAnchorOrigin` off `r_viewpoint.CenterEyePos`)
is part of this pillar — jitter-free placement everyone reuses. (A true body/wrist hardpoint resolver is
NOT present yet; surfaces ship on head-local offsets and gate the IK anchor behind that landing.)

**PILLAR 2 — `VRWeaponCard` — the one data model (the "easy to find, easy to plug into" seam).**
ONE struct, populated per surface from the live `Weapon`, via the wheel's existing introspection. This is
the single place weapon data is read — no UI ever hunts for it. Fields + source:
- **Name:** `Tag` → `GetTag()` (display); `GetClassName()` (internal key only)
- **Reserve ammo:** `(Ammo1!=null)?Ammo1.Amount:0`, `AmmoUse1`; `Ammo2` when non-null (`weapons.zs:14/29/1034`)
- **Loaded clip (chamber guns only):** `XRChamber`/`XRMagSize`/`XRReloading` (`vr_manual_reload.zs:25-27`); has-clip = `XRMagSize>0`; hide the row otherwise; suppress when `vr_manual_reload` off
- **Dual-wield:** capable = `Keywords.IndexOf("vr_dualwield")>=0`; variant `<class>_2`; owned-count cap 2; hand via `bOffhandWeapon`; `bTwoHanded` badge; base+_2 SHARE reserve → render ONCE
- **Identity chips:** Keywords pairs `class/role/dmg/style/weight/range/fire/handling` (display strings; dmg is QUALITATIVE — no damage number exists, do not invent one)
- **Defensive:** `parry_extent[x,y,z]` from `KEYWORDS.json` (only Shotgun/SSG/Chaingun/Pistol/ShieldSaw/VRSword); shield glyph sized by Z; applies to _2
- **Slot:** `SlotNumber` (keybind chip), `SelectionOrder` (sort)

**Extending it = one edit in one file, data-driven** (a weapon declares card data the same way it declares
Keywords/parry). Modders never touch UI code. Color-coded ammo language + mass-weighted haptics both
derive from this one model.

**PILLAR 3 — shared interaction + time + suppression spine.**
- Draw hook: a sibling call beside `VRWheel_Draw` in `hw_drawinfo.cpp` (VR-only, suppress-when-menuactive).
- **CRITICAL:** under the hard time-freeze a tic never runs (`p_tick.cpp` early-returns before `WorldTick`),
  so ALL geometry/text/gauges MUST be computed + drawn in the RENDER path, **not published from a ZScript
  EventHandler Tick** (a Tick publisher renders a dead, hand-unresponsive snapshot). This killed one concept's
  first design; it's the single most load-bearing correctness fact.
- Time-control: refcounted freeze (`GVRWheels[2]`, `GWheelTimeControlRefCount`, `ApplyWheelTimeControl`) is
  on the C: mirror but the **E: ship tree is still singleton `GVRWheel`** — STEP 0 of every deep surface is
  porting C:→E:.
- Commit → `MoveWeaponToHand` (re-equips OWNED guns only; any "summon into empty hand" is an explicit
  optional `VR_SummonWeapon` deliverable).
- Carried constraints everywhere: `P_SpawnParticle` INVISIBLE in VR (use quads/discs/models/glow panels);
  zero dynamic lights; glow entries re-publish every tic; shader work is spec-only.

**The neon layer (v2, dependency-gated but REAL):** the engine already has a native MSDF pipeline —
`SpawnSDFText`/`FVRMSDFTextThinker` (world neon text, styles Classic/Pulse/Glitch/Ticker/Explode; NULL-check
the atlas), `FRenderState::SetMSDFParams` (drives the neon shader uniforms; respect the std140 pad before
`u_MSDFColor`), and the GITD "wgType" neon catalog (13 digit panel, 14 shockwave, 15 disc-flash, 18
corner-bracket reticle, 21 12-seg gauge, 22 spectrum, etc.). v1 surfaces ship on promoted primitives + stock
FFont; the neon-SDF beauty is a real, named v2 upgrade — not a fantasy.

---

## VR options framework — deep, tooltipped, beginner→power-user

Built on the real `TFLV_TooltipOptionMenu` (copy `CinemaModeOptions`/`VRHUDOptions`). Every row: a control
immediately followed by a `TFLV_Tooltip "..."` (supports `\c[Color]`); gate-cvars auto-grey dependents.

- **Root:** `VRArsenalUIOptions`.
- **Beginner page (`VRArsenalBasics`) — 8 rows:** wrist enable · deep-surface {SeamReveal/ArsenalTarot/HipRift/Off}
  · classic wheel enable · time-slow · haptic-mass-scale · hover-model · muscle-memory-bypass · → Advanced. + reset.
- **Advanced hub** routes to per-surface pages (`VRWatchAdvanced`, `VRSeamAdvanced`, `VRTarotAdvanced`,
  `VRHipRiftAdvanced`), the existing wheel cvars, and `VRCardAdvanced` (shared card knobs). ~50 knobs beneath 8.
- Greyed dependency-gated rows are shown live (e.g. `summon_neon_lip` greyed "requires GITD/MSDF subsystem").
- A `!player.PlayInVR` 2D radial fallback + headset-free tuning rig ships with it.

---

## Seam Reveal — the gold plan (seven moves)

1. **The dual-wield PAIR-PULL is its irreplaceable reason to exist** — two mirrored models, one halo, "2x",
   reserve once; L grabs offhand, R grabs main, both in one reach. "You tear your chest open and come out akimbo."
2. **Coat-open at the BELLY, not reach-through at the sternum** (sternum = occlusion dead zone). Interior opens
   ~40cm in front of the gut, in the tracking cone, below the chin.
3. **Honest shallow membrane + real parallax:** owned guns on a shallow shelf ~0.4m in; UNOWNED as dim wireframe
   ghosts at 1.2–1.8m so head-motion produces genuine parallax (doubles as a progression tease).
4. **One glanceable datum + progressive disclosure:** panic = Tag + one big ammo gauge; full card only on ~0.4s dwell.
5. **Earned time-crunch** (default 0.15×, optional freeze) via the refcounted control; cinematic beats (catch-flash,
   rarity-tinted halo buzz, mass detent, collapse-flash + tear-snap-shut on commit).
6. **Neon "rift" wgType** as a named shader-lane deliverable (mirrored cyan/amber lips driven by rip progress;
   `AddGlowSpotWiped` floor spill). v1 = squashed discs + bright quad ring.
7. **Ship order inverted — prove foundation before beauty:** Pillar-1 promotion + a throwaway in-headset smoke
   test (one glow panel + one line of live ammo text at 72fps) GATES the pretty cards.

---

## Build roadmap (native-first, cheapest/safest first)

- **Phase 0 —** extract the 3 primitives → `hw_vrworldui` (byte-identical wheel). Standalone PR, unblocks all four.
- **Phase 0.5 —** world-UI smoke test in-headset (glow panel + live ammo text @72fps); port refcounted time-control C:→E:.
- **Phase 1 —** `VRWeaponCard` data model + wheel enhancement (on-hover stat card, mass haptics, 3D model default ON). Ships a better wheel today.
- **Phase 2 —** Check Your Watch / Wrist Slate (fast tier, safest new surface; compound-stillness reveal, deadman commit, seam-wipe draw).
- **Phase 3 —** menudef options suite (parallelizable; unblocks playtesting; includes flatscreen fallback).
- **Phase 4 —** Seam Reveal flagship on the proven spine (belly anchor, ballistic pull-back, parallax depth, PAIR-PULL, earned freeze).
- **Phase 5 —** Hip Rift + Arsenal Tarot as opt-in `vr_deep_surface` alternatives (near-free; harvest their best ideas — mass Rolodex haptic, wrist-loadout mini-cards, universal muscle-memory quick-draw — into ALL surfaces).
- **Phase 6 —** neon-SDF v2 upgrade pass once the GITD/MSDF subsystem is ported (swap FFont→neon wgType vocabulary).

---

## The two wild concepts

- **Hip Rift (Excalibur Draw):** reach down to your hip, a vertical neon tear rips open, your arsenal rises out
  as trophy-scale spinning models at chest height; reach higher/lower to pick (heavier=higher), release to commit;
  light slow-mo default, hard-freeze opt-in "first draw" beat; muscle-memory bypass after N draws makes the
  showpiece a reflex.
- **Arsenal Tarot (Fan of Guns):** hold both grips and spread — time freezes and your arsenal deals itself into a
  fan of neon tarot cards between your palms; resting cards show icon + one color-coded ammo number, the hovered
  card blooms into a full stat card with a spinning model; deal a gun to EACH hand and see both dual-wield loadouts
  docked on your wrists with a shared-pool tie-line. Reads like a AAA loadout screen you hold in your bare hands.

---

## Honest status
Everything above is design + source-grounded architecture + neon mockups. Nothing is built or compiled. The
load-bearing corrections the team surfaced: the public draw wrappers / glow / MSDF / hardpoint resolver are NOT
all present on the working tree yet (some are E:-only, some are named v2 dependencies); render-path-not-Tick is
mandatory under freeze; the E: wheel is still a singleton. Build Pillar 1 + the smoke test first; the beauty is
gated on that reading crisp at 72fps.
