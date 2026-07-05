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
		Weapon.SlotNumber 9;   // [XR] VR grab-tool slot (with IceHook + XRWhip); mirrors DoomPlayer's Player.WeaponSlot 9
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
		Keywords "class:vrsword", "grip:hilt", "dmg:blade", "dmg:slash", "style:melee", "range:touch", "role:offense_defense", "trait:parry", "vibe:steel_and_plasma";
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
	// AltFire: HURL the blade -- a glowing SDF sword that tumbles end-over-end downrange,
	// cuts what it passes, then boomerangs back to your hand. The weapon itself stays equipped
	// (the thrown blade is a projected copy), so you can't lose it.
	AltFire:
		VRSW A 1 A_VRSwordThrow();
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

	// AltFire throw: hurl the current blade as a boomerang ThrownVRSword. Aims along the VR hand
	// (AttackPos/Angle/Pitch) in headset, along the view on flatscreen. The equipped weapon is
	// never removed, so it always comes back even if the projectile is destroyed.
	action void A_VRSwordThrow()
	{
		if (invoker.ActiveBlade == null) return;
		CVar throwCV = CVar.FindCVar("vr_sword_throw");
		if (throwCV && !throwCV.GetBool()) return;   // throwing disabled -> AltFire is a no-op
		CVar retCV = CVar.FindCVar("vr_sword_throw_returns");
		bool doReturn = !retCV || retCV.GetBool();

		int hand = invoker.bOffhandWeapon ? 1 : 0;
		vector3 origin; double ang, pit;
		if (player != null && player.PlayInVR)
		{
			origin = invoker.bOffhandWeapon ? OffhandPos : AttackPos;
			ang    = invoker.bOffhandWeapon ? OffhandAngle : AttackAngle;
			pit    = invoker.bOffhandWeapon ? OffhandPitch : AttackPitch;
		}
		else
		{
			origin = pos + (0, 0, height * 0.5);
			ang = angle; pit = pitch;
		}

		let tsw = ThrownVRSword(Actor.Spawn("ThrownVRSword", origin));
		if (!tsw) return;
		tsw.angle = ang; tsw.pitch = pit;
		tsw.Vel3DFromAngle(tsw.Speed, ang, pit);

		Color gc = invoker.ActiveBlade.GlowColor;
		vector3 bc = (gc.a > 0) ? (gc.r / 255.0, gc.g / 255.0, gc.b / 255.0) : (0.8, 0.86, 1.0);
		int throwDmg = int(invoker.ActiveBlade.BaseDamage * invoker.ActiveBlade.SpeedDamageCeil);
		tsw.Launch(self, hand, throwDmg, invoker.ActiveBlade.DamageType,
		           (invoker.ActiveBlade.BehaviorFlags & BF_IGNOREARMOR) != 0, bc * 1.5, 55, doReturn);

		if (invoker.ActiveBlade.SndSwing.Length() > 0)
			A_StartSound(invoker.ActiveBlade.SndSwing, CHAN_WEAPON);
	}
}

// The thrown VR sword: a glowing SDF blade that TUMBLES END-OVER-END through the air (camera-
// facing so it always reads as a spinning blade), cuts any monster it passes on the way out, then
// homes back to the throwing hand like a boomerang. NOCLIP + manual distance hit-detection so it
// can never stall on a wall (same trick as ThrownChainsaw). SDF-drawn (SIGL) -- no assets, no
// Radiance. The VRSword weapon stays equipped the whole time, so a thrown blade is never lost.
class ThrownVRSword : Actor
{
	vector3 bladeCol;
	Actor   thrower;
	int     hand;
	int     dmg;
	Name    dmgType;
	bool    ignoreArmor;
	bool    doReturn;
	bool    returning;
	int     life, maxLife;
	double  homeR;
	Array<Actor> alreadyHit;

	Default
	{
		+NOGRAVITY +NOCLIP +NOBLOCKMAP +DONTSPLASH +NOTIMEFREEZE
		+BRIGHT +FORCEXYBILLBOARD +ROLLSPRITE +ROLLCENTER
		RenderStyle "Add";
		Radius 14;
		Height 14;
		Speed 30;
	}

	void Launch(Actor who, int inHand, int d, Name dt, bool noArmor, vector3 col, int lifeTics, bool returns)
	{
		thrower = who; master = who; target = who;
		hand = inHand; dmg = d; dmgType = dt; ignoreArmor = noArmor;
		bladeCol = col; maxLife = lifeTics; life = lifeTics; homeR = 54.0; doReturn = returns;
	}

	// aim velocity straight at a world point (copied from ThrownChainsaw.Steer).
	void Steer(vector3 dest, double spd = -1)
	{
		if (spd < 0) spd = Speed;
		vector3 d = dest - pos;
		double h = d.xy.Length();
		if (h + abs(d.z) < 1) return;
		Vel3DFromAngle(spd, atan2(d.y, d.x), -atan2(d.z, h));
	}

	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		msdf_enabled = 512;              // stretched SDF rect = glowing blade
		msdf_glitch  = 0.12;
		Scale = (0.16, 1.05);            // thin x, long y
		if (bladeCol.Length() < 0.01) bladeCol = (0.8, 0.86, 1.0);
	}

	override void Tick()
	{
		// spin end-over-end (a thrown blade cartwheels) + glow
		Roll += 30.0;
		msdf_color = bladeCol * (1.3 + 0.3 * sin(level.maptime * 40.0));
		let tr = VRSwordBeamTrail(Actor.Spawn("VRSwordBeamTrail", pos));
		if (tr) { tr.trailCol = bladeCol; tr.roll = roll; tr.scale = scale; }

		if (life-- <= 0)
		{
			if (doReturn) returning = true;
			else { Destroy(); return; }   // no-return mode: flies out, cuts, vanishes
		}

		if (!returning)
		{
			// cut anything we pass (manual distance test since we're NOCLIP)
			BlockThingsIterator it = BlockThingsIterator.CreateFromPos(pos.x, pos.y, pos.z, radius + 40, radius + 40, false);
			while (it.Next())
			{
				Actor v = it.thing;
				if (v == null || v == self || v == thrower) continue;
				if (!v.bIsMonster && !v.bShootable) continue;
				if (v.bCorpse || v.health <= 0) continue;
				if (alreadyHit.Find(v) != alreadyHit.Size()) continue;
				vector3 c = v.pos + (0, 0, v.Height * 0.5);
				if ((c - pos).Length() > radius + v.radius + 12) continue;

				alreadyHit.Push(v);
				int df = ignoreArmor ? DMG_NO_ARMOR : 0;
				v.DamageMobj(self, thrower, dmg, dmgType, df);
				if ((v.pos - pos).Length() < radius + v.radius) A_StartSound("weapons/vrsword/hithard", CHAN_WEAPON);
			}
		}
		else
		{
			if (!thrower) thrower = players[consoleplayer].mo;
			if (!thrower) { Destroy(); return; }
			vector3 home = hand ? thrower.OffhandPos : thrower.AttackPos;
			Steer(home, Speed * 1.5);                       // returns faster than it left
			if ((home - pos).Length() <= homeR) { Destroy(); return; }   // caught
		}

		Super.Tick();
	}

	States
	{
	Spawn:
		SIGL A 1 Bright;
		Loop;
	}
}

// The Zelda sword beam: a fast plasma-typed energy projectile fired by VRSword.FireZeldaBeam
// when the wielder is at full health. Damage + colour are set per-blade by the spawner
// (SetDamage / SetShade). Uses the stock plasma sprite (guaranteed IWAD asset, no dependency)
// with additive blend so it reads as a glowing energy blade-bolt.
// The Zelda sword beam: a projectile that LOOKS LIKE A GLOWING SWORD flying STRAIGHT, tip-first,
// SPINNING ABOUT ITS OWN AXIS like an arrow (no end-over-end tumble). Drawn entirely with math --
// the engine-resident SDF sprite shader (SIGL -> vr_sdf_procedural.fp), a thin-and-long SDF blade
// whose long axis is manually oriented (FLATSPRITE Angle/Pitch/Roll) along its velocity, with its
// flat face spun around the flight axis each tic (the arrow roll). Colour + damage are set per
// blade by FireZeldaBeam. Trails a fading SDF comet streak. No sprite/model assets, no Radiance.
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
