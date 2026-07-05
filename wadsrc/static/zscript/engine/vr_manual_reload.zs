// ----------------------------------------------------------------------------
// vr_manual_reload.zs -- reusable manual-reload layer for the DoomXR arsenal.
//
// Per-weapon CHAMBER counter (rounds actually loaded) separate from reserve
// ammo. Firing is gated on the chamber; reloading transfers reserve into the
// chamber while the weapon plays its OWN authored reload animation.
//
// RELOAD VISUAL = the artist's baked frames. Every one of these weapon MD3s
// already contains a full, hand-animated reload as vertex-morph frames
// (e.g. Pistol.md3 frames 8-25 = PISR A-R; Plasma frames 18-29 = PLSR A-L).
// The reload is driven by stepping a reload SPRITE mapped to those frames in
// modeldef.txt -- exactly how the source mods (vanillaweapons/RLVR) drive it,
// and faithful to how each gun was designed to animate. This layer does NOT
// author any motion; it only counts rounds and tops the chamber at the right
// moment in the weapon's Reload state.
//
// Master toggle: vr_manual_reload (VR Weapon Options > "Manual Reload").
// OFF = original behavior (chamber never gates, no reload routing).
//
// Include BEFORE any weapon that uses the mixin.
// ----------------------------------------------------------------------------

mixin class XR_ManualReload
{
	int XRChamber;         // rounds currently loaded
	int XRMagSize;         // capacity
	bool XRReloading;      // true while the Reload state is running
	string XRMagClass;     // [XR] pouch magazine class this weapon pulls (XRMag_Chaingun etc.); "" = generic XRReloadMag
	bool XRChamberPreset;  // [XR] a dropped-gun handler pre-set a random chamber -- InitChamber must not overwrite it

	// AMMO MODEL: reserve ammo (Ammo1) is the player's TOTAL round count and is the
	// only true resource -- it drains normally per shot via the weapon's existing
	// A_BallisticFire/DepleteAmmo, unchanged. XRChamber is a SUB-LIMIT: how many of
	// those rounds can be fired before a reload is required. Firing drops both
	// together; reload just refills the chamber from whatever the total currently is
	// (no separate reserve deduction -- the rounds were always counted in the total).
	// This keeps the existing fire code correct with zero refund logic, and the
	// toggle-off path is exactly vanilla (chamber never gates, reload never entered).
	void XR_InitChamber(int magSize)
	{
		XRMagSize = magSize;
		if (XRChamberPreset) return;   // [variable dropped-gun ammo] keep the pre-set random/partial chamber
		int avail = Ammo1 ? Ammo1.Amount : magSize;
		XRChamber = min(magSize, avail);
	}

	// VR Weapon Options toggle. Default true (ship features on; user is in VR).
	bool XR_ManualReloadEnabled()
	{
		CVar c = CVar.FindCVar("vr_manual_reload");
		return c ? c.GetBool() : false;   // [XR] OPT-IN: default OFF -> unlimited fire, no chamber gate
	}

	// Call from Ready, before A_WeaponReady, to auto-route to the Reload state
	// when the chamber is empty. (On-demand reload via the reload button is
	// handled separately by A_WeaponReady(WRF_ALLOWRELOAD) + the Reload state.)
	// Returns a state so the psprite actually jumps to Reload (called as a 0-tic state action,
	// e.g. `GLAN A 0 A_XR_CheckChamber("Reload")`). Returning null continues the normal flow.
	// (invoker.SetStateLabel would set the weapon actor's own state, not the displayed psprite.)
	action state A_XR_CheckChamber(statelabel stateReload)
	{
		if (!invoker.XR_ManualReloadEnabled()) return null;
		if (invoker.XRChamber <= 0 && !invoker.XRReloading)
		{
			invoker.XRReloading = true;
			return ResolveState(stateReload);
		}
		return null;
	}

	// Chamber-gated fire. Returns true (and decrements the chamber) if a round
	// is available; otherwise plays a dry-click and returns false. When the
	// toggle is OFF this always returns true (unlimited chamber = old behavior).
	action bool A_XR_TryFire()
	{
		if (!invoker.XR_ManualReloadEnabled()) return true;

		if (invoker.XRChamber <= 0 || invoker.XRReloading)
		{
			A_StartSound("weapons/pistol", CHAN_WEAPON, volume: 0.35, attenuation: ATTN_NORM); // dry-click stand-in
			return false;
		}
		invoker.XRChamber--;
		return true;
	}

	// Mark the start of a reload sequence (used when the reload is entered on
	// demand via the reload button rather than the empty-chamber auto-route).
	action void A_XR_StartReload()
	{
		invoker.XRReloading = true;
	}

	// Refill the chamber from the reserve TOTAL. Call once, near the END of the
	// weapon's authored Reload state (the beat where the fresh round seats). No
	// reserve deduction -- reserve already counts the loaded rounds; the chamber
	// is just re-armed up to min(magSize, rounds you still have). Clears reloading.
	action void A_XR_RefillChamber()
	{
		int avail = invoker.Ammo1 ? invoker.Ammo1.Amount : 0;
		invoker.XRChamber = min(invoker.XRMagSize, avail);
		invoker.XRReloading = false;
	}

	// [XR] The reload BIND, in VR, is the EJECT: it drops the current magazine (chamber -> 0) and hands
	// off to the chest-pouch gesture (vr_ammo_pouch.zs -> reach chest, grip, seat, chambered). It does
	// NOT refill here -- the physical grab does. Call as the FIRST line of a weapon's Reload state:
	//   <SPR> A 0 A_XR_EjectToPouch();   // VR: eject -> Ready (pouch reloads); flatscreen: falls through
	// Returns "Ready" when the VR eject fired; returns null on flatscreen / toggle-off so the weapon's
	// own timed Reload beat + A_XR_RefillChamber run instead (no pouch to reach without controllers).
	action state A_XR_EjectToPouch()
	{
		if (!invoker.XR_ManualReloadEnabled()) return null;
		if (!self.player || !self.player.PlayInVR) return null;   // flatscreen: run the timed beat below
		CVar ej = CVar.FindCVar("vr_pouch_eject");
		if (ej && !ej.GetBool()) return null;   // eject disabled -> run the timed beat instead

		// [XR tactical] "1 in the barrel": if the mag still has rounds and tactical eject is on, KEEP the
		// chambered round (forfeit the partial mag) and drop the FSM to MAG_OUT via the native path -- you can
		// still fire the pipe round while the fresh mag comes in. Otherwise it's a dry eject (chamber -> 0).
		bool tactical = false;
		if (invoker.XRChamber > 0)
		{
			CVar tacc = CVar.FindCVar("vr_reload_tactical");
			if (!tacc || tacc.GetBool())
			{
				self.VR_BeginTacticalEject();   // native: clamps XRChamber to 1, sets MAG_OUT, opens perfect window
				tactical = true;
			}
		}
		if (!tactical) invoker.XRChamber = 0;   // mag out -> chamber empty -> FSM VRRL_EMPTY opens the pouch
		invoker.XRReloading = false;   // the physical grab completes it, not this state
		A_StartSound("misc/w_pkup", CHAN_BODY, volume: 0.5, attenuation: ATTN_NORM);  // eject "clunk" (placeholder)
		double hap = 0.7;
		CVar rh = CVar.FindCVar("vr_reload_haptic");
		if (rh) hap *= rh.GetFloat();
		self.VR_HapticPulse(invoker.bOffhandWeapon ? 1 : 0, hap, 0.08);   // eject rumble

		// [juice] fling a PHYSICAL spent mag along your aim -- it falls, litters, and staggers
		// a monster you eject it into ("reloaded into their face"). Heavier guns lob a heavier,
		// slower mag; colour hints the ammo type. See vr_reload_juice.zs.
		Color flair = Color(255, 150, 40, 255);   // default eject spark
		double tier = 1.0; int magMass = 8;
		if (invoker is "BFG9000" || invoker is "RocketLauncher") { tier = 0.7;  magMass = 60; flair = Color(120, 200, 255, 255); }
		else if (invoker is "Chaingun")    { tier = 0.8;  magMass = 40; }
		else if (invoker is "PlasmaRifle") { tier = 0.95; magMass = 14; flair = Color(120, 255, 220, 255); }
		else if (invoker is "Pistol" || invoker is "SMG") { tier = 1.2; magMass = 4; }

		CVar tc = CVar.FindCVar("vr_reload_mag_throw");
		let pp = PlayerPawn(self);
		Vector3 gunPos = pp ? pp.AttackPos : self.pos + (0, 0, self.height * 0.62);
		if (!tc || tc.GetBool())
		{
			double base = 12.0;
			CVar ec = CVar.FindCVar("vr_reload_mag_eject_speed");
			if (ec) base = ec.GetFloat();
			Vector3 dir = (cos(self.angle), sin(self.angle), 0.35);
			Actor sm = Actor.Spawn("XRSpentMag", gunPos);
			if (sm)
			{
				sm.Mass = magMass;
				sm.target = self;
				// [offhand-throw] optionally hand the ejected mag to your OFF-HAND so you catch it and
				// throw it yourself (flick to fling for dmg+stun); otherwise it auto-flings along aim.
				CVar oh = CVar.FindCVar("vr_reload_mag_to_offhand");
				let spent = XRSpentMag(sm);
				if (spent && oh && oh.GetBool())
				{
					spent.heldOff = true;
					spent.wasGrip = true;      // you're already gripping from the eject press
					sm.Vel = (0, 0, 0);
				}
				else
				{
					sm.Vel = dir.Unit() * base * tier;
				}
			}
		}
		// [flair] eject spark at the gun so it reads in the dark
		self.Level.AddGlowPanel(flair, 16.0, gunPos.x, gunPos.y, gunPos.z, 15, 1.0, 0.0, 0.0, 0);

		return ResolveState("Ready");
	}
}
