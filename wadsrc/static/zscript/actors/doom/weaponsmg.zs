// --------------------------------------------------------------------------
//
// SMG
//
// --------------------------------------------------------------------------

class SMG : DoomWeapon
{
	Default
	{
		Weapon.SelectionOrder 750;
		Weapon.AmmoUse 1;
		Weapon.AmmoGive 30;
		Weapon.AmmoType "Clip";
		Inventory.PickupMessage "Picked up an SMG!";
		Tag "SMG";
		Keywords "mass:40", "grab", "class:smg", "dmg:ballistic", "style:rapid", "weight:medium", "range:short", "fire:auto", "role:skirmisher";
	}
	States
	{
	Ready:
		SMGS A 1 A_WeaponReady;
		Loop;
	Deselect:
		SMGS A 1 A_Lower;
		Loop;
	Select:
		SMGS A 1 
		{
			A_Raise();
			A_DataSiphonEquip();
		}
		Loop;
	Fire:
		SMGG A 2 Bright 
		{
			A_FireBullets(2.5, 2.5, -1, 5, "BulletPuff");
			A_StartSound("weapons/smg", CHAN_WEAPON);
			A_VRRecoil(0.15);
		}
		SMGG B 2 Bright;
		SMGG B 0 A_ReFire;
		Goto Ready;
	Spawn:
		SMP1 A 0 A_CheckSpawnModel();
		SMP1 A -1;
		Stop;
	}
}
