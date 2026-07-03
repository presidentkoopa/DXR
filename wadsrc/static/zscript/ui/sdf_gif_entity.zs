class SDFGifEntity : Actor
{
    int frameCount;
    float currentFrame;
    float animSpeed;

    Default
    {
        +NOBLOCKMAP
        +NOGRAVITY
        +DONTSPLASH
        +CLIENTSIDEONLY
        +FORCEXYBILLBOARD
        RenderStyle "Add";
        Alpha 1.0;
        Scale 1.0;
    }

    override void Tick()
    {
        Super.Tick();

        // Animation logic
        currentFrame += animSpeed;
        if (currentFrame >= frameCount) currentFrame = 0;

        // Set sprite to the one bound to our ATLAS shader
        sprite = GetSpriteIndex("SDFG");
        frame = 0;

        // Sync with Renderer:
        // msdf_enabled = Frame Index (Integer part)
        // msdf_glitch  = Tweening / Glitch amount
        // msdf_color   = Tint/Alpha
        
        msdf_enabled = int(currentFrame);
        msdf_glitch = 0.0; // We can add reactive glitching here later
        msdf_color = (1.0, 1.0, 1.0); // msdf_color is FVector3 (RGB); alpha rides on the actor's Alpha
    }
}

class VRGifEventHandler : StaticEventHandler
{
    override void NetworkProcess(ConsoleEvent e)
    {
        if (e.Name == "summon_gif_sentinel")
        {
            PlayerInfo pl = players[e.Player];
            if (!pl || !pl.mo) return;

            // Spawn the sentinel 64 units in front of the player
            Vector3 spawnPos = pl.mo.Pos + (
                cos(pl.mo.Angle) * 64,
                sin(pl.mo.Angle) * 64,
                pl.mo.ViewHeight
            );

            SDFGifEntity sentinel = SDFGifEntity(Actor.Spawn("SDFGifEntity", spawnPos));
            if (sentinel)
            {
                sentinel.frameCount = 16; // Test hardcode
                sentinel.animSpeed = 0.5;
                Console.Printf("SDF Sentinel Summoned.");
            }
        }
    }
}
