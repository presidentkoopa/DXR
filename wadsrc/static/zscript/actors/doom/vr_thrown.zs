// --------------------------------------------------------------------------
//  vr_thrown.zs -- shared thrown-item behaviours for DoomXR VR.
//
//    * XRThrownSpin    -- roll-per-tic helper (spin by mass + throw velocity).
//                         Every thrown item should tumble; heavier tumbles
//                         slower, a harder throw spins faster.
//    * DeflectShockwave-- expanding shockwave RING drawn by the engine's own
//                         glow-billboard shader (main.fp wgType 14). No shader
//                         edit -- we just march wipeProgress 0->1 over a few
//                         tics. Used for shield missile-deflects.
//    * ThrownChainsaw  -- the boomerang chainsaw: a SMART multi-target
//                         boomerang that weaves through your locked targets,
//                         cuts each (damage even if it doesn't kill), then
//                         homes back to the throwing hand. Pure waypoint
//                         steering -- no wall-stall hack (see note below).
// --------------------------------------------------------------------------

class XRThrownSpin play
{
	// Degrees of model roll to add per tic. Tuned so mass 50 @ speed 30 gives
	// ~45 deg/tic (the old flat ShieldSaw rate). Heavier -> slower, faster -> quicker.
	static double RollDelta(double mass, double throwSpeed)
	{
		double refMass = 50.0, refSpeed = 30.0, refSpin = 45.0;
		double m = clamp(mass, 5.0, 400.0);
		double s = max(throwSpeed, 1.0);
		return clamp(refSpin * (s / refSpeed) * (refMass / m), 6.0, 100.0);
	}
}

// --------------------------------------------------------------------------
//  Deflect shockwave -- shader ring, no assets, no .fp edit.
//  The shader (main.fp, "SHOCKWAVE RING (14)") marches a contour outward inside
//  the panel as wipeProgress (wgMask.y) goes 0..1 and dissipates near the end.
//  We hold the panel radius constant (its max footprint) and animate progress.
// --------------------------------------------------------------------------
class DeflectShockwave : Actor
{
	Color  ringColor;
	double footprint;
	int    life, maxLife;

	Default
	{
		+NOBLOCKMAP +NOGRAVITY +NOINTERACTION +DONTSPLASH +CLIENTSIDEONLY +NOTIMEFREEZE
		Radius 1;
		Height 1;
	}

	// origin: the actor the wave emanates from. col: ring colour. foot: world radius. ticks: life.
	static DeflectShockwave Emit(Actor origin, Color col, double foot = 130.0, int ticks = 10)
	{
		if (!origin) return null;
		let s = DeflectShockwave(Actor.Spawn("DeflectShockwave", origin.pos + (0, 0, origin.height * 0.5)));
		if (s) { s.ringColor = col; s.footprint = foot; s.maxLife = ticks; s.life = ticks; }
		return s;
	}

	override void Tick()
	{
		if (life-- <= 0) { Destroy(); return; }
		double prog = 1.0 - (double(life) / double(maxLife));   // 0 -> 1 over the life
		level.AddGlowPanel(ringColor, footprint, pos.x, pos.y, pos.z, 14, prog, 0.0, 0.0, 0);
	}

	States
	{
	Spawn:
		TNT1 A 1;
		Wait;   // Tick() owns teardown
	}
}

// --------------------------------------------------------------------------
//  ThrownChainsaw -- smart multi-target boomerang.
//
//  WHY IT'S SMARTER than the ShieldSaw boomerang: that one is a real +MISSILE
//  projectile, so it collides with world geometry and needed a fiddly
//  stall/rip/NOCLIP-toggle hack to keep it from getting wedged on walls while
//  homing. This one carries +NOCLIP and does ALL of its own hit detection by
//  distance -- so it flies a clean waypoint path (target -> target -> hand)
//  that can never stall on geometry. Targets were locked with line-of-sight,
//  so phasing to reach them reads fine. One clean state machine, no hack.
// --------------------------------------------------------------------------
class ThrownChainsaw : Actor
{
	Array<Actor> hitList;   // locked targets, in visit order
	int    cur;             // index of the current target
	Actor  thrower;
	int    hand;            // 0 = main, 1 = off
	double throwSpeed;      // initial launch speed, for spin
	double dmgPerHit;
	bool   returning;
	int    life, maxLife;
	double homeR;           // catch radius at the hand

	Default
	{
		// NOCLIP (not NOINTERACTION): still moves by velocity every tic, but phases through
		// geometry so its waypoint homing can never stall on a wall. Hit detection is manual.
		+NOGRAVITY +NOCLIP +NOBLOCKMAP +DONTSPLASH
		+INTERPOLATEANGLES
		+FORCEXYBILLBOARD
		Radius 14;
		Height 14;
		Speed 26;
		Mass 60;            // chainsaw heft -> spin rate
		Scale 0.6;
	}

	// Called by the weapon immediately after spawn (targets already pushed into hitList).
	void Launch(Actor who, int inHand, double spd, double dmg, int lifeTics)
	{
		thrower = who; master = who; target = who;
		hand = inHand; throwSpeed = spd; dmgPerHit = dmg;
		maxLife = lifeTics; life = lifeTics; homeR = 52.0;
		Actor t = CurrentTarget();                                  // head straight at target #1
		if (t) Steer((t.pos.xy, t.pos.z + t.height * 0.5));         // else keep SpawnPlayerMissile's forward vel
	}

	// Aim velocity straight at a world point.
	void Steer(vector3 dest, double spd = -1)
	{
		if (spd < 0) spd = Speed;
		vector3 d = dest - pos;
		double h = d.xy.Length();
		if (h + abs(d.z) < 1) return;
		double yaw = atan2(d.y, d.x);
		double pit = -atan2(d.z, h);
		Vel3DFromAngle(spd, yaw, pit);
	}

	// First still-living locked target at or after 'cur' (skips any that died).
	Actor CurrentTarget()
	{
		while (cur < hitList.Size())
		{
			Actor a = hitList[cur];
			if (a && a.health > 0 && !a.bCorpse) return a;
			cur++;
		}
		return null;
	}

	override void Tick()
	{
		// Spin the blade by mass + how hard it was thrown.
		roll += XRThrownSpin.RollDelta(Mass, throwSpeed);
		// Neon trail (reuses the shield saw's additive trail puff).
		ShieldSawGlow(Actor.Spawn("ShieldSawGlow", pos)).A_SetAngle(angle);

		if (life-- <= 0) returning = true;

		if (!returning)
		{
			Actor t = CurrentTarget();
			if (!t)
			{
				returning = true;
			}
			else
			{
				vector3 c = (t.pos.xy, t.pos.z + t.height * 0.5);
				Steer(c);                                   // re-home every tic -> smooth weave
				if ((c - pos).Length() <= radius + t.radius + 10)
				{
					t.DamageMobj(self, thrower, int(dmgPerHit), "Saw", DMG_THRUSTLESS);
					A_StartSound("weapons/sawhit", CHAN_WEAPON);
					Actor.Spawn("ShieldSawBloods", c);
					cur++;                                  // advance to the next locked target
					if (!CurrentTarget()) returning = true;
				}
			}
		}
		else
		{
			if (!thrower) thrower = players[consoleplayer].mo;
			if (thrower)
			{
				vector3 home = hand ? thrower.OffhandPos : thrower.AttackPos;
				Steer(home, Speed * 1.5);                   // comes back faster than it went out
				if ((home - pos).Length() <= homeR) { Destroy(); return; }   // caught
			}
			else { Destroy(); return; }
		}

		Super.Tick();
	}

	States
	{
	Spawn:
		SAWG A 1;
		Loop;
	}
}
