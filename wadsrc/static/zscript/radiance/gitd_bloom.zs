// ============================================================================
// gitd_bloom.zs  --  BloomBoost, reactive + budget-subsidy (2.6x merge)
// ----------------------------------------------------------------------------
// BloomBoost forces GZDoom's bloom (which only catches near-white pixels) to
// trigger on DIM lights via a two-shader sandwich: a pre-pass lifts brightness/
// contrast before the engine bloom, a post-pass inverts it to restore the scene.
//
//   SUBSIDY  -- boost scales inversely with how many texture HERO lights are live
//               (from the shared bank): few lights -> high boost so they sparkle,
//               many -> ease off to avoid white-out.
//   REACTIVE -- brief decaying bloom on damage / low health (gentle, VR-safe).
//
// SCOPE DISCIPLINE: UiTick() runs in UI scope and may ONLY call the clearscope
// Shader.* API + read this handler's own cached fields. It may NOT call play
// functions (cvar helpers, the bank) or read play state. So all the maths runs
// in WorldTick() (play scope) and is snapshotted into plain fields; UiTick only
// pushes those into the shader. (The "GunBonsai pattern" the glow engine uses.)
// ============================================================================

class GITD_BloomHandler : EventHandler
{
    // reactive envelope (play scope)
    double react, reactGoal;
    int    lastHealth;

    // shader snapshot: written in WorldTick (play), read in UiTick (UI)
    bool   sEnabled;
    double sPreGamma, sPreContrast, sPreBright;
    double sPostGamma, sPostContrast, sPostBright;

    static bool   CB(String n, bool d)  { CVar c = CVar.FindCVar(n); return c ? c.GetBool()  : d; }
    static double CF(String n, double d){ CVar c = CVar.FindCVar(n); return c ? c.GetFloat() : d; }
    static int    CI(String n, int d)   { CVar c = CVar.FindCVar(n); return c ? c.GetInt()   : d; }

    override void WorldLoaded(WorldEvent e)
    {
        react = 0; reactGoal = 0; sEnabled = false;
        lastHealth = (players[consoleplayer].mo) ? players[consoleplayer].mo.health : 100;
        // NOTE: gl_bloom is a protected engine cvar (settable only from menu/command line, NOT
        // from script). BloomBoost still RIDES it (WorldTick gate) -- enable engine bloom via the
        // menu ("Engine Bloom (needed)") or +gl_bloom 1 on the launcher. (Forcing it here aborted the VM.)
    }

    override void WorldThingDamaged(WorldEvent e)
    {
        if (!CB("gitd_bloom_reactive", false)) return;
        let pmo = players[consoleplayer].mo;
        if (pmo && e.Thing == pmo) reactGoal = max(reactGoal, 0.8);
    }

    // ALL maths here (play scope), cached for UiTick.
    override void WorldTick()
    {
        bool on = CB("gitd_bloom", true);
        bool bloomOn = (CI("gl_bloom", 0) + (on ? 1 : 0)) > 1;
        if (!bloomOn) { sEnabled = false; return; }

        double gamma      = CF("gitd_bloomboost_gamma", 1.0);
        double contrast   = CF("gitd_bloomboost_contrast", 100.0) * 0.01;
        double brightness = CF("gitd_bloomboost_brightness", 0.0) * 0.01;

        // STRENGTH: an overall multiplier on the whole bloom push (new control,
        // replaces the old hero-light subsidy which this build no longer has).
        double strength = clamp(CF("gitd_bloom_strength", 1.0), 0.0, 3.0);
        brightness *= strength;
        contrast    = 1.0 + (contrast - 1.0) * strength;

        if (CB("gitd_bloom_reactive", false))
        {
            let pmo = players[consoleplayer].mo;
            if (pmo)
            {
                int hp = pmo.health;
                if (hp > 0 && hp < 40) reactGoal = max(reactGoal, (40 - hp) / 40.0 * 0.25);
            }
            react += (reactGoal - react) * 0.35;
            reactGoal *= 0.90;
            double rAmt = CF("gitd_bloom_react_amt", 0.35);
            brightness += react * rAmt;
            contrast   += react * rAmt * 0.4;
        }
        else { react = 0; reactGoal = 0; }

        // Headroom widened on the high end so the additive glow can run HOT toward
        // the footage look (you get closest with the glow maxed). The hard ceiling
        // still exists only to keep pow()/contrast from producing a NaN that paints
        // a solid rectangle -- the shader's own NaN floor is the real guard, so this
        // can sit high without blowing out.
        gamma      = clamp(gamma, 0.45, 2.2);
        contrast   = clamp(contrast, 0.5, 4.0);
        brightness = clamp(brightness, -0.5, 1.2);

        sPreGamma  = 1.0 / gamma;  sPreContrast  = contrast;       sPreBright  = brightness;
        sPostGamma = gamma;        sPostContrast = 1.0 / contrast; sPostBright = brightness;
        sEnabled   = true;
    }

    // UI scope: ONLY Shader.* + cached fields.
    override void UiTick()
    {
        let pp = players[consoleplayer];
        if (!pp) return;
        if (!sEnabled)
        {
            Shader.SetEnabled(pp, "BloomBoostPre",  false);
            Shader.SetEnabled(pp, "BloomBoostPost", false);
            return;
        }
        Shader.SetUniform1f(pp, "BloomBoostPre",  "gamma",      sPreGamma);
        Shader.SetUniform1f(pp, "BloomBoostPre",  "contrast",   sPreContrast);
        Shader.SetUniform1f(pp, "BloomBoostPre",  "brightness", sPreBright);
        Shader.SetEnabled  (pp, "BloomBoostPre",  true);
        Shader.SetUniform1f(pp, "BloomBoostPost", "gamma",      sPostGamma);
        Shader.SetUniform1f(pp, "BloomBoostPost", "contrast",   sPostContrast);
        Shader.SetUniform1f(pp, "BloomBoostPost", "brightness", sPostBright);
        Shader.SetEnabled  (pp, "BloomBoostPost", true);
    }
}
