// --------------------------------------------------------------------------
//
// Revolver
//
// --------------------------------------------------------------------------

class Revolver : DoomWeapon
{
	Default
	{
		Weapon.SelectionOrder 900;
		Weapon.AmmoUse 1;
		Weapon.AmmoGive 6;
		Weapon.AmmoType "Clip";
		Inventory.PickupMessage "Picked up a Revolver!";
		Tag "Revolver";
		Keywords "mass:30", "grab", "class:revolver", "dmg:ballistic", "style:power", "weight:light", "range:medium", "fire:single", "role:sidearm";
	}
	States
	{
	Ready:
		REVL A 1 A_WeaponReady;
		Loop;
	Deselect:
		REVL A 1 A_Lower;
		Loop;
	Select:
		REVL A 1 
		{
			A_Raise();
			A_DataSiphonEquip();
		}
		Loop;
	Fire:
		REVL E 2 Bright 
		{
			A_StartSound("weapons/revolver", CHAN_WEAPON);
			A_BallisticFire(0.5, 0.5, 1, 15, 2.5, gravity: 0.1, speed: 300);
		}
		REVL FGH 2;
		REVL I 3 A_ReFire;
		Goto Ready;
	Spawn:
		RVP1 A 0 A_CheckSpawnModel();
		RVP1 A -1;
		Stop;
	}
}
