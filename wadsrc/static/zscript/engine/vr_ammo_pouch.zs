// ----------------------------------------------------------------------------
// vr_ammo_pouch.zs -- chest-level ammo pouch for the VR manual-reload gesture.
//
// THE MISSING KEYSTONE. The native reload FSM (VR_UpdateWeaponReload, p_user.cpp)
// only SEATS a magazine you are already holding (an item tagged "xr_mag") into the
// gun. Nothing ever put that mag in your hand -- so the physical reload could never
// start. This handler is the front half: it draws a wireframe box at your chest, and
// when your hand reaches into it and grips, it spawns the ready weapon's magazine
// straight into that hand (via VR_TrySetHeldItem -> player_t::vr_held_items, the
// EXACT slot the FSM reads). From there the compiled FSM takes over: carry the mag
// to the gun's hs_magwell, grip to seat, rack, chambered.
//
// Pure ZScript -- feeds the already-compiled C++ FSM, no engine rebuild.
//
// Placement is CVar-tunable (you dial it in from the headset): vr_pouch_height,
// vr_pouch_forward, vr_pouch_radius. Gated on the same vr_manual_reload toggle.
// ----------------------------------------------------------------------------

// The spawned magazine. Invisible base sprite; its visible body is a model bound in
// modeldef.txt. "xr_mag" is the load-bearing keyword the FSM scans for (p_user.cpp:2498).
class XRReloadMag : Actor
{
	Default
	{
		Radius 4;
		Height 4;
		+NOGRAVITY
		+NOBLOCKMAP
		+NOINTERACTION      // no physics/collision; the held-item system positions it at the hand
		+DONTSPLASH
		Keywords "xr_mag";  // FSM only seats a held item carrying this keyword
	}
	States
	{
	Spawn:
		TNT1 A -1;          // model comes from modeldef (Model XRReloadMag ...); TNT1 = invisible sprite
		Stop;
	}
}

// Per-ammo-type magazines. Each binds its own model in modeldef.txt (mag_chaingun etc.).
// A weapon selects one by setting its mixin field XRMagClass in Ready/Select; unset weapons
// fall back to the generic XRReloadMag (pistol mag) below.
class XRMag_Chaingun : XRReloadMag {}
class XRMag_Plasma   : XRReloadMag {}
class XRMag_Shell    : XRReloadMag {}   // shotgun/SSG
class XRMag_Pod      : XRReloadMag {}   // BFG / rocket / M79 (energy pod / rocket)
class XRMag_Can      : XRReloadMag {}   // flamethrower fuel can

// ----------------------------------------------------------------------------
class XRAmmoPouch : StaticEventHandler
{
	bool gripPrev[2];   // per-hand grip rising-edge latch
	Actor pouchBox;     // persistent wireframe box marking the chest pouch anchor

	// Destroy the marker box (call on every early-out so it never lingers).
	void KillBox() { if (pouchBox && !pouchBox.bDestroyed) pouchBox.Destroy(); pouchBox = null; }

	override void WorldTick()
	{
		PlayerInfo p = players[consoleplayer];
		if (!p) { KillBox(); return; }
		PlayerPawn pmo = PlayerPawn(p.mo);
		if (!pmo || !pmo.player || !pmo.player.PlayInVR) { KillBox(); return; }

		// Master toggle -- reuse the manual-reload switch (VR Weapon Options).
		CVar mr = CVar.FindCVar("vr_manual_reload");
		if (mr && !mr.GetBool()) { KillBox(); return; }

		Weapon w = p.ReadyWeapon;
		if (!w) { KillBox(); return; }

		// Which pouch weapon + which magazine? `w is "Name"` is a safe RUNTIME check (no compile-time
		// dependency on weapon classes that are #included later). No chamber-count gate here: ZScript has
		// no generic field reader (IntVar/StringVar are C++-only), and the native FSM only SEATS a mag
		// when the chamber is actually empty, so grabbing one when full is a harmless no-op.
		class<Actor> magCls = "XRReloadMag";
		if (w is "Chaingun")                                    magCls = "XRMag_Chaingun";
		else if (w is "PlasmaRifle")                            magCls = "XRMag_Plasma";
		else if (w is "Shotgun" || w is "SuperShotgun")         magCls = "XRMag_Shell";
		else if (w is "BFG9000" || w is "RocketLauncher")       magCls = "XRMag_Pod";
		else if (w is "ID24Incinerator" || w is "ID24CalamityBlade" || w is "Flamethrower") magCls = "XRMag_Can";
		else if (!(w is "Rifle" || w is "SMG" || w is "Pistol" || w is "Revolver")) { KillBox(); return; }   // not a pouch-reload weapon

		// --- Chest anchor (body-relative, CVar-tunable so you place it from the headset) ---
		double ph = 40.0;  { CVar c = CVar.FindCVar("vr_pouch_height");  if (c) ph = c.GetFloat(); }
		double pf =  0.0;  { CVar c = CVar.FindCVar("vr_pouch_forward"); if (c) pf = c.GetFloat(); }
		double pr = 18.0;  { CVar c = CVar.FindCVar("vr_pouch_radius");  if (c) pr = c.GetFloat(); }
		double fx = cos(pmo.angle);
		double fy = sin(pmo.angle);
		Vector3 chest = pmo.pos + (fx * pf, fy * pf, ph);

		// --- Pouch marker: a REAL 3D wireframe cube at the chest anchor (NOT a billboard). ---
		// The old neon glow-panel was camera-facing, so it read as a flat blue plane splitting the
		// body. This wirebox is actual geometry sized to the reach radius, so you can see the pouch
		// volume without a plane in your face. Gated on the same vr_pouch_marker toggle.
		CVar mk = CVar.FindCVar("vr_pouch_marker");
		if (!mk || mk.GetBool())
		{
			if (!pouchBox || pouchBox.bDestroyed)
				pouchBox = Actor.Spawn("XRWireBoxWhite", chest);
			if (pouchBox)
			{
				pouchBox.SetOrigin(chest, false);
				pouchBox.Scale = (pr, pr);   // unit cube -> pr map units per edge (matches reach radius)
			}
		}
		else KillBox();

		// --- Reach-in + grip => spawn the mag (magCls chosen above) into that hand ---
		for (int hand = 0; hand < 2; hand++)
		{
			Vector3 handPos = (hand == 0) ? pmo.AttackPos : pmo.OffhandPos;
			double dist = (handPos - chest).Length();
			bool gripNow = pmo.GetGripValue(hand) > 0.5;
			bool edge = gripNow && !gripPrev[hand];
			gripPrev[hand] = gripNow;

			if (dist <= pr && edge)
			{
				Actor mag = Actor.Spawn(magCls, handPos);
				if (!mag) continue;
				if (!pmo.VR_TrySetHeldItem(hand, mag))
				{
					mag.Destroy();   // that hand was already full
				}
				else
				{
					double hap = 0.6;
					CVar rh = CVar.FindCVar("vr_reload_haptic");
					if (rh) hap *= rh.GetFloat();
					pmo.VR_HapticPulse(hand, hap, 0.06);   // pouch-grab rumble
				}
			}
		}
	}
}
