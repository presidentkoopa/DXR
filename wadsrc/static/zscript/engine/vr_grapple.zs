// ----------------------------------------------------------------------------
// vr_grapple.zs -- "VR Grapple & Beatdown".
//
// CANON (user): "grab a monster with my offhand and be able to punch it over and
// over with my main hand, weapon or not, and then throw the body into a crowd for
// area stun."
//
// A StaticEventHandler (XRGrapple) that runs per-tic in WorldTick, modeled on how
// the whip force-holds its victim (vr_whip.zs's grappleVictim / GM_YANK: set the
// victim's Vel toward a target world point every tic and let the engine's native
// movement integrate the one move -- collision-aware, no SetOrigin double-move).
//
//   OFF-HAND GRIP DOWN near a monster  -> GRAB (latch it as `grabbed`)
//   HELD: each tic force it to the OFF-HAND world position (OffhandPos)
//   MAIN-HAND fast swing near it       -> PUNCH (DamageMobj on a cooldown)
//   OFF-HAND GRIP RELEASE              -> THROW (Vel = handVel * mult, clear grab)
//   thrown body slows / stops          -> AREA-STUN nearby monsters once
//
// PURE ZScript feeding the already-native systems (impact momentum in
// p_interaction.cpp shoves whatever the thrown body hits; we only add the radius
// stun on top). No engine rebuild.
//
// LANDMINES honored (see project memory):
//   * ZScript has NO IntVar/StringVar/FloatVar -- read concrete native fields only.
//   * A StaticEventHandler must NEVER call an action function (A_StartSound,
//     A_Explode, ...) -- it faults. FX go through Level.AddGlowPanel(...) and
//     Actor.VR_HapticPulse(...); damage via mo.DamageMobj(...); state via
//     mo.SetStateLabel(...); motion via Vel / SetOrigin. All handler-safe.
//   * Particles are invisible in VR -> glow panels only.
//   * Hand indexing follows the whip/pouch precedent: index 0 = MAIN (AttackPos),
//     1 = OFF (OffhandPos); the same index feeds GetGripValue / GetHandVelocity /
//     VR_HapticPulse (the ammo-pouch handler uses exactly this mapping).
//
// CVARs are READ via CVar.FindCVar (NOT declared here -- the caller wires CVARINFO):
//   vr_grapple             (bool, true)   master toggle
//   vr_grapple_range       (float, 56)    off-hand grab reach, map units
//   vr_grapple_punch_speed (float, 18)    main-hand speed to register a punch, u/tic
//   vr_grapple_punch_damage(float, 15)    damage per punch
//   vr_grapple_throw_mult  (float, 1.5)   release-throw velocity multiplier
//   vr_grapple_stun_radius (float, 96)    area-stun radius around the thrown body
//   vr_grapple_grab_heavy  (bool, false)  allow grabbing bosses / heavy (Mass>600)
// ----------------------------------------------------------------------------

// A short-lived helper that RIDES the thrown body and, when it slows or stops,
// performs the one-shot radius stun on nearby monsters. Spawning this to carry the
// impact logic is cleaner than tracking the thrown actor from the handler across
// its whole flight (the handler would have to poll a possibly-destroyed pointer).
// NOINTERACTION so it never collides itself; it just follows and watches.
class XRGrappleThrownWatcher : Actor
{
	Actor  body;          // the thrown monster we ride
	Actor  thrower;       // the VR player (kill/stun credit)
	double stunRadius;
	int    life;          // hard cap so it can never leak (~1.2s)
	double lastSpeed;     // previous-tic speed, to detect the slow-down/impact

	const WATCH_LIFE   = 42;    // ~1.2s max ride
	const SLOW_SPEED   = 6.0;   // body considered "landed/impacted" below this u/tic
	const ARM_SPEED    = 10.0;  // must have gone at least this fast first (a real throw)

	Default
	{
		+NOBLOCKMAP +NOGRAVITY +NOINTERACTION +DONTSPLASH +NOTIMEFREEZE +CLIENTSIDEONLY;
		Radius 1;
		Height 1;
	}
	States { Spawn: TNT1 A -1; Stop; }

	static XRGrappleThrownWatcher Attach(Actor body, Actor thrower, double stunRadius)
	{
		if (!body) return null;
		let w = XRGrappleThrownWatcher(Actor.Spawn("XRGrappleThrownWatcher", body.pos));
		if (!w) return null;
		w.body       = body;
		w.thrower    = thrower;
		w.stunRadius = stunRadius;
		w.life       = WATCH_LIFE;
		w.lastSpeed  = body.Vel.Length();
		w.bArmed     = false;
		return w;
	}

	bool bArmed;   // the body actually reached throw speed at least once

	override void Tick()
	{
		// Do NOT Super.Tick() -- we don't want the default thinker moving this helper;
		// it only rides and observes.
		if (life-- <= 0) { Destroy(); return; }

		if (!body || body.bDestroyed)
		{
			// Body gone (died mid-air, telefragged, etc.) -- if it had been thrown fast,
			// still deliver the stun at our last position, then retire.
			if (bArmed) DoAreaStun(pos);
			Destroy();
			return;
		}

		SetOrigin(body.pos, true);

		double spd = body.Vel.Length();
		if (spd >= ARM_SPEED) bArmed = true;

		// Fire the one-shot stun the first tic a genuinely-thrown body slows to a
		// crawl (it hit something / the crowd), or its health hits zero on impact.
		bool impacted = bArmed && (spd < SLOW_SPEED || body.health <= 0);
		if (impacted)
		{
			DoAreaStun(body.pos);
			Destroy();
			return;
		}

		lastSpeed = spd;
	}

	// Loop nearby monsters within stunRadius and briefly stun them: kick them into
	// Pain and pad reactiontime so they hesitate. Handler-safe (SetStateLabel / field
	// writes only -- no action functions). Skips the thrown body itself and the thrower.
	private void DoAreaStun(vector3 center)
	{
		double r = stunRadius;
		BlockThingsIterator it = BlockThingsIterator.CreateFromPos(center.x, center.y, center.z, r, r, false);
		while (it.Next())
		{
			Actor n = it.thing;
			if (n == null || n == body || n == thrower) continue;
			if (!n.bIsMonster) continue;
			if (n.bCorpse || n.health <= 0) continue;

			vector3 d3 = n.pos + (0, 0, n.Height * 0.5) - center;
			if (d3.Length() > r + n.radius) continue;

			// brief stun: hesitate + flinch. reactiontime is a plain native int; a Pain
			// state (if any) reads as a visible flinch. Bosses hesitate but don't flinch-lock.
			n.reactiontime += 12;
			if (!n.bBoss)
			{
				let ps = n.FindState("Pain");
				if (ps) n.SetState(ps);
			}

			// small neon pop on each stunned target (glow panel = VR-visible, action-fn-free)
			Level.AddGlowPanel(Color(255, 120, 180, 255), 14.0,
				n.pos.x, n.pos.y, n.pos.z + n.Height * 0.5, 14, 1.0, 0.0, 0.0, 0);
		}

		// one bigger shock ring at the impact center
		Level.AddGlowPanel(Color(255, 180, 200, 255), r * 0.6,
			center.x, center.y, center.z, 14, 1.0, 0.0, 0.0, 0);
	}
}

// ----------------------------------------------------------------------------
class XRGrapple : StaticEventHandler
{
	Actor  grabbed;        // the monster currently held in the off-hand
	bool   offGripPrev;    // off-hand grip rising/falling-edge latch
	int    punchCooldown;  // tics until the next punch can land (anti per-tic multi-hit)

	// Hand index convention (whip/pouch precedent): 0 = MAIN (AttackPos / AttackAngle),
	// 1 = OFF (OffhandPos). Same index feeds GetGripValue / GetHandVelocity / VR_HapticPulse.
	const HAND_MAIN     = 0;
	const HAND_OFF      = 1;
	const GRIP_DOWN     = 0.5;    // analog squeeze threshold for "gripping"
	const PUNCH_CD      = 10;     // tics between landed punches
	const PUNCH_REACH   = 40.0;   // main hand must be within this of the grabbed body to connect
	const HEAVY_MASS    = 600.0;  // Mass above this = "heavy/boss", needs vr_grapple_grab_heavy

	// ---- CVar helpers (mirror the whip's CVF/CVB/CVI null-check pattern) ----
	private double CVF(string name, double def) { CVar c = CVar.FindCVar(name); return c ? c.GetFloat() : def; }
	private bool   CVB(string name, bool def)   { CVar c = CVar.FindCVar(name); return c ? c.GetBool()  : def; }

	// Drop whatever we hold and reset the held-state (never touches thrown-body logic;
	// that is owned by XRGrappleThrownWatcher once a throw hands off).
	private void ReleaseGrab()
	{
		if (grabbed && !grabbed.bDestroyed)
		{
			grabbed.bNoGravity   = grabbedHadNoGrav;   // restore whatever it was before the grab
			grabbed.reactiontime = grabbedReactSaved;
		}
		grabbed = null;
	}

	// remembered pre-grab actor state so the grab is non-destructive if it just ends
	bool grabbedHadNoGrav;
	int  grabbedReactSaved;

	override void WorldTick()
	{
		if (punchCooldown > 0) punchCooldown--;

		// master toggle
		if (!CVB("vr_grapple", true)) { ReleaseGrab(); offGripPrev = false; return; }

		// local VR player only
		PlayerInfo p = players[consoleplayer];
		if (!p) { ReleaseGrab(); offGripPrev = false; return; }
		PlayerPawn pawn = PlayerPawn(p.mo);
		if (!pawn || !pawn.player || !pawn.player.PlayInVR) { ReleaseGrab(); offGripPrev = false; return; }
		if (pawn.health <= 0) { ReleaseGrab(); offGripPrev = false; return; }

		// If we lost the body (died and got removed, telefragged, level changed), forget it.
		if (grabbed && (grabbed.bDestroyed || grabbed.health <= 0))
			ReleaseGrab();

		double range      = CVF("vr_grapple_range", 56.0);
		vector3 offPos    = pawn.OffhandPos;
		bool   gripNow    = pawn.GetGripValue(HAND_OFF) > GRIP_DOWN;
		bool   risingEdge = gripNow && !offGripPrev;
		bool   fallingEdge= !gripNow && offGripPrev;
		offGripPrev = gripNow;

		// ---- 1. GRAB: off-hand grip rising edge near a monster ----
		if (!grabbed && risingEdge)
			TryGrab(pawn, offPos, range);

		// ---- while held: HOLD (2) + PUNCH (3) ----
		if (grabbed)
		{
			HoldToHand(pawn, offPos);
			TryPunch(pawn);
		}

		// ---- 4. THROW: off-hand grip release while holding ----
		if (grabbed && fallingEdge)
			ThrowGrabbed(pawn);
	}

	// ---- 1. GRAB -------------------------------------------------------------
	// Latch the nearest valid monster within `range` of the off-hand. Prefer a
	// weakened/pained target but fall back to any (tunable via preference, below).
	// Skips heavy/boss (Mass > HEAVY_MASS) unless vr_grapple_grab_heavy is on.
	private void TryGrab(PlayerPawn pawn, vector3 offPos, double range)
	{
		bool allowHeavy = CVB("vr_grapple_grab_heavy", false);

		Actor best = null;
		double bestScore = -1.0;   // higher = better pick

		BlockThingsIterator it = BlockThingsIterator.CreateFromPos(offPos.x, offPos.y, offPos.z, range, range, false);
		while (it.Next())
		{
			Actor m = it.thing;
			if (m == null || m == pawn) continue;
			if (!m.bIsMonster) continue;
			if (m.bCorpse || m.health <= 0) continue;
			if (m.bDontThrust && !allowHeavy) continue;   // immovable/no-thrust things: leave alone unless heavy-grab

			// heavy / boss cheese-reduction
			if (!allowHeavy && (m.bBoss || m.Mass > HEAVY_MASS)) continue;

			vector3 d3 = m.pos + (0, 0, m.Height * 0.5) - offPos;
			double dist = d3.Length();
			if (dist > range + m.radius) continue;

			// score: closer is better; a pained/low-health target gets a bonus so the
			// "prefer a weakened target" intent wins ties, without excluding a fresh one.
			double proximity = 1.0 - clamp(dist / (range + m.radius), 0.0, 1.0);
			double hurt = 0.0;
			if (m.SpawnHealth() > 0)
				hurt = 1.0 - clamp(double(m.health) / double(m.SpawnHealth()), 0.0, 1.0);
			double score = proximity + hurt * 0.5;
			if (score > bestScore) { bestScore = score; best = m; }
		}

		if (!best) return;

		grabbed = best;
		grabbed.target = pawn;               // kill/stun credit (Doom convention: self.target)

		// remember pre-grab state so ending the grab restores it non-destructively
		grabbedHadNoGrav  = grabbed.bNoGravity;
		grabbedReactSaved = grabbed.reactiontime;

		// keep it from acting while held: pad reactiontime so it hesitates (simple + robust;
		// bFrozen would fully halt its thinker/animation which reads as a hard freeze -- we
		// want it to look manhandled, not paused). Off-hand carry needs bNoGravity so our
		// per-tic Vel isn't fighting the fall.
		grabbed.bNoGravity   = true;
		grabbed.reactiontime = max(grabbed.reactiontime, 8);

		// grab feedback: off-hand rumble + a neon clench pop at the hand
		pawn.VR_HapticPulse(HAND_OFF, 0.5, 0.06);
		Level.AddGlowPanel(Color(255, 150, 200, 255), 20.0,
			grabbed.pos.x, grabbed.pos.y, grabbed.pos.z + grabbed.Height * 0.5, 14, 1.0, 0.0, 0.0, 0);
	}

	// ---- 2. HOLD -------------------------------------------------------------
	// Force the grabbed monster toward the off-hand each tic by setting its Vel to the
	// displacement (targetPos - pos), exactly the whip's collision-aware convention: we
	// set Vel and let the engine's native movement do the one move (no SetOrigin, so it
	// can't tunnel through geometry or double-move off a wall).
	private void HoldToHand(PlayerPawn pawn, vector3 offPos)
	{
		if (!grabbed || grabbed.bDestroyed) return;

		// aim for the hand, biased so the body's CENTER sits at the hand (subtract half height)
		vector3 target = offPos - (0, 0, grabbed.Height * 0.5);
		vector3 delta  = target - grabbed.pos;

		// Vel = displacement lands it on the hand this tic; clamp so a fast hand sweep
		// doesn't inject an absurd velocity that overshoots and slingshots through walls.
		double maxHold = 48.0;   // u/tic ceiling while carried
		if (delta.Length() > maxHold)
			delta = delta.Unit() * maxHold;
		grabbed.Vel = delta;

		// keep it hesitating so it can't wander/attack out of the grip
		grabbed.reactiontime = max(grabbed.reactiontime, 4);
	}

	// ---- 3. PUNCH ------------------------------------------------------------
	// While held, a fast MAIN-hand move near the body lands a punch on a cooldown.
	// Works weapon-or-not (this is a raw hand read; it does not consult ReadyWeapon).
	private void TryPunch(PlayerPawn pawn)
	{
		if (punchCooldown > 0) return;
		if (!grabbed || grabbed.bDestroyed || grabbed.health <= 0) return;

		double punchSpeed = CVF("vr_grapple_punch_speed", 18.0);
		double handSpeed  = pawn.GetHandVelocity(HAND_MAIN).Length();
		if (handSpeed < punchSpeed) return;

		// proximity: the main hand must actually be at the body
		vector3 mainPos = pawn.AttackPos;
		vector3 d3 = grabbed.pos + (0, 0, grabbed.Height * 0.5) - mainPos;
		if (d3.Length() > PUNCH_REACH + grabbed.radius) return;

		int dmg = int(CVF("vr_grapple_punch_damage", 15.0));
		if (dmg < 1) dmg = 1;
		// harder swings hit a little harder, capped so a tracking spike can't one-shot
		double speedBonus = clamp((handSpeed - punchSpeed) / punchSpeed, 0.0, 1.0);
		dmg = int(dmg * (1.0 + speedBonus * 0.5));

		grabbed.DamageMobj(pawn, pawn, dmg, 'Melee');
		grabbed.TraceBleed(dmg, pawn);
		punchCooldown = PUNCH_CD;

		// hit feedback: main-hand rumble + a bright spark at the impact point
		pawn.VR_HapticPulse(HAND_MAIN, 0.7, 0.05);
		vector3 hit = grabbed.pos + (0, 0, grabbed.Height * 0.5);
		Level.AddGlowPanel(Color(255, 255, 230, 160), 22.0, hit.x, hit.y, hit.z, 14, 1.0, 0.0, 0.0, 0);
		Level.AddGlowPanel(Color(255, 255, 120, 60),  10.0, hit.x, hit.y, hit.z, 14, 0.5, 0.0, 0.0, 0);

		// if the punch killed it, we no longer hold anything (guard next tics)
		if (grabbed.health <= 0) ReleaseGrab();
	}

	// ---- 4. THROW ------------------------------------------------------------
	// On off-hand release, fling the body with the off-hand velocity * mult and hand off
	// to a watcher that delivers the area-stun on impact. The native impact-momentum
	// system (p_interaction.cpp) shoves whatever the flying body strikes.
	private void ThrowGrabbed(PlayerPawn pawn)
	{
		if (!grabbed || grabbed.bDestroyed) { ReleaseGrab(); return; }

		Actor body = grabbed;

		double mult   = CVF("vr_grapple_throw_mult", 1.5);
		vector3 hv    = pawn.GetHandVelocity(HAND_OFF);
		vector3 throwVel = hv * mult;

		// If the hand was basically still on release (a gentle let-go), give a tiny forward
		// nudge from the off-hand facing so a "throw" still travels rather than dropping at
		// the feet -- but keep it modest so a deliberate soft release just drops the body.
		if (throwVel.Length() < 4.0)
		{
			double ang = pawn.OffhandAngle;
			double pit = pawn.OffhandPitch;
			vector3 fwd = (cos(pit) * cos(ang), cos(pit) * sin(ang), -sin(pit));
			throwVel = fwd * 6.0;
		}

		// Clamp the launch so a VR tracking spike can't fling a body at absurd speed.
		double throwCeil = 90.0;   // u/tic
		if (throwVel.Length() > throwCeil)
			throwVel = throwVel.Unit() * throwCeil;

		// restore gravity/reaction BEFORE handing off so the thrown body arcs & acts normally
		body.bNoGravity   = grabbedHadNoGrav;
		body.reactiontime = grabbedReactSaved;
		body.target       = pawn;                 // impact-kill credit stays with the player
		body.Vel = throwVel;

		grabbed = null;   // clear the grab; the watcher owns the body from here

		// haptic + a launch flash off the off-hand
		pawn.VR_HapticPulse(HAND_OFF, 0.8, 0.08);
		vector3 hp = pawn.OffhandPos;
		Level.AddGlowPanel(Color(255, 200, 160, 255), 24.0, hp.x, hp.y, hp.z, 14, 1.0, 0.0, 0.0, 0);

		// ---- 5. AREA-STUN carrier: rides the body, stuns the crowd on impact ----
		double stunR = CVF("vr_grapple_stun_radius", 96.0);
		XRGrappleThrownWatcher.Attach(body, pawn, stunR);
	}
}
