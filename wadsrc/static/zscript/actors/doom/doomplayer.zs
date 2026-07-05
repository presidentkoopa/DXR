//===========================================================================
//
// Player
//
//===========================================================================
class DoomPlayer : PlayerPawn
{
	Default
	{
		Speed 1;
		Health 100;
		Radius 16;
		Height 56;
		Mass 100;
		PainChance 255;
		Player.DisplayName "Marine";
		Player.CrouchSprite "PLYC";
		Player.StartItem "Pistol";
		Player.StartItem "Fist";
		Player.StartItem "VRSword";
		Player.StartItem "IceHook";
		// [XR] Spawn with a FULL reserve of EVERY ammo type so every weapon (and its dual-wield _2,
		// which shares the same pool) is loaded and ready from the start -- no gun spawns empty.
		Player.StartItem "Clip", 200;        // bullets: Pistol / Rifle / Revolver / Chaingun / SMG
		Player.StartItem "Shell", 50;        // Shotgun / SuperShotgun
		Player.StartItem "RocketAmmo", 50;   // RocketLauncher / M79
		Player.StartItem "Cell", 300;        // PlasmaRifle / BFG9000
		Player.StartItem "Fuel", 100;        // Flamethrower
		// [XR] The VR grab-tools now ALSO have number-key slots (slot 9 = melee/grab: IceHook,
		// VRSword, XRWhip; ShieldSaw shares the melee slot 1). They still work as physical VR-grab
		// tools -- the slots just make them selectable/visible without the (unwired) holster-draw.
		// Spawn loadout: VRSword + IceHook via StartItem above; XRWhip + ShieldSaw via
		// WeaponReplacementHandler (vr_weapon_logic.zs), both CVars (vr_start_with_whip /
		// vr_start_with_shieldsaw) default ON -- so the marine spawns holding all four tools.
		// Dual-wield "_2" variants share their base's slot so the SECOND gun is selectable
		// (weapon wheel / next-weapon) -- required for the banked-spare case where both hands
		// were full when it was acquired. Melee/tools (Fist/Chainsaw/ShieldSaw/Grenade/IceHook/
		// VRSword/XRWhip) are not dual-wieldable, so no variants there.
		Player.WeaponSlot 1, "Fist", "Chainsaw", "Flamethrower", "Flamethrower_2", "ShieldSaw";
		Player.WeaponSlot 2, "Pistol", "Pistol_2", "SMG", "SMG_2", "Revolver", "Revolver_2";
		Player.WeaponSlot 3, "Shotgun", "Shotgun_2", "SuperShotgun", "SuperShotgun_2";
		Player.WeaponSlot 4, "Chaingun", "Chaingun_2", "Rifle", "Rifle_2";
		Player.WeaponSlot 5, "RocketLauncher", "RocketLauncher_2", "M79", "M79_2";
		Player.WeaponSlot 6, "ID24Incinerator", "PlasmaRifle", "PlasmaRifle_2";
		Player.WeaponSlot 7, "ID24CalamityBlade", "BFG9000", "BFG9000_2";
		Player.WeaponSlot 8, "HandGrenade";
		Player.WeaponSlot 9, "IceHook", "VRSword", "XRWhip";
		
		Player.ColorRange 112, 127;
		Player.Colorset 0, "$TXT_COLOR_GREEN",		0x70, 0x7F,  0x72;
		Player.Colorset 1, "$TXT_COLOR_GRAY",		0x60, 0x6F,  0x62;
		Player.Colorset 2, "$TXT_COLOR_BROWN",		0x40, 0x4F,  0x42;
		Player.Colorset 3, "$TXT_COLOR_RED",		0x20, 0x2F,  0x22;
		// Doom Legacy additions
		Player.Colorset 4, "$TXT_COLOR_LIGHTGRAY",	0x58, 0x67,  0x5A;
		Player.Colorset 5, "$TXT_COLOR_LIGHTBROWN",	0x38, 0x47,  0x3A;
		Player.Colorset 6, "$TXT_COLOR_LIGHTRED",	0xB0, 0xBF,  0xB2;
		Player.Colorset 7, "$TXT_COLOR_LIGHTBLUE",	0xC0, 0xCF,  0xC2;
	}

	States
	{
	Spawn:
		PLAY A -1;
		Loop;
	See:
		PLAY ABCD 4;
		Loop;
	Missile:
		PLAY E 12;
		Goto Spawn;
	Melee:
		PLAY F 6 BRIGHT;
		Goto Missile;
	Pain:
		PLAY G 4;
		PLAY G 4 A_Pain;
		Goto Spawn;
	Death:
		PLAY H 0 A_PlayerSkinCheck("AltSkinDeath");
	Death1:
		PLAY H 10;
		PLAY I 10 A_PlayerScream;
		PLAY J 10 A_NoBlocking;
		PLAY KLM 10;
		PLAY N -1;
		Stop;
	XDeath:
		PLAY O 0 A_PlayerSkinCheck("AltSkinXDeath");
	XDeath1:
		PLAY O 5;
		PLAY P 5 A_XScream;
		PLAY Q 5 A_NoBlocking;
		PLAY RSTUV 5;
		PLAY W -1;
		Stop;
	AltSkinDeath:
		PLAY H 6;
		PLAY I 6 A_PlayerScream;
		PLAY JK 6;
		PLAY L 6 A_NoBlocking;
		PLAY MNO 6;
		PLAY P -1;
		Stop;
	AltSkinXDeath:
		PLAY Q 5 A_PlayerScream;
		PLAY R 0 A_NoBlocking;
		PLAY R 5 A_SkullPop;
		PLAY STUVWX 5;
		PLAY Y -1;
		Stop;
	}
}
