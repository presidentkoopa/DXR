// --------------------------------------------------------------------------
//
// SMG
//
// --------------------------------------------------------------------------

class SMG : DoomWeapon
{
	mixin XR_ManualReload;   // [XR] chamber gate + box-mag physical reload (native VR gesture FSM refills it)

	Default
	{
		Weapon.SelectionOrder 750;
		Weapon.SlotNumber 2;   // [XR] slot 2 (matches DoomPlayer's Player.WeaponSlot 2)
		Weapon.AmmoUse 1;
		Weapon.AmmoGive 30;
		Weapon.AmmoType "Clip";
		Inventory.PickupMessage "Picked up an SMG!";
		Tag "SMG";
		Obituary "%o was cut down by %k's SMG.";
		Keywords "mass:40", "grab", "class:smg", "dmg:ballistic", "style:rapid", "weight:medium", "range:short", "fire:auto", "role:skirmisher", "vr_dualwield";
	}
	States
	{
	Ready:
		SMGS A 0 { if (invoker.XRMagSize == 0) invoker.XR_InitChamber(30); }   // [XR] mag size 30
		SMGS A 1 A_WeaponReady(WRF_ALLOWRELOAD);
		Loop;
	Deselect:
		SMGS A 1 A_Lower;
		Loop;
	Select:
		SMGS A 1
		{
			A_Raise();
			A_DataSiphonEquip();
			AssignWeaponHandling("boxmag");   // [XR] native box-mag FSM; hs_* geometric-default (no IQM needed)
		}
		Loop;
	Fire:
		TNT1 A 0 A_JumpIf(!A_XR_TryFire(), "Ready");   // [XR] chamber gate; dry-clicks when empty
		SMGG A 2
		{
			A_FireBullets(2.5, 2.5, -1, 5, "BulletPuff");
			A_StartSound("weapons/smgfire", CHAN_WEAPON);
			A_Recoil(0.15);
		}
		SMGG B 2;
		SMGG B 0 A_ReFire;
		Goto Ready;
	// [XR] Manual reload beat (flatscreen / gesture-FSM fallback). No baked reload anim on SMGG.
	Reload:
		SMGS A 0 A_XR_EjectToPouch();   // VR: eject mag -> Ready (chest pouch reloads); flatscreen: falls through
		SMGS A 25;
		SMGS A 10 A_XR_RefillChamber();   // re-arm chamber from the Clip reserve
		Goto Ready;
	Flash:
		TNT1 A 2 Bright A_Light1;
		Goto LightDone;
	Spawn:
		SMP1 A 0 A_CheckSpawnModel();
		SMP1 A -1;
		Stop;
	}
}
