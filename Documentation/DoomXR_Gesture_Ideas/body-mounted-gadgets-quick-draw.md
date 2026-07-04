# Body-Mounted Gadgets & Quick-Draw

_Body-anchored holster/pouch draw gestures (hip, shoulder, back, wrist, bandolier) that swap held items via reach-to-anchor plus grip — HL:Alyx-adjacent but combat-focused, not menu-based._

### Shoulder Sling Quick-Draw — ⭐ TOP PICK

**Anchor:** Right/left shoulder blade — reach up-and-back over either shoulder  
**Trigger:** Hand enters the existing rShoulder/lShoulder HP_ANCHOR_BODY hardpoint radius (already seeded in vr_config.cpp, cells=3) AND a real grip rising-edge fires while VR_GetGripOwner resolves HARDPOINT for that hand  
**Effect:** Instantly swaps whatever's in that hand for the two-handed weapon slung there (rifle/shotgun/whip); empty-hand reach quick-draws it pre-gripped for an immediate two-hand barrel-capsule hold. Metal-shlick sound + a VR_HapticPulse tap confirms the swap.  
**Vibe:** Dropship-marine sling-check meets Doom arsenal swagger — the classic 'reach for the big gun' beat before a fight.  
**Engine cost:** Slot infra is already native (FHardpointSlot rShoulder/lShoulder, HP_ACT_HOLSTER) — the missing piece is the ZScript PlayerPawn hook that actually swaps ReadyWeapon on the grip edge, which is exactly the 'consumer rewiring' the grip-arbiter memory flags as deferred. Content/wiring, not a new hook.

### Hip Cross-Draw

**Anchor:** Right/left hip — the existing rHip/lHip HP_ANCHOR_BODY slots  
**Trigger:** Straight-down reach to your OWN-side hip draws the sidearm parked there; reaching ACROSS your body to the OPPOSITE hip (angle between hand-to-anchor vector and body-forward crosses a threshold) draws a bladed weapon instead, both confirmed by the real grip rising-edge  
**Effect:** Two distinct draws out of the same two slots depending on approach angle: straight pistol draw vs. cross-body machete/sword draw.  
**Vibe:** Western quick-draw duel energy filtered through Indy's improvised-blade instinct.  
**Engine cost:** Reuses rHip/lHip verbatim. The new signal needed is the approach-angle discriminator — a small addition returning an extra float from VR_ResolveHardpointWorldPos (it already has the hand-to-anchor vector on hand for the proximity check), so this is a light native add on top of an existing function, not a new subsystem.

### Boot-Knife Reach

**Anchor:** Boot/ankle — a brand-new low-Z hardpoint hotspot near the floor, well below the existing hip slot's oz=-26  
**Trigger:** Hand dips below a low body-relative Z threshold near the player's own root + grip rising-edge, same HP_ANCHOR_BODY math the hip/shoulder slots already use  
**Effect:** Instant silent trench-knife draw for a fast melee execute on staggered enemies — no ammo, no wind-up.  
**Vibe:** Colonial-marine boot-knife / Indy back-alley knife-draw beat; an always-available panic-button melee that fits 90s Doom's 'fists as backup weapon' spirit.  
**Engine cost:** Pure content — literally one more FHardpointSlot entry appended to the default Hardpoints table in vr_config.cpp (or dropped into vr_hardpoints.json), reusing HP_ANCHOR_BODY + HP_ACT_HOLSTER exactly as-is. Zero new C++.

### Wrist-Top Grapple Quick-Cast

**Anchor:** Top of the off-hand wrist — the already-stubbed wristTop HP_ANCHOR_WRIST/HP_ACT_ABILITY slot (abilityName "wrist_top")  
**Trigger:** Main hand taps the top face of the off-hand wrist (grip rising-edge inside the existing wristTop radius) while the whip/IceHook is the current offhand item  
**Effect:** Fires an instant targeted grapple-yank at whatever the main hand is currently aiming, skipping the normal whip wind-up — a hip-fire grapple option mid-fight.  
**Vibe:** Indy whip-crack reflex married to Doom's need for a zero-delay panic tool.  
**Engine cost:** The dispatch hook already exists and is unassigned: p_user.cpp's comment confirms wristTop's grip rising-edge already fires PlayerPawn.VR_HardpointAbility(hand, slotIndex) natively. This just needs the ZScript override calling into the already-built Verlet whip fire logic — the seam is open and waiting.

### Back Sling Big-Gun Draw

**Anchor:** Upper back/nape of neck — a new hardpoint slot, HP_ANCHOR_BODY with an oz above the existing shoulder slots, cells=4 for the biggest weapon class  
**Trigger:** BOTH hands reach behind the neck/upper back simultaneously, with both physHand grip rising-edges landing inside the slot radius within a short hysteresis window  
**Effect:** A dramatic two-handed draw of the loadout's biggest gun (BFG/rocket launcher) slung across the back, with a synchronized double-hand VR_HapticPulse on the draw.  
**Vibe:** The looter-shooter 'big gun' power fantasy plus Doom's own BFG mythology, staged as a real physical two-hand reach.  
**Engine cost:** Mostly content (one more Hardpoints entry) but the simultaneous-both-hands trigger is genuinely new: propose a requireBothHands bool on FHardpointSlot that gates the draw on both physHand grip edges landing within a window, mirroring the timing logic the existing two-hand barrel-capsule test already uses for held weapons.

### Forearm Ammo/Heat Glance

**Anchor:** The gun-hand's own forearm (not the off-hand wrist wheel) — a derived elbow-to-wrist midpoint  
**Trigger:** Gaze dwell: dot(headForward, forearm-to-head vector) stays past a threshold for N ticks, like checking a watch — no button, pure proximity+dwell since it's read-only info  
**Effect:** Fades in a glowing SDF readout (mag count or plasma heat gauge) on the gun forearm itself, arcade HUD-in-the-world instead of a screen-space number.  
**Vibe:** Pip-Boy/Aliens-smartgun readout energy, keeps the arcade ammo-counter satisfaction embodied instead of floating in a HUD corner.  
**Engine cost:** Needs one new native seam: the first-person IK arm system already computes an elbow joint internally for reach-solving (p_user.cpp's GetJointBindTRS math) but doesn't expose it. Propose AActor.GetArmJointPos(hand, joint) so ZScript can derive a forearm midpoint without re-deriving IK math. Rendering reuses the already-in-flight (uncompiled) SpawnSDFText thunk / BEHAVIOR_Anchor from vr_msdf_text.h.

### Bandolier Grenade Pull

**Anchor:** A diagonal chest-strap hotspot distinct from the existing vertical ammo-pouch reload point  
**Trigger:** Reach to the bandolier line + grip rising-edge, same HP_ANCHOR_BODY proximity math as the shoulder/hip slots but a different coordinate so it can't be confused with the reload reach  
**Effect:** Pulls a grenade straight into hand already primed (spoon released, timer running) for an immediate fast lob, contrasted with menu-selected grenades that arm on throw.  
**Vibe:** Rambo/Aliens chest-rig grenade pull — a panic-button 'oh no' beat that rewards fast, decisive VR body movement.  
**Engine cost:** Same holster-slot pattern as shoulders/hips, but the payload isn't a weapon swap — propose a third EHardpointAction value (e.g. HP_ACT_CONSUMABLE) alongside the existing HOLSTER/ABILITY pair so a grip-edge here spawns/primes an inventory item instead of swapping ReadyWeapon. Small, natural enum extension riding the same VR_ResolveHardpointWorldPos + grip-arbiter plumbing.

### Off-Hand Jam-Clear Rack

**Anchor:** The MAIN gun-hand's own wrist (the 'other' wrist from the off-hand ability mounts), reached by the off-hand  
**Trigger:** Off-hand grip-taps the top of the main hand's wrist while the held weapon is in a new JAMMED sub-state  
**Effect:** A slap-rack motion instantly clears the jam with a racking sound and a haptic kick on both controllers, restoring fire-readiness.  
**Vibe:** Aliens pulse-rifle-jam trope turned into a satisfying, tactile arcade recovery beat instead of a punishing wait.  
**Engine cost:** Extends the ALREADY-NATIVE manual-reload bone-read+hotspot+FSM (per weapon) with one more state (JAMMED) and one more hotspot (main-hand wrist, reached by off-hand) — the hotspot-detection plumbing is entirely reused from the shipped 14-weapon reload system, just a new state and a new coordinate.

### Twin-Hip Akimbo Draw

**Anchor:** Both hips simultaneously — same rHip/lHip slots as the cross-draw idea, but both at once  
**Trigger:** Both physHand grip rising-edges land inside rHip and lHip respectively within a short hysteresis window (mirrors the back-sling both-hands timing)  
**Effect:** Draws matched twin pistols akimbo into both hands in one motion instead of drawing them one at a time.  
**Vibe:** Peak looter-shooter power fantasy (Bulletstorm/Borderlands akimbo swagger) delivered as a single decisive body gesture.  
**Engine cost:** Directly plugs into the in-flight N-instance dual-wield work (the Shotgun_2 distinct-class proof) — the akimbo pair just needs to be the two items already parked at rHip/lHip, drawn together via the same requireBothHands timing gate proposed for the back slot. Ties an existing content system to an existing native slot pair.

### Cross-Draw Dual Wield

**Anchor:** both hip-holster anchors, opposite-hand reach  
**Trigger:** left hand reaches toward the right-hip anchor and right hand toward the left-hip anchor at the same time (each hand's approach vector dotted against the 'opposite hip' direction), with both grip buttons pressed inside a short simultaneity window  
**Effect:** both weapons draw in one crossed flourish as the arms uncross, instantly equipping dual-wield with a brief spin-flourish on each weapon  
**Vibe:** John-Woo/Doom-Eternal-chainsaw-drama dual-wield theatrics — a big weapon-swap showmanship beat  
**Engine cost:** builds directly on the in-flight, CVar-gated ZScript holster-system-plan; the 'crossed' detection is pure vector math against existing hip anchors, no new native required

