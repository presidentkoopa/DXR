// --------------------------------------------------------------------------
//
// Pistol 
//
// --------------------------------------------------------------------------

class Pistol : DoomWeapon
{
	mixin XR_ManualReload;

	Default
	{
		Weapon.SelectionOrder 1900;
		Weapon.SlotNumber 2;   // [XR] slot 2 (matches DoomPlayer's Player.WeaponSlot 2)
		Weapon.AmmoUse 1;
		Weapon.AmmoGive 20;
		Weapon.AmmoType "Clip";
		Obituary "$OB_MPPISTOL";
		+WEAPON.WIMPY_WEAPON
		Inventory.Pickupmessage "$PICKUP_PISTOL_DROPPED";
		Tag "$TAG_PISTOL";
		Keywords "mass:10", "grab", "class:pistol", "dmg:ballistic", "style:precision", "weight:light", "range:medium", "fire:semi", "handling:snappy", "role:sidearm", "vr_dualwield";
	}
	States
	{
	Ready:
		PISG A 0 { if (invoker.XRMagSize == 0) invoker.XR_InitChamber(12); }   // mag size 12
		PISG A 1 A_WeaponReady(WRF_ALLOWRELOAD);                              // reload bind -> eject -> chest pouch
		Loop;
	// [XR] Removed A_XR_CheckChamber auto-route: the Pistol now uses the chest-pouch reload like the other
	// mag guns (dry-click on empty fire, then reload-bind ejects the mag and you grab a fresh one). Removing
	// it also prevents an eject<->Reload infinite loop with A_XR_EjectToPouch below.
	Deselect:
		PISG A 1 A_Lower;
		Loop;
	Select:
		PISG A 1
		{
			A_Raise();
			AssignWeaponHandling("boxmag");   // [XR] native box-mag FSM; chest-pouch reload
		}
		Loop;
	Fire:
		TNT1 A 0 A_JumpIf(!A_XR_TryFire(), "Ready");   // chamber gate (consumes 1 loaded round; dry-clicks when empty)
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
			// each burst round self-gates on the chamber (stops mid-burst if it empties)
			if (A_XR_TryFire()) { A_FirePistol(); A_Recoil(0.8); }
		}
		PISG B 3
		{
			// each burst round self-gates on the chamber (stops mid-burst if it empties)
			if (A_XR_TryFire()) { A_FirePistol(); A_Recoil(0.8); }
		}
		PISG B 3
		{
			// each burst round self-gates on the chamber (stops mid-burst if it empties)
			if (A_XR_TryFire()) { A_FirePistol(); A_Recoil(0.8); }
		}
		PISG C 4;
		PISG B 5 A_ReFire;
		Goto Ready;
	// Manual reload -- drives Pistol.md3's OWN baked reload animation (frames 8-25,
	// PISR A-R, mapped in modeldef.txt). 18 frames x 2 tics = ~1s snappy sidearm reload;
	// chamber is topped from the reserve total on the final chambering frame.
	Reload:
		PISR A 0 A_XR_EjectToPouch();   // VR: eject mag -> Ready (chest pouch reloads); flatscreen: plays the PISR anim below
		PISR A 2;
		PISR B 2;
		PISR C 2;
		PISR D 2;
		PISR E 2;
		PISR F 2;
		PISR G 2;
		PISR H 2;
		PISR I 2;
		PISR J 2;
		PISR K 2;
		PISR L 2;
		PISR M 2;
		PISR N 2;
		PISR O 2;
		PISR P 2;
		PISR Q 2;
		PISR R 2 A_XR_RefillChamber();   // round chambers -> re-arm from reserve total
		Goto Ready;
	Flash:
		// VR: muzzle-flash sprite suppressed (billboarded 2D flash reads badly in stereo).
		// Keep only the dynamic muzzle light. TNT1 = invisible.
		TNT1 A 7 Bright A_Light1;
		Goto LightDone;
		TNT1 A 7 Bright A_Light1;
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