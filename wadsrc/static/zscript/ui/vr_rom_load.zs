class VRRomLoadHandler : StaticEventHandler
{
    float scanline;
    bool active;
    
    override void WorldLoaded(WorldEvent e)
    {
        // DISABLED (blackout fix): this "ROM compiling" sweep is a full-screen postprocess whose
        // scanline is advanced in WorldTick. WorldTick PAUSES while a menu is up (title screen / any
        // menu), so the scanline stays at its -0.1 start -> the whole final image (menu included) is
        // painted as the black-green "void" and the screen goes black while input still works.
        // (Only became live once the gldefs PostProcess block got its Name field, so SetEnabled
        // actually matches now.) Re-enable once reworked to: (a) drive the scanline off REAL time,
        // not world ticks, so it finishes even when paused, and (b) only run on real gameplay maps,
        // never the title map / menus. Left dormant so the screen renders normally.
        scanline = 1.5;
        active = false;
        PPShader.SetEnabled("rom_load", false);
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
