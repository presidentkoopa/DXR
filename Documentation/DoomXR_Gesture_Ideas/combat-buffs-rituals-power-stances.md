# Combat Buffs, Rituals & Power Stances

_Gesture-triggered self/ally buffs and power activations (berserk, overcharge, war cry, BFG windup) that turn popping a powerup into a physical ritual instead of a menu press._

### Pull-Cord Rev

**Anchor:** hip-level, on the hand NOT holding the chainsaw (offhand reaches down past the hip anchor next to the saw's motor housing)  
**Trigger:** Player is holding a chainsaw-class weapon; offhand crosses the hip anchor and GetHandVelocity(offhand) shows one sharp downward-then-up yank (a real pull-cord motion, detected as a velocity sign-flip on the vertical axis within ~200ms) — no button needed for the flavor rev, but a real grip-bit still gates any gameplay-affecting version  
**Effect:** Chainsaw does a visible/audible pull-start rev-up flourish (idle players already do this on quarter-munchers), and if the yank lands in a tight speed window it grants a timed 'hot rev' buff — faster gib-through on the next few kills. A bad/lazy yank just plays the cosmetic rev with no buff, so it's low-risk showboating with a skill ceiling  
**Vibe:** Chainsaw-specific slot — it's THE Doom prop, and a literal pull-cord gesture (not just holding trigger) makes revving feel mechanical and arcade-tactile instead of a HL2 gravity-gun hum  
**Engine cost:** Pure ZScript reading GetHandVelocity's sign flip, gated by a CVar-tunable window (vr_chainsaw_pullcord_ms). If it ships as gameplay-affecting (the hot-rev buff) rather than cosmetic, propose a native per-weapon 'FlourishWindow' timestamp field on the weapon instance so the buff timer survives weapon switches/saves cleanly instead of living in a fragile ZScript state var

### Gorilla Berserk Slam

**Anchor:** bilateral — both hands cross above the temple/helmet anchor, then slam down past the chest anchor  
**Trigger:** Player is carrying an uncommitted berserk pack pickup (collected but not yet 'popped'); both hand positions dwell above the helmet anchor simultaneously for a beat, then GetHandVelocity(0) and GetHandVelocity(1) both spike downward together within the same tic window, confirmed by both grip buttons being held through the whole motion (arms-raised dwell + button hold is the generous-radius/context-gate the drift problem demands)  
**Effect:** Pops berserk immediately with a red-flash screen effect, a beefy dual-hand haptic slam pulse, and (this is the flourish part) leaves a shockwave-style knockback on nearby weak enemies so the activation itself is a mini-attack, not just a menu toggle  
**Vibe:** Berserk/power-up activation slot — chest-thump-then-slam is the most primal 'I am about to wreck this room' gesture there is, distinct from the seed's single temple-tap-for-flashlight because it's bilateral, dwelling, and destructive rather than a quick toggle-tap  
**Engine cost:** Fully buildable in ZScript on existing anchors + GetHandVelocity + grip buttons — no new native needed for detection. The knockback-on-activation is just a small AoE thrust reusing whatever push/force code already backs the whip's yank, so this is a good 'ship it in ZScript first' candidate per the project's own POC-then-native pattern

### Overhead BFG Charge Ritual

**Anchor:** world-relative — weapon raised above the helmet anchor, held with native two-hand grip  
**Trigger:** vr_grip_owner reads TWOHAND on the BFG-class weapon AND the weapon's position dwells above the helmet anchor (arms raised skyward) while the charge button is held; dwell time directly drives charge percentage instead of a fixed timer  
**Effect:** A rising-frequency haptic pulse train and a native GLOW-gradient pulse on the weapon (no dynamic lights, per the hard constraint) build as the ritual holds, releasing early fires a weaker shot while a full dwell fires the max-charge blast — turns the BFG's already-iconic windup into a physical ritual instead of a held trigger  
**Vibe:** This is the 'quarter-muncher big-gun moment' — every arcade shooter has one weapon you hold overhead like a trophy before the screen-clearing payoff, and raising the BFG like a ritual offering fits the Doom-meets-pulp-adventure tone precisely  
**Engine cost:** Mostly composition of existing pieces (TWOHAND grip state, anchor dwell, GLOW gradient for the charge-visual instead of a banned dynamic light). The charge-percent-from-dwell-time is a small new field worth being explicit about — a per-weapon 'ChargeDwellTicks' accumulator is cleanest living in the native weapon FSM alongside the reload state machine rather than bolted on in ZScript, since that FSM already owns per-weapon tic-accurate state

### Double-Fist Overcharge

**Anchor:** both hands driven simultaneously to the chest anchor  
**Trigger:** GetHandVelocity(lefthand) and GetHandVelocity(righthand) both point inward toward the chest anchor and exceed a combined speed threshold on the same tick, with either grip pressed at the moment of impact (the button press is the real activation edge for MP determinism; the fist-thump just gates when it's allowed)  
**Effect:** activates a timed action-skill buff (damage/fire-rate/adrenaline), a GLOW pulse radiates outward from the torso, and both hands get a strong haptic pulse  
**Vibe:** the literal 'slam your vault-hunter skill button' moment, but it's your own fists hitting your own chest — aggressive Doom-marine bravado  
**Engine cost:** fully ZScript-buildable from existing GetHandVelocity plus body anchors; no new native required, the button press already keeps it net-safe

### Overhead War Cry

**Anchor:** weapon-hand position raised above the temple/helmet anchor height  
**Trigger:** weapon-bone height exceeds the helmet anchor for a ~0.5s dwell, plus a held button to confirm (raising alone shouldn't fire a real gameplay effect per the net-safe rule)  
**Effect:** a timed rally buff applies (to self, or nearby allies in co-op), the weapon and hand flare with GLOW, and an SDF banner text plus roar cue plays  
**Vibe:** Aliens 'let's go, marines!' chest-beating morale beat, readable across a room in co-op  
**Engine cost:** ZScript-only, reuses existing helmet/temple anchor math and button state; no new native needed — low-risk candidate

### Bandolier Cinch Overcharge — ✋ needs a free hand

**Anchor:** chest bandolier/pouch anchor, both hands simultaneously  
**Trigger:** both hands grip the chest-pouch anchor together and pull apart laterally with high symmetric velocity (a 'cinch tighten' motion); proximity is the filter, the two-hand outward velocity spike is the trigger, gated by an actual button hold so it can't misfire during ordinary single-hand pouch reaches  
**Effect:** spends banked arcade combo/score meter for a short rapid-fire/reload-speed TURBO buff; the physical bandolier mesh lights notch-by-notch via native glow gradient as it runs  
**Vibe:** Aliens marine bandolier iconography plus 90s-arcade 'crank the turbo lever' power-meter trope — a second, distinct two-handed gesture layered on the existing single-hand pouch-reload anchor  
**Engine cost:** reuses the existing chest-anchor proximity primitive from the pouch-reload keystone; needs a new two-hand symmetric-pull template in the hand-intent arbiter and, if absent, a native combo/turbo-buff field

### Double-Slap Pop — ⚠ needs button for MP

**Anchor:** chest anchor (the existing ammo-pouch reach point)  
**Trigger:** Two rapid taps of a hand against the chest anchor within a tight time window (a real double-tap, distinguished from the single reach-and-dwell already used for the ammo pouch so the two gestures can't be confused) while carrying an uncommitted powerup pickup  
**Effect:** Instantly self-activates the held powerup without opening any menu/wheel — a fast, physical, no-UI alternative to a wrist-wheel selection for the single most time-critical case (you're about to die, pop the item NOW)  
**Vibe:** This is deliberately adjacent to (not a copy of) the wrist-wheel seed: the wheel is for browsing/choosing among several gadgets, this is the panic-button muscle-memory slap for when there's no time to look at your wrist — pure arcade urgency  
**Engine cost:** Pure ZScript double-tap timing against the same chest anchor already computed for the pouch, gated so it only fires when the pouch-reload reach ISN'T also in progress (reuse the existing enable/trigger separation pattern). No new native hook needed — good low-risk addition alongside the shipped pouch keystone

