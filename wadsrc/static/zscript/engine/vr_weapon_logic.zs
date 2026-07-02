class WeaponReplacementHandler : StaticEventHandler
{
	override void CheckReplacement(CheckReplacementEvent e)
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
			p.GiveInventory("HandGrenade", 3);
			
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
		}
	}
}
