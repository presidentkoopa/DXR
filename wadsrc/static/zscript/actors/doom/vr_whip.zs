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
//   SECONDARY (AltFire) -- GRAPPLE: LineTrace from the hand (range = ActiveWhip.Reach, the SAME
//                          number the rope sim/crack use -- it can't grab farther than the whip
//                          physically reaches). Two outcomes:
//                          * Geometry hit -> GM_ATTACHED, one unified tension-physics state:
//                            self-gravity + a taut-line distance constraint. Airborne, this alone
//                            produces a pendulum swing (Indy gap-swing); release keeps your
//                            tangential speed so you launch off. Grounded, nothing visibly happens
//                            -- the floor already absorbs it every tic, no explicit branch needed.
//                            Hold FIRE while attached for a deliberate reel-in (contextual, not
//                            automatic); off-hand grip (BT_USER1) mid-swing pumps the rope length
//                            for real angular-momentum speed changes (climb up = speed up).
//                          * Monster hit -> GM_YANK, entangle-yank: pull force is
//                            handSpeed*massRatio (100/targetMass, mirrors the throw-formula
//                            convention) -- heavier enemies resist more, a harder swing pulls
//                            harder. Bosses/too-light-a-swing never get pulled (the crack still
//                            hits via FireCrack's own collision). A caught enemy tumbles (Roll)
//                            and lands in front of the player (not their exact origin) for a
//                            guaranteed melee-followup window -- the Bulletstorm-into-chainsaw combo.
//                          Rope-tension knockback (fireballs etc. while attached) is clamped by a
//                          dedicated pinball safeguard -- velocity ceiling, per-hit impulse cap,
//                          diminishing returns on rapid repeat hits, and a damage-aware taper so
//                          getting wrecked reads in the health bar, not as loss of physical control.
//                          Hold AltFire to keep the line, release to let go.
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

// One connected SDF rope segment: a flat, camera-facing SDF quad stretched between two adjacent
// Verlet nodes and drawn by the ENGINE-RESIDENT SDF sprite shader (shaders/glsl/vr_sdf_procedural.fp,
// bound to SIGL via gldefs -- NOT the Radiance glow-panel cascade). This is what makes the whip a
// real connected rope/chain that renders in the base engine with no companion mod loaded. The
// flat-quad orient math is copied verbatim from XR_GravityPathNode.XR_Orient (vr_gravity_path.zs),
// which uses the same SIGL sprite + msdf bit 512 (seamed flat rectangle = chain-link look).
class XRWhipChainLink : Actor
{
	const XR_LINK_PX = 64.0;   // base pixel size backing SIGL (matches XR_GravityPathNode.XR_BASE_PX)

	Default
	{
		+NOGRAVITY +NOCLIP +NOBLOCKMAP +DONTSPLASH +NOTIMEFREEZE +NOINTERACTION
		+FLATSPRITE +ROLLCENTER
		RenderStyle "Add";
	}
	States
	{
	Spawn:
		SIGL A -1 Bright;
		Stop;
	}

	// spherical yaw/pitch tilting a FLATSPRITE quad so its face-normal = n (Pitch=0 => facing +Z,
	// no tilt). Copied from XR_GravityPathNode.XR_VectorToYawPitch.
	static void LinkYawPitch(Vector3 n, out double yaw, out double pitch)
	{
		double horiz = sqrt(n.x * n.x + n.y * n.y);
		yaw   = (horiz > 0.0001) ? VectorAngle(n.x, n.y) : 0.0;
		pitch = atan2(horiz, n.z);
	}

	// Span a->b with the flat face pointing along faceN (toward the camera), sized len x width.
	void OrientSegment(Vector3 a, Vector3 b, Vector3 faceN, double width)
	{
		Vector3 seg = b - a;
		double len = seg.Length();
		if (len < 0.0001) { bInvisible = true; return; }
		bInvisible = false;
		Vector3 tangent = seg / len;

		SetOrigin(a + seg * 0.5, true);

		double yaw, pitch;
		LinkYawPitch(faceN, yaw, pitch);
		Angle = yaw;
		Pitch = pitch;

		double ryaw = yaw - 90.0;
		Vector3 baseRight = (cos(ryaw), sin(ryaw), 0.0);
		Vector3 nn = faceN.Unit();
		double tdotn = tangent.x * nn.x + tangent.y * nn.y + tangent.z * nn.z;
		Vector3 tproj = (tangent.x - nn.x * tdotn, tangent.y - nn.y * tdotn, tangent.z - nn.z * tdotn);
		double tlen = tproj.Length();
		if (tlen > 0.0001)
		{
			tproj /= tlen;
			Vector3 c = (baseRight.y * tproj.z - baseRight.z * tproj.y,
						 baseRight.z * tproj.x - baseRight.x * tproj.z,
						 baseRight.x * tproj.y - baseRight.y * tproj.x);
			double crossDotN = c.x * nn.x + c.y * nn.y + c.z * nn.z;
			double dotRT = baseRight.x * tproj.x + baseRight.y * tproj.y + baseRight.z * tproj.z;
			Roll = atan2(crossDotN, dotRT);
		}
		Scale = (len / XR_LINK_PX, width / XR_LINK_PX);
	}
}

// TIER 2 -- world-space carrier for the rigged whip IQM (models/weapons/xrwhip/whip_rigged.iqm,
// 21 bones). Spawned by XRWhip only when the vr_whip_model CVar is on; XRWhip parks it at the
// hand and drives its bones each tic from the Verlet sim via SetModelBonePose. Invisible sprite
// -- the model itself is the whole visual. A_ChangeModel attaches the modeldef 'XRWhipRigged'
// A one-shot expanding SDF flash burst (crack ring, fire pop, spark) drawn by the engine-resident
// SDF sprite shader (SIGL -> vr_sdf_procedural.fp, circle mode) -- NO AddGlowPanel, so the whip's
// crack/elemental FX render in the base engine with no Radiance mod. Scales r0->r1 and fades over
// 'maxLife' tics. Also used by the Ember/Tesla profiles (vr_whip_profile.zs).
class XRSDFBurst : Actor
{
	vector3 col;
	double  r0, r1;
	int     life, maxLife;

	Default
	{
		+NOBLOCKMAP +NOGRAVITY +NOINTERACTION +DONTSPLASH +CLIENTSIDEONLY +NOTIMEFREEZE
		+BRIGHT +FORCEXYBILLBOARD
		RenderStyle "Add";
		Radius 1;
		Height 1;
	}

	// spawn a burst at world point p, colour c, growing startR->endR over 'ticks' tics.
	static void Emit(vector3 p, Color c, double startR, double endR, int ticks)
	{
		let b = XRSDFBurst(Actor.Spawn("XRSDFBurst", p));
		if (!b) return;
		b.col = (c.r / 255.0, c.g / 255.0, c.b / 255.0);
		b.r0 = startR; b.r1 = endR; b.maxLife = max(ticks, 1); b.life = b.maxLife;
	}

	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		msdf_enabled = 0;        // SDF circle/sigil core
		msdf_glitch  = 0.10;
	}

	override void Tick()
	{
		if (life-- <= 0) { Destroy(); return; }
		double f    = 1.0 - double(life) / double(maxLife);   // 0 -> 1 over the life
		double r    = r0 + (r1 - r0) * f;
		double fade = 1.0 - f;
		Scale = (r / 64.0, r / 64.0);
		msdf_color = col * (1.5 * fade);
		Alpha = fade;
	}

	States
	{
	Spawn:
		SIGL A 1 Bright;
		Wait;
	}
}

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

// Model-holder actor for the rigged whip IQM. A_ChangeModel('XRWhipRigged') above (and MODELDEF's
// "Model XRWhipRigged" block) must bind to a REAL actor class -- this exists only to carry that
// mesh so both the modeldef parser and A_ChangeModel resolve it. Never spawned in-world.
class XRWhipRigged : Actor
{
	Default { +NOBLOCKMAP +NOINTERACTION +NOGRAVITY +DONTSPLASH +NOTIMEFREEZE; }
	States { Spawn: TNT1 A -1; Stop; }
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
	// NO separate range constant: grapple range is ActiveWhip.Reach (see StartGrappleFromAim),
	// the SAME number the rope sim and crack use. An earlier pass hardcoded this to 900 while
	// Reach was 190-300 -- letting the "whip" grapple something 3x farther than the whip's own
	// simulated rope could ever physically reach. That's not a whip grapple, that's a hitscan
	// with a leather prop attached. One reach number for the whole weapon, no exceptions.
	const WHIP_GRAPPLE_TIME  = 140;     // ~4s max hold
	// Self-applied gravity while attached (bNoGravity is on during a grapple, so we supply our own).
	// NOTE (physics audit 2026-07-03): the engine's real gravity is 1.0 units/tic^2
	// (GetGravity() = sv_gravity(800) * 0.00125). 0.9 is a deliberate ~10% "floatier swing" FEEL
	// choice, NOT a bug -- left as-is per the no-silent-balance-changes rule. Set to 1.0 (or read
	// owner.GetGravity()) if you want the swing to match world gravity exactly.
	const WHIP_SWING_GRAV    = 0.9;
	// A yanked enemy lands in front of the player, not on top of them -- so a follow-up melee
	// swing (chainsaw, etc.) actually connects instead of the enemy overlapping/behind you.
	// 80 = DEFMELEERANGE/chainsaw reach (64, see weaponchainsaw.zs A_Saw) + 16 (Lost Soul, the
	// smallest-radius combat monster) -- zero-margin for Lost Soul, generous for everything else.
	const WHIP_MELEE_LANDING_RANGE = 80.0;
	// Shared floor for grapple rope length (used at catch-time AND in ApplySwingPump) -- one
	// constant so the two can't drift apart. Also the min a pumped rope can shorten to.
	const WHIP_MIN_ROPE_DIST = 24.0;

	// GM_REEL and GM_SWING (two different pull mechanisms picked once at catch-time by anchor
	// height) are GONE -- replaced by ONE unified tension-physics state, GM_ATTACHED. Airborne
	// naturally swings (gravity + taut-line constraint, nothing else needed); grounded naturally
	// does nothing (the floor already absorbs the self-applied fake-gravity, no explicit
	// player.onground branch required). The old unconditional "fly straight to whatever you hit"
	// behavior is replaced by an opt-in deliberate pull: hold Fire while attached.
	const GM_NONE     = 0;
	const GM_YANK     = 2;
	const GM_ATTACHED = 3;

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
	// whip-owned entangle countdown -- was grappleVictim.special1, but special1 is a SHARED actor
	// scratch field other actors use, so writing it could collide. Single-victim state, so one
	// plain int on the whip is correct and needs zero AActor-side fields (audit fix).
	int     grappleEntangleTimer;

	// ---- pinball safeguards (while GM_ATTACHED) ----
	vector3 prevGrappleVel;
	int     lastBigImpulseTic;
	double  recentDamage;
	int     lastKnownHealth;
	bool    healthTracked;

	// ---- rolling peak hand-speed (entanglement mass pre-gate in StartGrappleFromAim) ----
	// Updated every non-grappling tic in Tick(). AltFire fires on a single button-down tic, not a
	// velocity-crossing like the crack, so gating on the exact-frame reading would demand aiming
	// precisely AND being at peak swing speed simultaneously -- a decay-peak-hold instead lets a
	// wind-up-then-trigger swing register.
	double  handSpeedPeak;

	// ---- SDF chain rope render (default when the profile has no model) ----
	Array<XRWhipChainLink> chainLinks;   // one per rope segment, repositioned every render tic

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
		Weapon.SlotNumber 9;   // [XR] VR grab-tool slot (with IceHook + VRSword); mirrors DoomPlayer's Player.WeaponSlot 9
		+WEAPON.NOAUTOAIM
		+WEAPON.NOALERT
		+WEAPON.MELEEWEAPON
		Tag "Whip";
		Keywords "class:xrwhip", "dmg:whip", "style:melee", "style:grapple";
		Inventory.PickupMessage "Picked up the XR Whip!";
	}

	// ---- CVar helpers (VR Weapon Options) -- mirrors CheckWhipCVar's null-check pattern ----
	private double CVF(string name, double def)
	{
		CVar c = CVar.FindCVar(name);
		return c ? c.GetFloat() : def;
	}
	private bool CVB(string name, bool def)
	{
		CVar c = CVar.FindCVar(name);
		return c ? c.GetBool() : def;
	}
	private int CVI(string name, int def)
	{
		CVar c = CVar.FindCVar(name);
		return c ? c.GetInt() : def;
	}

	// ---- profile binding (state context only, like VRSword.BindBlade) --------------------
	private void BindWhip(int idx)
	{
		class<WhipProfile> cls = "Whip_Leather";   // 0 = Indiana Jones (rigged leather model)
		if (idx == 1) cls = "Whip_Techno";         // 1 = SDF techno-colour chain (engine-resident, no Radiance)
		else if (idx == 2) cls = "Whip_Ember";
		else if (idx == 3) cls = "Whip_Tesla";

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

	// hue in [0,360) -> saturated neon RGB (HSV with S=V=1). Cheap 6-segment ramp.
	private static Color HueToNeon(double h)
	{
		h = h - floor(h / 360.0) * 360.0;
		double x = 1.0 - abs((h / 60.0) - 2.0 * floor(h / 120.0) - 1.0);
		double r, g, b;
		int seg = int(h / 60.0);
		if      (seg == 0) { r = 1.0; g = x;   b = 0.0; }
		else if (seg == 1) { r = x;   g = 1.0; b = 0.0; }
		else if (seg == 2) { r = 0.0; g = 1.0; b = x;   }
		else if (seg == 3) { r = 0.0; g = x;   b = 1.0; }
		else if (seg == 4) { r = x;   g = 0.0; b = 1.0; }
		else               { r = 1.0; g = 0.0; b = x;   }
		return Color(255, int(r * 255.0), int(g * 255.0), int(b * 255.0));
	}

	private void HideChain(int fromIndex)
	{
		for (int i = fromIndex; i < chainLinks.Size(); i++)
			if (chainLinks[i]) chainLinks[i].bInvisible = true;
	}

	void DestroyChain()
	{
		for (int i = 0; i < chainLinks.Size(); i++)
			if (chainLinks[i]) chainLinks[i].Destroy();
		chainLinks.Clear();
	}

	// Draw the rope as CONNECTED SDF SEGMENTS through the engine-resident SDF sprite shader --
	// no AddGlowPanel, no Radiance dependency, no floating dots. One XRWhipChainLink bridges each
	// pair of adjacent Verlet nodes, billboarded toward the head so it reads from any angle.
	//
	// REACTIVE ENERGY ROPE: every segment's width / colour / glow / glitch is driven live from the
	// Verlet sim's own state, so the whip visibly LOADS and CRACKS:
	//   * speed  (node velocity = pos-prev) -> the crack travels handle->tip as a white-hot pulse,
	//     and the segment THINS as it goes supersonic (a real whip thins toward the tip).
	//   * tension (segment stretch vs rest length) -> taut segments thin, brighten and glitch
	//     (strained energy) while a slack rope is thick and dim.
	//   * tip taper -> the tip is the hottest, thinnest point of the whole rope.
	// All of it is data the sim already computes -- pure math, no new shader, engine-standalone.
	private void RenderRope()
	{
		int last = nodes.Size() - 1;
		if (last < 1) { HideChain(0); return; }

		vector3 headPos = owner ? owner.GetHeadPos() : pos;

		// fixed tint for non-cycling profiles; techno computes a per-segment hue in the loop -- a
		// neon gradient that flows DOWN the rope over time (Blood Dragon synthwave, not a flat hue).
		// CrackColor = the white-hot energy colour segments blend toward as speed/tension climb.
		vector3 fixedCol = (ActiveWhip.CordColor.r / 255.0, ActiveWhip.CordColor.g / 255.0, ActiveWhip.CordColor.b / 255.0);
		double  hueBase  = level.maptime * 4.0 + BoundWhipIndex * 40.0;
		vector3 hotCol = (ActiveWhip.CrackColor.r / 255.0, ActiveWhip.CrackColor.g / 255.0, ActiveWhip.CrackColor.b / 255.0);

		double crackSpd = max(1.0, ActiveWhip.CrackSpeed);

		for (int i = 0; i < last; i++)
		{
			if (i >= chainLinks.Size())
				chainLinks.Push(XRWhipChainLink(Spawn("XRWhipChainLink", nodes[i].pos)));
			XRWhipChainLink lk = chainLinks[i];
			if (!lk) continue;

			XRWhipNode na = nodes[i];
			XRWhipNode nb = nodes[i + 1];
			vector3 a = na.pos, b = nb.pos;

			// ---- reactive terms, all straight from the Verlet sim ----
			double spd     = ((na.pos - na.prev).Length() + (nb.pos - nb.prev).Length()) * 0.5;
			double energy  = clamp(spd / crackSpd, 0.0, 1.4);                          // 0 idle .. >1 mid-crack
			double segNow  = (b - a).Length();
			double taut    = clamp((segNow - segLen) / max(1.0, segLen), 0.0, 1.5);    // 0 slack .. stretched
			double tipFrac = double(i) / double(max(1, last - 1));                     // 0 handle .. 1 tip

			// width: taper to the tip, then THIN with speed (supersonic) and tension
			double baseW = max(1.0, na.radius + nb.radius);
			double w = max(0.6, baseW * (1.0 - 0.55 * energy) * (1.0 - 0.35 * taut));

			// per-segment base colour: techno flows a neon hue gradient handle->tip; others fixed.
			vector3 baseCol = fixedCol;
			if (ActiveWhip.RopeCycleHue)
			{
				Color hc = HueToNeon(hueBase + tipFrac * 150.0);   // 150deg span down the rope
				baseCol = (hc.r / 255.0, hc.g / 255.0, hc.b / 255.0);
			}

			// colour: idle base -> white-hot as energy/tension/tip climb; brightness blooms with both
			double heat   = clamp(energy * 0.9 + taut * 0.5 + tipFrac * energy * 0.7, 0.0, 1.0);
			double bright = 0.55 + 0.95 * energy + 0.55 * taut + ActiveWhip.GlowBoost;
			vector3 col   = (baseCol * (1.0 - heat) + hotCol * heat) * bright;

			vector3 faceN = headPos - (a + b) * 0.5;
			if (faceN.Length() < 0.0001) faceN = (0.0, 0.0, 1.0);

			lk.OrientSegment(a, b, faceN.Unit(), w);
			lk.msdf_enabled = 512;                                                     // seamed flat rect = chain link
			lk.msdf_glitch  = clamp(ActiveWhip.RopeGlitch + energy * 0.35 + taut * 0.35, 0.0, 1.0);
			lk.msdf_color   = col;
			lk.Alpha        = clamp(0.65 + 0.35 * energy + 0.35 * taut, 0.4, 1.0);
		}
		HideChain(last);   // any surplus links from a longer previous rope get hidden
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

		// SDF crack flash: an expanding ring + a bright core pop at the tip (engine-standalone,
		// no AddGlowPanel/Radiance). Bigger on a genuine supersonic boom.
		double ringR = boom ? 60.0 : 34.0;
		XRSDFBurst.Emit(tip, ActiveWhip.CrackColor, ringR * 0.25, ringR, boom ? 8 : 6);
		XRSDFBurst.Emit(tip, ActiveWhip.CrackColor, ringR * 0.4, ringR * 0.15, 4);   // hot core snap

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

			// Mass-scaled + ceiling-clamped knockback (physics audit): mirrors the throw formula's
			// 100/Mass convention (heavier enemies shove less) and the native ApplyKickback 32 u/tic
			// cap, so no single crack -- even two-handed supersonic on a light target -- can fling
			// anything to absurd speed. Respects +DONTTHRUST (native no-knockback opt-out).
			if (!v.bDontThrust)
			{
				vector3 kd = pull ? (owner.pos - v.pos) : tipDir;
				if (kd.Length() > 0.001)
				{
					kd = kd.Unit();
					double vKnock = min(knock * (100.0 / max(1.0, v.Mass)), CVF("vr_whip_crack_knock_ceiling", 32.0));
					v.Vel += kd * vKnock;
				}
			}

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
		if (owner == null || owner.player == null || grappleActive || ActiveWhip == null) return;

		vector3 handPos = bOffhandWeapon ? owner.OffhandPos : owner.AttackPos;
		double ang = bOffhandWeapon ? owner.OffhandAngle : owner.AttackAngle;
		double pit = bOffhandWeapon ? owner.OffhandPitch : owner.AttackPitch;

		FLineTraceData lt;
		double hz = handPos.z - owner.pos.z;   // originate near hand height
		// Grapple range = the whip's own Reach, the SAME number the rope sim/crack use -- not
		// a bigger separate hitscan range. If it can't physically reach that far, it can't grab.
		bool hit = owner.LineTrace(ang, ActiveWhip.Reach, pit, 0, hz, 0.0, 0.0, lt);

		if (!hit || lt.HitType == TRACE_HitNone)
		{
			if (ActiveWhip && ActiveWhip.SndWhoosh.Length() > 0)
				A_StartSound(ActiveWhip.SndWhoosh, CHAN_WEAPON);   // dry throw
			return;
		}

		bool hitActor = (lt.HitType == TRACE_HitActor && lt.HitActor && lt.HitActor.bShootable);

		// Entanglement mass pre-gate (physics-audit follow-up): previously ANY shootable actor
		// entangled instantly regardless of mass -- only the CONTINUOUS per-tic pull check below
		// (in UpdateGrapple) caught a too-heavy target, one tic later, reading as a catch-then-
		// instant-release flicker. Gate it at the SOURCE instead, reusing the exact same ratio so
		// "swing harder" already buys tolerance for more mass -- no new balance constants. Bosses
		// are exempt: the reel-toward-them fallback in UpdateGrapple is the intended outcome for
		// something that heavy, not a failure case.
		if (hitActor && !lt.HitActor.bBoss)
		{
			double gateMass = lt.HitActor.Mass;
			if (CVB("vr_easy_grab_props", false) && lt.HitActor.Keywords.IndexOf("flags:grabprop") != -1)
				gateMass *= CVF("vr_easy_grab_scale", 0.5);
			double gateMassRatio = 100.0 / max(1.0, gateMass);
			double gatePullSpeed = min(handSpeedPeak * CVF("vr_whip_yank_force_scale", 1.0) * gateMassRatio,
										CVF("vr_whip_yank_pull_cap", 45.0));
			if (gatePullSpeed < CVF("vr_whip_entangle_minspeed", 4.0))
			{
				// too heavy for how hard you swung -- the crack still hit via FireCrack on the way
				// in, just no entanglement; dry-throw sound reuses the "missed" feedback
				if (ActiveWhip && ActiveWhip.SndWhoosh.Length() > 0)
					A_StartSound(ActiveWhip.SndWhoosh, CHAN_WEAPON);
				return;
			}
		}

		grappleActive = true;
		grappleTimer = WHIP_GRAPPLE_TIME;

		if (hitActor)
		{
			grappleVictim = lt.HitActor;
			grappleMode = GM_YANK;
			grappleEntangleTimer = CVI("vr_whip_entangle_duration", 12);   // whip-owned, not victim.special1
			// Mark the player as responsible from the moment the yank locks on, not just once
			// caught -- covers a flags:grabprop prop (e.g. the barrel) colliding with something
			// mid-pull, before it ever reaches the catch threshold. Standard Doom convention
			// (A_Explode's RadiusAttack reads self.target for kill credit).
			grappleVictim.target = owner;
		}
		else
		{
			grappleAnchor = lt.HitLocation;
			// Floor the rope length so a point-blank catch can't create a near-zero grappleDist
			// (degenerate rope direction + inverted first swing-pump response). LOWER bound only --
			// NOT clamped to Reach, because the trace originates hz above owner.pos, so the true 3D
			// catch distance can legitimately exceed Reach by up to |hz| (triangle inequality).
			grappleDist = max((grappleAnchor - owner.pos).Length(), WHIP_MIN_ROPE_DIST);
			// Unconditional now -- no more height check picking REEL vs SWING. Airborne naturally
			// swings (gravity + taut-line), grounded naturally does nothing (floor absorbs it).
			grappleMode = GM_ATTACHED;
			if (!owner.bNoGravity) { owner.bNoGravity = true; grappleSetNoGrav = true; }
		}

		// seed the pinball-safeguard trackers fresh for this grapple session
		prevGrappleVel = owner.Vel;
		lastBigImpulseTic = 0;
		recentDamage = 0.0;
		lastKnownHealth = owner.health;
		healthTracked = true;

		if (ActiveWhip && ActiveWhip.SndCrack.Length() > 0)
			A_StartSound(ActiveWhip.SndCrack, CHAN_WEAPON, 0, 0.7);   // the catch
	}

	private void UpdateGrapple()
	{
		if (owner == null || owner.player == null) { EndGrapple(); return; }
		if (!(owner.player.cmd.buttons & BT_ALTATTACK)) { EndGrapple(); return; }
		if (--grappleTimer <= 0) { EndGrapple(); return; }

		// recent-damage tracker for the damage-aware taper (pinball safeguard) -- runs regardless
		// of mode, decays every tic so a hit from 3 seconds ago stops mattering.
		if (healthTracked)
		{
			int dmgThisTic = lastKnownHealth - owner.health;
			if (dmgThisTic > 0) recentDamage += dmgThisTic;
			recentDamage *= 0.92;
			lastKnownHealth = owner.health;
		}

		if (grappleMode == GM_ATTACHED)
		{
			// [XR fling fix] Publish live-swing every tic the pendulum owns the pawn. We are past the
			// BT_ALTATTACK-held early-return (~609), inside grappleActive, in the GM_ATTACHED branch --
			// all three predicate terms hold. Native climb (VR_UpdateClimbing) reads this and yields its
			// Vel write + gravity flag to us, so only one system moves the pawn this tic (no fling).
			if (owner && owner.player) owner.VR_SetWhipSwingLive(true);
			// [XR grip arbiter] Publish rope-attached under the FREE hand's PHYSICAL index (GM_ATTACHED only,
			// never GM_YANK) so the arbiter grants that hand GRIP_WHIP and ApplySwingPump can act on grip.
			if (owner && owner.player)
			{
				int freeSlot = 1 - (bOffhandWeapon ? 1 : 0);
				owner.VR_SetWhipRopeAttached(owner.VR_PhysicalHandForSlot(freeSlot), true);
			}
			vector3 toA = grappleAnchor - owner.pos;
			double d = toA.Length();
			if (d < 1.0) { EndGrapple(); return; }            // degenerate: anchor ~= player, bail (parity w/ GM_YANK guard)
			vector3 rope = toA / d;                           // unit, toward anchor

			// Tension physics -- the ONE state for any geometry catch. ENERGY-CONSERVING taut line
			// via predict-and-project, with the ENGINE as the sole integrator: the player pawn is a
			// thinker whose native Tick (P_XYMovement/P_ZMovement) applies owner.Vel to pos every
			// tic. So we set Vel to the exact displacement that lands on the rope sphere and let the
			// engine do the one move -- we must NOT ALSO SetOrigin, or the player double-moves off
			// the sphere and flings outward (caught by the physics re-audit; the VR climb system
			// p_user.cpp sets Vel and lets native movement integrate it, never SetOrigin -- same
			// convention). Only project when actually overshooting; otherwise leave Vel as the free
			// gravity/swing velocity (this is what conserves energy -- no per-tic radial cancel).
			// Airborne this is a pendulum; grounded the floor cancels the self-gravity, nothing moves.
			owner.Vel += (0.0, 0.0, -WHIP_SWING_GRAV);        // self-applied (bNoGravity is on)
			vector3 predicted = owner.pos + owner.Vel;         // where the engine WILL move us this tic
			vector3 toAnchorP = grappleAnchor - predicted;
			double dP = toAnchorP.Length();
			if (dP > grappleDist && dP > 0.0001)               // only correct a real overshoot
			{
				vector3 ropeP = toAnchorP / dP;
				predicted = grappleAnchor - ropeP * grappleDist;  // project back onto the rope sphere
				owner.Vel = predicted - owner.pos;                 // engine will integrate this -> lands ON the sphere
				d = grappleDist;                                   // d authoritative after the correction
			}
			else d = dP;

			// Contextual deliberate pull: Fire is free while AltFire holds the line, so holding
			// it here means "reel me in on purpose" instead of the old unconditional auto-fly.
			// (Ordering: must stay AFTER the taut-line correction and BEFORE the pinball clamp.)
			if (CVB("vr_whip_contextual_yank", true) && (owner.player.cmd.buttons & BT_ATTACK))
			{
				double reelSpeed = CVF("vr_whip_reel_speed", 22.0);
				owner.Vel += rope * reelSpeed * 0.15;         // ramping pull while held (saturates to the ceiling in ~12 tics)
				if (d < 56.0) { EndGrapple(); return; }       // arrived
			}

			// Climb-to-pump-the-swing: off-hand grip (BT_USER1, unclaimed) shortens/lengthens the
			// effective rope length; angular momentum conservation (v*L = const) means shortening
			// speeds you up, same trick as a skater pulling their arms in.
			ApplySwingPump(rope);

			// Pinball safeguards -- clamp per-hit impulse, then the overall ceiling. Runs LAST so
			// it also catches anything ApplySwingPump or a stray native ApplyKickback added.
			ApplyGrapplePinballSafeguard();
		}
		else if (grappleMode == GM_YANK)
		{
			// bDestroyed guards a use-after-Destroy window: something else could destroy the victim
			// this same tic (before health drops), and reading a destroyed actor's fields is UB.
			if (grappleVictim == null || grappleVictim.bDestroyed || grappleVictim.health <= 0) { EndGrapple(); return; }

			int hand = bOffhandWeapon ? 1 : 0;
			double handSpeed = owner.GetHandVelocity(hand).Length();     // "the player velocity check"
			// "Easier Grabbing" gameplay toggle: scales EFFECTIVE mass (pull force only, not the
			// actor's real Mass/collision physics) for flags:grabprop props -- same toggle, keyword,
			// AND scale cvar the gravity-glove throw/pull code checks (p_user.cpp), kept consistent
			// here. Was a hardcoded 0.5; now vr_easy_grab_scale (native cvar, hw_vrmodes.cpp) so it's
			// user-tunable -- default unchanged. Same formula used by the entanglement pre-gate above.
			double yankMass = grappleVictim.Mass;
			if (CVB("vr_easy_grab_props", false) && grappleVictim.Keywords.IndexOf("flags:grabprop") != -1)
				yankMass *= CVF("vr_easy_grab_scale", 0.5);
			double massRatio = 100.0 / max(1.0, yankMass);      // mirrors the throw-formula convention
			// #1 CRITICAL (physics audit): clamp pullSpeed at the SOURCE. handSpeed is a raw VR
			// controller reading with NO ceiling anywhere in the native pipeline, so a tracking spike
			// (or a genuinely violent real swing) would otherwise inject an arbitrarily huge velocity
			// straight into a monster. Clamping here also keeps the Roll-tumble below consistent with
			// the actual pull.
			double pullSpeed = handSpeed * CVF("vr_whip_yank_force_scale", 1.0) * massRatio;
			pullSpeed = min(pullSpeed, CVF("vr_whip_yank_pull_cap", 45.0));
			double minSpeed  = CVF("vr_whip_entangle_minspeed", 4.0);

			if (grappleVictim.bBoss || pullSpeed < minSpeed)
			{
				if (grappleVictim.bBoss)
				{
					// reel the player toward the immovable boss -- guard .Unit() against a zero
					// vector (boss teleporting onto you, coincident positions), else NaN permanently
					// corrupts owner.Vel with no self-recovery. Route through the pinball safeguard so
					// this owner.Vel write is clamped like every other one.
					vector3 toVictim = grappleVictim.pos - owner.pos;
					if (toVictim.Length() > 0.001)
					{
						owner.Vel = toVictim.Unit() * CVF("vr_whip_reel_speed", 22.0);
						ApplyGrapplePinballSafeguard();
					}
					else EndGrapple();
				}
				else
					EndGrapple();          // too weak to catch -- the crack still hit via FireCrack, no pull
				return;
			}

			// ENTANGLED: pull toward a point in front of the player, not their exact origin, so a
			// follow-up melee swing actually connects instead of the enemy landing on/behind you.
			vector3 fwd = (cos(owner.angle), sin(owner.angle), 0.0);
			vector3 landing = owner.pos + fwd * WHIP_MELEE_LANDING_RANGE;

			// Reverse-throw ARC (Bulletstorm-style yank), not a flat straight-line drag. Horizontal
			// steering is continuous (still tracks a moving player); the vertical component climbs
			// toward an apex while there's meaningful ground left to cover, then hands off to the
			// object's own natural gravity to arc it back down as it closes in -- instead of fighting
			// gravity every tic with a raw 3D pull vector (which is why it used to read as "dragged
			// along the ground").
			vector2 toLandingXY = (landing.x - grappleVictim.pos.x, landing.y - grappleVictim.pos.y);
			double horizDist = toLandingXY.Length();
			vector2 horizDir = (horizDist > 0.001) ? toLandingXY / horizDist : (0.0, 0.0);

			double arcHeight = CVF("vr_whip_yank_arc_height", 80.0);
			double apexZ = max(owner.pos.z, grappleVictim.pos.z) + arcHeight;
			double liftNeeded = apexZ - grappleVictim.pos.z;

			double liftSpeed = 0.0;
			if (horizDist > WHIP_MELEE_LANDING_RANGE * 0.35 && liftNeeded > 0.0)
			{
				// Still meaningfully far out and below the arc's apex -- keep climbing toward it.
				liftSpeed = min(liftNeeded * 0.2, CVF("vr_whip_yank_lift_cap", 20.0));
			}
			// else: close enough, or already past the apex -- stop adding lift and let existing
			// Vel.Z + native gravity carry it back down into the landing, same as a real thrown
			// object falling out of its arc.

			grappleVictim.Vel.X = horizDir.X * pullSpeed;
			grappleVictim.Vel.Y = horizDir.Y * pullSpeed;
			grappleVictim.Vel.Z += liftSpeed;   // additive: blends with gravity's own per-tic pull

			// Clamp the RESULTANT victim speed every tic. Mirrors the owner-side pinball ceiling.
			// Full 3-vector clamp to match the native P_XYMovement backstop's shape.
			double vCeil = CVF("vr_whip_yank_vel_ceiling", 60.0);
			if (grappleVictim.Vel.Length() > vCeil)
				grappleVictim.Vel = grappleVictim.Vel.Unit() * vCeil;

			// roll/tumble, scaled to how hard the yank is -- Roll is a real, plain read/write
			// native field (actor.zs:111); harder yank, faster tumble.
			double rollScale = CVF("vr_whip_roll_speed_scale", 1.0);
			grappleVictim.Roll += clamp(pullSpeed * 0.4, 2.0, 40.0) * rollScale;

			// guaranteed vulnerability window -- whip-owned countdown (was grappleVictim.special1,
			// a shared actor scratch field other actors write -- collision risk, now whip-local).
			if (grappleEntangleTimer > 0)
			{
				grappleEntangleTimer--;
				if (ActiveWhip && (ActiveWhip.BehaviorFlags & WF_DISARM) != 0)
				{
					let ps = grappleVictim.FindState("Pain");
					if (ps) grappleVictim.SetState(ps);
					grappleVictim.reactiontime += 8;
				}
			}

			double d = (landing - grappleVictim.pos).Length();
			if (d < 40.0)
			{
				// Catch: hand a flags:grabprop prop (currently just ExplosiveBarrel) into the
				// player's native held-item slot instead of just dropping it loose on arrival --
				// from then on it's a normal held item (throwable, shootable, voxel-shown) via the
				// existing gravity-glove machinery. Monsters (no flags:grabprop) are unaffected --
				// they keep landing loose in front of the player exactly as before.
				if (grappleVictim.Keywords.IndexOf("flags:grabprop") != -1)
				{
					if (owner.VR_TrySetHeldItem(hand, grappleVictim))
					{
						if (CVB("vr_whip_catch_damage", false))
							owner.DamageMobj(self, owner, int(CVF("vr_whip_catch_damage_amount", 5.0)), 'None');
					}
				}
				EndGrapple();
			}
		}
	}

	// Angular-momentum-conserving rope-length change: v_new = v_old * (L_old / L_new). Shortening
	// the rope speeds up the tangential (swinging) component; lengthening slows it. Only the
	// tangential component is rescaled -- the radial component is already governed by the taut-line
	// constraint above and shouldn't be touched here.
	private void ApplySwingPump(vector3 rope)
	{
		int hand = bOffhandWeapon ? 1 : 0;
		int offHand = 1 - hand;                          // free hand's WEAPON SLOT
		int physOff = owner.VR_PhysicalHandForSlot(offHand);   // -> PHYSICAL controller index (handedness-correct)

		// [XR grip arbiter] Enable the rope-length pump on the free hand's GRIP (the arbiter granted it
		// GRIP_WHIP because rope-attached is published for that hand). Retires the old BT_USER1 gate for VR;
		// BT_USER1 stays as the flatscreen/no-VR fallback (matches every VR weapon's button-fallback rule).
		bool vrPump = owner.player.PlayInVR && CVB("vr_whip_grip_pump", true)
		              && owner.VR_GetGripOwner(physOff) == GRIP_WHIP;
		bool flatPump = !owner.player.PlayInVR && (owner.player.cmd.buttons & BT_USER1);
		if (!vrPump && !flatPump) return;

		vector3 offVel = owner.GetHandVelocity(physOff);      // physical-indexed (fixes latent slot-as-physical read)
		double climbRate = -(offVel dot rope);       // hand moving TOWARD anchor shortens the rope

		double pumpScale = CVF("vr_whip_swing_pump", 1.0);
		if (pumpScale <= 0.0) return;

		// Clamp the per-tic length CHANGE, not just the resulting distance. This bounds BOTH the
		// velocity rescale ratio (so a huge climbRate spike can't multiply your speed wildly in one
		// tic) AND the taut-line SetOrigin snap distance next tic (grappleDist can't jump far).
		// Clamping the derived ratio alone missed the position-teleport half. (Physics audit.)
		double maxStep = 8.0;   // max rope-length change per tic, map units
		double step = clamp(climbRate * pumpScale, -maxStep, maxStep);
		// Upper bound is max(grappleDist, Reach), NOT a flat Reach: a catch can legitimately start
		// with grappleDist > Reach (the trace originates hz above owner.pos -- see StartGrappleFromAim).
		// A flat Reach cap would SNAP such a rope down to Reach in one tic, defeating maxStep and
		// giving a free tangential-speed spike (ratio = grappleDist/newDist jumps well above 1). This
		// lets the rope only walk toward Reach at <= maxStep/tic. (Physics re-audit.)
		double newDist = clamp(grappleDist - step, WHIP_MIN_ROPE_DIST, max(grappleDist, ActiveWhip.Reach));
		if (abs(newDist - grappleDist) < 0.001) return;

		double ratio = grappleDist / max(0.0001, newDist);   // epsilon guard independent of the design floor
		vector3 tangential = owner.Vel - rope * (owner.Vel dot rope);
		owner.Vel = owner.Vel - tangential + tangential * ratio;
		grappleDist = newDist;
	}

	// Rope-tension knockback safety valve. Never touches the shared native ApplyKickback (used by
	// every actor in the game) -- this only re-clamps whatever the player's Vel already is each
	// tic while attached, regardless of what pushed it there (fireball, splash, swing-pump, etc.).
	private void ApplyGrapplePinballSafeguard()
	{
		vector3 delta = owner.Vel - prevGrappleVel;
		double deltaLen = delta.Length();

		// per-hit impulse cap, with diminishing returns on rapid repeat hits (anti-juggle-lock).
		// max(0.001,...) floors the CVar so a negative/zero config value can't turn the .Unit()
		// below into a zero-vector call (which would NaN owner.Vel). Belt-and-suspenders with the
		// deltaLen > 0.001 guard so a future refactor reading the CVar elsewhere is still safe.
		double perHitCap = max(0.001, CVF("vr_whip_grapple_hit_cap", 26.0));
		int t = level.maptime;
		if (t - lastBigImpulseTic < 10) perHitCap *= 0.5;

		if (deltaLen > perHitCap && deltaLen > 0.001)
		{
			owner.Vel = prevGrappleVel + delta.Unit() * perHitCap;
			lastBigImpulseTic = t;
		}

		// damage-aware taper: the more you've recently been hurt, the harder the ceiling clamps --
		// getting wrecked should read in the health bar, not as loss of physical control.
		double baseCeiling = max(0.001, CVF("vr_whip_grapple_vel_ceiling", 40.0));
		double hitScale    = CVF("vr_whip_grapple_hit_scale", 0.5);
		double ceiling = baseCeiling * clamp(1.0 - (recentDamage / 100.0) * hitScale, 0.25, 1.0);

		double speed = owner.Vel.Length();
		if (speed > ceiling && speed > 0.001)
			owner.Vel = owner.Vel.Unit() * ceiling;

		prevGrappleVel = owner.Vel;
	}

	void EndGrapple()
	{
		// [XR fling fix] Clear live-swing FIRST -- before any other statement -- so no future early-return
		// added above can leave it latched true and permanently suppress climb. Native climb resumes its
		// Vel + gravity management next tic. Pairs with the publish in UpdateGrapple's GM_ATTACHED branch.
		if (owner && owner.player) owner.VR_SetWhipSwingLive(false);
		// [XR grip arbiter] Clear rope-attached on BOTH physical hands (cheap, index-agnostic) so no stale
		// GRIP_WHIP grant survives the grapple ending regardless of which hand held it.
		if (owner && owner.player)
		{
			owner.VR_SetWhipRopeAttached(0, false);
			owner.VR_SetWhipRopeAttached(1, false);
		}
		if (grappleSetNoGrav && owner) owner.bNoGravity = false;
		grappleSetNoGrav = false;
		grappleActive = false;
		grappleMode = GM_NONE;
		grappleVictim = null;
		grappleTimer = 0;
		grappleEntangleTimer = 0;
		healthTracked = false;
	}

	// The taut grapple line, drawn as CONNECTED SDF SEGMENTS (engine-standalone, no AddGlowPanel).
	// Reuses the rope's chainLinks pool -- while grappling the rope isn't drawn, so the pool is free.
	private void RenderGrappleLine(vector3 handPos)
	{
		vector3 target = (grappleMode == GM_YANK && grappleVictim)
			? grappleVictim.pos + (0, 0, grappleVictim.Height * 0.5)
			: grappleAnchor;
		vector3 seg = target - handPos;
		vector3 headPos = owner ? owner.GetHeadPos() : pos;
		Color cc = ActiveWhip.CordColor;
		vector3 fcol = (cc.r / 255.0, cc.g / 255.0, cc.b / 255.0) * 1.3;

		int steps = 12;
		for (int i = 0; i < steps; i++)
		{
			if (i >= chainLinks.Size())
				chainLinks.Push(XRWhipChainLink(Spawn("XRWhipChainLink", handPos)));
			XRWhipChainLink lk = chainLinks[i];
			if (!lk) continue;
			vector3 a = handPos + seg * (double(i)     / double(steps));
			vector3 b = handPos + seg * (double(i + 1) / double(steps));
			vector3 faceN = headPos - (a + b) * 0.5;
			if (faceN.Length() < 0.0001) faceN = (0.0, 0.0, 1.0);
			lk.OrientSegment(a, b, faceN.Unit(), 5.0);
			lk.msdf_enabled = 512;
			lk.msdf_glitch  = 0.05;
			lk.msdf_color   = fcol;
			lk.Alpha = 1.0;
		}
		HideChain(steps);
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
			DestroyChain();
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
		bool twoHand = CVB("vr_whip_two_hand_boost", true) && (otherPos - handPos).Length() < WHIP_TWOHAND_R;
		vector3 assistVel = twoHand ? owner.GetHandVelocity(1 - hand) : (0.0, 0.0, 0.0);

		SimulateRope(handPos, assistVel, twoHand);

		// Tier 2 is now the DEFAULT visual: the rigged 300-map-unit braided-leather IQM
		// (models/weapons/xrwhip/whip_rigged.iqm), bones driven straight from the Verlet sim
		// every tic. `vr_whip_model` used to gate this but was never declared in CVARINFO --
		// the model was silently unreachable, not actually "opt-in." Now declared, defaulted
		// true (CVARINFO), with a menu toggle -- an escape hatch back to the glow-panel rope
		// if the rigged model ever looks wrong in-headset (bone axis/rest-length are
		// best-known values per DriveModelBones()'s own comment, not yet in-headset confirmed).
		// The Indiana Jones leather profile (WhipModel='XRWhipRigged') drives the rigged IQM;
		// the Techno/elemental profiles (WhipModel='') always take the SDF chain path. The
		// vr_whip_model toggle is an escape hatch: OFF forces the SDF chain even for leather.
		bool useModel = CVB("vr_whip_model", true) && ActiveWhip && ActiveWhip.WhipModel != '';
		if (useModel)
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

		// Rope visual: the rigged leather MODEL (Indy) when useModel, otherwise the connected
		// SDF CHAIN (default for techno/elemental, and the fallback if vr_whip_model is off).
		// Never both -- so a real leather whip doesn't get a chain drawn down its own length.
		if (!useModel) RenderRope();
		else HideChain(0);

		// crack evaluation
		XRWhipNode tipN = nodes[nodes.Size() - 1];
		vector3 tipVel = tipN.pos - tipN.prev;
		double tipSpeed = tipVel.Length();
		double handSpeed = owner.GetHandVelocity(hand).Length();
		double effTip = max(tipSpeed, handSpeed);      // sim leads, hand speed is the floor

		// decay-peak-hold for the GM_YANK entanglement pre-gate (see field comment) -- runs here,
		// not inside UpdateGrapple, because this whole function returns early while grappleActive
		// (Tick() line ~889), i.e. it only samples while NOT already grappling, which is exactly
		// the window before an AltFire press that the pre-gate needs to see.
		handSpeedPeak = max(handSpeed, handSpeedPeak * CVF("vr_whip_yank_peak_decay", 0.85));

		// vr_whip_crack_threshold is a global override on top of the profile's own CrackSpeed --
		// profiles differ from each other by a multiplicative ratio to their own 95.0 baseline, so
		// changing the CVar shifts every profile together instead of erasing their differences.
		double crackAt = ActiveWhip.CrackSpeed * (CVF("vr_whip_crack_threshold", 95.0) / 95.0);
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
		// Fire's role changes while grappling: it's the deliberate-reel input (read directly from
		// cmd.buttons in UpdateGrapple), not another attack. Without this guard, holding both
		// buttons together would re-trigger a full lash/LineAttack every tic via A_WeaponReady's
		// normal fire-button polling, stacking damage on top of the pull.
		if (invoker.grappleActive) return;

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
