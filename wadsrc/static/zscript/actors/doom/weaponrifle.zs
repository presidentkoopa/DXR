// --------------------------------------------------------------------------
//
// Rifle
//
// --------------------------------------------------------------------------

class Rifle : DoomWeapon
{
	Default
	{
		Weapon.SelectionOrder 800;
		Weapon.AmmoUse 1;
		Weapon.AmmoGive 20;
		Weapon.AmmoType "Clip";
		Inventory.PickupMessage "Picked up a Rifle!";
		Tag "Rifle";
		Obituary "%o was picked off by %k's rifle.";
		Keywords "mass:50", "grab", "class:rifle", "dmg:ballistic", "style:precision", "weight:medium", "range:long", "fire:semi", "role:marksman";
	}
	States
	{
	Ready:
		RIFL A 1 A_WeaponReady;
		Loop;
	Deselect:
		RIFL A 1 A_Lower;
		Loop;
	Select:
		RIFL A 1
		{
			A_Raise();
			A_DataSiphonEquip();
		}
		Loop;
	Fire:
		RIFL B 2
		{
			A_StartSound("weapons/rifle", CHAN_WEAPON);
			A_BallisticFire(0.1, 0.1, 1, 10, 1.2, gravity: 0.05, speed: 500);
		}
		RIFL CDE 1;
		RIFL A 2 A_ReFire;
		Goto Ready;
	// 3-round burst, tight grouping: same low spread every shot (no widening/degrading
	// across the burst, unlike the old escalating-spread version) so all 3 rounds land
	// close together -- the real "burst mode" feel, not a spray.
	// Toggle: vr_altfire_rifle -- if off, alt-fire is a no-op (no ammo consumed).
	AltFire:
		TNT1 A 0 A_JumpIf(!CVar.FindCVar("vr_altfire_rifle") || CVar.FindCVar("vr_altfire_rifle").GetBool(), "AltFireGo");
		Goto Ready;
	AltFireGo:
		RIFL B 2
		{
			A_StartSound("weapons/rifle", CHAN_WEAPON);
			A_BallisticFire(0.1, 0.1, 1, 10, 1.2, gravity: 0.05, speed: 500);
		}
		RIFL C 1;
		RIFL B 2
		{
			A_StartSound("weapons/rifle", CHAN_WEAPON);
			A_BallisticFire(0.1, 0.1, 1, 10, 1.2, gravity: 0.05, speed: 500);
		}
		RIFL C 1;
		RIFL B 2
		{
			A_StartSound("weapons/rifle", CHAN_WEAPON);
			A_BallisticFire(0.1, 0.1, 1, 10, 1.2, gravity: 0.05, speed: 500);
		}
		RIFL CDE 1;
		RIFL A 5;
		Goto Ready;
	Flash:
		TNT1 A 3 Bright A_Light1;
		Goto LightDone;
	Spawn:
		RFP1 A 0 A_CheckSpawnModel();
		RFP1 A -1;
		Stop;
	}
}
