class VRRomLoadHandler : StaticEventHandler
{
    float scanline;
    bool active;
    
    override void WorldLoaded(WorldEvent e)
    {
        // Don't trigger on savegame loads or similar if necessary, 
        // but for now, every map load is fine.
        scanline = -0.1; // Start slightly above screen
        active = true;
        PPShader.SetEnabled("rom_load", true);
        PPShader.SetUniform1f("rom_load", "scanline_pos", scanline);
    }
    
    override void WorldTick()
    {
        if (active)
        {
            int fidelity = CVar.GetCVar("vr_visual_fidelity", players[consoleplayer]).GetInt();
            double speed = 0.012;
            if (fidelity == 0) speed = 0.05; // Quick compile
            else if (fidelity == 3) speed = 0.008; // Long, premium compile
            
            scanline += speed;
            PPShader.SetUniform1f("rom_load", "scanline_pos", scanline);
            
            if (scanline >= 1.2) 
            {
                active = false;
                PPShader.SetEnabled("rom_load", false);
            }
        }
    }
}
