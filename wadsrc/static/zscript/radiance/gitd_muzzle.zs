// ============================================================================
// FILE: gitd_muzzle.zs  --  GITD muzzle-flash light (global toggle)
// ----------------------------------------------------------------------------
// A brief golden-orange dynamic light that flares on the player when they fire,
// then dies in a couple tics. GLOBAL toggle (gitd_muzzle_lights), NOT tied to a
// preset -- though Blackout pairs with it beautifully.
//
// "Player fired" has no clean ZScript event, so we detect it the robust,
// weapon-agnostic way: each tic, check whether the player's READY weapon is in
// an attack/fire animation (PSP_WEAPON layer not in its idle/ready state, with
// the player holding +attack or the weapon refiring). When firing, we SNAP one
// light to the player and refresh its short life; we never stack a second light,
// so even full-auto is a single flickering flare -- Quest-frugal by design.
//
// A_AttachLight / A_RemoveLight are stock engine APIs -- no engine patch needed.
// ============================================================================

// The carrier actor: invisible, rides the firing player, emits the muzzle light.
class GITD_MuzzleLight : Actor
{
    Actor host;          // the player pawn this rides
    Color mcol;
    int   mrad, mlife, mage;
    bool  strobe;        // true while rapid-firing (chaingun): flicker instead of one fade

    Default { +NOINTERACTION; +NOGRAVITY; +NOBLOCKMAP; +DONTSPLASH; RenderStyle "None"; }
    States { Spawn: TNT1 A 1; Loop; }

    // (Re)arm on each SHOT: full brightness immediately, then fall off. mlife in tics.
    void Flash(Color c, int rad) { mcol = c; mrad = rad; mlife = 4; mage = -1; }
    // Mark whether this re-arm is part of a rapid-fire burst (sets the strobe look).
    void SetStrobe(bool s) { strobe = s; }

    override void Tick()
    {
        Super.Tick();
        // Ride the player. They fired a gun -> a light is on them. Simple.
        if (host)
            SetOrigin(host.pos + (0, 0, host.height * 0.6), true);

        mage++;
        if (mage > mlife) { A_RemoveLight("gitd_muzzle"); Destroy(); return; }

        double fade = 1.0 - double(mage) / double(mlife + 1);   // tic0 = full, smooth to 0
        if (fade > 1.0) fade = 1.0;
        if (fade < 0.0) fade = 0.0;

        // STROBE (chaingun): a real on/OFF flicker. Every other tic the light is
        // FULLY ON, the tics between are knocked right down -- so holding the
        // chaingun reads as a rapid muzzle strobe on the walls instead of one fade.
        // We use the global level time so the flicker is steady regardless of when
        // each shot re-armed the light.
        if (strobe)
        {
            bool litTic = (level.maptime & 1) == 0;   // on/off every game tic
            fade = litTic ? 1.0 : 0.15;               // hard bright vs near-dark
        }

        int finalRad = int(double(mrad) * fade);
        if (finalRad < 1) finalRad = 1;
        // flag 8 = LF_ATTENUATE: realistic falloff that LIGHTS the wall texture.
        A_AttachLight("gitd_muzzle", 0, mcol, finalRad, 0, 8);  // point, attenuated
    }
}

// Per-tic driver: detects firing and flashes the muzzle light on each player.
class GITD_MuzzleHandler : EventHandler
{
    // one light per player, refreshed while firing
    Array<GITD_MuzzleLight> mlights;
    // per-player rising-edge tracker: was the muzzle-flash layer active last tic?
    Array<int> wasFlashing;   // 0/1 per player (int array; ZScript has no bool array literal need)

    static int CI(String n, int def) { CVar c = CVar.FindCVar(n); return c ? c.GetInt()  : def; }
    static bool CB(String n, bool def){ CVar c = CVar.FindCVar(n); return c ? c.GetBool() : def; }

    override void WorldLoaded(WorldEvent e) { if (!e.IsSaveGame) mlights.Clear(); }

    // Muzzle colour: custom override, else default golden-orange.
    Color MuzzleColor()
    {
        if (CB("gitd_muzzle_custom", false))
        {
            CVar cc = CVar.FindCVar("gitd_muzzle_color");
            if (cc) { int pk = cc.GetInt(); return Color(255, (pk>>16)&0xFF, (pk>>8)&0xFF, pk&0xFF); }
        }
        return Color(255, 255, 190, 90);   // default golden-orange
    }


    override void WorldTick()
    {
        bool on = CB("gitd_muzzle_lights", false);

        // prune destroyed entries
        for (int i = mlights.Size() - 1; i >= 0; i--)
            if (!mlights[i]) mlights.Delete(i);

        if (!on) { wasFlashing.Clear(); return; }

        int rad = CI("gitd_muzzle_size", 160);
        Color c = MuzzleColor();

        // make sure the per-player flash-edge tracker is sized
        while (wasFlashing.Size() < MAXPLAYERS) wasFlashing.Push(0);

        for (int pn = 0; pn < MAXPLAYERS; pn++)
        {
            if (!playeringame[pn] || !players[pn].mo) continue;

            // Fire ONE light per shot, synced to the gun's actual muzzle-flash
            // frame -- exactly like the monster muzzle flash fires on the firing
            // frame. The player's PSP_FLASH psprite layer is non-null ONLY while
            // the weapon is showing its muzzle flash (A_GunFlash sets it on the
            // shot, clears it otherwise). So "flash layer just became active" = the
            // shot just went off. No early trigger (button-down fires too soon), no
            // strobing within a flash -- one clean pulse per BANG.
            bool newShot = false;
            let p = players[pn];
            int flashing = (p.FindPSprite(PSP_FLASH) != null) ? 1 : 0;
            if (flashing == 1 && wasFlashing[pn] == 0) newShot = true;  // rising edge of the flash frame
            wasFlashing[pn] = flashing;

            // ===== CHAINGUN STROBE -- PLAYER's OWN WEAPONS ONLY, BOTH HANDS =====
            // We look ONLY at the weapon objects the player is holding:
            //   player.ReadyWeapon   (main hand)
            //   player.OffhandWeapon (off hand, VR)
            // An enemy chaingunner is a world Actor and is NEVER the player's
            // ReadyWeapon/OffhandWeapon, so it can't possibly trigger this. The
            // chaingun is matched by class (your VR chaingun inherits from Chaingun,
            // so "is Chaingun" matches it in either hand). "Firing" = the player is
            // actively refiring (player.refire > 0, i.e. holding the trigger on the
            // auto weapon) AND that weapon's flash layer is live this tic. While that
            // holds, we re-arm the muzzle light every tic and the carrier flickers it
            // for the machine-gun strobe. Every other weapon falls through to the
            // clean one-pulse-per-shot path below.
            bool chaingunInHand =
                (p.ReadyWeapon   && (p.ReadyWeapon   is "Chaingun")) ||
                (p.OffhandWeapon && (p.OffhandWeapon is "Chaingun"));

            // Both main-hand AND offhand weapons set their muzzle flash on the SAME
            // PSP_FLASH layer (engine SetSafeFlash always uses PSP_FLASH regardless of
            // hand -- verified in weapons.zs), so this one check covers either hand.
            bool flashLive = (p.FindPSprite(PSP_FLASH) != null);

            bool chaingunFiring = gitd_muzzle_chaingun_strobe && chaingunInHand
                                  && (p.refire > 0 || flashLive);

            bool isChaingun = chaingunFiring;          // strobe look only while chaingun-firing
            bool keepAlive  = newShot || chaingunFiring;

            // find an existing light riding this player
            GITD_MuzzleLight existing = null;
            for (int i = 0; i < mlights.Size(); i++)
                if (mlights[i] && mlights[i].host == p.mo) { existing = mlights[i]; break; }

            if (existing)
            {
                existing.SetStrobe(isChaingun);        // chaingun firing -> flicker
                if (keepAlive) existing.Flash(c, rad); // re-arm while firing / per shot
                continue;                              // otherwise let the pulse fall off
            }

            // no light yet -> spawn when a shot happens (or the chaingun is firing)
            if (!keepAlive) continue;
            let nl = GITD_MuzzleLight(Actor.Spawn("GITD_MuzzleLight", p.mo.pos + (0,0, p.mo.height*0.6)));
            if (nl) { nl.host = p.mo; nl.SetStrobe(isChaingun); nl.Flash(c, rad); mlights.Push(nl); }
        }
    }
}
