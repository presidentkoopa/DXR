# Engine-Level Foundations & New Native Hooks

_Ideas whose core content is itself a proposed new native C++ seam (CVar, exposed function, AActor field, render/haptic hook) rather than a pure content gesture riding existing systems._

### Lasso Wind-Up (overhead circle grapple)

**Anchor:** whip-hand, overhead, relative to derived shoulder anchor  
**Trigger:** GRIP_WHIP already owned by that hand (existing arbiter verdict) AND the hand traces a closing loop overhead, detected by a new native gesture-shape classifier fed by an expanded position-history ring buffer (today's vr_hand_vel_buffer[hand][4] only holds 4 velocity samples for smoothing, no position trail)  
**Effect:** a windup meter fills each full loop traced; on grip-release the whip lashes out at boosted range/speed with a wider grapple capture radius -- a flashy cowboy wind-up throw instead of a straight yank  
**Vibe:** Indiana Jones pulp adventure + arcade satisfaction -- a whip should reward a big theatrical wind-up, not just a flick of the wrist  
**Engine cost:** New field player_t::vr_hand_pos_buffer[2][32] (~0.5s at 60hz) populated in P_PlayerThink next to the existing vr_hand_vel_buffer; new native AActor.ClassifyGestureShape(int hand) thunk in vmthunks_actors.cpp returning GESTURE_NONE/CIRCLE_CW/CIRCLE_CCW/FIGURE8/SLASH via a closure+net-angular-sweep test -- this is the keystone several ideas below reuse

### Matrix Brace (stillness bullet-time dodge) — ⚠ needs button for MP

**Anchor:** whole-body: both hands + head, relative to their own recent motion, not a fixed anchor  
**Trigger:** GetHandVelocity(0)/(1) and head linear velocity all stay under an epsilon for N consecutive tics (a new stillness counter) while an incoming hitscan/projectile is inside a danger cone  
**Effect:** smoothly ramps a global time-dilation CVar down to e.g. 0.35x for a short window then back to 1.0x -- a physical 'freeze and lean' bullet-time beat triggered by bracing, not a menu toggle  
**Vibe:** Doom/Aliens arcade tension payoff -- dodging a Revenant homing missile in slow-mo because you physically went still and leaned  
**Engine cost:** New CVar g_xr_timescale + native VR_SetTimeDilation(float scale, float rampSeconds), host/single-player gated per the multiplayer pose-is-render-scope-only note; new per-player stillness-tic counter modeled on the grip arbiter's existing hysteresis CVar pattern

### True Shoulder Draw (bone-anchored holster)

**Anchor:** actual IK shoulder-blade bone position, not a derived anchor  
**Trigger:** hand crosses a TIGHT radius (safe now because the anchor doesn't drift on lean/turn) of the real shoulder-bone world position read off the connected IK skeleton, plus grip button  
**Effect:** draws the sword/whip from an over-the-shoulder holster reliably even mid-lean or crouch, where today's derived chest/shoulder anchors would need generous radii and produce false positives/negatives  
**Vibe:** Cashes in the realism the working first-person IK arms already bought -- the holster you reach for should be exactly where the model's shoulder actually is  
**Engine cost:** New native AActor.GetIKBonePos(FName boneName) reading the already-connected first-person IK skeleton (marine_novr.iqm) each tic as a world-space DVector3 -- a drift-free alternative to the feet+viewheight derived anchors, usable by any future gesture that wants tight geometry

### Bare-Hand Catch-and-Throwback — ⚠ needs button for MP · ✋ needs a free hand

**Anchor:** either hand, open/ungripped, intercepting a thrown actor's flight path  
**Trigger:** a new hand-intent verdict CATCH_READY -- open hand (no grip held) moving toward an incoming thrown actor within its predicted path, distinct from the existing GRIP_GLOVE world-object-throw verdict  
**Effect:** a native catch attaches the live grenade/projectile actor to the hand that tic (fuse keeps ticking), and a follow-up throw motion relaunches it back at its source  
**Vibe:** Aliens under-fire panic-catch beat, plus the 90s run-and-gun satisfaction of turning enemy ordnance back on them  
**Engine cost:** Grows the existing EGripOwner arbiter (p_user.cpp VR_ResolveGripOwner) into a broader VR_GetHandIntent(player_t*, int hand) verb enum adding CATCH_READY, computed from proximity-to-live-thrown-actor plus closing velocity -- exactly the arbiter's own stated growth direction from grip-ownership into full motion-verb classification

### Chainsaw Sawing Rev

**Anchor:** both hands on the chainsaw barrel axis, using the existing two-hand capsule test  
**Trigger:** while the native two-hand capsule already reports engaged, the off-hand oscillates back-and-forth along the shared weapon axis at rising frequency instead of staying still  
**Effect:** builds a decaying 'rev energy' meter that raises damage/stagger and adds a rasping haptic buzz -- mechanical, skill-based revving instead of a flat two-hand damage bonus  
**Vibe:** 90s Doom chainsaw fantasy made genuinely physical and arcade-satisfying instead of a static two-hand hold  
**Engine cost:** New AActor field vr_saw_oscillation_energy integrated natively each tic from the off-hand's velocity component along the weapon's forward axis (sign-flip counting), decaying over time -- lives right next to the existing two-hand capsule code in VR_CalculateTwoHanding (p_user.cpp)

### Cross-Arm Guard Stance — ⭐ TOP PICK · ⚠ needs button for MP

**Anchor:** chest, palm-in facing the player's own body (inverse of the shipped palm-out gate)  
**Trigger:** OffhandRoll indicates palm-in toward the chest anchor, sustained past a dwell threshold  
**Effect:** raises a temporary native guard flag reducing melee knockback/stagger and granting brief hit-forgiveness against a lunging melee attacker -- a physical 'brace for impact' read  
**Vibe:** Aliens facehugger-lunge panic block; the defensive mirror of the existing offense-only palm-out cast gate  
**Engine cost:** New player_t field vr_guard_stance_active with a native dwell timer using the grip arbiter's existing hysteresis-CVar pattern, since dwell timing is unreliable tic-by-tic in ZScript under variable frame/net timing

### Sight-Down-the-Barrel ADS Focus — ⚠ needs button for MP

**Anchor:** weapon-to-eye sightline, using the derived temple/helmet anchor  
**Trigger:** sustained high dot-product between head-forward and weapon-forward (true aiming down sights), held past a dwell threshold -- same gating shape as the shipped palm-out cast, applied to weapon-vs-head instead of palm-vs-world  
**Effect:** a short native micro-focus window nudges effective spread/recoil down and gives a soft time-perception tightening, rewarding actually raising the gun to your eye instead of hip-firing  
**Vibe:** Rewards real marksmanship with a felt arcade payoff, the natural next step from the palm-out cast-gate pattern  
**Engine cost:** New CVar vr_ads_focus_window plus a native per-player dwell counter comparing weapon-forward (already used for AttackPos/Dir) against head-forward each tic

### Force-Yank Recall — ⚠ needs button for MP

**Anchor:** whichever hand threw the boomerang sword or whip head, any position  
**Trigger:** a velocity-reversal signature -- the hand's velocity flips direction sharply along roughly the same axis within a short tic window -- detected off the same expanded position/velocity ring buffer proposed for the lasso wind-up  
**Effect:** spikes the already-built thrown weapon's return speed and homing strength for that recall, turning a passive auto-return into an active, timed Force-pull flourish  
**Vibe:** Adds a satisfying active-input beat to the existing throwable boomerang sword instead of leaving it fire-and-forget  
**Engine cost:** New native bool AActor.DetectVelocityReversal(int hand, float windowSeconds) scanning the position/velocity ring buffer, feeding directly into the existing thrown-weapon recall logic as a speed/homing multiplier

### Two-Hand Clap Shockwave — ⚠ needs button for MP · ✋ needs a free hand

**Anchor:** both hands, converging to near-zero separation  
**Trigger:** a native clap detector comparing both hands' tracked positions/closing velocity in the same tic, with debounce so it only fires once per clap  
**Effect:** triggers a short-radius melee shockwave push, rendered as a billboard shock-ring actor (per the no-particles-in-VR constraint), plus a synchronized double-pulse haptic on both controllers  
**Vibe:** Big, satisfying 90s Doom crowd-clear panic-button move -- a trigger that's only possible because this is VR, you can't clap in a flatscreen game  
**Engine cost:** New native bool VR_DetectHandClap(player_t*) comparing both hands together each tic (can't be cheaply reconstructed from per-hand ZScript calls with proper debounce), spawning a billboard shock-ring actor consistent with the existing particles-invisible-in-VR workaround

### Cooked Grenade Spin-Fuse — ⚠ needs button for MP

**Anchor:** hand holding a grenade, wrist rotation rather than translation  
**Trigger:** rapid wrist rotation (angular velocity, not linear) above a threshold while a grenade is held -- today OffhandPitch/Roll/Angle expose only static per-tic orientation and GetHandVelocity is purely linear, so no rotational-rate signal exists at all yet  
**Effect:** spinning the grenade in-hand winds a 'spin charge' that shortens cook-timer feedback delay and adds bonus fragmentation radius on throw -- a physical revolver-spin flourish for grenade prep  
**Vibe:** Looter-shooter flourish-for-reward loop (do a trick, get a bonus) married to Doom's frag-grenade arsenal  
**Engine cost:** New native AActor.GetHandAngularVelocity(int hand) -- a rotational-rate ring buffer parallel to the existing linear vr_hand_vel_buffer, differencing consecutive per-tic OffhandPitch/Roll/Angle samples that already exist but are never differenced into a rate today

### Gravity Wall Push-Off — ⭐ TOP PICK · ⚠ needs button for MP

**Anchor:** palm planted flat against a wall/ceiling surface, evaluated relative to current GravityDir  
**Trigger:** hand velocity spikes away from a solid surface immediately after being detected flat/stationary against it (a plant-then-push signature), computed relative to AActor.GravityDir rather than world-up  
**Effect:** launches the player with an impulse along the outward normal in GravityDir-relative space -- a real hand-driven push-off for parkour through the flipped-gravity plank sections, beyond just walking the planks  
**Vibe:** Extends the existing gravity-plank rail-guard traversal into an actively physical parkour move -- Aliens zero-g corridor vertigo plus arcade platforming payoff  
**Engine cost:** New native VR_WallPushOff(player_t*, DVector3 contactNormal) reading the hand's plant-then-release velocity spike and applying a launch impulse computed in GravityDir-relative space, sitting next to the existing native gravity-plank code that already reasons about AActor.GravityDir

### Sigil Circle Overcharge — ⚠ needs button for MP

**Anchor:** off-hand, empty, near a weapon hardpoint or while wielding the whip/sword  
**Trigger:** off-hand traces a full GESTURE_CIRCLE (reusing the same shape classifier as the lasso wind-up) while near the weapon or a designated hardpoint anchor  
**Effect:** arms one of the whip/sword's already-built elemental SDF effects (fire/ice/lightning) as a temporary overcharge, drawn from a real air-drawn sigil instead of a menu/button cycle  
**Vibe:** Turns an already-shipped elemental FX system into a pulpy 'draw a sigil on your blade' Indiana-Jones-meets-magic beat, genuinely beyond the seed palm-out cast gate  
**Engine cost:** Reuses the ClassifyGestureShape keystone from the lasso idea; the only new native surface is a binding layer mapping GESTURE_CIRCLE + weapon-proximity onto the existing elemental-FX enable flags already wired into vr_whip.zs/vr_sword.zs

