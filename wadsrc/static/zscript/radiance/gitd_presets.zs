// ============================================================================
// GITD PRESETS - one-tap configurations that set DarkDoomZ + GlowInTheDark
// cvars together. Pick a preset in the menu -> it writes the whole batch.
//
// A preset is just "apply N cvar values at once." Driven by a netevent so it
// works in-game (VR, no console). gitd_preset_apply <n>.
//
// Presets:
//   1 = BLACKOUT  -- pure-black DarkDoom; base glow OFF; only COMBAT lights the
//                    void: death FX, enemy-hit glows, reactive killstreak floor.
//                    The signature look - an arena that's painted by violence.
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
                case 2:  ApplyAurora();      break; // Added
                case 3:  ApplyNeonChaos();   break; // Added
                case 4:  ApplyRedAlert();    break;
                case 5:  ApplyColdFront();   break;
                case 6:  ApplyNeonUnison();  break;
                case 7:  ApplyInferno();     break; // Added
                case 8:  ApplyVaporwave();   break; // Added
                case 9:  ApplySolarFlare();  break; // Added (Meltdown)
                case 10: ApplyGhost();       break; // Added
                case 11: ApplySynthwaveDusk(); break;
                case 12: ApplyCyberpunkRain(); break;
                case 13: ApplySystemShock();  break; // NEW
                case 14: ApplyTron();         break; // NEW
                case 15: ApplyVaporwaveChill(); break;
                case 16: ApplyOverdriveRainbow(); break;
                case 17: ApplyMeltdown();     break; // NEW (Chroma Overdrive based)
                case 18: ApplyNebulaDream();  break;
                case 19: ApplyChromaOverdrive(); break;
                case 20: ApplyGridSweep();    break;
            }
        }
    }

    // ... (SetI, SetF, ApplyBlackout, GlowBase, ApplyNeonUnison, ApplyNeonChaos, ApplyRedAlert, ApplyColdFront, ApplyVaporwave, ApplyAurora, ApplyInferno, ApplyGhost, ApplySynthwaveDusk, ApplyCyberpunkRain, ApplyVaporwaveChill, ApplyOverdriveRainbow, ApplySolarFlare, ApplyNebulaDream, ApplyChromaOverdrive, ApplyGridSweep already there)

    void ApplyMeltdown()
    {
        ApplyChromaOverdrive();
        SetF("vr_neon_glow", 8.0);
        SetF("vr_neon_pulse_speed", 5.0);
        SetI("vr_blackout_mode", 1);
        Console.Printf("\c[Orange]GITD: MELTDOWN.");
    }

    void ApplySystemShock()
    {
        ApplyBlackout();
        SetI("vr_blackout_mode", 1);
        SetI("vr_neon_color_a", 0x00FF00); // Matrix Green
        SetI("vr_neon_color_b", 0x008000);
        SetF("vr_neon_thickness", 1.5);
        SetI("gitd_wall_pattern", 2);      // Light Grid
        SetI("gitd_floor_mode", 0);        // Static
        SetI("gitd_floor_enabled", 1);
        SetI("gitd_floor_color", 0x002000);
        Console.Printf("\c[Green]GITD: SYSTEM SHOCK.");
    }

    void ApplyTron()
    {
        ApplyBlackout();
        SetI("vr_blackout_mode", 1);
        SetI("vr_neon_color_a", 0x00FFFF); // Tron Cyan
        SetI("vr_neon_color_b", 0xFF8000); // Tron Orange
        SetF("vr_neon_thickness", 1.2);
        SetI("gitd_wall_pattern", 2);      // Light Grid
        SetI("gitd_floor_mode", 0);
        SetI("gitd_floor_enabled", 1);
        SetI("gitd_floor_color", 0x001020);
        SetI("gitd_ceil_enabled", 1);
        SetI("gitd_ceil_color", 0x001020);
        Console.Printf("\c[Cyan]GITD: TRON.");
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
        SetI("gitd_gridsweep",       0);
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

    // Magenta floor, cyan ceiling, dreamy breathing gradient.
    void ApplyVaporwave()
    {
        GlowBase();
        SetI("ddz_preset",          3);
        SetI("gitd_floor_color",    0xFF2DC6);   // magenta floor
        SetI("gitd_ceil_color",     0x29E6FF);   // cyan ceiling
        SetI("gitd_wall_color",     0xFF2DC6);   // magenta walls
        SetI("gitd_floor_mode",     2);          // breathe
        SetI("gitd_ceil_mode",      2);
        SetI("gitd_wall_mode",      2);
        SetF("gitd_floor_speed",    0.6);
        SetF("gitd_ceil_speed",     0.6);
        SetF("gitd_wall_speed",     0.6);
        Console.Printf("\c[Cyan]GITD: Vaporwave.");
    }


    // Hues drift smoothly room to room like northern lights.
    void ApplyAurora()
    {
        GlowBase();
        SetI("ddz_preset",           2);         // dim, soft
        SetI("hf_glow_random",       1);
        SetI("hf_glow_random_mode",  2);         // hue drift (cohesive)
        SetF("hf_glow_random_drift", 18.0);
        SetI("hf_glow_mode",         2);         // breathe
        Console.Printf("\c[Cyan]GITD: Aurora.");
    }

    // Fast, churning hue-drift -- dark and intense.
    void ApplyInferno()
    {
        GlowBase();
        SetI("ddz_preset",           4);          // darker, high contrast
        SetI("hf_glow_random",       1);
        SetI("hf_glow_random_mode",  2);          // hue drift (cohesive room-to-room sweep)
        SetF("hf_glow_random_drift", 30.0);       // fast churn between rooms
        SetI("hf_glow_mode",         1);          // pulse / flicker
        SetF("hf_glow_intensity",    1.2);
        Console.Printf("\c[Cyan]GITD: Inferno.");
    }

    // Slow, faint hue-drift in near-total black. Eerie and minimal.
    void ApplyGhost()
    {
        GlowBase();
        SetI("ddz_preset",           6);          // murky, near-black
        SetI("hf_glow_random",       1);
        SetI("hf_glow_random_mode",  2);          // hue drift (cohesive room-to-room sweep)
        SetF("hf_glow_random_drift", 6.0);        // slow, barely-there shift
        SetI("hf_glow_mode",         2);          // slow breathe
        SetF("hf_glow_intensity",    0.6);        // faint
        Console.Printf("\c[Cyan]GITD: Ghost.");
    }

    // Synthwave Dusk: Hot orange ceiling, deep violet floor, neon magenta walls.
    void ApplySynthwaveDusk()
    {
        GlowBase();
        SetI("ddz_preset",           3);          // dark canvas
        SetI("gitd_floor_color",      0x6A0DAD);   // violet
        SetI("gitd_ceil_color",       0xFF5A14);   // hot orange
        SetI("gitd_wall_color",       0xFF007F);   // neon magenta
        SetI("gitd_floor_mode",      2);          // breathe
        SetI("gitd_ceil_mode",       2);          // breathe
        SetI("gitd_wall_mode",       1);          // pulse
        SetF("gitd_floor_speed",     0.5);
        SetF("gitd_ceil_speed",      0.5);
        SetF("gitd_wall_speed",      1.2);
        
        // BloomBoost settings
        SetI("gitd_bloom",           1);
        SetF("gitd_bloom_strength",  1.0);
        SetF("gitd_bloomboost_gamma", 1.0);
        SetF("gitd_bloomboost_contrast", 140.0);
        SetF("gitd_bloomboost_brightness", 15.0);
        
        Console.Printf("\c[Pink]GITD: Synthwave Dusk.");
    }


    // Cyberpunk Rain: Neon magenta floor, electric cyan ceiling, yellow walls, rapid breathe.
    void ApplyCyberpunkRain()
    {
        GlowBase();
        SetI("ddz_preset",           3);
        SetI("gitd_floor_color",      0xFF007F);   // neon magenta
        SetI("gitd_ceil_color",       0x00F0FF);   // electric cyan
        SetI("gitd_wall_color",       0xFFFF00);   // yellow
        SetI("gitd_floor_mode",      2);          // breathe
        SetI("gitd_ceil_mode",       2);          // breathe
        SetI("gitd_wall_mode",       1);          // pulse
        SetF("gitd_floor_speed",     2.5);        // rapid
        SetF("gitd_ceil_speed",      2.5);
        SetF("gitd_wall_speed",      3.0);
        
        // BloomBoost settings
        SetI("gitd_bloom",           1);
        SetF("gitd_bloom_strength",  1.2);
        SetF("gitd_bloomboost_gamma", 1.0);
        SetF("gitd_bloomboost_contrast", 150.0);
        SetF("gitd_bloomboost_brightness", 20.0);
        
        Console.Printf("\c[Pink]GITD: Cyberpunk Rain.");
    }

    // Vaporwave Chill: Dreamy lavender floor, peach ceiling, hot-pink walls, slow relaxing breath.
    void ApplyVaporwaveChill()
    {
        GlowBase();
        SetI("ddz_preset",           3);
        SetI("gitd_floor_color",      0x9370DB);   // lavender
        SetI("gitd_ceil_color",       0xFFB07C);   // peach
        SetI("gitd_wall_color",       0xFF69B4);   // hot-pink
        SetI("gitd_floor_mode",      2);          // breathe
        SetI("gitd_ceil_mode",       2);          // breathe
        SetI("gitd_wall_mode",       2);          // breathe
        SetF("gitd_floor_speed",     0.2);        // very slow chill
        SetF("gitd_ceil_speed",      0.2);
        SetF("gitd_wall_speed",      0.15);
        
        // BloomBoost settings
        SetI("gitd_bloom",           1);
        SetF("gitd_bloom_strength",  0.8);
        SetF("gitd_bloomboost_gamma", 1.1);
        SetF("gitd_bloomboost_contrast", 120.0);
        SetF("gitd_bloomboost_brightness", 10.0);
        
        Console.Printf("\c[Cyan]GITD: Vaporwave Chill.");
    }

    // Overdrive Rainbow: Shifting rainbow cycles on all three planes chasing each other.
    void ApplyOverdriveRainbow()
    {
        GlowBase();
        SetI("ddz_preset",           4);          // dark high contrast
        SetI("gitd_floor_mode",      4);          // rainbow cycle
        SetI("gitd_ceil_mode",       4);          // rainbow cycle
        SetI("gitd_wall_mode",       4);          // rainbow cycle
        SetF("gitd_floor_speed",     1.5);        // offset speeds
        SetF("gitd_ceil_speed",      1.2);
        SetF("gitd_wall_speed",      1.8);
        
        // BloomBoost settings
        SetI("gitd_bloom",           1);
        SetF("gitd_bloom_strength",  1.6);
        SetF("gitd_bloomboost_gamma", 0.95);
        SetF("gitd_bloomboost_contrast", 160.0);
        SetF("gitd_bloomboost_brightness", 22.0);
        
        Console.Printf("\c[Orange]GITD: Overdrive Rainbow.");
    }

    // Solar Flare: Molten crimson floor, roaring gold ceiling, and pulsing solar orange walls.
    void ApplySolarFlare()
    {
        GlowBase();
        SetI("ddz_preset",           4);          // high-contrast dark canvas
        SetI("gitd_floor_color",      0x500000);   // molten crimson/maroon
        SetI("gitd_ceil_color",       0xFFD700);   // roaring gold/yellow
        SetI("gitd_wall_color",       0xFF4500);   // solar orange
        SetI("gitd_floor_mode",      1);          // pulse (molten bubbling)
        SetI("gitd_ceil_mode",       2);          // breathe (slow solar hum)
        SetI("gitd_wall_mode",       1);          // pulse
        SetF("gitd_floor_speed",     0.4);        // sluggish molten flow
        SetF("gitd_ceil_speed",      0.3);        // massive scale
        SetF("gitd_wall_speed",      1.5);        // active heat
        
        // BloomBoost settings (Solar flare is super bright)
        SetI("gitd_bloom",           1);
        SetF("gitd_bloom_strength",  1.8);
        SetF("gitd_bloomboost_gamma", 0.85);
        SetF("gitd_bloomboost_contrast", 175.0);
        SetF("gitd_bloomboost_brightness", 25.0);
        
        Console.Printf("\c[Orange]GITD: Solar Flare.");
    }

    // Nebula Dream: Deep stardust pink ceiling, cosmic indigo walls, and deep teal floor.
    void ApplyNebulaDream()
    {
        GlowBase();
        SetI("ddz_preset",           3);          // soft dark canvas
        SetI("gitd_floor_color",      0x008080);   // deep teal floor
        SetI("gitd_ceil_color",       0xFF69B4);   // stardust pink ceiling
        SetI("gitd_wall_color",       0x4B0082);   // indigo walls
        SetI("gitd_floor_mode",      2);          // breathe
        SetI("gitd_ceil_mode",       2);          // breathe
        SetI("gitd_wall_mode",       2);          // breathe
        SetF("gitd_floor_speed",     0.25);       // slow stardust float
        SetF("gitd_ceil_speed",      0.2);
        SetF("gitd_wall_speed",      0.15);
        
        // BloomBoost settings
        SetI("gitd_bloom",           1);
        SetF("gitd_bloom_strength",  1.1);
        SetF("gitd_bloomboost_gamma", 1.05);
        SetF("gitd_bloomboost_contrast", 135.0);
        SetF("gitd_bloomboost_brightness", 12.0);
        
        Console.Printf("\c[Pink]GITD: Nebula Dream.");
    }

    // Chroma Overdrive: Blazing magenta ceiling, hot purple floor, and screaming neon-lime walls.
    void ApplyChromaOverdrive()
    {
        GlowBase();
        SetI("ddz_preset",           4);          // dark canvas
        SetI("gitd_floor_color",      0x9400D3);   // hot purple floor
        SetI("gitd_ceil_color",       0xFF00FF);   // blazing magenta ceiling
        SetI("gitd_wall_color",       0x00FF00);   // neon-lime walls
        SetI("gitd_floor_mode",      1);          // pulse
        SetI("gitd_ceil_mode",       2);          // breathe
        SetI("gitd_wall_mode",       1);          // pulse
        SetF("gitd_floor_speed",     2.2);        // high-frequency throb
        SetF("gitd_ceil_speed",      2.0);
        SetF("gitd_wall_speed",      2.5);
        
        // BloomBoost settings (Heavy, blinding over-saturated contrast)
        SetI("gitd_bloom",           1);
        SetF("gitd_bloom_strength",  2.0);
        SetF("gitd_bloomboost_gamma", 0.75);
        SetF("gitd_bloomboost_contrast", 195.0);
        SetF("gitd_bloomboost_brightness", 32.0);
        
        Console.Printf("\c[Green]GITD: Chroma Overdrive.");
    }


}
