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
		Weapon.SlotNumber 9;			// unused slot — selectable on "9", no clash with 1-8
		Weapon.AmmoUse 0;
		Weapon.AmmoGive 0;
		Weapon.Kickback 100;
		+WEAPON.NOAUTOFIRE
		+WEAPON.MELEEWEAPON
		+WEAPON.NOALERT
		Inventory.PickupMessage "You got the ICE HOOKS!";
		Tag "Ice Hook";
		Keywords "mass:4", "grab", "class:icehook", "dmg:pierce", "style:climb", "weight:light", "range:melee", "role:utility";
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
				if (s) { s.angle = angle; s.target = target; }	// target = the thrower, for the pull
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
