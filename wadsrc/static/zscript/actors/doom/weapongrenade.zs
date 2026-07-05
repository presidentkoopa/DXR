// --------------------------------------------------------------------------
//
// Hand Grenade
//
// --------------------------------------------------------------------------

class HandGrenade : DoomWeapon
{
	Default
	{
		Weapon.SelectionOrder 2500;
		Weapon.SlotNumber 8;   // [XR] slot 8 (matches DoomPlayer's Player.WeaponSlot 8)
		Weapon.AmmoUse 1;
		Weapon.AmmoGive 3;
		Weapon.AmmoType "GrenadeAmmo";
		Inventory.PickupMessage "Picked up some Hand Grenades!";
		Tag "Hand Grenade";
		+WEAPON.NOAUTOFIRE
		Keywords "mass:5", "grab", "class:grenade", "dmg:explosive", "style:thrown", "weight:light", "range:medium", "role:tactical";
	}

	States
	{
	Ready:
		JHND A 1 A_WeaponReady();
		Loop;
	Deselect:
		JHND A 1 A_Lower;
		Loop;
	Select:
		JHND A 1
		{
			A_Raise();
			A_DataSiphonEquip();
		}
		Loop;
	Fire:
		JHND B 4;
		JHND C 4 A_StartSound("weapons/grnpullpin", CHAN_WEAPON);
		JHND D 4;
	Hold:
		JHND D 1;
		TNT1 A 0 A_ReFire("Hold");
	Throw:
		JHND E 2 A_StartSound("weapons/grntoss", CHAN_WEAPON);
		JHND F 2 
		{
			Actor proj = A_SpawnProjectile("ThrownGrenade", 0, 0, 0, 12);
			if (proj) proj.master = self;
		}
		JHND GHI 2;
		Goto Ready;
	Spawn:
		JGRN A 0 A_CheckSpawnModel();
		JGRN A -1;
		Stop;
	}
}

class ThrownGrenade : Actor
{
	Default
	{
		Radius 5;
		Height 5;
		Speed 25;
		Damage 5;
		Projectile;
		-NOGRAVITY
		+BOUNCEONFLOORS
		+BOUNCEONWALLS
		+BOUNCEONCEILINGS
		+CANBOUNCEWATER
		+INTERPOLATEANGLES
		BounceType "Doom";
		BounceFactor 0.6;
		WallBounceFactor 0.5;
		BounceSound "weapons/grnbounce";
		Gravity 0.8;
		DamageType "Explosive";
		Obituary "%o was shredded by %k's grenade.";
	}

	int timer;

	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		timer = 0;
	}

	override void Tick()
	{
		Super.Tick();
		if (bNoTimeFreeze && !isFrozen())
		{
			timer++;
			if (timer >= 105) 
			{
				Explode();
			}
		}
	}

	void Explode()
	{
		A_StartSound("weapons/grenadebang", CHAN_BODY, CHANF_OVERLAP);
		A_Explode(160, 256);
		A_Explode(120, 128);
		A_SpawnItemEx("GrenadeExplosionEffect", 0, 0, 0);
		level.AddGlowPanel(Color(255, 255, 160, 60), 200.0, pos.x, pos.y, pos.z, 14, 1.0, 0.0, 0.0, 0);
		for (int i = 0; i < 16; i++)
		{
			A_SpawnItemEx("GrenadeShrapnel", 0, 0, 8, frandom(10, 20), 0, frandom(2, 10), random(0, 360), SXF_NOCHECKPOSITION);
		}
		Destroy();
	}

	States
	{
	Spawn:
		JGRN ABCDEFGH 2 
		{
			angle += 25;
			roll += 25;
		}
		Loop;
	}
}

class GrenadeHandler : StaticEventHandler
{
	override void NetworkProcess(ConsoleEvent e)
	{
		if (e.Name == "throw_grenade")
		{
			PlayerInfo pl = players[e.Player];
			if (!pl || !pl.mo || pl.health <= 0) return;
			
			// Check for ammo
			Inventory ammo = pl.mo.FindInventory("GrenadeAmmo");
			if (ammo && ammo.Amount > 0)
			{
				ammo.Amount--;
				pl.mo.A_StartSound("weapons/grntoss", CHAN_WEAPON);
				Actor proj = pl.mo.SpawnPlayerMissile("ThrownGrenade");
				if (proj)
				{
					// Try to find the HandGrenade weapon in inventory to set as master
					proj.master = pl.mo.FindInventory("HandGrenade");
				}
			}
			else
			{
				pl.mo.A_StartSound("DRYFIRE", CHAN_WEAPON);
			}
		}
		else if (e.Name == "throw_weapon")
		{
			PlayerInfo pl = players[e.Player];
			if (!pl || !pl.mo || pl.health <= 0) return;
			
			// We need to call A_ThrowCurrentWeapon from a state, but here we are in an event.
			// However, we can spawn it directly.
			Weapon weap = pl.ReadyWeapon;
			if (weap && !(weap is "Fist"))
			{
				CVar throwVar = CVar.GetCVar("vr_weapon_throwable", pl);
				if (throwVar && throwVar.GetBool())
				{
					String wCls = weap.GetClassName();
					pl.mo.A_StartSound("weapons/grntoss", CHAN_WEAPON);
					
					// Manually spawn the ThrownWeapon actor
					Vector3 pos = pl.mo.Pos + (0, 0, pl.mo.ViewHeight);
					Vector3 dir = (cos(pl.mo.Angle) * cos(pl.mo.Pitch), sin(pl.mo.Angle) * cos(pl.mo.Pitch), -sin(pl.mo.Pitch));
					
					ThrownWeapon thrown = ThrownWeapon(Actor.Spawn("ThrownWeapon", pos));
					if (thrown)
					{
						thrown.target = pl.mo;
						thrown.vel = dir * 25;
						thrown.weaponClass = wCls;
						pl.mo.TakeInventory(wCls, 1);
					}
				}
			}
		}
	}

	// Grenade trajectory-arc preview -- disabled. This called pl.mo.LineTrace (a play-scope-only
	// function) from inside RenderOverlay (a ui-scope callback, events.zs: "virtual ui void
	// RenderOverlay"), and Screen.ProjectVector, which does not exist anywhere in this fork's
	// Screen API (grep of engine/base.zs finds zero Project* functions at all). Both problems are
	// structural, not typos -- this needs a real play-scope arc precomputation feeding a ui-scope
	// draw step, not a quick fix. Disabled rather than guessed at under time pressure.
	override void RenderOverlay(RenderEvent e)
	{
	}
}

class GrenadeExplosionEffect : Actor
{
	Default
	{
		+NOBLOCKMAP
		+NOGRAVITY
		+BRIGHT
		+FORCEXYBILLBOARD
		RenderStyle "Add";
		Alpha 1.0;
		Scale 2.0;
	}
	States
	{
	Spawn:
		EXP1 ABCDEFGHIJKLMN 2 Bright;
		Stop;
	}
}

class GrenadeShrapnel : Actor
{
	Default
	{
		Radius 2;
		Height 2;
		Speed 20;
		Damage 5;
		Projectile;
		Gravity 0.8;
		-NOGRAVITY
		+BOUNCEONFLOORS
		BounceType "Doom";
		Scale 0.2;
	}
	States
	{
	Spawn:
		TNT1 A 1 Bright A_SpawnParticle("Gray", SPF_FULLBRIGHT, 5, 2);
		Loop;
	Death:
		PUFF A 2;
		Stop;
	}
}

class GrenadeAmmo : Ammo
{
	Default
	{
		Inventory.Amount 1;
		Inventory.MaxAmount 10;
		Ammo.BackpackAmount 2;
		Ammo.BackpackMaxAmount 20;
		Inventory.Icon "GRNDA0";
		Inventory.PickupMessage "Picked up a Grenade.";
		Tag "Grenades";
	}
	States
	{
	Spawn:
		JGRN A -1;
		Stop;
	}
}
