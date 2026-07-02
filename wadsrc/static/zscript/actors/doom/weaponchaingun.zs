// --------------------------------------------------------------------------
//
// Chaingun
//
// --------------------------------------------------------------------------

class Chaingun : DoomWeapon
{
	Default
	{
		Weapon.SelectionOrder 700;
		Weapon.AmmoUse 1;
		Weapon.AmmoGive 20;
		Weapon.AmmoType "Clip";
		Inventory.PickupMessage "$GOTCHAINGUN";
		Obituary "$OB_MPCHAINGUN";
		Tag "$TAG_CHAINGUN";
		Keywords "mass:50", "grab", "class:chaingun", "dmg:ballistic", "style:suppression", "weight:medium", "range:medium", "fire:auto", "handling:steady", "role:suppressor";
	}
	States
	{
	Ready:
		CHGG A 1 A_WeaponReady;
		Loop;
	Deselect:
		CHGG A 1 A_Lower;
		Loop;
	Select:
		CHGG A 1 A_Raise;
		Loop;
	Fire:
		CHGG AB 4 A_FireCGun;
		CHGG B 0 A_ReFire;
		Goto Ready;
	Flash:
		CHGF A 5 Bright A_Light1;
		Goto LightDone;
		CHGF B 5 Bright A_Light2;
		Goto LightDone;
	Spawn:
		MGUN A 0 A_CheckSpawnModel();
		MGUN A -1;
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
	action void A_FireCGun()
	{
		if (player == null) return;
		
		int hand = 0;
		Weapon weap = invoker == player.OffhandWeapon ? player.OffhandWeapon : player.ReadyWeapon;
		if (weap != null && invoker == weap && stateinfo != null && stateinfo.mStateType == STATE_Psprite)
		{
			hand = weap.bOffhandWeapon ? 1 : 0;
			// A_BallisticFire handles ammo and recoil
			A_BallisticFire(5.6, 0, 1, 5, 0.2);

			State flash = weap.FindState('Flash');
			if (flash != null)
			{
				let psp = player.GetPSprite(hand ? PSP_OFFHANDWEAPON : PSP_WEAPON);
				if (psp) 
				{
					State atk = weap.FindState('Fire');
					int theflash = (atk == psp.CurState) ? 0 : 1;
					player.SetSafeFlash(weap, flash, theflash);
				}
			}
		}
		player.mo.PlayAttacking2 ();
		A_StartSound ("weapons/chngun", CHAN_WEAPON);
	}
}
