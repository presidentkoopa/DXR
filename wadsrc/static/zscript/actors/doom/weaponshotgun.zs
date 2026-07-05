// --------------------------------------------------------------------------
//
// Shotgun
//
// --------------------------------------------------------------------------

class Shotgun : DoomWeapon
{
	mixin XR_ManualReload;   // [XR] chamber gate + reload; native VR gesture FSM refills it (vr_new_weapon_handling)
	Default
	{
		Weapon.SelectionOrder 1300;
		Weapon.SlotNumber 3;   // [XR] slot 3 (matches DoomPlayer's Player.WeaponSlot 3)
		Weapon.AmmoUse 1;
		Weapon.AmmoGive 8;
		Weapon.AmmoType "Shell";
		Inventory.PickupMessage "$GOTSHOTGUN";
		Obituary "$OB_MPSHOTGUN";
		Tag "$TAG_SHOTGUN";
		Keywords "mass:40", "grab", "class:shotgun", "dmg:ballistic", "style:spread", "weight:medium", "range:short", "fire:pump", "handling:solid", "role:workhorse", "vr_dualwield";
	}
	States
	{
	Ready:
		SHTG A 0 { if (invoker.XRMagSize == 0) invoker.XR_InitChamber(8); }   // [XR] mag size 8 (shells)
		SHTG A 1 A_WeaponReady(WRF_ALLOWRELOAD);                              // on-demand reload button (classic fallback)
		Loop;
	Deselect:
		SHTG A 1 A_Lower;
		Loop;
	Select:
		SHTG A 1
		{
			A_Raise();
			AssignWeaponHandling("shell");   // [XR] shell-by-shell reload FSM (RS_SHELL) + pump rack; hs_* geometric-default
		}
		Loop;
	Fire:
		TNT1 A 0 A_JumpIf(!A_XR_TryFire(), "Ready");   // [XR] chamber gate: consumes 1 loaded round, dry-clicks when empty
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
	Reload:
		SHTG A 0 A_XR_EjectToPouch();   // VR: eject mag -> Ready (chest pouch reloads); flatscreen: falls through
		SHTG A 30;
		SHTG A 15 A_XR_RefillChamber();   // re-arm chamber from the reserve
		Goto Ready;
	Flash:
		// VR: muzzle-flash sprite suppressed, muzzle light kept.
		TNT1 A 4 Bright A_Light1;
		TNT1 A 3 Bright A_Light2;
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

// Dual-wield variant: a DISTINCT class the engine can select independently from the base
// Shotgun (that's the whole point -- weapon selection is by class, so two of ONE class are
// indistinguishable). Inherits everything (states, fire, Keywords incl. vr_dualwield). It must
// NOT redeclare AmmoType, so it shares the same shell reserve pool as the base Shotgun. Its 3D
// model is shared via a cloned "Model Shotgun_2" stanza in modeldef.txt (model lookup is keyed
// on the exact class, so a bare subclass would render invisible without it).
// VR_GiveDualWield spawns this on the second pickup; scales to _3.._N by the same pattern.
class Shotgun_2 : Shotgun {}

