// The barrel of green goop ------------------------------------------------

class ExplosiveBarrel : Actor
{
	Default
	{
		Health 20;
		Radius 10;
		Height 42;
		+SOLID
		+SHOOTABLE
		+NOBLOOD
		+ACTIVATEMCROSS
		+DONTGIB
		+NOICEDEATH
		+OLDRADIUSDMG
		DeathSound "world/barrelx";
		Obituary "$OB_BARREL";
		// "flags:grabprop" lets the VR gravity-glove grab-candidate scan pick this up despite
		// lacking MF_SPECIAL/MF_MISSILE (p_user.cpp's native filter checks this specific token --
		// NOT the bare "grab" tag below, which is a general mass-namespace marker shared by nearly
		// every actor in the game, monsters included, and would be unsafe to gate grabbability on);
		// "flags:throwable" makes a release-with-velocity actually throw it instead of just
		// dropping it (KeywordDispatcher::IsThrowable).
		Keywords "mass:100", "grab", "class:barrel", "type:hazard", "trait:volatile", "dmg:splash", "weight:medium", "status:reactive", "flags:throwable", "flags:grabprop";
	}
	States
	{
	Spawn:
		BAR1 AB 6;
		Loop;
	Death:
		BEXP A 5 BRIGHT;
		BEXP B 5 BRIGHT A_Scream;
		BEXP C 5 BRIGHT;
		BEXP D 10 BRIGHT
		{
			A_Explode();
			// By default, layer the same pretty fireball built for grenades on top of the
			// stock BEXP burn, at 60% of the grenade's size (a barrel reads smaller than a
			// hand-grenade blast). Purely visual -- A_Explode above already applied the real,
			// unchanged damage/radius. Opt into "vr_barrel_vanilla_explosion" to get the plain
			// stock BEXP-only explosion instead.
			CVar vanillaVar = CVar.GetCVar("vr_barrel_vanilla_explosion", players[consoleplayer]);
			bool vanilla = (vanillaVar && vanillaVar.GetBool());
			if (!vanilla)
			{
				// A_SpawnItemEx returns (bool, Actor) -- destructure both (single-Actor capture
				// would only grab the bool). Pattern confirmed in stateprovider.zs.
				bool fxSpawned;
				Actor fx;
				[fxSpawned, fx] = A_SpawnItemEx("GrenadeExplosionEffect", 0, 0, 0);
				if (fx) fx.scale *= 0.6; // 60% of the grenade explosion
			}
		}
		BEXP E 10 BRIGHT;
		TNT1 A 1050 BRIGHT A_BarrelDestroy;
		TNT1 A 5 A_Respawn;
		Wait;
	}

	// VR impact explosive: grabbing+throwing the barrel and hitting a shootable actor with it
	// detonates it on contact, same as being shot -- reuses the Death:BEXP sequence above
	// untouched. Gated on real throw speed so a barrel merely resting/rolling on the floor (or
	// nudged by physics) doesn't self-detonate; only a genuine VR throw does.
	override void Tick()
	{
		Super.Tick();

		if (health > 0 && Vel.Length() > 10.0)
		{
			BlockThingsIterator it = BlockThingsIterator.Create(self, radius + 64);
			while (it.Next())
			{
				let targ = it.thing;
				if (targ == null || targ == self || !targ.bShootable || targ.health <= 0) continue;

				double blockdist = radius + targ.radius;
				if (Distance3D(targ) > blockdist) continue;

				// Credit whoever grabbed/threw this (set at grab time in p_user.cpp / whip
				// catch) so A_Explode's RadiusAttack correctly attributes the kill to the
				// player, not the barrel itself. Falls back to self if it was never grabbed
				// (e.g. shoved into motion some other way). (Plain assign + null-check, NOT a
				// ?: ternary -- ZScript can't reconcile Actor 'target' with ExplosiveBarrel 'self'.)
				Actor killer = target;
				if (killer == null) killer = self;
				Die(killer, killer);
				break;
			}
		}
	}
}

extend class Actor
{
	void A_BarrelDestroy()
	{
		if (sv_barrelrespawn)
		{
			Height = Default.Height;
			bInvisible = true;
			bSolid = false;
		}
		else
		{
			Destroy();
		}
	}
}

// Bullet puff -------------------------------------------------------------

class BulletPuff : Actor
{
	Default
	{
		+NOBLOCKMAP
		+NOGRAVITY
		+ALLOWPARTICLES
		+RANDOMIZE
		+ZDOOMTRANS
		RenderStyle "Translucent";
		Alpha 0.5;
		VSpeed 1;
		Mass 5;
	}
	States
	{
	Spawn:
		PUFF A 4 Bright;
		PUFF B 4;
	Melee:
		PUFF CD 4;
		Stop;
	}
}
	
// Container for an unused state -------------------------------------------

/* Doom defined the states S_STALAG, S_DEADTORSO, and S_DEADBOTTOM but never
 * actually used them. For compatibility with DeHackEd patches, they still
 * need to be kept around. This class serves that purpose.
 */

class DoomUnusedStates : Actor
{
	States
	{
	Label1:
		SMT2 A -1;
		stop;
	Label2:
		PLAY N -1;
		stop;
		PLAY S -1;
		stop;
	TNT: // MBF compatibility
		TNT1 A -1;
		Loop;
	}
}

// MBF Beta emulation items

class EvilSceptre : ScoreItem
{
	Default
	{
		Inventory.PickupMessage "$BETA_BONUS3";
	}
	States
	{
	Spawn:
		BON3 A 6;
		Loop;
	}
}

class UnholyBible : ScoreItem
{
	Default
	{
		Inventory.PickupMessage "$BETA_BONUS4";
	}
	States
	{
	Spawn:
		BON4 A 6;
		Loop;
	}
}
