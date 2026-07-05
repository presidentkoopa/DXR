// ----------------------------------------------------------------------------
// vr_reload_debug.zs -- DEBUG visualisation for the VR manual-reload gesture.
//
// Draws REAL 3D wireframe-cube models (models/debug/wirebox.obj, 12 edge tubes) at
// the reach targets so you can SEE the zones in the headset instead of guessing:
//   * both HANDS       -> green boxes   (AttackPos / OffhandPos)
//   * held CLIPS       -> cyan boxes    (every live XRReloadMag in the world)
//   * the chest POUCH  -> white box     (the reach-in anchor, mirrors vr_ammo_pouch.zs)
//
//   * hotspots         -> magenta magwell / yellow rack / orange foregrip
//                         (world pos from the native FSM getter VR_GetWeaponHotspot)
//
// Hotspot boxes are LIVE (VR_GetWeaponHotspot lands with the Phase-1 rebuild); a hotspot
// the weapon doesn't define returns (0,0,0) and is skipped so no box sticks at the origin.
//
// Master toggle: vr_reload_debug (default OFF). Per-category sub-toggles. This is a
// pure visual overlay -- it feeds nothing and changes no gameplay.
//
// Data-only (ZScript + model + modeldef) -- rides in on a pk3 repack, no C++ compile.
// ----------------------------------------------------------------------------

// Invisible carrier actor; its body is the wirebox model bound in modeldef.txt.
// +NOSAVEGAME so debug props never pollute a save (the handler respawns them each tic).
class XRWireBox : Actor
{
	Default
	{
		+NOGRAVITY +NOBLOCKMAP +NOINTERACTION +DONTSPLASH +NOSAVEGAME +BRIGHT
		RenderStyle "Add";
		Alpha 0.85;
	}
	States { Spawn: TNT1 A -1; Stop; }
}
// One subclass per colour so each binds its own solid-colour skin in modeldef.
class XRWireBoxGreen   : XRWireBox {}
class XRWireBoxCyan    : XRWireBox {}
class XRWireBoxMagenta : XRWireBox {}
class XRWireBoxYellow  : XRWireBox {}
class XRWireBoxOrange  : XRWireBox {}
class XRWireBoxWhite   : XRWireBox {}

class XRReloadDebug : StaticEventHandler
{
	Actor handBox[2];
	Actor clipBox[2];
	Actor pouchBox;
	Actor hotBox[3];   // magwell / rack / foregrip -- driven by VR_GetWeaponHotspot (Phase-1 native)

	// Spawn-or-move a box to pos, scaled so the unit cube becomes `edge` map units.
	// (Model honours actor Scale: Scale.X -> X/Y, Scale.Y -> Z, so equal = uniform.)
	Actor PlaceBox(Actor b, class<Actor> cls, Vector3 pos, double edge)
	{
		if (!b || b.bDestroyed)
			b = Actor.Spawn(cls, pos);
		if (b)
		{
			double s = CVarF("vr_reload_debug_scale", 1.0);
			b.SetOrigin(pos, false);
			b.Scale = (edge * s, edge * s);
		}
		return b;
	}

	// Destroy a box if it exists; always returns null so the caller nulls its ref.
	Actor Kill(Actor b)
	{
		if (b && !b.bDestroyed) b.Destroy();
		return null;
	}

	bool SubOn(string cv)
	{
		CVar c = CVar.FindCVar(cv);
		return !c || c.GetBool();   // default ON when the sub-toggle is absent
	}
	double CVarF(string cv, double def)
	{
		CVar c = CVar.FindCVar(cv);
		return c ? c.GetFloat() : def;
	}

	void TearDown()
	{
		handBox[0] = Kill(handBox[0]); handBox[1] = Kill(handBox[1]);
		clipBox[0] = Kill(clipBox[0]); clipBox[1] = Kill(clipBox[1]);
		pouchBox   = Kill(pouchBox);
		hotBox[0] = Kill(hotBox[0]); hotBox[1] = Kill(hotBox[1]); hotBox[2] = Kill(hotBox[2]);
	}

	override void WorldTick()
	{
		CVar dbg = CVar.FindCVar("vr_reload_debug");
		PlayerInfo p = players[consoleplayer];
		PlayerPawn pmo = p ? PlayerPawn(p.mo) : null;

		if (!dbg || !dbg.GetBool() || !pmo || !pmo.player || !pmo.player.PlayInVR)
		{
			TearDown();
			return;
		}

		// --- HANDS (green) ---
		if (SubOn("vr_reload_debug_hands"))
		{
			handBox[0] = PlaceBox(handBox[0], "XRWireBoxGreen", pmo.AttackPos, 7.0);
			handBox[1] = PlaceBox(handBox[1], "XRWireBoxGreen", pmo.OffhandPos, 7.0);
		}
		else { handBox[0] = Kill(handBox[0]); handBox[1] = Kill(handBox[1]); }

		// --- CLIPS (cyan) -- box every live reload mag (XRReloadMag + subclasses) ---
		if (SubOn("vr_reload_debug_clips"))
		{
			int idx = 0;
			ThinkerIterator it = ThinkerIterator.Create("XRReloadMag");
			while (idx < 2)
			{
				Thinker t = it.Next();
				if (!t) break;
				Actor mag = Actor(t);
				if (!mag) continue;
				clipBox[idx] = PlaceBox(clipBox[idx], "XRWireBoxCyan", mag.pos, 5.0);
				idx++;
			}
			for (; idx < 2; idx++) clipBox[idx] = Kill(clipBox[idx]);
		}
		else { clipBox[0] = Kill(clipBox[0]); clipBox[1] = Kill(clipBox[1]); }

		// --- POUCH anchor (white) -- same body-relative math as vr_ammo_pouch.zs ---
		if (SubOn("vr_reload_debug_pouch"))
		{
			double ph = CVarF("vr_pouch_height", 40.0);
			double pf = CVarF("vr_pouch_forward", 0.0);
			double pr = CVarF("vr_pouch_radius", 18.0);
			Vector3 chest = pmo.pos + (cos(pmo.angle)*pf, sin(pmo.angle)*pf, ph);
			pouchBox = PlaceBox(pouchBox, "XRWireBoxWhite", chest, pr);
		}
		else pouchBox = Kill(pouchBox);

		// --- HOTSPOTS (magenta magwell / yellow rack / orange foregrip) ---
		// World positions come from the native FSM (VR_GetWeaponHotspot -> VR_WeaponHotspotWorld).
		// A zero vector means "no such hotspot on this weapon" (no IQM bone + no geometric fallback);
		// don't draw a box stuck at the world origin in that case.
		if (SubOn("vr_reload_debug_hotspots") && pmo.player.ReadyWeapon)
		{
			Weapon w = pmo.player.ReadyWeapon;
			Vector3 mw = w.VR_GetWeaponHotspot("hs_magwell");
			Vector3 rk = w.VR_GetWeaponHotspot("hs_rack");
			Vector3 fg = w.VR_GetWeaponHotspot("hs_foregrip");
			if (mw != (0,0,0)) hotBox[0] = PlaceBox(hotBox[0], "XRWireBoxMagenta", mw, 4.0); else hotBox[0] = Kill(hotBox[0]);
			if (rk != (0,0,0)) hotBox[1] = PlaceBox(hotBox[1], "XRWireBoxYellow",  rk, 4.0); else hotBox[1] = Kill(hotBox[1]);
			if (fg != (0,0,0)) hotBox[2] = PlaceBox(hotBox[2], "XRWireBoxOrange",  fg, 4.0); else hotBox[2] = Kill(hotBox[2]);
		}
		else { hotBox[0] = Kill(hotBox[0]); hotBox[1] = Kill(hotBox[1]); hotBox[2] = Kill(hotBox[2]); }
	}
}
