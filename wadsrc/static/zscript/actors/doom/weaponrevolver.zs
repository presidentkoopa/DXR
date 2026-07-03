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
		Obituary "%o was gunned down by %k's revolver.";
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
		REVL E 2
		{
			A_StartSound("weapons/revolver", CHAN_WEAPON);
			A_BallisticFire(0.5, 0.5, 1, 15, 2.5, gravity: 0.1, speed: 300);
		}
		REVL FGH 2;
		REVL I 3 A_ReFire;
		Goto Ready;
	// "Fan the hammer": 3 rapid, loose shots -- much faster cycle than normal Fire, wide
	// spread and heavier per-shot recoil since you're slapping the hammer, not aiming.
	// Toggle: vr_altfire_revolver -- if off, alt-fire is a no-op (no ammo consumed).
	AltFire:
		TNT1 A 0 A_JumpIf(!CVar.FindCVar("vr_altfire_revolver") || CVar.FindCVar("vr_altfire_revolver").GetBool(), "AltFireGo");
		Goto Ready;
	AltFireGo:
		REVL E 1
		{
			A_StartSound("weapons/revolver", CHAN_WEAPON);
			A_BallisticFire(3.0, 3.0, 1, 12, 3.0, gravity: 0.1, speed: 300);
		}
		REVL F 1
		{
			A_StartSound("weapons/revolver", CHAN_WEAPON);
			A_BallisticFire(3.0, 3.0, 1, 12, 3.0, gravity: 0.1, speed: 300);
		}
		REVL G 1
		{
			A_StartSound("weapons/revolver", CHAN_WEAPON);
			A_BallisticFire(3.0, 3.0, 1, 12, 3.0, gravity: 0.1, speed: 300);
		}
		REVL HI 2;
		REVL I 3 A_ReFire;
		Goto Ready;
	Flash:
		TNT1 A 3 Bright A_Light1;
		Goto LightDone;
	Spawn:
		RVP1 A 0 A_CheckSpawnModel();
		RVP1 A -1;
		Stop;
	}
}
