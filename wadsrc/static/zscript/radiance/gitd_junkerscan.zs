// ============================================================================
//  GITD_JunkerScan -- THE JUNKER SCAN ORCHESTRATOR.
//
//  HackFraud's signature "hack-in-progress" overlay: a diagnostic scan that
//  ASSEMBLES out of the in-air neon-panel primitives around a center point,
//  every panel FACING the player. It is a HACK -- so it BOOTS like one:
//
//     UNAUTHORIZED ACCESS  ->  SYNC (scrolling)  ->  ACCESS GRANTED
//
//  over ~2-3 seconds, the SKULL centerpiece MATERIALIZES wireframe->solid
//  (its wipeProgress sweep crawls top->bottom), then the framing brackets snap
//  in, the radar rings settle, the waveform strip lights, the bars + gauge fill,
//  the spectrum block animates, and the numeric readout COLUMNS spin up.
//
//  EVERY visible element is an AddGlowPanel air-panel (the proven single-frame
//  primitive: re-emitted EVERY tick or it vanishes). Shapes used:
//     13  numeric digit panel (font-atlas glyphs; the readout columns + status code)
//     14  shockwave ring  (reused as the nested radar RINGS)
//     18  corner BRACKETS (target reticle frame)
//     19  WAVEFORM / oscilloscope strip
//     21  segmented BAR / GAUGE (vertical fill)
//     22  SPECTRUM / heatmap strip
//     23  SKULL sampler (wireframe->solid materialize -- the centerpiece)
//
//  DEMO: on WorldLoaded, GITD_JunkerScanHandler spawns ONE scan ~96u in front of
//  player 1 at eye height, facing them, and re-triggers the boot every few
//  seconds so the user SEES it loop on boot in VR. Gated on gitd_junker_demo
//  (default ON). Nothing here touches scoring -- presentation only.
//
//  ---- STRINGS DEPENDENCY (read me) ----------------------------------------
//  The shader font path renders ONE NUMBER per panel (digits 0-9 unpacked from
//  the panel's `counter` lane via pnum). There is NO multi-letter / arbitrary
//  text path yet -- the atlas glyph cells exist, but no shader branch packs a
//  STRING across a panel. So the status WORDS ("UNAUTHORIZED ACCESS" / "SYNC" /
//  "ACCESS GRANTED") cannot be drawn as letters today. Until a string-panel
//  shader branch lands, the boot status is shown as a NUMERIC STATUS CODE in a
//  dedicated readout (401 UNAUTHORIZED -> rolling SYNC digits -> 200 GRANTED),
//  matching the HTTP-status read of the hack. The skull + all shapes + numeric
//  columns still drive fully, so the boot choreography is visibly complete.
//  When strings land, swap GITD_JunkerScan.mStatusCode for a string emit.
// ============================================================================

// ----------------------------------------------------------------------------
//  GITD_JunkerScan -- the scan thinker. A play-scope Actor that lives for one
//  full boot cycle, advancing mTick each frame and RE-EMITTING the whole panel
//  assembly (single-frame primitives) around mCenter, all camera-facing.
//
//  Choreography (tics @ 35hz; ~2.6s total at defaults):
//     PHASE 0  BOOT   [0 .. mSkullTics)      skull materializes wireframe->solid;
//                                            status = 401 UNAUTHORIZED; brackets
//                                            snap in over the first ~10 tics.
//     PHASE 1  SYNC   [mSkullTics .. +SYNC)  skull solid; rings + waveform +
//                                            spectrum animate; readout columns
//                                            SCROLL (rolling digits) = "syncing".
//     PHASE 2  GRANTED[.. mLifeTics)         status = 200 GRANTED; bars + gauge
//                                            fill to their target; readouts lock
//                                            to their final vitals/threat/score.
//  Then the handler re-fires after a gap so it loops on boot.
// ----------------------------------------------------------------------------
class GITD_JunkerScan : Actor
{
	int     mTick;        // tics alive
	Vector3 mCenter;      // scan center in world space (panels arrange around this)
	int     mSkullTics;   // tics for the skull wireframe->solid sweep (PHASE 0)
	int     mSyncTics;    // tics the SYNC phase runs
	int     mLifeTics;    // total tics before the scan self-destructs

	// final readout values (placeholders -- the user/HF brain feeds real vitals later)
	int     mVitals;      // e.g. health/integrity readout
	int     mThreat;      // e.g. threat index
	int     mScoreRead;   // e.g. score/bounty readout

	Default { +NOINTERACTION +NOGRAVITY +NOBLOCKMAP +DONTSPLASH +NOTONAUTOMAP; RenderStyle "None"; }
	States { Spawn: TNT1 A 1; Loop; }

	// ---- null-safe cvar helpers (pattern: gitd_combo.zs) ----
	static bool   CBool(string n, bool d)  { CVar c = CVar.FindCVar(n); return c ? c.GetBool()  : d; }
	static int    CInt (string n, int d)   { CVar c = CVar.FindCVar(n); return c ? c.GetInt()   : d; }
	static double CFlt (string n, double d){ CVar c = CVar.FindCVar(n); return c ? c.GetFloat() : d; }

	// ZScript has NO smoothstep -- hand-roll the cubic ease. t clamped 0..1.
	static double SStep(double t)
	{
		t = clamp(t, 0.0, 1.0);
		return t * t * (3.0 - 2.0 * t);
	}

	// ------------------------------------------------------------------
	//  Spawn one scan centered at `center`. Pulls timing from cvars so the
	//  user can dial the boot length in VR without touching code.
	// ------------------------------------------------------------------
	static GITD_JunkerScan Make(Vector3 center, int vitals, int threat, int scoreRead)
	{
		let s = GITD_JunkerScan(Actor.Spawn("GITD_JunkerScan", center));
		if (!s) return null;
		s.mCenter    = center;
		s.mTick      = 0;
		s.mSkullTics = max(8,  int(CFlt("gitd_junker_skulltime", 28.0)));   // wireframe->solid sweep
		s.mSyncTics  = max(8,  CInt("gitd_junker_synctime", 30));           // SYNC scroll window
		int linger   = max(8,  CInt("gitd_junker_grantedtime", 35));        // GRANTED hold window
		s.mLifeTics  = s.mSkullTics + s.mSyncTics + linger;
		s.mVitals    = clamp(vitals,    0, 99999);
		s.mThreat    = clamp(threat,    0, 99999);
		s.mScoreRead = clamp(scoreRead, 0, 99999);
		return s;
	}

	override void Tick()
	{
		Super.Tick();
		mTick++;
		if (mTick > mLifeTics) { Destroy(); return; }

		// global master gate -- if the whole junker scan is disabled, draw nothing.
		if (!CBool("gitd_junker_enabled", true)) return;

		// phase boundaries
		int p0End = mSkullTics;                 // end of BOOT/materialize
		int p1End = mSkullTics + mSyncTics;      // end of SYNC

		// 0=BOOT, 1=SYNC, 2=GRANTED
		int phase = (mTick < p0End) ? 0 : (mTick < p1End) ? 1 : 2;

		// neon timer is a smooth seconds-ish value the shader already reads; we only
		// need world position + lanes here. All panels are camera-facing (dir 0,0).
		Vector3 c = mCenter;

		// ============================ SKULL (centerpiece) ============================
		// wipeProgress = the materialize sweep 0..1 across PHASE 0, then held at 1.
		double skullSweep;
		if (phase == 0) skullSweep = SStep(double(mTick) / double(max(1, mSkullTics)));
		else            skullSweep = 1.0;
		// shape 23, font irrelevant (fixed UV) -> raw 23; counter unused (0).
		Color skullCol = Color(255, 60, 200, 255);   // neon cyan-violet skull
		level.AddGlowPanel(skullCol, CFlt("gitd_junker_skullradius", 30.0),
			c.x, c.y, c.z, 23, skullSweep, 0.0, 0.0, 0);

		// ============================ CORNER BRACKETS (frame) ========================
		// snap in over the first ~10 tics, then hold. Brightness rides wipeProgress.
		double brBright = SStep(clamp(double(mTick) / 10.0, 0.0, 1.0));
		Color brCol = Color(255, 60, 255, 120);       // green-cyan reticle
		// brackets frame the WHOLE scan -> larger than the skull.
		level.AddGlowPanel(brCol, 56.0, c.x, c.y, c.z, 18, brBright, 0.0, 0.0, 0);

		// ============================ NESTED RADAR RINGS ============================
		// shape 14 = shockwave ring; wipeProgress drives the contour radius 0..1.
		// Two nested rings sweeping on a loop = a radar pulse around the subject.
		if (phase >= 0)
		{
			double rA = double((mTick) % 26) / 26.0;          // outer sweep
			double rB = double((mTick + 13) % 26) / 26.0;     // inner sweep (phase-offset)
			Color ringCol = Color(255, 60, 220, 255);
			level.AddGlowPanel(ringCol, 50.0, c.x, c.y, c.z, 14, rA, 0.0, 0.0, 0);
			level.AddGlowPanel(ringCol, 34.0, c.x, c.y, c.z, 14, rB, 0.0, 0.0, 0);
		}

		// ============================ WAVEFORM STRIP ============================
		// shape 19; counter = amplitude seed. Lights from SYNC on; dim during BOOT.
		double wfBright = (phase == 0) ? 0.35 : 1.0;
		Color wfCol = Color(255, 70, 255, 180);
		// hung BELOW the skull, offset down in Z.
		level.AddGlowPanel(wfCol, 26.0, c.x, c.y, c.z - 42.0, 19, wfBright, 0.0, 0.0, 7);

		// ============================ SPECTRUM BLOCK ============================
		// shape 22; counter = level seed. Animates continuously once booted.
		double spBright = (phase == 0) ? 0.25 : 1.0;
		Color spCol = Color(255, 255, 120, 60);       // warm spectrum
		// hung ABOVE the skull.
		level.AddGlowPanel(spCol, 24.0, c.x, c.y, c.z + 44.0, 22, spBright, 0.0, 0.0, 3);

		// ============================ SEGMENTED BARS + VERTICAL GAUGE ============
		// shape 21; counter = fill 0..100. During BOOT/SYNC they're empty/low; in
		// GRANTED they ramp to their target fill (eased). Two bars (left) + one
		// vertical gauge (right) reading vitals/threat.
		double fillEase;
		if      (phase < 2) fillEase = 0.0;
		else                fillEase = SStep(clamp(double(mTick - p1End) / 14.0, 0.0, 1.0));
		Color barCol = Color(255, 80, 255, 140);      // green vitals bar
		Color gaugeCol = Color(255, 255, 90, 70);     // amber threat gauge

		int vitalsFill = int(fillEase * clamp(double(mVitals) / 100.0, 0.0, 1.0) * 100.0);
		int threatFill = int(fillEase * clamp(double(mThreat) / 100.0, 0.0, 1.0) * 100.0);
		// left bar (vitals), to the LEFT of the skull
		level.AddGlowPanel(barCol, 20.0, c.x, c.y, c.z, 21, 1.0, 0.0, 0.0, vitalsFill);
		// NOTE: shape 21 panels share the same world point -> to SEPARATE them in
		// screen space they need distinct positions. Camera-facing panels can't be
		// pushed left/right in world XY without knowing the view right-vector, so we
		// stagger them in Z (vertical), which IS view-independent.
		// vertical GAUGE (threat), placed lower-left.
		level.AddGlowPanel(gaugeCol, 18.0, c.x, c.y, c.z - 20.0, 21, 1.0, 0.0, 0.0, threatFill);

		// ============================ NUMBER READOUT COLUMNS ============================
		// shape 13 numeric panels via the font atlas. During SYNC the columns SCROLL
		// (rolling digits) to read as "syncing"; in GRANTED they lock to final values.
		// font index packs in wipeType hundreds digit: wipeType = 13 + font*100.
		int FONT_READOUT = 27;   // digital808 LED look (matches the HUD ammo readout)

		// --- STATUS CODE readout (stands in for the status WORDS; see header note) ---
		//   PHASE 0 BOOT  -> 401  (UNAUTHORIZED)
		//   PHASE 1 SYNC  -> rolling 3-digit churn (the handshake)
		//   PHASE 2 GRANT -> 200  (ACCESS GRANTED)
		int statusCode;
		if      (phase == 0) statusCode = 401;
		else if (phase == 1) statusCode = (mTick * 137) % 1000;   // churning sync digits
		else                 statusCode = 200;
		Color stCol = (phase == 2) ? Color(255, 80, 255, 120)     // green = granted
		            : (phase == 1) ? Color(255, 255, 220, 60)      // amber = syncing
		                           : Color(255, 255, 70, 60);      // red = unauthorized
		// status readout sits at the TOP of the stack.
		level.AddGlowPanel(stCol, 14.0, c.x, c.y, c.z + 64.0, 13 + FONT_READOUT * 100,
			1.0, 0.0, 0.0, statusCode);

		// --- VITALS / THREAT / SCORE columns (lower stack). Scroll during SYNC. ---
		int vRead, tRead, sRead;
		if (phase == 2)
		{
			vRead = mVitals; tRead = mThreat; sRead = mScoreRead;
		}
		else
		{
			// rolling churn so the columns read as "populating"
			vRead = (mTick * 73)  % 1000;
			tRead = (mTick * 191) % 100;
			sRead = (mTick * 521) % 100000;
		}
		Color colVit = Color(255, 80, 255, 120);
		Color colThr = Color(255, 255, 120, 60);
		Color colScr = Color(255, 255, 200, 70);
		// stagger the three columns vertically (view-independent separation).
		level.AddGlowPanel(colVit, 12.0, c.x, c.y, c.z - 60.0, 13 + FONT_READOUT * 100, 1.0, 0.0, 0.0, vRead);
		level.AddGlowPanel(colThr, 12.0, c.x, c.y, c.z - 74.0, 13 + FONT_READOUT * 100, 1.0, 0.0, 0.0, tRead);
		level.AddGlowPanel(colScr, 12.0, c.x, c.y, c.z - 88.0, 13 + FONT_READOUT * 100, 1.0, 0.0, 0.0, sRead);
	}
}

// ----------------------------------------------------------------------------
//  GITD_JunkerScanHandler -- DEMO driver. On WorldLoaded, and then on a loop,
//  spawns ONE junker scan in front of player 1 at eye height so the user SEES
//  the boot choreography on boot in VR. Gated on gitd_junker_demo (default ON).
//
//  REGISTRATION: appended to the addeventhandlers line in `zmapinfo` -- an
//  EventHandler is DEAD unless registered there. VERIFIED present.
// ----------------------------------------------------------------------------
class GITD_JunkerScanHandler : EventHandler
{
	int mGap;   // tics until the next demo re-fire

	static bool   CBool(string n, bool d)   { CVar c = CVar.FindCVar(n); return c ? c.GetBool()  : d; }
	static int    CInt (string n, int d)    { CVar c = CVar.FindCVar(n); return c ? c.GetInt()   : d; }
	static double CFlt (string n, double d) { CVar c = CVar.FindCVar(n); return c ? c.GetFloat() : d; }

	override void WorldLoaded(WorldEvent e)
	{
		mGap = 0;   // fire immediately on map load
	}

	override void WorldTick()
	{
		// DEMO only -- the real HF brain will call GITD_JunkerScan.Make() at the
		// right moment (boss intro / hack interaction). Gate keeps it opt-out.
		if (!CBool("gitd_junker_demo", true)) return;
		if (!CBool("gitd_junker_enabled", true)) return;

		if (mGap > 0) { mGap--; return; }

		let pmo = players[consoleplayer].mo;
		if (!pmo || pmo.health <= 0) return;

		// center ~96u in FRONT of the player at eye height, facing them.
		// ZScript trig is in DEGREES (matches gitd_brand / gitd_triptych).
		double fa   = pmo.angle;
		double dist = CFlt("gitd_junker_dist", 96.0);
		double cx   = pmo.pos.x + cos(fa) * dist;
		double cy   = pmo.pos.y + sin(fa) * dist;
		double cz   = pmo.pos.z + pmo.height * 0.72;   // eye height
		Vector3 center = (cx, cy, cz);

		// placeholder vitals/threat/score (the user dials / the brain feeds later)
		GITD_JunkerScan.Make(center, 87, 42, 13370);

		// schedule the next loop: scan length + a breathing gap.
		int skull = max(8, int(CFlt("gitd_junker_skulltime", 28.0)));
		int sync  = max(8, CInt("gitd_junker_synctime", 30));
		int grant = max(8, CInt("gitd_junker_grantedtime", 35));
		int gap   = max(0, CInt("gitd_junker_loopgap", 70));
		mGap = skull + sync + grant + gap;
	}
}
