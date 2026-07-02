// --------------------------------------------------------------------------
//
// Super Shotgun Helpers
//
// --------------------------------------------------------------------------

extend class StateProvider
{
	action void A_FireShotgunIndividual()
	{
		if (player == null) return;
		
		int hand = 0;
		int alflags = 0;
		Weapon weap = invoker == player.OffhandWeapon ? player.OffhandWeapon : player.ReadyWeapon;
		
		if (weap != null && invoker == weap && stateinfo != null && stateinfo.mStateType == STATE_Psprite)
		{
			hand = weap.bOffhandWeapon ? 1 : 0;
			alflags |= weap.bOffhandWeapon ? ALF_ISOFFHAND : 0;
			
			// Deplete 1 shell for individual fire
			if (!weap.DepleteAmmo (weap.bAltFire, true, 1))
				return;
			
			// Custom flash state if needed
			State flash = weap.FindState('Flash');
			if (flash) player.SetPsprite(PSP_FLASH, flash, true, weap);
		}
		
		A_StartSound ("weapons/sshotf", CHAN_WEAPON);
		player.mo.PlayAttacking2 ();
		
		A_BallisticFire(7.0, 5.0, 10, 5, 2.0);
	}
	
	action void A_VRRecoil(double intensity)
	{
		if (!player || !player.mo) return;
		CVar recoilVar = CVar.GetCVar("vr_recoil", player);
		if (recoilVar && recoilVar.GetBool())
		{
			player.mo.pitch -= intensity * frandom(0.8, 1.2);
			player.mo.angle += frandom(-intensity*0.2, intensity*0.2);
		}
	}
}

// --------------------------------------------------------------------------
//
// Plasma Beam Projectile
//
// --------------------------------------------------------------------------

class PlasmaBeam : Actor
{
	Default
	{
		Radius 13;
		Height 8;
		Speed 60;
		Damage 7;
		Projectile;
		+BRIGHT
		+FORCEXYBILLBOARD
		+SPAWNSOUNDSOURCE
		RenderStyle "Add";
		Alpha 0.8;
		Scale 0.25;
		DamageType "PlasmaDamage";
		Decal "Scorch";
	}
	States
	{
	Spawn:
		PLBA ABCDEF 2 Bright;
		Loop;
	Death:
		PLSE ABCDE 2 Bright;
		Stop;
	}
}

extend class StateProvider
{
	action void A_FirePlasmaBeam()
	{
		if (player == null) return;
		
		int hand = 0;
		Weapon weap = invoker == player.OffhandWeapon ? player.OffhandWeapon : player.ReadyWeapon;
		
		if (weap != null && invoker == weap && stateinfo != null && stateinfo.mStateType == STATE_Psprite)
		{
			hand = weap.bOffhandWeapon ? 1 : 0;
			if (!weap.DepleteAmmo (weap.bAltFire, true))
				return;
		}
		
		A_StartSound("weapons/plasma/fire", CHAN_WEAPON, CHANF_OVERLAP);
		SpawnPlayerMissile ("PlasmaBeam", aimflags:hand ? ALF_ISOFFHAND : 0);
		A_VRRecoil(0.2);
	}
}

class ThrownWeapon : Actor
{
	Default
	{
		Radius 8;
		Height 8;
		Speed 30;
		Damage 20;
		Projectile;
		-NOGRAVITY
		+BOUNCEONFLOORS
		+BOUNCEONWALLS
		BounceType "Doom";
		BounceFactor 0.5;
		Gravity 0.8;
		DamageType "Melee";
	}

	String weaponClass;

	States
	{
	Spawn:
		TNT1 A 1
		{
			angle += 45;
			roll += 45;
			// Visual representation would be better with models
		}
		Loop;
	Death:
		TNT1 A 0
		{
			A_SpawnItemEx(weaponClass, 0, 0, 0, 0, 0, 0, 0, SXF_NOCHECKPOSITION);
		}
		Stop;
	}
}

extend class StateProvider
{
	action void A_ThrowCurrentWeapon()
	{
		if (!player || !player.mo) return;
		
		Weapon weap = player.ReadyWeapon;
		if (!weap || weap is "Fist") return;

		CVar throwVar = CVar.GetCVar("vr_weapon_throwable", player);
		if (!throwVar || !throwVar.GetBool()) return;

		String wCls = weap.GetClassName();
		player.mo.A_StartSound("weapons/grntoss", CHAN_WEAPON);
		
		// Create a projectile that looks like the weapon
		ThrownWeapon thrown = ThrownWeapon(SpawnPlayerMissile("ThrownWeapon"));
		if (thrown)
		{
			thrown.weaponClass = wCls;
			player.mo.TakeInventory(wCls, 1);
		}
	}

	action void A_CheckSpawnModel()
	{
		CVar modVar = CVar.GetCVar("vr_spawn_models", players[consoleplayer]);
		if (modVar && modVar.GetBool())
		{
			// Logic to swap current sprite-actor for a model-actor if applicable
		}
	}

	action void A_BallisticFire(double spread_x, double spread_y, int pelletCount, int damage, double recoil, bool flash = true, double gravity = 0.15, double speed = 200)
	{
		if (!player || !player.mo) return;
		
		int hand = 0;
		Weapon weap = invoker == player.OffhandWeapon ? player.OffhandWeapon : player.ReadyWeapon;
		if (weap != null && invoker == weap && stateinfo != null && stateinfo.mStateType == STATE_Psprite)
		{
			hand = weap.bOffhandWeapon ? 1 : 0;
			if (!weap.DepleteAmmo (weap.bAltFire, true))
				return;

			if (flash)
			{
				player.SetSafeFlash(weap, weap.FindState('Flash'), i: (player.refire ? 1 : 0));
			}
		}

		player.mo.PlayAttacking2();

		CVar dropVar = CVar.GetCVar("vr_ballistic_drop", player);
		bool useDrop = dropVar && dropVar.GetBool();

		for (int i = 0; i < pelletCount; i++)
		{
			if (useDrop)
			{
				double ang = angle + frandom(-spread_x, spread_x);
				double pit = pitch + frandom(-spread_y, spread_y);
				
				Actor projectile = player.mo.SpawnPlayerMissile("BallisticBullet", ang, aimflags: hand ? ALF_ISOFFHAND : 0);
				if (projectile)
				{
					projectile.pitch = pit;
					projectile.master = weap;
					projectile.Damage = damage;
					projectile.gravity = gravity;
					projectile.speed = speed;
					// Re-calculate velocity since we changed speed
					projectile.vel = (cos(projectile.angle) * cos(projectile.pitch), sin(projectile.angle) * cos(projectile.pitch), -sin(projectile.pitch)) * speed;
				}
			}
			else
			{
				player.mo.A_FireBullets(spread_x, spread_y, 1, damage, "BulletPuff", FBF_NORANDOM, aimflags:hand ? ALF_ISOFFHAND : 0);
			}
		}
		
		A_VRRecoil(recoil);
	}
}

class BallisticBullet : FastProjectile
{
	Default
	{
		Radius 2;
		Height 2;
		Speed 200; // Faster for "Real Bullets"
		Damage 5;
		Projectile;
		+RANDOMIZE
		-NOGRAVITY
		Gravity 0.15; // Slightly more drop
		Decal "BulletChip";
		MissileType "BallisticTracer";
		MissileHeight 8;
		DeathSound "weapons/pistol"; // Small impact sound
	}
	
	States
	{
	Spawn:
		TNT1 A 1;
		Loop;
	Death:
		TNT1 A 0 
		{
			A_SpawnItemEx("BulletPuff");
			A_StartSound("bullet/impact", CHAN_BODY, 0, 0.5);
		}
		Stop;
	}
}

class BallisticTracer : Actor
{
	Default
	{
		+NOBLOCKMAP
		+NOGRAVITY
		RenderStyle "Add";
		Alpha 0.6;
		Scale 0.1;
	}
	States
	{
	Spawn:
		PUFF A 2 Bright;
		Stop;
	}
}
