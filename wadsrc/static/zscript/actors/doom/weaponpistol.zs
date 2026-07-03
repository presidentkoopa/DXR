// --------------------------------------------------------------------------
//
// Pistol 
//
// --------------------------------------------------------------------------

class Pistol : DoomWeapon
{
	Default
	{
		Weapon.SelectionOrder 1900;
		Weapon.AmmoUse 1;
		Weapon.AmmoGive 20;
		Weapon.AmmoType "Clip";
		Obituary "$OB_MPPISTOL";
		+WEAPON.WIMPY_WEAPON
		Inventory.Pickupmessage "$PICKUP_PISTOL_DROPPED";
		Tag "$TAG_PISTOL";
		Keywords "mass:10", "grab", "class:pistol", "dmg:ballistic", "style:precision", "weight:light", "range:medium", "fire:semi", "handling:snappy", "role:sidearm";
	}
	States
	{
	Ready:
		PISG A 1 A_WeaponReady;
		Loop;
	Deselect:
		PISG A 1 A_Lower;
		Loop;
	Select:
		PISG A 1 A_Raise;
		Loop;
	Fire:
		PISG A 4;
		PISG B 6
		{
			A_FirePistol();
			A_Recoil(0.8);
		}
		PISG C 4;
		PISG B 5 A_ReFire;
		Goto Ready;
	// 3-round burst, tight grouping: same tight spread as the normal single shot, fired
	// three times back to back with steady (not escalating) recoil compensation.
	// Toggle: vr_altfire_pistol -- if off, alt-fire is a no-op (no ammo consumed).
	AltFire:
		TNT1 A 0 A_JumpIf(!CVar.FindCVar("vr_altfire_pistol") || CVar.FindCVar("vr_altfire_pistol").GetBool(), "AltFireGo");
		Goto Ready;
	AltFireGo:
		PISG A 2;
		PISG B 3
		{
			A_FirePistol();
			A_Recoil(0.8);
		}
		PISG B 3
		{
			A_FirePistol();
			A_Recoil(0.8);
		}
		PISG B 3
		{
			A_FirePistol();
			A_Recoil(0.8);
		}
		PISG C 4;
		PISG B 5 A_ReFire;
		Goto Ready;
	Flash:
		PISF A 7 Bright A_Light1;
		Goto LightDone;
		PISF A 7 Bright A_Light1;
		Goto LightDone;
 	Spawn:
		PIST A 0 A_CheckSpawnModel();
		PIST A -1;
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
	//===========================================================================
	// This is also used by the shotgun and chaingun
	//===========================================================================
	
	protected action void GunShot(bool accurate, Class<Actor> pufftype, double pitch)
	{
		int damage = 5 * random[GunShot](1, 3);
		double ang = angle;

		if (!accurate)
		{
			ang += Random2[GunShot]() * (5.625 / 256);

			if (GetCVar ("vertspread") && !sv_novertspread)
			{
				pitch += Random2[GunShot]() * (3.549 / 256);
			}
		}
		int laflags = invoker == player.OffhandWeapon ? LAF_ISOFFHAND : 0;
		LineAttack(ang, PLAYERMISSILERANGE, pitch, damage, 'Hitscan', pufftype, laflags);
	}
	
	//===========================================================================
	action void A_FirePistol()
	{
		A_StartSound("weapons/pistol", CHAN_WEAPON);
		A_BallisticFire(0.5, 0.5, 1, 5, 0.8);
	}
}