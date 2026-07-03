// ============================================================================
//  GITD "BRASS STORM" -- the SMG weapon-signature score effect.
//
//  Every SMG hit flicks a tiny SHELL CASING out of the wound carrying that hit's
//  damage number. The casing tumbles in 3D, arcs under gravity, BOUNCES off the
//  floor (a bright shard 'clink' on each bounce), then comes to rest and fades,
//  PILING near the player's feet. Because the SMG is rapid, dozens exist at once
//  -- everything here is cheap, self-integrating one-shot actors on the glow-panel
//  primitive (the proven gitd_dampop pattern).
//
//  A single persistent RUNNING TOTAL panel rides in the player's lower periphery,
//  climbing as the spray lands and decaying a beat after fire stops.
//
//  Shapes used (procedural neon, no font atlas except the casing's stamped number):
//    16 = CASING body (rounded capsule) with the damage number stamped on it.
//    17 = SHARD flash (the bounce 'clink').
//
//  Cvars: gitd_brass_enabled (master), gitd_brass_total (running-total panel on/off).
// ============================================================================

// ----------------------------------------------------------------------------
//  GITD_BrassCasing -- one ejected shell. Self-integrating; spins, arcs, bounces.
// ----------------------------------------------------------------------------
class GITD_BrassCasing : Actor
{
	int    dmg;          // the damage number stamped on this casing
	int    life;
	int    maxl;
	Vector3 pvel;
	double  restZ;      // resting plane (player-foot height near where it lands)
	double  spin;        // accumulated tumble angle (radians)
	double  spinRate;    // radians per tic
	int     bounces;     // how many times it has clinked
	double  restTimer;   // tics spent at rest (drives the final fade)

	Default { +NOINTERACTION +NOGRAVITY +NOBLOCKMAP +DONTSPLASH +NOTONAUTOMAP; RenderStyle "None"; }
	States { Spawn: TNT1 A 1; Loop; }

	override void Tick()
	{
		Super.Tick();
		life++;
		if (life > maxl) { Destroy(); return; }

		// ---- integrate motion ----
		Vector3 np = pos + pvel;

		bool grounded = (bounces >= 3) || (restTimer > 0);
		if (!grounded)
		{
			pvel.z  -= 1.05;     // gravity (heavier than a dampop -> a real little casing)
			pvel.xy *= 0.985;    // light air drag

			// ---- BOUNCE off the floor ----
			if (np.z <= restZ && pvel.z < 0)
			{
				np.z = restZ;
				pvel.z = -pvel.z * 0.42;          // damp the rebound
				pvel.xy *= 0.55;                 // scrub sideways speed on impact
				spinRate *= 0.6;                // tumble slows on each hit
				bounces++;

				// the 'clink' -- a tiny bright shard flash at the contact point
				GITD_BrassShard.Fire(np, color(255, 255, 244, 210));

				// once it's barely moving, let it settle
				if (abs(pvel.z) < 1.2 && bounces >= 1) { pvel.z = 0; bounces = 3; }
			}
		}
		else
		{
			// resting on the pile: kill residual drift, count down to fade-out
			pvel = (0, 0, 0);
			np.z = restZ;
			restTimer++;
		}

		SetOrigin(np, true);
		spin += spinRate;

		// ---- brightness / fade ----
		double fade;
		if (restTimer > 0)
		{
			// linger on the pile for ~22 tics, then ease out
			double rt = clamp(restTimer / 22.0, 0.0, 1.0);
			fade = 1.0 - rt;
		}
		else
		{
			fade = 1.0 - double(life) / double(maxl);
		}
		fade = clamp(fade, 0.0, 1.0);
		fade = fade * fade * (3.0 - 2.0 * fade);
		if (fade <= 0.01) return;

		// ---- TUMBLE: a FIXED-orientation panel whose outward normal spins.
		// dir != 0 => world-fixed orientation; rotating it makes the casing wheel
		// over in the air. (Camera-facing would never read as 'tumbling'.)
		double dx = cos(spin);
		double dy = sin(spin);

		// brass tint, warming to white-hot at the stamped number (handled in shader).
		Color col = Color(255, 255, 196, 70);          // brass/amber neon
		double rad = 6.5;                               // small -- it's a casing, not a card

		// wipeType 16 = CASING body + stamped number. counter = the damage value.
		level.AddGlowPanel(col, rad, np.x, np.y, np.z, 16, fade, dx, dy, dmg);
	}

	// Spawn a casing for one SMG hit. mon = the monster, dmg = this hit's damage,
	// pn = the player who fired (for the running total).
	static void Fire(Actor mon, int dmg, int pn)
	{
		if (!mon) return;
		let men = CVar.FindCVar("gitd_brass_enabled");
		if (men && !men.GetBool()) return;

		// eject point: at the wound, mid-body.
		Vector3 ep = (mon.pos.x + frandom[gbrass](-6.0, 6.0),
		              mon.pos.y + frandom[gbrass](-6.0, 6.0),
		              mon.pos.z + mon.height * 0.55);

		GITD_BrassCasing c = GITD_BrassCasing(Actor.Spawn("GITD_BrassCasing", ep));
		if (!c) return;
		c.dmg  = dmg;
		c.maxl = 56;                                       // ~0.8s ceiling
		c.life = 0;
		c.bounces = 0;
		c.restTimer = 0;

		// the casing flicks out the ejection port: sideways + up, with a strong sideways
		// bias toward the PLAYER so the brass rains down around their feet.
		double rz = 0.0;
		Vector3 toPly = (0, 0, 0);
		if (pn >= 0 && pn < MAXPLAYERS && playeringame[pn] && players[pn].mo)
		{
			let pmo = players[pn].mo;
			rz = pmo.pos.z;                                // floor = the player's feet
			Vector3 d = level.Vec3Diff(ep, pmo.pos);      // ep -> player
			double L = d.xy.Length();
			if (L > 1.0) toPly = (d.x / L, d.y / L, 0);
		}
		// resting plane: just above the player's feet (so the pile sits at the boots).
		c.restZ = rz + 1.5;

		double side = frandom[gbrass](2.4, 4.2);          // sideways flick
		double up   = frandom[gbrass](4.0, 6.5);          // pop up
		double towardPlayer = frandom[gbrass](1.2, 3.0);  // drift toward the boots
		// base sideways flick is a random in-plane dir; bias it at the player.
		double a = frandom[gbrass](0.0, 6.2831);
		Vector3 flick = (cos(a) * side + toPly.x * towardPlayer,
		                 sin(a) * side + toPly.y * towardPlayer,
		                 up);
		c.pvel = flick;

		c.spin     = frandom[gbrass](0.0, 6.2831);
		c.spinRate = frandom[gbrass](0.22, 0.46) * (random[gbrass](0,1) == 0 ? 1.0 : -1.0);

		// feed the running total in the player's periphery.
		GITD_BrassTotal.Add(pn, dmg);
	}
}

// ----------------------------------------------------------------------------
//  GITD_BrassShard -- the one-frame 'clink' flash when a casing hits the floor.
//  Ultra-cheap: a couple of bright shard panels that fade in ~6 tics.
// ----------------------------------------------------------------------------
class GITD_BrassShard : Actor
{
	int life, maxl;
	double rad;
	Color col;

	Default { +NOINTERACTION +NOGRAVITY +NOBLOCKMAP +DONTSPLASH +NOTONAUTOMAP; RenderStyle "None"; }
	States { Spawn: TNT1 A 1; Loop; }

	override void Tick()
	{
		Super.Tick();
		life++;
		if (life > maxl) { Destroy(); return; }
		double fade = 1.0 - double(life) / double(maxl);
		fade = clamp(fade, 0.0, 1.0);
		// shard expands slightly as it flashes out
		double r = rad * (1.0 + (1.0 - fade) * 0.8);
		// wipeType 17 = shard flash. counter unused (0).
		level.AddGlowPanel(col, r, pos.x, pos.y, pos.z, 17, fade, 0.0, 0.0, 0);
	}

	static void Fire(Vector3 at, Color c)
	{
		GITD_BrassShard s = GITD_BrassShard(Actor.Spawn("GITD_BrassShard", at));
		if (!s) return;
		s.maxl = 6;
		s.rad  = 5.0;
		s.col  = c;
	}
}

// ----------------------------------------------------------------------------
//  GITD_BrassTotal -- the persistent RUNNING-TOTAL panel. ONE static actor,
//  re-created on demand. Rides at a fixed offset in the player's lower periphery,
//  climbs as casings land, and decays a beat after fire stops.
// ----------------------------------------------------------------------------
class GITD_BrassTotal : Actor
{
	int total;          // current displayed spray total
	int idleTics;       // tics since the last hit (drives the decay)
	int owner;          // which player's periphery we ride
	double showAmt;     // smoothed display value (eases toward total)

	Default { +NOINTERACTION +NOGRAVITY +NOBLOCKMAP +DONTSPLASH +NOTONAUTOMAP; RenderStyle "None"; }
	States { Spawn: TNT1 A 1; Loop; }

	// add to the running total for player pn, (re)spawning the panel if needed.
	static void Add(int pn, int dmg)
	{
		if (pn < 0) return;
		let ten = CVar.FindCVar("gitd_brass_total");
		if (ten && !ten.GetBool()) return;

		GITD_BrassTotal t = Find(pn);
		if (!t)
		{
			Vector3 sp = (0, 0, 0);
			if (pn < MAXPLAYERS && playeringame[pn] && players[pn].mo) sp = players[pn].mo.pos;
			t = GITD_BrassTotal(Actor.Spawn("GITD_BrassTotal", sp));
			if (!t) return;
			t.owner = pn;
			t.total = 0;
			t.showAmt = 0;
		}
		t.total += dmg;
		t.idleTics = 0;
	}

	static GITD_BrassTotal Find(int pn)
	{
		ThinkerIterator it = ThinkerIterator.Create("GITD_BrassTotal");
		GITD_BrassTotal t;
		while (t = GITD_BrassTotal(it.Next()))
			if (t.owner == pn) return t;
		return null;
	}

	override void Tick()
	{
		Super.Tick();

		if (owner < 0 || owner >= MAXPLAYERS || !playeringame[owner] || !players[owner].mo)
		{ Destroy(); return; }
		let pmo = players[owner].mo;

		idleTics++;
		// after the spray stops, hold briefly then drain the total away.
		int holdFor = 18;
		if (idleTics > holdFor)
		{
			// drain ~6% per tic so a big spray visibly bleeds down.
			total = int(total * 0.94) - 1;
			if (total <= 0) { Destroy(); return; }
		}

		// ease the shown number toward the real total (no jarring jumps).
		showAmt += (double(total) - showAmt) * 0.35;
		int shown = int(showAmt + 0.5);
		if (shown <= 0) shown = total > 0 ? 1 : 0;

		// ---- LOWER PERIPHERY anchor: a fixed offset in front-and-down of the eye,
		// rotated into the player's facing so it always sits in the same screen spot.
		double ang  = pmo.angle * (3.14159265 / 180.0);
		double ca = cos(ang), sa = sin(ang);
		// forward 46u, to the right 30u, below eye level.
		double fwd = 46.0, rgt = 30.0;
		double ox = ca * fwd - sa * (-rgt);     // forward + right offset in world XY
		double oy = sa * fwd + ca * (-rgt);
		double eyeZ = pmo.pos.z + pmo.height * 0.78;
		Vector3 panelPos = (pmo.pos.x + ox, pmo.pos.y + oy, eyeZ - 26.0);

		// brightness: full while spraying, dimming as it decays.
		double bright = (idleTics <= holdFor) ? 1.0
		              : clamp(double(total) / 200.0, 0.30, 1.0);
		Color col = Color(255, 255, 210, 90);   // warm brass total

		// camera-facing (dir 0,0) so it stays readable; wipeType 13 = plain digit panel.
		level.AddGlowPanel(col, 14.0, panelPos.x, panelPos.y, panelPos.z,
			13, bright, 0.0, 0.0, clamp(shown, 0, 99999));
	}
}
