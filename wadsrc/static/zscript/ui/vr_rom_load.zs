class VRRomLoadHandler : StaticEventHandler
{
    bool   active;
    double startMS;   // MSTimeF() at sweep start -- real wall-clock, keeps advancing through pause/menus

    // Same visual range/pacing as the original tick-based version (scanline -0.1 -> 1.2, matching
    // rom_load.fp's uv.y compare), just driven by elapsed wall-clock seconds instead of world tics,
    // converted from the original "units per tic" speeds at 35 tics/sec: 1.3 / speed / 35.
    const SCAN_START    = -0.1;
    const SCAN_END      = 1.2;
    const DUR_DEFAULT   = 3.095;   // was speed 0.012/tic
    const DUR_QUICK     = 0.743;   // fidelity 0, was speed 0.05/tic
    const DUR_PREMIUM   = 4.643;   // fidelity 3, was speed 0.008/tic

    override void WorldLoaded(WorldEvent e)
    {
        active = false;
        PPShader.SetEnabled("rom_load", false);

        // FIX (was permanently disabled -- see history): only play on real gameplay maps, never the
        // title screen / demo loop / intermission / finale / startup console (gamestate != GS_LEVEL
        // covers all of those) -- a title-map sweep was the other half of the original blackout bug.
        if (gamestate != GS_LEVEL) return;

        active = true;
        startMS = MSTimeF();
    }

    override void UiTick()
    {
        if (!active) return;

        // FIX: real wall-clock elapsed time, NOT WorldTick -- WorldTick pauses while any menu (or
        // the title screen) is up, which used to leave the scanline stuck at its start value forever,
        // painting the whole screen (menu included) as the black-green "void". MSTimeF() (clearscope,
        // real time) keeps advancing regardless of pause state, so the sweep always finishes.
        double elapsedSec = (MSTimeF() - startMS) / 1000.0;

        int fidelity = CVar.GetCVar("vr_visual_fidelity", players[consoleplayer]).GetInt();
        double duration = DUR_DEFAULT;
        if (fidelity == 0) duration = DUR_QUICK;
        else if (fidelity == 3) duration = DUR_PREMIUM;

        double f = clamp(elapsedSec / duration, 0.0, 1.0);
        double scanline = SCAN_START + (SCAN_END - SCAN_START) * f;
        PPShader.SetUniform1f("rom_load", "scanline_pos", scanline);
        PPShader.SetEnabled("rom_load", true);

        if (f >= 1.0)
        {
            active = false;
            PPShader.SetEnabled("rom_load", false);
        }
    }
}
