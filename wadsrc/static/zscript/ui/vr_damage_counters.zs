class VRDamageCounter : Actor
{
    int damageTotal;
    int lifeTimer;
    Actor owner;

    Default
    {
        +NOBLOCKMAP
        +NOGRAVITY
        +DONTSPLASH
        +NOINTERACTION
        +CLIENTSIDEONLY
        +BILLBOARD
        RenderStyle "Add";
        Alpha 1.0;
        Scale 0.15;
    }

    override void Tick()
    {
        if (!owner || lifeTimer-- <= 0)
        {
            Destroy();
            return;
        }

        // Set sprite to the one bound to our SDF shader
        sprite = GetSpriteIndex("VRDM");
        frame = 0;

        // Pass MSDF uniforms to main.fp via native fields
        msdf_enabled = damageTotal;
        msdf_glitch = (lifeTimer < 20) ? 0.05 : 0.0;
        
        // Color mapping: Cyan (low) -> Orange (mid) -> Red (high/crit)
        vector3 clr = (0.0, 1.0, 1.0); // Cyan
        if (damageTotal > 200) clr = (1.0, 0.0, 0.0); // Red
        else if (damageTotal > 50) clr = (1.0, 0.5, 0.0); // Orange
        
        msdf_color = clr;

        // We will eventually read these from the FVRMSDFManager in C++, 
        // but for now we set the base values for the renderer.
        
        // Float upwards and follow owner
        SetOrigin(owner.Pos + (0, 0, owner.Height + 12 + (60 - lifeTimer) * 0.4), true);
        
        // Fade out
        if (lifeTimer < 20)
        {
            Alpha = lifeTimer / 20.0;
            Scale *= 0.98;
        }
    }
}

class VRDamageHandler : StaticEventHandler
{
    Array<VRDamageCounter> counters;

    override void WorldThingDamaged(WorldEvent e)
    {
        if (!e.Thing || e.Damage <= 0) return;
        
        // Only show for monsters or players
        if (!(e.Thing.bIsMonster || e.Thing.player)) return;

        VRDamageCounter counter = null;
        
        // Look for existing counter on this target
        for (int i = 0; i < counters.Size(); i++)
        {
            if (counters[i] && counters[i].owner == e.Thing)
            {
                counter = counters[i];
                break;
            }
        }

        if (counter)
        {
            counter.damageTotal += e.Damage;
            counter.lifeTimer = 60; // Reset timer (approx 1.7s at 35fps)
            counter.Scale = 0.2; // Pop scale
        }
        else
        {
            counter = VRDamageCounter(Actor.Spawn("VRDamageCounter", e.Thing.Pos + (0, 0, e.Thing.Height + 8)));
            if (counter)
            {
                counter.owner = e.Thing;
                counter.damageTotal = e.Damage;
                counter.lifeTimer = 60;
                counters.Push(counter);
            }
        }
    }
    
    override void WorldTick()
    {
        // Cleanup nulls from the array
        for (int i = counters.Size() - 1; i >= 0; i--)
        {
            if (counters[i] == null || counters[i].bDestroyed)
            {
                counters.Delete(i);
            }
        }
    }
}
