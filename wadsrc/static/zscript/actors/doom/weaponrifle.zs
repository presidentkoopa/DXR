// --------------------------------------------------------------------------
//
// Rifle
//
// --------------------------------------------------------------------------

class Rifle : DoomWeapon
{
	mixin XR_ManualReload;   // [XR] chamber gate + reload; native VR gesture FSM refills it (vr_new_weapon_handling)
	Default
	{
		Weapon.SelectionOrder 800;
		Weapon.SlotNumber 4;   // [XR] slot 4 (matches DoomPlayer's Player.WeaponSlot 4)
		Weapon.AmmoUse 1;
		Weapon.AmmoGive 20;
		Weapon.AmmoType "Clip";
		Inventory.PickupMessage "Picked up a Rifle!";
		Tag "Rifle";
		Obituary "%o was picked off by %k's rifle.";
		Keywords "mass:50", "grab", "class:rifle", "dmg:ballistic", "style:precision", "weight:medium", "range:long", "fire:semi", "role:marksman", "vr_dualwield";
	}
	States
	{
	Ready:
		RIFL A 0 { if (invoker.XRMagSize == 0) invoker.XR_InitChamber(20); }   // [XR] mag size 20
		RIFL A 1 A_WeaponReady(WRF_ALLOWRELOAD);                              // on-demand reload button (classic fallback)
		Loop;
	// [XR] Deliberately NO A_XR_CheckChamber auto-route here: an empty chamber dry-clicks on fire, then EITHER
	// the native VR gesture FSM (VR_UpdateWeaponReload) OR the reload button (-> Reload state) refills it, no fight.
	Deselect:
		RIFL A 1 A_Lower;
		Loop;
	Select:
		RIFL A 1
		{
			A_Raise();
			A_DataSiphonEquip();
			AssignWeaponHandling("boxmag");   // [XR] DATA-ONLY: native box-mag FSM; hs_* auto-read from the IQM
		}
		Loop;
	Fire:
		TNT1 A 0 A_JumpIf(!A_XR_TryFire(), "Ready");   // [XR] chamber gate: consumes 1 loaded round, dry-clicks when empty
		RIFL B 2
		{
			A_StartSound("weapons/rifle", CHAN_WEAPON);
			A_BallisticFire(0.1, 0.1, 1, 10, 1.2, gravity: 0.05, speed: 500);
		}
		RIFL CDE 1;
		RIFL A 2 A_ReFire;
		Goto Ready;
	// 3-round burst, tight grouping: same low spread every shot (no widening/degrading
	// across the burst, unlike the old escalating-spread version) so all 3 rounds land
	// close together -- the real "burst mode" feel, not a spray.
	// Toggle: vr_altfire_rifle -- if off, alt-fire is a no-op (no ammo consumed).
	AltFire:
		TNT1 A 0 A_JumpIf(!CVar.FindCVar("vr_altfire_rifle") || CVar.FindCVar("vr_altfire_rifle").GetBool(), "AltFireGo");
		Goto Ready;
	AltFireGo:
		RIFL B 2
		{
			// [XR] each burst round self-gates on the chamber (stops mid-burst if it empties)
			if (A_XR_TryFire()) { A_StartSound("weapons/rifle", CHAN_WEAPON); A_BallisticFire(0.1, 0.1, 1, 10, 1.2, gravity: 0.05, speed: 500); }
		}
		RIFL C 1;
		RIFL B 2
		{
			if (A_XR_TryFire()) { A_StartSound("weapons/rifle", CHAN_WEAPON); A_BallisticFire(0.1, 0.1, 1, 10, 1.2, gravity: 0.05, speed: 500); }
		}
		RIFL C 1;
		RIFL B 2
		{
			if (A_XR_TryFire()) { A_StartSound("weapons/rifle", CHAN_WEAPON); A_BallisticFire(0.1, 0.1, 1, 10, 1.2, gravity: 0.05, speed: 500); }
		}
		RIFL CDE 1;
		RIFL A 5;
		Goto Ready;
	// [XR] Manual reload button fallback (flatscreen / vr_new_weapon_handling off). No baked reload anim on
	// RIFL; a plain ~1.3s beat that re-arms the chamber. The native VR gesture FSM refills XRChamber instead
	// when vr_new_weapon_handling is on -- both write XRChamber, so either path works.
	Reload:
		RIFL A 0 A_XR_EjectToPouch();   // VR: eject mag -> Ready (chest pouch reloads); flatscreen: falls through
		RIFL A 30;
		RIFL A 15 A_XR_RefillChamber();   // round chambers -> re-arm from the reserve total
		Goto Ready;
	Flash:
		TNT1 A 3 Bright A_Light1;
		Goto LightDone;
	Spawn:
		RFP1 A 0 A_CheckSpawnModel();
		RFP1 A -1;
		Stop;
	}
}
