class VRBlackoutHandler : StaticEventHandler
{
    override void WorldTick()
    {
        PlayerInfo ply = players[consoleplayer];
        
        // Blackout & Presets
        bool blackout = CVar.GetCVar("vr_blackout_mode", ply).GetBool();
        int preset = CVar.GetCVar("vr_radiance_preset", ply).GetInt();
        
        float ambient = CVar.GetCVar("vr_radiance_ambient", ply).GetFloat();
        float contrast = CVar.GetCVar("vr_radiance_contrast", ply).GetFloat();
        
        // Preset Overrides
        if (preset == 1) { // DarkDoom
            ambient *= 0.3;
            contrast *= 1.5;
        } else if (preset == 2) { // BLACKOUT
            blackout = true;
            ambient = 0.05;
            contrast = 2.0;
        } else if (preset == 3) { // Arcade Neon
            ambient *= 0.6;
            contrast *= 1.2;
        }

        // DISABLED (build-blocker): these Shader.SetUniform1f/3f(null, uniform, value) calls used a
        // 3-arg form that does not exist -- the only valid form is 4-arg (player, shaderName, uniform,
        // value). They also targeted monster_neon.fp, a HardwareShader *Sprite* material shader that the
        // post-process uniform API cannot drive. So this neon/blackout effect never actually ran. Body
        // neutered to unblock compilation; proper material-shader uniform plumbing is a follow-up.
    }
}
