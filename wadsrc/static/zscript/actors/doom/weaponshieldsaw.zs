// --------------------------------------------------------------------------
//
// ShieldSaw -- off-hand triple-mode tool, ported from the RLVR ("Rusted
// Legacy") devbuild prototype found in Desktop/BUGFIX and adapted to
// DoomXR-native conventions (bOffhandWeapon / ALF_ISOFFHAND / LAF_ISOFFHAND,
// same pattern Fist/Chainsaw/Pistol already use -- no RLOffhandFist needed,
// any Weapon here can be off-hand).
//
// Three modes on one item:
//   1. Block  -- held up as a passive stance; ProtectorShield rides the
//                off-hand and can deflect or absorb incoming attacks.
//   2. Saw    -- active circular-saw melee, a ring of hits around the player.
//   3. Throw  -- launches as a bouncing boomerang that auto-aims at the
//                nearest visible monster, sticks briefly on impact, then
//                homes back to whichever hand threw it.
//
// Motion-throw: RLVR gated this behind an optional external mod ("oVRdrive")
// reading a gesture-token API. DoomXR doesn't need that -- the engine already
// tracks smoothed per-hand velocity natively (player->vr_hand_vel_buffer,
// p_user.cpp), now exposed to ZScript as Actor.GetHandVelocity(hand). A throw
// is just "hand velocity exceeds the engine's own flick threshold" -- no
// external dependency at all.
//
// Keywords: deliberately free of the substring "fist" -- models.cpp:214 hot-
// swaps ANY VR psprite whose Caller Keywords contain "fist" to the bare hand
// model, so a weapon that wants to render its own model must avoid it.
// "class:shieldsaw" instead ties into the native parry/twohand keyword
// profile system (KEYWORDS.json "weapons" namespace, keyword_dispatcher.cpp)
// for free -- see the KEYWORDS.json entry added alongside this file.
//
// Balance numbers below (damage, deflect chance, ranges) are carried over
// 1:1 from RLVR's defaults, not re-tuned -- treat every CVar as a starting
// point to dial in from the headset, not a finished value.
// --------------------------------------------------------------------------

// ---- Tiny invisible actor used as an aim-probe / return-vector target -----
class DummyPuff : Actor
{
	Default
	{
		Radius 1;
		Height 1;
		Speed 0;
		Damage 0;
		+NOINTERACTION;
		+NOGRAVITY;
	}
	States
	{
	Spawn:
		TNT1 A 1;
		Stop;
	}
}

// ---- Passive block stance: rides the off-hand, can deflect/absorb --------
class ProtectorShield : Actor
{
	Default
	{
		Radius 15;
		Height 30;
		Mass 1;
		Scale 1;
		BloodType "ShieldSawSparks";
		+SHOOTABLE
		+AIMREFLECT
		+NOGRAVITY
		+DONTTHRUST
		+NOBLOOD
		+NOPAIN
		+DONTRIP
		+NOTARGET
	}

	States
	{
	Spawn:
		TNT1 A 0;
		TNT1 A 35;
		Stop;
	}

	override void Tick()
	{
		if (master)
		{
			let pmo = master.player.mo;
			vector3 mPos = pmo.OffhandPos + (Actor.AngleToVector(pmo.OffhandAngle + 180, 1), 0) * (pmo.radius + radius);
			SetOrigin(mPos - (0, 0, height / 2), false);
			A_SetAngle(pmo.OffhandAngle + 90);
		}
		Super.Tick();
	}

	override int DamageMobj(Actor inflictor, Actor source, int damage, Name mod, int flags, double angle)
	{
		// Never reflect the wielder's own attacks back at them. This must NOT touch
		// bSHOOTABLE/bAIMREFLECT: those are persistent actor flags, and permanently
		// clearing them here (the original RLVR behavior) bricked the shield the first
		// time it ever took friendly-fire splash damage from its own wielder -- it would
		// silently stop blocking/reflecting for the rest of the level. Just skip the
		// reflect/absorb FX for this hit instead.
		if (master && master.player && source == master.player.mo)
		{
		}
		else if (master && master.player)
		{
			bREFLECTIVE = false;

			if (inflictor.bMISSILE)
			{
				A_StartSound("weapons/shield/throw", CHAN_WEAPON);
				// (Removed spawn of 'BDWhiteShockWaveSmall' -- a Brutal Doom cosmetic shockwave
				//  actor that does not exist in this engine. Deflect still fires its sound; add a
				//  native shockwave actor here later if a visual is wanted.)

				// carried default: ~30% deflect the missile back out, ~20% partial self-damage otherwise
				if (random[deflect](0, 9) > 6)
					bREFLECTIVE = true;
				else if (random[deflect](0, 9) > 5)
					master.DamageMobj(inflictor, source, damage * 0.1, mod, flags, angle);
			}
			else
			{
				A_StartSound("weapons/shield/hit", CHAN_WEAPON);
				Actor.Spawn("ShieldSawSparks", pos + (0, 0, height / 2));
			}
		}

		Super.DamageMobj(inflictor, source, damage, mod, flags, angle);
		return 1;
	}
}

// ---- Impact FX --------------------------------------------------------
class ShieldSawSparks : Actor
{
	Default
	{
		+NOINTERACTION
		+NOGRAVITY
		RenderStyle "Add";
		Scale 0.4;
	}
	States
	{
	Spawn:
		TNT1 A 1;
		TNT1 A 3;
		Stop;
	}
}

class ShieldSawBloods : Actor
{
	Default
	{
		+NOINTERACTION
		Scale 0.4;
	}
	States
	{
	Spawn:
		TNT1 A 1;
		TNT1 A 4;
		Stop;
	}
}

// Trail glow the flying saw leaves behind each tic.
class ShieldSawGlow : Actor
{
	Default
	{
		RenderStyle "Add";
		Damage 0;
		+NOINTERACTION
		+SKYEXPLODE
	}
	States
	{
	Spawn:
		TNT1 A 2;
		Stop;
	}
}

// ---- The thrown boomerang projectile --------------------------------------
class ThrownShieldSaw : Actor
{
	int hand;                 // which hand threw it: 0 = main, 1 = off
	transient int maxAge;
	transient int stalled;
	transient int cutThrough;
	transient vector3 prevPos;
	bool bouncing;
	vector3 lastBouncePos;
	double bounceIgnoreGuideDist;
	bool shieldHit;
	double damageMult;
	double speedMult;

	Default
	{
		Speed 20;
		Radius 10;
		Height 10;
		Damage 10;
		DamageType "Saw";
		Scale 0.5;
		Projectile;
		DeathSound "FighterHammerExplode";
		BounceType "Doom";
		BounceFactor 1.0;
		BounceCount 5;
		+INTERPOLATEANGLES
		+USEBOUNCESTATE
	}

	private double ScaledDamage(double baseDamage)
	{
		damageMult = clamp(damageMult, 1, 10);
		return baseDamage * random[shieldAttack](1, 8) * damageMult;
	}

	// Not a DoomXR native -- ports RLVR's own helper (it isn't in stock ZScript either;
	// RLVR defined this same body on every class that needed it).
	private double GetPitchTo(Actor source, Actor target, double zOfs = 0, double targZOfs = 0, bool absolute = false)
	{
		vector3 origin = (source.pos.xy, source.pos.z - source.floorClip + zOfs);
		vector3 dest = (target.pos.xy, target.pos.z - target.floorClip + targZOfs);
		vector3 diff = absolute ? (dest - origin) : level.Vec3Diff(origin, dest);
		return -atan2(diff.z, diff.xy.Length());
	}

	override int DoSpecialDamage(Actor victim, int damage, Name damagetype)
	{
		if (!bRIPPER) tracer = victim;
		if (master && victim)
		{
			if (victim == master) { Destroy(); return 0; }
			return damage;
		}
		Super.DoSpecialDamage(victim, damage, damagetype);
		return damage;
	}

	override void BeginPlay()
	{
		double maxRange = 1920; // matches ShieldSaw.shieldAttackRange default (see setupShieldSaw)
		maxAge = ceil(maxRange / speed);
		bounceIgnoreGuideDist = 5 * 64;
		Super.BeginPlay();
		A_ChangeVelocity(vel.x * speedMult, vel.y * speedMult, vel.z * speedMult, CVF_REPLACE);
	}

	override void Tick()
	{
		Super.Tick();

		if (!InStateSequence(curState, ResolveState("Death")) && !InStateSequence(curState, ResolveState("XDeath")))
		{
			roll += 45; // spinning-blade look; modeldef USEACTORROLL applies this to the model
			ShieldSawGlow(Actor.Spawn("ShieldSawGlow", pos)).A_SetAngle(angle);
		}

		if (!shieldHit)
		{
			if (GetAge() == 35)
			{
				tracer = target;
				target = self;
				bRIPPER = true;
			}
			if (GetAge() > maxAge) ReturnToMaster();

			if (bouncing && Level.Vec3Diff(pos, lastBouncePos).Length() > bounceIgnoreGuideDist)
				bouncing = false;
		}

		if (bRIPPER)
		{
			if (self && Distance2D(master) < 50) { Destroy(); return; }
			else if (self && Distance2D(master) < 90) bMISSILE = false;
			else bMISSILE = bSolid = true;

			if (self && Level.Vec3Diff(pos, prevPos).Length() < 3) stalled++;
			if (stalled > 3)
			{
				bNOCLIP = true;
				stalled = 0;
				ReturnToMaster();
				cutThrough = 5;
			}
			if (cutThrough) cutThrough--;
			if (!cutThrough) bNOCLIP = false;
		}

		prevPos = pos;
	}

	// Homes toward whichever hand threw it, using the same AttackPos/OffhandPos
	// world-space fields the rest of the VR engine reads.
	void ReturnToMaster()
	{
		if (!master) master = players[consoleplayer].mo;
		let dummy = Actor.Spawn("DummyPuff", (hand ? master.OffhandPos : master.AttackPos));
		if (dummy)
			Vel3DFromAngle(GetDefaultSpeed("ThrownShieldSaw") * 2, AngleTo(dummy), GetPitchTo(self, dummy));
		else
			Vel3DFromAngle(GetDefaultSpeed("ThrownShieldSaw") * 2, AngleTo(master), GetPitchTo(self, master));
	}

	action void A_StickOnSurface()
	{
		if (invoker.bRIPPER) { invoker.ReturnToMaster(); return; }
		if (invoker.tracer)
		{
			double newZ = invoker.pos.z;
			if (!invoker.tracer.bSolid) newZ = invoker.tracer.pos.z + 12;
			if (invoker.tracer != invoker.master) invoker.SetOrigin((invoker.tracer.pos.xy, newZ), true);
		}
	}

	action void A_ReturnToMaster()
	{
		invoker.bMISSILE = true;
		invoker.bRIPPER = true;
		invoker.SetDamage(int(invoker.ScaledDamage(3)));  // Actor.Damage is readonly; SetDamage is the native writable path
		invoker.ClearBounce();
		invoker.ReturnToMaster();
	}

	States
	{
	Spawn:
		SH00 A 1;
		Loop;
	Bounce:
		TNT1 A 0 A_StartSound("weapons/shield/bounce");
		TNT1 A 1
		{
			bouncing = true;
			lastBouncePos = pos;
			Actor.Spawn("ShieldSawSparks", pos);
		}
		Goto Spawn;
	Death:
	Crash:
		TNT1 A 0
		{
			shieldHit = true;
			A_StartSound("weapons/shield/hithard");
		}
	WaitReturn:
		TNT1 AAAAAAAAAAAA 3
		{
			A_StickOnSurface();
			if (random(0, 10) > 6) Actor.Spawn("ShieldSawSparks", pos);
		}
		TNT1 A 0 A_ReturnToMaster();
		Stop;
	XDeath:
		TNT1 A 0 { shieldHit = true; }
	WaitReturnOnMonster:
		TNT1 AAAAAAAAAAAA 2
		{
			A_StickOnSurface();
			A_StartSound("weapons/fleshimpact");
			if (random(0, 10) > 7) Actor.Spawn("ShieldSawBloods", pos);
			A_Explode(5.0 * damageMult, 10, XF_NOSPLASH);
		}
		TNT1 A 0 A_ReturnToMaster();
		Stop;
	}
}

// ---- The weapon itself -----------------------------------------------------
class ShieldSaw : Weapon
{
	double shieldAttackRange;
	double shieldDamageMult;
	double shieldSpeedMult;
	bool shieldMotionThrow;
	int shieldThrowAim;
	bool shieldBounce;
	bool forceCallBack;
	Actor shieldFlying;
	bool shieldReturned;
	Actor throwTarget;
	Actor protectorShield;
	bool sawAttack;
	bool shieldMode;
	bool shieldIdle;
	const SHIELDSAW_RANGE = 96; // DEFMELEERANGE-equivalent close-quarters saw range

	Default
	{
		Weapon.SelectionOrder 4200;
		+WEAPON.NOAUTOAIM
		+WEAPON.NOALERT
		+WEAPON.NOAUTOSWITCHTO
		Tag "Shield Saw";
		Keywords "mass:55", "grab", "class:shieldsaw", "dmg:saw", "style:melee_throw", "weight:heavy", "range:medium", "fire:continuous", "handling:heavy", "role:defense_offense", "flags:throwable";
		Inventory.PickupMessage "Picked up the Shield Saw!";
	}

	// Not DoomXR natives -- ports RLVR's own helpers (duplicated per-class in the source
	// project too; there's no free-function scope in ZScript to share them from).
	private double GetPitchTo(Actor source, Actor target, double zOfs = 0, double targZOfs = 0, bool absolute = false)
	{
		vector3 origin = (source.pos.xy, source.pos.z - source.floorClip + zOfs);
		vector3 dest = (target.pos.xy, target.pos.z - target.floorClip + targZOfs);
		vector3 diff = absolute ? (dest - origin) : level.Vec3Diff(origin, dest);
		return -atan2(diff.z, diff.xy.Length());
	}

	private double GetFOVDistance(PlayerPawn viewer, Actor other)
	{
		vector3 viewpoint = viewer.pos;
		viewpoint.z = viewer.player.viewz;
		vector3 otherCenter = other.pos;
		otherCenter.z += other.Height * 0.5;
		vector2 viewAngles = (viewer.angle, viewer.pitch);
		vector3 sphericalCoords = Level.SphericalCoords(viewpoint, otherCenter, viewAngles);
		return sphericalCoords.xy.Length();
	}

	private void setupShieldSaw()
	{
		double rangeCvar = 30.0, dmCvar = 1.0, smCvar = 1.0;
		bool bounceCvar = true, callCvar = true, mthrowCvar = true;
		int aimCvar = 2;

		CVar c;
		c = CVar.FindCVar("vr_shieldsaw_range");      if (c) rangeCvar = c.GetFloat();
		c = CVar.FindCVar("vr_shieldsaw_dmg_mult");    if (c) dmCvar = c.GetFloat();
		c = CVar.FindCVar("vr_shieldsaw_speed_mult");  if (c) smCvar = c.GetFloat();
		c = CVar.FindCVar("vr_shieldsaw_bounce");      if (c) bounceCvar = c.GetBool();
		c = CVar.FindCVar("vr_shieldsaw_callback");    if (c) callCvar = c.GetBool();
		c = CVar.FindCVar("vr_shieldsaw_motionthrow"); if (c) mthrowCvar = c.GetBool();
		c = CVar.FindCVar("vr_shieldsaw_aim");         if (c) aimCvar = c.GetInt();

		shieldAttackRange = 64 * rangeCvar;
		shieldDamageMult = dmCvar;
		shieldSpeedMult = smCvar;
		shieldBounce = bounceCvar;
		forceCallBack = callCvar;
		shieldThrowAim = aimCvar;
		shieldMotionThrow = mthrowCvar;
		if (!shieldFlying) shieldReturned = true;
	}

	private void checkForProtectorShield()
	{
		if (shieldMode && !shieldFlying && !sawAttack)
		{
			if (!protectorShield) protectorShield = Actor.Spawn("ProtectorShield");
			protectorShield.master = owner;
		}
		else if (protectorShield)
		{
			protectorShield.Destroy();
		}
	}

	// Native-velocity motion throw: a real hand flick, no external mod dependency.
	// vr_grab_flick_threshold (the engine's own existing "this counts as a flick"
	// speed, p_user.cpp) is 10.0 map-units/tic -- reused here for consistency.
	private void motionThrowShield()
	{
		if (shieldFlying || !shieldMotionThrow)
		{
			shieldReturned = false;
			return;
		}

		double flickThreshold = 10.0;
		CVar c = CVar.FindCVar("vr_shieldsaw_throwspeed");
		if (c) flickThreshold = c.GetFloat();

		vector3 handVel = owner.GetHandVelocity(bOffhandWeapon ? 1 : 0);
		if (handVel.Length() < flickThreshold)
		{
			shieldReturned = false;
			return;
		}

		let handPitch = -(bOffhandWeapon ? owner.OffhandPitch : owner.AttackPitch);
		let handRoll = bOffhandWeapon ? owner.OffhandRoll : owner.AttackRoll;

		if (throwTarget && throwTarget.health < 1) throwTarget = null;

		if (shieldThrowAim == 2)
		{
			Actor mo;
			double nearestDist;
			ThinkerIterator ts = ThinkerIterator.Create();
			while (mo = Actor(ts.Next()))
			{
				if (mo && mo.bIsMonster && mo.bSolid && owner.Distance2D(mo) <= shieldAttackRange
					&& mo.health > 0 && owner.CheckSight(mo) && mo != owner)
				{
					let fovDist = GetFOVDistance(PlayerPawn(owner), mo);
					if (((nearestDist && fovDist < nearestDist) || !nearestDist) && fovDist < 30)
					{
						nearestDist = fovDist;
						throwTarget = mo;
					}
				}
			}
		}

		int alflags = bOffhandWeapon ? ALF_ISOFFHAND : 0;
		shieldFlying = owner.SpawnPlayerMissile("ThrownShieldSaw", aimflags: alflags);

		if (shieldFlying)
		{
			shieldReturned = false;
			shieldFlying.master = owner;
			shieldFlying.target = owner;
			ThrownShieldSaw(shieldFlying).damageMult = shieldDamageMult;
			ThrownShieldSaw(shieldFlying).speedMult = shieldSpeedMult;
			ThrownShieldSaw(shieldFlying).hand = bOffhandWeapon ? 1 : 0;
			if (!shieldBounce) shieldFlying.ClearBounce();

			if (throwTarget)
			{
				shieldFlying.tracer = throwTarget;
				let bodyTarget = Actor.Spawn("DummyPuff", (throwTarget.pos.xy, throwTarget.pos.z + throwTarget.height * 2 / 3));
				shieldFlying.Vel3DFromAngle(GetDefaultSpeed(shieldFlying.GetClassName()) * shieldSpeedMult,
					shieldFlying.AngleTo(bodyTarget), GetPitchTo(shieldFlying, bodyTarget));
			}
			else if (handRoll > 31 || handRoll < -31)
			{
				shieldFlying.Vel3DFromAngle(GetDefaultSpeed(shieldFlying.GetClassName()) * shieldSpeedMult,
					shieldFlying.angle, shieldFlying.pitch - 20);
			}

			A_StartSound("weapons/shield/throw", CHAN_WEAPON);
			owner.A_AlertMonsters(640);
			SetStateLabel("ShieldWaitReturn");
		}
	}

	// Guides an in-flight, non-locked shield toward wherever the player is aiming.
	private void guideShieldMotion()
	{
		if (!shieldThrowAim || throwTarget) return;
		if (shieldFlying && ThrownShieldSaw(shieldFlying).bouncing) return;

		int laflags = LAF_NORANDOMPUFFZ | LAF_NOIMPACTDECAL | LAF_NOINTERACT;
		int alflags = bOffhandWeapon ? ALF_ISOFFHAND : 0;
		if (bOffhandWeapon) laflags |= LAF_ISOFFHAND;

		double pitch = owner.AimTarget() ? owner.BulletSlope(null, alflags) : owner.pitch;
		let aimGuide = owner.LineAttack(owner.angle, shieldAttackRange, pitch, 0, "none", "DummyPuff", laflags);

		if (aimGuide && shieldFlying && !shieldFlying.bRIPPER && !ThrownShieldSaw(shieldFlying).shieldHit)
		{
			shieldFlying.Vel3DFromAngle(GetDefaultSpeed(shieldFlying.GetClassName()) * shieldSpeedMult,
				shieldFlying.AngleTo(aimGuide), GetPitchTo(shieldFlying, aimGuide));
		}
	}

	private void circularSawAttack()
	{
		let pmo = owner;
		int laflags = bOffhandWeapon ? LAF_ISOFFHAND : 0;
		double ang = pmo.angle;
		double pitch = pmo.AimTarget() ? pmo.BulletSlope(null, ALF_PORTALRESTRICT) : pmo.pitch;
		double damage = 2;

		for (int i = 0; i <= 12; i++)
			pmo.LineAttack(ang, SHIELDSAW_RANGE, pitch + i * 30, damage, 'Melee', "BulletPuff", laflags);

		sawAttack = true;
	}

	action void A_ShieldMotionThrow() { invoker.motionThrowShield(); }
	action void A_GuideShieldMotion() { invoker.guideShieldMotion(); }
	action void A_CircularSawAttack() { invoker.circularSawAttack(); }

	action void A_CallShieldBack()
	{
		if (invoker.shieldFlying && invoker.forceCallBack)
			ThrownShieldSaw(invoker.shieldFlying).A_ReturnToMaster();
	}

	action void A_CheckShieldFlying()
	{
		if (!invoker.shieldFlying)
		{
			invoker.shieldReturned = true;
			invoker.shieldIdle = false;
		}
	}

	// Non-motion melee-first attack: tries a short-range circular swing before falling back to a throw.
	action bool A_ShieldThrow()
	{
		if (player == null) return false;

		int laflags = LAF_ISMELEEATTACK;
		int alflags = invoker.bOffhandWeapon ? ALF_ISOFFHAND : 0;   // action fn: self=pawn, so qualify the weapon flag with invoker
		if (invoker.bOffhandWeapon) laflags |= LAF_ISOFFHAND;

		double damage = random[ShieldAtk](40, 55) * clamp(invoker.shieldDamageMult, 1, 10);
		if (invoker.owner.CountInv("PowerStrength")) damage *= 5;

		FTranslatedLineTarget t;
		for (int i = 0; i < 16; i++)
		{
			for (int j = 1; j >= -1; j -= 2)
			{
				double ang = angle + j * i * (45. / 32);
				double slope = AimLineAttack(ang, SHIELDSAW_RANGE, t, 0., ALF_CHECK3D | alflags);
				LineAttack(ang, SHIELDSAW_RANGE, slope, damage, 'Melee', "DummyPuff", laflags, t);
				if (t.linetarget != null)
				{
					if (t.linetarget.bIsMonster || t.linetarget.player)
						t.linetarget.Thrust(10, t.attackAngleFromSource);
					return false;
				}
			}
		}

		// nothing in melee range: throw it instead
		invoker.shieldFlying = SpawnPlayerMissile("ThrownShieldSaw", aimflags: alflags);
		if (invoker.shieldFlying)
		{
			invoker.shieldReturned = false;
			invoker.shieldFlying.master = invoker.owner;
			invoker.shieldFlying.target = invoker.owner;
			ThrownShieldSaw(invoker.shieldFlying).damageMult = invoker.shieldDamageMult;
			ThrownShieldSaw(invoker.shieldFlying).speedMult = invoker.shieldSpeedMult;
			ThrownShieldSaw(invoker.shieldFlying).hand = invoker.bOffhandWeapon ? 1 : 0;
			if (!invoker.shieldBounce) invoker.shieldFlying.ClearBounce();
		}

		invoker.shieldReturned = false;
		A_StartSound("weapons/shield/throw", CHAN_WEAPON);
		A_AlertMonsters(640);
		return true;
	}

	States
	{
	Ready:
		SHLD A 0 { invoker.setupShieldSaw(); }
		SHLD A 0 A_JumpIf(invoker.shieldReturned == false, "ShieldWaitReturn");
		SHLD A 0 A_JumpIf(invoker.shieldIdle == false, "ReadyShieldSaw");
		SHLD A 1
		{
			A_WeaponReady(WRF_ALLOWRELOAD | WRF_ALLOWZOOM);
			invoker.checkForProtectorShield();
			invoker.sawAttack = false;
		}
		Loop;
	ReadyShieldSaw:
		SHSW A 1
		{
			A_WeaponReady(WRF_ALLOWRELOAD | WRF_ALLOWZOOM);
			invoker.checkForProtectorShield();
			invoker.sawAttack = false;
		}
		Loop;
	Deselect:
		SHLD A 1 A_Lower;
		Loop;
	Select:
		SHLD A 0 A_StartSound("weapon/shieldsaw/draw", CHAN_WEAPON);
		SHLD A 1 A_Raise;
		Loop;
	// Primary fire: toggle the passive block stance on/off.
	Fire:
		SHLD A 0
		{
			A_JumpIf(invoker.shieldFlying, "CallBackShield");
			invoker.shieldMode = !invoker.shieldMode;
			invoker.shieldIdle = invoker.shieldMode;
			invoker.checkForProtectorShield();
		}
		SHLD A 4;
		Goto Ready;
	// Alt fire: activate the circular saw and attack; hold to keep sawing, release to
	// (optionally) motion-throw it out as a boomerang.
	AltFire:
		SHLD A 0 A_JumpIf(invoker.shieldFlying, "CallBackShield");
		SHSW ABC 2;
	ShieldSawLoop:
		SHSW A 0 A_StartSound("weapon/shieldsaw/loop", CHAN_WEAPON);
		SHSW A 0 A_CircularSawAttack();
		SHSW A 1;
		SHSW A 0 A_ReFire("ShieldSawLoop");
		SHSW A 0 A_JumpIf(invoker.shieldMotionThrow == false, "ShieldThrow");
		SHSW A 0 A_ShieldMotionThrow();
		SHSW A 0 A_JumpIf(!invoker.shieldFlying, 2);
		SHSW A 0 A_StopSound(CHAN_WEAPON);
		Goto ShieldWaitReturn;
		SHSW ABC 2;
		Goto ReadyShieldSaw;
	ShieldThrow:
		SHSW A 1 A_ShieldThrow();
	ShieldWaitReturn:
		SHSW A 1
		{
			A_GuideShieldMotion();
			A_CheckShieldFlying();
			A_WeaponReady(WRF_ALLOWRELOAD | WRF_ALLOWZOOM);
		}
		Goto Ready;
	CallBackShield:
		SHSW A 1
		{
			A_CallShieldBack();
			A_WeaponReady(WRF_ALLOWRELOAD | WRF_ALLOWZOOM);
		}
		Goto Ready;
	Spawn:
		SHLD A -1;
		Stop;
	}
}
