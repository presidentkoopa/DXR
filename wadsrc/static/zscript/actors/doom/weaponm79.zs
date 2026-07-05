// --------------------------------------------------------------------------
//
// M79 Grenade Launcher  (DoomXR-native)
//
// Wired from the Skulltag M79 assets (Desktop\m79 + SPRITES + SOUNDS). It is a real
// grenade launcher, NOT a rocket launcher: primary fires a tumbling 40mm grenade that
// arcs under gravity, spins end-over-end (nade.md3, driven by USEACTORPITCH in
// modeldef.txt) and detonates on impact. Alt fire lobs a bouncy grenade that ricochets
// off walls/floors and cooks off on a short fuse. Shares slot 5 + rocket ammo with the
// Rocket Launcher. Viewmodel = M79.md3 (models/weapons/hud/m79) mapped in modeldef.txt.
// Muzzle-flash sprite suppressed to TNT1 like every other VR weapon.
//
// --------------------------------------------------------------------------

class M79 : DoomWeapon
{
	mixin XR_ManualReload;

	Default
	{
		Weapon.SelectionOrder 2600;
		Weapon.SlotNumber 5;   // [XR] slot 5 (matches DoomPlayer's Player.WeaponSlot 5)
		Weapon.AmmoUse 1;
		Weapon.AmmoGive 2;
		Weapon.AmmoType "RocketAmmo";
		+WEAPON.NOAUTOFIRE
		Inventory.PickupMessage "Picked up the M79 Grenade Launcher!";
		Tag "M79 Grenade Launcher";
		Keywords "mass:70", "grab", "class:grenadelauncher", "dmg:explosive", "style:lobber", "weight:heavy", "range:medium", "fire:single", "handling:heavy", "role:heavy", "vr_dualwield";
	}
	States
	{
	Ready:
		GLAN A 0 { if (invoker.XRMagSize == 0) invoker.XR_InitChamber(1); }   // single-shot break-open
		GLAN A 0 A_XR_CheckChamber("Reload");                                 // auto-reload when spent
		GLAN A 1 A_WeaponReady(WRF_ALLOWRELOAD);                              // + on-demand reload button
		Loop;
	Deselect:
		GLAN A 1 A_Lower;
		Loop;
	Select:
		GLAN A 1 A_Raise;
		Loop;
	// Primary: lob a 40mm grenade -- arcs, tumbles end-over-end, detonates on impact.
	Fire:
		TNT1 A 0 A_JumpIf(!A_XR_TryFire(), "Ready");   // must have a grenade chambered
		GLAF A 4 A_GunFlash;
		GLAF B 8
		{
			A_StartSound("weapons/grenadefire", CHAN_WEAPON);
			A_FireM79Grenade();
			A_Recoil(4.0);
		}
		GLAF C 6;
		GLAN A 0 A_ReFire;
		Goto Ready;
	// Alt: lob a bouncy grenade -- ricochets and cooks off on a short fuse.
	AltFire:
		TNT1 A 0 A_JumpIf(!A_XR_TryFire(), "Ready");
		GLAF A 4 A_GunFlash;
		GLAF B 8
		{
			A_StartSound("weapons/grenadefire", CHAN_WEAPON);
			A_FireM79Grenade("M79BounceGrenade");
			A_Recoil(4.0);
		}
		GLAF C 6;
		GLAN A 0 A_ReFire;
		Goto Ready;
	// Break-open reload -- drives M79.md3's OWN baked reload (frames 7-32, GLR1 A-Z,
	// mapped in modeldef.txt): hinge open, extract spent shell, load 40mm, snap closed.
	Reload:
		GLR1 A 2 A_StartSound("weapons/grenadeopen", CHAN_WEAPON, volume: 0.7);
		GLR1 BCDEFGHIJKL 2;
		GLR1 M 2 A_StartSound("weapons/grenadeload", CHAN_AUTO, volume: 0.7);
		GLR1 NOPQRSTUVW 2;
		GLR1 X 2 A_XR_RefillChamber();   // fresh round seated -> re-arm
		GLR1 Y 2 A_StartSound("weapons/grenadeclose", CHAN_WEAPON, volume: 0.7);
		GLR1 Z 2;
		Goto Ready;
	Flash:
		// VR: muzzle-flash sprite suppressed, muzzle light kept.
		TNT1 A 4 Bright A_Light1;
		TNT1 A 3 Bright A_Light2;
		Goto LightDone;
	Spawn:
		GLAP A -1;
		Stop;
	}
}

//===========================================================================
//
// M79 grenade fire -- VR-correct spawn (respects off-hand aim), slight upward
// pitch for the lob arc, and ammo depletion. Modeled on A_FireSTGrenade
// (weaponrlaunch.zs). Pass a class to fire the bouncy variant on alt-fire.
//
//===========================================================================

extend class StateProvider
{
	action void A_FireM79Grenade(class<Actor> grenadetype = "M79Grenade")
	{
		if (grenadetype == null || player == null)
			return;

		int hand = 0;
		Weapon weap = invoker == player.OffhandWeapon ? player.OffhandWeapon : player.ReadyWeapon;
		if (weap != null && invoker == weap && stateinfo != null && stateinfo.mStateType == STATE_Psprite)
		{
			hand = weap.bOffhandWeapon ? 1 : 0;
		}

		// Raise the aim slightly so the grenade lobs in an arc instead of driving flat.
		double savedpitch = pitch;
		pitch -= 6.328125;
		SpawnPlayerMissile(grenadetype, aimflags: hand ? ALF_ISOFFHAND : 0);
		pitch = savedpitch;
	}
}

//===========================================================================
//
// M79Grenade -- primary 40mm round. Arcs under gravity, tumbles end-over-end,
// detonates the instant it touches anything (wall, floor, or monster).
//
//===========================================================================

class M79Grenade : Actor
{
	Default
	{
		Radius 6;
		Height 6;
		Speed 42;
		Damage 20;
		Projectile;
		-NOGRAVITY
		+INTERPOLATEANGLES
		Gravity 0.4;
		DamageType "Explosive";
		Obituary "%o was blown apart by %k's grenade launcher.";
	}

	// End-over-end tumble in flight. Movement follows velocity; pitch/roll here are
	// cosmetic only (USEACTORPITCH/USEACTORROLL in modeldef.txt spin the model).
	override void Tick()
	{
		Super.Tick();
		if (!isFrozen())
		{
			pitch += 26;
			roll += 7;
		}
	}

	void M79Detonate()
	{
		A_StartSound("weapons/grenadebang", CHAN_BODY, CHANF_OVERLAP);
		A_Explode(140, 176);
		A_Explode(90, 80);
		A_SpawnItemEx("GrenadeExplosionEffect", 0, 0, 0);
		level.AddGlowPanel(Color(255, 255, 160, 60), 200.0, pos.x, pos.y, pos.z, 14, 1.0, 0.0, 0.0, 0);
		for (int i = 0; i < 16; i++)
		{
			A_SpawnItemEx("GrenadeShrapnel", 0, 0, 8, frandom(10, 20), 0, frandom(2, 10), random(0, 360), SXF_NOCHECKPOSITION);
		}
	}

	States
	{
	Spawn:
		JGRN A 1;
		Loop;
	Death:
		TNT1 A 0 { M79Detonate(); }
		Stop;
	}
}

//===========================================================================
//
// M79BounceGrenade -- alt-fire round. Ricochets off floors/walls/ceilings and
// cooks off on a short fuse (impact does NOT detonate it, so it bounces around
// corners before going up).
//
//===========================================================================

class M79BounceGrenade : M79Grenade
{
	Default
	{
		Speed 34;
		Gravity 0.5;
		+BOUNCEONFLOORS
		+BOUNCEONWALLS
		+BOUNCEONCEILINGS
		+CANBOUNCEWATER
		+INTERPOLATEANGLES
		BounceType "Doom";
		BounceFactor 0.55;
		WallBounceFactor 0.5;
		BounceSound "weapons/grnbounce";
	}

	int fuse;

	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		fuse = 0;
	}

	override void Tick()
	{
		Super.Tick();   // inherits the end-over-end tumble
		if (!isFrozen())
		{
			fuse++;
			if (fuse >= 84)   // ~2.4s cook-off
			{
				SetStateLabel("Death");
			}
		}
	}

	States
	{
	Spawn:
		JGRN A 1;
		Loop;
	Death:
		TNT1 A 0 { M79Detonate(); }
		Stop;
	}
}
