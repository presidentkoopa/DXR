// ============================================================================
//  ICE HOOK — DoomXR dual-purpose VR tool / weapon   (baked in 2026-07-03,
//  from the standalone IceHook_mod v1 prototype)
//
//  Fire   (main trigger) : melee swing  — pick to the skull (A_CustomPunch)
//  AltFire (2nd trigger) : throw a hook — flies straight, embeds where it hits,
//                          and damages monsters it strikes.
//
//  STANDALONE by design: this does NOT touch the C++ climb loop
//  (VR_UpdateClimbing is velocity-driven with no anchor — see design notes).
//  Climb / grapple-pull / retrieval-to-hand are a later layer built on
//  IceHookStuck as an anchor. This layer just makes the tool exist and work.
//
//  Given to every player via Player.StartItem in doomplayer.zs -- the real
//  "default class" mechanism (same as Pistol/Fist), not a StaticEventHandler
//  workaround. The standalone prototype used an IceHookHandler auto-give
//  handler specifically because it couldn't edit doomplayer.zs from outside
//  the engine tree; now that it's baked in, that workaround is gone.
//
//  Art: real IQM model (models/icehook/icehook.iqm, MODELDEF-bound to the ICHK
//  sprite) + a dedicated ICHK placeholder 2D sprite for the flatscreen/no-model
//  fallback -- a byte-recolored copy of the vanilla fist (PUNG), NOT a reuse,
//  so binding a MODELDEF FrameIndex to it cannot reskin the stock Fist weapon.
//  Thrown/stuck-hook actors still use JGRN (grenade) as a placeholder.
// ============================================================================

class IceHook : DoomWeapon
{
	Default
	{
		Weapon.SelectionOrder 1800;
		Scale 0.2;						// [XR] runtime Scale is IGNORED for this model, so the real size fix is
										//      BAKED into the mesh geometry (verts x0.05 in icehook.iqm, backup
										//      .bak alongside). Kept at the 0.2 baseline so re-baking the iqm to a
										//      different factor changes size predictably. To resize: re-bake the iqm.
		Weapon.SlotNumber 9;			// unused slot — selectable on "9", no clash with 1-8
		Weapon.AmmoUse 0;
		Weapon.AmmoGive 0;
		Weapon.Kickback 100;
		+WEAPON.NOAUTOFIRE
		+WEAPON.MELEEWEAPON
		+WEAPON.NOALERT
		Inventory.PickupMessage "You got the ICE HOOKS!";
		Tag "Ice Hook";
		Keywords "mass:4", "grab", "class:icehook", "grip:none", "dmg:pierce", "style:climb", "weight:light", "range:melee", "role:utility";
	}

	// [XR grapple-point preview] No existing aim-resolution to mirror here (unlike the whip's
	// StartGrappleFromAim) -- A_IceHookThrow just fires a physical projectile that flies until it
	// hits something, no pre-fire trace at all. This is a genuinely new forward trace, run every tic
	// while this hook is readied, so the preview promises roughly where a throw right now would land.
	// Range is a generous fixed cap (the real projectile has no reach limit, it flies until impact),
	// not tied to a cvar since there's nothing to tune -- it's just "far enough to always hit something."
	override void Tick()
	{
		Super.Tick();
		if (owner == null || owner.player == null) return;
		bool active = (owner.player.ReadyWeapon == self) || (owner.player.OffhandWeapon == self);
		if (!active) return;

		CVar pe = CVar.FindCVar("vr_icehook_preview_enable");
		if (pe && !pe.GetBool()) return;

		bool offhand = (owner.player.OffhandWeapon == self) && (owner.player.ReadyWeapon != self);
		Vector3 handPos = offhand ? owner.OffhandPos : owner.AttackPos;
		double ang = offhand ? owner.OffhandAngle : owner.AttackAngle;
		double pit = offhand ? owner.OffhandPitch : owner.AttackPitch;
		double hz = handPos.z - owner.pos.z;

		FLineTraceData lt;
		bool hit = owner.LineTrace(ang, 1024.0, pit, 0, hz, 0.0, 0.0, lt);
		if (hit && lt.HitType != TRACE_HitNone)
		{
			double radius = 6.0; { CVar r = CVar.FindCVar("vr_icehook_preview_radius"); if (r) radius = r.GetFloat(); }
			int color = 0x40C0FF; { CVar c = CVar.FindCVar("vr_icehook_preview_color"); if (c) color = c.GetInt(); }
			Level.AddGlowPanel(color, radius, lt.HitLocation.x, lt.HitLocation.y, lt.HitLocation.z, 0, 0.0, 0.0, 0.0, 0);
		}
	}

	// --- main trigger: melee swing -------------------------------------------
	action void A_IceHookMelee()
	{
		int dmg = 40;
		let cv = CVar.GetCVar("vr_icehook_melee_damage");
		if (cv) dmg = cv.GetInt();
		A_StartSound("weapons/grntoss", CHAN_WEAPON);
		// norandom=true for a consistent bite; flags=0 so it never eats ammo;
		// range 100 to be forgiving for VR reach.
		A_CustomPunch(dmg, true, 0, "BulletPuff", 100);
	}

	// --- second trigger: throw the hook --------------------------------------
	action void A_IceHookThrow()
	{
		double spd = 40.0;
		let cv = CVar.GetCVar("vr_icehook_throw_speed");
		if (cv) spd = cv.GetFloat();
		A_StartSound("weapons/grntoss", CHAN_WEAPON);
		// SpawnPlayerMissile honors the VR hand aim path (OverrideAttackPosDir).
		Actor proj = SpawnPlayerMissile("IceHookProjectile");
		if (proj && proj.Vel.Length() > 0)
			proj.Vel = proj.Vel.Unit() * spd;
	}

	// All states use ICHK frame A only -- the model is a single static frame with
	// no per-swing/throw pose, so there is nothing for extra sprite letters to show;
	// collapsing to one frame also means exactly one MODELDEF FrameIndex covers
	// every state (Ready/Select/Deselect/Fire/AltFire/Spawn) at once.
	States
	{
	Ready:
		ICHK A 1 A_WeaponReady();
		Loop;
	Deselect:
		ICHK A 1 A_Lower;
		Loop;
	Select:
		ICHK A 1 A_Raise;
		Loop;
	Fire:
		ICHK A 4;
		ICHK A 4 A_IceHookMelee();
		ICHK A 4;
		ICHK A 4 A_ReFire;
		Goto Ready;
	AltFire:
		ICHK A 3;
		ICHK A 2 A_IceHookThrow();
		ICHK A 3;
		ICHK A 6;
		Goto Ready;
	Spawn:
		ICHK A -1;
		Stop;
	}
}

// Off-hand instance: Doom weapons are MaxAmount 1, so a second independent hook
// needs its own class to occupy the off hand at the same time as the main hook.
class IceHookOff : IceHook { }

// ============================================================================
//  The thrown hook — flies straight, sticks on impact, hurts what it hits.
// ============================================================================
class IceHookProjectile : Actor
{
	Default
	{
		Radius 6;
		Height 6;
		Speed 40;
		Damage 6;					// missile dmg is Damage x random(1..8) -> ~6-48
		Projectile;
		+NOGRAVITY				// a hard-thrown pick, not a lob
		+BRIGHT
		Scale 0.6;
		Obituary "%o caught %k's ice hook.";
		DeathSound "weapons/grnbounce";
	}

	States
	{
	Spawn:
		JGRN A 2 { angle += 30; }		// spin in flight
		Loop;
	Death:
		JGRN A 0
		{
			// PICK-CLIMB POLICY: every surface is pickable by default; a liquid
			// is the only thing a pick can't bite. Walls (BlockingLine) and
			// monsters (BlockingMobj) always take the pick — the liquid test only
			// applies when the hook came down on a liquid floor plane, so a stick
			// to a dry wall above lava is still valid.
			bool pickable = true;
			if (!BlockingLine && !BlockingMobj)
			{
				TerrainDef ter = GetFloorTerrain();
				if (ter && ter.IsLiquid)
				{
					let cv = CVar.GetCVar("vr_icehook_pick_liquids");
					pickable = (cv && cv.GetBool());
				}
			}

			if (pickable)
			{
				// Embed a persistent hook at the impact point — the actor a
				// future climb/grapple layer would treat as a remote anchor.
				Actor s = Spawn("IceHookStuck", pos, ALLOW_REPLACE);
				if (s)
				{
					s.angle = angle; s.target = target;	// target = the thrower, for the pull
					// [stick FX] VR-visible ice-blue flash + sharp bite sound the INSTANT it locks in, so you
					// know without staring. Particles are invisible in the VR stereo pass, so use AddGlowPanel.
					Level.AddGlowPanel(Color(255, 90, 205, 255), 32.0, pos.x, pos.y, pos.z, 14, 1.0, 0.0, 0.0, 0);
					A_StartSound("weapons/grnbounce", CHAN_WEAPON, 0, 1.0);
				}
			}
			else
			{
				A_StartSound("weapons/grnbounce", CHAN_BODY);	// clattered off / into the drink
			}
		}
		Stop;
	}
}

// ============================================================================
//  The embedded hook left in the world after a throw.
// ============================================================================
class IceHookStuck : Actor
{
	Default
	{
		Radius 4;
		Height 8;
		+NOGRAVITY
		+NOBLOCKMAP
		+DONTSPLASH
		Scale 0.6;
	}

	int  life;
	int  pullTimer;
	bool pulling;
	int  returnTimer;   // [return] tics until an idle pick flies back (or is retrievable)

	override void PostBeginPlay()
	{
		Super.PostBeginPlay();

		int secs = 30;
		let cv = CVar.GetCVar("vr_icehook_stick_life");
		if (cv) secs = cv.GetInt();
		life = (secs <= 0) ? -1 : secs * 35;	// -1 == forever

		// Begin the "zip to hook" pull if enabled and we know who threw it.
		let ap = CVar.GetCVar("vr_icehook_autopull");
		pulling = (target && target.player && (ap ? ap.GetBool() : true));
		pullTimer = 105;	// ~3s hard cap so a snagged pull can't strand you
		let rd = CVar.GetCVar("vr_icehook_return_delay");
		returnTimer = rd ? rd.GetInt() : 70;
	}

	override void Tick()
	{
		Super.Tick();

		if (pulling && target && target.player && target.health > 0)
		{
			Vector3 to = pos - target.pos;
			double dist = to.Length();

			double arrive = 48.0;
			double spd = 30.0;
			double maxRange = 900.0;
			let sc = CVar.GetCVar("vr_icehook_pull_speed"); if (sc) spd = sc.GetFloat();
			let rc = CVar.GetCVar("vr_icehook_pull_range"); if (rc) maxRange = rc.GetFloat();

			if (dist <= arrive || pullTimer <= 0 || dist > maxRange)
			{
				StopPull();
			}
			else
			{
				// Reel the thrower in. Full-Vel overwrite each tic: collision-aware
				// (walls still block, no clipping) and the +Z lifts you when the hook is
				// overhead. We deliberately DON'T touch bNoGravity — the C++ climb loop
				// clears MF_NOGRAVITY every non-climbing tic (p_user.cpp:1980), so any flag
				// we set is dead on arrival; the Vel overwrite dominates gravity anyway.
				double step = (spd < dist) ? spd : dist;	// don't overshoot the arrive band
				target.Vel = to.Unit() * step;
				pullTimer--;
			}
		}
		else if (pulling)
		{
			StopPull();	// thrower died / vanished
		}

		// [findability] a subtle VR-visible pulse (~6/sec) so a planted pick is easy to spot for retrieval.
		if ((Level.maptime % 10) == 0)
			Level.AddGlowPanel(Color(200, 90, 205, 255), 14.0, pos.x, pos.y, pos.z, 14, 0.6, 0.0, 0.0, 0);

		// [return / retrieve] once the grapple-pull is done, the pick either flies BACK to the thrower
		// (boomerang, vr_icehook_autoreturn ON) or just waits to be walked-over and collected (toggle OFF).
		if (!pulling && target)
		{
			let ar = CVar.GetCVar("vr_icehook_autoreturn");
			bool autoReturn = ar ? ar.GetBool() : true;
			if (autoReturn)
			{
				if (returnTimer > 0) returnTimer--;
				else
				{
					Vector3 to = (target.pos + (0.0, 0.0, 32.0)) - pos;   // aim for mid-body, not feet
					double d = to.Length();
					if (d < 48.0)
					{
						Level.AddGlowPanel(Color(255, 90, 205, 255), 20.0, pos.x, pos.y, pos.z, 14, 1.0, 0.0, 0.0, 0);
						A_StartSound("weapons/grnbounce", CHAN_BODY);	// caught it back
						Destroy(); return;
					}
					SetOrigin(pos + to.Unit() * min(28.0, d), true);	// fly back to the hand (a prop, not the pawn -- SetOrigin ok)
				}
			}
			else if ((target.pos - pos).Length() < 56.0)
			{
				A_StartSound("weapons/grnbounce", CHAN_BODY);	// walked over and collected
				Destroy(); return;
			}
		}

		if (life > 0)
		{
			life--;
			if (life <= 0) { StopPull(); Destroy(); return; }
		}
	}

	void StopPull()
	{
		pulling = false;
	}

	States
	{
	Spawn:
		JGRN A -1;
		Stop;
	}
}
