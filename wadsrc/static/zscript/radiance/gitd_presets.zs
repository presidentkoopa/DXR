// ============================================================================
// GITD PRESETS - one-tap configurations that set DarkDoomZ + GlowInTheDark
// cvars together. Pick a preset in the menu -> it writes the whole batch.
//
// A preset is just "apply N cvar values at once." Driven by a netevent so it
// works in-game (VR, no console). gitd_preset_apply <n>.
//
// Presets:
//   1  = BLACKOUT     -- pure-black DarkDoom; base glow OFF; only COMBAT lights
//                        the void: death FX, enemy-hit glows, reactive killstreak.
//   3  = NEON CHAOS    -- every room its own wild colour, breathing over time.
//   4  = RED ALERT      -- the whole arena throbs alarm-red.
//   5  = COLD FRONT      -- deep-blue floors fading to icy-white ceilings.
//   6  = NEON UNISON      -- one synchronized colour, gently pulsing.
//   21 = ATOMIC PILE       -- sickly green-yellow radioactive glow, slow heavy pulse.
// ============================================================================
//
// ROLE IN GITD: This is the user-facing "front door" to the whole
// GlowInTheDark + DarkDoomZ tuning surface. Instead of expecting the player to
// hand-tune ~25 individual cvars from a console (impossible in VR, where there
// is no keyboard), this handler bundles a curated, internally-consistent set of
// values behind a single menu action. The menu/keybind fires a ConsoleEvent
// ("gitd_preset_apply <n>"); this EventHandler receives it and writes the batch.
// It owns no per-tick state and renders nothing - it is purely a cvar writer.
class GITD_PresetHandler : EventHandler   // EventHandler so it can receive netevents map-wide
{
    // Entry point: runs when a "gitd_preset_apply" ConsoleEvent fires (via the
    // netevent console command / menu). NetworkProcess (not WorldTick) is used
    // so the apply is demo/multiplayer-safe and reaches every node consistently.
    override void NetworkProcess(ConsoleEvent e)
    {
        // Only react to our own event name; ignore every other netevent on the bus.
        if (e.Name == "gitd_preset_apply")
        {
            int which = e.Args[0];          // Arg0 selects which preset
            switch (which)
            {
                case 1:  ApplyBlackout();    break;
                case 3:  ApplyNeonChaos();   break;
                case 4:  ApplyRedAlert();    break;
                case 5:  ApplyColdFront();   break;
                case 6:  ApplyNeonUnison();  break;
                case 21: ApplyAtomicPile();  break;
            }
        }
    }

    // --- CVar write helpers. Every preset writes through these so the class
    // has one place that resolves the cvar and one place a typo would surface. ---
    void SetI(string name, int val)
    {
        CVar cv = CVar.GetCVar(name, players[consoleplayer]);
        if (!cv) cv = CVar.FindCVar(name);
        if (cv) cv.SetInt(val);
    }

    void SetF(string name, double val)
    {
        CVar cv = CVar.GetCVar(name, players[consoleplayer]);
        if (!cv) cv = CVar.FindCVar(name);
        if (cv) cv.SetFloat(val);
    }

    // Applies the BLACKOUT preset: kill all ambient light, leave only combat to
    // illuminate the arena. Writes the full DarkDoom + glow + death-FX batch.
    void ApplyBlackout()
    {
        // --- DARKDOOM: pure black ---
        // Drive DarkDoomZ to its darkest possible state - we want a true void as
        // the canvas, so combat glows read with maximum contrast.
        SetI("ddz_mode",     12);   // DarkDoom Black (subtract 256 = pitch black)
        SetI("ddz_preset",   8);    // max darkening
        SetI("ddz_minlight", 0);    // no light floor   (allow sectors to reach 0 light)
        SetI("ddz_pregain",  0);    // no pre-tonemap brightening
        SetI("ddz_postgain", 0);    // no post-tonemap brightening - keep blacks crushed
        SetI("ddz_fog",      0);    // fog off; fog would lift the blacks and wash out glow

        // --- GITD BASE GLOW: OFF (no ambient floor/ceiling glow) ---
        // The whole point of BLACKOUT is that nothing glows passively - so the
        // standing/ambient GITD glow channel is fully disabled here.
        SetI("hf_glow_enabled",    0);   // master ambient-glow switch off
        SetI("hf_glow_random",     0);   // no randomized glow placement
        SetI("hf_glow_cycle",      0);   // no glow color/intensity cycling
        SetI("hf_glow_mode",       0);   // base glow mode reset to none

        // --- COMBAT LIGHT: the only things that light the void ---
        // enemy-hit / bullet-impact glows ON, painting the floor where shots land
        // This is what makes the arena "painted by violence" - every hit leaves a
        // momentary light, so the player's own fire reveals the space.
        SetI("hf_glow_impact",        1);    // enable impact glows
        SetI("hf_glow_impact_planes", 1);    // glow the FLOOR at impacts
        SetI("hf_glow_impact_radius", 160);  // big, readable in the dark
        SetI("hf_glow_impact_time",   28);   // lingering neon decay  (~0.8s at 35tic, slow fade)
        SetI("hf_glow_impact_shape",  0);    // pulse
        SetI("hf_glow_impact_liquid", 1);    // also splash glow onto liquid surfaces

        // reactive killstreak floor glow ON (floor reacts under you in combat)
        // A pool of light that grows with your streak - rewards aggression by
        // literally lighting more of the floor the better you're doing.
        SetI("hf_glow_killstreak", 1);   // enable streak-reactive floor glow
        SetI("hf_glow_ks_radius",  320); // large footprint so the streak glow is felt around you
        SetI("hf_glow_ks_max",     10);  // cap streak scaling at 10 kills (avoid runaway brightness)

        // --- DEATH FX: ON, big (the void remembers kills) ---
        // Each kill stamps a death effect; with base glow off these become the
        // persistent landmarks in an otherwise black room.
        SetI("gitd_death_enabled", 1);   // enable death-FX system
        SetI("gitd_death_size",    320); // large mark so kills read at distance in the dark
        SetI("gitd_death_walk",    1);   // mark stays tied to the floor / walkable surface
        SetI("gitd_death_memory",  0);   // memory off: marks fade, no permanent battlefield buildup

        // Cyan notice: confirms the apply and flags that DarkDoom's darkest modes
        // typically need a map restart to fully re-light all sectors from scratch.
        Console.Printf("\c[Cyan]GITD: BLACKOUT preset applied. Restart map for full darkness.");
    }

    // Shared baseline for the glow-on presets: master glow on, every surface, no
    // cycling/randomize/gradient (each preset re-enables what it wants), over a dark
    // DarkDoom-Classic canvas so the colours read. Each preset overrides after this.
    void GlowBase()
    {
        SetI("hf_glow_enabled",     1);
        SetI("gitd_surfaces",       7);     // floor + ceiling + walls
        SetI("hf_glow_random",      0);
        SetI("hf_glow_random_mode", 0);
        SetI("hf_glow_random_rate", 0);
        SetI("hf_glow_cycle",       0);
        SetI("hf_glow_gradient",    0);
        SetI("hf_glow_split",       0);
        SetI("hf_glow_mode",        0);     // static unless a preset overrides
        SetF("hf_glow_intensity",   1.0);
        SetI("ddz_mode",           11);     // DarkDoom Classic canvas
        SetI("ddz_minlight",        0);
        SetI("ddz_fog",             0);

        // Reset independent plane parameters
        SetI("gitd_floor_enabled",   1);
        SetI("gitd_ceil_enabled",    1);
        SetI("gitd_wall_enabled",    1);
        SetF("gitd_floor_intensity", 1.0);
        SetF("gitd_ceil_intensity",  1.0);
        SetF("gitd_wall_intensity",  1.0);
        SetF("gitd_floor_height",    64.0);
        SetF("gitd_ceil_height",     64.0);
        SetF("gitd_wall_height",     64.0);
        SetI("gitd_floor_mode",      0);
        SetI("gitd_ceil_mode",       0);
        SetI("gitd_wall_mode",       0);
        SetF("gitd_floor_speed",     1.0);
        SetF("gitd_ceil_speed",      1.0);
        SetF("gitd_wall_speed",      1.0);
    }

    // One unified complementary color pair on planes, gently pulsing.
    void ApplyNeonUnison()
    {
        GlowBase();
        SetI("ddz_preset",          3);

        // Pick a synchronized beautiful starting color
        int pair = random[PresetUnison](0, 2);
        int col = 0x28DCFF; // electric cyan
        if (pair == 1) {
            col = 0xFFFF00; // bright yellow
        } else if (pair == 2) {
            col = 0x39FF14; // neon green
        }

        SetI("gitd_floor_color",    col);
        SetI("gitd_ceil_color",     col);
        SetI("gitd_wall_color",     col);
        SetI("gitd_floor_mode",     5);          // cycle
        SetI("gitd_ceil_mode",      5);
        SetI("gitd_wall_mode",      5);
        SetF("gitd_floor_speed",    0.1);       // very slow relaxing cycling
        SetF("gitd_ceil_speed",     0.1);
        SetF("gitd_wall_speed",     0.1);
        Console.Printf("\c[Cyan]GITD: Neon Unison.");
    }

    // Every room its own wild colour, breathing over time.
    void ApplyNeonChaos()
    {
        GlowBase();
        SetI("ddz_preset",          3);
        SetI("hf_glow_random",      1);
        SetI("hf_glow_random_mode", 0);          // vivid, any hue
        SetI("hf_glow_random_rate", 70);         // re-roll ~2s = shifting chaos
        SetI("hf_glow_mode",        2);          // breathe cycle
        Console.Printf("\c[Cyan]GITD: Neon Chaos.");
    }

    // The whole arena throbs alarm-red.
    void ApplyRedAlert()
    {
        GlowBase();
        SetI("ddz_preset",          4);          // darker, tense
        SetI("gitd_floor_color",    0xFF1818);   // alarm red
        SetI("gitd_ceil_color",     0xFF1818);
        SetI("gitd_wall_color",     0xFF1818);
        SetI("gitd_floor_mode",     2);          // breathe
        SetI("gitd_ceil_mode",      2);
        SetI("gitd_wall_mode",      2);
        SetF("gitd_floor_speed",    0.3);        // slow dramatic breath
        SetF("gitd_ceil_speed",     0.3);
        SetF("gitd_wall_speed",     0.3);
        SetF("gitd_floor_intensity", 1.2);
        SetF("gitd_ceil_intensity",  1.2);
        SetF("gitd_wall_intensity",  1.2);
        Console.Printf("\c[Cyan]GITD: Red Alert.");
    }

    // Deep-blue floors fading up to icy-white ceilings, slow and frosty.
    void ApplyColdFront()
    {
        GlowBase();
        SetI("ddz_preset",          3);
        SetI("gitd_floor_color",    0x1840FF);   // deep blue floor
        SetI("gitd_ceil_color",     0xC8E6FF);   // icy white ceiling
        SetI("gitd_wall_color",     0x1840FF);   // deep blue walls
        SetI("gitd_floor_mode",     2);          // slow breathe
        SetI("gitd_ceil_mode",      2);
        SetI("gitd_wall_mode",      2);
        SetF("gitd_floor_speed",    0.5);
        SetF("gitd_ceil_speed",     0.5);
        SetF("gitd_wall_speed",     0.5);
        Console.Printf("\c[Cyan]GITD: Cold Front.");
    }

    // Atomic Pile: sickly green-yellow radioactive floor & walls, dull olive
    // ceiling, slow heavy pulse like a reactor breathing. First-pass values --
    // retune via the sliders in Floor/Ceiling/Wall Glow or Advanced.
    void ApplyAtomicPile()
    {
        GlowBase();
        SetI("ddz_preset",          4);          // darker canvas, radioactive glow reads hot
        SetI("gitd_floor_color",    0x9ACD00);   // radioactive green-yellow
        SetI("gitd_ceil_color",     0x4B5A00);   // dull olive ceiling
        SetI("gitd_wall_color",     0x9ACD00);   // radioactive green-yellow
        SetI("gitd_floor_mode",     1);          // pulse
        SetI("gitd_ceil_mode",      2);          // breathe
        SetI("gitd_wall_mode",      1);          // pulse
        SetF("gitd_floor_speed",    0.35);       // slow, heavy
        SetF("gitd_ceil_speed",     0.25);
        SetF("gitd_wall_speed",     0.35);
        SetF("gitd_floor_intensity", 1.3);
        SetF("gitd_wall_intensity",  1.3);
        Console.Printf("\c[Green]GITD: Atomic Pile.");
    }
}
