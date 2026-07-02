// ============================================================================
//  GITD_ComboMeter -- a cumulative DAMAGE counter drawn with the SHADER digits
//  (wipeType 13: the SAME engine glow-number the floor kill counter uses), riding
//  each monster. Keep damaging it -> the number CLIMBS; stop too long -> the chain
//  breaks, the number fades, and the PEAK is banked into the score system.
//
//  This is the GITD glow SHADER, not sprites. It draws on the floor beneath the
//  monster, tracking it. It runs in TANDEM with HF_DamNum (the per-hit pops) --
//  two separate systems, on purpose. VR-safe (flat surface glow like every GITD FX).
//
//  Score tie-in: on bank it fires the `hf_combo_bank` netevent (player, points,
//  peak). HF's score brain (HF_ScoreHandler) receives it and awards the points --
//  decoupled, so GITD never hard-depends on HF being loaded.
//
//  Cvars: gitd_combo_enabled, gitd_combo_target (0 all / 1 champions / 2 bosses),
//         gitd_combo_fade (chain-break window, tics), gitd_combo_radius,
//         gitd_combo_scoremul, gitd_combo_color (0 cyan / 1 gold / 2 red / 3 green).
// ============================================================================

class GITD_ComboTag : Actor
{
	int total;      // cumulative damage this chain
	int peak;       // highest the chain reached (what we bank)
	int chain;      // tics since the last hit (breaks at gitd_combo_fade)
	int age;        // for the open animation
	int owner;      // player number that built this chain (for scoring)
	bool banked;
	Vector3 burstAt;   // last-known spot above the monster's head, where the score burst spawns

	Default { +NOINTERACTION +NOGRAVITY +NOBLOCKMAP +DONTSPLASH +NOTONAUTOMAP; RenderStyle "None"; }
	States { Spawn: TNT1 A 1; Loop; }

	static int    CInt(string n, int d)    { CVar c = CVar.FindCVar(n); return c ? c.GetInt()   : d; }
	static double CFlt(string n, double d) { CVar c = CVar.FindCVar(n); return c ? c.GetFloat() : d; }

	void AddDamage(int dmg, int pn)
	{
		if (dmg <= 0) return;
		total += dmg;
		if (total > peak) peak = total;
		chain = 0;          // refresh the chain
		owner = pn;
	}

	override void Tick()
	{
		Super.Tick();
		age++;
		Actor mon = master;
		if (!mon || mon.health <= 0) { Bank(); return; }     // monster gone -> bank the chain

		int fadeAfter = max(5, CInt("gitd_damage_numbers_window", 15));
		chain++;
		if (chain > fadeAfter) { Bank(); return; }            // chain broke -> bank

		burstAt = (mon.pos.x, mon.pos.y, mon.pos.z + mon.height + 30.0);   // where the score burst will appear

		// draw the running total with the shader, on a PANEL floating above the monster's
		// head, FACING the player (the in-air glow-billboard, not the floor disc).
		int shown = clamp(total, 0, 99999);
		int cidx  = clamp(CInt("gitd_combo_color", 1), 0, 3);   // default gold

		// neon colour per cidx (cyan / gold / red / green)
		int br, bg, bb;
		CVar cc = CVar.FindCVar("gitd_damage_numbers_color");
		if (cc)
		{
			Color c = cc.GetColor();
			br = c.r; bg = c.g; bb = c.b;
		}
		else if (cidx == 0) { br =  60; bg = 210; bb = 255; }   // cyan
		else if (cidx == 1) { br = 255; bg = 196; bb =  60; }   // gold
		else if (cidx == 2) { br = 255; bg =  60; bb =  60; }   // red
		else                { br =  70; bg = 255; bb = 110; }   // green

		double prog = (age < 10) ? double(age) / 10.0 : 1.0;    // panel pops in
		// dim as the chain ages toward breaking -- a visible "hurry, it's slipping" cue
		double heat = 1.0 - clamp(double(chain) / double(fadeAfter), 0.0, 1.0) * 0.55;
		double bright = clamp(prog * heat, 0.20, 1.0);
		Color col = Color(255, int(br * bright), int(bg * bright), int(bb * bright));

		double rad   = 22.0;                                    // panel half-size
		double headZ = mon.pos.z + mon.height + 16.0;          // float just above the head

		int style = CInt("gitd_combo_style", 0);
		if (style == 0 || style == 2)
		{
			level.AddGlowPanel(col, rad, mon.pos.x, mon.pos.y, headZ, 6313,
				1.0, 0.0, 0.0, shown);                             // wipeType 6313 = digit panel, font index 63 (pacfont); counter = the number
		}
		if (style == 1 || style == 2)
		{
			int packn = shown + cidx * 131072;
			Color floorCol = Color(255, (packn >> 16) & 255, (packn >> 8) & 255, packn & 255);
			double floorRad = CFlt("gitd_combo_radius", 56.0);
			level.AddGlowSpotWiped(floorCol, floorRad, mon.pos.x, mon.pos.y, 13, prog, 1.0, 0.0, 1);
		}
	}

	void Bank()
	{
		if (!banked && peak > 0)
		{
			banked = true;
			double mul = CFlt("gitd_combo_scoremul", 1.0);
			int pts = int(peak * mul);
			if (pts > 0)
				EventHandler.SendNetworkEvent("hf_combo_bank", owner, pts, peak);

			// fire the kill-reward score display at the spot the chain ended
			Vector3 sp = (burstAt.x == 0 && burstAt.y == 0 && burstAt.z == 0) ? pos : burstAt;
			GITD_ScoreBurst b = GITD_ScoreBurst(Actor.Spawn("GITD_ScoreBurst", sp));
			if (b) { b.score = peak; b.owner = owner; b.maxlife = 90; }
		}
		Destroy();
	}
}

class GITD_ComboHandler : EventHandler
{
	static int CInt(string n, int d) { CVar c = CVar.FindCVar(n); return c ? c.GetInt() : d; }

	override void WorldThingDamaged(WorldEvent e)
	{
		Actor mon = e.Thing;
		if (!mon || !mon.bIsMonster || mon.health <= 0 || e.Damage <= 0) return;

		int pn = PlayerFrom(e);
		if (pn < 0) return;

		int mode = CInt("gitd_damage_numbers_mode", 0);
		if (mode == 1) // Per-Shot Numbers
		{
			GITD_DamPop.Fire(mon.pos + (0, 0, mon.height * 0.6), e.Damage);
		}
		else if (mode == 2) // Cumulative Tracking
		{
			GITD_ComboTag tag = FindTag(mon);
			if (!tag)
			{
				tag = GITD_ComboTag(Actor.Spawn("GITD_ComboTag", mon.pos));
				if (tag) 
				{
					tag.master = mon;
					tag.burstAt = (mon.pos.x, mon.pos.y, mon.pos.z + mon.height + 30.0);
				}
			}
			if (tag) tag.AddDamage(e.Damage, pn);
		}

		// Keep the old combo logic running for scoring if enabled, but independent of popups
		if (CInt("gitd_combo_enabled", 1) && mode != 2)
		{
			GITD_ComboTag tag = FindTag(mon);
			if (!tag && PassesFilter(mon))
			{
				tag = GITD_ComboTag(Actor.Spawn("GITD_ComboTag", mon.pos));
				if (tag) 
				{
					tag.master = mon;
					tag.burstAt = (mon.pos.x, mon.pos.y, mon.pos.z + mon.height + 30.0);
				}
			}
			if (tag) tag.AddDamage(e.Damage, pn);
		}
	}

	int PlayerFrom(WorldEvent e)
	{
		Actor s = e.DamageSource;
		if (s && s.player) return s.PlayerNumber();
		if (e.Inflictor && e.Inflictor.target && e.Inflictor.target.player)
			return e.Inflictor.target.PlayerNumber();
		return -1;
	}

	bool PassesFilter(Actor mon)
	{
		int f = CInt("gitd_combo_target", 0);     // 0 all, 1 champions, 2 bosses
		if (f <= 0) return true;
		if (f == 2) return mon.bBoss;
		// champions: HF tags them elsewhere; until that's wired, treat bosses as the
		// "elite" set so the filter does SOMETHING useful in the meantime.
		return mon.bBoss;
	}

	GITD_ComboTag FindTag(Actor mon)
	{
		ThinkerIterator it = ThinkerIterator.Create("GITD_ComboTag");
		GITD_ComboTag t;
		while (t = GITD_ComboTag(it.Next()))
			if (t.master == mon) return t;
		return null;
	}
}
