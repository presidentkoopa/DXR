# Arcade Score & Showboat Flourish

_Pure style/score layers on top of existing actions (twirls, flicks, quickdraw timing) that never change core function — reward showing off without any risk of abuse._

### Trophy Fist Pump

**Anchor:** overhead — the hand that landed the killing blow crosses above the temple/helmet anchor  
**Trigger:** Within a short window after a kill event, the credited hand's position crosses above the helmet anchor and its grip button is squeezed into a fist-hold for a beat (dwell, not just a pass-through, so an accidental raised hand mid-reload doesn't false-trigger)  
**Effect:** Extends the active combo-multiplier timer by a flat bonus and plays a quick arcade 'COMBO!' stinger + screen-corner flash, stacking visually the more consecutive kills get fist-pumped; whiffing the pump (no fist within the window) just lets the combo decay normally, so it's pure upside for players who bother  
**Vibe:** Combo-multiplier slot — turns the abstract 'combo timer' most looter-shooters bury in a corner HUD number into a physical celebration beat the player performs themselves, which is exactly the quarter-muncher dopamine loop the lens wants  
**Engine cost:** Entirely ZScript-buildable: kill-credit already knows which hand fired (AttackPos/hand index exists per the weapon-hand ruleset), and the anchor-cross + grip-dwell pattern mirrors the existing pouch-reload template exactly. No new native hook needed — good candidate to prototype first and see if it even needs one

### Gunslinger Twirl

**Anchor:** wrist-relative — the weapon-holding hand's roll axis  
**Trigger:** Weapon is idle (not mid-fire, not mid-reload-FSM) and the holding hand's roll angle sweeps continuously through roughly a full rotation within a short time window, read the same way OffhandRoll already feeds the palm-out cast gate — just applied to whichever hand holds the current ready weapon instead of the offhand  
**Effect:** Plays a one-handed twirl flourish animation on the 3D in-hand model (leveraging the existing weapon-archetype render hook), ejects a cosmetic spent-shell/casing billboard sprite, and grants a small 'showboat' score bonus with a light haptic tick — purely a flavor/score gesture that never fires the weapon, so it can't be abused as a DPS trick  
**Vibe:** Weapon-flourish-between-kills slot — the gunslinger spin is the exact 'style points while nothing is trying to kill you yet' beat that Bulletstorm/Borderlands trained players to crave, and it dovetails with the existing shell-eject/reload-flourish work already noted in memory  
**Engine cost:** Detection reuses the same roll-angle read already wired for the palm-out cast gate, just against the main hand's orientation instead of Offhand*; if the main hand doesn't already expose an equivalent Pitch/Angle/Roll triplet the way Offhand does, that's the one small native gap worth naming explicitly — a symmetric 'MainhandRoll' (or a generic per-hand accessor instead of Offhand-only) would make this and future main-hand gestures trivial instead of special-cased

### Shell-Ejector Showboat

**Anchor:** wrist-relative — shotgun-style weapon tilted and racked with an exaggerated offhand pump-throw  
**Trigger:** Immediately after a kill (within a short window), the offhand performs the normal pump-action racking motion but with GetHandVelocity showing an exaggerated overshoot past the normal racking distance/speed (a flourish-strength racking rather than a merely functional one)  
**Effect:** Plays an extra shell-ejection billboard-sprite flourish (smoking casing arcs away) and adds a small style-score tick on top of the normal chamber-round action — the weapon still just racks normally for gameplay purposes, the overshoot only adds the cosmetic/score layer  
**Vibe:** Another weapon-flourish-between-kills entry, deliberately paired with Gunslinger Twirl to give shotgun mains their own showboat instead of only rifle/pistol twirls — matches the Bulletstorm 'kill with style' scoring lens directly  
**Engine cost:** Layers on top of the same GetHandVelocity read already used for racking detection in the manual-reload FSM; the only new piece is a magnitude-overshoot threshold check, cheap enough to do in ZScript without a new native hook — a good 'ship without touching C++' candidate

### Cylinder Flick Reload

**Anchor:** wrist-relative main hand roll + offhand sweep across the weapon body  
**Trigger:** During the native manual-reload FSM's 'eject' step, instead of the slow default motion the player does a fast wrist-roll snap on the main hand (revolver-style cylinder-flick, read via a roll-velocity spike) immediately followed by an offhand sweep across the weapon's body within a tight window  
**Effect:** Completes that specific reload step early with a flourish animation and a small speed bonus to the whole reload FSM, but only for weapons flagged as 'flick-capable' (revolvers, lever-actions); fumbling the timing just falls through to the normal-speed manual reload with no penalty  
**Vibe:** Directly extends the already-shipped manual-reload FSM into a skill-expression flourish, which is exactly the 'weapon-flourish' and 'quarter-muncher skill ceiling' overlap the lens wants — reload becomes a mini-rhythm-game instead of a chore  
**Engine cost:** This should hook the existing native reload FSM rather than duplicate it — the FSM already reads bone/hotspot state per weapon, so the fast-path just needs a new transition edge (a 'flourish-complete' state) gated by the same velocity read used elsewhere; propose exposing a per-weapon boolean flag (already how vr_new_weapon_handling per-weapon opt-in works) rather than another parallel ZScript reload system, per the standing 'avoid forked reload logic' warning already in memory

### Holster Quickdraw Duel

**Anchor:** hip holster anchor (existing holster draw/stow system)  
**Trigger:** an ambush/xeno-reveal setpiece opens a timed window; hand velocity trace from hip-holster anchor to full arm extension (GetHandVelocity + start/stop proximity) is measured against a tight time budget  
**Effect:** a fast draw inside the window grants a 'PERFECT DRAW' arcade bonus (crit + score popup); a borderline draw grants brief bullet-time grace; a late draw is simply normal  
**Vibe:** Aliens ambush dread (silence-before-the-storm) resolved through a 90s-arcade reflex quickdraw minigame, riding entirely on the already-shipped holster system rather than duplicating it  
**Engine cost:** pure ZScript/content on top of the existing holster and GetHandVelocity; only a new draw-speed timer state, no new native surface required

### Trick Reload Toss

**Anchor:** chest-pouch reach-and-grab (the existing manual-reload keystone), plus an exaggerated overhand toss motion  
**Trigger:** during the native manual-reload FSM's eject step, if the ejected mag/shell's hand-velocity samples trace an upward-then-overhand arc instead of a simple drop, classify it as a 'trick reload'  
**Effect:** a cosmetic flourish reload variant plays (spinning the new mag before seating it), a small speed bonus or style-meter tick is granted, and the ejected mag becomes a physical billboard-trailed object that clatters on the floor  
**Vibe:** Bulletstorm-style reload flair layered onto the already-shipped 14-weapon manual reload system — rewards showing off over pure efficiency  
**Engine cost:** rides entirely on the already-native reload FSM (bone-read+hotspot+state machine); name the seam as an optional 'trick-toss branch' added inside that existing native FSM rather than a new system, since the toss-vs-drop velocity-shape check may need the same frame precision the FSM already has

