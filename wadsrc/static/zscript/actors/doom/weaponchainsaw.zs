// --------------------------------------------------------------------------
//
// Chainsaw
//
// --------------------------------------------------------------------------

class Chainsaw : DoomWeapon
{
	// ---- Boomerang-throw (AltFire) state ----
	Array<Actor> lockList;   // monsters currently locked, in acquisition order
	bool sawInFlight;        // a thrown chainsaw is out; block re-throw / re-lock

	Default
	{
		Weapon.Kickback 0;
		Weapon.SelectionOrder 2200;
		Weapon.SlotNumber 1;   // [XR] slot 1 (matches DoomPlayer's Player.WeaponSlot 1)
		Weapon.UpSound "weapons/sawup";
		Weapon.ReadySound "weapons/sawidle";
		Inventory.PickupMessage "$GOTCHAINSAW";
		Obituary "$OB_MPCHAINSAW";
		Tag "$TAG_CHAINSAW";
		+WEAPON.MELEEWEAPON
		Keywords "mass:60", "grab", "class:chainsaw", "dmg:shredder", "dmg:mechanical", "style:melee", "weight:heavy", "range:touch", "fire:continuous", "handling:heavy", "trait:berserker_fuel", "role:desperation", "context:loud";
	}

	// Angular (view-cone) distance of 'other' from where the player is looking; smaller = more centred.
	private double GetFOVDistance(PlayerPawn viewer, Actor other)
	{
		vector3 viewpoint = viewer.pos;
		viewpoint.z = viewer.player.viewz;
		vector3 otherCenter = other.pos;
		otherCenter.z += other.Height * 0.5;
		vector2 viewAngles = (viewer.angle, viewer.pitch);
		vector3 sph = Level.SphericalCoords(viewpoint, otherCenter, viewAngles);
		return sph.xy.Length();
	}

	// Held each tic while AltFire is down: prune dead locks, acquire the next nearest
	// in-cone monster (up to the cap), and draw a target bracket over every lock.
	void UpdateChainsawLocks()
	{
		int   lockMax  = 3;   double lockRange = 640.0;  double lockCone = 35.0;
		CVar c;
		c = CVar.FindCVar("vr_chainsaw_lock_max");   if (c) lockMax  = clamp(c.GetInt(), 1, 5);
		c = CVar.FindCVar("vr_chainsaw_lock_range"); if (c) lockRange = c.GetFloat();
		c = CVar.FindCVar("vr_chainsaw_lock_cone");  if (c) lockCone  = c.GetFloat();

		// prune dead / gone
		for (int i = lockList.Size() - 1; i >= 0; i--)
			if (!lockList[i] || lockList[i].health <= 0 || lockList[i].bCorpse) lockList.Delete(i);

		// acquire one new best candidate this tic (ramps the lock up while you hold)
		if (owner && lockList.Size() < lockMax)
		{
			Actor best; double bestFov = 1e9;
			ThinkerIterator it = ThinkerIterator.Create("Actor");
			Actor mo;
			while (mo = Actor(it.Next()))
			{
				if (!mo.bIsMonster || mo.health <= 0 || mo == owner || mo.bCorpse) continue;
				if (owner.Distance2D(mo) > lockRange || !owner.CheckSight(mo)) continue;
				double fov = GetFOVDistance(PlayerPawn(owner), mo);
				if (fov > lockCone) continue;
				bool already = false;
				for (int i = 0; i < lockList.Size(); i++) if (lockList[i] == mo) { already = true; break; }
				if (already) continue;
				if (fov < bestFov) { bestFov = fov; best = mo; }
			}
			if (best) { lockList.Push(best); owner.A_StartSound("weapons/sawidle", CHAN_BODY); }
		}

		// highlight every current lock with corner brackets (shader wgType 18)
		for (int i = 0; i < lockList.Size(); i++)
		{
			Actor a = lockList[i];
			if (a) level.AddGlowPanel(Color(255, 255, 90, 40), a.radius * 2.4,
				a.pos.x, a.pos.y, a.pos.z + a.height * 0.5, 18, 1.0, 0.0, 0.0, 0);
		}
	}

	// On release: launch the boomerang with the locked queue.
	void ThrowChainsaw()
	{
		if (!owner) { lockList.Clear(); return; }
		double dmg = 25.0;
		CVar c = CVar.FindCVar("vr_chainsaw_throw_dmg"); if (c) dmg = c.GetFloat();

		int hand    = bOffhandWeapon ? 1 : 0;
		int alflags = bOffhandWeapon ? ALF_ISOFFHAND : 0;
		// SpawnPlayerMissile returns (Actor, Actor); assign to a single Actor (takes the first)
		// THEN cast -- casting the multi-return call directly is a "too many values" error.
		Actor m = owner.SpawnPlayerMissile("ThrownChainsaw", aimflags: alflags);
		let saw = ThrownChainsaw(m);
		if (!saw) { lockList.Clear(); return; }

		for (int i = 0; i < lockList.Size(); i++)
			if (lockList[i]) saw.hitList.Push(lockList[i]);

		saw.Launch(owner, hand, saw.Speed, dmg, 175);
		sawInFlight = true;
		lockList.Clear();
		owner.A_StartSound("weapons/sawup", CHAN_WEAPON);
		owner.A_AlertMonsters(512);
	}

	action void A_ChainsawLock()  { invoker.UpdateChainsawLocks(); }
	action void A_ChainsawThrow() { invoker.ThrowChainsaw(); }
	// Clears the in-flight flag once the thrown saw is gone (it Destroys itself on catch/timeout).
	action void A_ChainsawFlightCheck()
	{
		if (invoker.sawInFlight)
		{
			bool anyOut = false;
			ThinkerIterator it = ThinkerIterator.Create("ThrownChainsaw");
			if (it.Next()) anyOut = true;
			if (!anyOut) invoker.sawInFlight = false;
		}
	}

	States
	{
	Ready:
		SAWG CD 4
		{
			A_WeaponReady();
			A_ChainsawFlightCheck();
		}
		Loop;
	Deselect:
		SAWG C 1 A_Lower;
		Loop;
	Select:
		SAWG C 1 A_Raise;
		Loop;
	Fire:
		SAWG AB 4 A_Saw;
		SAWG B 0 A_ReFire;
		Goto Ready;
	// AltFire: boomerang throw. Hold to lock up to N in-cone monsters (they bracket up),
	// release to hurl the saw -- it weaves through them cutting each, then returns to hand.
	AltFire:
		SAWG C 0 A_JumpIf(invoker.sawInFlight, "Ready");   // one saw out at a time
	ChainsawLockLoop:
		SAWG C 2 A_ChainsawLock();
		SAWG C 0 A_ReFire("ChainsawLockLoop");
		SAWG C 0 A_ChainsawThrow();
		SAWG CD 3;
		Goto Ready;
	Spawn:
		CSAW A 0 A_CheckSpawnModel();
		CSAW A -1;
		Stop;
	}
}
	

extend class StateProvider
{
	action void A_Saw(sound fullsound = "weapons/sawfull", sound hitsound = "weapons/sawhit", int damage = 2, class<Actor> pufftype = "BulletPuff", int flags = 0, double range = 0, double spread_xy = 2.8125, double spread_z = 0, double lifesteal = 0, int lifestealmax = 0, class<BasicArmorBonus> armorbonustype = "ArmorBonus")
	{
		FTranslatedLineTarget t;

		if (player == null)
		{
			return;
		}

		if (pufftype == null)
		{
			pufftype = 'BulletPuff';
		}
		if (damage == 0)
		{
			damage = 2;
		}
		if (!(flags & SF_NORANDOM))
		{
			damage *=  random[Saw](1, 10);
		}
		if (range == 0)
		{ 
			range = MeleeRange + MELEEDELTA + (1. / 65536.); // MBF21 SAWRANGE;
		}

		Weapon weap = invoker == player.OffhandWeapon ? player.OffhandWeapon : player.ReadyWeapon;
		int hand = weap != null && weap.bOffhandWeapon ? 1 : 0;
		int alflags = hand ? ALF_ISOFFHAND : 0;
		double ang = angle + spread_xy * (Random2[Saw]() / 255.);
		double slope = AimLineAttack (ang, range, t, flags: alflags) + spread_z * (Random2[Saw]() / 255.);

		if (weap != null && !(flags & SF_NOUSEAMMO) && !(!t.linetarget && (flags & SF_NOUSEAMMOMISS)) && !weap.bDehAmmo &&
			invoker == weap && stateinfo != null && stateinfo.mStateType == STATE_Psprite)
		{
			if (!weap.DepleteAmmo (weap.bAltFire))
				return;
		}

		int puffFlags = (flags & SF_NORANDOMPUFFZ) ? LAF_NORANDOMPUFFZ : 0;
		puffFlags |= hand ? LAF_ISOFFHAND : 0;

		Actor puff;
		int actualdamage;
		[puff, actualdamage] = LineAttack (ang, range, slope, damage, 'Melee', pufftype, puffFlags, t);

		if (!t.linetarget)
		{
			if ((flags & SF_RANDOMLIGHTMISS) && (Random[Saw]() > 64))
			{
				player.extralight = !player.extralight;
			}
			A_StartSound (fullsound, CHAN_WEAPON);
			return;
		}

		if (flags & SF_RANDOMLIGHTHIT)
		{
			int randVal = Random[Saw]();
			if (randVal < 64)
			{
				player.extralight = 0;
			}
			else if (randVal < 160)
			{
				player.extralight = 1;
			}
			else
			{
				player.extralight = 2;
			}
		}

		if (lifesteal && !t.linetarget.bDontDrain)
		{
			if (flags & SF_STEALARMOR)
			{
				if (armorbonustype == null)
				{
					armorbonustype = "ArmorBonus";
				}
				if (armorbonustype != null)
				{
					BasicArmorBonus armorbonus = BasicArmorBonus(Spawn(armorbonustype));
					armorbonus.SaveAmount = int(armorbonus.SaveAmount * actualdamage * lifesteal);
					armorbonus.MaxSaveAmount = lifestealmax <= 0 ? armorbonus.MaxSaveAmount : lifestealmax;
					armorbonus.bDropped = true;
					armorbonus.ClearCounters();

					if (!armorbonus.CallTryPickup (self))
					{
						armorbonus.Destroy ();
					}
				}
			}

			else
			{
				GiveBody (int(actualdamage * lifesteal), lifestealmax);
			}
		}

		A_StartSound (hitsound, CHAN_WEAPON);
			
		// turn to face target
		if ((!player.PlayInVR || vanilla_melee_attack) && !(flags & SF_NOTURN))
		{
			double anglediff = deltaangle(angle, t.angleFromSource);

			if (anglediff < 0.0)
			{
				if (anglediff < -4.5)
					angle = t.angleFromSource + 90.0 / 21;
				else
					angle -= 4.5;
			}
			else
			{
				if (anglediff > 4.5)
					angle = t.angleFromSource - 90.0 / 21;
				else
					angle += 4.5;
			}
			player.resetDoomYaw = true;
		}
		if (!(flags & SF_NOPULLIN))
			bJustAttacked = true;
	}
}
