# Tension, Threat-Sense & Danger Haptics

_Aliens-style dread and situational-awareness gestures rendered as haptic waveforms, directional audio, or billboard cues rather than HUD markers — felt, not read._

### Motion Tracker Sweep — ⭐ TOP PICK · ✋ needs a free hand

**Anchor:** wrist/forearm (off-hand raised to chest/eye height, tracker screen leveled toward player)  
**Trigger:** off-hand must be holding the 'Motion Tracker' item; proximity filter = hand height rises above the hip anchor into chest/eye band AND pitch stays near-horizontal (screen facing player) for dwell > 0.25s; a real button press starts the active sweep (net-safe), after which passive tracking updates while the pose holds  
**Effect:** spawns a small billboard-quad display bone-attached to the hand showing pip blips for nearby hostile actors within radius; beep audio rate AND same-hand VR_HapticPulse frequency both scale up as the nearest hostile closes distance, so the beeping and the buzzing in your actual hand get faster and more frantic  
**Vibe:** THE iconic Aliens hardware ritual (Hicks/Vasquez tracker checks); replaces a minimap with a held prop and physical unease instead of UI  
**Engine cost:** mostly ZScript composing existing hooks: native VR_HapticPulse for the beep-buzz, a hand-bone-attached billboard sprite (respects no-particle/no-dynamic-light constraints); only new native surface needed if there's no efficient 'nearest N hostiles within radius' query yet -- propose AActor.CountHostilesInRadius if missing

### Dread Pulse — ⭐ TOP PICK

**Anchor:** none / global -- delivered as a real physical signal on both controllers  
**Trigger:** passive, no player gesture initiates it; each tic a 'ThreatLevel' scalar is computed from nearby hostile count/distance, player health fraction, and local light level (darker = more dread)  
**Effect:** VR_HapticPulse rate and intensity on both hands map to a heartbeat BPM curve -- a slow single thump when clear, a racing double-thump when something is close or flanking -- so tension is FELT as real vibration rather than read off a meter  
**Vibe:** the single most Aliens-tension mechanic possible: the game makes your own pulse race instead of showing you a number  
**Engine cost:** propose a new native seam -- a per-tick VR_UpdateDreadPulse hook (CVar-gated vr_dread_haptic) computing ThreatLevel from existing AI-awareness/proximity queries and driving the already-native VR_HapticPulse at a variable frequency; a native tick hook gives more frame-accurate cadence than ZScript Tick() polling

### Cupped-Ear Threat Cue — ⚠ needs button for MP · ✋ needs a free hand

**Anchor:** hand cupped near the player's own ear, temple-adjacent anchor, sustained pose  
**Trigger:** hand held in a cupped near-ear pose within the temple anchor radius for a dwell period at low velocity — a deliberate 'listen' pose, distinguishable from the flashlight temple-tap by dwell+cup versus a quick tap  
**Effect:** triggers a directional haptic 'heartbeat' pulse on that hand/ear side, its intensity and side indicating the nearest unseen threat's bearing, with no visual HUD marker  
**Vibe:** Aliens' auditory-dread 'did you hear that?' trope combined with 90s-arcade off-screen-enemy edge indicators (Smash TV/Robotron-style), delivered as a felt haptic compass instead of a screen marker to keep it diegetic  
**Engine cost:** the existing haptic-pulse native (VR_HapticPulse) needs a directional/side-selective intensity variant plus a nearest-hostile bearing query exposed to ZScript — a small, clearly named native seam

### Divining Ears — ✋ needs a free hand

**Anchor:** bilateral temple/helmet anchor — both hands cup the sides of the head like an 'I can't hear you' listening gesture  
**Trigger:** Both hand positions dwell near the temple/helmet anchor SIMULTANEOUSLY (not a single tap like the flashlight toggle) for a sustained ~0.5-1s, confirmed by a held grip button on at least one hand to avoid accidental triggers from just scratching your head; distinguished from the flashlight gesture by requiring both hands + dwell instead of one hand + tap  
**Effect:** Triggers a directional 'secret sense' ping: the hand physically closer to the map's nearest undiscovered secret gets a distinct haptic pattern (a slow heartbeat pulse via VR_HapticPulse) that intensifies as the player turns toward it, like an Indiana-Jones divining rod — no HUD marker, pure haptic wayfinding so it doesn't break immersion  
**Vibe:** Secret-sense slot — Doom's secret-hunting dopamine is core to the lens, and routing the answer through directional haptics (not a UI arrow) keeps it feeling like a diegetic 90s-adventure trick rather than a modern quest marker  
**Engine cost:** The gesture detection is pure ZScript (anchor math + dwell timer already how climb/pouch gestures work). The real native ask is new: a per-hand DIRECTIONAL haptic (today's VR_HapticPulse is presumably a flat intensity/duration on one controller) needs an angle-weighted intensity curve computed from player-yaw-vs-secret-bearing, which is cheapest done natively each tic in p_user.cpp where the arbiter already runs, exposed as a CVar-tunable 'secret sense' radius so level designers/mappers aren't required to hand-place hint actors

### Startle-Flinch Hazard Reveal

**Anchor:** whichever hand passes near a tagged hazard actor (trap/pit/dart wall)  
**Trigger:** sharp velocity reversal (fast approach then hard negative acceleration/pull-back) within a hazard's proximity radius — an involuntary flinch signature; kept render-scope/cosmetic only by construction, no net-relevant effect, so it needs no button gate  
**Effect:** nearby tagged hazards render a brief native-glow outline pulse (about half a second) plus a sharp 'yank back' haptic on that hand — a reveal, not an auto-dodge  
**Vibe:** Indiana Jones's 'the trap almost got you' punish-carelessness beat paired with Aliens motion-tracker-style hazard revelation, except the 'device' is your own flinch reflex instead of a held tool  
**Engine cost:** hand-intent arbiter needs a new FLINCH verb (velocity-reversal template) plus a lightweight native call to flag hazard actors for a glow-pulse — a small, well-scoped addition alongside the existing glow-gradient system

### X-Block Flinch Guard — ⚠ needs button for MP

**Anchor:** forearms crossing in front of face/chest  
**Trigger:** both hands detected moving rapidly inward and upward toward the chest/face anchor simultaneously -- a velocity-spike-toward-center signature on both hands via GetHandVelocity within the same short window; deliberately no button since a flinch has to fire instantly  
**Effect:** local-only: brief camera-shake dampening and an audio duck (like flinching shields your senses) plus a small capped knockback-resistance nudge, kept minor enough to stay meaningless for competitive net-play -- it never becomes a hard damage-negation without a button behind it  
**Vibe:** rewards an honest physical flinch in a dark corridor -- pure fight-or-flight instinct made mechanical  
**Engine cost:** exactly the kind of raw-motion-to-verb classification the in-flight hand-intent arbiter is meant to grow into -- propose adding a 'GUARD' verb (both-hands-inward velocity spike) alongside the existing NONE/CLIMB/GLOVE/WHIP/HARDPOINT/TWOHAND classes

### Acid-Blood Recoil — ⚠ needs button for MP

**Anchor:** weapon/hand position relative to a freshly-killed acid-blooded corpse (world-relative proximity)  
**Trigger:** an acid-blooded kill opens a short hiss-warning window near the corpse; the player must physically yank the weapon-hand backward away from it (GetHandVelocity away-from-corpse threshold) within that window  
**Effect:** success = no consequence; failure (hand/weapon lingered in the splash zone) gives the held weapon a temporary corroded-look model swap via the existing weapon-archetype render-swap hook, plus a brief accuracy/handling debuff  
**Vibe:** THE quintessential Aliens hazard beat -- acid blood eating through the deck -- turned into a genuine physical reflex test rather than a cutscene  
**Engine cost:** reuses the existing FVRWeaponResolver archetype-swap hook to show a corroded model variant (no new native render code); the hazard timer and velocity check are ZScript -- if DoomXR has no weapon-condition scalar yet (HF has one), propose a lightweight ZScript-side corrosion counter on the weapon actor first

### Sentry/Mine Plant-and-Arm

**Anchor:** world-relative floor point (off-hand reaches down past the hip toward the ground)  
**Trigger:** two stage: (1) proximity filter = off-hand height drops below the hip anchor toward the floor plane while holding a deployable item; (2) an open-palm grip-release places the device at that floor point; (3) a separate short reach-tap on the placed prop (proximity + brief dwell) or button press arms it  
**Effect:** placing spawns the mine/sentry inert on the floor; arming lights a native Sector.SetGlowSpot indicator (no dynamic light, respects the hard constraint) and starts an audible arming tick; armed sentries auto-track hostiles, mines wait for a proximity trip  
**Vibe:** the Aliens sentry-gun/motion-tracker-perimeter setup ritual -- kneeling to secure a chokepoint before it all goes wrong is pure marine tension  
**Engine cost:** extend the in-flight hand-intent arbiter with a new 'PLACE' verb (adjacent to existing HARDPOINT/GLOVE classes) for the downward-reach-and-release motion; the armed indicator reuses the existing native GLOW gradient system, no new lighting hook needed

### Flare Snap-Ignite

**Anchor:** hip draw into a wrist-snap motion  
**Trigger:** draw a flare from the hip anchor (reach+grip like a sidearm draw), then a sharp downward wrist-snap detected as a GetHandVelocity spike along the hand's local -Y axis within a short window -- ignites the flare; a subsequent normal throw-release launches it  
**Effect:** the ignited flare becomes a billboard sprite actor (avoiding the particle-invisible-in-VR trap) with a GLOW-gradient light pool once it lands, usable to bait enemies toward light or momentarily part the dark  
**Vibe:** glow-stick-snap physicality (pulp-adventure) paying off as horror-lite dread relief when the corridor finally lights up  
**Engine cost:** mostly ZScript composing existing native GetHandVelocity + the GLOW gradient system + the established billboard-actor pattern; no new native hook strictly required

### Rail Light Toggle

**Anchor:** foregrip/barrel axis (the existing native two-hand capsule grip zone)  
**Trigger:** off-hand already gripping the two-hand capsule zone (the native barrel-axis capsule test is the proximity filter, already shipped) + a distinct button press on that hand (not the main trigger) toggles the light  
**Effect:** toggles a forward-facing GLOW-gradient beam / laser-sight line mounted on the weapon model itself (respecting the zero-dynamic-lights constraint) -- a distinct fixture from the personal temple-tap flashlight, useful for corridor sweeps and target designation  
**Vibe:** the classic USCM pulse-rifle weapon-light look, reinforcing claustrophobic corridor-clearing without duplicating the existing personal-flashlight gesture  
**Engine cost:** directly reuses the existing native two-hand capsule grip test as the enabling filter -- no new detection needed; only new work is wiring a button-bit in that grip state to a light/laser toggle rendered via the existing GLOW system, a cheap adjacent extension

