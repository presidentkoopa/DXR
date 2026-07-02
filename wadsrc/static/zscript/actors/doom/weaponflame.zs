// --------------------------------------------------------------------------
//
// Flamethrower
//
// --------------------------------------------------------------------------

class Flamethrower : DoomWeapon
{
	Default
	{
		Weapon.SelectionOrder 1800;
		Weapon.AmmoUse 1;
		Weapon.AmmoGive 50;
		Weapon.AmmoType "Fuel";
		Inventory.PickupMessage "Picked up a Flamethrower!";
		Tag "Flamethrower";
		Keywords "mass:60", "grab", "class:flamethrower", "dmg:fire", "style:stream", "weight:medium", "range:short", "fire:continuous", "role:crowd_control";
	}
	States
	{
	Ready:
		HBFT A 1 A_WeaponReady;
		Loop;
	Deselect:
		HBFT A 1 A_Lower;
		Loop;
	Select:
		HBFT A 1 
		{
			A_Raise();
			A_DataSiphonEquip();
		}
		Loop;
	Fire:
		HBFT B 1 Bright A_StartSound("weapons/flame", CHAN_WEAPON, CHANF_LOOPING);
		Hold:
		HBFT C 1 Bright 
		{
			Actor proj = A_SpawnProjectile("FlameMissile");
			if (proj) proj.master = self; 
			
			int fidelity = CVar.GetCVar("vr_visual_fidelity", player).GetInt();
			int pCount = 1 + fidelity; // 1, 2, 3, 4
			for (int i = 0; i < pCount; i++)
			{
				A_SpawnItemEx("FlameParticle", 0, 0, 32, frandom(15, 25), frandom(-2, 2), frandom(-2, 2), 0, SXF_NOCHECKPOSITION);
			}
		}
		HBFT D 1 Bright A_TakeInventory("Fuel", 1);
		HBFT B 1 Bright A_ReFire("Hold");
		HBFT A 0 A_StopSound(CHAN_WEAPON);
		HBFT A 0 A_StartSound("weapons/flamestop", CHAN_WEAPON);
		Goto Ready;
	Spawn:
		HBFT A -1;
		Stop;
	}
}

class FlameMissile : Actor
{
	Default
	{
		Radius 12;
		Height 12;
		Speed 32;
		Damage 4;
		Projectile;
		+BRIGHT
		+FORCEXYBILLBOARD
		+THRUACTORS
		DamageType "Fire";
		Scale 0.6;
		Alpha 1.0;
		RenderStyle "Add";
	}
	States
	{
	Spawn:
		FLME A 0 NoDelay A_SpawnItemEx("FlameLight", 0, 0, 0, 0, 0, 0, 0, SXF_SETMASTER);
	SpawnLoop:
		FLME ABCDEFGHIJKLMN 1 Bright 
		{
			A_FadeOut(0.04);
			A_SetScale(scale.x * 1.1);
			if (i % 2 == 0) A_SpawnItemEx("FlameSmoke", frandom(-4, 4), frandom(-4, 4), frandom(-4, 4), 0, 0, frandom(1, 2), 0, SXF_NOCHECKPOSITION);
		}
		Stop;
	Death:
		FLME N 2 Bright 
		{
			A_Explode(24, 80);
			A_SpawnItemEx("FlameLightSmall", 0, 0, 0);
		}
		Stop;
	}
}

class FlameSmoke : Actor
{
	Default
	{
		+NOBLOCKMAP
		+NOGRAVITY
		+FORCEXYBILLBOARD
		RenderStyle "Translucent";
		Alpha 0.4;
		Scale 0.2;
	}
	States
	{
	Spawn:
		SMOK ABCDEFGHIJKLMNOP 2
		{
			A_FadeOut(0.02);
			A_SetScale(scale.x * 1.05);
			vel.z += 0.1;
		}
		Stop;
	}
}

class FlameLight : Actor
{
	Default { +NOBLOCKMAP +NOGRAVITY }
	States { Spawn: TNT1 A 1 Bright; Loop; }
}

class FlameLightSmall : FlameLight {}

class FlameParticle : Actor
{
	Default
	{
		+NOBLOCKMAP
		+NOGRAVITY
		+BRIGHT
		+FORCEXYBILLBOARD
		RenderStyle "Add";
		Alpha 0.6;
		Scale 0.4;
	}
	States
	{
	Spawn:
		FRFX ABCDEFGHIJKLMNOP 1 Bright 
		{
			A_FadeOut(0.04);
			A_SetScale(scale.x * 1.08);
		}
		Stop;
	}
}

class Fuel : Ammo
{
	Default
	{
		Inventory.Amount 50;
		Inventory.MaxAmount 300;
		Ammo.BackpackAmount 50;
		Ammo.BackpackMaxAmount 600;
		Inventory.Icon "FUELI0";
		Inventory.PickupMessage "Picked up some Fuel.";
		Tag "Fuel";
	}
	States
	{
	Spawn:
		FUEL A -1;
		Stop;
	}
}
