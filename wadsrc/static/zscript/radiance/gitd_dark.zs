// ============================================================================
// FILE: gitd_dark.zs  -  GITD (Glow In The Dark) darkening + flashlight layer
// ----------------------------------------------------------------------------
// ROLE IN GITD:
//   GITD is built on the idea that the world is genuinely dark, so that GLOW
//   (surface-gradient self-illumination) and glow-spots actually read against a
//   black backdrop. This file supplies the TWO pieces that make that possible:
//
//     1) DarkDoomZ_Handler  - a baked copy of the DarkDoomZ darkening framework
//        (originally by Caligari87 / FishyClockwork). It walks every sector at
//        load time, remembers the original light levels, then re-darkens them
//        through one of several curves (linear / multiplicative / clamp /
//        gamma) driven by CVARs. This is what makes "uniform dark = glow
//        everywhere" possible (see ddz_lighting note below).
//
//     2) GITD_Flashlight    - a LAGLESS player flashlight implemented purely in
//        ZScript. It traces the aim and SNAPS a hidden light actor to the hit
//        point every tic, so there is no follow-lag and (crucially) no terrain
//        splash, unlike the old TDDR hitscan-puff trick.
//
// IMPORTANT (DarkDoomedZ / ddz_lighting): when ddz_lighting is FALSE we destroy
// the engine's "Lighting" thinkers so vanilla light effects can't re-brighten
// rooms away from spawn. ddz_lighting 0 = uniform dark = glow visible in every
// room (the start-room-only washout is exactly the ddz_lighting=true symptom).
// ============================================================================

// ============================================================================
// GITD DarkDoomZ (baked) - real darkening by Caligari87 / FishyClockwork
// framework. Its OWN flashlight is REMOVED here; we use GITD_Flashlight instead
// (lagless ZScript trace+snap, below). Multi-mode sector darkening + fog.
// ============================================================================
// Event handler that re-lights every sector in the map according to the ddz_*
// CVARs, re-running whenever any of those CVARs change.
class DarkDoomZ_Handler : EventHandler {
    Array<int> BaseLightLevels;                                          // original per-sector light levels, captured at load (our "source of truth")
    int Mode, Preset, PreGain, PostGain, FogDensity, MinLight;          // current darkening parameters, mirrored from the ddz_* CVARs
    int OldMode, OldPreset, OldPreGain, OldPostGain, OldFogDensity, OldMinLight; // previous-frame copies, used to detect CVAR changes (avoid re-lighting every tic)
    double SkyMode, OldSkyMode;                                          // sky darkening multiplier + its previous value (sky sectors handled separately)
    int BaseAdjustment, FinalAdjustment;                                // working darkening amounts (base = before sky scaling, final = after)
    bool IsSky;                                                          // scratch flag: is the sector currently being processed a sky sector?

    int GetDdzInt(string name) {
        let cv = CVar.GetCVar(name, players[consoleplayer]);
        return cv ? cv.GetInt() : 0;
    }
    double GetDdzFloat(string name) {
        let cv = CVar.GetCVar(name, players[consoleplayer]);
        return cv ? cv.GetFloat() : 0.0;
    }
    bool GetDdzBool(string name) {
        let cv = CVar.GetCVar(name, players[consoleplayer]);
        return cv ? cv.GetBool() : false;
    }

    // Captures pristine sector light levels on map load, optionally kills the
    // engine's Lighting thinkers, then applies the initial darkening pass.
    override void WorldLoaded(WorldEvent e) {
        if(!GetDdzBool("ddz_lighting")) {                                             // ddz_lighting off => we want uniform dark, so remove dynamic light thinkers...
            ThinkerIterator it = ThinkerIterator.Create("Lighting");
            Lighting effect;
            while (effect = Lighting(it.Next())) { effect.Destroy(); }  // ...that would otherwise re-brighten rooms and wash out the glow
        }
        BaseLightLevels.Clear();                                        // start fresh (handler may persist across levels)
        for(int i = 0; i < Level.Sectors.Size(); i++)
            BaseLightlevels.Push(Level.Sectors[i].LightLevel);         // snapshot every sector's ORIGINAL brightness before we darken anything
        ChangeLighting();                                              // apply darkening immediately on load
    }

    // NOTE: original PlayerSpawned gave DarkDoomZ's flashlight here - REMOVED.
    // GITD_Flashlight (separate handler) provides the lagless flashlight instead.

    // Fires a netevent every UI tic so darkening re-evaluates net-safely (CVAR reads must round-trip through NetworkProcess).
    override void UiTick() { EventHandler.SendNetworkEvent("UpdateLights"); }
    // Net-side receiver for the per-tic "UpdateLights" ping; re-runs the darkening pass.
    override void NetworkProcess(ConsoleEvent e) {
        if(e.Name == "UpdateLights") ChangeLighting();
    }

    // Re-derives every sector's light level (and fog) from the ddz_* CVARs, but
    // only does the expensive sector walk when a parameter actually changed.
    void ChangeLighting() {
        Mode = GetDdzInt("ddz_mode"); Preset = GetDdzInt("ddz_preset"); PreGain = GetDdzInt("ddz_pregain");   // pull live CVAR values into our working fields
        PostGain = GetDdzInt("ddz_postgain"); SkyMode = GetDdzFloat("ddz_skymode"); FogDensity = GetDdzInt("ddz_fog");
        MinLight = GetDdzInt("ddz_minlight");

        bool changed = (OldMode != Mode || OldPreset != Preset || OldPreGain != PreGain // dirty-check: did any knob move since last pass?
            || OldPostGain != PostGain || OldSkyMode != Skymode
            || OldFogDensity != FogDensity || OldMinLight != MinLight);

        if (changed) {                                                  // skip the whole sector loop when nothing changed (this runs every tic)
            BaseAdjustment = 32 * Preset;                              // preset is a coarse step; each unit = 32 light-units of darkening
            for(int i = 0; i < BaseLightLevels.Size(); i++) {
                int BaseLightLevel = BaseLightLevels[i] + PreGain;     // start from the ORIGINAL level (+ pre-gain bias) - never from the already-darkened value
                IsSky = (level.Sectors[i].GetTexture(0) == skyflatnum ||  // sky if floor (0) OR ceiling (1) uses the sky flat
                         level.Sectors[i].GetTexture(1) == skyflatnum);
                FinalAdjustment = BaseAdjustment;
                if(IsSky) FinalAdjustment = int(FinalAdjustment * SkyMode); // sky sectors get scaled darkening so the sky doesn't go pitch-black
                switch(Mode) {                                          // each mode is a different darkening curve:
                    case 1: Level.Sectors[i].Lightlevel = BaseLightLevel - FinalAdjustment; break;                                   // linear subtract
                    case 2: Level.Sectors[i].Lightlevel = int(BaseLightLevel * (1.0 - FinalAdjustment / 256.0)); break;              // multiplicative (proportional dim; 256 = full light range)
                    case 3: Level.Sectors[i].Lightlevel = clamp(BaseLightLevel, 0, 256 - FinalAdjustment); break;                    // ceiling clamp (cap brightness, leave dark rooms dark)
                    case 4: Level.Sectors[i].Lightlevel = int((256 - (FinalAdjustment ** (FinalAdjustment / 256))) * (BaseLightLevel / 256.0) ** (1 + (FinalAdjustment / (33 - (FinalAdjustment / 8))))); break; // gamma-ish curve: nonlinear rolloff that crushes shadows harder than highlights
                    case 10: Level.Sectors[i].Lightlevel = BaseLightLevel - 96; break;   // fixed darkening presets (96/128/256), ignore Preset entirely
                    case 11: Level.Sectors[i].Lightlevel = BaseLightLevel - 128; break;
                    case 12: Level.Sectors[i].Lightlevel = BaseLightLevel - 256; break;  // -256 = effectively pitch black regardless of source
                    default: Level.Sectors[i].Lightlevel = BaseLightLevel; break;        // mode 0 / unknown = no darkening (just pre-gain)
                }
                Level.Sectors[i].Lightlevel += PostGain;               // post-gain bias applied AFTER the curve (lift the whole result up/down)
                Level.Sectors[i].Lightlevel = max(Level.Sectors[i].Lightlevel, MinLight); // floor so the world never drops below the configured minimum
                double FinalFogDensity = FogDensity;
                if(IsSky) FinalFogDensity *= SkyMode;                  // scale fog on sky sectors to match their reduced darkening
                level.Sectors[i].SetFogDensity(int(FinalFogDensity));
            }
        }
        OldMode = Mode; OldPreset = Preset; OldPreGain = PreGain;      // remember this pass's params so next tic's dirty-check works
        OldPostGain = PostGain; OldSkyMode = SkyMode;
        OldFogDensity = FogDensity; OldMinLight = MinLight;
    }
}

// ============================================================================
// GITD_Flashlight - LAGLESS ZScript flashlight. Reproduces the TDDR trick
// (trace the aim, SNAP the light to the hit point each tic = no follow-lag)
// but using ZScript LineTrace, which is a PURE QUERY - it spawns NO puff, so
// it does NOT trigger water/lava splashes (the TDDR bug). Toggle: netevent.
// ============================================================================
// // Event handler that listens for the flashlight toggle netevent and grants /
// flips the per-player flashlight controller item, playing standard click sounds.
class GITD_FlashHandler : EventHandler
{
    override void NetworkProcess(ConsoleEvent e)
    {
        if (e.Name == "gitd_flashlight_toggle")
        {
            int pn = e.Player;                                          // which player pressed the toggle
            if (!playeringame[pn] || !players[pn].mo) return;          // guard against ghosts / no pawn
            let fl = GITD_FlashController(players[pn].mo.FindInventory("GITD_FlashController"));
            if (!fl)
            {
                players[pn].mo.GiveInventory("GITD_FlashController", 1); // first toggle: grant the controller (starts "on")
                players[pn].mo.A_StartSound("DDZ_Flashlight_On", CHAN_AUTO, 0, 0.5);
            }
            else
            {
                fl.on = !fl.on;                                        // subsequent toggles: just flip state
                if (fl.on) players[pn].mo.A_StartSound("DDZ_Flashlight_On", CHAN_AUTO, 0, 0.5);
                else       players[pn].mo.A_StartSound("DDZ_Flashlight_Off", CHAN_AUTO, 0, 0.5);
            }
        }
    }
}

// Per-player inventory item that drives the flashlight: each tic it manages the
// two spring-physics spotlights (tight beam + soft outer spill) with beautiful sway.
class GITD_FlashController : Inventory
{
    bool on;                                                            // is the flashlight currently lit?
    DarkDoomZ_Spotlight SelfLight1, SelfLight2;                         // the two spotlights: tight beam + soft spill

    Default { Inventory.MaxAmount 1; +INVENTORY.UNDROPPABLE; +INVENTORY.UNTOSSABLE; } // exactly one, can't be dropped/tossed away

    // On grant, run base attach logic then default the flashlight to on (first toggle should light it immediately).
    override void AttachToOwner(Actor other) { Super.AttachToOwner(other); on = true; }

    // Per-tic effect: when on, manage the two spring-physics spotlights; when off, tear them down.
    override void DoEffect()
    {
        Super.DoEffect();
        if (!owner || !owner.player) return;                          // only meaningful on a real player pawn

        if (!on)
        {
            if (SelfLight1) { SelfLight1.Destroy(); SelfLight1 = null; }
            if (SelfLight2) { SelfLight2.Destroy(); SelfLight2 = null; }
            return;
        }

        // --- Custom Dynamic Flashlight logic ---
        int mode = 0;
        CVar cm = CVar.FindCVar("gitd_flashlight_mode");
        if (cm) mode = cm.GetInt();

        double intensity = 1.0;
        CVar ci = CVar.FindCVar("gitd_flashlight_intensity");
        if (ci) intensity = ci.GetFloat();
        if (intensity < 0.1) intensity = 0.1;
        if (intensity > 2.0) intensity = 2.0;

        int r = 255, g = 255, b = 255; // Default white
        if (mode == 0) // Normal LED (Custom Color Picker)
        {
            CVar cc = CVar.FindCVar("gitd_flashlight_color");
            if (cc)
            {
                int pk = cc.GetInt();
                r = (pk >> 16) & 0xFF;
                g = (pk >> 8) & 0xFF;
                b = pk & 0xFF;
            }
        }
        else if (mode == 1) // Thermal Heat (Bright Orange-Red)
        {
            r = 255; g = 70; b = 0;
        }
        else if (mode == 2) // UV Bioluminescent (Fluro Deep Purple)
        {
            r = 120; g = 0; b = 255;
        }
        else if (mode == 3) // Tech Grid (Electric Cyan)
        {
            r = 0; g = 240; b = 255;
        }

        // Optics / Radius
        int beamInner = 0;
        int beamOuter = 15;
        int beamRadius = int(640 * intensity);

        int spillInner = 15;
        int spillOuter = 75;
        int spillRadius = int(256 * intensity);

        // Handheld spring-physics parameters (classic responsive sway)
        double spring = 0.25;
        double damping = 0.2;
        int inertia = 4;
        double offsetAngle = 0;
        double offsetZ = -13; // default chest
        int originMode = 0;   // default view-follow

        int attach = 0;
        CVar ca = CVar.FindCVar("gitd_flashlight_attach");
        if (ca) attach = ca.GetInt();

        if (attach == 0)      // head (a few units below view/eyes)
        {
            offsetZ = -2;
            originMode = 0;
        }
        else if (attach == 1) // main hand
        {
            originMode = 1;
        }
        else if (attach == 2) // offhand
        {
            originMode = 2;
        }
        else if (attach == 3) // chest
        {
            offsetZ = -13;
            originMode = 0;
        }

        // Lazy spawn SelfLight1 (beam)
        if (!SelfLight1)
        {
            SelfLight1 = DarkDoomZ_Spotlight(Spawn("DarkDoomZ_Spotlight", owner.pos, false));
            SelfLight1.FollowTarget = owner;
            SelfLight1.originMode = originMode;
            SelfLight1.isSpill = false;
            SelfLight1.angle = owner.angle;
            SelfLight1.pitch = owner.pitch;
            SelfLight1.spring = spring;
            SelfLight1.damping = damping;
            SelfLight1.inertia = inertia;
            SelfLight1.offsetAngle = offsetAngle;
            SelfLight1.offsetZ = offsetZ;
        }
        // Lazy spawn SelfLight2 (spill)
        if (!SelfLight2)
        {
            SelfLight2 = DarkDoomZ_Spotlight(Spawn("DarkDoomZ_Spotlight", owner.pos, false));
            SelfLight2.FollowTarget = owner;
            SelfLight2.originMode = originMode;
            SelfLight2.isSpill = true;
            SelfLight2.angle = owner.angle;
            SelfLight2.pitch = owner.pitch;
            SelfLight2.spring = spring;
            SelfLight2.damping = damping;
            SelfLight2.inertia = inertia;
            SelfLight2.offsetAngle = offsetAngle;
            SelfLight2.offsetZ = offsetZ;
        }

        // Live update colors, attachment origins, and optics
        if (SelfLight1)
        {
            SelfLight1.originMode = originMode;
            SelfLight1.offsetZ = offsetZ;
            SelfLight1.args[DynamicLight.LIGHT_RED] = r;
            SelfLight1.args[DynamicLight.LIGHT_GREEN] = g;
            SelfLight1.args[DynamicLight.LIGHT_BLUE] = b;
            SelfLight1.args[DynamicLight.LIGHT_INTENSITY] = beamRadius;
            SelfLight1.SpotInnerAngle = beamInner;
            SelfLight1.SpotOuterAngle = beamOuter;
        }
        if (SelfLight2)
        {
            SelfLight2.originMode = originMode;
            SelfLight2.offsetZ = offsetZ;
            SelfLight2.args[DynamicLight.LIGHT_RED] = int(r * 0.75);
            SelfLight2.args[DynamicLight.LIGHT_GREEN] = int(g * 0.75);
            SelfLight2.args[DynamicLight.LIGHT_BLUE] = int(b * 0.75);
            SelfLight2.args[DynamicLight.LIGHT_INTENSITY] = spillRadius;
            SelfLight2.SpotInnerAngle = spillInner;
            SelfLight2.SpotOuterAngle = spillOuter;
        }
    }

    // Cleanup: destroy the light actors if the controller itself is destroyed (player death/level end) so no orphan light remains.
    override void OnDestroy()
    {
        if (SelfLight1) { SelfLight1.Destroy(); SelfLight1 = null; }
        if (SelfLight2) { SelfLight2.Destroy(); SelfLight2 = null; }
        Super.OnDestroy();
    }
}

// The follow-with-spring-physics spotlight. A real DynamicLight (Point + Spot + Attenuate)
// that chases the player's view with a damped spring.
class DarkDoomZ_Spotlight : DynamicLight
{
    actor FollowTarget;
    double vela, velp;
    double spring, damping;
    double offsetAngle, offsetZ;
    vector3 targetPos;
    int inertia;
    int originMode;   // 0 head/view, 1 weapon hand, 2 off-hand
    bool isSpill;     // true = the soft outer spill light (cheaper to throttle)
    int tickPhase;

    default
    {
        DynamicLight.Type "Point";
        +DYNAMICLIGHT.ATTENUATE;
        +DYNAMICLIGHT.SPOT;
    }

    override void Tick()
    {
        super.Tick();
        if (!followTarget || !followTarget.player) return;
        if (inertia == 0) inertia = 1;

        // ---- VR OPTIMISATION ----
        tickPhase ^= 1;
        bool perfOn = false;
        {
            CVar c = CVar.FindCVar("ddz_fl_perf");
            if (c) perfOn = c.GetBool();
        }
        if (perfOn && isSpill && tickPhase == 0) return;

        double baseAng = followTarget.angle;
        double basePit = followTarget.pitch;
        Vector3 basePos;
        bool gun = (originMode != 0) && followTarget.OverrideAttackPosDir;
        if (gun && originMode == 1)        // weapon hand
        {
            basePos = followTarget.AttackPos;
            Vector3 d = followTarget.AttackDir(followTarget, followTarget.angle, followTarget.pitch);
            baseAng = d.x; basePit = d.y;
        }
        else if (gun && originMode == 2)   // off-hand
        {
            basePos = followTarget.OffhandPos;
            Vector3 d = followTarget.OffhandDir(followTarget, followTarget.angle, followTarget.pitch);
            baseAng = d.x; basePit = d.y;
        }
        else                               // head / view (and flatscreen fallback)
        {
            basePos = followTarget.vec3Angle(
                2 + (6 * abs(sin(offsetAngle))),
                followtarget.angle + offsetAngle,
                followtarget.player.viewheight + offsetZ,
                false);
        }
        targetpos = basePos;

        vel.x += DampedSpring(pos.x, targetpos.x, vel.x, 1, 1);
        vel.y += DampedSpring(pos.y, targetpos.y, vel.y, 1, 1);
        vel.z += DampedSpring(pos.z, targetpos.z, vel.z, 1, 1);
        vela  += DampedSpring(angle, baseAng, vela, spring, damping);
        velp  += DampedSpring(pitch, basePit, velp, spring, damping);
        setOrigin(pos + vel, true);
        A_SetAngle(angle + (vela / inertia), true);
        A_SetPitch(pitch + (velp / inertia), true);
    }

    double DampedSpring(double p, double r, double v, double k, double d)
    {
        return -(d * v) - (k * (p - r));
    }
}
