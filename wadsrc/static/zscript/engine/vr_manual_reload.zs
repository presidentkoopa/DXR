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
		int avail = Ammo1 ? Ammo1.Amount : magSize;
		XRChamber = min(magSize, avail);
	}

	// VR Weapon Options toggle. Default true (ship features on; user is in VR).
	bool XR_ManualReloadEnabled()
	{
		CVar c = CVar.FindCVar("vr_manual_reload");
		return c ? c.GetBool() : true;
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
}
