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

        Shader.SetUniform1f(null, "u_BlackoutMode", blackout ? 1.0 : 0.0);
        Shader.SetUniform1f(null, "u_RadianceAmbient", ambient);
        Shader.SetUniform1f(null, "u_RadianceContrast", contrast);
        
        // Neon Granular Controls
        Shader.SetUniform1f(null, "u_NeonThickness", CVar.GetCVar("vr_neon_thickness", ply).GetFloat());
        Shader.SetUniform1f(null, "u_NeonThreshold", CVar.GetCVar("vr_neon_threshold", ply).GetFloat());
        Shader.SetUniform1f(null, "u_NeonGlow", CVar.GetCVar("vr_neon_glow", ply).GetFloat());
        Shader.SetUniform1f(null, "u_NeonPulseSpeed", CVar.GetCVar("vr_neon_pulse_speed", ply).GetFloat());
        
        int cA = CVar.GetCVar("vr_neon_color_a", ply).GetInt();
        int cB = CVar.GetCVar("vr_neon_color_b", ply).GetInt();
        
        vector3 colorA = ((cA >> 16) & 255, (cA >> 8) & 255, cA & 255) / 255.0;
        vector3 colorB = ((cB >> 16) & 255, (cB >> 8) & 255, cB & 255) / 255.0;
        
        Shader.SetUniform3f(null, "u_NeonColorA", colorA);
        Shader.SetUniform3f(null, "u_NeonColorB", colorB);
    }
}
