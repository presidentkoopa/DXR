# Finishing Moves & Kill Flourishes

_Physical execute/finisher gestures that end a fight with a scripted payoff (gib, slam, snap, punt, environmental kill) — snap-trigger combat centerpieces distinct from normal gunplay._

### Rip-and-Tear Glory Rend — ⭐ TOP PICK

**Anchor:** world-relative — both hand positions converge on a staggered enemy's torso/head hitbox  
**Trigger:** Enemy enters a native 'execute-eligible' HP-threshold state (like Doom 2016 stagger-glow); player closes to melee range, both grip buttons held simultaneously (native TWOHAND-style dual-grip check, reusing the same two-hand capsule logic already used for foregrips), then AActor.GetHandVelocity(0) and GetHandVelocity(1) read sharply DIVERGENT vectors (hands yanking apart) past a tuned speed floor within a short window  
**Effect:** Auto-snaps the corpse into a scripted rip-apart gib (billboard-sprite gore chunks per the no-particle rule), grants a brief invulnerability flicker + score/combo pop, both controllers get a native VR_HapticPulse double-tap (one per hand) timed to the rip  
**Vibe:** This is the arcade glory-kill fantasy distilled to the one gesture Doom players already mime at their screens — two-handed tear satisfies the chainsaw-gib instinct even on non-chainsaw kills, and it's the finishing-move slot the lens explicitly asks for  
**Engine cost:** Mostly ZScript on top of existing hooks — GetHandVelocity is already exposed and dual-grip is just reading vr_grip_owner[2] on both hands. The one real native ask: an 'execute-eligible' flag/threshold on the monster (a bool or HP-percent field checked in p_interaction.cpp's damage path) so the game can gate the stagger-glow and know when to accept the gesture instead of a normal punch

### Bore-Through Plunge — ⭐ TOP PICK

**Anchor:** world-relative — chainsaw barrel axis driven forward into an enemy's chest/torso volume  
**Trigger:** Native two-hand capsule grip already active on the chainsaw (vr_grip_owner == TWOHAND) AND GetHandVelocity of the main hand shows a sustained forward thrust exceeding a speed floor while the barrel-axis capsule overlaps a living monster's bounding volume for several consecutive tics (a real 'push it in and hold' motion, not a tap)  
**Effect:** Locks the saw into the target, ramps a rising-pitch haptic pulse train (VR_HapticPulse frequency increasing tic over tic) simulating resistance, then pops a big gib payout + combo-multiplier tick once the dwell completes — pulling back early aborts with only a stagger, rewarding commitment  
**Vibe:** This is the chainsaw's 90s power fantasy at its purest — leaning your whole body into the saw like the original Doom guy sprite — and it reuses the native two-hand capsule test that already exists for foregrips  
**Engine cost:** The capsule-vs-monster overlap test over multiple consecutive tics is the one piece that doesn't fully exist yet — today's two-hand capsule is barrel-vs-grip-point, not barrel-vs-enemy-hitbox. Propose extending the native capsule test (same code path in the grip arbiter) to optionally test against nearby AActor bounding boxes, exposed as a thunk like AActor.VR_BarrelOverlapsActor(), so this and future 'impale' mechanics share one native primitive instead of each weapon re-deriving it in ZScript

### Stagger-Point Snap Execute

**Anchor:** shoulder anchor of the targeted staggered enemy (reach toward its shoulder/collar, not your own)  
**Trigger:** An enemy is in the native stagger-glow state (same eligibility flag proposed for Rip-and-Tear) and within melee range; the player's main hand reaches out and its grip button is squeezed at the moment the hand-to-enemy-shoulder distance crosses a close threshold, while the offhand simultaneously does a short forward stab motion (a velocity-spike thrust, read the same way as any punch/melee swing today)  
**Effect:** Snap-executes the enemy with a scripted knife/blade takedown animation (or bare-hand neck-snap if unarmed) and a directional haptic 'thunk'; because it's a snap on contact rather than a held dwell, it's built for a DIFFERENT moment than Rip-and-Tear — a fast single-enemy pick-off mid-crowd instead of a big two-hand centerpiece finisher, so the two coexist as a quick option vs. a flashy one  
**Vibe:** Finishing-move slot's 'quick and stylish' sibling — Doom running-and-gunning needs a FAST execute you can do without stopping your feet, distinct from the showy two-hand rip, which matters for keeping run-and-gun momentum unbroken  
**Engine cost:** Reuses existing melee-swing velocity detection plus the same proposed stagger-eligibility flag from Rip-and-Tear (one native flag serves both finishers, which is the efficient path). No separate new hook beyond that shared flag

### Whip-Yank Ground Pound — ⭐ TOP PICK

**Anchor:** melee range directly in front of the player, immediately following the shipped whip entangle/yank  
**Trigger:** once the existing whip-yank has landed an enemy in melee range and marked it entangled/dazed, the free/main hand does a sharp downward velocity spike (GetHandVelocity Z strongly negative) above threshold with grip held during the swing  
**Effect:** the enemy is slammed into the floor (or into a nearby hazard for an environmental kill), dealing a heavy finisher hit with a ground-crack GLOW burst, billboard debris sprites, and a strong haptic pulse  
**Vibe:** the exact leash-kick combo this lens asks for — Bulletstorm's yank-then-finish rhythm realized on the already-built whip system  
**Engine cost:** reuses the shipped whip entangle/yank state machine; the downward-slam classification should ride the same new verb slot proposed for Boot Shove Kill rather than being a one-off addition to the arbiter

### Overhead Idol Slam Finisher

**Anchor:** both hands raised above the temple/helmet anchor, then converging downward together  
**Trigger:** both hands rise above head height and hold briefly (telegraph wind-up), then converge downward with matching high velocity; a melee/finisher button press at the top of the wind-up keeps timing player-intentional  
**Effect:** executes a staggered enemy with a two-handed overhead slam, triggering screen-shake, a billboard 'MEGA KILL' text popup, and a brief slow-mo — pure combat feedback, no loot payload  
**Vibe:** Indiana Jones's heavy-idol/overhead-ritual physicality driving a 90s-arcade finisher-callout dopamine hit, deliberately about the visceral heft of the motion rather than a loot reward  
**Engine cost:** mostly content-level; the only native-adjacent piece is a symmetric two-hand SLAM verb template in the hand-intent arbiter, inverting the existing two-hand capsule/stabilize logic into a converging gesture

### Called Shot Point

**Anchor:** offhand aim (OffhandDir/OffhandAngle) at a staggered enemy's head/weak-point hitbox  
**Trigger:** enemy is in a staggered/dazed state and within short range; offhand orientation is dotted against the enemy's head-bone direction inside a tight cone at the moment the actual fire button lands the kill (fire button is the real trigger, offhand-point is the arming condition)  
**Effect:** killing the staggered enemy while offhand is pointed at its weak point triggers a brief VR-safe time dip (no camera shake), an SDF 'EXECUTED'/style-name popup billboard, and a bumped loot-rarity roll on the drop  
**Vibe:** Bulletstorm called-shot showmanship fused with a Borderlands rarity payoff — rewards precision instead of spray  
**Engine cost:** mostly ZScript on existing OffhandDir + AttackPos; only needs an enemy 'staggered' flag readable from ZScript if one isn't already exposed — the kill itself stays on the normal server-authoritative fire button so it's net-safe by construction

### Boot Shove Kill

**Anchor:** hand overlapping an enemy's torso volume at melee range, grip held  
**Trigger:** GetHandVelocity(hand) forward-thrust magnitude spikes above threshold while the hand overlaps the enemy's torso and grip is held during the swing — classified as a new 'SHOVE/STRIKE' verb  
**Effect:** enemy launches backward with a knockback impulse toward the nearest hazard; hitting spikes/fire/a pit counts as a Bulletstorm-style environmental kill, plus a big haptic pulse on the shoving hand  
**Vibe:** pure Bulletstorm 'kill with the environment' arcade satisfaction, made physical instead of a QTE  
**Engine cost:** propose extending the hand-intent arbiter's verb enum (currently NONE/CLIMB/GLOVE/WHIP/HARDPOINT/TWOHAND) with a SHOVE verb that reads velocity-vs-actor-overlap; the resulting knockback impulse should still resolve through a real server-authoritative call for net safety, same pattern as the grip arbiter

### Boot the Corpse — ⚠ needs button for MP

**Anchor:** hip anchor, sweeping forward-down  
**Trigger:** A hand crosses the hip anchor with a sharp forward-and-down velocity spike (GetHandVelocity) while a fresh corpse/ragdoll actor is within a short reach radius — essentially a soccer-style boot swing aimed low  
**Effect:** Sends the corpse ragdoll flying with an impulse, satisfying the classic 'punt the dead imp across the room' arcade urge; chaining several boots without missing ticks up a small 'field goal' style combo counter and a haptic thump on contact  
**Vibe:** Pure 90s Doom arcade silliness — this is the physical-comedy beat that makes a game feel alive between real fights, the same energy as gibbing a corpse for fun rather than necessity  
**Engine cost:** ZScript-buildable using GetHandVelocity + existing ragdoll/ThrustThingZ-style impulse calls; no new native hook strictly required, though if ragdolls aren't already real physics actors (vs. static death-frame sprites) that's a pre-existing engine capability question worth confirming before promising the effect, not something to invent here

