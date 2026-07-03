// --------------------------------------------------------------------------
//
// WhipProfile -- pure-data cosmetic/combat definition for XRWhip, the exact
// sibling of BladeProfile (vr_blade_profile.zs). XRWhip owns the rope sim,
// crack detection, two-hand momentum, collision and the grapple secondary;
// a WhipProfile only supplies what makes one whip different from another.
// Swapping Leather / Ember / Tesla never touches XRWhip -- see BindWhip().
//
// The whip's identity is Indiana Jones first: a mass-tapered leather thong
// whose tip is driven supersonic by the sim (the CRACK). Elemental affixes
// (Ember, Tesla) ride the same body via OnCrack(), the one code hook a
// profile may add beyond data -- mirrors BladeProfile.ModifyDamage().
//
// Numbers below are starting estimates for in-headset tuning, not finished
// balance. Speeds are in MAP UNITS PER TIC (vr_vunits_per_meter=34, 35 tics/s
// => 1 unit/tic ~= 1.03 m/s, Mach 1 ~= 333 units/tic -- the true boom).
//
// --------------------------------------------------------------------------

enum EWhipBehaviorFlags
{
	WF_DISARM  = 1,   // a confirmed crack briefly staggers the target (Pain), Indy-style
	WF_IGNITE  = 2,   // OnCrack applies a fire follow-up in a radius around the tip
	WF_CHAIN   = 4,   // OnCrack arcs to nearby targets (Tesla)
	WF_PULL    = 8,   // crack knockback is INWARD (toward the wielder) instead of away
}

class WhipProfile : Object
{
	string ProfileName;

	// ---- Visual ----
	name   WhipModel;         // MODELDEF entry for the rigged IQM handle (Tier 2); '' => glow-panel rope only
	double Reach;             // total thong length, map units -- drives node spacing and reach
	double CordWidth;         // map units -- collision half-width + base glow radius
	Color  CordColor;         // rope glow tint (NO dynamic light -- glow panel / GITD only)
	Color  CrackColor;        // sonic-boom flash tint at the tip

	// ---- Audio (SNDINFO by FULL path; MONO only -- stereo is silent on desktop) ----
	string SndCreak;          // idle leather creak (looped)
	string SndWhoosh;         // fast swing, pre-crack
	string SndCrack;          // the supersonic snap
	string SndHitFlesh;

	// ---- Combat ----
	name   DamageType;
	int    BaseDamage;
	double MinSpeed, SpeedFloor;   // tip speed below MinSpeed: damage = BaseDamage*SpeedFloor
	double MaxSpeed, SpeedCeil;    // tip speed at/above MaxSpeed: damage = BaseDamage*SpeedCeil
	double CrackSpeed;             // tip speed that triggers a crack at all (units/tic)
	double Knockback;              // impulse applied to a cracked target
	int    BehaviorFlags;

	virtual void Setup() {}

	// The one code hook a profile may add beyond data. Default: no change.
	virtual int ModifyDamage(Actor victim, Actor inflictor, int damage, int hand)
	{
		return damage;
	}

	// Elemental follow-up, fired once per confirmed crack at the tip position.
	// Base profile does nothing -- pure leather is all momentum.
	// 'play' scope: overrides call DamageMobj / AddGlowPanel (play functions), so this hook
	// runs in play context (WhipProfile : Object is otherwise data-scoped). Overrides inherit it.
	virtual play void OnCrack(Actor whip, vector3 tip, double tipSpeed) {}

	double DamageScaleForSpeed(double tipSpeed)
	{
		double t = clamp((tipSpeed - MinSpeed) / max(1.0, MaxSpeed - MinSpeed), 0.0, 1.0);
		return SpeedFloor + (SpeedCeil - SpeedFloor) * t;
	}
}

// ---- Leather: the Indiana Jones default. Heavy knockback, staggers, no element. --------------
class Whip_Leather : WhipProfile
{
	override void Setup()
	{
		ProfileName = "Bullwhip";
		WhipModel   = '';                       // glow-panel rope until the rigged IQM lands
		// 300 map units (~8.8m @ 34u/m) -- matches the Tier-2 rigged model's true bind-pose
		// length EXACTLY (models/weapons/xrwhip/whip_rigged.iqm, 20 bones x 15.0 map units,
		// independently byte-verified). Bumped from 190 for two reasons: (1) grappling-hook
		// reach per direct request, and (2) DriveModelBones() drives ROTATION only with FIXED
		// per-bone translation -- if Reach != the model's bind length, the rigid-skinned model
		// visually overshoots/undershoots the sim's real tip. Keep these in lockstep.
		Reach       = 300;
		CordWidth   = 3.0;
		CordColor   = Color(255, 120, 82, 40);  // warm tan leather
		CrackColor  = Color(255, 255, 245, 210);// hot white snap

		SndCreak    = "weapons/xrwhip/leather/creak";
		SndWhoosh   = "weapons/xrwhip/leather/whoosh";
		SndCrack    = "weapons/xrwhip/leather/crack";
		SndHitFlesh = "weapons/xrwhip/leather/hit";

		DamageType  = 'Melee';
		BaseDamage  = 22;
		MinSpeed    = 70;  SpeedFloor = 0.5;
		MaxSpeed    = 240; SpeedCeil  = 2.6;     // reward a genuinely fast swing
		CrackSpeed  = 95;
		Knockback   = 14.0;
		BehaviorFlags = WF_DISARM;
	}
}

// ---- Ember: enchanted fire whip. The crack ignites a small radius. --------------------------
class Whip_Ember : WhipProfile
{
	override void Setup()
	{
		ProfileName = "Ember Lash";
		WhipModel   = '';
		Reach       = 300;    // matches the Tier-2 model's bind length -- see Whip_Leather
		CordWidth   = 3.0;
		CordColor   = Color(255, 255, 96, 20);  // glowing orange braid
		CrackColor  = Color(255, 255, 170, 60);

		SndCreak    = "weapons/xrwhip/ember/hum";
		SndWhoosh   = "weapons/xrwhip/ember/whoosh";
		SndCrack    = "weapons/xrwhip/ember/crack";
		SndHitFlesh = "weapons/xrwhip/ember/sear";

		DamageType  = 'Fire';
		BaseDamage  = 20;
		MinSpeed    = 70;  SpeedFloor = 0.7;
		MaxSpeed    = 240; SpeedCeil  = 2.2;
		CrackSpeed  = 90;
		Knockback   = 10.0;
		BehaviorFlags = WF_DISARM | WF_IGNITE;
	}

	override void OnCrack(Actor whip, vector3 tip, double tipSpeed)
	{
		if (whip == null) return;

		// Fire burst: a bright disc flash + a small radius sear around the tip.
		whip.level.AddGlowPanel(Color(255, 255, 150, 40), 46.0, tip.x, tip.y, tip.z, 15, 1.0, 0.0, 0.0, 0);

		double burnR = 56.0;
		BlockThingsIterator it = BlockThingsIterator.CreateFromPos(tip.x, tip.y, tip.z, burnR, burnR, false);
		while (it.Next())
		{
			Actor v = it.thing;
			if (v == null || v == whip || !v.bShootable || v.health <= 0 || v.bCorpse) continue;
			if ((v.pos + (0, 0, v.Height * 0.5) - tip).Length() > burnR + v.radius) continue;
			v.DamageMobj(whip, whip.target, 8, 'Fire');
		}
	}
}

// ---- Tesla: enchanted lightning whip. The crack arcs to nearby targets. ----------------------
class Whip_Tesla : WhipProfile
{
	override void Setup()
	{
		ProfileName = "Tesla Coil";
		WhipModel   = '';
		Reach       = 300;    // matches the Tier-2 model's bind length -- see Whip_Leather
		CordWidth   = 2.6;
		CordColor   = Color(255, 90, 200, 255); // electric cyan
		CrackColor  = Color(255, 210, 240, 255);

		SndCreak    = "weapons/xrwhip/tesla/hum";
		SndWhoosh   = "weapons/xrwhip/tesla/whoosh";
		SndCrack    = "weapons/xrwhip/tesla/crack";
		SndHitFlesh = "weapons/xrwhip/tesla/zap";

		DamageType  = 'Electric';
		BaseDamage  = 18;
		MinSpeed    = 70;  SpeedFloor = 0.8;
		MaxSpeed    = 240; SpeedCeil  = 2.0;
		CrackSpeed  = 90;
		Knockback   = 8.0;
		BehaviorFlags = WF_CHAIN;
	}

	override void OnCrack(Actor whip, vector3 tip, double tipSpeed)
	{
		if (whip == null) return;

		// Arc to up to 3 nearby targets, drawing a lightning-bolt glow panel to each
		// (wgType 26 = lightning bolt in the neon shader library) plus a shock hit.
		double arcR = 180.0;
		int arcsLeft = 3;

		BlockThingsIterator it = BlockThingsIterator.CreateFromPos(tip.x, tip.y, tip.z, arcR, arcR, false);
		while (it.Next() && arcsLeft > 0)
		{
			Actor v = it.thing;
			if (v == null || v == whip || !v.bShootable || v.health <= 0 || v.bCorpse) continue;

			vector3 c = v.pos + (0, 0, v.Height * 0.5);
			vector3 d = c - tip;
			if (d.Length() > arcR) continue;

			// Bolt from tip toward the target: dir packed as (dirX,dirY), reach in counter.
			double a = atan2(d.y, d.x);
			whip.level.AddGlowPanel(Color(255, 190, 230, 255), d.Length(), tip.x, tip.y, tip.z, 26, 1.0, cos(a), sin(a), int(d.Length()));
			v.DamageMobj(whip, whip.target, 10, 'Electric');
			arcsLeft--;
		}
	}
}
