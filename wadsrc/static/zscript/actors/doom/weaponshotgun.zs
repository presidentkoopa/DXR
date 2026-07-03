// --------------------------------------------------------------------------
//
// Shotgun
//
// --------------------------------------------------------------------------

class Shotgun : DoomWeapon
{
	Default
	{
		Weapon.SelectionOrder 1300;
		Weapon.AmmoUse 1;
		Weapon.AmmoGive 8;
		Weapon.AmmoType "Shell";
		Inventory.PickupMessage "$GOTSHOTGUN";
		Obituary "$OB_MPSHOTGUN";
		Tag "$TAG_SHOTGUN";
		Keywords "mass:40", "grab", "class:shotgun", "dmg:ballistic", "style:spread", "weight:medium", "range:short", "fire:pump", "handling:solid", "role:workhorse";
	}
	States
	{
	Ready:
		SHTG A 1 A_WeaponReady;
		Loop;
	Deselect:
		SHTG A 1 A_Lower;
		Loop;
	Select:
		SHTG A 1 A_Raise;
		Loop;
	Fire:
		SHTG A 3;
		SHTG A 7 
		{
			A_FireShotgun();
			A_Recoil(3.0);
		}
		SHTG BC 5;
		SHTG D 4;
		SHTG CB 5;
		SHTG A 3;
		SHTG A 7 A_ReFire;
		Goto Ready;
	Flash:
		SHTF A 4 Bright A_Light1;
		SHTF B 3 Bright A_Light2;
		Goto LightDone;
	Spawn:
		SHOT A 0 
		{
			if (CVar.GetCVar("vr_spawn_models", players[consoleplayer]).GetBool())
			{
				// In a real implementation, we would spawn a model actor here
				// For now we just acknowledge the toggle
			}
		}
		SHOT A -1;
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

	action void A_FireShotgun()
	{
		A_StartSound("weapons/shotgf", CHAN_WEAPON);
		A_BallisticFire(5.6, 5.6, 7, 5, 3.0);
	}

}	

