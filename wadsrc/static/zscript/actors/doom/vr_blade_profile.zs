// --------------------------------------------------------------------------
//
// BladeProfile -- pure-data cosmetic/combat definition for VRSword. The
// weapon (vr_sword.zs) owns all motion tracking, swing gating, collision,
// and damage application; a BladeProfile only supplies what makes one blade
// different from another. Swapping blades (Steel / Lightsaber / Dragon's
// Tooth) never touches VRSword itself -- see BindBlade() there.
//
// Numbers below (damage, speed thresholds, armor-pierce fractions) are
// starting estimates for in-headset tuning, not finished balance values.
//
// --------------------------------------------------------------------------

enum EBladeBehaviorFlags
{
	// BF_DEFLECT is UNUSED -- projectile deflection ended up native and weapon-class-wide
	// (KEYWORDS.json "VRSword" parry_extent + VR_CheckWeaponParry, hw_vrmodes.cpp:1194,
	// wired via the "class:vrsword" Keywords tag in vr_sword.zs), not gated per blade
	// cosmetic. ALL THREE blades deflect uniformly as a result -- simpler and reuses an
	// already-built, already-tested system instead of hand-rolled ZScript reflection.
	// Left declared (not deleted) only so a future per-blade deflect DIFFERENCE has a slot.
	BF_DEFLECT     = 1,   // currently a no-op; see comment above
	BF_IGNOREARMOR = 2,   // damage bypasses armor absorption (DMG_NO_ARMOR)
	BF_CAUTERIZE   = 4,   // no blood spawn on a confirmed hit
	BF_DISMEMBER   = 8,   // flags the hit for whatever gore/dismember system consumes it
}

class BladeProfile : Object
{
	string ProfileName;

	// ---- Visual ----
	name BladeModel;          // MODELDEF entry, applied via A_ChangeModel
	double BladeLength;       // map units -- drives reach
	double BladeWidth;        // map units -- sweep/collision radius contribution
	Color GlowColor;          // NO dynamic light (RADIANCE hard constraint) -- glow spot / particle color only

	// ---- Audio (SNDINFO by FULL path; MONO only -- stereo is silent on desktop) ----
	string SndIdleHum;
	string SndSwing;
	string SndHitFlesh;
	string SndHitHard;

	// ---- Combat ----
	name DamageType;
	int BaseDamage;
	double MinSwingSpeed, SpeedDamageFloor;   // below MinSwingSpeed: damage = BaseDamage*SpeedDamageFloor
	double MaxSwingSpeed, SpeedDamageCeil;    // at/above MaxSwingSpeed: damage = BaseDamage*SpeedDamageCeil
	int BehaviorFlags;

	virtual void Setup() {}

	// The one code hook a profile may add beyond data. Default: no change.
	virtual int ModifyDamage(Actor victim, Actor inflictor, int damage, int hand)
	{
		return damage;
	}

	double DamageScaleForSpeed(double tipSpeed)
	{
		double t = clamp((tipSpeed - MinSwingSpeed) / max(1.0, MaxSwingSpeed - MinSwingSpeed), 0.0, 1.0);
		return SpeedDamageFloor + (SpeedDamageCeil - SpeedDamageFloor) * t;
	}
}

// ---- Steel Sword: heft-driven, wide speed/damage curve, dismembers on a clean hit -----------
class Blade_Steel : BladeProfile
{
	override void Setup()
	{
		ProfileName    = "Steel Sword";
		BladeModel     = 'VRSwordBladeSteel';
		BladeLength    = 40;
		BladeWidth     = 6;
		GlowColor      = Color(0, 0, 0, 0); // no glow -- plain steel

		SndIdleHum     = "";
		SndSwing       = "weapons/vrsword/swing";       // DSSWING whoosh
		SndHitFlesh    = "weapons/vrsword/hitflesh";    // bone-crunch slice
		SndHitHard     = "weapons/vrsword/hithard";     // axe-into-hard clang

		DamageType     = 'Melee';
		BaseDamage     = 18;
		MinSwingSpeed  = 20;  SpeedDamageFloor = 0.6;
		MaxSwingSpeed  = 60;  SpeedDamageCeil  = 2.4;
		BehaviorFlags  = BF_DISMEMBER;
	}
}

// ---- Lightsaber: energy blade, flat damage curve, deflects incoming projectiles -------------
class Blade_Lightsaber : BladeProfile
{
	override void Setup()
	{
		ProfileName    = "Lightsaber";
		BladeModel     = 'VRSwordBladePlasma';
		BladeLength    = 52;
		BladeWidth     = 4;
		GlowColor      = Color(255, 60, 160, 255);

		SndIdleHum     = "";                             // no clean hum loop in the library yet
		SndSwing       = "weapons/vrsword/swinge";       // AXECLN energy-blade swing
		SndHitFlesh    = "weapons/vrsword/hitflesh";
		SndHitHard     = "weapons/vrsword/hitenergy";    // B2KCLANG energy clang

		DamageType     = 'Fire';
		BaseDamage     = 45;
		MinSwingSpeed  = 20;  SpeedDamageFloor = 1.0;
		MaxSwingSpeed  = 60;  SpeedDamageCeil  = 1.6;
		BehaviorFlags  = BF_DEFLECT | BF_CAUTERIZE | BF_DISMEMBER;
	}
}

// ---- Dragon's Tooth: nano-crystal blade, near-instant kill, ignores armor -------------------
class Blade_DragonsTooth : BladeProfile
{
	override void Setup()
	{
		ProfileName    = "Dragon's Tooth";
		BladeModel     = 'VRSwordBladeNano';
		BladeLength    = 46;
		BladeWidth     = 3;
		GlowColor      = Color(70, 140, 255, 255);

		SndIdleHum     = "";
		SndSwing       = "weapons/vrsword/swinge";       // AXECLN clean energy swing
		SndHitFlesh    = "weapons/vrsword/hitflesh";
		SndHitHard     = "weapons/vrsword/hitenergy";

		DamageType     = 'Nano';
		BaseDamage     = 200;
		MinSwingSpeed  = 20;  SpeedDamageFloor = 1.0;
		MaxSwingSpeed  = 60;  SpeedDamageCeil  = 1.0;   // speed-independent -- it cuts, it doesn't bludgeon
		BehaviorFlags  = BF_IGNOREARMOR | BF_DISMEMBER | BF_CAUTERIZE;
	}

	// Near-instant kill on any non-boss target: this is the one profile that needs
	// code beyond data, since "kill it outright" isn't expressible as a damage number.
	override int ModifyDamage(Actor victim, Actor inflictor, int damage, int hand)
	{
		if (victim && victim.health > 0 && !victim.bBoss && !victim.bNoDamage)
			return victim.health + 1;
		return damage;
	}
}

// --------------------------------------------------------------------------
//  Blade model-holder actors.
//  VRSword swaps its rendered blade at runtime via A_ChangeModel(BladeModel),
//  where BladeModel is one of these class names (set per BladeProfile above).
//  A_ChangeModel's first arg is a MODELDEF name, and MODELDEF Model blocks must
//  bind to a REAL actor class -- but the BladeProfiles are ': Object' data
//  classes and can't carry a model. These tiny actors exist ONLY to hang the
//  three blade meshes (modeldef.txt "Model VRSwordBlade*") so both the modeldef
//  parser and A_ChangeModel can resolve them. They are never spawned in-world.
// --------------------------------------------------------------------------
class VRSwordBladeSteel : Actor
{
	Default { +NOBLOCKMAP +NOINTERACTION +NOGRAVITY +DONTSPLASH +NOTELEPORT; }
	States { Spawn: VRSW A -1; Stop; }
}
class VRSwordBladePlasma : VRSwordBladeSteel {}
class VRSwordBladeNano  : VRSwordBladeSteel {}
