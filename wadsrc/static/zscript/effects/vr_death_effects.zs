class FatalErrorActor : Actor
{
    int lifeTimer;
    
    Default
    {
        +NOBLOCKMAP
        +NOGRAVITY
        +DONTSPLASH
        +NOINTERACTION
        +CLIENTSIDEONLY
        RenderStyle "Add";
        Alpha 1.0;
        Scale 2.0;
    }

    override void Tick()
    {
        if (lifeTimer++ > 150) // Stay for ~4 seconds
        {
            Destroy();
            return;
        }

        // Use the SDF digit sprite but repurposed
        sprite = GetSpriteIndex("VRDM");
        frame = 0;

        // u_IsMSDF repurposed as a "State/Seed" for the shader logic
        // We'll make it flicker between different "error states"
        msdf_enabled = 1; 
        msdf_glitch = 0.8;
        msdf_color = (1.0, 0.1, 0.1); // Bright red

        // Position it in front of the player
        if (players[consoleplayer].mo)
        {
            Actor pmo = players[consoleplayer].mo;
            Vector3 front = (cos(pmo.angle), sin(pmo.angle), 0) * 128;
            SetOrigin(pmo.Pos + (0, 0, players[consoleplayer].viewheight) + front, true);
            Angle = pmo.angle + 180; // Face player
        }
    }
}

class VRDeathHandler : StaticEventHandler
{
    bool deathSequenceActive;
    int deathTimer;

    override void WorldThingDied(WorldEvent e)
    {
        if (e.Thing && e.Thing.player)
        {
            TriggerDeathSequence(e.Thing.player);
        }
    }

    void TriggerDeathSequence(PlayerInfo pl)
    {
        if (deathSequenceActive) return;

        deathSequenceActive = true;
        deathTimer = 0;

        // Freeze world (using a trick or just setting speed to 0 if possible)
        // For now, we just trigger the visuals
        PPShader.SetEnabled("fatal_exception", true);
        PPShader.SetUniform1f("fatal_exception", "u_FatalStrength", 1.0);
        
        Actor.Spawn("FatalErrorActor", pl.mo.Pos);
        pl.mo.A_StartSound("system/crash", CHAN_AUTO, CHANF_UI);
    }

    override void WorldTick()
    {
        if (deathSequenceActive)
        {
            deathTimer++;

            // Pulse the glitch strength
            float strength = 0.5 + 0.5 * sin(deathTimer * 0.5);
            PPShader.SetUniform1f("fatal_exception", "u_FatalStrength", strength);

            if (deathTimer > 175)
            {
                deathSequenceActive = false;
                PPShader.SetEnabled("fatal_exception", false);
            }
        }
    }

    // FIX: if a new map loads while the sequence is still running (console "map" command, restart,
    // IDCLIP-through, a scripted level change, etc.) before the 5s timeout, nothing previously reset
    // deathSequenceActive or turned the shader back off -- the glitch would stay stuck on forever
    // AND the "if (deathSequenceActive) return;" guard in TriggerDeathSequence would permanently
    // block the effect from ever firing again for the rest of the session. Force-reset on every
    // level transition so a death sequence can never outlive its own map.
    override void WorldUnloaded(WorldEvent e)
    {
        if (deathSequenceActive)
        {
            deathSequenceActive = false;
            deathTimer = 0;
            PPShader.SetEnabled("fatal_exception", false);
        }
    }
}
