// ============================================================================
// gitd_flatglow.zs -- floor + ceiling glow that washes IN FROM THE WALLS.
// ----------------------------------------------------------------------------
// The native wall glow climbs up from where the wall meets the FLOOR and down
// from where it meets the CEILING. This does the mirror: it spreads that same
// glow OUT ACROSS the floor and ceiling, starting at every wall edge and fading
// inward -- visually the same wash, and each step / sector reacts from its own
// walls in its own colour.
//
// Engine glow-spot channel (Level.AddGlowSpotWiped), ZERO dynamic lights. A
// glow-spot is dropped at every wall's midpoint near you; the engine keeps the
// 16 nearest the camera, so the surfaces around you light up live.
//
// (Positions cached as int X/Y arrays -- ZScript forbids Array<struct>.)
// ============================================================================
class GITD_FlatGlow : EventHandler
{
    Array<int> mX, mY;   // wall (linedef) midpoint
    Array<int> sIdx;     // the sector that owns this wall (for its glow colour)
    bool ready;

    static int    CI(String n, int d)   { CVar c = CVar.FindCVar(n); return c ? c.GetInt()   : d; }
    static double CF(String n, double d){ CVar c = CVar.FindCVar(n); return c ? c.GetFloat() : d; }
    static bool   CB(String n, bool d)  { CVar c = CVar.FindCVar(n); return c ? c.GetBool()  : d; }

    Color ColorCvar(String n, Color def)
    {
        CVar cv = CVar.FindCVar(n);
        if (!cv) return def;
        int pk = cv.GetInt();
        return Color(255, (pk >> 16) & 0xFF, (pk >> 8) & 0xFF, pk & 0xFF);
    }

    // Scale a glow color's RGB by a factor (the Floor/Ceiling Brightness slider,
    // 0..1.5), clamped to byte range. Alpha stays 255; factor 0 = black = no
    // additive wash contribution -> "walls only".
    static Color ScaleColor(Color c, double f)
    {
        int r = int(clamp(c.r * f, 0, 255));
        int g = int(clamp(c.g * f, 0, 255));
        int b = int(clamp(c.b * f, 0, 255));
        return Color(255, r, g, b);
    }

    // Cache every sector's wall midpoints WITH that sector's index (so a wall
    // shared by two sectors lights each side in its own sector's colour).
    override void WorldLoaded(WorldEvent e)
    {
        ready = false;
        mX.Clear(); mY.Clear(); sIdx.Clear();
        for (int i = 0; i < level.Sectors.Size(); i++)
        {
            Sector s = level.Sectors[i];
            if (!s) continue;
            for (int j = 0; j < s.lines.Size(); j++)
            {
                Line l = s.lines[j];
                if (!l) continue;
                Vector2 mid = (l.v1.p + l.v2.p) * 0.5;
                mX.Push(int(mid.x)); mY.Push(int(mid.y)); sIdx.Push(i);
            }
        }
        ready = true;
    }

    // Glow-spots are transient -> re-paint the wall edges near you EVERY tic.
    override void WorldTick()
    {
        if (!ready) return;
        if (!CB("gitd_flatglow", true))   return;
        if (!CB("hf_glow_enabled", true)) return;

        let pi = players[consoleplayer];
        if (!pi || !pi.mo) return;
        double px = pi.mo.pos.x, py = pi.mo.pos.y;

        double cull   = CF("gitd_flatglow_cull", 700.0);
        double cull2  = cull * cull;
        double radius = CF("gitd_flatglow_radius", 128.0);   // how far the glow reaches in from the wall
        int    surf   = CI("gitd_surfaces", 7);
        if ((surf & 3) == 0) return;   // neither floor nor ceiling selected

        // Floor/Ceiling Brightness slider: a multiplier on this inward surface
        // wash, separate from the wall gradient (gitd_glow.zs SetGlowColor). At 0
        // the wash is off -> "walls only"; turn it down if the floors blow out.
        double surfGlow = CF("gitd_surface_glow", 1.0);
        if (surfGlow <= 0.0) return;

        bool   randomize = CB("hf_glow_random", false);
        bool   gradient  = CB("hf_glow_gradient", false);
        bool   liquidPri = CB("hf_glow_liquid_priority", true);
        double inten     = CF("hf_glow_intensity", 1.0);
        int    rerollR   = CI("hf_glow_random_rate", 0);
        int    epoch     = (rerollR > 0) ? int(level.maptime / rerollR) : 0;

        Color fixFloor = ColorCvar("hf_glow_color_floor", Color(255, 60, 180, 255));
        Color fixCeil  = gradient ? ColorCvar("hf_glow_color_ceil", Color(255, 255, 80, 40)) : fixFloor;

        // Drop a spot at every wall within reach; the engine keeps the 16 nearest
        // the camera. (Cap submissions for perf on dense maps.)
        int submitted = 0;
        for (int i = 0; i < mX.Size() && submitted < 96; i++)
        {
            double dx = mX[i] - px, dy = mY[i] - py;
            if (dx*dx + dy*dy > cull2) continue;
            int si = sIdx[i];
            Sector s = level.Sectors[si];
            if (!s) continue;

            Color uf = fixFloor, uc = fixCeil;
            bool isLiq = false;
            if (liquidPri)
            {
                bool liq; Color lc;
                [liq, lc] = HF_GlowHandler.HF_LiquidColorOf(s);
                if (liq) { isLiq = true; uf = lc; }
            }
            if (randomize)
            {
                if (!isLiq) uf = HF_GlowHandler.HF_RandSectorColor(si, 0, epoch, inten);
                uc = HF_GlowHandler.HF_RandSectorColor(si, 1, epoch, inten);
            }

            // Scale each surface wash by the Floor/Ceiling Brightness slider so
            // the floors/ceilings can be dimmed (or pushed up to 1.5x) without
            // touching the wall gradient.
            Color sf = ScaleColor(uf, surfGlow);
            Color sc = ScaleColor(uc, surfGlow);
            if ((surf & 1) != 0) { level.AddGlowSpotWiped(sf, radius, mX[i], mY[i], 0, 0.0, 1.0, 0.0, 1); submitted++; }
            if ((surf & 2) != 0) { level.AddGlowSpotWiped(sc, radius, mX[i], mY[i], 0, 0.0, 1.0, 0.0, 2); submitted++; }
        }
    }
}
