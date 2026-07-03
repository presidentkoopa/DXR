// --------------------------------------------------------------------------
//
// XRWhip -- a physics VR bullwhip. A mass-tapered Verlet rope hangs from the
// tracked hand; a fast swing drives the light tip supersonic and it CRACKS.
// Sibling in spirit to VRSword (vr_sword.zs): the weapon owns all motion,
// simulation, collision and damage, and its cosmetic/elemental identity is
// data-driven by WhipProfile (vr_whip_profile.zs).
//
//   PRIMARY  (Fire)     -- "lash": injects a forward impulse into the tip so
//                          a directed crack is available on demand, on top of
//                          whatever your real swing is already doing.
//   TWO-HAND            -- bring the off hand near the handle and its velocity
//                          feeds energy into the whole chain: bigger cracks,
//                          lower crack threshold, +damage (Castlevania IV).
//   SECONDARY (AltFire) -- GRAPPLE: LineTrace from the hand, context-picks a mode:
//                          * REEL  -- snag low/level geometry, fly yourself to it.
//                          * SWING -- snag geometry high above you, pendulum on a
//                                     taut line; release keeps your tangential speed
//                                     so you launch off (Indy gap-swing).
//                          * YANK  -- snag a monster, rip it to you (or reel toward a
//                                     boss too heavy to move). WF_DISARM staggers +
//                                     stuns it on the pull.
//                          Hold to keep the line, release to let go.
//
// RENDERING: the rope is drawn with in-world glow panels (level.AddGlowPanel,
// the same neon-billboard path PlasmaBeam uses) -- zero sprite assets, fits
// the GITD aesthetic. The rigged leather IQM model is the Tier-2 upgrade
// (procedural bones, see Desktop\Documentation\DoomXR_Whip_IQM_Rigging_Patch_Spec.md);
// this file is the playable Tier-1 that needs no engine patch.
//
// Speeds are MAP UNITS PER TIC. vr_vunits_per_meter=34, 35 tics/s =>
// 1 unit/tic ~= 1.03 m/s, Mach 1 ~= 333 units/tic (WHIP_MACH1 -- the true boom).
//
// SUGGESTED CVARINFO (optional -- code falls back if absent):
//   user int vr_whip_profile = 0;   // 0 Leather, 1 Ember, 2 Tesla
//
// SUGGESTED SNDINFO (MONO, full path -- missing sounds simply don't play):
//   weapons/xrwhip/leather/{creak,whoosh,crack,hit}  (+ ember/, tesla/ sets)
//
// MVP scope, same honesty as vr_sword: crack collision is a per-crack sweep of
// the tip segment (broad BlockThingsIterator + closest-point narrow phase),
// not swept substepping -- an absurdly fast tip between two tics can still skip
// a thin target. Grapple originates from the player + VR hand aim, not a true
// per-hand ray. Both upgrades are deferred until this is proven in-headset.
//
// --------------------------------------------------------------------------

// One rope node. Object-derived (mirrors BladeProfile) so it can live in a
// dynamic Array<> -- ZScript dynamic arrays can't hold vector3 directly.
class XRWhipNode : Object
{
	vector3 pos;
	vector3 prev;
	double  invMass;   // 0 = pinned (the handle); larger = lighter (the tip)
	double  radius;    // taper, drives mass and glow size
}

// TIER 2 -- world-space carrier for the rigged whip IQM (models/weapons/xrwhip/whip_rigged.iqm,
// 21 bones). Spawned by XRWhip only when the vr_whip_model CVar is on; XRWhip parks it at the
// hand and drives its bones each tic from the Verlet sim via SetModelBonePose. Invisible sprite
// -- the model itself is the whole visual. A_ChangeModel attaches the modeldef 'XRWhipRigged'
// as a per-actor override, and SetModelUseProceduralPose(true) tells the render path to read our
// per-bone TRS buffer instead of the (nonexistent) baked animation.
class XRWhipModel : Actor
{
	Default
	{
		+NOBLOCKMAP +NOGRAVITY +NOINTERACTION +DONTSPLASH +NOTIMEFREEZE
		Radius 1;
		Height 1;
	}
	States
	{
	Spawn:
		TNT1 A 0 NoDelay
		{
			A_ChangeModel('XRWhipRigged');
			SetModelUseProceduralPose(true);
		}
		TNT1 A -1;
		Stop;
	}
}

class XRWhip : Weapon
{
	// ---- sim tunables ----
	const WHIP_MAXNODES      = 16;
	const WHIP_GRAV          = 0.55;    // rope sag, units/tic^2
	const WHIP_DAMP          = 0.985;   // air drag on the chain
	const WHIP_ITERS         = 8;       // constraint relaxation passes
	const WHIP_TWOHAND_COUPLE= 0.16;    // how much off-hand velocity feeds the chain
	const WHIP_TWOHAND_R     = 48.0;    // off-hand within this of the handle => two-handing
	const WHIP_MACH1         = 333.0;   // supersonic threshold => the big boom
	const WHIP_CRACK_CD      = 9;       // tics between cracks
	const WHIP_LASH_IMPULSE  = 130.0;   // Fire-button tip impulse

	// ---- grapple tunables ----
	const WHIP_GRAPPLE_RANGE = 900.0;
	const WHIP_GRAPPLE_TIME  = 140;     // ~4s max hold
	const WHIP_REEL_SPEED    = 22.0;
	const WHIP_YANK_SPEED    = 18.0;
	const WHIP_SWING_MINRISE = 40.0;    // anchor this far above you => pendulum swing, not reel
	const WHIP_SWING_GRAV    = 0.9;     // self-applied gravity while swinging

	const GM_NONE  = 0;
	const GM_REEL  = 1;
	const GM_YANK  = 2;
	const GM_SWING = 3;

	WhipProfile ActiveWhip;
	int         BoundWhipIndex;

	Array<XRWhipNode> nodes;
	double  segLen;
	bool    simReady;
	int     crackCooldown;
	Array<Actor> hitThisCrack;

	double  pendingLash;
	vector3 pendingLashDir;

	bool    grappleActive;
	int     grappleMode;
	vector3 grappleAnchor;
	double  grappleDist;
	Actor   grappleVictim;
	bool    grappleSetNoGrav;
	int     grappleTimer;

	// ---- Tier 2: rigged model driving (opt-in via `set vr_whip_model 1`) ----
	XRWhipModel whipModel;
	const MDL_BONES   = 21;     // whip_root + seg_00..seg_19
	// Bind-pose bone length, MAP UNITS (bones 1..20 are uniform -- confirmed by direct byte-read
	// of the shipped whip_rigged.iqm: 20 bones x 15.0 = 300 map-unit total reach, matching
	// build_whip.py's EXPORT_SCALE=75 / TARGET_REACH_MAPUNITS=300). Earlier constants (0.22/0.12)
	// were leftover "meters" values from the model's pre-map-unit-scale first pass -- this engine
	// authors IQM models directly in map-unit space (see VRSword's BladeLength convention), so
	// bind length must be in that same space or the driven mesh visibly detaches/gaps (rigid
	// per-bone skin weighting doesn't tolerate a translation mismatch against the authored bind).
	const MDL_SEG_LEN = 15.0;

	Default
	{
		Weapon.SelectionOrder 4200;
		+WEAPON.NOAUTOAIM
		+WEAPON.NOALERT
		+WEAPON.MELEEWEAPON
		Tag "Whip";
		Keywords "class:xrwhip", "dmg:whip", "style:melee", "style:grapple";
		Inventory.PickupMessage "Picked up the XR Whip!";
	}

	// ---- profile binding (state context only, like VRSword.BindBlade) --------------------
	private void BindWhip(int idx)
	{
		class<WhipProfile> cls = "Whip_Leather";
		if (idx == 1) cls = "Whip_Ember";
		else if (idx == 2) cls = "Whip_Tesla";

		ActiveWhip = WhipProfile(new(cls));
		ActiveWhip.Setup();
		BoundWhipIndex = idx;

		if (ActiveWhip.WhipModel != '')
			A_ChangeModel(ActiveWhip.WhipModel);

		A_StopSound(CHAN_BODY);
		if (ActiveWhip.SndCreak.Length() > 0)
			A_StartSound(ActiveWhip.SndCreak, CHAN_BODY, CHANF_LOOPING);

		// force a rope rebuild so new reach/width takes effect
		simReady = false;
		nodes.Clear();
	}

	void CheckWhipCVar()
	{
		int idx = 0;
		CVar c = CVar.FindCVar("vr_whip_profile");
		if (c) idx = c.GetInt();
		if (!ActiveWhip || idx != BoundWhipIndex)
			BindWhip(idx);
	}

	// Point-to-segment distance (identical helper to VRSword's narrow phase).
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

	// ---- rope lifecycle ------------------------------------------------------------------
	private void InitRope(vector3 handPos, vector3 dir)
	{
		nodes.Clear();
		int nodeCount = WHIP_MAXNODES;
		segLen = ActiveWhip.Reach / double(nodeCount - 1);

		double handleR = ActiveWhip.CordWidth * 1.7;
		double tipR    = max(0.4, ActiveWhip.CordWidth * 0.15);

		for (int i = 0; i < nodeCount; i++)
		{
			XRWhipNode n = XRWhipNode(new("XRWhipNode"));
			double frac = double(i) / double(nodeCount - 1);
			n.radius  = handleR + (tipR - handleR) * frac;
			double m  = n.radius * n.radius;              // mass ~ cross-section
			n.invMass = (i == 0) ? 0.0 : 1.0 / m;         // node 0 pinned to the hand
			n.pos  = handPos + dir * (segLen * i);
			n.prev = n.pos;
			nodes.Push(n);
		}
		simReady = true;
	}

	private void SimulateRope(vector3 handPos, vector3 assistVel, bool twoHand)
	{
		int last = nodes.Size() - 1;
		if (last < 1) return;

		// queued Fire "lash": push the tip's previous position back so it inherits
		// a forward velocity next integrate -> a directed crack on demand.
		if (pendingLash > 0.0)
		{
			nodes[last].prev = nodes[last].pos - pendingLashDir * pendingLash;
			pendingLash = 0.0;
		}

		// Verlet integrate (node 0 pinned, skip it)
		for (int i = 1; i <= last; i++)
		{
			XRWhipNode n = nodes[i];
			vector3 vel = (n.pos - n.prev) * WHIP_DAMP;
			if (twoHand) vel += assistVel * WHIP_TWOHAND_COUPLE;
			n.prev = n.pos;
			n.pos  = n.pos + vel + (0.0, 0.0, -WHIP_GRAV);
		}

		nodes[0].pos = handPos;

		// distance constraints, inverse-mass weighted (this is where the taper
		// turns hand motion into a momentum wave that snaps the tip).
		for (int k = 0; k < WHIP_ITERS; k++)
		{
			for (int i = 0; i < last; i++)
			{
				XRWhipNode a = nodes[i];
				XRWhipNode b = nodes[i + 1];
				vector3 delta = b.pos - a.pos;
				double d = delta.Length();
				if (d < 0.0001) continue;
				double diff = (d - segLen) / d;
				double wsum = a.invMass + b.invMass;
				if (wsum <= 0.0)
				{
					b.pos = b.pos - delta * diff;         // a pinned -> all correction to b
					continue;
				}
				a.pos = a.pos + delta * (diff * (a.invMass / wsum));
				b.pos = b.pos - delta * (diff * (b.invMass / wsum));
			}
			nodes[0].pos = handPos;
		}
	}

	private void RenderRope()
	{
		int last = nodes.Size() - 1;
		for (int i = 0; i <= last; i++)
		{
			XRWhipNode n = nodes[i];
			double r = 2.0 + n.radius * 1.2;
			level.AddGlowPanel(ActiveWhip.CordColor, r, n.pos.x, n.pos.y, n.pos.z, 15, 0.6, 0.0, 0.0, 0);
		}
		// the popper: a brighter dot at the very tip
		XRWhipNode tip = nodes[last];
		level.AddGlowPanel(ActiveWhip.CrackColor, 5.0, tip.pos.x, tip.pos.y, tip.pos.z, 15, 0.9, 0.0, 0.0, 0);
	}

	// ---- Tier 2 bone driving --------------------------------------------------------------

	// Shortest-arc quaternion rotating unit vector a onto unit vector b.
	// (Quat is a first-class ZScript type; QuatStruct holds the static factories; ZScript
	// atan2 returns DEGREES, which is exactly what QuatStruct.AxisAngle wants.)
	private Quat QuatFromTo(vector3 a, vector3 b)
	{
		vector3 axis = a cross b;
		double al = axis.Length();
		double d = a dot b;
		if (al < 0.0001)
		{
			if (d >= 0) return QuatStruct.FromAngles(0, 0, 0);        // identical -> identity
			return QuatStruct.AxisAngle((1.0, 0.0, 0.0), 180.0);      // opposite -> flip
		}
		axis = axis / al;
		return QuatStruct.AxisAngle(axis, atan2(al, d));
	}

	// Sample the Verlet node polyline at fraction f in [0,1] (the sim has fewer nodes than the
	// model has bones, so we resample the chain onto the 21 bones).
	private vector3 SampleChain(double f)
	{
		int last = nodes.Size() - 1;
		if (last < 0) return (0, 0, 0);
		double x = clamp(f, 0.0, 1.0) * last;
		int i0 = int(x);
		if (i0 >= last) return nodes[last].pos;
		double frac = x - i0;
		return nodes[i0].pos * (1.0 - frac) + nodes[i0 + 1].pos * frac;
	}

	// Push the sim's shape onto the model's 21 bones. Rotation-only chain: each bone aims its
	// local +Y (BONE_FWD, per the verified IQM Y-up rest axis) along its segment direction, in
	// LOCAL space = parentWorldRot.Conjugate() * worldRot. Translation is the parent-local bind
	// length so segments keep their size. NOTE: bone axis (+Y) and MDL_*_LEN are best-known
	// values that need one in-headset confirmation once this is built (see patch spec).
	private void DriveModelBones()
	{
		if (whipModel == null || nodes.Size() < 2) return;

		Quat parentWorldRot = QuatStruct.FromAngles(0, 0, 0);
		for (int i = 0; i < MDL_BONES; i++)
		{
			double f0 = double(i)     / double(MDL_BONES - 1);
			double f1 = double(i + 1) / double(MDL_BONES - 1);
			vector3 p0 = SampleChain(f0);
			vector3 p1 = SampleChain(f1 < 1.0 ? f1 : 1.0);
			vector3 seg = p1 - p0;
			if (seg.Length() < 0.001) seg = (0.0, 0.0, -1.0);
			vector3 segDir = seg.Unit();

			Quat worldRot = QuatFromTo((0.0, 1.0, 0.0), segDir);
			Quat localRot = parentWorldRot.Conjugate() * worldRot;

			// parent-local translation = the PARENT bone's bind length (root->handle, rest->seg)
			double transLen = (i == 0) ? 0.0 : MDL_SEG_LEN;
			whipModel.SetModelBonePose(i, 0.0, transLen, 0.0,
				localRot.x, localRot.y, localRot.z, localRot.w);

			parentWorldRot = worldRot;
		}
	}

	// ---- the crack ----------------------------------------------------------------------
	private void FireCrack(vector3 tip, double tipSpeed, bool twoHand, vector3 tipDir)
	{
		crackCooldown = WHIP_CRACK_CD;
		hitThisCrack.Clear();

		bool boom = tipSpeed >= WHIP_MACH1;   // genuinely supersonic

		if (ActiveWhip.SndCrack.Length() > 0)
			A_StartSound(ActiveWhip.SndCrack, CHAN_WEAPON, boom ? CHANF_OVERLAP : 0, boom ? 1.0 : 0.8);

		// shockwave ring (wgType 14) + a white core flash (15); bigger on a boom
		double ringR = boom ? 60.0 : 34.0;
		level.AddGlowPanel(ActiveWhip.CrackColor, ringR, tip.x, tip.y, tip.z, 14, 1.0, 0.0, 0.0, 0);
		level.AddGlowPanel(ActiveWhip.CrackColor, ringR * 0.5, tip.x, tip.y, tip.z, 15, 1.0, 0.0, 0.0, 0);

		int last = nodes.Size() - 1;
		vector3 a = nodes[last - 1].pos;
		vector3 b = tip;
		vector3 mid = (a + b) * 0.5;
		double reach = (b - a).Length() + ActiveWhip.CordWidth + 24.0;

		double dmgScale = ActiveWhip.DamageScaleForSpeed(tipSpeed);
		if (twoHand) dmgScale *= 1.35;
		if (boom)    dmgScale *= 1.5;

		double knock = ActiveWhip.Knockback * (0.6 + dmgScale);
		bool pull = (ActiveWhip.BehaviorFlags & WF_PULL) != 0;
		int hand = bOffhandWeapon ? 1 : 0;

		BlockThingsIterator it = BlockThingsIterator.CreateFromPos(mid.x, mid.y, mid.z, reach, reach, false);
		while (it.Next())
		{
			Actor v = it.thing;
			if (v == null || v == owner || v == self) continue;
			if (!v.bIsMonster && !v.bShootable) continue;
			if (v.bCorpse || v.health <= 0) continue;
			if (hitThisCrack.Find(v) != hitThisCrack.Size()) continue;

			double dist = PointSegmentDistance(v.pos + (0, 0, v.Height * 0.5), a, b);
			if (dist > v.radius + ActiveWhip.CordWidth + 8.0) continue;

			hitThisCrack.Push(v);

			int dmg = int(ActiveWhip.BaseDamage * dmgScale);
			dmg = ActiveWhip.ModifyDamage(v, self, dmg, hand);
			v.DamageMobj(self, owner, dmg, ActiveWhip.DamageType);
			v.TraceBleed(dmg, self);

			vector3 kd = pull ? (owner.pos - v.pos) : tipDir;
			if (kd.Length() > 0.001) kd = kd.Unit();
			v.Vel += kd * knock;

			// Indy stagger
			if ((ActiveWhip.BehaviorFlags & WF_DISARM) != 0 && !v.bBoss)
			{
				let ps = v.FindState("Pain");
				if (ps) v.SetState(ps);
			}

			if (ActiveWhip.SndHitFlesh.Length() > 0)
				A_StartSound(ActiveWhip.SndHitFlesh, CHAN_AUTO);
		}

		ActiveWhip.OnCrack(self, tip, tipSpeed);
	}

	// ---- primary fire: directed lash ----------------------------------------------------
	void LashFromAim()
	{
		if (owner == null) return;
		double ang = bOffhandWeapon ? owner.OffhandAngle : owner.AttackAngle;
		double pit = bOffhandWeapon ? owner.OffhandPitch : owner.AttackPitch;
		vector3 dir = (cos(pit) * cos(ang), cos(pit) * sin(ang), -sin(pit));
		pendingLash = WHIP_LASH_IMPULSE;
		pendingLashDir = dir;
		if (ActiveWhip && ActiveWhip.SndWhoosh.Length() > 0)
			A_StartSound(ActiveWhip.SndWhoosh, CHAN_WEAPON);
	}

	// ---- secondary fire: grapple --------------------------------------------------------
	void StartGrappleFromAim()
	{
		if (owner == null || owner.player == null || grappleActive) return;

		vector3 handPos = bOffhandWeapon ? owner.OffhandPos : owner.AttackPos;
		double ang = bOffhandWeapon ? owner.OffhandAngle : owner.AttackAngle;
		double pit = bOffhandWeapon ? owner.OffhandPitch : owner.AttackPitch;

		FLineTraceData lt;
		double hz = handPos.z - owner.pos.z;   // originate near hand height
		bool hit = owner.LineTrace(ang, WHIP_GRAPPLE_RANGE, pit, 0, hz, 0.0, 0.0, lt);

		if (!hit || lt.HitType == TRACE_HitNone)
		{
			if (ActiveWhip && ActiveWhip.SndWhoosh.Length() > 0)
				A_StartSound(ActiveWhip.SndWhoosh, CHAN_WEAPON);   // dry throw
			return;
		}

		grappleActive = true;
		grappleTimer = WHIP_GRAPPLE_TIME;

		if (lt.HitType == TRACE_HitActor && lt.HitActor && lt.HitActor.bShootable)
		{
			grappleVictim = lt.HitActor;
			grappleMode = GM_YANK;
		}
		else
		{
			grappleAnchor = lt.HitLocation;
			grappleDist = (grappleAnchor - owner.pos).Length();
			// anchor well above you => pendulum SWING; otherwise REEL yourself in
			grappleMode = (grappleAnchor.z - owner.pos.z > WHIP_SWING_MINRISE) ? GM_SWING : GM_REEL;
			if (!owner.bNoGravity) { owner.bNoGravity = true; grappleSetNoGrav = true; }
		}

		if (ActiveWhip && ActiveWhip.SndCrack.Length() > 0)
			A_StartSound(ActiveWhip.SndCrack, CHAN_WEAPON, 0, 0.7);   // the catch
	}

	private void UpdateGrapple()
	{
		if (owner == null || owner.player == null) { EndGrapple(); return; }
		if (!(owner.player.cmd.buttons & BT_ALTATTACK)) { EndGrapple(); return; }
		if (--grappleTimer <= 0) { EndGrapple(); return; }

		if (grappleMode == GM_REEL)
		{
			vector3 toA = grappleAnchor - owner.pos;
			double d = toA.Length();
			if (d < 56.0) { EndGrapple(); return; }        // arrived
			owner.Vel = toA.Unit() * WHIP_REEL_SPEED;
		}
		else if (grappleMode == GM_SWING)
		{
			// Pendulum: hang at fixed rope length from a high anchor, gravity does the
			// rest. Release (BT_ALTATTACK up) keeps your tangential speed -> you fly off.
			vector3 toA = grappleAnchor - owner.pos;
			double d = toA.Length();
			if (d < 24.0) { EndGrapple(); return; }
			vector3 rope = toA / d;                          // unit, toward anchor
			owner.Vel += (0.0, 0.0, -WHIP_SWING_GRAV);       // self-applied (bNoGravity is on)
			double radial = owner.Vel dot rope;              // + = toward anchor
			if (radial < 0.0) owner.Vel -= rope * radial;    // cancel only the rope-stretching part
			if (d > grappleDist)                             // taut-line length constraint
				owner.SetOrigin(grappleAnchor - rope * grappleDist, true);
		}
		else if (grappleMode == GM_YANK)
		{
			if (grappleVictim == null || grappleVictim.health <= 0) { EndGrapple(); return; }

			if (grappleVictim.bBoss || grappleVictim.Mass > 400)
			{
				// too heavy to move -- reel the player toward it instead
				owner.Vel = (grappleVictim.pos - owner.pos).Unit() * WHIP_REEL_SPEED;
			}
			else
			{
				grappleVictim.Vel += (owner.pos - grappleVictim.pos).Unit() * WHIP_YANK_SPEED;
				if (ActiveWhip && (ActiveWhip.BehaviorFlags & WF_DISARM) != 0)
				{
					// disarm: interrupt whatever it's doing and stagger it briefly
					let ps = grappleVictim.FindState("Pain");
					if (ps) grappleVictim.SetState(ps);
					grappleVictim.reactiontime += 8;
				}
				double d = (grappleVictim.pos - owner.pos).Length();
				if (d < 72.0) EndGrapple();
			}
		}
	}

	void EndGrapple()
	{
		if (grappleSetNoGrav && owner) owner.bNoGravity = false;
		grappleSetNoGrav = false;
		grappleActive = false;
		grappleMode = GM_NONE;
		grappleVictim = null;
		grappleTimer = 0;
	}

	private void RenderGrappleLine(vector3 handPos)
	{
		vector3 target = (grappleMode == GM_YANK && grappleVictim)
			? grappleVictim.pos + (0, 0, grappleVictim.Height * 0.5)
			: grappleAnchor;
		vector3 seg = target - handPos;
		int steps = 12;
		for (int i = 0; i <= steps; i++)
		{
			vector3 p = handPos + seg * (double(i) / double(steps));
			level.AddGlowPanel(ActiveWhip.CordColor, 4.0, p.x, p.y, p.z, 15, 0.7, 0.0, 0.0, 0);
		}
	}

	// ---- per-tic driver -----------------------------------------------------------------
	override void Tick()
	{
		Super.Tick();

		if (crackCooldown > 0) crackCooldown--;

		if (owner == null || owner.player == null)
		{
			EndGrapple();
			return;
		}

		bool active = (owner.player.ReadyWeapon == self) || (owner.player.OffhandWeapon == self);
		if (!active)
		{
			EndGrapple();
			simReady = false;
			nodes.Clear();
			if (whipModel != null) { whipModel.Destroy(); whipModel = null; }
			return;
		}

		if (ActiveWhip == null) return;   // BindWhip runs from the Ready state

		int hand = bOffhandWeapon ? 1 : 0;
		vector3 handPos = bOffhandWeapon ? owner.OffhandPos : owner.AttackPos;
		double ang = bOffhandWeapon ? owner.OffhandAngle : owner.AttackAngle;
		double pit = bOffhandWeapon ? owner.OffhandPitch : owner.AttackPitch;
		vector3 dir = (cos(pit) * cos(ang), cos(pit) * sin(ang), -sin(pit));

		// grapple owns the frame while engaged
		if (grappleActive)
		{
			UpdateGrapple();
			if (grappleActive) RenderGrappleLine(handPos);
			return;
		}

		if (!simReady || nodes.Size() == 0)
			InitRope(handPos, dir);

		// two-hand: off hand near the handle feeds its velocity into the chain
		vector3 otherPos = bOffhandWeapon ? owner.AttackPos : owner.OffhandPos;
		bool twoHand = (otherPos - handPos).Length() < WHIP_TWOHAND_R;
		vector3 assistVel = twoHand ? owner.GetHandVelocity(1 - hand) : (0.0, 0.0, 0.0);

		SimulateRope(handPos, assistVel, twoHand);
		RenderRope();

		// Tier 2 (opt-in): spawn the rigged model, park it at the hand, drive its bones from
		// the sim. Default OFF -- glow rope stays the visual until `set vr_whip_model 1` AND a
		// rebuild (the SetModelBonePose native ships with the Tier-2 C++ patch).
		CVar mc = CVar.FindCVar("vr_whip_model");
		if (mc && mc.GetBool())
		{
			if (whipModel == null)
				whipModel = XRWhipModel(Spawn("XRWhipModel", handPos));
			if (whipModel != null)
			{
				whipModel.SetOrigin(handPos, true);
				DriveModelBones();
			}
		}
		else if (whipModel != null)
		{
			whipModel.Destroy();
			whipModel = null;
		}

		// crack evaluation
		XRWhipNode tipN = nodes[nodes.Size() - 1];
		vector3 tipVel = tipN.pos - tipN.prev;
		double tipSpeed = tipVel.Length();
		double handSpeed = owner.GetHandVelocity(hand).Length();
		double effTip = max(tipSpeed, handSpeed);      // sim leads, hand speed is the floor

		double crackAt = ActiveWhip.CrackSpeed;
		if (twoHand) crackAt *= 0.7;

		// whoosh telegraph just under threshold
		if (crackCooldown == 0 && effTip > crackAt * 0.6 && effTip < crackAt
			&& ActiveWhip.SndWhoosh.Length() > 0 && (level.maptime % 6 == 0))
			A_StartSound(ActiveWhip.SndWhoosh, CHAN_VOICE);

		if (crackCooldown == 0 && effTip >= crackAt)
		{
			vector3 vdir = tipVel.Length() > 0.001 ? tipVel.Unit() : dir;
			FireCrack(tipN.pos, effTip, twoHand, vdir);
		}
	}

	States
	{
	Ready:
		TNT1 A 0 { invoker.CheckWhipCVar(); }
		TNT1 A 1 A_WeaponReady(WRF_ALLOWRELOAD);
		Loop;
	Deselect:
		TNT1 A 0 { invoker.EndGrapple(); }
		TNT1 A 1 A_Lower;
		Loop;
	Select:
		TNT1 A 1 A_Raise;
		Loop;
	Fire:
		TNT1 A 1 A_XRWhipFireFlatscreen();
		Goto Ready;
	AltFire:
		TNT1 A 1 { invoker.StartGrappleFromAim(); }
		Goto Ready;
	Spawn:
		TNT1 A -1;
		Stop;
	}

	// Button-triggered crack strike -- works in BOTH VR and flatscreen (mirrors
	// VRSword.A_VRSwordFireFlatscreen, which is why GetHandVelocity never gates it).
	// In VR it supplements the physical motion-crack in Tick() and kicks the rope with a
	// lash impulse; in flatscreen it is the ONLY attack path. Reach-length LineAttack.
	action void A_XRWhipFireFlatscreen()
	{
		if (invoker.ActiveWhip == null) return;

		invoker.LashFromAim();   // VR: feed the sim so the rope also cracks visually

		int laflags = 0;
		int alflags = invoker.bOffhandWeapon ? ALF_ISOFFHAND : 0;
		if (invoker.bOffhandWeapon) laflags |= LAF_ISOFFHAND;

		double range = invoker.ActiveWhip.Reach;
		FTranslatedLineTarget t;
		double pitch = AimLineAttack(angle, range, t, 0., ALF_CHECK3D | alflags);

		int dmg = int(invoker.ActiveWhip.BaseDamage * invoker.ActiveWhip.SpeedCeil * 0.7);
		if (t.linetarget)
			dmg = invoker.ActiveWhip.ModifyDamage(t.linetarget, invoker, dmg, invoker.bOffhandWeapon ? 1 : 0);

		LineAttack(angle, range, pitch, dmg, invoker.ActiveWhip.DamageType, "BulletPuff", laflags, t);

		if (invoker.ActiveWhip.SndCrack.Length() > 0)
			A_StartSound(invoker.ActiveWhip.SndCrack, CHAN_WEAPON);

		// vanilla melee convention: snap to face the hit target outside VR
		if ((player != null && !player.PlayInVR || vanilla_melee_attack) && t.linetarget)
		{
			angle = t.angleFromSource;
			if (player != null) player.resetDoomYaw = true;
		}
	}
}
