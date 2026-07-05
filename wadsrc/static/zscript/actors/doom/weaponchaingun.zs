// --------------------------------------------------------------------------
//
// Chaingun
//
// --------------------------------------------------------------------------

class Chaingun : DoomWeapon
{
	mixin XR_ManualReload;   // [XR] chamber gate + box-mag physical reload (native VR gesture FSM refills it)

	Default
	{
		Weapon.SelectionOrder 700;
		Weapon.SlotNumber 4;   // [XR] slot 4 (matches DoomPlayer's Player.WeaponSlot 4)
		Weapon.AmmoUse 1;
		Weapon.AmmoGive 20;
		Weapon.AmmoType "Clip";
		Inventory.PickupMessage "$GOTCHAINGUN";
		Obituary "$OB_MPCHAINGUN";
		Tag "$TAG_CHAINGUN";
		Keywords "mass:50", "grab", "class:chaingun", "grip:heavy", "dmg:ballistic", "style:suppression", "weight:medium", "range:medium", "fire:auto", "handling:steady", "role:suppressor", "vr_dualwield";
	}
	States
	{
	Ready:
		CHGG A 0 { if (invoker.XRMagSize == 0) { invoker.XR_InitChamber(50); invoker.XRMagClass = "XRMag_Chaingun"; } }   // [XR] belt/mag size 50, chaingun mag
		CHGG A 1 A_WeaponReady(WRF_ALLOWRELOAD);
		Loop;
	Deselect:
		CHGG A 1 A_Lower;
		Loop;
	Select:
		CHGG A 1
		{
			A_Raise();
			AssignWeaponHandling("boxmag");   // [XR] native box-mag FSM; hs_* geometric-default (no IQM needed)
		}
		Loop;
	Fire:
		TNT1 A 0 A_JumpIf(!A_XR_TryFire(), "Ready");   // [XR] chamber gate (shot 1); dry-clicks when empty
		CHGG A 4 A_FireCGun;
		TNT1 A 0 A_JumpIf(!A_XR_TryFire(), "Ready");   // [XR] chamber gate (shot 2)
		CHGG B 4 A_FireCGun;
		CHGG B 0 A_ReFire;
		Goto Ready;
	// [XR] Manual reload beat (flatscreen / gesture-FSM fallback). No baked reload anim on CHGG.
	Reload:
		CHGG A 0 A_XR_EjectToPouch();   // VR: eject mag -> Ready (chest pouch reloads); flatscreen: falls through
		CHGG A 30;
		CHGG A 12 A_XR_RefillChamber();   // re-arm chamber from the Clip reserve
		Goto Ready;
	Flash:
		// VR: muzzle-flash sprite suppressed, muzzle light kept.
		TNT1 A 5 Bright A_Light1;
		Goto LightDone;
		TNT1 A 5 Bright A_Light2;
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
