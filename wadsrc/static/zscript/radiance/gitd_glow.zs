// ============================================================================
// hf_glow.zs -- HF GlowInTheDark, dynamic ZScript rebuild
// ============================================================================
// Replaces the old ACS colorfulmaps controller. Drives per-sector floor/ceiling
// glow live via the engine's native SetGlowColor / SetGlowHeight. Because it
// runs in ZScript every tick, it can do things ACS could not: animated pulse,
// breathing, and combat-reactive intensity -- all without a map restart.
//
// The curated glowing-flat list still lives in GLDEFS.txt (kept as-is). This
// handler layers a colored, animated glow on top, controlled by cvars:
//
//   hf_glow_enabled    master on/off
//   hf_glow_mode       0 static / 1 pulse / 2 breathe / 3 react-combat
//   hf_glow_target     0 floor / 1 ceiling / 2 both
//   hf_glow_r/g/b      primary glow color (player color select)
//   hf_glow_intensity  brightness multiplier
//   hf_glow_height     glow falloff height
//   hf_glow_speed      animation speed for pulse/breathe
//   (reserved/greyed: hf_glow_onlylit, _r2/_g2/_b2, _actors, _combatmul)
//
// Applied periodically (not every single tic) for performance on big maps.
// ============================================================================
//
// ----------------------------------------------------------------------------
// ROLE IN GITD: This is the runtime heart of the GlowInTheDark (GITD) mod's
// "ambient glow" pillar. Two cooperating pieces live here:
//   1) HF_GlowHandler (an EventHandler) -- the global per-tick driver that
//      colours every sector's floor/ceiling glow, runs the killstreak "heat"
//      red-floor effect, and draws the streak HUD. It uses the native GLOW
//      surface-gradient channel (SetGlowColor/SetGlowHeight) -- the GITD hard
//      rule is ZERO dynamic lights for the ambient glow; GLOW is the mechanism.
//   2) HF_ImpactRipple (an Actor) -- a per-hit, expanding/collapsing light
//      pulse spawned at projectile impacts. NOTE: this one deliberately uses
//      A_AttachLight (an explicit runtime light), which is acceptable here
//      because it is a transient impact FX actor, not the ambient surface glow.
//
// SCOPE DISCIPLINE: GZDoom splits "play" (simulation) and "ui" (rendering)
// scope. WorldTick/WorldThingDied run in PLAY; RenderOverlay runs in UI. UI
// code may only READ cached fields, never touch cvars or play-scope state --
// hence the hud* fields are snapshotted in WorldTick and only read in the
// overlay (the documented "GunBonsai pattern").
// ----------------------------------------------------------------------------
class HF_GlowHandler : EventHandler   // Global event handler: drives ambient glow, killstreak FX, and the streak HUD.
{
	bool   active;
	double phase;        // animation phase accumulator
	int    refreshTimer; // re-apply throttle

	// --- killstreak glow state (written in play tick, read by the ui HUD) ---
	int    ksKills;      // current streak count
	int    ksTimer;      // tics left before the streak decays a kill
	double ksHeat;       // smoothed 0..1 streak intensity (eases up/down)

	// HUD config cached from cvars in play (WorldTick); the ui RenderOverlay
	// only reads these fields -- never cvars -- matching the GunBonsai pattern
	// ("use cached data updated in play scope via WorldTick").
	bool   hudOn;
	double hudX, hudY, hudScale;


	// Map start: reset the handler so glow re-applies cleanly on a fresh level.
	override void WorldLoaded(WorldEvent e)
	{
		// Clean up persistent vaporwave colors if they are set as startup defaults
		CVar cfl = CVar.FindCVar("gitd_floor_color");
		CVar ccl = CVar.FindCVar("gitd_ceil_color");
		if (cfl && ccl)
		{
			int flColor = cfl.GetInt();
			int clColor = ccl.GetInt();
			if (flColor == 0xff007f && clColor == 0x00f0ff)
			{
				cfl.SetInt(0xffb028); // Default warm amber
				ccl.SetInt(0x303030); // Default minimal slate grey
			}
		}

		if (!CB("hf_glow_enabled", false))
		{
			ClearGlow();
		}

		active = false;
		phase = 0.0;
		refreshTimer = 0;
	}

	// read an int cvar safely
	// CI/CF/CB: null-safe cvar readers -- return the default if the cvar is absent.
	static int CI(String name, int def)
	{
		CVar c = CVar.FindCVar(name);
		return c ? c.GetInt() : def;
	}
	// Null-safe float cvar read.
	static double CF(String name, double def)
	{
		CVar c = CVar.FindCVar(name);
		return c ? c.GetFloat() : def;
	}
	// Null-safe bool cvar read.
	static bool CB(String name, bool def)
	{
		CVar c = CVar.FindCVar(name);
		return c ? c.GetBool() : def;
	}
	// linear interpolate a->b by t (0..1)
	static double HF_Lerp(double a, double b, double t)
	{
		return a + (b - a) * t;
	}

	// Deterministic hash -> 0..1, so a given (seed) always yields the same value.
	// Lets each sector keep a STABLE random color instead of strobing every frame.
	static double HF_Hash01(int seed)
	{
		// integer hash (xorshift-ish), then fold to 0..1
		// Big odd constants are classic hash multipliers: they scramble bits so
		// nearby seeds (adjacent sector indices) map to very different outputs.
		int x = seed * 374761393 + 668265263;
		x = (x ^ (x >> 13)) * 1274126177;
		x = x ^ (x >> 16);
		// Mask off the sign bit (0x7FFFFFFF), then divide to land in [0,1].
		return (x & 0x7FFFFFFF) / double(0x7FFFFFFF);
	}

	// Produce a vivid, stable-ish random color for a sector. `salt` separates the
	// floor stream from the ceiling stream so the two planes differ. `epoch` lets
	// the whole palette re-roll over time when a re-roll rate is set.
	static color HF_RandSectorColor(int sectorIndex, int salt, int epoch, double inten, double timeSec = 0.0)
	{
		// Mix the three inputs with distinct large primes so sector/salt/epoch
		// each perturb the seed independently (no accidental collisions).
		int seed = sectorIndex * 2654435761 + salt * 40503 + epoch * 19349663;
		// [GITD] room-to-room variety MODE (hf_glow_random_mode): 0 vivid (any hue),
		// 1 curated neon palette, 2 hue-drift across sector index (cohesive sweep),
		// 3 complementary floor/ceiling pair. Default 0 keeps the original behaviour.
		int rmode = CI("hf_glow_random_mode", 0);
		double h   = 0.0;
		double sat = 0.85;
		double val = 0.95;
		if (rmode == 1)
		{
			// CURATED: snap the hue to a hand-built neon set so the arena reads as
			// designed, not noise. The sector hash picks which entry of the palette.
			int pal = CI("hf_glow_random_palette", 0);
			int idx = int(HF_Hash01(seed) * 6.0);
			h   = GITD_PaletteHue(pal, idx);
			sat = 0.80 + 0.20 * HF_Hash01(seed + 7);
			val = 0.85 + 0.15 * HF_Hash01(seed + 13);
		}
		else if (rmode == 2)
		{
			// HUE DRIFT: the whole wheel rotates CONTINUOUSLY over time (timeSec, seconds)
			// so colours glide and never hard-snap, plus a fixed per-sector offset so
			// neighbouring rooms still differ in space. No epoch/re-roll dependency = no
			// jumps. Ceiling rides 35deg off the floor for a gentle two-tone.
			double drift   = CF("hf_glow_random_drift", 12.0);   // per-sector spatial offset (deg)
			double dspeed  = CF("hf_glow_drift_speed", 4.0);     // deg/sec the wheel turns
			double baseHue = (salt == 1) ? 35.0 : 0.0;
			h = baseHue + timeSec * dspeed + sectorIndex * drift;
			h -= 360.0 * floor(h / 360.0);
		}
		else if (rmode == 3 && salt == 1)
		{
			// COMPLEMENTARY: ceiling takes the floor's hue + 180 so each room is a
			// tuned two-tone pair, not two unrelated colours.
			int fseed = sectorIndex * 2654435761 + epoch * 19349663;   // the floor (salt 0) seed
			h = HF_Hash01(fseed) * 360.0 + 180.0;
			h -= 360.0 * floor(h / 360.0);
		}
		else
		{
			// 0 = VIVID (original): any hue around the wheel, punchy sat/val.
			h   = HF_Hash01(seed) * 360.0;
			sat = 0.75 + 0.25 * HF_Hash01(seed + 7);
			val = 0.85 + 0.15 * HF_Hash01(seed + 13);
		}
		double r, g, b;
		[r, g, b] = HF_HSV2RGB(h, sat, val);
		// Scale by intensity and clamp into byte range before packing the color.
		int ir = int(clamp(r * 255.0 * inten, 0, 255));
		int ig = int(clamp(g * 255.0 * inten, 0, 255));
		int ib = int(clamp(b * 255.0 * inten, 0, 255));
		return Color(255, ir, ig, ib);
	}

	// [GITD] Curated neon hue palettes (degrees). Each palette = 6 vivid HF hues,
	// selected by hf_glow_random_palette. ZScript has no array literals, so switched.
	static double GITD_PaletteHue(int pal, int idx)
	{
		int i = idx % 6; if (i < 0) i += 6;
		if (pal == 1)   // acid -- greens / limes
		{
			switch (i) { case 0: return 95;  case 1: return 80;  case 2: return 130; case 3: return 160; case 4: return 60;  default: return 110; }
		}
		if (pal == 2)   // sunset -- oranges / reds / pink
		{
			switch (i) { case 0: return 12;  case 1: return 28;  case 2: return 45;  case 3: return 330; case 4: return 350; default: return 18;  }
		}
		if (pal == 3)   // vapor -- magenta / cyan / violet
		{
			switch (i) { case 0: return 300; case 1: return 320; case 2: return 200; case 3: return 185; case 4: return 260; default: return 290; }
		}
		// arcade (default) -- cyan, magenta, lime, amber, violet, hot-pink
		switch (i) { case 0: return 185; case 1: return 300; case 2: return 95;  case 3: return 45;  case 4: return 270; default: return 330; }
	}

	// HSV (h 0..360, s/v 0..1) -> RGB (each 0..1)
	// Standard HSV->RGB. ZScript has no GLSL builtins, so the math is inlined.
	static double, double, double HF_HSV2RGB(double h, double s, double v)
	{
		double c = v * s;                                 // chroma
		double hp = h / 60.0;                             // hue sextant position (0..6)
		double hp2 = hp - 2.0 * floor(hp / 2.0);          // hp mod 2.0, double-safe
		double x = c * (1.0 - abs(hp2 - 1.0));            // second-largest component
		double r = 0, g = 0, b = 0;
		// Select RGB ordering by which 60-degree sextant the hue falls in.
		if      (hp < 1.0) { r = c; g = x; b = 0; }
		else if (hp < 2.0) { r = x; g = c; b = 0; }
		else if (hp < 3.0) { r = 0; g = c; b = x; }
		else if (hp < 4.0) { r = 0; g = x; b = c; }
		else if (hp < 5.0) { r = x; g = 0; b = c; }
		else               { r = c; g = 0; b = x; }
		double m = v - c;                                 // value lift added to all channels
		return r + m, g + m, b + m;
	}

	// RGB (each 0..1) -> HSV (h 0..360, s/v 0..1)
	// Standard RGB->HSV logic inlined for ZScript.
	static double, double, double HF_RGB2HSV(double r, double g, double b)
	{
		double mx = max(r, max(g, b));
		double mn = min(r, min(g, b));
		double df = mx - mn;
		double h = 0;
		double s = (mx == 0.0) ? 0.0 : (df / mx);
		double v = mx;
		if (mx != mn)
		{
			if (mx == r) h = (g - b) / df + (g < b ? 6.0 : 0.0);
			else if (mx == g) h = (b - r) / df + 2.0;
			else if (mx == b) h = (r - g) / df + 4.0;
			h *= 60.0;
		}
		return h, s, v;
	}


	// Main per-tic driver (PLAY scope): caches HUD config, advances animation,
	// throttles the full sector re-apply, and runs the killstreak glow.
	override void WorldTick()
	{
		// --- killstreak decay + heat smoothing ---
		HF_KillstreakTick();

		// cache HUD config from cvars here (play scope) for the ui overlay
		hudOn    = CB("hf_streakhud", true);
		hudX     = CF("hf_streakhud_x", 0.5);
		hudY     = CF("hf_streakhud_y", 0.15);
		hudScale = CF("hf_streakhud_scale", 2.0);

		bool enabled = CB("hf_glow_enabled", false);

		// Turning off: clear any glow we applied, once.
		if (!enabled)
		{
			if (active) { ClearGlow(); active = false; }
			return;
		}

		int mode = CI("hf_glow_mode", 1);
		double speed = CF("hf_glow_speed", 1.0);

		// advance animation phase
		// 0.015/tic is a slow base drift; wrap at 1000 to keep sin() args bounded.
		phase += 0.015 * speed;
		if (phase > 1000.0) phase -= 1000.0;


		// throttle full re-apply: static every ~1s, animated every 3 tics
		// Static mode rarely changes, so 35 tics (~1s) is plenty; animated modes
		// need a fast 3-tic cadence to look smooth without re-touching every sector each tic.
		refreshTimer--;
		bool doApply = false;
		// drift mode must re-apply often or its smooth hue rotation would step coarsely
		bool drifting = CB("hf_glow_random", false) && CI("hf_glow_random_mode", 0) == 2;
		if (mode == 0 && !drifting) { if (refreshTimer <= 0) { doApply = true; refreshTimer = 35; } }
		else                        { if (refreshTimer <= 0) { doApply = true; refreshTimer = 3;  } }

		if (doApply)
		{
			ApplyGlow(mode);
			active = true;
		}


		// killstreak red glow runs every tic, independent of the main glow throttle
		if (CB("hf_glow_killstreak", true))
			HF_ApplyKillstreakGlow();
	}

	// Count a kill toward the streak whenever a monster dies to the player.
	override void WorldThingDied(WorldEvent e)
	{
		// STANDALONE PoC: pop an impact ripple when a projectile dies (hits something),
		// so the impact glow works with ANY weapon, not just HF bullets.
		if (e.Thing && e.Thing.bMissile && CB("hf_glow_impact", false))
			e.Thing.Spawn("HF_ImpactRipple", e.Thing.Pos, ALLOW_REPLACE);

		if (!CB("hf_glow_killstreak", true)) return;
		if (!e.Thing || !e.Thing.bIsMonster) return;
		// only player kills count toward the streak
		Actor src = e.Thing.target;   // the killer
		// Prefer the inflictor's owner (e.g. the player who fired the projectile)
		// over the victim's direct target, so projectile/hitscan kills attribute correctly.
		if (e.Inflictor && e.Inflictor.target) src = e.Inflictor.target;
		if (!src || !src.player) return;

		ksKills++;
		int km = CI("hf_glow_ks_max", 10);
		if (km < 1) km = 1;
		if (ksKills > km) ksKills = km;          // cap the streak at the configured max
		ksTimer = CI("hf_glow_ks_window", 105);  // (re)arm the decay window on each kill
	}

	// Decay the streak and ease the heat value toward the target each tic.
	void HF_KillstreakTick()
	{
		if (ksKills > 0)
		{
			ksTimer--;
			if (ksTimer <= 0)
			{
				ksKills--;                               // lose one kill off the streak
				ksTimer = CI("hf_glow_ks_window", 105);
			}
		}
		int km = CI("hf_glow_ks_max", 10);
		if (km < 1) km = 1;
		double targetHeat = double(ksKills) / double(km);   // normalize streak to 0..1
		if (targetHeat > 1.0) targetHeat = 1.0;
		// ease: rises fast on a kill, cools slowly
		// Asymmetric easing gives the "snap hot, fade cool" feel: 0.25 up vs 0.04 down.
		double rate = (targetHeat > ksHeat) ? 0.25 : 0.04;
		ksHeat += (targetHeat - ksHeat) * rate;
		if (ksHeat < 0.001) ksHeat = 0.0;                   // snap tiny residue to zero so glow fully clears
	}

	// Paint a red glow on the floor in a radius around each player. The radius
	// and redness scale with streak heat. Because the player stands on the
	// floor, the sector under them always tracks -- closer surfaces read redder.
	void HF_ApplyKillstreakGlow()
	{
		if (ksHeat <= 0.0) return;          // nothing to paint when fully cooled

		double maxR = CF("hf_glow_ks_radius", 256.0);
		double radius = maxR * ksHeat;       // hotter streak -> wider red pool
		if (radius < 48.0) radius = 48.0;    // keep a minimum visible footprint

		for (int p = 0; p < MAXPLAYERS; ++p)
		{
			if (!playeringame[p]) continue;
			PlayerPawn pawn = players[p].mo;
			if (!pawn) continue;
			Sector psec = pawn.CurSector;
			if (!psec) continue;

			// The player's own floor: reddest (closest surface, always tracks).
			// Red rises 0.4->1.0 with heat; green/blue fall to 0 so it desaturates to pure red as it heats.
			int rr = int(255 * (0.4 + 0.6 * ksHeat));
			Color redCore = Color(255, rr, int(35 * (1.0 - ksHeat)), int(35 * (1.0 - ksHeat)));
			double h = radius * 0.5;          // glow falloff height scales with the pool radius
			psec.SetGlowColor(Sector.floor, redCore);
			psec.SetGlowHeight(Sector.floor, h);

			// Bleed into neighbouring sectors within the radius, fading with the
			// distance from the player to that shared line's midpoint.
			for (int li = 0; li < psec.lines.Size(); ++li)
			{
				Line ln = psec.lines[li];
				if (!ln) continue;
				// Pick the sector on the OTHER side of this shared line.
				Sector other = (ln.frontsector == psec) ? ln.backsector : ln.frontsector;
				if (!other || other == psec) continue;

				// distance from player to this line's midpoint
				Vector2 mid = (ln.v1.p + ln.v2.p) * 0.5;
				double dist = (pawn.pos.xy - mid).Length();
				if (dist > radius) continue;    // skip neighbours outside the heat radius

				double falloff = 1.0 - (dist / radius);   // 1 near, 0 at edge
				double heat2 = ksHeat * falloff;           // local heat dims with distance
				int rr2 = int(255 * (0.3 + 0.5 * heat2));
				Color redEdge = Color(255, rr2, int(20 * (1.0 - heat2)), int(20 * (1.0 - heat2)));
				other.SetGlowColor(Sector.floor, redEdge);
				other.SetGlowHeight(Sector.floor, h * (0.4 + 0.4 * falloff));   // shorter falloff farther out
			}
		}
	}

	// compute the animated intensity 0..1 for the current mode/phase
	double ModeIntensity(int mode)
	{
		double base = CF("hf_glow_intensity", 1.0);
		switch (mode)
		{
			case 1: // pulse -- sharp sine throb
				// phase*360 makes one full sine cycle per unit of phase; oscillates 0.10..1.00 * base.
				return base * (0.55 + 0.45 * sin(phase * 360.0));
			case 2: // breathe -- slow, gentle
				// Slower 120-degree multiplier + narrower 0.40..1.00 band = calm "breathing".
				return base * (0.70 + 0.30 * sin(phase * 120.0));
			case 3: // react-combat -- brighter when monsters are near/alert
			{
				double combat = CombatLevel();
				double mul = CF("hf_glow_combatmul", 2.0);
				return base * (0.5 + 0.5 * combat * mul);
			}
			default: // static
				return base;
		}
	}

	// crude "combat" measure: fraction of nearby monsters that are awake.
	double CombatLevel()
	{
		PlayerInfo pi = players[consoleplayer];
		if (!pi || !pi.mo) return 0.0;
		int total = 0, awake = 0;
		ThinkerIterator it = ThinkerIterator.Create("Actor");
		Actor a;
		while (a = Actor(it.Next()))
		{
			if (!a.bISMONSTER || a.health <= 0) continue;     // only live monsters count
			if (a.Distance3D(pi.mo) > 1024) continue;          // 1024 units = "nearby"
			total++;
			if (a.target) awake++;                              // has a target -> alerted/in combat
			if (total > 24) break; // cap the scan  (bound the per-tic cost on crowded maps)
		}
		if (total == 0) return 0.0;
		return double(awake) / double(total);
	}

	// Recolour every sector's floor/ceiling glow for this frame, honouring the
	// active mode plus the cycle / gradient / split / randomize / liquid options.
	// compute the animated intensity 0..1 for a specific plane
	double GetPlaneIntensity(double base, int mode, double phaseVal)
	{
		switch (mode)
		{
			case 1: // pulse -- sharp sine throb
				return base * (0.55 + 0.45 * sin(phaseVal * 360.0));
			case 2: // breathe -- slow, gentle
				return base * (0.70 + 0.30 * sin(phaseVal * 120.0));
			case 3: // react-combat -- brighter when monsters are near/alert
			{
				double combat = CombatLevel();
				double mul = CF("hf_glow_combatmul", 2.0);
				return base * (0.5 + 0.5 * combat * mul);
			}
			default: // static
				return base;
		}
	}

	// Recolour every sector's floor/ceiling glow for this frame, honouring the
	// active mode plus the cycle / gradient / split / randomize / liquid options.
	void ApplyGlow(int mode)
	{
		double floorInten = GetPlaneIntensity(CF("gitd_floor_intensity", 1.0), CI("gitd_floor_mode", 0), level.maptime * 0.015 * CF("gitd_floor_speed", 1.0));
		double ceilInten  = GetPlaneIntensity(CF("gitd_ceil_intensity", 1.0),  CI("gitd_ceil_mode", 0),  level.maptime * 0.015 * CF("gitd_ceil_speed", 1.0));
		double wallInten  = GetPlaneIntensity(CF("gitd_wall_intensity", 1.0),  CI("gitd_wall_mode", 0),  level.maptime * 0.015 * CF("gitd_wall_speed", 1.0));

		floorInten = clamp(floorInten, 0.0, 2.0);
		ceilInten  = clamp(ceilInten, 0.0, 2.0);
		wallInten  = clamp(wallInten, 0.0, 2.0);

		// primary colors unpack
		int fR = 255, fG = 176, fB = 40; // Default warm amber
		CVar cfl = CVar.FindCVar("gitd_floor_color");
		if (cfl) { int pk = cfl.GetInt(); fR = (pk >> 16) & 0xFF; fG = (pk >> 8) & 0xFF; fB = pk & 0xFF; }

		int cR = 48, cG = 48, cB = 48; // Default minimal slate grey
		CVar ccl = CVar.FindCVar("gitd_ceil_color");
		if (ccl) { int pk = ccl.GetInt(); cR = (pk >> 16) & 0xFF; cG = (pk >> 8) & 0xFF; cB = pk & 0xFF; }

		int wR = 255, wG = 176, wB = 40; // Default warm amber
		CVar cwl = CVar.FindCVar("gitd_wall_color");
		if (cwl) { int pk = cwl.GetInt(); wR = (pk >> 16) & 0xFF; wG = (pk >> 8) & 0xFF; wB = pk & 0xFF; }

		// Legacy fallbacks / compatibility
		bool randomize = CB("hf_glow_random", false);
		bool liquidPriority = CB("hf_glow_liquid_priority", true);

		// Handle legacy overrides -- commented out to allow presets to apply their cohesive colors
		/*
		if (CB("color_toggle", true))
		{
			if (CB("color_ovrand", false))
			{
				fR = CI("color_redd", 135); fG = CI("color_greenn", 135); fB = CI("color_bluee", 135);
				cR = CI("color_red", 135);  cG = CI("color_green", 135);  cB = CI("color_blue", 135);
				randomize = false;
			}
			else
			{
				randomize = true;
			}
		}
		*/

		int rerollRate = CI("hf_glow_random_rate", 0);
		int epoch = (rerollRate > 0) ? int(level.maptime / rerollRate) : 0;
		double tsec = level.maptime / 35.0;

		Array<color> finalFloorColors;
		Array<color> finalCeilColors;
		finalFloorColors.Resize(level.Sectors.Size());
		finalCeilColors.Resize(level.Sectors.Size());

		Array<double> finalFloorHeights;
		Array<double> finalCeilHeights;
		finalFloorHeights.Resize(level.Sectors.Size());
		finalCeilHeights.Resize(level.Sectors.Size());

		for (int i = 0; i < level.Sectors.Size(); i++)
		{
			Sector s = level.Sectors[i];
			if (!s) continue;

			bool isLiquid = false;
			color lcol;
			if (liquidPriority)
			{
				[isLiquid, lcol] = LiquidColorFor(s);
			}

			// --- Floor / Lower Wall Color & Height ---
			color colFloor;
			double hFloor = 0.0;
			if (CB("gitd_floor_enabled", true))
			{
				if (CI("gitd_floor_mode", 0) == 4) // Rainbow Cycle
				{
					double h = (level.maptime * CF("gitd_floor_speed", 1.0) * 4.0);
					h -= 360.0 * floor(h / 360.0);
					double r, g, b;
					[r, g, b] = HF_HSV2RGB(h, 0.95, 0.95);
					colFloor = Color(255, int(r * 255.0 * floorInten), int(g * 255.0 * floorInten), int(b * 255.0 * floorInten));
				}
				else if (CI("gitd_floor_mode", 0) == 5) // Cycle
				{
					double h, s, v;
					[h, s, v] = HF_RGB2HSV(fR / 255.0, fG / 255.0, fB / 255.0);
					double shift = (level.maptime * CF("gitd_floor_speed", 1.0) * 4.0);
					h += shift;
					h -= 360.0 * floor(h / 360.0);
					double r, g, b;
					[r, g, b] = HF_HSV2RGB(h, s, v);
					colFloor = Color(255, int(r * 255.0 * floorInten), int(g * 255.0 * floorInten), int(b * 255.0 * floorInten));
				}
				else if (randomize && !isLiquid)
				{
					colFloor = HF_RandSectorColor(i, 0, epoch, floorInten, tsec);
				}
				else if (isLiquid)
				{
					colFloor = lcol;
				}
				else
				{
					colFloor = Color(255, int(clamp(fR * floorInten, 0, 255)), int(clamp(fG * floorInten, 0, 255)), int(clamp(fB * floorInten, 0, 255)));
				}
				hFloor = CF("gitd_floor_height", 64.0);
			}
			else if (CB("gitd_wall_enabled", true))
			{
				// Fallback to Wall color so lower walls still glow
				if (CI("gitd_wall_mode", 0) == 4) // Rainbow Cycle
				{
					double h = (level.maptime * CF("gitd_wall_speed", 1.0) * 4.0);
					h -= 360.0 * floor(h / 360.0);
					double r, g, b;
					[r, g, b] = HF_HSV2RGB(h, 0.95, 0.95);
					colFloor = Color(255, int(r * 255.0 * wallInten), int(g * 255.0 * wallInten), int(b * 255.0 * wallInten));
				}
				else if (CI("gitd_wall_mode", 0) == 5) // Cycle
				{
					double h, s, v;
					[h, s, v] = HF_RGB2HSV(wR / 255.0, wG / 255.0, wB / 255.0);
					double shift = (level.maptime * CF("gitd_wall_speed", 1.0) * 4.0);
					h += shift;
					h -= 360.0 * floor(h / 360.0);
					double r, g, b;
					[r, g, b] = HF_HSV2RGB(h, s, v);
					colFloor = Color(255, int(r * 255.0 * wallInten), int(g * 255.0 * wallInten), int(b * 255.0 * wallInten));
				}
				else
				{
					colFloor = Color(255, int(clamp(wR * wallInten, 0, 255)), int(clamp(wG * wallInten, 0, 255)), int(clamp(wB * wallInten, 0, 255)));
				}
				hFloor = CF("gitd_wall_height", 64.0);
			}

			// --- Ceiling / Upper Wall Color & Height ---
			color colCeil;
			double hCeil = 0.0;
			if (CB("gitd_ceil_enabled", true))
			{
				if (CI("gitd_ceil_mode", 0) == 4) // Rainbow Cycle
				{
					double h = (level.maptime * CF("gitd_ceil_speed", 1.0) * 4.0);
					h -= 360.0 * floor(h / 360.0);
					double r, g, b;
					[r, g, b] = HF_HSV2RGB(h, 0.95, 0.95);
					colCeil = Color(255, int(r * 255.0 * ceilInten), int(g * 255.0 * ceilInten), int(b * 255.0 * ceilInten));
				}
				else if (CI("gitd_ceil_mode", 0) == 5) // Cycle
				{
					double h, s, v;
					if (CI("gitd_floor_mode", 0) == 5)
					{
						[h, s, v] = HF_RGB2HSV(fR / 255.0, fG / 255.0, fB / 255.0);
						double shift = (level.maptime * CF("gitd_floor_speed", 1.0) * 4.0);
						h += shift + 180.0; // Perfect complementary offset
					}
					else
					{
						[h, s, v] = HF_RGB2HSV(cR / 255.0, cG / 255.0, cB / 255.0);
						double shift = (level.maptime * CF("gitd_ceil_speed", 1.0) * 4.0);
						h += shift;
					}
					h -= 360.0 * floor(h / 360.0);
					double r, g, b;
					[r, g, b] = HF_HSV2RGB(h, s, v);
					colCeil = Color(255, int(r * 255.0 * ceilInten), int(g * 255.0 * ceilInten), int(b * 255.0 * ceilInten));
				}
				else if (randomize)
				{
					colCeil = HF_RandSectorColor(i, 1, epoch, ceilInten, tsec);
				}
				else
				{
					colCeil = Color(255, int(clamp(cR * ceilInten, 0, 255)), int(clamp(cG * ceilInten, 0, 255)), int(clamp(cB * ceilInten, 0, 255)));
				}
				hCeil = CF("gitd_ceil_height", 64.0);
			}
			else if (CB("gitd_wall_enabled", true))
			{
				// Fallback to Wall color so upper walls still glow
				if (CI("gitd_wall_mode", 0) == 4) // Rainbow Cycle
				{
					double h = (level.maptime * CF("gitd_wall_speed", 1.0) * 4.0);
					h -= 360.0 * floor(h / 360.0);
					double r, g, b;
					[r, g, b] = HF_HSV2RGB(h, 0.95, 0.95);
					colCeil = Color(255, int(r * 255.0 * wallInten), int(g * 255.0 * wallInten), int(b * 255.0 * wallInten));
				}
				else if (CI("gitd_wall_mode", 0) == 5) // Cycle
				{
					double h, s, v;
					if (CI("gitd_floor_mode", 0) == 5)
					{
						[h, s, v] = HF_RGB2HSV(fR / 255.0, fG / 255.0, fB / 255.0);
						double shift = (level.maptime * CF("gitd_floor_speed", 1.0) * 4.0);
						h += shift + 180.0;
					}
					else
					{
						[h, s, v] = HF_RGB2HSV(wR / 255.0, wG / 255.0, wB / 255.0);
						double shift = (level.maptime * CF("gitd_wall_speed", 1.0) * 4.0);
						h += shift;
					}
					h -= 360.0 * floor(h / 360.0);
					double r, g, b;
					[r, g, b] = HF_HSV2RGB(h, s, v);
					colCeil = Color(255, int(r * 255.0 * wallInten), int(g * 255.0 * wallInten), int(b * 255.0 * wallInten));
				}
				else
				{
					colCeil = Color(255, int(clamp(wR * wallInten, 0, 255)), int(clamp(wG * wallInten, 0, 255)), int(clamp(wB * wallInten, 0, 255)));
				}
				hCeil = CF("gitd_wall_height", 64.0);
			}

			finalFloorColors[i] = colFloor;
			finalCeilColors[i]  = colCeil;
			finalFloorHeights[i] = hFloor;
			finalCeilHeights[i]  = hCeil;
		}

		// --- Sector Color Blending (Fluid Bleed) ---
		if (CB("gitd_blend_enabled", false))
		{
			double blendRate = CF("gitd_blend_rate", 0.15);
			blendRate = clamp(blendRate, 0.0, 1.0);

			Array<color> blendedFloor;
			Array<color> blendedCeil;
			blendedFloor.Resize(level.Sectors.Size());
			blendedCeil.Resize(level.Sectors.Size());

			for (int i = 0; i < level.Sectors.Size(); i++)
			{
				Sector s = level.Sectors[i];
				if (!s) continue;

				color cF = finalFloorColors[i];
				color cC = finalCeilColors[i];

				double sumFR = cF.r, sumFG = cF.g, sumFB = cF.b;
				double sumCR = cC.r, sumCG = cC.g, sumCB = cC.b;
				int neighborCount = 1;

				for (int li = 0; li < s.lines.Size(); ++li)
				{
					Line ln = s.lines[li];
					if (!ln) continue;
					Sector other = (ln.frontsector == s) ? ln.backsector : ln.frontsector;
					if (!other || other == s) continue;

					int otherIdx = other.Index();
					color oF = finalFloorColors[otherIdx];
					color oC = finalCeilColors[otherIdx];

					sumFR += oF.r; sumFG += oF.g; sumFB += oF.b;
					sumCR += oC.r; sumCG += oC.g; sumCB += oC.b;
					neighborCount++;
				}

				double avgFR = sumFR / neighborCount;
				double avgFG = sumFG / neighborCount;
				double avgFB = sumFB / neighborCount;

				double avgCR = sumCR / neighborCount;
				double avgCG = sumCG / neighborCount;
				double avgCB = sumCB / neighborCount;

				int blendFR = int(HF_Lerp(cF.r, avgFR, blendRate));
				int blendFG = int(HF_Lerp(cF.g, avgFG, blendRate));
				int blendFB = int(HF_Lerp(cF.b, avgFB, blendRate));

				int blendCR = int(HF_Lerp(cC.r, avgCR, blendRate));
				int blendCG = int(HF_Lerp(cC.g, avgCG, blendRate));
				int blendCB = int(HF_Lerp(cC.b, avgCB, blendRate));

				blendedFloor[i] = Color(255, blendFR, blendFG, blendFB);
				blendedCeil[i]  = Color(255, blendCR, blendCG, blendCB);
			}

			for (int i = 0; i < level.Sectors.Size(); i++)
			{
				finalFloorColors[i] = blendedFloor[i];
				finalCeilColors[i]  = blendedCeil[i];
			}
		}

		// --- Apply final computed colors & heights to the engine ---
		for (int i = 0; i < level.Sectors.Size(); i++)
		{
			Sector s = level.Sectors[i];
			if (!s) continue;

			s.SetGlowHeight(Sector.floor, 0);
			s.SetGlowHeight(Sector.ceiling, 0);

			if (finalFloorHeights[i] > 0.0)
			{
				s.SetGlowColor(Sector.floor, finalFloorColors[i]);
				s.SetGlowHeight(Sector.floor, finalFloorHeights[i]);
			}
			if (finalCeilHeights[i] > 0.0)
			{
				s.SetGlowColor(Sector.ceiling, finalCeilColors[i]);
				s.SetGlowHeight(Sector.ceiling, finalCeilHeights[i]);
			}
		}
	}

	// Detect a liquid floor and return its characteristic glow color.
	// Uses the floor flat's name (nukage/lava/water/blood/slime keywords).
	// Instance wrapper around the static detector (callable from this handler).
	bool, color LiquidColorFor(Sector s)
	{
		bool isLiq;
		color c;
		[isLiq, c] = HF_LiquidColorOf(s);
		return isLiq, c;
	}

	// Static version so other actors (the impact ripple) can detect liquids too.
	// Returns (isLiquid, glowColor); matches the floor flat name against keywords.
	static bool, color HF_LiquidColorOf(Sector s)
	{
		if (!s) return false, Color(255, 0, 0, 0);
		TextureID ftex = s.GetTexture(Sector.floor);
		String tn = TexMan.GetName(ftex);
		tn = tn.MakeLower();                              // case-insensitive keyword match
		// nukage / slime / sludge / mud -> green
		if (tn.IndexOf("nuke") >= 0 || tn.IndexOf("slime") >= 0 || tn.IndexOf("sludg") >= 0
			|| tn.IndexOf("mud") >= 0 || tn.IndexOf("ooze") >= 0)
			return true, Color(255, 60, 220, 40);
		// lava / fire -> orange-red
		if (tn.IndexOf("lava") >= 0 || tn.IndexOf("fire") >= 0)
			return true, Color(255, 255, 90, 20);
		// blood / gore -> deep red
		if (tn.IndexOf("blood") >= 0 || tn.IndexOf("gore") >= 0)
			return true, Color(255, 200, 20, 20);
		// water -> blue
		if (tn.IndexOf("water") >= 0 || tn.IndexOf("fwater") >= 0)
			return true, Color(255, 40, 120, 255);
		return false, Color(255, 0, 0, 0);               // not a recognized liquid
	}

	// Zero out all sector glow heights (turns the effect fully off). Color is
	// left as-is since a 0 height makes the glow invisible regardless.
	void ClearGlow()
	{
		for (int i = 0; i < level.Sectors.Size(); i++)
		{
			Sector s = level.Sectors[i];
			if (!s) continue;
			s.SetGlowHeight(Sector.floor, 0);
			s.SetGlowHeight(Sector.ceiling, 0);
		}
	}

	// --- Streak HUD timer (prototype for the larger combo HUD) -------------
	// A small, x/y-positionable, scalable readout of seconds left before the
	// streak decays and the floor starts cooling.
	// UI scope: reads ONLY cached fields (no cvars/play state) and draws the readout.
	override void RenderOverlay(RenderEvent e)
	{
		// read ONLY cached fields here (set in WorldTick) -- no cvar/play calls
		if (!hudOn) return;
		if (ksKills <= 0) return;            // nothing to show when no streak

		double sw = Screen.GetWidth();
		double sh = Screen.GetHeight();

		double scale = hudScale;
		if (scale < 0.5) scale = 0.5;        // floor the scale so text never vanishes
		double fx = hudX;
		double fy = hudY;

		Font fnt = Font.GetFont("BIGFONT");
		if (!fnt) fnt = smallfont;           // fallback if BIGFONT is unavailable

		// seconds remaining before the next kill decays off the streak
		double secs = ksTimer / 35.0;        // 35 tics per second
		String txt = String.Format("STREAK x%d  %.1fs", ksKills, secs);

		// color shifts white -> hot red as the streak heats up
		int rcol = Font.CR_WHITE;
		if (ksHeat > 0.66)      rcol = Font.CR_RED;
		else if (ksHeat > 0.33) rcol = Font.CR_ORANGE;
		else                    rcol = Font.CR_YELLOW;

		// Scale via a smaller virtual canvas: 2x scale = half-size canvas, so
		// BIGFONT draws twice as large.
		double vw = sw / scale;
		double vh = sh / scale;
		double vx = fx * vw;                 // fractional x/y -> virtual-canvas pixels
		double vy = fy * vh;

		// Center the text on (vx,vy) by subtracting half its measured size.
		double tw = fnt.StringWidth(txt);
		double th = fnt.GetHeight();
		Screen.DrawText(fnt, rcol, vx - tw * 0.5, vy - th * 0.5, txt,
			DTA_VirtualWidthF, vw, DTA_VirtualHeightF, vh, DTA_KeepRatio, true);
	}
}


// ============================================================================
// HF_ImpactRipple -- a circular light pulse on the wall at a bullet impact.
// Radiates outward to a max radius then collapses back in, then dies.
//
// Built on A_AttachLight (the engine's explicit runtime-light API): each tic we
// re-attach a light of the same id at a new radius. Re-calling A_AttachLight
// with the same id replaces the prior light, so the radius animates reliably.
// Toggled by hf_glow_impact; tuned by hf_glow_impact_radius / _time / color.
// ============================================================================
class HF_ImpactRipple : Actor   // Transient per-impact light pulse spawned at projectile hits.
{
	int    ripLife;    // total tics of life
	int    ripAge;     // tics elapsed (our own counter)
	double ripMax;     // peak radius

	Default
	{
		// Invisible, inert marker actor: it exists only to host the animated light.
		+NOBLOCKMAP
		+NOGRAVITY
		+NOINTERACTION
		+INVISIBLE
		Radius 1;
		Height 1;
	}

	// Read tuning cvars, clamp lifetime, then jump into the ripple animation.
	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		ripMax  = HF_RippleCVarF("hf_glow_impact_radius", 96.0);
		ripLife = int(HF_RippleCVarF("hf_glow_impact_time", 18.0));
		if (ripLife < 2) ripLife = 2;        // need >=2 tics so t-step math is meaningful
		ripAge = 0;
		SetStateLabel("Ripple");
	}

	States
	{
	// Ripple: one-tic loop that re-attaches the light at an animated radius,
	// optionally flashing the hit sector's floor/ceiling glow, until life ends.
	Ripple:
		TNT1 A 1
		{
			// advance one tic; compute the light radius via the chosen SHAPE.
			ripAge++;
			double t = double(ripAge) / double(ripLife);   // normalized 0..1 progress
			if (t >= 1.0) { A_RemoveLight("hf_ripple"); return ResolveState("Done"); }   // life over: drop light, finish

			// SHAPE MODES (hf_glow_impact_shape):
			//   0 Pulse    -- grow then collapse (sin)         [default]
			//   1 Flash    -- instant on, fade out
			//   2 Expand   -- grow out and hold to the end
			//   3 Throb    -- two quick pulses
			//   4 Implode  -- start big, collapse inward
			int shapeMode = HF_RippleCVarI("hf_glow_impact_shape", 0);
			double shape;
			if (shapeMode == 1)      shape = 1.0 - t;                 // flash + fade
			else if (shapeMode == 2) shape = t;                      // expand + hold
			else if (shapeMode == 3) shape = abs(sin(t * 360.0));    // throb (2 pulses)
			else if (shapeMode == 4) shape = 1.0 - t;                // implode (radius shrinks)
			else                     shape = sin(t * 180.0);         // pulse (default): 0->1->0 over the life

			int rad = int(ripMax * shape);    // shape (0..1) drives the current light radius
			Color col = Color(255,
				HF_RippleCVarI("hf_glow_impact_r", 80),
				HF_RippleCVarI("hf_glow_impact_g", 160),
				HF_RippleCVarI("hf_glow_impact_b", 255));
			// Re-attach same-id light each tic to animate radius; type 2 = additive/pulse light.
			A_AttachLight("hf_ripple", 0, col, rad, 0, 2);

			// Optional: flash the floor/ceiling glow at the hit sector.
			if (HF_RippleCVarI("hf_glow_impact_planes", 0) != 0 && CurSector)
			{
				double pInten = shape;        // tie the plane-glow brightness to the ripple shape
				int pr = int(HF_RippleCVarI("hf_glow_impact_r", 80)  * pInten);
				int pg = int(HF_RippleCVarI("hf_glow_impact_g", 160) * pInten);
				int pb = int(HF_RippleCVarI("hf_glow_impact_b", 255) * pInten);
				Color pcol = Color(255, pr, pg, pb);

				// LIQUID REACTION: if the hit floor is a liquid (water/lava/blood/
				// nukage/mud...) and the option is on, the floor-hit glow takes the
				// liquid's color instead -- a hit in water glows blue, lava orange.
				int target = HF_RippleCVarI("hf_glow_impact_planes", 0); // 1 floor,2 ceil,3 both
				bool floorIsLiquid = false;
				Color lcol;
				if ((target == 1 || target == 3) && HF_RippleCVarI("hf_glow_impact_liquid", 1) != 0)
				{
					// Reuse the handler's static liquid detector for consistency.
					[floorIsLiquid, lcol] = HF_GlowHandler.HF_LiquidColorOf(CurSector);
				}

				if (target == 1 || target == 3)
				{
					Color fcol = pcol;
					if (floorIsLiquid)
					{
						// scale the liquid color by the pulse intensity so it still throbs
						fcol = Color(255, int(lcol.r * pInten), int(lcol.g * pInten), int(lcol.b * pInten));
					}
					CurSector.SetGlowColor(Sector.floor, fcol);
					CurSector.SetGlowHeight(Sector.floor, ripMax * 0.5);   // height tied to peak radius
				}
				if (target == 2 || target == 3)
				{
					CurSector.SetGlowColor(Sector.ceiling, pcol);
					CurSector.SetGlowHeight(Sector.ceiling, ripMax * 0.5);
				}
			}
			return ResolveState(null);        // stay in this state (Loop) for the next tic
		}
		Loop;
	// Done: clean up any temporary sector glow we set, then despawn.
	Done:
		TNT1 A 1
		{
			// clear any temporary floor/ceiling impact glow we set
			if (HF_RippleCVarI("hf_glow_impact_planes", 0) != 0 && CurSector)
			{
				int target = HF_RippleCVarI("hf_glow_impact_planes", 0);
				if (target == 1 || target == 3) CurSector.SetGlowHeight(Sector.floor, 0);
				if (target == 2 || target == 3) CurSector.SetGlowHeight(Sector.ceiling, 0);
			}
		}
		Stop;
	}

	// Null-safe cvar readers local to the ripple actor (mirror the handler's CI/CF).
	static int HF_RippleCVarI(String n, int def) { CVar c = CVar.FindCVar(n); return c ? c.GetInt()   : def; }
	static double HF_RippleCVarF(String n, double def) { CVar c = CVar.FindCVar(n); return c ? c.GetFloat() : def; }
}

class GITD_ScannedMarker : Inventory
{
	color scannedColor;
	Default
	{
		Inventory.MaxAmount 1;
		+Inventory.UNDROPPABLE
		+Inventory.UNTOSSABLE
	}
}

