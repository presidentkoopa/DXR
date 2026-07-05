// --------------------------------------------------------------------------
//
// Plasma rifle
//
// --------------------------------------------------------------------------

class PlasmaRifle : DoomWeapon
{
	mixin XR_ManualReload;   // [XR] chamber gate + box-mag physical reload (native VR gesture FSM refills it)

	Default
	{
		Weapon.SelectionOrder 100;
		Weapon.SlotNumber 6;   // [XR] slot 6 (matches DoomPlayer's Player.WeaponSlot 6)
		Weapon.AmmoUse 1;
		Weapon.AmmoGive 40;
		Weapon.AmmoType "Cell";
		Inventory.PickupMessage "$GOTPLASMA";
		Tag "$TAG_PLASMARIFLE";
		Keywords "mass:70", "grab", "class:plasma", "dmg:energy", "dmg:thermal", "style:suppression", "weight:medium", "range:medium", "fire:auto", "handling:steady", "role:suppressor", "vr_dualwield";
	}
	States
	{
	Ready:
		PLSG A 0 { if (invoker.XRMagSize == 0) { invoker.XR_InitChamber(40); invoker.XRMagClass = "XRMag_Plasma"; } }   // [XR] cell-mag size 40, plasma mag
		PLSG A 1 A_WeaponReady(WRF_ALLOWRELOAD);
		Loop;
	Deselect:
		PLSG A 1 A_Lower;
		Loop;
	Select:
		PLSG A 1
		{
			A_Raise();
			// [XR] heat-vent (RS_CANISTER) by default per RELOAD_JUICE_SPEC (energy weapon); box-mag fallback when off.
			CVar hv = CVar.FindCVar("vr_reload_heatvent");
			AssignWeaponHandling((!hv || hv.GetBool()) ? "heatvent" : "boxmag");
		}
		Loop;
	Fire:
		TNT1 A 0 A_JumpIf(!A_XR_TryFire(), "Ready");   // [XR] chamber gate; dry-clicks when empty
		PLSG A 3
		{
			A_FirePlasma();
			A_Recoil(0.15);
			// [XR] heat-vent feed: native FSM (RS_CANISTER) vents on overheat; no-op for other styles.
			CVar hvf = CVar.FindCVar("vr_reload_heatvent");
			if (!hvf || hvf.GetBool()) self.VR_AddReloadHeat(CVar.FindCVar("vr_reload_heat_per_shot") ? CVar.FindCVar("vr_reload_heat_per_shot").GetInt() : 10);
		}
		PLSG B 20 A_ReFire;
		Goto Ready;
	// [XR] Manual reload beat (flatscreen / gesture-FSM fallback). No baked reload anim mapped on PLSG.
	Reload:
		PLSG A 0 A_XR_EjectToPouch();   // VR: eject mag -> Ready (chest pouch reloads); flatscreen: falls through
		PLSG A 30;
		PLSG A 12 A_XR_RefillChamber();   // re-arm chamber from the Cell reserve
		Goto Ready;
	// Toggle: vr_altfire_plasma -- if off, alt-fire is a no-op (no ammo consumed).
	AltFire:
		TNT1 A 0 A_JumpIf(!CVar.FindCVar("vr_altfire_plasma") || CVar.FindCVar("vr_altfire_plasma").GetBool(), "AltFireGo");
		Goto Ready;
	AltFireGo:
		PLSG A 1 A_FirePlasmaBeam;
		PLSG B 0 A_ReFire;
		Goto Ready;
	Flash:
		// VR: muzzle-flash sprite suppressed, muzzle light kept.
		TNT1 A 4 Bright A_Light1;
		Goto LightDone;
		TNT1 A 4 Bright A_Light1;
		Goto LightDone;
	Spawn:
		PLAS A 0 A_CheckSpawnModel();
		PLAS A -1;
		Stop;
	}
}

class PlasmaBall : Actor
{
	Default
	{
		Radius 13;
		Height 8;
		Speed 25;
		Damage 5;
		Projectile;
		+RANDOMIZE
		+ZDOOMTRANS
		RenderStyle "Add";
		Alpha 0.75;
		SeeSound "weapons/plasmaf";
		DeathSound "weapons/plasmax";
		Obituary "$OB_MPPLASMARIFLE";
		Keywords "ballistics:plasmaball";
	}
	States
	{
	Spawn:
		PLSS AB 6 Bright;
		Loop;
	Death:
		PLSE ABCDE 4 Bright;
		Stop;
	}
}

// --------------------------------------------------------------------------
//
// BFG 2704
//
// --------------------------------------------------------------------------

class PlasmaBall1 : PlasmaBall
{
	Default
	{
		Damage 4;
		BounceType "Classic";
		BounceFactor 1.0;
		Obituary "$OB_MPBFG_MBF";
	}
	States
	{
	Spawn:
		PLS1 AB 6 Bright;
		Loop;
	Death:
		PLS1 CDEFG 4 Bright;
		Stop;
	}
}
	
class PlasmaBall2 : PlasmaBall1
{
	States
	{
	Spawn:
		PLS2 AB 6 Bright;
		Loop;
	Death:
		PLS2 CDE 4 Bright;
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
	//
	// A_FirePlasma
	//
	//===========================================================================

	action void A_FirePlasma()
	{
		int hand = 0;
		if (player == null)
		{
			return;
		}
		Weapon weap = invoker == player.OffhandWeapon ? player.OffhandWeapon : player.ReadyWeapon;
		if (weap != null && invoker == weap && stateinfo != null && stateinfo.mStateType == STATE_Psprite)
		{
			hand = weap.bOffhandWeapon ? 1 : 0;
			if (!weap.DepleteAmmo (weap.bAltFire, true))
				return;
			
			State flash = weap.FindState('Flash');
			if (flash != null)
			{
				player.SetSafeFlash(weap, flash, random[FirePlasma](0, 1));
			}
			
		}
		
		SpawnPlayerMissile ("PlasmaBall", aimflags:hand ? ALF_ISOFFHAND : 0);
	}
}
