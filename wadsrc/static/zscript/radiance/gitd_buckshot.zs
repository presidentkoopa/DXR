// ============================================================================
//  GITD_Buckshot -- the SHOTGUN weapon-signature score effect: "Buckshot".
//
//  On a shotgun hit the score DETONATES into ~6-10 pellet-SHARDS that blast out
//  of the wound in a CONE pointing along the shot (player -> monster), each shard
//  a small glowing fragment (shape 17) carrying a SLICE of the hit's score. They
//  fly fast, a couple are biased to whip PAST the player's head, and each one
//  EMBEDS the instant it strikes a wall/floor: stop, stick, glow, slow-fade.
//  ~0.4s after the blast the FULL TOTAL slams together at the wound with a
//  concussive FILLED-DISC flash (15) + a SHOCKWAVE RING (14) punching outward.
//
//  Bigger damage => wider + faster cone, more shards, bigger slam. Pure
//  choreography on the AddGlowPanel primitive (no engine change); shapes 14/15/17
//  are the procedural neon SDFs added in the shader's wgType branch.
//
//  Entry point: GITD_Buckshot.Fire(mon, dmg, pn)  -- called from the combo
//  handler when the damaging weapon maps to the SHOTGUN signature.
//
//  Cvar: gitd_buckshot_enabled (master on/off).
// ============================================================================

// ----------------------------------------------------------------------------
//  GITD_BuckShard -- one pellet of the detonation. Flies a ballistic arc, and
//  LineTraces from its last pos to its new pos each tic; on a world hit it snaps
//  to the contact point, sticks flat to the surface (fixed orientation), and
//  slow-fades. Shape 17 = the procedural shard SDF.
// ----------------------------------------------------------------------------
class GITD_BuckShard : Actor
{
	int    slice;        // the score slice this shard carries (shown on the fragment)
	int    life;
	int    maxl;         // total lifetime in tics
	Vector3 pvel;
	bool   embedded;     // has stuck to a surface?
	int    embedLife;    // tics since embed (drives the stuck-glow fade)
	double nx, ny;       // fixed surface normal once embedded (dir for AddGlowPanel)
	int    rgb;          // packed neon tint (r<<16|g<<8|b)
	double sz;           // shard half-size

	Default { +NOINTERACTION +NOGRAVITY +NOBLOCKMAP +DONTSPLASH +NOTONAUTOMAP; RenderStyle "None"; }
	States { Spawn: TNT1 A 1; Loop; }

	override void Tick()
	{
		Super.Tick();
		life++;
		if (life > maxl) { Destroy(); return; }

		int br = (rgb >> 16) & 0xFF, bg = (rgb >> 8) & 0xFF, bb = rgb & 0xFF;

		if (!embedded)
		{
			// --- in-flight: trace the step we're about to take for a world hit ---
			Vector3 step = pvel;
			double slen = step.Length();
			if (slen > 0.01)
			{
				double sa  = atan2(step.y, step.x);                 // yaw of travel
				double sp  = -atan2(step.z, step.xy.Length());      // pitch (down = +)
				FLineTraceData t;
				bool hit = LineTrace(sa, slen + 2.0, sp,
				                     TRF_THRUACTORS,                 // pass actors, hit world only
				                     0.0, data: t);
				if (hit && t.HitType != TRACE_HitNone &&
				    (t.HitType == TRACE_HitWall || t.HitType == TRACE_HitFloor || t.HitType == TRACE_HitCeiling))
				{
					// --- EMBED: snap to the contact, lift a hair off, freeze ---
					Vector3 hp = t.HitLocation;
					if (t.HitType == TRACE_HitWall)
					{
						// Outward normal = perpendicular to the hit line, chosen to
						// face back toward the incoming shard (it struck from outside).
						if (t.HitLine)
						{
							Vector2 d = t.HitLine.delta;
							double dl = d.Length(); if (dl < 0.001) dl = 1.0;
							double n1x = -d.y / dl, n1y = d.x / dl;        // one perpendicular
							// pick the perpendicular that opposes travel (points back at us)
							double dotv = n1x * step.x + n1y * step.y;
							nx = (dotv > 0.0) ? -n1x : n1x;
							ny = (dotv > 0.0) ? -n1y : n1y;
						}
						else { nx = -cos(sa); ny = -sin(sa); }            // fallback: face whence it came
						hp.x += nx * 1.5; hp.y += ny * 1.5;
					}
					else
					{
						nx = 0.0; ny = 0.0;        // floor/ceiling -> camera-facing read
						hp.z += (t.HitType == TRACE_HitFloor) ? 2.0 : -2.0;
					}
					SetOrigin(hp, true);
					embedded = true;
					embedLife = 0;
					// stuck shards linger a touch longer so the wall reads "studded with glow"
					maxl = life + 22;
				}
			}

			if (!embedded)
			{
				SetOrigin(pos + pvel, true);
				pvel.z  -= 0.62;        // gravity arc
				pvel.xy *= 0.965;       // light air drag (shards keep their punch)
			}

			// bright, hot fragment streaking out
			double f = clamp(1.0 - double(life) / double(maxl), 0.0, 1.0);
			f = f * f * (3.0 - 2.0 * f);
			double bright = clamp(0.55 + f * 0.45, 0.0, 1.0);
			Color col = Color(255, int(br * bright), int(bg * bright), int(bb * bright));
			// shape 17 = shard; dir(0,0) = camera-facing while tumbling
			level.AddGlowPanel(col, sz, pos.x, pos.y, pos.z, 17, f, 0.0, 0.0, slice);
		}
		else
		{
			// --- embedded: stuck to the surface, fixed orientation, slow fade ---
			embedLife++;
			int hold = max(8, maxl - life + embedLife);    // remaining stuck-glow budget
			double f = clamp(1.0 - double(embedLife) / double(hold + 1), 0.0, 1.0);
			f = f * f * (3.0 - 2.0 * f);
			double bright = clamp(0.25 + f * 0.55, 0.0, 1.0);
			Color col = Color(255, int(br * bright), int(bg * bright), int(bb * bright));
			// fixed-orientation panel (nx,ny) for walls; (0,0) for floor/ceiling
			level.AddGlowPanel(col, sz * 1.05, pos.x, pos.y, pos.z, 17, f, nx, ny, slice);
		}
	}
}

// ----------------------------------------------------------------------------
//  GITD_BuckSlam -- the payoff. Spawned at the wound, waits the blast delay,
//  then punches a SHOCKWAVE RING (14) + FILLED-DISC flash (15) and assembles the
//  FULL TOTAL as a camera-facing number that converges in and rings, then fades.
// ----------------------------------------------------------------------------
class GITD_BuckSlam : Actor
{
	int    total;        // full hit score the shards summed to
	int    delay;        // tics to wait before the slam (the shards' flight)
	int    life;
	int    rgb;          // neon tint shared with the shards
	double power;        // 0..1 scaled by damage -> ring radius / disc size

	Default { +NOINTERACTION +NOGRAVITY +NOBLOCKMAP +DONTSPLASH +NOTONAUTOMAP; RenderStyle "None"; }
	States { Spawn: TNT1 A 1; Loop; }

	override void Tick()
	{
		Super.Tick();
		life++;
		if (life <= delay) return;                  // shards still in flight

		int sl = life - delay;                       // tics since the slam fired
		int slamLen = 30;
		if (sl > slamLen) { Destroy(); return; }

		int br = (rgb >> 16) & 0xFF, bg = (rgb >> 8) & 0xFF, bb = rgb & 0xFF;
		double prog = double(sl) / double(slamLen);  // 0..1 across the slam

		// ---- concussion frames: a hard disc flash + an outward shockwave ring ----
		if (sl <= 12)
		{
			double ringR = 26.0 + power * 60.0;                 // bigger damage = wider ring
			double rp    = double(sl) / 12.0;                   // ring expansion lane (0..1)
			// SHOCKWAVE RING (shape 14): wipeProgress carries the expanding radius
			Color ringCol = Color(255, br, bg, bb);
			level.AddGlowPanel(ringCol, ringR, pos.x, pos.y, pos.z, 14, rp, 0.0, 0.0, 0);

			// FILLED-DISC flash (shape 15): a bright concussive core, fading fast
			double dfade = clamp(1.0 - rp, 0.0, 1.0);
			double discR = (14.0 + power * 18.0) * (0.6 + 0.4 * dfade);
			Color discCol = Color(255, 255, 255, 235);          // molten white core
			level.AddGlowPanel(discCol, discR, pos.x, pos.y, pos.z, 15, dfade, 0.0, 0.0, 0);
		}

		// ---- the FULL TOTAL number: converges in from a slight pop, then fades ----
		double asm, fade = 1.0;
		if (sl < 8)        asm  = 1.0 - double(sl) / 8.0;                    // converge in
		else if (sl < 22)  asm  = 0.0;                                       // hold
		else             { asm  = 0.0; fade = 1.0 - double(sl - 22) / 8.0; } // fade out
		asm  = clamp(asm,  0.0, 1.0); asm  = asm  * asm  * (3.0 - 2.0 * asm);
		fade = clamp(fade, 0.0, 1.0); fade = fade * fade * (3.0 - 2.0 * fade);

		let pmo = players[consoleplayer].mo;
		double a = pmo ? pmo.angle : angle;
		double rgtx = sin(a), rgty = -cos(a);                   // camera-right (horizontal)

		// digit count
		int n = 1, tmp = total;
		while (tmp >= 10) { tmp /= 10; n++; }
		if (n > 5) n = 5;

		double h = 19.0 + power * 7.0;                          // bigger hit = bigger number
		double spacing = h * 2.2;
		// number rides the weapon tint, brightening to white-hot at the slam peak
		double slamHot = clamp(1.0 - prog, 0.0, 1.0);
		int nr = int(br + (255 - br) * slamHot * 0.7);
		int ng = int(bg + (255 - bg) * slamHot * 0.7);
		int nb = int(bb + (255 - bb) * slamHot * 0.7);
		Color col = Color(255, nr, ng, nb);

		for (int i = 0; i < n; i++)
		{
			int digit = (total / Pow10(n - 1 - i)) % 10;
			double off   = (double(i) - double(n - 1) / 2.0) * spacing;
			double homeX = pos.x + rgtx * off;
			double homeY = pos.y + rgty * off;

			// each digit converges in from its own scatter offset (the shard-slam look)
			double sgnH = (i % 2 == 0) ? -1.0 : 1.0;
			double sgnV = (i < (n + 1) / 2) ? 1.0 : -1.0;
			double px = homeX + rgtx * sgnH * 70.0 * asm;
			double py = homeY + rgty * sgnH * 70.0 * asm;
			double pz = pos.z + sgnV * 52.0 * asm;

			level.AddGlowPanel(col, h, px, py, pz, 13, fade, 0.0, 0.0, digit);
		}
	}

	static int Pow10(int p) { int v = 1; for (int k = 0; k < p; k++) v *= 10; return v; }
}

// ----------------------------------------------------------------------------
//  GITD_Buckshot -- the static factory. Builds the cone, spawns the shards, and
//  arms the slam. Call once per shotgun hit.
// ----------------------------------------------------------------------------
class GITD_Buckshot play
{
	static void Fire(Actor mon, int dmg, int pn)
	{
		if (!mon) return;
		let en = CVar.FindCVar("gitd_buckshot_enabled");
		if (en && !en.GetBool()) return;
		if (pn < 0 || pn >= MAXPLAYERS || !players[pn].mo) return;

		Actor pl = players[pn].mo;

		// --- wound point (cone apex) ---
		Vector3 wound = (mon.pos.x, mon.pos.y, mon.pos.z + mon.height * 0.55);

		// --- shot direction: player -> monster (the cone axis) ---
		Vector3 axis = (wound.x - pl.pos.x, wound.y - pl.pos.y,
		                wound.z - (pl.pos.z + pl.height * 0.78));
		double al = axis.Length();
		if (al < 1.0) { axis = (cos(pl.angle), sin(pl.angle), 0.0); al = 1.0; }
		axis /= al;

		// eye position (for biasing a couple shards to whip PAST the head)
		Vector3 eye = (pl.pos.x, pl.pos.y, pl.pos.z + pl.height * 0.78);

		// --- damage scaling: bigger hit => more shards, wider + faster cone ---
		double pw     = clamp(double(dmg) / 60.0, 0.0, 1.0);   // 0..1 power
		int    shards = 6 + int(pw * 4.0 + 0.5);               // 6..10 pellets
		double speed  = 9.0 + pw * 7.0;                        // base blast speed
		double spread = 0.45 + pw * 0.35;                      // cone half-width (tan-ish)

		// build an orthonormal basis around the axis for cone spread
		Vector3 up = (0.0, 0.0, 1.0);
		if (abs(axis.z) > 0.9) up = (1.0, 0.0, 0.0);
		Vector3 rgt = (axis.y * up.z - axis.z * up.y,
		               axis.z * up.x - axis.x * up.z,
		               axis.x * up.y - axis.y * up.x);          // axis x up
		double rl = rgt.Length(); if (rl < 0.001) rl = 1.0; rgt /= rl;
		Vector3 vup = (rgt.y * axis.z - rgt.z * axis.y,
		               rgt.z * axis.x - rgt.x * axis.z,
		               rgt.x * axis.y - rgt.y * axis.x);        // rgt x axis (true up in cone plane)

		// neon tint: shotgun signature = hot amber/orange (HF's 2nd orange family)
		int rgb = (255 << 16) | (124 << 8) | 27;               // #FF7C1B

		// split the score across the shards (last shard mops up the remainder)
		int per = max(1, dmg / shards);
		int given = 0;

		for (int i = 0; i < shards; i++)
		{
			// jittered cone direction
			double sx = frandom[gbuck](-1.0, 1.0) * spread;
			double sy = frandom[gbuck](-1.0, 1.0) * spread;

			// bias ~2 shards back toward the player's eye so they whip PAST the head
			bool toFace = (i < 2);
			Vector3 dir;
			if (toFace)
			{
				Vector3 back = (eye.x - wound.x, eye.y - wound.y, eye.z - wound.z);
				double bl = back.Length(); if (bl < 1.0) bl = 1.0; back /= bl;
				// mostly toward the face, with cone jitter so it sprays near (not into) the eye
				dir = (back.x + rgt.x * sx * 1.3 + vup.x * sy * 1.3,
				       back.y + rgt.y * sx * 1.3 + vup.y * sy * 1.3,
				       back.z + rgt.z * sx * 1.3 + vup.z * sy * 1.3);
			}
			else
			{
				dir = (axis.x + rgt.x * sx + vup.x * sy,
				       axis.y + rgt.y * sx + vup.y * sy,
				       axis.z + rgt.z * sx + vup.z * sy);
			}
			double dl = dir.Length(); if (dl < 0.001) dl = 1.0; dir /= dl;

			GITD_BuckShard sh = GITD_BuckShard(Actor.Spawn("GITD_BuckShard", wound));
			if (!sh) continue;

			double sp = speed * frandom[gbuck](0.82, 1.18);    // per-pellet speed variance
			if (toFace) sp *= 1.15;                            // face-whippers travel a touch faster
			sh.pvel  = (dir.x * sp, dir.y * sp, dir.z * sp + 1.6);   // slight upward kick
			sh.maxl = 16 + random[gbuck](0, 6);
			sh.sz   = 7.0 + frandom[gbuck](0.0, 2.5);
			sh.rgb  = rgb;

			int give = (i == shards - 1) ? max(1, dmg - given) : per;
			given  += give;
			sh.slice = give;
		}

		// --- arm the slam: fires the ring + disc + total after the shards' flight ---
		GITD_BuckSlam slam = GITD_BuckSlam(Actor.Spawn("GITD_BuckSlam", wound));
		if (slam)
		{
			slam.total = dmg;
			slam.delay = 12;                 // ~0.34s -- the blast beat
			slam.power = pw;
			slam.rgb   = rgb;
		}
	}
}
