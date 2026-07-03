// --------------------------------------------------------------------------
//
// Super Shotgun
//
// --------------------------------------------------------------------------

class SuperShotgun : DoomWeapon
{
	Default
	{
		Weapon.SelectionOrder 400;
		Weapon.AmmoUse 2;
		Weapon.AmmoGive 8;
		Weapon.AmmoType "Shell";
		Inventory.PickupMessage "$GOTSUPER";
		Obituary "$OB_MPSSHOTGUN";
		Tag "$TAG_SUPERSHOTGUN";
		Keywords "mass:60", "grab", "class:ssg", "dmg:ballistic", "style:spread", "weight:heavy", "range:point_blank", "fire:break_action", "handling:heavy", "role:burst";
	}
	States
	{
	Ready:
		SHT2 A 1 A_WeaponReady;
		Loop;
	Deselect:
		SHT2 A 1 A_Lower;
		Loop;
	Select:
		SHT2 A 1 A_Raise;
		Loop;
	Fire:
		SHT2 A 3;
		SHT2 A 7 
		{
			A_FireShotgun2();
			A_Recoil(4.0);
		}
		SHT2 B 7;
		SHT2 C 7 A_CheckReload;
		SHT2 D 7 A_OpenShotgun2;
		SHT2 E 7;
		SHT2 F 7 A_LoadShotgun2;
		SHT2 G 6;
		SHT2 H 6 A_CloseShotgun2;
		SHT2 A 5 A_ReFire;
		Goto Ready;
	// Single-barrel, fired twice: one barrel at a time instead of both at once --
	// two separate individual shots (2 shells total) rather than one combined blast.
	// Toggle: vr_altfire_ssg -- if off, alt-fire is a no-op (no ammo consumed).
	AltFire:
		TNT1 A 0 A_JumpIf(!CVar.FindCVar("vr_altfire_ssg") || CVar.FindCVar("vr_altfire_ssg").GetBool(), "AltFireGo");
		Goto Ready;
	AltFireGo:
		SHT2 A 3;
		SHT2 A 7 A_FireShotgunIndividual;
		SHT2 A 4;
		SHT2 A 7 A_FireShotgunIndividual;
		SHT2 B 7;
		SHT2 C 7 A_CheckReload;
		SHT2 D 7 A_OpenShotgun2;
		SHT2 E 7;
		SHT2 F 7 A_LoadShotgun2;
		SHT2 G 6;
		SHT2 H 6 A_CloseShotgun2;
		SHT2 A 5 A_ReFire;
		Goto Ready;
	// unused states
		SHT2 B 7;
		SHT2 A 3;
		Goto Deselect;
	Flash:
		SHT2 I 4 Bright A_Light1;
		SHT2 J 3 Bright A_Light2;
		Goto LightDone;
	Spawn:
		SGN2 A 0 A_CheckSpawnModel();
		SGN2 A -1;
		Stop;
	}
}



//===========================================================================
//
// Code (must be attached to StateProvider)
//
//===========================================================================

extend class StateProvider
{
	action void A_FireShotgun2()
	{
		A_StartSound("weapons/sshotf", CHAN_WEAPON);
		A_BallisticFire(11.2, 7.1, 20, 5, 4.0);
	}


	action void A_OpenShotgun2() 
	{ 
		A_StartSound("weapons/sshoto", CHAN_WEAPON); 
	}
	
	action void A_LoadShotgun2() 
	{ 
		A_StartSound("weapons/sshotl", CHAN_WEAPON); 
	}
	
	action void A_CloseShotgun2() 
	{ 
		A_StartSound("weapons/sshotc", CHAN_WEAPON);
		A_Refire();
	}
}
