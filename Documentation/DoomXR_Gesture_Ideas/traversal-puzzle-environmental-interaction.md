# Traversal, Puzzle & Environmental Interaction

_Indiana-Jones-style pulp adventure beats — relic handling, balance, climbing, brace puzzles — built on physical care and timing rather than button prompts._

### Sandbag Idol Swap — ⭐ TOP PICK

**Anchor:** world-relative (relic pedestal trigger volume, not body anchor)  
**Trigger:** Grip-release detected on a held 'Relic' actor while a substitute actor of matching Weight field is placed into the same pedestal socket within a short window; native pressure-plate sensor compares HeldWeight before/after instead of just presence-of-object.  
**Effect:** Same-weight substitute keeps the plate depressed and the vault stays quiet; wrong weight or a too-slow swap fires the trap (dart wall / rolling boulder spawn) immediately.  
**Vibe:** This IS the Raiders idol-and-sandbag beat, made physical: the player has to actually hold two objects, judge the trade, and commit the swap with their own hands instead of watching a cutscene.  
**Engine cost:** Small native add: a float Weight field on the existing vr_held_items(prop) class, and the pedestal sensor reads that field instead of a boolean occupancy check. Everything else (grip/release detection) is already native.

### Living Torch

**Anchor:** hand-held prop, world-relative light target (sconce/brazier)  
**Trigger:** Proximity+button touches a wall sconce to ignite a carried torch prop; from then on the torch actor itself becomes a moving light source the player carries and points.  
**Effect:** Nearby GLOW-tagged sector geometry brightens/dims as the torch actor moves near it, revealing hidden glyphs and safe paths in dark corridors instead of a static lit room.  
**Vibe:** Torchlight-in-hand exploration is core pulp-tomb atmosphere — carrying your own light into the dark, not walking through a pre-lit level.  
**Engine cost:** Real engine ask: current native GLOW system (Sector.SetGlowSpot) is a fixed point. Propose `Sector.SetGlowSpotActor(AActor source)` / a per-tick re-sample of glow origin bound to a carried actor's position, so the glow can move with the torch while staying strictly gradient-only (respects the zero-dynamic-lights constraint).

### Compass Dowsing

**Anchor:** chest-held prop, orientation-driven (OffhandPitch/OffhandAngle)  
**Trigger:** Player holds a compass/map item near chest anchor and holds the offhand still (low GetHandVelocity magnitude) for ~0.4s; the sustained low-velocity dwell 'locks on' a dowsing needle toward the nearest tagged quest objective.  
**Effect:** A small billboard-sprite needle/arrow settles and points toward the objective; jostling the hand makes it spin uselessly, encouraging a real 'hold it steady' physical beat instead of an instant HUD marker.  
**Vibe:** Old-world adventuring tool, not a UI waypoint — fits the pulp fantasy of divining your way through ruins with an artifact rather than a minimap.  
**Engine cost:** Mostly ZScript using existing OffhandAngle + GetHandVelocity. Optional native nice-to-have: `AActor.NearestTagged(FName tag)` helper so the search isn't an O(n) ZScript actor-iterator loop every tic.

### Rope-Bridge Arms-Out Balance

**Anchor:** shoulder anchor (both hands relative to shoulder height/offset)  
**Trigger:** While standing on a flagged 'balance beam' line/sector, continuously compare both hand positions to the shoulder anchor; symmetric arms-out posture with low GetHandVelocity = stable, asymmetric offset + velocity spikes (flailing) = wobble.  
**Effect:** Wobble state applies camera roll-sway / reduced traction on the plank; consciously holding arms out like a tightrope walker keeps the crossing steady.  
**Vibe:** The rickety rope bridge over the chasm is a genre staple — turning it into an actual embodied balance act (arms out, don't flail) sells the vertigo far better than a scripted sway.  
**Engine cost:** Extend the existing gravity-plank rail-guard traversal system with a new native player field, e.g. float BalanceStability computed from hand/shoulder offsets, and a per-node flag `RequiresBalance` on XR_GravityPath so it's engine-level physics feedback, not a scripted camera tween.

### Roll-Cancel Boulder Dodge

**Anchor:** whole-body: crouch-rate (feet-derived viewheight drop) plus both-hand velocity, world-relative dive vector  
**Trigger:** sharp crouch-velocity spike combined with both hands moving in a matched downward-lateral 'duck-dive' template within a short window; a dash/dodge button press within that window is the real net-safe confirm, motion only supplies direction and timing bonus  
**Effect:** brief i-frames plus a body-relative slide-dash in the lean direction; if timed inside a boulder/trap telegraph window, spawns a billboard 'STYLE!' popup, a haptic burst, and an arcade score bonus  
**Vibe:** Indiana Jones instinctive trap-dodge (duck under the rolling boulder) fused with 90s-arcade speedrun dash-tech scoring — the same survival duck doubles as a scored trick instead of just staying alive  
**Engine cost:** hand-intent arbiter (already generalizing from the grip arbiter) needs a new DIVE verb classifying crouch-rate + hand-velocity template; dash impulse can reuse/extend an existing movement native, button stays the confirm

### Snap-Catch Falling Relic

**Anchor:** world-relative (falling/knocked relic actor's predicted trajectory) + either hand  
**Trigger:** A fragile relic actor enters freefall (knocked off a pedestal); player moves a hand to intercept its predicted position and presses grip at the moment of contact.  
**Effect:** Successful catch saves the relic (and skips whatever alarm/shatter its fall would trigger) — a real 'gotcha' Indy moment; a missed catch lets it smash or clatter and alert nearby threats.  
**Vibe:** The reflex catch of a priceless artifact is a signature pulp beat — rewarding genuine hand-eye timing over combat skill.  
**Engine cost:** Reuse the existing ballistics/AttackPos prediction math already computing spread and trajectories for weapons; expose a generic `AActor.PredictedPosition(float dt)` helper so ZScript can test hand-position-vs-predicted-impact-point without duplicating physics.

### Two-Hand Pry-Open — ✋ needs a free hand

**Anchor:** environmental prop handle/bar (dual hand grip, reusing weapon capsule test)  
**Trigger:** Both hands grip a crate lid / stuck door bar / sarcophagus lid via the existing native two-hand CAPSULE test, then twist (relative roll delta between the two hand quaternions) and pull apart (increasing hand separation) over several ticks.  
**Effect:** Incremental progress bar as the lid groans open; on completion it pops with a treasure spray (billboard-sprite gold sparkle, no dynamic light) instead of an instant 'press E' open.  
**Vibe:** Wrenching open a stuck sarcophagus or treasure crate with both hands is exactly the tactile, slightly-dangerous discovery moment the genre wants.  
**Engine cost:** Near-zero new native code — this directly reuses the already-built native two-hand capsule grip system (currently weapon-only) against a PryableProp actor type; just needs the capsule test generalized to accept a non-weapon target.

### Palm-Plant Piton — ⭐ TOP PICK

**Anchor:** wrist/palm, world-relative (wall surface normal)  
**Trigger:** Hand's palm-normal aligns with the nearest wall surface normal (dot product above threshold) while in reach of a climbable-tagged texture, plus a grip press — 'slaps' a piton into the wall.  
**Effect:** Spawns a piton actor and registers it as a new GravityDir/climb node on demand, letting the player author their own foothold route on any climb:<tex> surface instead of only using pre-placed climb geometry.  
**Vibe:** Driving your own handhold into a cliff face mid-climb is a pure Indy improvisation beat — cleverness and daring over a fixed ladder.  
**Engine cost:** Extends the existing GRABMAP climb:<tex> system. Needs a `AActor.TraceFromHand(int hand)` native helper returning hit actor/normal/texture at the hand position, so ZScript can spawn dynamic climb nodes instead of relying only on pre-authored geometry.

### Steady-Hand Relic Placement

**Anchor:** world-relative (pedestal socket) + hand velocity  
**Trigger:** Hand hovers over a pedestal anchor holding a relic; GetHandVelocity magnitude must stay under an epsilon for a sustained dwell window before grip-release counts as a clean placement rather than a drop.  
**Effect:** A careful, motionless release sets the relic down safely; releasing while the hand is still moving fast registers as a fumble/tip, which can tip a trap or chip the artifact's value.  
**Vibe:** Handling priceless treasure should feel different from tossing ammo in a pouch — this makes 'be careful with that' a literal physical requirement, not a prompt.  
**Engine cost:** Pure ZScript using the already-exposed GetHandVelocity — a genuine zero-new-native cheap win to pair with the flashier asks above.

### Torch Throw / Burn the Bridge

**Anchor:** hand-held torch prop, world-relative brazier or rope-bridge target  
**Trigger:** Reuses the existing throw-release velocity detection (already driving the sword's boomerang) but applied to a torch-class prop; on impact with a Brazier actor it ignites it, on impact with a RopeBridge actor it severs/burns it.  
**Effect:** Lighting a distant brazier from across a chasm to reveal the way forward, or hurling the torch to burn the rope bridge behind you and strand pursuers — a genuine risk/reward traversal choice.  
**Vibe:** 'Burn the bridge behind you' is a defining pulp-escape trope, and lighting the path ahead with a thrown torch is classic tomb-exploration flavor distinct from combat throws.  
**Engine cost:** Entirely reuses the existing throw/release detection plus the native GLOW toggle hook — flagged as content-only, zero new native code, just a new prop class and two impact-target actor types.

### Fragile-Relic Hip Stow

**Anchor:** hip pouch anchor (distinct FSM branch from the ammo pouch)  
**Trigger:** Reaching to the hip anchor with a relic flagged Fragile gates a slower two-stage stow (cup hand under the relic, then push it into the pouch) rather than the quick-draw motion used for ammo; rushing the motion or skipping the dwell causes it to 'clatter'.  
**Effect:** Treasure gets stowed safely with a deliberate, careful motion; slamming it in like a shotgun shell degrades its condition or makes noise that can alert nearby threats.  
**Vibe:** Differentiates how you physically handle a priceless relic versus a spare mag — treasure deserves its own tactile respect, reinforcing the adventurer fantasy over the shooter fantasy.  
**Engine cost:** Reuses the already-shipped native chest/hip pouch reach-and-grab FSM built for manual reload; just needs a new state branch keyed on the held item's Fragile flag. Small diff since the plumbing already exists.

### Two-Hand Overhead Brace — ⚠ needs button for MP · ✋ needs a free hand

**Anchor:** temple/helmet-height (both hands raised overhead, palms forward)  
**Trigger:** Both hands enter capsule-contact with the leading face of a closing-wall trap or oncoming rolling hazard, palms oriented against its surface normal (via OffhandDir), sustained contact starts a stamina-drain brace check.  
**Effect:** Player physically holds back a closing stone door or props up a collapsing ceiling for as long as they can sustain the brace; letting go too early gets them crushed, holding it lets an ally/objective clear.  
**Vibe:** 'Hold the door/ceiling with everything you've got' is a tense, non-combat physical set-piece straight out of the genre's collapsing-temple climaxes.  
**Engine cost:** Reuses the native two-hand capsule detection again, but generalized to test against an environment hazard actor rather than a weapon barrel axis — propose lifting VR_TwoHandCapsuleTest out of the weapon-only path into a general AActor utility.

### Vine Hand-Over-Hand Swing — ✋ needs a free hand

**Anchor:** hand-held rope/vine prop, world-relative pendulum physics  
**Trigger:** Grip a dangling vine/rope segment (proximity+button) then drive pawn movement the same way the existing velocity-driven wall-climb works (pawn.Vel = -(handVel)) while the rope itself swings underneath as a pendulum.  
**Effect:** A genuine jungle hand-over-hand swing across a gap or chasm, distinct from both the whip's grapple-swing and the gravity-plank walk — pure Tarzan/Indy traversal beat.  
**Vibe:** Swinging hand-over-hand across a ravine on a loose vine is a signature pulp-jungle set piece that feels different in the body from grappling with the whip.  
**Engine cost:** Reuses two existing systems as libraries: the velocity-driven climb model and the whip's own Verlet rope solver. Only new native ask if the Verlet solver isn't already decoupled: extract it into a shared VerletRopeComponent so non-whip actors (a plain vine prop) can use the same physics.

### Light-Shaft Rune Alignment — ⚠ needs button for MP

**Anchor:** shoulder/arm-extended reach (hand raised above shoulder anchor into a tagged LightShaft volume) + wrist roll  
**Trigger:** Raise a held relic with the arm fully extended (per the existing IK reach) into a tagged overhead light-shaft volume, then roll the wrist until the engraved rune reaches within tolerance of a target angle, held for a short dwell.  
**Effect:** Puzzle door unlocks as the GLOW gradient shifts color/intensity in response to correct alignment — direct visual feedback with zero dynamic lights involved.  
**Vibe:** This is the 'headpiece in the light, turn it just so' Raiders-of-the-Lost-Ark medallion trope made literal — cleverness and precision, not combat, solves the room.  
**Engine cost:** Reuses the existing IK wrist-rotation read and native GLOW gradient system almost entirely; only possible new ask is a small target-rotation-tolerance helper if one doesn't already exist from the parry/aim-assist code, otherwise pure ZScript content.

