class WeaponReplacementHandler : StaticEventHandler
{
	override void CheckReplacement(ReplaceEvent e)
	{
		// Replacement logic based on CVars
		
		if (e.Replacee == "Chainsaw")
		{
			if (frandom(0, 100) < CVar.GetCVar("vr_chainsaw_flame_chance").GetFloat())
			{
				e.Replacement = "Flamethrower";
				e.IsFinal = true;
			}
		}
		else if (e.Replacee == "Chaingun")
		{
			float rChance = CVar.GetCVar("vr_chaingun_rifle_chance").GetFloat();
			float sChance = CVar.GetCVar("vr_chaingun_smg_chance").GetFloat();
			float roll = frandom(0, 100);
			
			if (roll < rChance)
			{
				e.Replacement = "Rifle";
				e.IsFinal = true;
			}
			else if (roll < rChance + sChance)
			{
				e.Replacement = "SMG";
				e.IsFinal = true;
			}
		}
		else if (e.Replacee == "Pistol" || e.Replacee == "Rifle")
		{
			if (frandom(0, 100) < CVar.GetCVar("vr_weapon_revolver_chance").GetFloat())
			{
				e.Replacement = "Revolver";
				e.IsFinal = true;
			}
		}
		else if (e.Replacee == "RocketLauncher")
		{
			if (frandom(0, 100) < CVar.GetCVar("vr_weapon_m79_chance").GetFloat())
			{
				e.Replacement = "M79";
				e.IsFinal = true;
			}
		}
		else if (e.Replacee == "Shotgun")
		{
			if (frandom(0, 100) < CVar.GetCVar("vr_shotgun_ssg_chance").GetFloat())
			{
				e.Replacement = "SuperShotgun";
				e.IsFinal = true;
			}
		}
		else if (e.Replacee == "PlasmaRifle")
		{
			if (frandom(0, 100) < CVar.GetCVar("vr_plasma_bfg_chance").GetFloat())
			{
				e.Replacement = "BFG9000";
				e.IsFinal = true;
			}
		}
		else if (e.Replacee == "RocketAmmo" || e.Replacee == "RocketBox")
		{
			if (frandom(0, 100) < 20) // 20% chance to find grenades in rocket stashes
			{
				e.Replacement = "HandGrenade";
				e.IsFinal = true;
			}
		}
	}

	override void WorldThingSpawned(WorldEvent e)
	{
		if (!e.Thing || !e.Thing.player) return;

		PlayerPawn p = PlayerPawn(e.Thing);
		if (p)
		{
			// --- Grenades: toggle + count ---
			if (CVar.GetCVar("vr_start_with_grenade").GetBool())
			{
				int gc = CVar.GetCVar("vr_start_grenade_count").GetInt();
				if (gc > 0) p.GiveInventory("HandGrenade", gc);
			}

			// --- Rifle REPLACES the Pistol at spawn ---
			if (CVar.GetCVar("vr_start_with_rifle").GetBool())
			{
				if (p.FindInventory("Pistol"))
				{
					p.TakeInventory("Pistol", 1);
					p.GiveInventory("Rifle", 1);
					if (p.player.ReadyWeapon is "Pistol")
					{
						p.player.ReadyWeapon = Weapon(p.FindInventory("Rifle"));
					}
				}
			}

			// --- Opt-in grab tools (granted here) ---
			if (CVar.GetCVar("vr_start_with_whip").GetBool() && !p.FindInventory("XRWhip"))
				p.GiveInventory("XRWhip", 1);
			if (CVar.GetCVar("vr_start_with_shieldsaw").GetBool() && !p.FindInventory("ShieldSaw"))
				p.GiveInventory("ShieldSaw", 1);

			// --- Opt-out of the default StartItem loadout (doomplayer.zs gives these; toggle off removes) ---
			if (!CVar.GetCVar("vr_start_with_sword").GetBool())   p.TakeInventory("VRSword", 1);
			if (!CVar.GetCVar("vr_start_with_icehook").GetBool()) p.TakeInventory("IceHook", 1);
			if (!CVar.GetCVar("vr_start_with_pistol").GetBool())  p.TakeInventory("Pistol", 1);
			if (!CVar.GetCVar("vr_start_with_fist").GetBool())    p.TakeInventory("Fist", 1);

			// --- Dual-wield starting loadout: spawn holding a matched pair (one gun per hand) ---
			// vr_start_dualwield: 0 off, 1 = 2x Revolver, 2 = 2x Pistol, 3 = 2x SMG. Gives the base
			// gun + its distinct "_2" variant (both real classes in weapon_dualwield_variants.zs) and
			// equips one into each hand, mirroring PlayerPawn.VR_GiveDualWield's bring-up path.
			int dw = CVar.GetCVar("vr_start_dualwield").GetInt();
			if (dw > 0)
			{
				String baseName = "";
				if      (dw == 1) baseName = "Revolver";
				else if (dw == 2) baseName = "Pistol";
				else if (dw == 3) baseName = "SMG";

				if (baseName != "")
				{
					String varName = baseName .. "_2";
					// Grant the pair (both share the base's reserve ammo pool via inheritance).
					if (!p.FindInventory(baseName)) p.GiveInventory(baseName, 1);
					if (!p.FindInventory(varName))  p.GiveInventory(varName, 1);

					Weapon wb = Weapon(p.FindInventory(baseName));
					Weapon wv = Weapon(p.FindInventory(varName));
					if (wb && wv)
					{
						// Clear both hands, then bring each gun up into its assigned hand. Setting
						// bOffhandWeapon + PendingWeapon and calling BringUpWeapon is the same path
						// VR_GiveDualWield uses, so the PSprite/hand wiring matches a live dual-grab.
						p.player.ReadyWeapon = null;
						p.player.OffhandWeapon = null;

						wb.bOffhandWeapon = false;
						if (wb.SisterWeapon) wb.SisterWeapon.bOffhandWeapon = false;
						p.player.PendingWeapon = wb;
						p.BringUpWeapon();

						wv.bOffhandWeapon = true;
						if (wv.SisterWeapon) wv.SisterWeapon.bOffhandWeapon = true;
						p.player.PendingWeapon = wv;
						p.BringUpWeapon();

						p.player.PendingWeapon = WP_NOCHANGE;
					}
				}
			}
		}
	}
}
