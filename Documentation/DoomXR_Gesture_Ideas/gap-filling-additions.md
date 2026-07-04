# Gap-filling additions (from the critique pass)

These fill holes the critique caught in the main catalog.

### Push-Wall Secret Shove

**Anchor:** world-relative — both hands (or one) pressed flat against a linedef/sector tagged as a secret-push panel, distinct from any body anchor  
**Trigger:** hand(s) detected palm-flat against the tagged surface with sustained forward force (GetHandVelocity sustained into the plane, not a tap) held through a short dwell, PLUS a real grip/trigger button held the whole time so it can't be triggered by just bumping into scenery and stays net-deterministic  
**Effect:** the wall grinds open as a real secret door once the dwell completes, with a stone-grind SFX and a GLOW-gradient dust-mote sweep rendered as billboard sprites (never raw particles) — the classic Doom 'is this wall suspicious?' press turned into an actual two-handed shove  
**Vibe:** this IS the 90s-Doom secret-hunting ritual made physical; every Doom player has walked up to a wall hoping for a secret, and this is the one gesture that lets them shove it open with their own hands instead of a hidden use-key check  
**Engine cost:** propose a new tagged special (e.g. a `secret:<tex>` naming convention mirroring the already-shipped `climb:<tex>` GRABMAP texture-tag system) plus a native check comparing sustained hand-forward-force against the sector plane normal, exposed as `Actor.VR_CheckWallShove(sector, hand)` — a small, clearly-scoped native ask riding an existing content-tagging pattern

### Cover Peek Lean

**Anchor:** whole-body — head position offset from the feet-derived root column, NOT a hand gesture at all  
**Trigger:** head drifts laterally past a threshold distance from the neutral standing column while positioned behind a tagged cover volume, scaled continuously rather than as a discrete tap; no button gates the lean itself since it's pure movement/visibility, but the actual shot still requires the real fire button, keeping the net-relevant action button-gated  
**Effect:** the player's own physical lean peeks the camera and hitbox origin out from behind chest-high cover while the weapon stays fully two-handed and ready the entire time, exposing only a sliver of silhouette proportional to how far they leaned  
**Vibe:** delivers Aliens-style corridor-combat tension and run-and-gun cover play with ZERO hand gestures required — the perfect hands-full-safe complement to a catalog otherwise full of reach-and-release ideas  
**Engine cost:** head tracking driving the camera is already native; the genuinely new ask is `AActor.VR_ExposedFraction(cover_volume)`, letting AI/hit-detection reason about partial exposure past a tagged cover linedef instead of a binary in/out-of-cover flag — a modest, clearly-scoped hook

### Vault Push-Off

**Anchor:** either/both hands planted flat on the top surface of a low, tagged Vaultable obstacle forward of the hip anchor  
**Trigger:** hand(s) detected in contact with a Vaultable-flagged prop/linedef top, followed by a sharp combined downward-then-forward velocity push (a real shove-off signature), with a real jump/vault button pressed at the moment of push — button is the net-safe confirm, the hand-plant is just the enabling read  
**Effect:** launches the player up and over the obstacle in one fluid motion; a single-hand plant leaves the other hand free to keep a weapon raised the whole time, landing directly back into normal run-and-gun movement with no animation lock  
**Vibe:** classic arcade run-and-gun momentum (Doom Eternal/Bulletstorm mantle-through-combat) that never interrupts the gunplay — exactly the 'never break stride' traversal beat this brainstorm keeps almost-reaching for but never lands  
**Engine cost:** reuses the gravity-plank rail-guard traversal's tagged-geometry pattern (a new `Vaultable` flag alongside the existing climb:<tex> convention) plus a native launch-impulse call, a natural sibling to the already-proposed `VR_WallPushOff` — propose `VR_VaultLaunch(player_t*, DVector3 contactPoint)`

### Backup Piece Draw

**Anchor:** low-behind-back, opposite hip from the main holster — a new hardpoint distinct from both hip slots and the upper-back sling slot  
**Trigger:** hand reaches behind and below the hip, crossing the body's own midline to a tucked-in-the-waistband hotspot, plus a real grip rising-edge — identical HP_ANCHOR_BODY + grip pattern already proven for every other hardpoint draw  
**Effect:** draws a small backup sidearm/derringer stashed at the small of the back, a fast last-resort panic-button pistol distinct from the primary hip holster and the two-handed shoulder-slung weapon  
**Vibe:** pulp/Western 'one more gun up my sleeve' trope plus Doom-guy never-truly-disarmed swagger; the one body anchor (back, low) the whole catalog's hardpoint sprawl never actually claims for itself  
**Engine cost:** purely another `FHardpointSlot` config-table entry using the exact HP_ANCHOR_BODY + HP_ACT_HOLSTER pattern already shipped for rHip/lHip/rShoulder/lShoulder — zero new C++ logic, just a new coordinate, the cheapest possible way to close the back-anchor gap

### Grab-Anything Improvised Bash

**Anchor:** world-relative — any small/medium loose scenery prop (pipe, chair, bottle, barrel) within reach, either hand  
**Trigger:** grip button pressed while the hand overlaps a prop actor flagged `Improvised` — the same proximity+button template already used for whip/sword pickup, just pointed at arbitrary tagged scenery instead of an authored weapon actor  
**Effect:** the prop becomes a temporary held item usable for velocity-triggered bash swings (reusing existing melee-swing detection) that degrades/breaks after a few hits and can be thrown away with a normal release-throw; meanwhile the player's real weapon auto-stows to a hip/back hardpoint for the duration instead of being dropped, so nothing is ever actually lost  
**Vibe:** the classic 'grab whatever's nearby and start swinging' VR affordance (Half-Life: Alyx/Boneworks energy), reframed with 90s-Doom improvisational chaos and Indiana Jones's grab-the-nearest-torch/chair scrappiness — a whole missing category  
**Engine cost:** the real new engine ask here is the auto-stow-not-drop behavior: extend the grip-intent arbiter with an `IMPROVISED` verdict adjacent to the existing GLOVE class, paired with a native call that parks the real weapon on the nearest free hardpoint slot rather than dropping it — this stow-on-grab pattern is the one genuinely new seam, and it's reusable by any future 'my hand is about to be busy' gesture

### Arm-Pump Sprint

**Anchor:** both hands, read against their OWN recent motion (a frequency/oscillation pattern), not a fixed body anchor  
**Trigger:** both hands swing in a sustained alternating or synchronized front-back pumping motion at a rate above threshold, read via the same position/velocity ring buffer already proposed for gesture-shape classification — a pure magnitude/frequency signal that works whether the hands are full or empty, no button needed since it's a continuous movement-speed input exactly like existing thumbstick locomotion  
**Effect:** forward movement speed ramps toward a sprint cap while the pumping continues, decaying back to normal walk speed once the arms go still  
**Vibe:** the single most literal 'feel the verb' read available for the run half of run-and-gun — you make yourself run faster by physically pumping your arms, and it works with a shotgun in each hand exactly as well as with empty hands  
**Engine cost:** genuinely new native ask: a per-tick oscillation-frequency accumulator on both hands (parallel to the position/velocity ring buffer proposed for `ClassifyGestureShape`), driving a `float vr_sprint_pump_scalar` fed into the existing movement-speed calculation — frame-accurate frequency detection is unreliable via ZScript Tick() polling, the same justification already used to argue Matrix Brace's stillness counter should be native

### Buddy Drag Revive

**Anchor:** both hands gripping a downed co-op ally's forearm/collar drag-point, world-relative to the ally's ragdoll  
**Trigger:** both hands overlap the ally's drag hotspot with grip held, then a sustained pull motion (GetHandVelocity hauling toward a tagged safe zone or just continuously) while a real revive-hold button is also pressed — the button is the net-safe confirm, the haul motion is flavor/positioning only  
**Effect:** physically drags the downed ally's ragdoll along the floor toward cover while reviving them over a dwell period, instead of a static kneel-and-hold prompt; during the drag the reviving player's own weapon auto-stows to a hardpoint (reusing the Grab-Anything auto-stow behavior) so they're never awkwardly one-handing a rifle while hauling a body  
**Vibe:** Aliens' 'leave no one behind' marine-squad desperation played as a genuine physical struggle instead of a progress bar — the arcade-coin-op 'continue?' beat reframed as an in-fiction rescue, and the catalog's only real co-op-specific combat gesture  
**Engine cost:** needs a real, clearly-scoped co-op native hook: `AActor.VR_DragTarget` parenting the downed ally's ragdoll position to the reviving player's hand offset each tic in a server-authoritative way (so it stays deterministic across clients), plus reuse of the proposed auto-stow hardpoint call

### Hit-Side Flinch Haptic

**Anchor:** none/global — but the OUTPUT is localized to whichever hand/side corresponds to where the last hit landed on the player's own body  
**Trigger:** purely passive and server-driven: on taking damage, the already-known hit location relative to player facing (front/back/left/right) fires the cue — no player gesture at all, so there's nothing to net-sync beyond data the server already has  
**Effect:** fires a sharp, side-matched VR_HapticPulse (a front-left hit buzzes the left controller harder, a back hit buzzes both faintly), giving an instant felt sense of 'where did that come from' with no HUD damage-direction arrow  
**Vibe:** Aliens' fog-of-war dread payoff — an unseen hit should feel like a physical flinch on that side of the body, reinforcing tension without breaking immersion with a UI element, and it's a simpler, lower-risk cousin of the gesture-triggered Cupped-Ear Threat Cue since it needs no player input at all  
**Engine cost:** small, low-risk native seam: extract the hit-direction-relative-to-facing that's likely already computed for damage numbers/floating text, and route it through the existing native VR_HapticPulse with a left/right intensity split — good first candidate to ship before the fancier gesture-triggered directional haptics elsewhere in the catalog

