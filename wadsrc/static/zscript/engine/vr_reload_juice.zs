// ----------------------------------------------------------------------------
// vr_reload_juice.zs -- physical magazines + reload "juice".
//
// Canon (RELOAD_JUICE_SPEC.md): ejected mags are REAL objects -- they fall, bounce,
// litter the floor, glow in the dark, fade out, and STAGGER + damage a monster you
// fling one into ("reloaded into their face"). The eject (A_XR_EjectToPouch) spawns
// one with your aim momentum; a slow drop just litters, a hard fling bonks a demon.
//
// Pure ZScript -- rides a pk3 repack, no C++ compile.
// CVars: vr_reload_mag_throw / _damage / _eject_speed / _life (see CVARINFO).
// ----------------------------------------------------------------------------

class XRSpentMag : Actor
{
	int  life;
	bool hitDone;    // one damage event per throw so it can't machine-gun a crowd
	bool heldOff;    // held in the off-hand awaiting a manual throw (offhand-throw mode)
	bool wasGrip;    // off-hand grip state last tic (release-edge detect)

	Default
	{
		Radius 5;
		Height 5;
		Mass 8;
		Gravity 0.9;
		+DROPPED
		+NOBLOCKMONST
		+DONTSPLASH
		+NOTELEPORT
		+CANBOUNCEWATER
		BounceType "Doom";
		BounceFactor 0.35;
		WallBounceFactor 0.35;
		RenderStyle "Translucent";
		Alpha 1.0;
		Scale 1.0;
	}

	States { Spawn: TNT1 A -1; Stop; }

	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		int secs = 6;
		CVar c = CVar.FindCVar("vr_reload_mag_life");
		if (c) secs = c.GetInt();
		life = (secs <= 0) ? -1 : secs * 35;
	}

	override void Tick()
	{
		Super.Tick();

		// [offhand-throw] while held in the off-hand: track the hand, fling on grip-release.
		if (heldOff)
		{
			PlayerPawn pp = target ? PlayerPawn(target) : null;
			if (!pp || !pp.player) { heldOff = false; bNoGravity = false; }
			else
			{
				bNoGravity = true;                       // hold it steady at the hand, no sag
				bool grip = pp.GetGripValue(1) > 0.5;    // off-hand grip
				SetOrigin(pp.OffhandPos, false);
				Vel = (0, 0, 0);
				if (wasGrip && !grip)                    // released -> throw with the hand's velocity
				{
					double mult = 1.5;
					CVar mc = CVar.FindCVar("vr_reload_mag_throw_mult");
					if (mc) mult = mc.GetFloat();
					Vel = pp.GetHandVelocity(1) * mult;
					heldOff = false;
					bNoGravity = false;
				}
				wasGrip = grip;
				if (life > 0) { life--; if (life <= 0) { Destroy(); return; } }
				return;                                  // no damage/glow while it's in your hand
			}
		}

		double spd = Vel.Length();

		// --- fast contact => damage + stagger a monster (once) ---
		if (!hitDone && spd >= 6.0)
		{
			double dmgRange = radius + 22.0;
			BlockThingsIterator it = BlockThingsIterator.Create(self, dmgRange);
			while (it.Next())
			{
				Actor mo = it.thing;
				if (!mo || mo == self || !mo.bIsMonster || mo.health <= 0) continue;
				if (Distance3D(mo) > dmgRange) continue;

				int dmg = 8;
				CVar dc = CVar.FindCVar("vr_reload_mag_damage");
				if (dc) dmg = dc.GetInt();

				mo.DamageMobj(self, self.target, dmg, 'Melee');
				// Knockback is handled by the native impact-momentum system (p_interaction.cpp):
				// mass*velocity / targetMass, so a heavy mag shoves and a light one just taps. No
				// flat nudge here -- that would double-push and ignore mass.
				A_StartSound("weapons/grntoss", CHAN_BODY, volume: 0.9);
				Level.AddGlowPanel(Color(255, 220, 120, 255), 22.0, pos.x, pos.y, pos.z, 15, 1.0, 0.0, 0.0, 0);
				hitDone = true;
				break;
			}
		}

		// --- faint glow so a spent mag reads in RADIANCE dark ---
		if ((Level.maptime % 6) == 0)
			Level.AddGlowPanel(Color(255, 170, 60, 255), 7.0, pos.x, pos.y, pos.z, 14, 0.5, 0.0, 0.0, 0);

		// --- fade + expire ---
		if (life > 0)
		{
			life--;
			if (life < 35) Alpha = double(life) / 35.0;
			if (life <= 0) { Destroy(); return; }
		}
	}
}

// ----------------------------------------------------------------------------
// XRReloadFumble -- "fumble under fire". Canon (RELOAD_JUICE_SPEC): taking a big hit
// mid-reload has a % chance to make you DROP the loose mag -- it only loosens the
// gesture (native VR_AbortReload resets the FSM, ammo is untouched) and litters a
// live XRSpentMag. Never voids ammo. Default OFF (opt-in white-knuckle mode).
//
// VR_AbortReload / VR_GetReloadState are PARAM_SELF_PROLOGUE natives (no psprite
// context), so it is safe to call them on the pawn from this handler.
// CVars: vr_reload_fumble (master, default FALSE), vr_reload_fumble_damage (min hit),
//        vr_reload_fumble_chance (%).
// ----------------------------------------------------------------------------
class XRReloadFumble : StaticEventHandler
{
	override void WorldThingDamaged(WorldEvent e)
	{
		CVar en = CVar.FindCVar("vr_reload_fumble");
		if (!en || !en.GetBool()) return;

		Actor mo = e.Thing;
		if (!mo || !mo.player) return;
		if (mo.player != players[consoleplayer]) return;   // local VR player only
		if (!mo.player.PlayInVR) return;

		// only while a reload gesture is actually in flight (state != READY)
		if (mo.VR_GetReloadState() == 0) return;

		int minDmg = 25;
		CVar dc = CVar.FindCVar("vr_reload_fumble_damage");
		if (dc) minDmg = dc.GetInt();
		if (e.Damage < minDmg) return;

		int pct = 15;
		CVar cc = CVar.FindCVar("vr_reload_fumble_chance");
		if (cc) pct = cc.GetInt();
		if (random[XRFumble](1, 100) > pct) return;

		// fumble! reset the in-flight reload (ammo untouched) + litter a dropped mag.
		mo.VR_AbortReload();

		let pp = PlayerPawn(mo);
		Vector3 dropPos = pp ? pp.AttackPos : mo.pos + (0, 0, mo.height * 0.55);
		Actor sm = Actor.Spawn("XRSpentMag", dropPos);
		if (sm)
		{
			// weak, mostly-vertical toss so it just clatters at your feet (not a weapon)
			double ang = mo.angle + frandom[XRFumble](-30.0, 30.0);
			Vector3 dir = (cos(ang) * 0.4, sin(ang) * 0.4, 0.5);
			sm.Vel = dir * 3.0;
			sm.Mass = 8;
			sm.target = mo;
		}
		// Visual-only fumble cue (a red spark at the gun). No action-func / sound call from a handler
		// (landmine); the dropped XRSpentMag makes its own clatter in its Tick.
		mo.Level.AddGlowPanel(Color(255, 60, 40, 255), 20.0, dropPos.x, dropPos.y, dropPos.z, 15, 1.0, 0.0, 0.0, 0);
	}
}

// ----------------------------------------------------------------------------
// XRReloadPerfectFX -- PERFECT-reload payoff. Canon: nailing the combat-reload timing
// window pops a neon "PERFECT" over the gun + a bright glow flash. Polls the native
// read-once flag VR_GetReloadPerfect (PARAM_SELF_PROLOGUE, safe from a handler); the
// flag is raised by the FSM when a refill lands in the window and cleared on read.
//
// A dedicated combo meter does not currently exist in DoomXR; when one lands, feed it
// here (send a NetEvent / call its Add). CVar: vr_reload_perfect_fx (default TRUE).
// ----------------------------------------------------------------------------
class XRReloadPerfectFX : StaticEventHandler
{
	override void WorldTick()
	{
		CVar en = CVar.FindCVar("vr_reload_perfect_fx");
		if (en && !en.GetBool()) return;

		PlayerInfo p = players[consoleplayer];
		PlayerPawn pmo = p ? PlayerPawn(p.mo) : null;
		if (!pmo || !pmo.player || !pmo.player.PlayInVR) return;

		if (pmo.VR_GetReloadPerfect() != 1) return;   // read-once; only fires on the tic the window was hit

		// neon "PERFECT" over the gun + a white flash. SpawnSDFText is a level native (see vr_test_maptext.zs).
		Vector3 gp = pmo.AttackPos;
		gp.z += 8.0;
		pmo.Level.SpawnSDFText(gp.x, gp.y, gp.z, "PERFECT", 1.1);
		pmo.Level.AddGlowPanel(Color(255, 255, 240, 255), 30.0, gp.x, gp.y, gp.z, 15, 1.0, 0.0, 0.0, 0);
	}
}

// ----------------------------------------------------------------------------
// XRMagTrail -- "mag glow-trail" (canon 3.2). A fresh mag leaves a neon streak as you
// carry it from the pouch and slam it home. The held XRReloadMag moves with your hand,
// so a glow panel dropped on it every few tics reads as a trailing streak. Colour hints
// the ammo type. CVar: vr_reload_mag_trail (default on). Pure ZScript, rides the repack.
// ----------------------------------------------------------------------------
class XRMagTrail : StaticEventHandler
{
	override void WorldTick()
	{
		CVar en = CVar.FindCVar("vr_reload_mag_trail");
		if (en && !en.GetBool()) return;
		if ((Level.maptime % 3) != 0) return;   // every 3 tics -> a dotted streak, not a smear

		ThinkerIterator it = ThinkerIterator.Create("XRReloadMag");
		while (true)
		{
			Thinker t = it.Next();
			if (!t) break;
			Actor mag = Actor(t);
			if (!mag) continue;
			Color c = Color(120, 220, 255, 255);                // default neon-cyan streak
			if (mag is "XRMag_Plasma")        c = Color(120, 255, 220, 255);
			else if (mag is "XRMag_Pod")      c = Color(160, 200, 255, 255);
			else if (mag is "XRMag_Chaingun") c = Color(255, 180, 90, 255);
			mag.Level.AddGlowPanel(c, 8.0, mag.pos.x, mag.pos.y, mag.pos.z, 14, 0.7, 0.0, 0.0, 0);
		}
	}
}

// ----------------------------------------------------------------------------
// XRDroppedAmmo -- variable ammo in DROPPED enemy guns. Canon: a gun a monster drops
// carries a random (sometimes ZERO -> cruel click) chamber, so grabbing it is a gamble.
// Sets a preset chamber + XRChamberPreset so XR_InitChamber keeps it on pickup. Concrete
// casts (NO IntVar). CVar: vr_reload_dropped_ammo (default true).
// ----------------------------------------------------------------------------
class XRDroppedAmmo : StaticEventHandler
{
	override void WorldThingSpawned(WorldEvent e)
	{
		CVar en = CVar.FindCVar("vr_reload_dropped_ammo");
		if (en && !en.GetBool()) return;
		Actor t = e.Thing;
		if (!t || !t.bDropped) return;   // only monster-dropped weapons
		if (t is "Shotgun")           { let w = Shotgun(t);      w.XRChamber = random[XRDrop](0, 8);  w.XRChamberPreset = true; }
		else if (t is "SuperShotgun") { let w = SuperShotgun(t); w.XRChamber = random[XRDrop](0, 2);  w.XRChamberPreset = true; }
		else if (t is "Chaingun")     { let w = Chaingun(t);     w.XRChamber = random[XRDrop](0, 30); w.XRChamberPreset = true; }
	}
}

// ----------------------------------------------------------------------------
// XRChaingunSlam -- two-hand ammo-box SLAM reload for the Chaingun ("love it"). When the
// belt isn't full, a hard OFF-HAND downward slam near the gun (the two-hand box-slam
// motion) instantly re-arms the whole belt + big haptic. Concrete Chaingun() cast for the
// mixin fields (NO IntVar). CVars: vr_reload_chaingun_slam (true), _slam_speed (14).
// ----------------------------------------------------------------------------
class XRChaingunSlam : StaticEventHandler
{
	bool slamPrev;
	override void WorldTick()
	{
		CVar en = CVar.FindCVar("vr_reload_chaingun_slam");
		if (en && !en.GetBool()) { slamPrev = false; return; }
		PlayerInfo p = players[consoleplayer];
		PlayerPawn pmo = p ? PlayerPawn(p.mo) : null;
		if (!pmo || !pmo.player || !pmo.player.PlayInVR) { slamPrev = false; return; }
		Weapon w = pmo.player.ReadyWeapon;
		if (!w || !(w is "Chaingun")) { slamPrev = false; return; }
		let cg = Chaingun(w);
		if (cg.XRMagSize <= 0 || cg.XRChamber >= cg.XRMagSize) { slamPrev = false; return; }   // full / not inited

		vector3 offVel = pmo.GetHandVelocity(1);        // temp: ZScript can't read .z directly off a call return
		double downSpeed = -offVel.z;                   // off-hand punching DOWN
		double thr = 14.0;
		CVar tc = CVar.FindCVar("vr_reload_chaingun_slam_speed");
		if (tc) thr = tc.GetFloat();
		bool slamNow = (downSpeed > thr) && ((pmo.OffhandPos - pmo.AttackPos).Length() < 40.0);
		if (slamNow && !slamPrev)
		{
			int avail = cg.Ammo1 ? cg.Ammo1.Amount : 0;
			cg.XRChamber = min(cg.XRMagSize, avail);
			cg.XRReloading = false;
			pmo.VR_HapticPulse(0, 1.0, 0.12);
			pmo.VR_HapticPulse(1, 1.0, 0.12);
			pmo.Level.AddGlowPanel(Color(255, 200, 80, 255), 26.0, pmo.AttackPos.x, pmo.AttackPos.y, pmo.AttackPos.z, 15, 1.0, 0.0, 0.0, 0);
		}
		slamPrev = slamNow;
	}
}
