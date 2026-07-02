// ============================================================================
//  GITD "THE BRAND" -- the REVOLVER weapon-signature score effect.
//
//  ONE heavy, oversized molten-white number FORGES at the wound (with a disc
//  flash + a shockwave ring punching out), then RECOILS toward the player's eye
//  and DECELERATES HARD, stopping dead a hand's-width short of the face -- the
//  violent stop IS the punch. It then rings/shimmers like struck steel while a
//  smoke puff curls up and the whole thing fades. Weight + a hard stop.
//
//  Four pieces, all on the AddGlowPanel air-panel primitive (the proven
//  gitd_dampop self-integrating one-shot actor pattern):
//    GITD_Brand       -- the number (shape 13, heavy font), forge -> recoil -> settle
//    GITD_BrandShape  -- the forge ring (shape 14) + disc flash (shape 15)
//    GITD_BrandSmoke  -- the settle smoke puff (shape 20)
//
//  Entry point: GITD_Brand.Fire(mon, dmg, pn) -- called from the combo handler
//  when the damaging weapon maps to the REVOLVER signature (Pistol / default).
//
//  Cvar: gitd_brand_enabled (master on/off).
//
//  Tunables are placeholder FEEL values (the user dials these in VR); none of
//  them change scoring -- this is presentation only.
// ============================================================================

// ----------------------------------------------------------------------------
//  GITD_Brand -- the single heavy number. Choreography by 'life' tics (35hz):
//    FORGE  (life 0..FORGE_END)   : at the wound, oversized + over-bright.
//    RECOIL (..RECOIL_END)        : eases wound -> stopPos via cubic ease-OUT
//                                   (fast start, hard decel = the recoil punch).
//    SETTLE (..TTL)              : parked at the face, damped struck-steel
//                                   scale/brightness wobble, then fades.
//  stopPos is recomputed live each tic from the player's current eye so the
//  number tracks the head a little even while flying (VR: the player may turn).
// ----------------------------------------------------------------------------
class GITD_Brand : Actor
{
	int     dmg;
	int     life;
	Vector3 startPos;   // the wound (cone apex / forge point)
	Vector3 stopPos;    // where the recoil halts, a hand's-width short of the eye

	// --- feel constants (placeholders; presentation only) ---
	const FONT       = 63;     // heavy font index for the brand number (matches combo face)
	const TTL       = 26;     // total tics the number lives (~0.74s @35hz)
	const FORGE_END  = 4;      // tics: the oversized forge window
	const RECOIL_END = 15;     // tics: the number has stopped by here
	const STOP_GAP   = 36.0;   // world units short of the eye it freezes
	const BASE_RAD   = 26.0;   // half-size of the number at rest (BIG, it's the hero)
	const FORGE_RAD  = 40.0;   // over-sized half-size on the forge frames

	Default { +NOINTERACTION +NOGRAVITY +NOBLOCKMAP +DONTSPLASH +NOTONAUTOMAP; RenderStyle "None"; }
	States { Spawn: TNT1 A 1; Loop; }

	// cubic ease-out: fast start, hard slow finish -> the STOP reads as the recoil.
	static double EaseOut(double x)
	{
		x = clamp(x, 0.0, 1.0);
		double inv = 1.0 - x;
		return 1.0 - inv * inv * inv;
	}

	override void Tick()
	{
		Super.Tick();
		life++;
		if (life > TTL) { Destroy(); return; }

		// spawn the curl of smoke exactly as the number parks (settle frame).
		if (life == RECOIL_END + 1)
		{
			GITD_BrandSmoke s = GITD_BrandSmoke(Actor.Spawn("GITD_BrandSmoke", stopPos + (0, 0, 8.0)));
			if (s) { s.maxl = 14; s.rise = 1.4; }
		}

		// ---- live eye each tic; recompute the halt point a hand's-width short ----
		let pmo = players[consoleplayer].mo;
		if (pmo)
		{
			Vector3 eye   = pmo.pos + (0, 0, pmo.height * 0.78);
			Vector3 toEye = level.Vec3Diff(startPos, eye);     // start -> eye (portal-aware)
			double d = toEye.Length();
			if (d > 1.0)
			{
				Vector3 n = toEye / d;
				stopPos = eye - n * STOP_GAP;                  // freeze short of the face
			}
			else stopPos = startPos;
		}

		double radius, fade;
		Vector3 p;

		if (life <= FORGE_END)
		{
			// FORGE: sit at the wound, oversized, full white-hot.
			double k = double(life) / double(FORGE_END);       // 0..1
			radius = FORGE_RAD + (BASE_RAD - FORGE_RAD) * k;
			fade   = 1.0;
			p      = startPos;
		}
		else if (life <= RECOIL_END)
		{
			// RECOIL: ease wound -> stopPos, decelerating hard.
			double raw = double(life - FORGE_END) / double(RECOIL_END - FORGE_END);
			double e   = EaseOut(raw);
			p      = startPos + (stopPos - startPos) * e;
			radius = BASE_RAD;
			fade   = 1.0;
		}
		else
		{
			// SETTLE: parked at the face, struck-steel ring, fade out.
			double raw = double(life - RECOIL_END) / double(TTL - RECOIL_END);   // 0..1
			double wob = exp(-raw * 5.0) * sin(raw * 38.0);    // fast damped wobble
			radius = BASE_RAD * (1.0 + 0.12 * wob);
			double st = clamp((raw - 0.45) / 0.55, 0.0, 1.0); double f = 1.0 - st * st * (3.0 - 2.0 * st);   // hold then drop
			fade   = clamp(f * (1.0 + 0.18 * wob), 0.0, 1.0);
			p      = stopPos;
		}

		Color col = Color(255, 255, 255, 232);                 // molten white-gold (shader white-cores it)
		int wt = 13 + FONT * 100;                              // shape 13, heavy font
		level.AddGlowPanel(col, radius, p.x, p.y, p.z, wt, fade, 0.0, 0.0, dmg);
	}

	// Spawn the whole effect from one revolver hit.
	static void Fire(Actor mon, int dmg, int pn)
	{
		if (!mon) return;
		let en = CVar.FindCVar("gitd_brand_enabled");
		if (en && !en.GetBool()) return;

		// wound = monster mid-body (the forge point)
		Vector3 wound = (mon.pos.x, mon.pos.y, mon.pos.z + mon.height * 0.55);

		GITD_Brand b = GITD_Brand(Actor.Spawn("GITD_Brand", wound));
		if (b)
		{
			b.dmg      = dmg;
			b.life     = 0;
			b.startPos = wound;
			let pmo = players[consoleplayer].mo;
			Vector3 eye = pmo ? pmo.pos + (0, 0, pmo.height * 0.78) : wound + (0, 0, 48.0);
			Vector3 toEye = level.Vec3Diff(wound, eye);
			double d = toEye.Length();
			b.stopPos = (d > 1.0) ? eye - (toEye / d) * GITD_Brand.STOP_GAP : wound;
		}

		// FORGE flash: a quick disc (15) + an outward shockwave ring (14) at t0.
		GITD_BrandShape disc = GITD_BrandShape(Actor.Spawn("GITD_BrandShape", wound));
		if (disc) { disc.shape = 15; disc.maxl = 5;  disc.rad0 = 30.0; disc.rad1 = 30.0; }
		GITD_BrandShape ring = GITD_BrandShape(Actor.Spawn("GITD_BrandShape", wound));
		if (ring) { ring.shape = 14; ring.maxl = 12; ring.rad0 = 18.0; ring.rad1 = 78.0; }
	}
}

// ----------------------------------------------------------------------------
//  GITD_BrandShape -- a self-animating forge panel. Sweeps wipeProgress 0->1
//  across its life (the shader's animation lane) and lerps its radius. Sits at
//  the wound, camera-facing. shape 14 = ring, 15 = disc.
// ----------------------------------------------------------------------------
class GITD_BrandShape : Actor
{
	int    shape;          // 14 ring / 15 disc
	int    life, maxl;
	double rad0, rad1;     // radius lerps rad0 -> rad1 across life

	Default { +NOINTERACTION +NOGRAVITY +NOBLOCKMAP +DONTSPLASH +NOTONAUTOMAP; RenderStyle "None"; }
	States { Spawn: TNT1 A 1; Loop; }

	override void Tick()
	{
		Super.Tick();
		life++;
		if (life > maxl) { Destroy(); return; }

		double t = double(life) / double(maxl);            // 0..1 anim lane
		double radius = rad0 + (rad1 - rad0) * t;

		// disc (15): the shader reads wipeProgress as brightness and snaps it off
		// (env = panim^2), so feed it a falling 1->0. ring (14): the shader reads
		// wipeProgress as the EXPANSION lane (0->1), so feed it t directly.
		double wp = (shape == 15) ? clamp(1.0 - t, 0.0, 1.0) : t;

		Color col = Color(255, 255, 255, 226);             // gold-white forge heat
		level.AddGlowPanel(col, radius, pos.x, pos.y, pos.z, shape, wp, 0.0, 0.0, 0);
	}
}

// ----------------------------------------------------------------------------
//  GITD_BrandSmoke -- the settle smoke puff. Drifts up, billows, fades. Shape 20
//  (soft additive haze in the shader; wipeProgress = brightness, faded to 0).
// ----------------------------------------------------------------------------
class GITD_BrandSmoke : Actor
{
	int    life, maxl;
	double rise;   // per-tic upward drift (decays)

	Default { +NOINTERACTION +NOGRAVITY +NOBLOCKMAP +DONTSPLASH +NOTONAUTOMAP; RenderStyle "None"; }
	States { Spawn: TNT1 A 1; Loop; }

	override void Tick()
	{
		Super.Tick();
		life++;
		if (life > maxl) { Destroy(); return; }
		SetOrigin(pos + (0, 0, rise), true);
		rise *= 0.96;

		double t = double(life) / double(maxl);
		double radius = 16.0 + 26.0 * t;                   // billows as it curls
		double fade = 1.0 - t;                             // brightness -> 0
		Color col = Color(255, 150, 140, 130);             // desaturated warm grey, dim
		level.AddGlowPanel(col, radius, pos.x, pos.y, pos.z, 20, fade, 0.0, 0.0, 0);
	}
}
