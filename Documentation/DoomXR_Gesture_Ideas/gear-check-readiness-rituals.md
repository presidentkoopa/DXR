# Gear-Check & Readiness Rituals

_Cosmetic self-check gestures (pat, slap, mic-key, low-ready, chamber peek) that surface real weapon/squad state through bark or haptic feedback without altering mechanics._

### Chest Rig Ammo Pat

**Anchor:** chest (existing ammo pouch anchor)  
**Trigger:** off-hand taps INTO the chest anchor and immediately retreats (dwell < 0.15s, no grip held) -- a fast approach-then-retreat GetHandVelocity signature, distinct from the slower reload reach-grab which requires the dedicated reload button  
**Effect:** plays a self-check voice bark ('twelve rounds, good') derived from the same per-weapon mag/ammo bone-state the manual-reload FSM already reads, plus a light chest-thump haptic; purely a gear-check, never triggers an actual reload  
**Vibe:** marine pre-breach self-check ritual, a small reassurance beat before pushing into a dark room  
**Engine cost:** ZScript reuse of the existing manual-reload FSM's ammo-state read; the only new piece is a tap-vs-grab velocity-signature classifier, a natural extension of the in-flight hand-intent arbiter (already growing to classify raw motion into verbs) -- propose adding a 'TAP' verb class there

### Holster Slap Confirm

**Anchor:** hip (sidearm holster)  
**Trigger:** hand slaps the hip anchor and releases immediately (dwell < 0.2s, no grip) -- same tap-classifier signature as the chest pat, applied at the hip anchor  
**Effect:** leather/mechanical slap SFX plus a tiny haptic thud confirming the sidearm is holstered and topped off; if the sidearm is currently drawn/elsewhere, plays a contextual warning bark instead ('sidearm's out') tying gesture to real weapon state  
**Vibe:** reflexive nervous-marine habit that fills quiet corridor time with texture instead of silence  
**Engine cost:** pure ZScript, reuses the same tap-classifier verb proposed for the chest pat plus existing holster/draw state tracking

### Shoulder Mic Key

**Anchor:** shoulder (off-hand reaches to the opposite shoulder like keying a mic clip)  
**Trigger:** off-hand reaches the shoulder anchor (proximity filter) + trigger/grip squeeze = press-to-talk button-bit (a real button, keeping it net-safe for a future MP voice channel or an SP scripted radio-check)  
**Effect:** in SP, triggers a scripted squad radio-check bark, objective reminder, or an ammo-resupply call-in; in a future MP mode, opens a local PTT channel scoped to squeeze duration; a small haptic click on key-press plus brief radio-static audio filter sells the mic-click  
**Vibe:** colonial marine squad-comms energy -- 'sound off!' -- ties gesture flavor to an eventual real net feature instead of being purely cosmetic  
**Engine cost:** reach detection is pure ZScript against the existing shoulder anchor; the future-MP PTT gate needs a genuine net-safe voice-channel field -- propose a net_ptt_active per-player field mirroring existing button-bit plumbing, gated purely on the real button so the gesture stays enabling-only

### Low-Ready Breach Stance — ⚠ needs button for MP

**Anchor:** chest (weapon crossed diagonally, muzzle angled down)  
**Trigger:** dominant-hand weapon orientation pitched downward and held near the chest anchor, sustained for dwell > ~1s (a held pose, not a tap) -- exits immediately if the weapon is raised back to fire-ready  
**Effect:** while held, grants a 'quiet movement' state -- dampened footstep audio and camera-bob, evoking a slow tactical clear -- purely a pacing tool for corridor tension, not a stealth-kill mechanic  
**Vibe:** reinforces claustrophobic slow-corridor dread pacing between combat beats -- the marine-ritual feel of holding a rifle low while clearing a room  
**Engine cost:** pose+dwell detection is ZScript against the existing weapon-hand transform and chest anchor; footstep/camera dampening likely already has hooks in the movement/audio system -- mostly content wiring, no new native surface needed

### Chamber Peek — ⭐ TOP PICK

**Anchor:** eye/face (weapon brought close to the face, rolled ~90 degrees so the ejection port faces the eye)  
**Trigger:** dominant-hand weapon enters the face-proximity radius AND its roll orientation sits within a band around 90 degrees from neutral (ejection port toward the eye), held for dwell ~0.3s  
**Effect:** replaces the numeric HUD ammo counter with a physical look-and-see chamber/mag-well close-up (a bone-attached indicator near the weapon rather than a HUD corner readout) plus a stuck-round visual tell if the weapon is jammed, encouraging players to self-verify state instead of glancing at a number  
**Vibe:** marine-professionalism ritual, and the tension of taking your eyes off the corridor to check your own gun  
**Engine cost:** reuses the existing per-weapon bone-read ammo/mag state (same data the manual-reload FSM already reads) at a new trigger condition; roll-orientation-band detection is ZScript math off the existing weapon-hand transform, no new native hook required

### Wrist-Wrap Field Dress — ✋ needs a free hand

**Anchor:** cross-body wrist-to-wrist grab (off-hand grips the injured hand's wrist)  
**Trigger:** HP below a threshold (context gate) plus off-hand proximity to the other wrist held at low velocity (dwell) rather than a stray brush, confirmed by the existing heal-item-use button  
**Effect:** starts a self-bandage heal-over-time with a temporary adrenaline damage buff on completion; the player can't fire two-handed weapons mid-wrap, creating real vulnerability  
**Vibe:** Aliens' 'wounded marine, patch yourself up and get back in it' desperation beat fused with looter-shooter's clutch-heal-with-flourish itemization — a Borderlands second-wind moment reframed as a body-as-UI ritual  
**Engine cost:** pure ZScript on existing anchor/dwell/button primitives — just a new wrist-to-wrist proximity comparison between two already-derived anchors, no new native surface

