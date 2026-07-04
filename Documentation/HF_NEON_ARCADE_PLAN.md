# HF Neon Arcade — Plan of Action
*Generated from a live debugging + architecture session on DOOM_FRESH (`E:\DoomXR-work\DOOM_FRESH`). Everything marked "VERIFIED" was confirmed against actual source this session, not recalled from memory.*

---

## 0. North Star

A VR looter-shooter combat loop where every hit, kill, and pickup reads as an **arcade spectacle**: escalating combo chains, weapon-signature FX, health bars, worldspace pickup cards, a real economy/shop, scripted boss beats, and — eventually — monsters rendered as deformable, mergeable, splittable SDF blobs instead of static sprites. Runs great on a 3080 Ti now; scales down to mobile/Quest later via a tiered quality system, not a rewrite.

---

## 1. Where We Actually Are (verified, not assumed)

### Real and solid
- **Glow-panel primitive** (`level.AddGlowPanel`, native, `vk_shader.cpp`/`hw_renderstate.h`) — draws camera-facing or fixed-orientation flat shapes: digit panels, rings, discs, shell casings, shards, brackets, spirals, hex fields, sunbursts. This is genuinely good working infrastructure.
- **Combo/score arbiter** (`gitd_combo.zs`, `SDFComboArbiter`) — kill-context matching, combo triggers, score banking.
- **Damage pop-ups** (`gitd_dampop.zs`) — per-hit floating numbers.
- **Kill-reward score bursts** (`gitd_scoreburst.zs`) — shard-assemble digit convergence effect.
- **Three complete weapon-signature choreographies**: revolver "Brand," SMG "Brass Storm" (casings, bounces, running total), shotgun "Buckshot" (pellet cone, embed-on-surface, concussion slam). All real, all wired to real game events.
- **Keyword system** — C++ `KeywordDispatcher`, 25 profiles loaded from `KEYWORDS.json`, 35 files of monster/weapon `Keywords "..."` data, native `Keywords` field on `AActor`. Fixed tonight (was crashing on every boot — see §2).
- **MSDF font/sprite renderer** (`msdf_atlas.fp`) — crisp-edge sprite scaling + tint + glitch-flicker. One real "SDF monster" prototype (`GITD_SDFImp`) exists but is just a tinted/glitched stock Imp sprite — no shape math.

### Real but artificially capped
- **Glow-spot channel**: hard-capped at `MAX_WALL_GLOW_SPOTS = 16` globally shared across the whole scene (combo numbers + damage pops + kill marks + death FX + heat map + everything). This cap is **not a hardware limit** — it's `65536 bytes / sizeof(StreamData)`, and `65536` is the Vulkan *guaranteed-minimum* uniform buffer range, not a query of the actual device. A 3080 Ti almost certainly reports a real limit in the multi-GB range. **This is a self-imposed ceiling, fixable in one contained change.**

### Confirmed NOT to exist anywhere in this codebase (checked live source + orphaned files, not memory)
- Health bars (any style)
- In-world weapon pickup cards (the native `canvastexture`/`GetCanvas` hook exists in the engine but zero ZScript calls it)
- Shop screen / economy / currency
- Weapon wheel / inventory wheel
- Boss encounter director / scripted beat sequencing
- Mini-games
- Deformable/merging SDF monster shader math (`smin`/metaball blending) — zero instances anywhere in the shader tree

**None of the above are stubs or half-built. They are absent.** Building them is greenfield work, not repair work.

---

## 2. Tonight's Repair Work (context for why the engine boots at all now)

Fixed this session, in order:
1. Vulkan crash: 28 loose fog/regime uniforms illegally declared outside a block → moved into the `StreamData` UBO.
2. CVARINFO quote-style typo (`'ff ff ff'` → `"ff ff ff"`).
3. Illegal write to a shader input (`pixelpos.xyz +=`) → localized to a proper variable.
4. Two ZScript syntax bugs (illegal function-local `static`, a local variable named the reserved word `color`).
5. A dozen "attempt to redefine" collisions between mod fields and native `Actor` fields (`vel`, `speed`, `score`, `floorZ` — all case-insensitive clashes).
6. Include-order bugs: two files using `extend class Actor`/`extend class StateProvider` were `#include`d *before* those base classes existed in the translation unit.
7. Strife/Doom `FlameThrower`/`FlameMissile` class-name collision (duplicate include).
8. `vr_weapon_menu.zs`: illegal struct-in-dynamic-array + `PClass` (C++ name, not a ZScript type) → converted to a proper `class`, fixed the native signature to match.
9. **Root cause of the recurring hard crash**: `AActor::Keywords` (C++ `FString`) was never declared `native` in ZScript, so the object system never *constructed* it — first `Keywords "..."` assignment dereferenced a null-minus-12 pointer. Currently **stripped to a no-op** (data lines all still present, dormant) pending the real fix below.
10. Missing sprite art (`GBANG`, referenced in `weapongrenade.zs`, existed nowhere) → real 8-frame `EXPL` explosion art imported from the user's sprite library and wired in.
11. `vr_weapon_helpers.zs` (ballistic fire, plasma beam, grenade throw, shotgun individual-fire, `ThrownWeapon`) was a complete, real file — **just never `#include`d**. Confirmed now landed in `zscript.txt` (line 60) from the parallel weapon-fix pass, along with the related fixes (`OnBounce`→`SpecialBounceHit`, `NetworkEvent`→`ConsoleEvent`, `CheckReplacementEvent`→`ReplaceEvent`, the `GBANG`→`EXPL` sprite fix).

**Standing debt**: reimplement `Keywords` properly — (a) declare `native String Keywords;` in `actor.zs`, (b) rename `GITD_DeathEffect`'s colliding local `keywords` field, (c) restore the property handler to actually concatenate the comma-list into the FString. All three sub-fixes are already documented inline in the stripped handler's code comment.

---

## 3. The Plan — Batches, Not Single Steps

Work in the batches below; test/boot after each batch, not after every file.

### BATCH 1 — Foundation + first proof-of-concept (build now)
1. **Reimplement `Keywords` for real** (the 3-part fix documented in §2) — unblocks the whole keyword-driven combo system (role/anatomy/trait-based triggers currently can't fire because the arbiter never reads `.Keywords`).
2. **Wire `.Keywords` into the combo arbiter** — fold `victim.Keywords` + inflictor keywords into the context string `SDFComboArbiter` matches against. This single change lights up every keyword-based combo already defined (`anatomy:cybernetic`, `role:boss`, `dmg:fire`, etc.) that currently can never trigger.
3. **Fix the glow-spot cap for real**: query the actual device `maxUniformBufferRange` (Vulkan `VkPhysicalDeviceLimits`) instead of hardcoding the 64KB floor. Add a `hf_gfx_tier` cvar (0=potato, 1=mid, 2=high) that picks `MAX_WALL_GLOW_SPOTS`/`MAX_STREAM_DATA` accordingly at compile-relevant boundaries (shader `#define` injection already supports this — it's templated per-build, just needs the value parameterized by tier instead of fixed).
4. **Health bar system** — new, self-contained. Rides the (now larger) glow-spot budget. Suggested v1: worldspace bar above monster heads using the same `AddGlowPanel` primitive already trusted and understood, driven by `health / spawnhealth()`.
5. **One pickup card, end-to-end, for a single weapon** — actually exercise the unused `canvastexture`/`GetCanvas` native hook for the first time in this codebase. Proves the worldspace-UI pipeline before committing to art for the whole roster.

→ **TEST CHECKPOINT: boot, confirm keyword combos fire, confirm health bars render, confirm the one pickup card displays correctly, confirm no glow-spot starvation with everything active at once.**

### BATCH 2 — Generalize + economy
6. Generalize the pickup card to the full weapon roster (art + data-driven layout, not one-off code per weapon).
7. Shop screen: currency, inventory persistence, purchase flow. New economy layer — first real "systems" build in this batch, budget the most time here.
8. Boss encounter director: scripted beat sequencing (phase transitions, telegraphed attacks, arena state changes) built on top of the combo/score plumbing that already works. Start with ONE boss, not a general framework.

→ **TEST CHECKPOINT: boot, shop transaction round-trip, one full scripted boss fight start-to-finish.**

### BATCH 3 — Polish + reach
9. Weapon wheel / inventory wheel (VR-native selection, off-hand joystick per the Ermac Gearbox reference pattern already noted in project history).
10. Interactive menu polish pass (the option-menu framework exists and works — this is UX, not new plumbing).
11. Mini-game(s) — treat as stretch, scope one small self-contained loop, not a system.

### LATER — separate arc, not this sprint
12. **SDF blob-monster prototype**: pick ONE simple enemy. Build real `smin`-blended 2D distance-function shader math (doesn't exist anywhere yet) for 2-3 body-part primitives. Feed it a *per-instance* data channel (not the shared global glow-spot array — a new small per-actor uniform or texture-encoded buffer). Prove merge/stretch/flash on this one enemy before deciding whether to generalize to splitting-into-children or the full roster. This is a real R&D arc — budget it separately from the sprint above.

---

## 4. Tiering System (ties Batch 1 item 3 into the mobile roadmap)

| Tier | Target | Glow-spot budget | Notes |
|---|---|---|---|
| High | Desktop discrete GPU (3080 Ti class) | Query real device limit, raise ceiling substantially (64–128+) | No visible compromise |
| Mid | Mid-range desktop / high-end mobile | Moderate raise (32) | Balance point |
| Potato | Quest / low-end mobile | Keep near current 16 | This tier is why 16 existed in the first place — it wasn't wrong, just wrongly applied universally |

Selected via cvar at startup; shader `#define` values are already templated per-build in `vk_shader.cpp`, so this is parameterizing an existing mechanism, not inventing one.

---

## 5. Ground Rules Carried From Tonight

- **Verify against live source before trusting memory** — multiple times tonight, recalled context turned out to describe a different project state. Always grep/read before asserting something exists.
- **No silent stripping** — when something is disabled to unblock a boot (like `Keywords` right now), the reason and the reimplementation path get documented inline in the code, not just in chat.
- **Batch, then test** — this document itself is structured that way per your instruction: a few changes, then boot and look, not one-file-one-boot.
- **Kill the exe before rebuilding** — recurring gotcha tonight (`LNK1104`, locked file); always `taskkill /F /IM doomxr.exe` before a build.

---

## 6. The Unifying Philosophy: "Keywords For Everything"

This is the idea that ties every later section together, so it gets called out on its own.

**The core insight**: keywords decouple *what a thing is* from *what it does and how it looks*. A shotgun isn't a hardcoded class with hardcoded behavior — it's a bag of tags (`dmg:ballistic`, `role:sidearm`, `anatomy:cybernetic`). Anything reading those tags (combo arbiter, color dispatcher, score system, and eventually the renderer itself) responds to the tags, not the class name. Swap the tags, swap the identity. An Imp tagged `role:boss` behaves like a boss. A shotgun tagged `dmg:energy` scores like a plasma weapon.

**Why it matters beyond flavor**: keywords are the entire mod-authoring surface of this game. Anyone who isn't touching ZScript/C++ can still change gameplay — recolor a monster, make a wall climbable, set a weapon's recoil, define rarity, trigger a combo — through a text tag and a JSON file. This is *why* the `Keywords` construction bug (§2, item 9) mattered so much: it wasn't just a boot-blocking crash, it was the failure of the one mechanism that makes this game extensible to other people, not just this session.

**The concrete next step this unlocks**: add a `render:` namespace to `KEYWORDS.json` alongside the existing `anatomy`/`role`/`trait` namespaces. Have the renderer check it. `render:sdf_blob` vs `render:sprite` vs `render:msdf_glitch` becomes a per-monster, author-controlled dispatch — meaning the SDF blob-monster work (§3, item 12) can be added as ONE tagged enemy coexisting with every sprite-based monster through the exact same pipeline, not a flag-day rewrite of the whole roster.

---

## 7. SDF Vector-Enemy Vision (the long arc beyond §3 item 12)

Full identity commitment: enemies aren't sprites wearing a shader effect — they *are* the shader effect. Rendered live, per-pixel, every frame, as blended math shapes (circles/capsules/blobs via `smin` — smooth-minimum blending) instead of baked art.

**Reactive properties envisioned**: dynamic fluid animation, "3D-feeling" 2D shapes, vector stretching in reaction to damage/hit direction, scaling in size, flashing/color-shifting by state, and — the escalation mechanic — **damaged enemies of the same tag merging together into one bigger, more dangerous fused entity.**

**Honest cost breakdown** (from the earlier appraisal, preserved here since it's still accurate):
- The visual merge is the *cheap* half once the blend-shader math exists — two overlapping primitive sets naturally melt into one shape via `smin`. That's the whole point of the operator.
- The *expensive* half is gameplay bookkeeping: proximity detection between same-tagged damaged enemies, the fusion event itself (combine health, scale up the primitive set, recompute stats, destroy the absorbed actor), and deciding whether a fused enemy is just "bigger version of the same thing" or a genuinely new tier/archetype (a design call, not an engineering one — changes scope significantly either way).
- Current engine reality check: **zero** `smin`/metaball math exists anywhere in the shader tree today, and the current glow-spot data channel (§1, "capped" section) is a single shared global list, not a per-instance-many-primitives channel. This is genuinely greenfield, not an extension.

**Build order** (do not skip steps — each proves the next is worth attempting):
1. One enemy. 2-3 shape primitives. `smin` blend. Prove it looks and performs right in VR before anything else.
2. `merge:` keyword namespace gates which enemies are even allowed to fuse (author-controlled, same pattern as everything else — not a global rule).
3. Proximity + fusion event (health/stat merge, actor destroy/replace) — pure gameplay code, no new rendering tech needed once step 1 works.
4. Only after 1-3 prove out: consider splitting-into-children, full roster rollout, and mobile-tier performance budget.

---

## 8. Setpiece Designer + Behavior-Reactive Combos + AI Reuse

Three related ideas from the same conversation, extending the plan past §3 Batch 3:

**Setpiece Designer**: generalize the boss-encounter-director idea (§3, item 8) into a proper authoring layer — combat beats (spawn wave, telegraphed attack, phase transition, arena change) described in a JSON file, with keywords tagging which enemies/weapons/effects slot into which beat. Same philosophy as `KEYWORDS.json`/`sdf_combos.json`: the fight becomes data, not hand-coded ZScript, so new setpieces don't require touching code at all.

**Weapon-based combos reacting to behavior**: extend Brand/Brass Storm/Buckshot (§1, already real) from "this weapon always does this effect" to "this weapon's effect changes based on what the enemy is doing" — panicking, charging, fleeing, mid-merge, whatever state the keyword/AI system exposes. This is enrichment of the existing combo-arbiter context, not a new system.

**Leverage existing free AI mods**: don't hand-write pathing/decision-tree logic from scratch when a solid, free, license-compatible mod already solved a piece of it. Consistent with the project's standing rule on art/code provenance (assets reused freely, code never cloned — same line already drawn with Brutal Doom references). Specific candidate mods get identified when we're actually at this step, not guessed now.

---

## 9. MSDF Toolchain Packaging (mod-author convenience)

**The gap this closes**: `msdf_atlas.fp` expects a generated MSDF font/sprite atlas image that has never actually been produced — `vr_assets/msdf/` is empty. A working `msdf-atlas-gen.exe` (v1.4.0) already exists as a side-effect of the main engine build (`build/bin/Release/msdf-atlas-gen.exe`) — confirmed identical version to the fresh copy on the user's Desktop (`Desktop/MSDF/msdf-atlas-gen-master`), so no separate build is needed for the tool itself.

**The packaging ask**: ship the generator tool (+ its `giflib`/`msdfgen` dependencies) *inside* the mod distribution, not as a one-off dev-only artifact — so any future mod author can regenerate/add fonts and atlases themselves without needing to rebuild the engine or involve the original developer.

**The convention to extend it with**: this codebase already has an established, working pattern for exactly this kind of author convenience —
- `KEYWORDS.json` / `sdf_combos.json` — plain-JSON, no-code-required configuration, already real.
- A locked naming convention for SDF assets: `[SetID]_[PrimaryKeyword]_[EventKeyword]_[VariantIndex].sdf`.
- Browser-based JSON editor tools (`sdf_combo_authoring.html` + a sibling) — a designer edits in a friendly UI, exports JSON, engine reads it, zero code touched.

The font/atlas packaging should follow the **same** convention, not invent a new one: a mod author drops a font file + a small JSON describing it (same naming discipline as `KEYWORDS.json`), and the packaged tool + engine pick it up the same way `KEYWORDS.json` gets picked up at boot.

**UPDATE — pivoted and DONE for the sprite/GIF case**: `msdfgen`/`msdf-atlas-gen` turned out to be the wrong tool for full-color animated sprite art — they only generate distance fields from flat monochrome vector shapes (font glyph outlines) and have no raster input path at all; using them would have flattened all color out of the art. Built and shipped instead: `tools/sdf_authoring/gif_to_sdf_atlas.py` — a single self-contained Python script (Pillow + numpy + scipy, all already present, **zero compiler/toolchain needed**) that computes a proper single-channel signed distance field directly from each GIF frame's silhouette via `scipy.ndimage` distance transform, and stores it in the output alpha channel while leaving the original full-color RGB untouched. Placed in the same `tools/sdf_authoring/` folder as the existing HTML combo editors, so it ships with the mod automatically.

**Tested and verified working**, not just written: ran against a real reference GIF (`test.gif`, 22 frames) — output confirmed a genuine graduated distance-field gradient (36 distinct alpha values spanning the full 0-255 range, ~16% of pixels sitting in the near-edge band) with full per-channel color variation preserved (not flattened to grayscale). Outputs land as a packed grid-atlas PNG + a companion JSON (frame size, grid columns/rows, frame count, spread) — see `Desktop/SDF_TEST_OUTPUT/` for the proof-of-concept run.

**Still open, not done**: `msdf_atlas.fp` still hardcodes a 4×4 grid and does not read this tool's JSON output at all — wiring the shader to read `cols`/`rows`/`frameCount` dynamically (via a small per-actor data feed, same pattern as `msdf_enabled`/`msdf_color`) is the next concrete step that would make this tool's output actually renderable in-game, not just producible offline.

**`msdf-atlas-gen.exe` itself is still relevant** for its original purpose — real TEXT/font MSDF atlases (crisp glowing numbers/labels), where flat monochrome vector glyphs are exactly the right input. That deliverable (run it against one real font, wire the result into the font-rendering path) is still open and separate from the sprite/GIF pipeline above.

**Next planned layer — offline authoring tools using keywords + templates**: generalize the existing `sdf_combo_authoring.html` pattern (pick a trigger/value/flavor-text, export JSON, zero code touched) beyond just combos — to effect templates, SDF atlas settings, and monster/weapon keyword profiles. Same browser-form-to-JSON convention, just more categories covered, so mod authors keep building their own effects without ever opening ZScript or a compiler.

---

## 10. "SDF" Is Four Different Things In This Project — Don't Conflate Them

This confusion came up directly tonight and is worth locking down permanently, because getting it wrong leads to wrong scoping decisions (see the correction below).

### (A) The glow-spot channel — `level.AddGlowPanel` / `AddGlowSpotWiped`
- **What it is**: a shared, global, engine-side list of up to `MAX_WALL_GLOW_SPOTS` (16, artificially capped — see §1/§4) flat shapes drawn by the shader: digit panels, rings, discs, brackets, spirals.
- **Not a game object.** Cannot collide, cannot be picked up, has no gameplay identity. It's pure rendering — a shape gets added to a list, the shader draws it, that's the whole lifecycle.
- **Correct use**: combo numbers, damage pop-ups, kill marks, score bursts — anything that's purely visual and doesn't need to exist as a "thing" in the world.

### (B) Per-actor MSDF fields — `msdf_enabled` / `msdf_glitch` / `msdf_color` on `AActor`
- **What it is**: real fields living directly on the Actor class itself (fixed and confirmed working tonight — `DEFINE_FIELD` exports added, `msdf_color` corrected to the right type). Fed into the shader per-actor via `SetMSDFParams()`, completely separate from the glow-spot channel's 16-slot budget.
- **IS a real game object.** Whatever actor carries these fields is still a full Actor — collidable, pickupable, has inventory logic, whatever it needs to be. The fields just change *how it's drawn* (MSDF sprite path instead of a plain flat texture), not *what it is*.
- **Already proven**: `GITD_SDFImp` is a real, functional `DoomImp` rendered this way — tinted, glitch-flickering, still a normal monster underneath.
- **THE CORRECTION MADE TONIGHT**: an earlier claim that the six `hf_killrewards.zs` pickup bits "cannot be replaced with SDF" was too broad — that was true of channel (A) only. Channel (B) means a real pickup Actor (Health/Armor/Ammo bit, still fully collidable, still gives the player the item) can *also* be rendered via the MSDF path instead of a sprite — "spinning glowing SDF hologram that still works as a real pickup" is buildable now, no contradiction. Concrete next step: port one bit (suggested: the gold orb) to prove it.

### (C) The GIF→SDF atlas tool — `tools/sdf_authoring/gif_to_sdf_atlas.py`
- **What it is**: a *different distance-field technique* than (A) or (B)'s underlying font-style MSDF — a single-channel signed distance field computed via `scipy.ndimage` distance transform directly from a raster image's silhouette, stored in the alpha channel, with the original full-color RGB left untouched.
- **Why it's different from `msdfgen`**: `msdfgen` (the tool in `Desktop/MSDF`) only works on flat monochrome VECTOR shapes (font glyph outlines) — it has no raster/bitmap input path and would flatten color art to grayscale. This tool exists specifically because full-color animated sprite art needed a different, correct technique.
- **Status**: built and tested tonight against a real GIF, verified working (real gradient data, real color preservation). The *shader-side consumption* of this tool's output isn't wired up yet — `msdf_atlas.fp` still hardcodes a 4×4 grid and doesn't read this tool's JSON. That's the next concrete step to make its output actually renderable.
- **How it connects to (B)**: an Actor using the (B) MSDF-field path could sample frames from a (C)-generated atlas instead of a single static tint — this is the concrete mechanism behind "math-based monsters out of deconstructed GIFs."

### (D) True procedural/deformable SDF (the "blob monster" vision) — does not exist yet
- **What it would be**: monsters made of live math shapes (circles/capsules) blended with `smin` (smooth-minimum), rendered per-pixel, enabling real merge/stretch/split behavior — not sprite-based at all, not even MSDF-sprite-based.
- **Status: zero code exists anywhere in the shader tree.** No `smin`, no metaball math, nothing. This is the separate, genuine R&D arc from §7 — real, wanted, but categorically different from (B) and (C), which are both still fundamentally "a picture, made crisp/full-color," not "a shape defined by math that can flow and merge."

**One-line summary for future reference**: (A) is a visual-only shared effect list. (B) is a real actor that draws itself via MSDF instead of a sprite — usable today. (C) is the tool that generates full-color art for (B) to consume. (D) is genuine procedural geometry and is the only one of the four that's still pure R&D.

---

## 11. Attack Plan: Universal Keyword Coverage (guns, monsters, pickups, decorations, corpses, map geometry)

**Scope note**: this section covers DOOM_FRESH only. No other project trees.

### Current real coverage (verified against tonight's boot log, not assumed)
- **All weapons already carry real `Keywords "..."` data** — confirmed for every weapon including the newly-added ones: Rifle, Revolver, SMG, HandGrenade, Flamethrower, plus the full stock roster (Pistol, Shotgun, SuperShotgun, Chaingun, Chainsaw, RocketLauncher, PlasmaRifle, BFG9000). Depth varies (3 to 14 keyword values per weapon) — worth an audit pass for consistency, but coverage exists, this is NOT a from-scratch task.
- **All monsters already carry real `Keywords` data** — confirmed for the entire stock roster (Zombieman through SpiderMastermind). Same depth-consistency caveat as weapons.
- **Most pickups already carry keywords** — ammo (Clip/RocketAmmo/Cell/Shell), armor (ArmorBonus/GreenArmor/BlueArmor), powerups (Soulsphere/Megasphere/RadSuit/etc.), keys — all confirmed tagged in the boot log.

### Confirmed real gaps (zero `Keywords` lines found)
- **Decorations** (`wadsrc/static/zscript/actors/doom/doomdecorations.zs`) — checked directly, zero matches. Lamps, plants, barrels-as-decor, etc. carry no keyword data at all today.
- **Corpses** (`wadsrc/static/zscript/actors/doom/deadthings.zs`) — checked directly, zero matches.

### The surprising find: map geometry already has the field, just not the behavior
- `Line` and `Sector` **already have a native `Keywords` field** (`src/maploader/udmf.cpp:1197` `ld->Keywords`, `:1758` `sec->Keywords`), populated from UDMF map data at load time. This is NOT greenfield — it's an existing, working native field with exactly **one** behavior currently wired to it (`climbable`, auto-injected at `udmf.cpp:1204-1205`).
- **The gap isn't the field — it's that nothing reads `ld->Keywords`/`sec->Keywords` for door/lift/teleporter behavior.** Adding a `liftable`/`grabbable` keyword namespace and a handler that checks it on interaction is additive to something real, not new infrastructure.

### Attack plan, in order

1. **Audit + fill decorations and corpses.** Add `Keywords "..."` lines to `doomdecorations.zs` and `deadthings.zs`, following the exact same namespace conventions already established for weapons/monsters (`anatomy:`, `mass:`, `role:`) rather than inventing new ones. This is mechanical, low-risk, high-coverage work — the pattern is proven, just needs applying to two more files.

2. **Weight + grab/throw for decorative objects (lamps, etc.).** The mechanism already exists and is live: `KeywordDispatcher::IsThrowable(heldItem->Keywords)` runs today in `src/playsim/p_user.cpp` (lines 1504, 1691) for weapon throw logic. Extending this to decorations means: (a) tag the decoration with `mass:X` + a throwable/grab keyword (same `KEYWORDS.json` namespaces already used for weapons), (b) confirm/extend whatever makes an object "grabbable" in the first place (currently proven for held weapons/inventory items — decorations are static `Actor`/`Decoration` classes today, not held items, so there's a real open question here: does the grab system work on any actor found via a hand-reach check, or only on `Inventory`-type held items? **This needs a direct check before promising it "just works"** — flagging honestly rather than assuming.

3. **Door/teleporter "physically lift" mechanic.** Real native `Keywords` already exists on `Line`/`Sector` (see above) — the work here is: (a) add a `liftable`/`interactable` keyword namespace to `KEYWORDS.json` for map-geometry use (separate from the actor-facing namespaces, since lines/sectors aren't actors), (b) build a new interaction handler that checks a targeted line/sector's `Keywords` on a VR-grab action and drives door movement directly instead of only through the standard trigger-linedef-special flow. **This is the biggest, most novel item on this list** — doors triggered by physically grabbing and pulling, not by touching a linedef, is a real new interaction model, not just "add more keyword data." Should be scoped and prototyped on ONE door type before generalizing to all door/lift/teleporter geometry.

---

## 12. The Designed Keyword Taxonomy (from-scratch, inspired by HackFraud_dev's proven conventions — not imported)

**Scope note reiterated**: HF_Monster/HF_Weapon/Champions were examined for design inspiration only. No HF classes are being ported. The taxonomy below is designed so that IF HF-style content is ever loaded externally, our dispatcher can still read its tags — but nothing here requires importing HF itself.

**Key design decision — decoupled color semantics.** HF_Monster's tier ladder and the Champions mod's independent affixes both used "color" to mean two different mechanical things — that collision is resolved here by splitting into three separate, independently-optional axes: `tint:` (pure visual, no gameplay meaning), `rank:` (linear power-scaling, optional), `affix:` (named stackable special ability, optional). A monster can carry any combination of the three without ambiguity.

### Monster keywords
- `species:` — biological/mechanical type (imp, demon, human, spider, mechanical, undead)
- `role:` — combat function (fodder, skirmisher, floater, charger, bruiser, summoner, boss, miniboss)
- `trait:` — attack/behavior style, stackable (projectile, hitscan, melee, homing, summon, shadow, teleport, plasma, fire)
- `faction:` — allegiance grouping (hell, human, neutral, machine)
- `anatomy:` — damage-response category (flesh, mechanical, demonic, undead, ethereal)
- `vulnerability:` — explicit weak points with implied multiplier (head_crit, eye_crit, core_stun, explosive, melee)
- `rank:` — linear power tier, numeric or named (optional)
- `affix:` — named special ability, stackable (optional; e.g. `affix:regen`, `affix:teleport`, `affix:explosive_death`, `affix:clone_on_death`)
- `tint:` — pure visual recolor, zero mechanical meaning on its own
- `deathfx:` — which GITD death visual plays: `deathpool`, `seamreveal`, `ghostwalk`, `deathping`, `stylizedx`, `hexfield`, `hexrings`, `spiral`, `squarerings`, `star`, `sunburst`, `grid`, `firework`, `invertimpact` (impact-only), or `auto`
- `bosskit:` — boss-mechanic package (`captain` for orb-champion style, `none`)
- `summons:` — space-separated reinforcement roster
- `splitroster:` — space-separated death-fracture roster
- `combatstate:` — stackable eligibility flags (`knockdownable`, `laststand`, `staggerable`)
- `behavior:` — decision-making flavor, independent of stat scaling (calm, aggressive, erratic, defensive)

### Weapon keywords
- `class:` — archetype (pistol, revolver, smg, rifle, shotgun, chaingun, fist, chainsaw, flamethrower, rocket, plasma, bfg, railgun, grenade)
- `fire:` — mode, stackable (single, burst, rapid, auto, pump, spread, charge)
- `dmg:` — damage type, stackable (ballistic, melee, blunt, blade, pierce, explosive, fire, lightning, melt, energy, acid, cold) — same vocabulary monster `vulnerability:`/`deathfx:` routing and map `hazard:` read against
- `ammo:` — resource type (clip, shell, rocket, cell, none)
- `wield:mainhand` / `wield:offhand` — hand assignment
- `wield:onehand` / `wield:twohand` — grip requirement, ties into the existing stabilization system
- `throwable:light/medium/heavy` — throw-weight class, gates throw handling separately from precise `mass:`
- `slot:` — weapon-wheel/menu position
- `rarity:` — loot-quality ladder (cursed, trash, basic, common, uncommon, advanced, designer, prototype) — deliberately not `tier:`, never collides with monster `rank:`
- `recoil:` — force category (light/medium/heavy) or numeric
- `parry:` — parry-box size class (small/medium/large) or numeric extent

### Item / pickup / decoration keywords
- `itemtype:` — health, armor, ammo, currency, key, powerup, weaponmod
- `rarity:` — shared ladder with weapons
- `value:` — numeric currency/sell value
- `points:` — score value on pickup
- `mass:` — precise physics weight (already real)
- `throwable:light/medium/heavy` — same axis as weapons, extended to decorations/lamps
- `consumable:` — used up on pickup vs. persists as a held object
- `deathfx:` — reused from monsters, applies to destructible decorations (e.g. a barrel with `deathfx:firework`)
- `keytype:` — which lock this key opens (pairs with map `requires:`)

### Map geometry keywords (Line/Sector)
- `interact:` — interaction type (door, lever, button, teleporter, liftable)
- `liftable:` — can be physically grabbed and pulled, optionally with a resistance value
- `resistance:` — pull-force needed (pairs with `liftable:`)
- `climbable:` — already real, unchanged
- `requires:` — a `keytype:` value needed to open/use
- `teleport_type:` — instant, portal, timed
- `hazard:` — environmental damage on this sector, reusing the `dmg:` vocabulary

### Invented ballistic keywords (genuinely new — absent from both reference projects)
- `bullet_drop:` — gravity-affected fall magnitude (exists in JSON today, dead in the loader)
- `air_resistance:` — velocity decay over distance/time (exists in JSON today, dead in the loader)
- `muzzle_velocity:` — initial projectile speed (new)
- `zero_range:` — distance at which the weapon is "zeroed" — drop invisible at this range, increasingly visible beyond it (new — the concept that makes long-range VR aiming feel like a real gun)
- `falloff:` — damage-over-distance dropoff curve (new)
- `penetration:` — passes through thin targets/walls, ties to the existing `+RIPPER` flag (new)
- `ricochet:` — bounce-off-hard-surfaces chance/behavior, ties to existing `BounceType` (new)
- `spread_pattern:` — cone shape: circular / horizontal-biased / vertical-biased (new)
- `stagger_force:` — hit-interrupt magnitude, independent of raw damage, feeds `combatstate:staggerable` (new)

---

## 13. Where This Lands: Engine-Level File Map

Every keyword axis above needs to be **parsed** (loader) and **applied to real content** (per-actor `Keywords "..."` lines). These are two different kinds of work, in different files.

### Core engine plumbing (edit once, benefits everything)
- `wadsrc/static/zscript/actors/actor.zs` — `native String Keywords;` (the standing-debt fix from §2/§11, item 1). Every monster/weapon/item keyword above rides on this one field being real.
- `src/playsim/keyword_dispatcher.h` — extend `KeywordProfile` struct with new fields per new namespace (rank, affix list, deathfx, throwable class, ballistics fields: muzzle_velocity/zero_range/falloff/penetration/ricochet/spread_pattern/stagger_force)
- `src/playsim/keyword_dispatcher.cpp` — add real parse branches for every namespace currently missing one: `role`/`trait`/`anatomy`/`vulnerability` (the ISAY.txt-confirmed dead ones), plus all-new branches for `rank`/`affix`/`tint`/`deathfx`/`bosskit`/`summons`/`splitroster`/`combatstate`/`behavior`/`wield`/`throwable`/`rarity`/`recoil`/`parry`/`itemtype`/`value`/`points`/`consumable`/`keytype`/`interact`/`liftable`/`resistance`/`requires`/`teleport_type`/`hazard`, and the full ballistics set
- `wadsrc/static/KEYWORDS.json` — add the corresponding data blocks (this is the modder-editable side; the C++ parse branch is what makes each block real instead of decorative)
- `src/scripting/vmthunks_actors.cpp` / `thingdef_properties.cpp` — no change needed beyond the §2 `Keywords` fix; the `keywords` ZScript property already accepts a variable-length list

### Map-geometry interaction (new file, not an edit)
- New EventHandler (e.g. `wadsrc/static/zscript/engine/vr_grab_interact.zs`) — reads a targeted `Line`/`Sector`'s `Keywords` on a VR-grab action, checks `liftable:`/`interact:`/`requires:`, and drives movement/behavior directly. This is the one item with no existing file to extend.

### GITD deathfx dispatch hook (small edit to existing file)
- `wadsrc/static/zscript/radiance/gitd3_deathfx.zs` — `GITD_DeathFXHandler`'s dispatch logic gets one new check: if the dying monster's `Keywords` contains `deathfx:X`, dispatch directly to that named `GITD_FX_*` class instead of (or before) the current automatic tier-based pick.

### Content files that get actual `Keywords "..."` additions/extensions (not engine plumbing — data)
- **Weapons** — extend existing lines in `wadsrc/static/zscript/actors/doom/weapon*.zs` (rifle, pistol, revolver, smg, shotgun, chainsaw, grenade, flamethrower, etc.) with the new axes: `throwable:`, `wield:mainhand/offhand`, `wield:onehand/twohand`, `recoil:`, `parry:`, `rarity:`, and the full ballistics set
- **Monsters** — extend existing lines in `wadsrc/static/zscript/actors/doom/*.zs` (doomimp, cyberdemon, cacodemon, etc.) with: `rank:` and/or `affix:`, `tint:`, `deathfx:`, `combatstate:`, `behavior:`, `bosskit:`, `summons:`/`splitroster:` where relevant
- **Decorations** — add first-ever `Keywords "..."` lines to `wadsrc/static/zscript/actors/doom/doomdecorations.zs` (currently zero coverage): `mass:`, `throwable:`, `deathfx:` where destructible
- **Corpses** — add first-ever `Keywords "..."` lines to `wadsrc/static/zscript/actors/doom/deadthings.zs` (currently zero coverage): `anatomy:`, `mass:`
- **Items/pickups** — extend/add lines across the ammo/armor/powerup/key files with `itemtype:`, `rarity:`, `value:`, `points:`, `throwable:`, `keytype:` where relevant

### Honest sizing
Items 1 is mechanical (extend a proven pattern to two more files). Item 2 is mostly proven (the throw system already reads keywords) but has one real open question (does grab work on non-inventory actors) that needs a direct answer before committing. Item 3 is genuinely new interaction design — the keyword field exists, but "grab and physically lift a door" as a player action does not, anywhere in this engine today.

---

## 14. Engine-Pass Verification Swarm (2026-07-03) — re-check of §11-13, recoil deep-dive, ballistics expansion

An 11-agent verification/ideation swarm re-checked the proposed fixes against live source (some time had passed and other work landed in parallel), then did a grounded VR-recoil design pass and a second ballistic-keyword sweep. Findings below are all re-verified against actual current source, not assumed.

### 14.1 Re-verify: what changed since §11-13 were written

**Keywords property handler — unchanged, still a no-op.** Re-confirmed byte-for-byte: `native String Keywords;` still absent from `actor.zs`; `DEFINE_PROPERTY(keywords, L, Actor)` in `thingdef_properties.cpp:608-618` is still the empty stub; `gitd3_deathfx.zs:127`'s colliding local `keywords` field on `GITD_DeathEffect` is still there, unrenamed, and still actively used by that file's own `HasTrait()`/`GetTrait()` helpers. **Nothing has moved on this since it was found.**

**ISAY.txt bugs — two fixed, two still broken (one via a NEW mismatch):**
| Bug | Status now |
|---|---|
| `role`/`trait`/`anatomy`/`vulnerability` unparsed | **Still broken**, exactly as found. Bonus finding: `keyword_dispatcher.cpp` now also parses dead `actor`/`pickup` namespace branches that don't exist in the current `KEYWORDS.json` at all — leftover from a schema rename that wasn't fully propagated. |
| `ballistics` namespace unparsed | **FIXED** — now has a real parse branch (`keyword_dispatcher.cpp:173-193`), explicitly commented as a fix for the previously-dead namespace. |
| `GetWeaponOffsets`/parry keyed off literal `'weapons:'` prefix | **FIXED differently** — profiles are now stored as `"class:"+lowercase(name)` and weapons carry matching `class:` tokens, so `GetWeaponOffsets` now genuinely works for weapons whose name matches (Pistol/Shotgun/Chaingun). Note: SuperShotgun's JSON key (`supershotgun`) doesn't match its actual ZScript keyword (`ssg`) — a smaller latent gap, not the original bug. |
| Parry lookup (`hw_vrmodes.cpp:1206`) | **Still broken — new cause.** It now passes the raw C++ class name (`"Pistol"`, unlowered, unprefixed) into `GetProfile()`, which does a bare map lookup against keys like `"class:pistol"`. Never matches. Same symptom (parry never resolves), different root cause than before. |
| `parry_extent_*` never parsed from JSON | **Still broken**, exactly as found — no `val.HasMember("parry_extent")` anywhere in the loader. |
| `SDFComboArbiter` unregistered in `AddEventHandlers` | **Still broken**, exactly as found. Confirmed the *only* `AddEventHandlers` line in the whole tree (`mapinfo/common.txt:8`) still omits it; sibling handlers (`VRBlackoutHandler`, `HF_GlowHandler`, etc.) are all present, confirming this codebase requires explicit registration — nothing auto-registers. |

**GITD restructuring status — NOT started in the engine repo; happening in parallel across TWO diverging side-locations.** `wadsrc/static/zscript/radiance/` (26 files) is fully intact, `zscript.txt`'s includes for it are unchanged, `mapinfo/common.txt`'s handler list is unchanged, and files in that folder were edited as recently as *today*. Meanwhile:
- `E:/_gitd35_repo` — a live clone of `github.com/presidentkoopa/GITD-3.5`, a genuine standalone pk3 source tree with its own full asset/script set, actively committed to today.
- `C:/Users/Command/Desktop/RadianceControlPanel_v0.8` — a smaller, separate prototype subset with its own new `radiance_control.zs` "Presets & Menu Sync" file.
- **These two have already diverged from each other AND from the DOOM_FRESH engine copy** — e.g. three different byte-sizes of `gitd_shaderbridge.zs` exist across the three locations right now, and `gitd_sdfmonster.zs` exists in DOOM_FRESH but is missing entirely from GITD-3.5.
- **Practical implication**: any plan assuming the engine copy is about to be deleted/replaced is premature — nothing has been removed yet, only duplicated outward, and the duplicates don't agree with each other. Reconciling three forks is a real future task, not a formality.

### 14.2 Recoil system — grounded, then honestly corrected

**Correction to something claimed earlier in this document/session**: `A_VRRecoil` (`vr_weapon_helpers.zs:37`) is **dead, unused scaffolding** — zero call sites anywhere in the tree. The actually-live recoil path is native `A_Recoil(force)` → `VR_ApplyRecoil` (`hw_vrmodes.cpp:1144`), called directly from every shipped weapon's fire state with real, already-tunable per-weapon force literals (Pistol 0.8, Shotgun 3.0, SSG 4.0, BFG 8.0, Rocket 6.0, SMG/Plasma 0.15, Chaingun/Rifle/Revolver via `A_BallisticFire(recoil:)`). `vr_recoil` (the master cvar gating all of this) **defaults OFF** — worth remembering before assuming any of this is felt by default today.

**What's real**: recoil genuinely perturbs `AttackPitch`/`AttackAngle` (not just cosmetic), two-handing already dampens both climb *and* yaw drift (not just climb, as earlier assumed), and the weapon-model visual kick (`vr_recoil_offset`) is a real rendered transform. **Haptics are 100% C++-internal** — no ZScript wrapper exists anywhere for `VR_HapticEvent`/`Vibrate`; every hitscan weapon fires the identical hardcoded `"fire_weapon"` pulse regardless of weapon type. The `KeywordDispatcher`-driven per-weapon recoil/parry profile system (JSON has real `recoil_force`/`parry_extent` data authored) is confirmed **dead at three independent stacked points** (property no-op → fields never parsed → lookup key mismatch) — fixing any one alone does nothing.

**Recoil extension ideas — post-adversarial-review status** (six physical-feel + six mechanic ideas generated, then independently re-verified against source):

| Idea | Verdict | Note |
|---|---|---|
| Owned Climb (fight muzzle rise back down) | **Solid, ZScript-only today** | Rides existing live pitch-accum → AttackPitch perturbation |
| Recoil Debt (bad recoil accelerates wear) | **Solid, ZScript-only** (needs one shared native getter) | Cleanly scoped |
| Recoil Signatures (per-weapon chatter pattern) | **Needs adjustment** | Real mechanism, but cadence math didn't match actual shipped fire rates — needs retuning, not new code |
| Grip Redistribution (two-hand changes kick, not just climb) | **Needs adjustment** | Mischaracterized current behavior — stabilization already dampens yaw drift too; only kick-offset is untouched |
| Steady Hand (combo bonus on early hit) | **Needs one native getter** | Otherwise correctly scoped |
| Worn-Gun Judder (CND-driven unpredictability) | **Mechanism fine, justification wrong** | Cites an "existing CND system" that **does not exist in DOOM_FRESH** — that's an HF-mod-only concept from a different project. Rebuild the jitter source from scratch if wanted here. |
| Flow Shot (counter-recoil rhythm bonus) | **Not feasible without real new native work** | Needs controller motion/delta tracking that doesn't exist anywhere, C++ or ZScript. Also mischaracterized `VR_CheckWeaponParry` as motion-based — it's actually a static spatial check, no motion term at all. |
| Signature Recoil Patterns (directional per-weapon pattern) | **Split** | Magnitude/timing variation = fine today. A true *directional* (left/right) authored pattern needs a native change to `VR_ApplyRecoil` — yaw drift is currently hardcoded-random in native code, no ZScript override path exists. |
| Magnum Kick (recoil shoves the shooter) | **Correctly flagged as needing native work** | Also: the native code has a deliberate comfort-safety comment ("don't adjust the player's camera — could make them sick") guarding exactly this path. A "torso-cam jolt" variant would be reversing a deliberate safety guard, not just adding a feature — flag this explicitly to whoever scopes it. |
| Brace Stance (torso-brace stabilization tier) | **Bigger than described** | Needs genuinely new native torso-tracking (no such reference point exists anywhere in the codebase) — reviving the keyword pipeline gets this idea *nowhere*, contrary to how it was originally scoped. |
| Shot-Timed Haptic Pulses (per-weapon pulse pattern) | **Correctly flagged as native-only** | Bonus finding: every fire-haptic call site *also* fires a separate hardcoded `Vibrate()` immediately before `VR_HapticEvent` — a real fix has to touch both, not just add a wrapper. |
| Environmental Drag (underwater/wind recoil) | **Split, with a real risk flagged** | Underwater half is solid ZScript-only (real `WaterLevel` field). The "revive dead `A_VRRecoil`" plan for the wind half is risky — that scaffold bypasses the exact camera-safety design the live recoil system was built around; don't reuse it uncritically. |

### 14.3 Ballistic keywords — 28 new concepts, zero overlap with the original 9

Two independent sweeps (real-world firearms vs. VR-perception/feel) came back genuinely non-redundant with each other and with the original 9 (`bullet_drop`, `air_resistance`, `muzzle_velocity`, `zero_range`, `falloff`, `penetration`, `ricochet`, `spread_pattern`, `stagger_force`):

**Firearms-realism (18)**: `ammo_type` (terminal behavior: FMJ/hollowpoint/AP/frangible), `projectile_mass` (momentum vs. kinetic-energy tradeoff, independent of velocity), `fragmentation`, `velocity_variance` (shot-to-shot consistency), `yaw_instability` (in-flight tumbling), `barrel_length`, `suppressor_effect`, `barrel_heat_drift` (sustained-fire accuracy drift), `sonic_signature` (supersonic crack vs. subsonic thump), `tracer_visibility`, `wind_drift`, `arming_distance` (minimum safe-arm range for explosives), `proximity_fuse`, `choke_constriction` (shotgun pattern tightening), `pellet_count`, `overpenetration_transfer` (energy retained after passing through), `impact_force_transfer` (stretch-cavity vs. pass-through energy split), `armor_deflection_angle` (obliquity/ricochet off armor).

**VR-feel (10)**: `flight_scale` (exaggerated visual size so a shot is dodgeable at all), `catch_window` (mid-air interception timing/forgiveness), `deflect_response` (what happens when caught — reflect/drop/detonate/stick), `impact_punch` (felt weight independent of raw damage), `homing_leash` (acquisition cone/turn-rate/break-off instead of flat homing), `charge_bleed` (accuracy degradation from over-holding a charge weapon), `overheat_vent` (heat cycle requiring a physical player action to clear), `telegraph_tell` (mandatory wind-up sized to real human VR reaction time), `approach_cue` (audio doppler/peripheral glow compensating for narrow HMD FOV), `afterimage_trail` (visual streak for post-hoc origin reconstruction, since VR has no killcam/minimap).

### 14.4 Updated engine-pass priority, given all of the above
1. Restore the `Keywords` field (native declaration + rename the `GITD_DeathEffect` collision + real property-handler assignment) — still the single highest-leverage fix, still untouched.
2. Add the missing `role`/`trait`/`anatomy`/`vulnerability` loader branches, and clean up the dead `actor`/`pickup` branches reading a schema that no longer exists.
3. Fix the *new* parry mismatch (lowercase+prefix the lookup key at the `hw_vrmodes.cpp:1206` call site) and add the missing `parry_extent` JSON parsing.
4. Register `SDFComboArbiter` in `mapinfo/common.txt`.
5. Only then: layer in Batch-1-worthy recoil extensions (Owned Climb, Recoil Debt — no engine work needed) and the highest-value new ballistic keywords (`ammo_type`, `wind_drift`, `telegraph_tell`, `impact_punch` are strong VR-feel candidates to prioritize).
6. Treat the GITD three-way fork (engine copy / GITD-3.5 repo / RadianceControlPanel prototype) as its own reconciliation task before building further on any of them — don't let new work land in a copy that's about to be superseded without knowing which one wins.
