// --------------------------------------------------------------------------
//
// Flamethrower
//
// --------------------------------------------------------------------------

class Flamethrower : DoomWeapon
{
	mixin XR_ManualReload;   // [XR] chamber gate + reload; native VR gesture FSM refills it (vr_new_weapon_handling)
	Default
	{
		Weapon.SelectionOrder 1800;
		Weapon.SlotNumber 1;   // [XR] slot 1 (matches DoomPlayer's Player.WeaponSlot 1)
		Weapon.AmmoUse 1;
		Weapon.AmmoGive 50;
		Weapon.AmmoType "Fuel";
		Inventory.PickupMessage "Picked up a Flamethrower!";
		Tag "Flamethrower";
		Keywords "mass:60", "grab", "class:flamethrower", "dmg:fire", "style:stream", "weight:medium", "range:short", "fire:continuous", "role:crowd_control", "vr_dualwield";
	}
	States
	{
	Ready:
		HBFT A 0 { if (invoker.XRMagSize == 0) invoker.XR_InitChamber(40); }   // [XR] mag size 40
		HBFT A 1 A_WeaponReady(WRF_ALLOWRELOAD);
		Loop;
	Deselect:
		HBFT A 1 A_Lower;
		Loop;
	Select:
		HBFT A 1
		{
			A_Raise();
			A_DataSiphonEquip();
			AssignWeaponHandling("boxmag");   // [XR] DATA-ONLY: native box-mag FSM; hs_* auto-read from the IQM
		}
		Loop;
	Fire:
		TNT1 A 0 A_JumpIf(!A_XR_TryFire(), "Ready");   // [XR] chamber gate at entry only (continuous stream); dry-clicks when empty
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
			// Light, sustained kick from the fuel pressure -- was previously the only
			// weapon with zero recoil at all.
			A_Recoil(0.1);
		}
		HBFT D 1 Bright A_TakeInventory("Fuel", 1);
		HBFT B 1 Bright A_ReFire("Hold");
		HBFT A 0 A_StopSound(CHAN_WEAPON);
		HBFT A 0 A_StartSound("weapons/flamestop", CHAN_WEAPON);
		Goto Ready;
	Reload:
		HBFT A 0 A_XR_EjectToPouch();   // VR: eject mag -> Ready (chest pouch reloads); flatscreen: falls through
		HBFT A 30;
		HBFT A 15 A_XR_RefillChamber();   // re-arm chamber from the reserve
		Goto Ready;
	Spawn:
		HBFT A 0 A_CheckSpawnModel();
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
		Obituary "%o was incinerated by %k's flamethrower.";
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
			if (level.time % 2 == 0) A_SpawnItemEx("FlameSmoke", frandom(-4, 4), frandom(-4, 4), frandom(-4, 4), 0, 0, frandom(1, 2), 0, SXF_NOCHECKPOSITION);
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
