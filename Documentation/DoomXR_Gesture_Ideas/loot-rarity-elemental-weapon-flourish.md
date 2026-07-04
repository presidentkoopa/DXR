# Loot, Rarity & Elemental Weapon Flourish

_Borderlands-style loot reveal beats and elemental status application/cycling gestures riding the native GLOW-gradient and weapon-archetype render hooks._

### Trophy Tilt Reveal — ⭐ TOP PICK

**Anchor:** held loot-drop item raised into the temple/helmet head-anchor radius  
**Trigger:** item bone position enters the head-anchor radius and dwells there (~0.4s) — no button needed since it's a cosmetic, render-scope-only reveal  
**Effect:** a GLOW-gradient color sweep plays across the item keyed to rarity tier, an SDF rarity-name + 'ta-da' text billboard pops beside it, and a small haptic tick fires on the holding hand  
**Vibe:** turns the Borderlands loot-beam ritual into something you physically hold up to your own face and admire  
**Engine cost:** need to confirm whether a per-actor transient GLOW attach exists (today's GLOW hook is Sector.SetGlowSpot, sector-scoped); if not, propose that as the seam — an AActor-attached glow pulse would generalize to lots of future feedback FX — otherwise fall back to a glow-palette billboard sprite, no new native required

### Backpack Spin Inspect

**Anchor:** loot item held within the chest-pouch anchor  
**Trigger:** the holding hand's orientation roll delta (frame-to-frame) exceeds a slow, deliberate-turn threshold while grip is held and the item is inside the chest-pouch radius — distinguishes 'twirling to inspect' from just carrying it  
**Effect:** the item visually self-rotates 1:1 with the hand's roll input in an isolated inspect bubble (mini Alyx-style), with a stats/name panel anchored beside it  
**Vibe:** the Borderlands 'hold the gun up and turn it over' loot fantasy, done as a real wrist motion  
**Engine cost:** needs per-tick orientation on the item-holding hand; OffhandRoll/Pitch/Angle already exist for the offhand — propose mirroring HandRoll/HandPitch/HandAngle for the main/weapon hand as the seam if the item ends up in that hand, otherwise it's ZScript-only today using the existing offhand fields

### Torch Dip Ignite

**Anchor:** world-relative — weapon muzzle brought near a fire-source actor (torch, burning barrel, lava)  
**Trigger:** muzzle-bone distance to the fire-source actor drops under a radius, plus a grip/trigger hold to confirm the 'dip'  
**Effect:** weapon gains Incendiary status for N shots and a small billboard flame sprite rides the muzzle  
**Vibe:** elemental application as a physical dip instead of a menu-selected mod — pure Indiana Jones torch-in-the-temple texture over classic Doom fire hazards  
**Engine cost:** fully ZScript-buildable today from actor-to-actor distance checks plus existing weapon status-effect flags; no new native required — good quick-win candidate

### Static Charge Crank

**Anchor:** offhand position along the barrel axis while the native two-hand capsule grip is active  
**Trigger:** offhand GetHandVelocity oscillates sign along the barrel axis (a rapid back-and-forth 'crank/rub') for 3+ reversals within ~1s while the TWOHAND grip state holds  
**Effect:** weapon charges to Shock status, an arcing billboard-sprite crackle climbs the barrel, and the next hit chain-lightnings to nearby enemies  
**Vibe:** tactile, hands-on elemental application with the exact status-effect flash a looter-shooter needs  
**Engine cost:** mostly ZScript using the existing capsule two-hand grip state plus buffered GetHandVelocity samples; if oscillation counting proves jittery in practice, propose a lightweight native 'rolling reversal-count' helper in the same spirit as the arbiter's hysteresis CVars — optional, not blocking

### Vial Snap Corrosive

**Anchor:** a chest-pouch-drawn vial item brought against the weapon barrel anchor  
**Trigger:** a sharp wrist-twist velocity spike while the vial is gripped against the barrel, plus a button press for the twist-off action  
**Effect:** the vial actor is consumed, the barrel gets a billboard-splash coating, and the weapon applies Corrosive status for N shots  
**Vibe:** Aliens marine 'crack a flare/chemlight' physicality repurposed onto a Borderlands corrosive element  
**Engine cost:** ZScript-only — held-item consumption already exists via the vr_held_items pattern from the weapon-hand ruleset; the 'snap' is just a velocity-spike-plus-button gate, no new native needed

### Trophy Pouch Toss

**Anchor:** a ground loot-drop item, thrown/carried toward the chest-pouch anchor  
**Trigger:** item is grabbed and carried into the chest-pouch reach radius (reusing the exact proximity-enables/button-confirms pattern already proven for ammo), with grip release inside the radius as the confirm  
**Effect:** the item auto-sorts into inventory with a rarity-colored GLOW flash and a shared 'ta-da' SDF popup (same reveal beat as Trophy Tilt Reveal), plus a satisfying chest-thunk haptic  
**Vibe:** makes Borderlands loot pickup a physical toss-into-your-vest ritual instead of a silent walk-over auto-pickup  
**Engine cost:** pure content/ZScript extension of the already-shipped chest-pouch reach-and-grab keystone; no new native required — cheapest idea on the list to prototype

### Twist-Lock Mod Cycle — ⚠ needs button for MP

**Anchor:** off-hand inside the weapon's existing two-hand foregrip capsule zone  
**Trigger:** off-hand is inside the native two-hand capsule test and performs a wrist twist — OffhandRoll delta exceeds a threshold while inside the capsule — read as a deliberate 'twist the mechanism' rotation rather than an incidental grip shift  
**Effect:** cycles the weapon's equipped elemental/attachment mod one step per clean twist, with a mechanical-thunk haptic and the weapon visibly reconfiguring via the existing weapon-archetype model-swap hook  
**Vibe:** Indiana Jones's 'twist the ancient stone mechanism to open it' hand-feel repurposed as looter-shooter mod/attachment cycling, using the two-hand capsule as a rotary dial instead of only a stabilizer  
**Engine cost:** capsule detection and OffhandRoll are already native/exposed; only new work is a ZScript mod-cycle state machine reacting to roll-delta-while-in-capsule, likely needing no new native surface at all

### Loot Vacuum Backhand Sweep

**Anchor:** chest/hip plane, either hand, dominant lateral velocity component  
**Trigger:** a wide backhand/forehand sweep where the hand's velocity vector is dominated by the lateral (side-to-side) axis rather than forward/back, exceeding a speed threshold at chest-to-hip height — the enabling filter; a grip/trigger press during the sweep is the real confirm that actually collects items  
**Effect:** nearby loose drops within a short radius are pulled toward the chest-pouch anchor with an escalating 'cha-ching' jingle scaled by item count, then actually collected on the button confirm  
**Vibe:** looter-shooter's 'vacuum up everything in the room' dopamine (Borderlands loot-suction) combined with 90s-arcade's satisfying full-room item-clear sweep, turned into one deliberate physical clearing gesture instead of walking over every pickup  
**Engine cost:** mostly ZScript reusing the existing chest-pouch anchor and the lateral component of GetHandVelocity; a native batch-magnetize helper may be worth adding only if item counts get large, since the button still gates the actual net-relevant pickup

