// --------------------------------------------------------------------------
//
// VRSword -- a single physical melee weapon whose cosmetic/combat identity is
// entirely data-driven via BladeProfile (vr_blade_profile.zs). The weapon
// owns motion tracking, swing gating, collision, and damage; swapping Steel
// / Lightsaber / Dragon's Tooth never touches this class, only which
// BladeProfile subclass BindBlade() instantiates.
//
// Swing detection uses Actor.GetHandVelocity(hand) -- already a correct,
// tic-smoothed, coordinate-remapped native in this engine (actor.zs:866),
// proven live in weaponshieldsaw.zs. This does NOT derive velocity from
// AttackPos deltas; that fallback is unnecessary now that the native exists.
//
// The blade's collision SEGMENT (for reach/hit-testing) is still built from
// AttackPos/OffhandPos + AttackAngle/Pitch, since GetHandVelocity gives a
// speed+direction for gating, not a fixed-length reach in front of the hand.
//
// MVP scope: broad-phase BlockThingsIterator + a closest-point-on-segment
// narrow phase, run once per tic. This is NOT swept substepping -- an
// extremely fast swing between two tics can still tunnel through a thin
// target. That upgrade (dossier: swept substepping / LineTrace precision)
// is deliberately deferred until this baseline is proven in-headset.
//
// Flatscreen fallback: the physical-swing Tick() mechanic only makes sense
// in VR (GetHandVelocity has no real controller feeding it when
// !player.PlayInVR, so it would just never gate). Every other melee weapon
// in this fork (weaponfist.zs, weaponshieldsaw.zs, stateprovider.zs) branches
// on !player.PlayInVR to provide a button-triggered LineAttack swing instead,
// and also gates the vanilla "turn to face the target" snap-turn behind
// (!player.PlayInVR || vanilla_melee_attack) -- matched here via
// FireFlatscreen(), so this weapon behaves like a normal Doom weapon when
// played without a headset, consistent with engine-wide convention.
//
// --------------------------------------------------------------------------

class VRSword : Weapon
{
	BladeProfile ActiveBlade;
	int BoundBladeIndex;
	bool Swinging;
	Array<Actor> HitThisSwing;

	Default
	{
		Weapon.SelectionOrder 4300;
		+WEAPON.NOAUTOAIM
		+WEAPON.NOALERT
		+WEAPON.MELEEWEAPON
		+WEAPON.NOAUTOSWITCHTO
		Tag "Sword";
		Obituary "was cut down by a VR Sword.";
		// "class:vrsword" is the functionally load-bearing tag: KeywordDispatcher lowercases
		// and prefixes the weapon's own class name the same way (keyword_dispatcher.cpp:259),
		// so this MUST match "VRSword" for KEYWORDS.json's "VRSword" -> parry_extent profile
		// to resolve via VR_CheckWeaponParry (hw_vrmodes.cpp:1194) -- native bullet/missile
		// deflection, already fully built and default-ON (vr_allow_weapon_parrying=true),
		// no ZScript deflection code needed. The rest are descriptive, not consumed by C++.
		Keywords "class:vrsword", "dmg:blade", "dmg:slash", "style:melee", "range:touch", "role:offense_defense", "trait:parry", "vibe:steel_and_plasma";
		Inventory.PickupMessage "Picked up the VR Sword!";
	}

	private void BindBlade(int idx)
	{
		class<BladeProfile> cls = "Blade_Steel";
		if (idx == 1) cls = "Blade_Lightsaber";
		else if (idx == 2) cls = "Blade_DragonsTooth";

		ActiveBlade = BladeProfile(new(cls));
		ActiveBlade.Setup();
		BoundBladeIndex = idx;

		if (ActiveBlade.BladeModel != '')
			A_ChangeModel(ActiveBlade.BladeModel);

		A_StopSound(CHAN_BODY);
		if (ActiveBlade.SndIdleHum.Length() > 0)
			A_StartSound(ActiveBlade.SndIdleHum, CHAN_BODY, CHANF_LOOPING);
	}

	private void CheckBladeCVar()
	{
		int idx = 0;
		CVar c = CVar.FindCVar("vr_sword_blade");
		if (c) idx = c.GetInt();
		if (!ActiveBlade || idx != BoundBladeIndex)
			BindBlade(idx);
	}

	// Point-to-segment distance, used for the narrow-phase collision test.
	private double PointSegmentDistance(vector3 p, vector3 a, vector3 b)
	{
		vector3 ab = b - a;
		double abLenSq = ab.x * ab.x + ab.y * ab.y + ab.z * ab.z;
		if (abLenSq <= 0.0001) return (p - a).Length();
		double t = ((p.x - a.x) * ab.x + (p.y - a.y) * ab.y + (p.z - a.z) * ab.z) / abLenSq;
		t = clamp(t, 0.0, 1.0);
		vector3 closest = a + ab * t;
		return (p - closest).Length();
	}

	private void PlayHitFX(Actor victim, int dmg)
	{
		if (!(ActiveBlade.BehaviorFlags & BF_CAUTERIZE))
			victim.TraceBleed(dmg, self);
		if (ActiveBlade.SndHitFlesh.Length() > 0)
			A_StartSound(ActiveBlade.SndHitFlesh, CHAN_AUTO);
	}

	// ZELDA MODE: like the Master Sword, at FULL HEALTH a swing/thrust fires a sword beam --
	// a plasma-typed energy projectile tinted to the current blade's colour. Opt-in via
	// vr_sword_zelda_mode (VR Weapon Options). Fires from both the physical VR swing (Tick)
	// and the flatscreen Fire button. Below full health it does nothing, so full HP is a real,
	// visible reward you feel the moment you take a scratch.
	void FireZeldaBeam(vector3 origin, double ang, double pit)
	{
		if (owner == null || owner.player == null || ActiveBlade == null) return;
		CVar zc = CVar.FindCVar("vr_sword_zelda_mode");
		if (!zc || !zc.GetBool()) return;
		if (owner.health < owner.GetMaxHealth()) return;   // full-health gate (the Zelda rule)

		let beam = VRSwordBeam(Actor.Spawn("VRSwordBeam", origin));
		if (!beam) return;
		beam.target = owner;
		beam.angle  = ang;
		beam.pitch  = pit;
		beam.Vel3DFromAngle(beam.Speed, ang, pit);
		beam.SetDamage(max(6, ActiveBlade.BaseDamage / 2));   // half the blade's melee power, plasma-typed
		// SDF beam colour from the blade's GlowColor (steel has none -> icy white). Brightened for Add bloom.
		Color gc = ActiveBlade.GlowColor;
		vector3 bc = (gc.a > 0) ? (gc.r / 255.0, gc.g / 255.0, gc.b / 255.0) : (0.75, 0.9, 1.0);
		beam.beamCol = bc * 1.6;
		A_StartSound("weapons/plasmaf", CHAN_WEAPON);
	}

	// Physical-swing detection. Meaningless without a real controller feeding
	// GetHandVelocity, so this only runs in VR -- flatscreen play uses the
	// button-triggered A_VRSwordFireFlatscreen() attack instead (Fire state),
	// same as every other melee weapon in this fork.
	override void Tick()
	{
		Super.Tick();

		if (owner == null || owner.player == null || !owner.player.PlayInVR || ActiveBlade == null)
			return;

		int hand = bOffhandWeapon ? 1 : 0;
		vector3 base = bOffhandWeapon ? owner.OffhandPos : owner.AttackPos;
		double ang    = bOffhandWeapon ? owner.OffhandAngle : owner.AttackAngle;
		double pit    = bOffhandWeapon ? owner.OffhandPitch : owner.AttackPitch;

		// Standard angle+pitch -> forward-vector conversion (cos/sin are degree-based
		// in ZScript; positive pitch looks down, hence -sin(pit) for Z).
		vector3 dir = (cos(pit) * cos(ang), cos(pit) * sin(ang), -sin(pit));
		vector3 tip = base + dir * ActiveBlade.BladeLength;

		double tipSpeed = owner.GetHandVelocity(hand).Length();

		double swingOn = 35.0, swingOff = 18.0;
		CVar c;
		c = CVar.FindCVar("vr_sword_swing_on");  if (c) swingOn  = c.GetFloat();
		c = CVar.FindCVar("vr_sword_swing_off"); if (c) swingOff = c.GetFloat();

		if (!Swinging && tipSpeed > swingOn)
		{
			Swinging = true;
			HitThisSwing.Clear();
			if (ActiveBlade.SndSwing.Length() > 0)
				A_StartSound(ActiveBlade.SndSwing, CHAN_WEAPON);
			FireZeldaBeam(tip, ang, pit);   // Zelda mode: full-health swing launches a sword beam
		}
		else if (Swinging && tipSpeed < swingOff)
		{
			Swinging = false;
		}

		if (!Swinging)
			return;

		// Broad phase: sphere query centered on the segment midpoint.
		vector3 mid = (base + tip) * 0.5;
		double halfLen = ActiveBlade.BladeLength * 0.5;
		double checkRadius = halfLen + ActiveBlade.BladeWidth + 32;

		BlockThingsIterator it = BlockThingsIterator.CreateFromPos(mid.x, mid.y, mid.z, checkRadius, checkRadius, false);
		while (it.Next())
		{
			Actor victim = it.thing;
			if (victim == null || victim == owner || victim == self) continue;
			if (!victim.bIsMonster && !victim.bShootable) continue;
			if (victim.bCorpse || victim.health <= 0) continue;
			if (HitThisSwing.Find(victim) != HitThisSwing.Size()) continue; // already hit this swing

			// Narrow phase: closest point on the blade segment vs. the victim's center.
			double dist = PointSegmentDistance(victim.pos + (0, 0, victim.Height * 0.5), base, tip);
			if (dist > victim.radius + ActiveBlade.BladeWidth) continue;

			HitThisSwing.Push(victim);

			int dmg = int(ActiveBlade.BaseDamage * ActiveBlade.DamageScaleForSpeed(tipSpeed));
			dmg = ActiveBlade.ModifyDamage(victim, self, dmg, hand);

			int dmgFlags = 0;
			if (ActiveBlade.BehaviorFlags & BF_IGNOREARMOR) dmgFlags |= DMG_NO_ARMOR;

			victim.DamageMobj(self, owner, dmg, ActiveBlade.DamageType, dmgFlags);
			PlayHitFX(victim, dmg);
		}
	}

	States
	{
	Ready:
		VRSW A 0 { invoker.CheckBladeCVar(); }
		VRSW A 1 A_WeaponReady(WRF_ALLOWRELOAD);
		Loop;
	Deselect:
		VRSW A 1 A_Lower;
		Loop;
	Select:
		VRSW A 1 A_Raise;
		Loop;
	// Button-triggered swing -- available in BOTH VR and flatscreen, matching every other
	// melee weapon in this fork (Fist/A_Punch fires on button press regardless of PlayInVR;
	// only the post-hit auto-turn is conditional). In VR this supplements the physical swing
	// in Tick(); in flatscreen it is the ONLY attack path, since GetHandVelocity never gates.
	Fire:
		VRSW A 1 A_VRSwordFireFlatscreen();
		Goto Ready;
	Spawn:
		VRSW A -1;
		Stop;
	}

	// Aim first (dry -- AimLineAttack deals no damage), so BladeProfile.ModifyDamage can see
	// the actual target (Dragon's Tooth checks victim.health) before the real hit is dealt in
	// one LineAttack call -- matches weaponfist.zs A_Punch's two-call aim-then-attack shape.
	action void A_VRSwordFireFlatscreen()
	{
		if (invoker.ActiveBlade == null) return;

		int laflags = LAF_ISMELEEATTACK;
		int alflags = invoker.bOffhandWeapon ? ALF_ISOFFHAND : 0;
		if (invoker.bOffhandWeapon) laflags |= LAF_ISOFFHAND;

		double range = MeleeRange + MELEEDELTA;
		FTranslatedLineTarget t;
		double pitch = AimLineAttack(angle, range, t, 0., ALF_CHECK3D | alflags);

		int dmg = int(invoker.ActiveBlade.BaseDamage * invoker.ActiveBlade.SpeedDamageCeil);
		if (t.linetarget)
			dmg = invoker.ActiveBlade.ModifyDamage(t.linetarget, invoker, dmg, invoker.bOffhandWeapon ? 1 : 0);

		LineAttack(angle, range, pitch, dmg, invoker.ActiveBlade.DamageType, "BulletPuff", laflags, t);

		if (invoker.ActiveBlade.SndSwing.Length() > 0)
			A_StartSound(invoker.ActiveBlade.SndSwing, CHAN_WEAPON);

		// Zelda mode: full-health Fire launches a sword beam along the aim (self = pawn here).
		invoker.FireZeldaBeam(pos + (0, 0, height * 0.5), angle, pitch);

		if (t.linetarget)
			invoker.PlayHitFX(t.linetarget, dmg);

		// Vanilla melee convention (weaponfist.zs A_Punch, stateprovider.zs, etc.): snap the
		// player to face the hit target, but only outside VR unless the player opted back in.
		if ((player != null && !player.PlayInVR || vanilla_melee_attack) && t.linetarget)
		{
			angle = t.angleFromSource;
			if (player != null) player.resetDoomYaw = true;
		}
	}
}

// The Zelda sword beam: a fast plasma-typed energy projectile fired by VRSword.FireZeldaBeam
// when the wielder is at full health. Damage + colour are set per-blade by the spawner
// (SetDamage / SetShade). Uses the stock plasma sprite (guaranteed IWAD asset, no dependency)
// with additive blend so it reads as a glowing energy blade-bolt.
// The Zelda sword beam: a projectile that LOOKS LIKE A GLOWING SWORD tumbling end-over-end
// through the air. Drawn entirely with math -- the engine-resident SDF sprite shader
// (SIGL -> vr_sdf_procedural.fp), stretched thin-and-long into a blade and spun via +ROLLSPRITE,
// camera-facing (+FORCEXYBILLBOARD) so it always reads as a blade from any angle. Colour + damage
// are set per blade by FireZeldaBeam. Trails a fading SDF comet streak. No sprite/model assets,
// no Radiance -- pure SDF math.
class VRSwordBeam : Actor
{
	vector3 beamCol;                 // 0..1 rgb (brightened), set by the spawner
	double  spinAng;                 // running arrow-spin angle about the flight axis
	const   BEAM_PX  = 64.0;
	const   BEAM_LEN = 58.0;         // blade length along flight (tip-to-tail)
	const   BEAM_WID = 11.0;         // blade width

	Default
	{
		Radius 6;
		Height 8;
		Speed 42;
		Projectile;
		+THRUGHOST +BRIGHT +NOGRAVITY
		+FLATSPRITE +ROLLCENTER
		RenderStyle "Add";
		Alpha 1.0;
		Damage 12;                 // fallback; FireZeldaBeam calls SetDamage() per blade
		DamageType "Plasma";
		SeeSound "weapons/plasmaf";
		DeathSound "weapons/plasmax";
		Obituary "was struck down by a flying sword beam.";
	}

	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		msdf_enabled = 512;              // flat SDF rect -> stretched = a glowing blade
		msdf_glitch  = 0.12;             // faint energy shimmer
		if (beamCol.Length() < 0.01) beamCol = (0.75, 0.9, 1.0);   // icy-white default
	}

	// Orient the flat SDF quad so its LONG axis points along 'fwd' (tip-first, straight flight)
	// and its face-normal = 'faceN' (which we spin about fwd for the arrow roll). Same flat-quad
	// orient math as XR_GravityPathNode, minus the move -- a projectile owns its own position.
	void OrientArrow(vector3 fwd, vector3 faceN)
	{
		double horiz = sqrt(faceN.x * faceN.x + faceN.y * faceN.y);
		double yaw = (horiz > 0.0001) ? VectorAngle(faceN.x, faceN.y) : angle;
		Angle = yaw;
		Pitch = atan2(horiz, faceN.z);

		double ryaw = yaw - 90.0;
		vector3 baseRight = (cos(ryaw), sin(ryaw), 0.0);
		double tdotn = fwd.x * faceN.x + fwd.y * faceN.y + fwd.z * faceN.z;
		vector3 tproj = (fwd.x - faceN.x * tdotn, fwd.y - faceN.y * tdotn, fwd.z - faceN.z * tdotn);
		double tl = tproj.Length();
		if (tl > 0.0001)
		{
			tproj /= tl;
			vector3 c = (baseRight.y * tproj.z - baseRight.z * tproj.y,
						 baseRight.z * tproj.x - baseRight.x * tproj.z,
						 baseRight.x * tproj.y - baseRight.y * tproj.x);
			double cdn = c.x * faceN.x + c.y * faceN.y + c.z * faceN.z;
			double drt = baseRight.x * tproj.x + baseRight.y * tproj.y + baseRight.z * tproj.z;
			Roll = atan2(cdn, drt);
		}
		Scale = (BEAM_WID / BEAM_PX, BEAM_LEN / BEAM_PX);
	}

	override void Tick()
	{
		// flight direction = the tip direction (straight, no tumble)
		vector3 v = Vel;
		double vl = v.Length();
		vector3 fwd = (vl > 0.01) ? v / vl : (cos(pitch) * cos(angle), cos(pitch) * sin(angle), -sin(pitch));

		// orthonormal basis perpendicular to fwd, then a face-normal that SPINS about fwd = arrow roll
		vector3 up0 = (abs(fwd.z) < 0.9) ? (0.0, 0.0, 1.0) : (1.0, 0.0, 0.0);
		vector3 rgt = (fwd.y * up0.z - fwd.z * up0.y, fwd.z * up0.x - fwd.x * up0.z, fwd.x * up0.y - fwd.y * up0.x);
		double rl = rgt.Length(); if (rl > 0.0001) rgt /= rl;
		vector3 upp = (rgt.y * fwd.z - rgt.z * fwd.y, rgt.z * fwd.x - rgt.x * fwd.z, rgt.x * fwd.y - rgt.y * fwd.x);
		spinAng += 34.0;                                        // arrow-spin rate, deg/tic
		vector3 faceN = rgt * cos(spinAng) + upp * sin(spinAng);

		OrientArrow(fwd, faceN);
		msdf_color = beamCol * (1.35 + 0.35 * sin(level.maptime * 40.0));

		// glowing comet trail: a fading copy of the blade at this pose
		let t = VRSwordBeamTrail(Actor.Spawn("VRSwordBeamTrail", pos));
		if (t) { t.trailCol = beamCol; t.angle = angle; t.pitch = pitch; t.roll = roll; t.scale = scale; }

		Super.Tick();
	}

	States
	{
	Spawn:
		SIGL A 1 Bright;
		Loop;
	Death:
		SIGL A 6 Bright;   // brief bloom on impact
		Stop;
	}
}

// Fading SDF after-image dropped by the beam each tic -- the glowing-blade comet streak.
// Keeps the beam's orientation/scale (copied at spawn) and just dims out.
class VRSwordBeamTrail : Actor
{
	vector3 trailCol;
	int life;

	Default
	{
		+NOBLOCKMAP +NOGRAVITY +NOINTERACTION +DONTSPLASH +CLIENTSIDEONLY +NOTIMEFREEZE
		+BRIGHT +FLATSPRITE +ROLLCENTER
		RenderStyle "Add";
		Radius 1;
		Height 1;
	}

	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		msdf_enabled = 512;
		life = 6;
	}

	override void Tick()
	{
		if (life-- <= 0) { Destroy(); return; }
		double f = double(life) / 6.0;
		msdf_color = trailCol * f;
		Alpha = f * 0.7;
	}

	States
	{
	Spawn:
		SIGL A 1 Bright;
		Wait;
	}
}
