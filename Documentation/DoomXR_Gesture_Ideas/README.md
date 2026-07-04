# DoomXR VR Gesture Ideas

81 curated ideas across 9 categories, plus 8 gap-filling additions.

Legend: ⭐ top pick · ⚠ pose-only, needs a real button-bit before multiplayer · ✋ needs a free hand (cuts against fire-while-hands-full)

## Categories

- [Finishing Moves & Kill Flourishes](finishing-moves-kill-flourishes.md) — 8 ideas
- [Combat Buffs, Rituals & Power Stances](combat-buffs-rituals-power-stances.md) — 7 ideas
- [Arcade Score & Showboat Flourish](arcade-score-showboat-flourish.md) — 6 ideas
- [Loot, Rarity & Elemental Weapon Flourish](loot-rarity-elemental-weapon-flourish.md) — 8 ideas
- [Body-Mounted Gadgets & Quick-Draw](body-mounted-gadgets-quick-draw.md) — 10 ideas
- [Tension, Threat-Sense & Danger Haptics](tension-threat-sense-danger-haptics.md) — 10 ideas
- [Gear-Check & Readiness Rituals](gear-check-readiness-rituals.md) — 6 ideas
- [Traversal, Puzzle & Environmental Interaction](traversal-puzzle-environmental-interaction.md) — 14 ideas
- [Engine-Level Foundations & New Native Hooks](engine-level-foundations-new-native-hooks.md) — 12 ideas
- [Gap-filling additions](gap-filling-additions.md) — 8 ideas

## Top picks (build these first)

- **Rip-and-Tear Glory Rend** — Auto-snaps the corpse into a scripted rip-apart gib (billboard-sprite gore chunks per the no-particle rule), grants a brief invulnerability flicker + score/combo pop, both controllers get a native VR_HapticPulse double-tap (one per hand) timed to the rip
- **Bore-Through Plunge** — Locks the saw into the target, ramps a rising-pitch haptic pulse train (VR_HapticPulse frequency increasing tic over tic) simulating resistance, then pops a big gib payout + combo-multiplier tick once the dwell completes — pulling back early aborts with only a stagger, rewarding commitment
- **Whip-Yank Ground Pound** — the enemy is slammed into the floor (or into a nearby hazard for an environmental kill), dealing a heavy finisher hit with a ground-crack GLOW burst, billboard debris sprites, and a strong haptic pulse
- **Trophy Tilt Reveal** — a GLOW-gradient color sweep plays across the item keyed to rarity tier, an SDF rarity-name + 'ta-da' text billboard pops beside it, and a small haptic tick fires on the holding hand
- **Motion Tracker Sweep** — spawns a small billboard-quad display bone-attached to the hand showing pip blips for nearby hostile actors within radius; beep audio rate AND same-hand VR_HapticPulse frequency both scale up as the nearest hostile closes distance, so the beeping and the buzzing in your actual hand get faster and more frantic
- **Dread Pulse** — VR_HapticPulse rate and intensity on both hands map to a heartbeat BPM curve -- a slow single thump when clear, a racing double-thump when something is close or flanking -- so tension is FELT as real vibration rather than read off a meter
- **Sandbag Idol Swap** — Same-weight substitute keeps the plate depressed and the vault stays quiet; wrong weight or a too-slow swap fires the trap (dart wall / rolling boulder spawn) immediately.
- **Chamber Peek** — replaces the numeric HUD ammo counter with a physical look-and-see chamber/mag-well close-up (a bone-attached indicator near the weapon rather than a HUD corner readout) plus a stuck-round visual tell if the weapon is jammed, encouraging players to self-verify state instead of glancing at a number
- **Palm-Plant Piton** — Spawns a piton actor and registers it as a new GravityDir/climb node on demand, letting the player author their own foothold route on any climb:<tex> surface instead of only using pre-placed climb geometry.
- **Shoulder Sling Quick-Draw** — Instantly swaps whatever's in that hand for the two-handed weapon slung there (rifle/shotgun/whip); empty-hand reach quick-draws it pre-gripped for an immediate two-hand barrel-capsule hold. Metal-shlick sound + a VR_HapticPulse tap confirms the swap.
- **Cross-Arm Guard Stance** — raises a temporary native guard flag reducing melee knockback/stagger and granting brief hit-forgiveness against a lunging melee attacker -- a physical 'brace for impact' read
- **Gravity Wall Push-Off** — launches the player with an impulse along the outward normal in GravityDir-relative space -- a real hand-driven push-off for parkour through the flipped-gravity plank sections, beyond just walking the planks

## What's still missing (critique gaps)

- Push-wall/secret-shove discovery: Doom's single most iconic interaction ("press on the suspicious wall") has zero direct physical-shove coverage. Divining Ears/Dread Pulse only give a directional haptic hint toward secrets — nothing lets the player actually lean both hands into a wall panel and feel it grind open.
- Lean-peek from cover using body/head offset (not hands): nothing uses the player's own physical lean (feet-root vs. head offset) to peek a sliver of hitbox out from behind chest-high cover while the weapon stays two-handed and ready. This is a core VR-shooter-tension trope, and notably it's the one gesture family that's inherently hands-full-SAFE since it uses body lean instead of a hand reach — a big miss given how many other ideas require releasing the weapon.
- Locomotion gestures are almost entirely absent: no arm-pump-to-sprint mechanic, no vault/mantle-over-low-cover push-off. The catalog's 'run-and-gun' coverage is all about the 'gun' (finishers, buffs, flourish) and none about the literal 'run' — a real hole given GetHandVelocity is explicitly available and idle for this.
- The 'back' body anchor named in the primer's six anchors (chest, hip, shoulder, temple, forearm/wrist, back) is essentially untouched on its own terms — it only shows up repurposed as an upper-back/nape coordinate for the big-gun sling. No low-back/waistband backup-piece draw, no shoulder-blade-scratch-style gesture.
- Environmental improvised-weapon grab (picking up ANY loose prop — pipe, chair, bottle — as a temporary bash weapon) is a whole missing category, despite fitting both 90s-Doom chaos and Indiana-Jones scrappy improvisation, and despite the whip/sword grip-detection template being trivially reusable for it.
- Localized/directional damage haptics are missing. Dread Pulse gives an ambient global heartbeat and Cupped-Ear Threat Cue/Divining Ears give a proactive gesture-triggered directional ping, but nothing purely REACTIVE maps 'which side of my body just got hit' to a felt haptic side-cue — a simpler, lower-risk cousin of those ideas that's conspicuously absent.
- Co-op-specific gestures are almost entirely missing. Nearly the whole catalog is single-player-framed; only Shoulder Mic Key and Overhead War Cry gesture at squad play. There's no ally-revive/drag, no ammo/item hand-off-to-teammate gesture, despite Aliens-squad-tension being a named target vibe.
- GravityDir-relative anchor recomputation is never addressed: the primer states body anchors derive from feet position + viewheight + facing angle (implicitly assuming normal gravity), but the project also ships wall/ceiling walking via GravityDir. Whether chest/hip/shoulder anchors even make sense upside-down or sideways is a real unaddressed hole given how much of the catalog (and the engine) leans on GravityDir elsewhere.
- Weapon-to-weapon mid-air toss-and-catch swap (throw current gun up, snatch replacement off hip/back before it lands) is absent — a flashier, more kinetic alternative to the many 'reach-to-anchor-and-grip-swap' hardpoint draws, none of which involve an actual mid-air handoff.
- Underhand/lob throwing motion is never distinguished from the overhand throws assumed everywhere (grenades, torch throw, boomerang sword recall) — no bank-shot/around-corner lob option, despite it being a mechanically distinct arm motion worth its own gesture read.
- The catalog never resolves what happens to a currently-held two-handed weapon's off-hand foregrip when a puzzle/utility gesture (Compass Dowsing, Motion Tracker Sweep, Living Torch, Bandolier Cinch) occupies that same hand — no auto-sling/one-handed-penalty answer is proposed anywhere, leaving a structural design gap between the weapon-handling systems and the prop-holding systems.
