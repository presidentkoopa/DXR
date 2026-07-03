// ============================================================================
// GITD Death-FX -- the adaptable effect MACHINE.  (standalone GITD lighting demo)
//
// A death visual is a RECIPE (subclass GITD_DeathEffect, override Tick01, call
// PRIMITIVES). The handler resolves a CONTEXT (colour + tier + the dead monster)
// and dispatches. The SILHOUETTE is the dead thing's OWN walk sprite (its frame
// A/B), laid on the floor as a tinted cutout -- so an imp leaves an imp, a
// zombieman leaves a zombieman, any mod's monster for free.
//
// COLOUR (cvar gitd_death_color_mode): 0 tier / 1 fixed (gitd_death_color) / 2 random.
// All glow is REAL glow via the engine glow-spot channel -- ZERO dynamic lights.
// ============================================================================
//
// COMMENTARY OVERVIEW (added documentation -- no code changed):
//   This is the heart of GITD's "Glow In The Dark" effects layer. Three pieces:
//     1. GITD_Palette          -- pure colour math (HSV, tier ramp, hashed random).
//     2. GITD_DeathEffect + subclasses -- the effect RECIPES; each paints a glow
//        pattern over its short life via the EmitSpot() primitive, which feeds the
//        engine's native glow-spot channel (level.AddGlowSpotWiped). NO dynamic
//        lights are ever used -- this is GITD's absolute hard constraint.
//     3. GITD_DeathFXHandler   -- the EventHandler that catches kills/hits/impacts,
//        resolves context, dispatches an effect, and owns the cross-cutting systems
//        (kill-counter combo numbers, the battlefield-memory heat map, hit-lights,
//        and the impact ring-buffer that keeps full-auto spray from hogging slots).
//   The HF_* classes at the bottom are PORTED sprite-based spark bursts (these DO
//   use sprites, not the glow channel) for weapon wall-impact flavour.
//
//   KEY ENGINE CONTRACT: level.AddGlowSpotWiped(color, radius, x, y, wipeType,
//   progress, dirX, dirY, planeFlags). wipeType selects the shader pattern; the
//   GITD rebuild added many (0 bloom, 1 seam, 2 stroke/bar, 3 ring, 4 hex-field,
//   5 hex-rings, 6 spiral, 7 square-rings, 8 star, 9 sunburst, 10 grid, 11 invert,
//   13 glow-number). wipeType also smuggles the wall-pattern index as wallPat*100.
//   There are only 16 engine glow-spot slots -- nearly every "cap"/"budget"/"ring-
//   buffer" comment below exists to keep one feature from starving the others.
// ============================================================================

// GITD_Palette -- pure static colour math: HSV conversion, tier-ramp, and a
// hashed pseudo-random hue. No state; just the colour vocabulary for all effects.
class GITD_Palette
{
    // Convert HSV (hue 0..360, sat/val 0..1) to an opaque RGB Color. Standard
    // hue-sextant algorithm; used everywhere a vivid neon colour is needed.
    static Color HSV(double h, double s, double v)
    {
        double c = v * s, hp = h / 60.0;                  // chroma + which 60-degree sextant
        double hp2 = hp - 2.0 * floor(hp / 2.0);          // hp mod 2 -> position within an X/C pair
        double x = c * (1.0 - abs(hp2 - 1.0));            // the second-strongest channel
        double r = 0, g = 0, b = 0;
        // assign chroma (c) and the ramp (x) to channels per sextant
        if      (hp < 1.0) { r = c; g = x; }
        else if (hp < 2.0) { r = x; g = c; }
        else if (hp < 3.0) { g = c; b = x; }
        else if (hp < 4.0) { g = x; b = c; }
        else if (hp < 5.0) { r = x; b = c; }
        else               { r = c; b = x; }
        double m = v - c;                                 // value floor added to every channel
        return Color(255, int((r + m) * 255), int((g + m) * 255), int((b + m) * 255));
    }
    // Colour for a monster TIER (0..tierCount-1): hue sweeps cyan(190) -> red(0)
    // as the threat tier rises, so tougher kills read hotter. Always full neon.
    static Color ForTier(int tier, int tierCount = 4)
    {
        if (tierCount < 2) tierCount = 2;                 // guard divide-by-zero on the ramp
        double f = clamp(double(tier) / double(tierCount - 1), 0.0, 1.0);
        return HSV(190.0 - 190.0 * f, 0.85, 1.0);         // 190deg (cyan) down to 0deg (red)
    }
    // Deterministic "random" hue from an integer seed (e.g. kill count). Uses an
    // integer hash (xorshift-style mix) so the same seed always gives the same
    // vivid colour -- repeatable across clients/saves, unlike random().
    static Color Random(int seed)
    {
        int x = seed * 374761393 + 668265263; x = (x ^ (x >> 13)) * 1274126177; x = x ^ (x >> 16);
        return HSV((x & 0x7FFFFFFF) / double(0x7FFFFFFF) * 360.0, 0.9, 1.0);  // mask sign bit -> 0..360
    }
}

// ----------------------------------------------------------------------------
// GITD_MonsterSilhouette -- the dead thing's OWN sprite, walk frames A/B cycling,
// laid flat on the floor, tinted (dark cutout, or glowing). Optionally drifts
// forward (ghost walk). Self-fades over its life.
// ----------------------------------------------------------------------------
class GITD_MonsterSilhouette : Actor
{
    int    bornTic, lifeTics;
    int    sprId;          // the dead monster's sprite sheet (e.g. TROO)
    double baseAlpha;
    double vx, vy, driftSpd;  // forward drift (0 = stay put); was 'speed' -- collides with native Actor.Speed (case-insensitive)

    Default
    {
        // Inert decoration: no collision, no gravity, no thinker interaction; FLATSPRITE lays it on the plane.
        +NOBLOCKMAP; +NOGRAVITY; +NOINTERACTION; +DONTSPLASH; +FLATSPRITE;
        RenderStyle "Stencil"; Alpha 0.85;   // Stencil -> SetShade tints the whole sprite one flat colour
    }
    States { Spawn: TNT1 A -1; Stop; }   // invisible placeholder frame; the real sprite is forced each Tick

    // Per-tic: advance the walk cycle, drift forward, self-fade, and hug the floor.
    override void Tick()
    {
        Super.Tick();
        int age = level.totaltime - bornTic;
        if (lifeTics > 0 && age >= lifeTics) { Destroy(); return; }   // expire with its parent effect
        if (driftSpd != 0.0) SetOrigin((pos.x + vx * driftSpd, pos.y + vy * driftSpd, pos.z), true);  // ghost drift
        sprite = sprId;                                               // force the dead monster's sprite sheet
        frame  = (age / 5) % 4;   // full A/B/C/D walk cycle -- keeps striding the whole time
        double t = double(age) / double(max(1, lifeTics));            // 0..1 life fraction
        Alpha = baseAlpha * (t < 0.7 ? 1.0 : 1.0 - (t - 0.7) / 0.3);  // hold, then linear fade over last 30%
        if (CurSector) SetZ(CurSector.floorplane.ZatPoint(pos.xy) + 1.0);  // +1 to avoid z-fighting the floor
    }
}

// ----------------------------------------------------------------------------
// GITD_DeathEffect -- the base EVERY death visual extends.
// ----------------------------------------------------------------------------
// The recipe base class: holds the resolved context (tint/tier/dead monster/
// facing), the per-style look knobs, and all the shared PRIMITIVES (EmitSpot,
// Bloom, silhouette spawning, colour/intensity/gradient/pulse folding). A
// subclass just sets lifeTics + reach in EffectSpawn() and paints in Tick01(t).
class GITD_DeathEffect : Actor
{
    int    bornTic, lifeTics;
    int    tier;
    Color  tint;
    double faceAngle;
    int    killCount;
    Actor  mon;
    string keywords;
    Actor  silh;       // the monster silhouette (optional)
    // per-effect look knobs (set in EffectSpawn; defaults below = neutral). Each style can carry
    // its OWN gradient + pulse; global cvars scale/override on top.
    Color  gradTo;            // gradient end colour
    bool   hasGrad;           // this effect gradients tint -> gradTo over its life
    double pulseHz, pulseDepth;   // brightness pulse (cycles over life, 0..1 depth)
    double styleInten;        // per-style intensity multiplier (1 = neutral)
    bool   isImpact;          // spawned by a weapon impact (uses gitd_impact_size, no silhouette)

    // Inert glow-emitter actor: never collides/interacts; RenderStyle "None" -> the actor itself draws nothing.
    Default { +NOBLOCKMAP; +NOGRAVITY; +NOINTERACTION; +DONTSPLASH; RenderStyle "None"; }
    States { Spawn: TNT1 A -1; Stop; }

    // Set a default life span; the handler stamps context and calls EffectSpawn() afterwards.
    override void PostBeginPlay()
    {
        Super.PostBeginPlay();
        if (lifeTics <= 0) lifeTics = 52;
        // EffectSpawn() is called by the handler AFTER it stamps mon/tint/face/born.
    }
    // Per-tic driver: compute life fraction t and call Tick01(t); handle persist/expire.
    override void Tick()
    {
        Super.Tick();
        int age = level.totaltime - bornTic;
        if (age >= lifeTics)
        {
            // gitd_death_persist 1 = the mark stays settled for the whole level (no fade/destroy).
            if (Persist() && CanPersist()) { Tick01(1.0); return; }   // re-paint at full-life t=1 forever
            EffectEnd(); if (silh) silh.Destroy(); Destroy(); return;
        }
        Tick01(double(age) / double(max(1, lifeTics)));   // normal path: drive the recipe with t in [0,1)
    }
    // [GITD] gitd_death_persist ("Marks Last") is for MONSTER-DEATH marks only. Weapon IMPACT stamps
    // must NEVER persist -- otherwise every floor shot leaves a permanent glow-spot emitter, and after
    // ~16 shots they fill all 16 engine glow slots and the floor STOPS REACTING to new shots.
    // Whether THIS effect should persist for the level: only death marks (not impacts) and only if the cvar is on.
    bool Persist() { if (isImpact) return false; let cv = CVar.FindCVar("gitd_death_persist"); return cv && cv.GetInt() == 1; }
    virtual bool CanPersist() { return true; }   // one-shot effects (Detector sweep) override to false

    virtual void EffectSpawn() {}   // set lifeTics/reach + spawn silhouette; called once after context is stamped
    virtual void Tick01(double t) {}// paint the effect at life-fraction t (0..1); the per-style recipe body
    virtual void EffectEnd() {}     // cleanup hook fired once when a non-persisting effect expires

    // keyword helpers -- a free-form trait string (e.g. "boss flying speed:2") attached per effect.
    bool HasTrait(string token) { return keywords.IndexOf(token) >= 0; }   // simple presence test
    // Parse "key:value" out of the keyword string; returns "" if the key is absent.
    string KeyVal(string key)
    {
        int i = keywords.IndexOf(key .. ":");
        if (i < 0) return "";
        int s = i + key.Length() + 1, e = keywords.IndexOf(" ", s);   // value runs to the next space
        if (e < 0) e = keywords.Length();
        return keywords.Mid(s, e - s);
    }

    // Plane targeting: gitd_death_planes 0 = Floor only, 1 = Floor + Ceiling. Floor-only is
    // encoded as a NEGATIVE radius, which the glow shader skips on ceilings & walls.
    double PlaneR(double radius) { return radius; }   // pass-through; plane targeting now via PlaneFlags()
    // True when the user wants the mark mirrored on the ceiling too (drives the extra ceiling silhouette).
    bool PlanesBoth() { let cv = CVar.FindCVar("gitd_death_planes"); return cv && cv.GetInt() == 1; }
    // [GITD] real plane targeting via the engine's FGlowSpot.planeFlags (rebuild shipped it).
    // gitd_death_planes 0 = Floor only (default) -> flag 1; 1 = Floor+Ceiling -> flag 0 (both planes).
    // gitd_death_planes -> FGlowSpot.planeFlags bits (floor=1, ceiling=2, wall=4; 0 = all surfaces).
    //   0 = Floor only (1) | 1 = Floor+Ceiling (3) | 2 = Everything incl. walls (0)
    int impactPlane;   // [GITD] weapon impacts: the surface actually struck (1 floor / 2 ceiling / 4 wall);
                       // 0 = fall back to the gitd_death_planes cvar. Lets a CEILING shot glow the ceiling
                       // and a FLOOR shot glow the floor, independent of the death-glow plane setting.
    // Translate the cvar into the engine's planeFlags bitmask passed to AddGlowSpotWiped.
    // When this is an impact that hit a known surface, glow THAT surface instead of obeying the cvar.
    int PlaneFlags()
    {
        if (impactPlane != 0) return impactPlane;   // an impact glows the exact surface it struck
        let cv = CVar.FindCVar("gitd_death_planes");
        int m = cv ? cv.GetInt() : 0;
        if (m == 1) return 3;   // floor + ceiling
        if (m >= 2) return 0;   // everything: floor + ceiling + walls
        return 1;               // floor only (default)
    }

    // ---- PRIMITIVES ----
    // EmitSpot is the single chokepoint for every glow spot: it packs the chosen WALL pattern
    // (gitd_wall_pattern 0..5) into the wipeType as wallPat*100. The shader decodes it -> normal 2D
    // shape on floors/ceilings, vertical wall-mode (Pillar/Scan/Grid/Curtain/Embers/Bars) on walls.
    void EmitSpot(Color c, double radius, double x, double y, int wipeType, double progress, double dx, double dy, int planeFlags)
    {
        let cv = CVar.FindCVar("gitd_wall_pattern");
        int wp = cv ? cv.GetInt() : 0;
        if (wp < 0) wp = 0;                       // clamp the wall-pattern selector to the valid 0..5 range
        if (wp > 5) wp = 5;
        level.AddGlowSpotWiped(c, radius, x, y, wipeType + wp * 100, progress, dx, dy, planeFlags);  // *100 = wall-pattern lane
    }
    // Bloom: a plain radial glow at this actor's position (wipeType 0). The simplest primitive.
    void Bloom(double radius, Color c) { EmitSpot(c, PlaneR(radius), pos.x, pos.y, 0, 0.0, 1.0, 0.0, PlaneFlags()); }
    // BloomAt: a plain radial glow at an arbitrary (x,y) -- used for drifting/scattered sub-spots.
    void BloomAt(double x, double y, double radius, Color c) { EmitSpot(c, PlaneR(radius), x, y, 0, 0.0, 1.0, 0.0, PlaneFlags()); }
    // SeamBloom: a directional "seam" window (wipeType 1) that wipes open along (dirX,dirY) as progress rises.
    void SeamBloom(double radius, Color c, double progress, double dirX, double dirY)
    { EmitSpot(c, PlaneR(radius), pos.x, pos.y, 1, progress, dirX, dirY, PlaneFlags()); }

    // copy the per-actor look onto a silhouette (shared by the floor and ceiling cutouts)
    void ConfigSilh(GITD_MonsterSilhouette s, bool glowing, double driftSpeed)
    {
        s.bornTic  = bornTic;
        s.lifeTics = lifeTics;
        s.sprId    = mon.sprite;       // the dead thing's own sprite sheet
        s.angle    = faceAngle;
        s.Scale    = mon.Scale;        // same size it was
        // glowing = bright tinted ghost; otherwise an opaque PURE BLACK cutout (negative-space silhouette)
        if (glowing) { s.bBRIGHT = true; s.baseAlpha = 0.9; s.SetShade(tint); }
        else         { s.baseAlpha = 1.0; s.SetShade(Color(255, 0, 0, 0)); }  // PURE BLACK cutout, opaque
        if (driftSpeed != 0.0) { s.vx = cos(faceAngle); s.vy = sin(faceAngle); s.driftSpd = driftSpeed; }  // walk forward
    }

    // How much to scale a flat silhouette so it stays on the corpse's flat ground (1.0 = no step
    // nearby; smaller = a step is close, tuck in so the sprite doesn't float out over stairs).
    double FlatFit()
    {
        if (!CurSector) return 1.0;
        double z0 = CurSector.floorplane.ZatPoint(pos.xy);                                  // the corpse's floor height
        double bodyHalf = (mon ? GetDefaultByType(mon.GetClass()).Height : 56.0) * 0.6;     // ~half the laid-flat body
        if (bodyHalf < 8.0) return 1.0;                                                      // tiny body -> never shrink
        double nearest = bodyHalf;
        // probe 8 compass directions; in each, march outward until the floor height jumps (a step/ledge)
        for (int i = 0; i < 8; i++)
        {
            double a = 45.0 * double(i), cx = cos(a), cy = sin(a);
            for (double d = 12.0; d <= bodyHalf; d += 12.0)
            {
                vector2 p = pos.xy + (cx, cy) * d;
                let ps = level.PointInSector(p);
                if (ps && abs(ps.floorplane.ZatPoint(p) - z0) > 14.0) { nearest = min(nearest, d); break; }  // step found here
            }
        }
        return clamp(nearest / bodyHalf, 0.35, 1.0);   // shrink toward the nearest edge, never below 35%
    }

    // body length (on-floor) per unit Scale ~ the monster's standing sprite height
    double SilhUnit() { double h = mon ? GetDefaultByType(mon.GetClass()).Height : 56.0; return (h < 8.0) ? 56.0 : h; }

    // spawn the dead monster's own sprite as a tinted, walking, plane-laid silhouette.
    // boxLen > 0 scales the body (aspect-preserved) to fit the box/pool it's framed in.
    void MakeSilhouette(bool glowing, double driftSpeed = 0.0, double boxLen = 0.0)
    {
        if (!mon) return;   // impacts (mon == null) get no silhouette
        let s = GITD_MonsterSilhouette(Spawn("GITD_MonsterSilhouette", pos, NO_REPLACE));
        if (!s) return;
        silh = s;
        ConfigSilh(s, glowing, driftSpeed);
        if (boxLen > 0.0) { double sc = boxLen / SilhUnit(); s.Scale = (sc, sc); }   // scale to the box
        double fit = FlatFit();                              // [GITD] tuck the body in near stairs, no float
        if (fit < 1.0) s.Scale = (s.Scale.x * fit, s.Scale.y * fit);
        if (s.CurSector) s.SetZ(s.CurSector.floorplane.ZatPoint(s.pos.xy) + 1.0);   // sit just above the floor

        // Floor + Ceiling mode: hang a matching cutout under the ceiling too.
        if (PlanesBoth() && s.CurSector)
        {
            let cs = GITD_MonsterSilhouette(Spawn("GITD_MonsterSilhouette", pos, NO_REPLACE));
            if (cs)
            {
                ConfigSilh(cs, glowing, driftSpeed);
                if (boxLen > 0.0) { double sc = boxLen / SilhUnit(); cs.Scale = (sc, sc); }
                cs.SetZ(s.CurSector.ceilingplane.ZatPoint(cs.pos.xy) - 1.0);   // just below the ceiling
            }
        }
    }

    // Scale every RGB channel by k (0..1) -- darkens a colour while keeping its hue. Used by ApplyInten.
    static Color Dim(Color c, double k) { return Color(255, int(c.r * k), int(c.g * k), int(c.b * k)); }

    // ---- INTENSITY / GRADIENT / PULSE ----
    // Read a float cvar with a fallback default (the int-cvar twin is CIntDef on the handler).
    static double GFloat(string n, double def) { let c = CVar.FindCVar(n); return c ? c.GetFloat() : def; }
    // Base reach in map units: impacts use gitd_impact_size, deaths use gitd_death_size (default 128).
    int FxSize() { let cv = CVar.FindCVar(isImpact ? "gitd_impact_size" : "gitd_death_size"); return cv ? cv.GetInt() : 128; }
    // brightness: <=1 dims; >1 pushes white-hot (additive headroom is capped, so over-drive whitens)
    Color ApplyInten(Color c, double inten)
    {
        inten = max(inten, 0.0);
        if (inten <= 1.0) return Dim(c, inten);                       // below 1 just darkens toward black
        double w = clamp((inten - 1.0) * 0.5, 0.0, 1.0);             // above 1 lerps toward white (capped)
        return Color(255, int(c.r + (255 - c.r) * w), int(c.g + (255 - c.g) * w), int(c.b + (255 - c.b) * w));
    }
    // The colour an effect should paint at life-fraction t, with a base brightness k. Folds in the
    // per-effect gradient + pulse, plus the global intensity/pulse/gradient cvars.
    Color FxColor(double t, double k)
    {
        Color base;
        let cm = CVar.FindCVar("gitd_death_color_mode");
        if (cm && cm.GetInt() == 3)
        {
            // RAINBOW: sweep the full hue wheel over the effect's life (offset per kill)
            double hue = t * 360.0 + double(killCount) * 47.0;        // 47-degree per-kill offset = adjacent kills differ
            hue -= 360.0 * floor(hue / 360.0);                        // wrap into 0..360
            base = GITD_Palette.HSV(hue, 0.9, 1.0);
        }
        else
        {
            // gradient endpoint: per-effect, or the global gradient cvar if enabled
            Color gto = tint; bool grad = hasGrad; if (hasGrad) gto = gradTo;
            let gc = CVar.FindCVar("gitd_death_grad");
            if (gc && gc.GetInt() == 1)
            {
                // global gradient overrides: unpack the packed 0xRRGGBB cvar as the gradient end colour
                let cc = CVar.FindCVar("gitd_death_grad_color");
                if (cc) { int v = cc.GetInt(); gto = Color(255, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF); grad = true; }
            }
            base = tint;
            // lerp tint -> gto across the life fraction t
            if (grad) base = Color(255, int(tint.r + (gto.r - tint.r) * t),
                                        int(tint.g + (gto.g - tint.g) * t),
                                        int(tint.b + (gto.b - tint.b) * t));
        }
        // intensity = global slider * per-style * this call's k
        double si = (styleInten > 0.0) ? styleInten : 1.0;
        double inten = GFloat("gitd_death_intensity", 1.0) * si * k;
        // pulse: per-effect, or the global pulse cvar if enabled
        double pHz = pulseHz, pDepth = pulseDepth;
        let pc = CVar.FindCVar("gitd_death_pulse");
        if (pc && pc.GetInt() == 1) { pHz = GFloat("gitd_death_pulse_speed", 2.0); pDepth = GFloat("gitd_death_pulse_depth", 0.5); }
        // modulate intensity by a sine over life: stays in [1-depth, 1] so it dips/brightens, never goes dark
        if (pDepth > 0.0) inten *= (1.0 - pDepth) + pDepth * (0.5 + 0.5 * sin(t * 360.0 * pHz));
        // when persisting for the whole level, settle to a steady glow instead of fading to nothing
        if (Persist() && CanPersist()) inten = max(inten, GFloat("gitd_death_intensity", 1.0) * si * 0.4);  // floor at 40%
        return ApplyInten(base, inten);
    }

    // Two-phase envelope: ramp the RADIUS up over the first bloomFrac of life, then hold it
    // while the BRIGHTNESS decays quadratically. Returns (radiusFrac, brightnessK) for Bloom-style FX.
    double, double BloomSettle(double t, double bloomFrac = 0.18)
    {
        if (t < bloomFrac) return t / bloomFrac, 1.0;                 // growing: radius 0->1, full brightness
        double ft = (t - bloomFrac) / (1.0 - bloomFrac);             // settle phase 0..1
        return 1.0, (1.0 - ft) * (1.0 - ft);                         // full radius, brightness eases out (squared)
    }
}

// ---- STYLE 1: Death Pool -- glow blooms, dark monster silhouette inside, fades.
// A glow pool blooms open under the corpse with the dead thing's black cutout inside it.
class GITD_FX_DeathPool : GITD_DeathEffect
{
    double maxReach;
    // Size the pool by tier and drop a dark (non-glowing) silhouette scaled to fit it.
    override void EffectSpawn()
    {
        lifeTics = 56;
        int sz = FxSize();
        maxReach = double(sz) * (0.85 + 0.05 * tier);   // tougher monster -> slightly bigger pool
        MakeSilhouette(false, 0.0, maxReach * 0.7);   // dark cutout, scaled to the pool
    }
    // Bloom open then settle/fade using the shared envelope.
    override void Tick01(double t)
    {
        double rf, k; [rf, k] = BloomSettle(t);          // rf = radius fraction, k = brightness
        Bloom(maxReach * rf, FxColor(t, k));
    }
}

// ---- STYLE 2: Seam Reveal -- narrow window wipes open, dark WALKING monster inside.
// A tall directional window (seam) wipes open along the corpse's facing, revealing the walking cutout.
class GITD_FX_SeamReveal : GITD_DeathEffect
{
    double maxReach, dirX, dirY, cx, cy;
    // Compute the seam direction/centre from the facing and size the window to the standing body length.
    override void EffectSpawn()
    {
        lifeTics = 80;
        dirX = cos(faceAngle); dirY = sin(faceAngle);
        // Body length laid flat ~ the monster's STANDING sprite height (corpse Height is reduced on death,
        // so read the class default). Size the box to the body + margin, and centre it on the body so the
        // head no longer clips past the clamp.
        double stdH = 56.0;
        if (mon) { let d = GetDefaultByType(mon.GetClass()); if (d) stdH = d.Height; }   // standing height, not corpse
        double bodyLen = stdH * 1.4;
        double halfH = bodyLen * 0.5 + 8.0;            // tall half-extent + margin
        maxReach = halfH / 0.62;                        // shader uses 0.62*radius as the tall half
        cx = pos.x + dirX * bodyLen * 0.5;             // shift box forward so feet->head sits centred
        cy = pos.y + dirY * bodyLen * 0.5;
        MakeSilhouette(false, 0.0, bodyLen);   // dark walking cutout scaled to the seam window
    }
    // Wipe the seam open over the first 30% of life, then hold the window while it fades out (squared).
    override void Tick01(double t)
    {
        double wipeFrac = 0.3, progress, k;
        if (t < wipeFrac) { progress = t / wipeFrac; k = 1.0; }   // opening
        else { progress = 1.0; double ft = (t - wipeFrac) / (1.0 - wipeFrac); k = (1.0 - ft) * (1.0 - ft); }  // fade
        EmitSpot(FxColor(t, k), PlaneR(maxReach), cx, cy, 1, progress, dirX, dirY, PlaneFlags());  // box centred on the body
    }
}

// ---- STYLE 3: Ghost Walk (the favorite) -- the GLOWING monster silhouette keeps
//      walking forward (its own sprite), trailing glow, then fades.
// The user's favourite: a glowing ghost of the dead monster strides away leaving a trail of glow.
class GITD_FX_GhostWalk : GITD_DeathEffect
{
    double maxReach, vx, vy, walkSpeed;
    // Spawn a GLOWING, forward-drifting silhouette and set its walk speed from the effect size.
    override void EffectSpawn()
    {
        lifeTics = 70;
        int sz = FxSize();
        maxReach = double(sz) * 0.55;
        walkSpeed = double(sz) * 0.02;           // units/tic forward
        vx = cos(faceAngle); vy = sin(faceAngle);
        MakeSilhouette(true, walkSpeed);          // GLOWING, drifting forward
    }
    // Lay a fading glow pool under the ghost's eased-forward position each tic (the trail).
    override void Tick01(double t)
    {
        double ease = 1.0 - (1.0 - t) * (1.0 - t);   // ease-out: fast start, slowing
        double off  = double(maxReach) * 2.0 * ease; // how far forward the trailing glow has reached
        double k = (t < 0.6) ? 1.0 : (1.0 - (t - 0.6) / 0.4);  // hold then fade last 40%
        BloomAt(pos.x + vx * off, pos.y + vy * off, maxReach, FxColor(t, k * 0.8));   // trailing glow under it
    }
}

// ---- STYLE 4: Death-Ping -- a bright pulse detonates outward (tier-scaled).
//      (v1 = filled expanding pulse; a true hollow ring is a ring-shader add.)
// A hollow neon ring detonates outward from the corpse and fades as it expands (radar ping).
class GITD_FX_DeathPing : GITD_DeathEffect
{
    double maxReach;
    // Short life; ring radius scales with tier.
    override void EffectSpawn()
    {
        lifeTics = 30;
        int sz = FxSize();
        maxReach = double(sz) * (1.0 + 0.35 * tier);
    }
    // wipeType 3 = expanding hollow ring; progress = t drives the ring outward, brightness = 1-t.
    override void Tick01(double t)
    {
        // hollow RING detonates outward (wipeType 3), fading as it expands
        EmitSpot(FxColor(t, 1.0 - t), PlaneR(maxReach), pos.x, pos.y, 3, t, 1.0, 0.0, PlaneFlags());
    }
}

// ---- STYLE 5: Stylized X -- two neon strokes slash on (staggered), bright tips,
//      settle-flash, slight per-kill rotation. Reads in chaos. Abstract mark (no silhouette).
// Two crossed neon strokes snap on one after the other to form an X mark (the "angry signature X").
class GITD_FX_StylizedX : GITD_DeathEffect
{
    double reach, ax, ay, bx, by;
    // Build a FIXED diagonal X (two perpendicular stroke directions) with a tiny per-kill jitter.
    override void EffectSpawn()
    {
        lifeTics = 40;
        int sz = FxSize();
        reach = double(sz) * 0.85;
        // FIXED diagonal X (never facing-relative, so it never collapses into a +); tiny per-kill jitter for life.
        double rot = 45.0 + (double(killCount * 37 % 16) - 8.0);   // 45deg +/- ~8deg hashed wobble
        ax = cos(rot);        ay = sin(rot);          // stroke 1  (NE-SW)
        bx = cos(rot + 90.0); by = sin(rot + 90.0);   // stroke 2  (NW-SE)  -> crossed = X
    }
    // Snap stroke 1 on fast, stroke 2 just after (staggered), then fade both. wipeType 2 = directional bar.
    override void Tick01(double t)
    {
        double p1 = clamp(t / 0.20, 0.0, 1.0);           // SNAP stroke 1 on
        double p2 = clamp((t - 0.16) / 0.20, 0.0, 1.0);  // stroke 2 right after
        double fade = (t < 0.6) ? 1.0 : (1.0 - (t - 0.6) / 0.4);
        Color c = FxColor(t, fade);
        if (p1 > 0.0) EmitSpot(c, PlaneR(reach), pos.x, pos.y, 2, p1, ax, ay, PlaneFlags());
        if (p2 > 0.0) EmitSpot(c, PlaneR(reach), pos.x, pos.y, 2, p2, bx, by, PlaneFlags());
    }
}

// ---- STYLE 5: Hex Field -- a honeycomb of cells flips open in a wave from the corpse outward
//      (the "flattened soccer ball unfolding"). One glow spot; the shader tiles + flips.
// A honeycomb (wipeType 4) tiles outward, cells flipping open in a wave -- all from one glow spot.
class GITD_FX_HexField : GITD_DeathEffect
{
    double reach;
    override void EffectSpawn()
    {
        lifeTics = 52;
        int sz = FxSize();
        reach = double(sz) * 1.15;
    }
    override void Tick01(double t)
    {
        double fade = (t < 0.78) ? 1.0 : (1.0 - (t - 0.78) / 0.22);   // hold most of life, quick tail fade
        EmitSpot(FxColor(t, fade), PlaneR(reach), pos.x, pos.y, 4, t, 1.0, 0.0, PlaneFlags());  // wipeType 4 = hex field
    }
}

// ---- IMPACT: Inverse Glow -- flips whatever colour/light is currently under the hit, within
//      radius X. Negative-space flash: blue glow -> orange, near-black floor -> white. wipeType 11.
//      Pure glow channel, ZERO dynamic lights.
// Inverts the colour/light already under the hit point for a glitchy negative-space pop (impacts only).
class GITD_FX_InvertImpact : GITD_DeathEffect
{
    double reach;
    override bool CanPersist() { return false; }   // an invert flash must never linger as a permanent emitter
    override void EffectSpawn() { lifeTics = 16; reach = double(FxSize()); }
    override void Tick01(double t)
    {
        double strength = 1.0 - t;                          // fades out over its 16-tic life
        strength *= 0.45 + 0.55 * abs(cos(t * 17.0));       // ~3 negative strobes -> reads as a glitch pop, not a glow
        // colour arg is ignored by the INVERT shader path; progress (6th arg) carries strength.
        EmitSpot(Color(255, 255, 255, 255), PlaneR(reach), pos.x, pos.y, 11, strength, 1.0, 0.0, PlaneFlags());
    }
}

// ---- STYLE 6: Hex Rings -- concentric neon hexagon rings spin out from the corpse (the wild one).
// Concentric hexagonal rings (wipeType 5) spin outward -- the flashy one.
class GITD_FX_HexRings : GITD_DeathEffect
{
    double reach;
    override void EffectSpawn()
    {
        lifeTics = 46;
        int sz = FxSize();
        reach = double(sz) * 1.25;
    }
    override void Tick01(double t)
    {
        double fade = (t < 0.7) ? 1.0 : (1.0 - (t - 0.7) / 0.3);
        EmitSpot(FxColor(t, fade), PlaneR(reach), pos.x, pos.y, 5, t, 1.0, 0.0, PlaneFlags());  // wipeType 5 = hex rings
    }
}

// ---- STYLE 7: Spiral -- neon arms unwind and spin out from the corpse.
// Neon spiral arms (wipeType 6) unwind and rotate out from the corpse.
class GITD_FX_Spiral : GITD_DeathEffect
{
    double reach;
    override void EffectSpawn()
    {
        lifeTics = 48;
        int sz = FxSize();
        reach = double(sz) * 1.2;
    }
    override void Tick01(double t)
    {
        double fade = (t < 0.72) ? 1.0 : (1.0 - (t - 0.72) / 0.28);
        EmitSpot(FxColor(t, fade), PlaneR(reach), pos.x, pos.y, 6, t, 1.0, 0.0, PlaneFlags());  // wipeType 6 = spiral
    }
}

// ---- GEOMETRIC SHAPES (single-spot shader patterns) ----
// Each of the next four is a one-spot geometric shader pattern: build reach in EffectSpawn,
// hold-then-fade in Tick01, dispatch with its own wipeType (7..10).
class GITD_FX_SquareRings : GITD_DeathEffect   // concentric rotating squares
{
    double reach;
    override void EffectSpawn() { lifeTics = 46; reach = double(FxSize()) * 1.2; }
    override void Tick01(double t)
    {
        double fade = (t < 0.7) ? 1.0 : (1.0 - (t - 0.7) / 0.3);
        EmitSpot(FxColor(t, fade), PlaneR(reach), pos.x, pos.y, 7, t, 1.0, 0.0, PlaneFlags());   // wipeType 7 = square rings
    }
}
class GITD_FX_Star : GITD_DeathEffect          // a growing 5-point star
{
    double reach;
    override void EffectSpawn() { lifeTics = 44; reach = double(FxSize()) * 1.1; }
    override void Tick01(double t)
    {
        double fade = (t < 0.72) ? 1.0 : (1.0 - (t - 0.72) / 0.28);
        EmitSpot(FxColor(t, fade), PlaneR(reach), pos.x, pos.y, 8, t, 1.0, 0.0, PlaneFlags());   // wipeType 8 = star
    }
}
class GITD_FX_Sunburst : GITD_DeathEffect       // 12 rotating radial spokes
{
    double reach;
    override void EffectSpawn() { lifeTics = 44; reach = double(FxSize()) * 1.2; }
    override void Tick01(double t)
    {
        double fade = (t < 0.7) ? 1.0 : (1.0 - (t - 0.7) / 0.3);
        EmitSpot(FxColor(t, fade), PlaneR(reach), pos.x, pos.y, 9, t, 1.0, 0.0, PlaneFlags());   // wipeType 9 = sunburst
    }
}
class GITD_FX_Grid : GITD_DeathEffect           // a checkerboard grid lighting up in a wave
{
    double reach;
    override void EffectSpawn() { lifeTics = 50; reach = double(FxSize()) * 1.2; }
    override void Tick01(double t)
    {
        double fade = (t < 0.75) ? 1.0 : (1.0 - (t - 0.75) / 0.25);
        EmitSpot(FxColor(t, fade), PlaneR(reach), pos.x, pos.y, 10, t, 1.0, 0.0, PlaneFlags());  // wipeType 10 = grid
    }
}

// ---- STYLE 8: Pulse Detect -- a shockwave races out over a LONG distance; every living monster
//      the front sweeps past gets a crazy neon mark stamped under it (radar lock).
//      NOTE: limited by the 4-spot cap for now (pulse + a few marks at once); the rebuild lifts it.
// Radar sweep: a long-range ring races out and stamps a persistent neon mark under every monster it passes.
class GITD_FX_Detector : GITD_DeathEffect
{
    double maxRange;
    Array<Actor> marked;   // monsters already tagged this sweep (avoid double-marking)
    override bool CanPersist() { return false; }   // the sweep is one-shot; its DetectMarks persist instead
    override void EffectSpawn()
    {
        lifeTics = 64;
        int sz = FxSize();
        maxRange = double(sz) * 5.0;     // BIG distance
    }
    override void Tick01(double t)
    {
        double front = t * maxRange;   // current radius of the expanding wavefront
        // the racing pulse ring
        EmitSpot(FxColor(t, 1.0 - t * 0.6), PlaneR(maxRange), pos.x, pos.y, 3, t, 1.0, 0.0, PlaneFlags());
        // sweep: tag every monster the front has newly reached
        let it = ThinkerIterator.Create("Actor");
        Actor a;
        while (a = Actor(it.Next()))
        {
            if (!a || !a.bIsMonster || a.health <= 0 || a == mon) continue;   // only live monsters, not the source
            if (marked.Find(a) != marked.Size()) continue;                    // already tagged -> skip
            if ((a.pos.xy - pos.xy).Length() <= front)                        // inside the wavefront now
            {
                marked.Push(a);
                let mk = GITD_FX_DetectMark(Actor.Spawn("GITD_FX_DetectMark", a.pos, NO_REPLACE));
                if (mk) { mk.bornTic = level.totaltime; mk.tint = tint; mk.killCount = killCount + marked.Size(); mk.EffectSpawn(); }  // vary shape per mark
            }
        }
    }
}

// the crazy mark stamped under a detected monster (shape varies for chaos)
// The neon mark dropped on each radar-detected monster; its shape rotates 4/5/6 for visual chaos.
class GITD_FX_DetectMark : GITD_DeathEffect
{
    double reach;
    int shape;
    override void EffectSpawn()
    {
        lifeTics = 40;
        int sz = FxSize();
        reach = double(sz) * 0.65;
        shape = 4 + (killCount % 3);     // 4 hex field / 5 hex rings / 6 spiral
    }
    override void Tick01(double t)
    {
        double fade = (t < 0.6) ? 1.0 : (1.0 - (t - 0.6) / 0.4);
        EmitSpot(FxColor(t, fade), PlaneR(reach), pos.x, pos.y, shape, t, 1.0, 0.0, PlaneFlags());
    }
}

// ---- STYLE 9: Firework -- a MEAN multidirectional burst. Many jagged multicolour streaks fire
//      outward from the corpse (each bar's centre offset outward so it reads as a ray, not a full
//      line), white-hot detonation flash. Rides the lifted 16-spot cap.
// A multidirectional multicolour burst: up to 14 streaks shoot outward + a white detonation flash.
class GITD_FX_Firework : GITD_DeathEffect
{
    double reach;
    int n;
    double angs[16];   // per-streak angle (fixed-size arrays sized to the 16-spot ceiling)
    double lens[16];   // per-streak length
    Color  cols[16];   // per-streak colour
    override bool CanPersist() { return false; }   // one-shot burst
    // Precompute each streak's angle/length/colour once (hashed off killCount for variety).
    override void EffectSpawn()
    {
        lifeTics = 34;
        int sz = FxSize();
        reach = double(sz) * 0.8;
        n = 14;
        for (int i = 0; i < n; i++)
        {
            angs[i] = (360.0 / double(n)) * double(i) + double((killCount * 7 + i * 53) % 30) - 15.0;   // even spread +/-15deg jitter
            lens[i] = reach * (0.55 + 0.45 * double((i * 37) % 100) / 100.0);                            // varied length
            double hue = double(((i * 360) / n + killCount * 23) % 360);
            cols[i] = GITD_Palette.HSV(hue, 0.95, 1.0);   // multicolour streaks
        }
    }
    // Each tic: grow every streak outward (offset so it reads as a ray), fade them, flash on detonation.
    override void Tick01(double t)
    {
        double ease = 1.0 - (1.0 - t) * (1.0 - t) * (1.0 - t);   // fast out
        double fade = (t < 0.25) ? 1.0 : (1.0 - (t - 0.25) / 0.75);
        double inten = GFloat("gitd_death_intensity", 1.0);
        for (int i = 0; i < n; i++)
        {
            double dx = cos(angs[i]), dy = sin(angs[i]);
            double half = ease * lens[i];                 // grows -> streak shoots outward
            // place the bar's CENTRE out at `half` so it reads as a ray from the corpse, not a full diameter line
            EmitSpot(ApplyInten(cols[i], fade * inten), half, pos.x + dx * half, pos.y + dy * half, 2, 1.0, dx, dy, PlaneFlags());
        }
        if (t < 0.12) BloomAt(pos.x, pos.y, reach * 0.5 * (1.0 - t / 0.12), Color(255, 255, 255, 255));  // detonation flash
    }
}

// ============================================================================
// ACCENT EFFECTS -- a garnish layered on top of ANY primary style (cvar gitd_death_accent).
// Spawned alongside the primary by the handler. Kept to a few spots so they coexist.
// ============================================================================

// forking electric bolts that crackle out and flash
// Accent: short-lived electric-blue bolts that crackle outward; layered atop any primary death style.
class GITD_FX_AccentLightning : GITD_DeathEffect
{
    double reach;
    double angs[5];
    override bool CanPersist() { return false; }
    override void EffectSpawn()
    {
        lifeTics = 14;
        int sz = FxSize();
        reach = double(sz) * 0.95;
        for (int i = 0; i < 5; i++) angs[i] = double((killCount * 41 + i * 72 + i * i * 13) % 360);   // hashed bolt angles
    }
    override void Tick01(double t)
    {
        double ease = clamp(t / 0.25, 0.0, 1.0);
        double fade = (t < 0.5) ? 1.0 : (1.0 - (t - 0.5) / 0.5);
        double inten = GFloat("gitd_death_intensity", 1.0);
        Color c = Color(255, 165, 210, 255);   // electric blue-white
        for (int i = 0; i < 5; i++)
        {
            double a = angs[i] + sin(t * 900.0 + double(i) * 2.0) * 10.0;   // crackle jitter
            double dx = cos(a), dy = sin(a);
            double half = ease * reach * 0.5;
            EmitSpot(ApplyInten(c, fade * inten), half, pos.x + dx * half, pos.y + dy * half, 2, 1.0, dx, dy, PlaneFlags());
        }
    }
}

// hot fragments flung outward, fading
// Accent: hot ember fragments flung outward along hashed angles, fading as they fly.
class GITD_FX_AccentShrapnel : GITD_DeathEffect
{
    double reach;
    double angs[6];
    double spds[6];
    override bool CanPersist() { return false; }
    override void EffectSpawn()
    {
        lifeTics = 22;
        int sz = FxSize();
        reach = double(sz);
        for (int i = 0; i < 6; i++) { angs[i] = double((killCount * 13 + i * 61) % 360); spds[i] = 0.55 + double((i * 43) % 100) / 100.0; }  // hashed angle + speed
    }
    override void Tick01(double t)
    {
        double fade = 1.0 - t;
        double inten = GFloat("gitd_death_intensity", 1.0);
        Color c = Color(255, 255, 190, 110);   // hot ember
        for (int i = 0; i < 6; i++)
        {
            double dist = t * reach * spds[i];                            // fragment flies outward over life
            BloomAt(pos.x + cos(angs[i]) * dist, pos.y + sin(angs[i]) * dist, reach * 0.13 * (1.0 - t * 0.4), ApplyInten(c, fade * inten));
        }
    }
}

// fast tiny sparks scattering
// Accent: a quick scatter of tiny bright sparks; the fastest, smallest garnish.
class GITD_FX_AccentSparks : GITD_DeathEffect
{
    double reach;
    double angs[8];
    override bool CanPersist() { return false; }
    override void EffectSpawn()
    {
        lifeTics = 16;
        int sz = FxSize();
        reach = double(sz) * 0.8;
        for (int i = 0; i < 8; i++) angs[i] = double((killCount * 19 + i * 47) % 360);   // hashed spark angles
    }
    override void Tick01(double t)
    {
        double fade = (1.0 - t) * (1.0 - t);   // squared -> snappy fade
        double inten = GFloat("gitd_death_intensity", 1.0);
        Color c = Color(255, 255, 240, 180);   // bright white-gold
        for (int i = 0; i < 8; i++)
        {
            double dist = t * reach * (0.7 + 0.3 * double((i * 29) % 100) / 100.0);
            BloomAt(pos.x + cos(angs[i]) * dist, pos.y + sin(angs[i]) * dist, reach * 0.06, ApplyInten(c, fade * inten));
        }
    }
}

// A brief DYNAMIC-LIGHT burst attached at a hit point -- the "burst of light on hitting enemies".
// Needs gl_lights = true. GITD-coloured; animates its radius down over a short life (additive).
// NOTE: this is the ONE place dynamic lights are used -- it is the HIT-light system (gitd_hitlight),
// deliberately separate from the glow-channel death/impact FX (which never use lights).
class GITD_HitLight : Actor
{
    Actor mon;            // the monster this light rides (one light per monster, refreshed on hit)
    Color lcol;
    int   lrad, llife, lage;
    Default { +NOINTERACTION +NOGRAVITY +NOBLOCKMAP +DONTSPLASH; RenderStyle "None"; }
    States { Spawn: TNT1 A 1; Loop; }
    void Refresh(Color c, int rad) { lcol = c; lrad = rad; llife = 8; lage = 0; }   // hit again -> reset, don't stack
    // Per-tic: follow the body, shrink the light radius over life, then detach + destroy.
    override void Tick()
    {
        Super.Tick();
        if (mon && mon.health > 0) SetOrigin(mon.pos + (0, 0, mon.height * 0.5), true);  // follow the body
        lage++;
        if (lage > llife) { A_RemoveLight("gitd_hit"); Destroy(); return; }   // life over -> drop the light
        double f = 1.0 - double(lage) / double(max(1, llife));                // 1 -> 0 radius shrink factor
        A_AttachLight("gitd_hit", 0, lcol, int(double(lrad) * f), 0, 2);   // type 0 = point, flag 2 = additive
    }
}

// ----------------------------------------------------------------------------
// GITD_DeathFXHandler -- catches kills, resolves context, dispatches.
// ----------------------------------------------------------------------------

// Paints a glowing NUMBER on the floor at a kill (wipeType 13 draws the digits in-shader, centred by
// construction). Orientation is LOCKED to the supplied facing via (dx,dy) -- exactly like the silhouette.
// The kill-counter badge actor: re-emits a glow-number spot each tic, opening/holding/closing its ring.
class GITD_SeamBox : Actor
{
    int age, life, packed;          // packed = number + colourIdx*131072
    double rad, dx, dy;
    Color vcol;                     // Visual color for billboard mode
    Default { +NOINTERACTION +NOGRAVITY +NOBLOCKMAP +DONTSPLASH; RenderStyle "None"; }
    States { Spawn: TNT1 A 1; Loop; }
    // Configure the badge: radius, packed number+colour, facing direction (scaled to the ellipse aspect), life.
    void Setup(double radius, int packn, double ddx, double ddy, bool big) { rad = radius; packed = packn; dx = ddx; dy = ddy; age = 0; life = big ? 80 : 60; }
    override void Tick()
    {
        Super.Tick(); age++;
        if (age > life) { Destroy(); return; }
        double prog;
        if (age < 12) prog = double(age) / 12.0;                     // ring opens
        else if (age > life - 14) prog = double(life - age) / 14.0;  // closes
        else prog = 1.0;                                             // holds
        prog = clamp(prog, 0.05, 1.0);

        CVar billboardCVar = CVar.FindCVar("gitd_kill_billboard");
        if (billboardCVar && billboardCVar.GetBool())
        {
            int num = packed % 131072;
            int font = packed / 131072;
            double zHeight = pos.z + 24.0; // float in the air
            level.AddGlowPanel(vcol, rad, pos.x, pos.y, zHeight, font * 100 + 13, prog, 0.0, 0.0, num);
        }
        else
        {
            Color enc = Color(255, (packed >> 16) & 255, (packed >> 8) & 255, packed & 255);   // number packed into RGB -> shader reads wgPk
            level.AddGlowSpotWiped(enc, rad, pos.x, pos.y, 13, prog, dx, dy, 1);   // wipeType 13 = in-shader glow number, floor
        }
    }
}

// The central EventHandler: hooks world events (kill/damage/spawn/died/load/tick) and owns every
// cross-cutting GITD system -- kill-counter combos, the heat map, hit-lights, and the impact ring-buffer.
class GITD_DeathFXHandler : EventHandler
{
    int killCount;
    int impactCount;
    Array<GITD_HitLight> hitLights;   // active hit-lights -- one per monster, hard-capped
    Array<GITD_DeathEffect> impactFX; // [GITD] live weapon-impact stamps, recycled oldest-first so full-auto spray always shows the newest (see TrackImpact)

    // [GITD] Battlefield Memory heat map -- every kill burns into a spatial grid; the hottest cells
    // glow on a thermal gradient (blue = one death ... red/white-hot = a pile). Accumulates + persists.
    Array<int> hmX, hmY, hmCount;     // parallel arrays: grid cell X, cell Y, and accumulated kill count
    int combo, lastKillTic, mapKills;   // [GITD] kill-counter combo streak + running map total (never resets)

    // On a fresh (non-save) level load, zero every accumulator so nothing carries over between maps.
    override void WorldLoaded(WorldEvent e) { if (!e.IsSaveGame) { killCount = 0; impactCount = 0; hitLights.Clear(); impactFX.Clear(); hmX.Clear(); hmY.Clear(); hmCount.Clear(); combo = 0; lastKillTic = -1000; mapKills = 0; } }

    // [GITD] Ring-buffer the live weapon-impact stamps. On each new impact: drop any that already
    // faded, then if we're over gitd_impact_max, CONSUME the oldest. So a full-auto spray always
    // shows the newest impacts, the cost stays bounded (Quest-friendly), and impacts never hog all
    // 16 engine glow-spot slots. Death marks + kill numbers are NOT tracked here (they self-manage).
    void TrackImpact(GITD_DeathEffect fx)
    {
        if (!fx) return;
        for (int i = impactFX.Size() - 1; i >= 0; i--)
            if (!impactFX[i]) impactFX.Delete(i);          // prune already-destroyed stamps
        impactFX.Push(fx);
        int cap = CIntDef("gitd_impact_max", 14);
        if (cap < 1) cap = 1;
        while (impactFX.Size() > cap)                       // over budget -> recycle the oldest
        {
            let old = impactFX[0];
            impactFX.Delete(0);
            if (old) old.Destroy();
        }
    }

    // Console-command hook: the "randomize colors" button rolls all four colour cvars at once.
    override void NetworkProcess(ConsoleEvent e)
    {
        if (e.Name == "gitd_randomize_colors")   // roll all four colour wheels at once
        {
            RandColor("hf_glow_color_floor");
            RandColor("hf_glow_color_ceil");
            RandColor("gitd_death_color");
            RandColor("gitd_death_grad_color");
        }
    }
    // Set a packed-RGB cvar to a random VIVID colour (each channel 48..255 to avoid muddy near-black).
    void RandColor(string cvname)
    {
        let cv = CVar.FindCVar(cvname);
        if (!cv) return;
        cv.SetInt(random(48, 255) * 65536 + random(48, 255) * 256 + random(48, 255));   // vivid (avoid near-black)
    }

    // Heat map: snap a world position to a 96-unit grid cell and bump that cell's kill count (or add it).
    void HeatAccumulate(double wx, double wy)
    {
        int cs = 96;                                       // grid cell size in map units
        int cx = int(floor(wx / cs));
        int cy = int(floor(wy / cs));
        for (int i = 0; i < hmX.Size(); i++)
            if (hmX[i] == cx && hmY[i] == cy) { hmCount[i]++; return; }   // existing cell -> increment
        hmX.Push(cx); hmY.Push(cy); hmCount.Push(1);                       // new cell -> start at 1
    }
    // Thermal colour for a heat-map cell: 1 kill = blue (cold) ... 8+ kills = red (white-hot).
    Color HeatColor(int cnt)
    {
        double t = clamp(double(cnt - 1) / 7.0, 0.0, 1.0);   // 1..8 kills maps to 0..1
        return GITD_Palette.HSV(220.0 * (1.0 - t), 0.95, 1.0);   // blue (cold) -> red (white-hot)
    }
    // Per-tic: when the heat map is enabled, paint up to a BUDGET of the hottest cells as glow spots.
    override void WorldTick()
    {
        let cv = CVar.FindCVar("gitd_heatmap");
        if (!cv || !cv.GetBool()) return;
        int n = hmX.Size();
        if (n == 0) return;
        // [GITD] cap the heatmap's share of the engine's 16 glow-spot slots so per-shot floor
        // impacts + kill-numbers + death-FX are never starved out (the "floor effects stop after a
        // few shots" bug: the heatmap used to claim 10/16 every tic). Default 4 -> >=12 slots free.
        int cs = 96, budget = clamp(CIntDef("gitd_heatmap_budget", 10), 0, 10);
        Array<int> used; used.Resize(n);
        for (int i = 0; i < n; i++) used[i] = 0;
        // selection-sort the top `budget` cells by count (small n, so a partial selection scan is fine)
        for (int e2 = 0; e2 < budget; e2++)
        {
            int best = -1, bestc = 0;
            for (int i = 0; i < n; i++)
            {
                if (used[i] != 0) continue;                // already drawn this tic
                if (hmCount[i] > bestc) { bestc = hmCount[i]; best = i; }
            }
            if (best < 0) break;                           // no more cells with kills
            used[best] = 1;
            double wx = (double(hmX[best]) + 0.5) * cs;     // cell centre back in world units
            double wy = (double(hmY[best]) + 0.5) * cs;
            int cnt = hmCount[best];
            double radius = 70.0 + double(min(cnt, 8)) * 16.0;            // hotter zone -> wider bloom
            level.AddGlowSpotWiped(HeatColor(cnt), radius, wx, wy, 0, 0.0, 1.0, 0.0, 1);   // radial, floor
        }
    }

    // ---- Kill Counter: a combo streak that pops a glowing number at each kill ----
    // On each kill: advance the combo (reset if past the window), pick Combo-vs-Total, and pop a glow number.
    void KillCombo(Actor mo)
    {
        let kc = CVar.FindCVar("gitd_killcounter");
        if (!kc || !kc.GetBool()) return;
        mapKills++;                                          // running map total -- never resets (only on level load)
        int window = CIntDef("gitd_kill_window", 90);        // combo reset window (tics) -- user-controllable
        if (level.maptime - lastKillTic > window) combo = 0; // too long since last kill -> streak broken
        combo++;
        lastKillTic = level.maptime;
        int shown = (CIntDef("gitd_kill_count_mode", 0) == 1) ? mapKills : combo;   // 0 = Combo streak, 1 = Total map tally
        int ms = CIntDef("gitd_kill_milestone", 25);
        bool milestone = (ms > 0 && shown % ms == 0);        // every Nth = a gold pop
        Color col = NumberColor(shown, milestone);
        SpawnKillNumber(mo.pos, shown, col, milestone, mo.angle);   // glow number on the floor, locked to the monster's facing
    }
    // Pick the floor-number colour per gitd_kill_color mode (gold / cyan / heat-by-combo / spectrum).
    Color NumberColor(int c, bool milestone)
    {
        int mode = CIntDef("gitd_kill_color", 0);
        if (mode == 1) return Color(255, 255, 200, 40);                                   // Gold
        if (mode == 2) return milestone ? Color(255, 255, 200, 40) : Color(255, 60, 210, 255);  // Cyan, gold on milestone
        if (mode == 3) { double t = clamp(double(c) / 50.0, 0.0, 1.0); return GITD_Palette.HSV(220.0 * (1.0 - t), 0.95, 1.0); }  // Heatmap by combo
        if (mode == 4) { double h = double(c) * 37.0; h -= 360.0 * floor(h / 360.0); return GITD_Palette.HSV(h, 0.9, 1.0); }     // Spectrum
        return Color(255, 60, 210, 255);                                                  // Cyan (default)
    }
    // Build a GITD_SeamBox badge sized to the digit count, packing the number+colour-index for the shader.
    void SpawnKillNumber(Vector3 p, int num, Color col, bool big, double faceAngle)
    {
        int len = String.Format("%d", num).Length();                   // digit count -> badge width
        int cidx = NumberColorIdx(big);                                // shader palette index
        int packn = (num > 99999 ? 99999 : num) + cidx * 131072;       // number + colour packed for wgPk (131072 = 2^17, clears the 5-digit field)
        double halfH = (big ? 46.0 : 34.0);                            // badge half-height (fixed)
        double halfW = halfH * (0.60 + double(len) * 0.42);            // grows with digit count -> ellipse
        double aspect = halfW / halfH;
        double diag = sqrt(halfW * halfW + halfH * halfH);            // bounding radius for the glow spot
        Vector2 rd = (cos(faceAngle), sin(faceAngle));                 // LOCKED to the monster's facing, like the silhouette
        let sb = GITD_SeamBox(Actor.Spawn("GITD_SeamBox", (p.x, p.y, p.z)));
        if (sb)
        {
            sb.Setup(diag, packn, rd.x * aspect, rd.y * aspect, big);   // bake the aspect into the facing vector
            sb.vcol = col;                                              // Visual color for billboard mode
        }
    }
    // The shader palette index that pairs with each gitd_kill_color mode (badge tint).
    int NumberColorIdx(bool big)
    {
        int mode = CIntDef("gitd_kill_color", 0);
        if (mode == 1) return 1;                       // Gold
        if (mode == 2) return big ? 1 : 0;             // Cyan, gold on milestone
        if (mode == 3) return 2;                       // Heatmap -> red badge
        if (mode == 4) return 3;                       // Spectrum -> green badge (limited palette for now)
        return 0;                                      // Cyan
    }

    // BURST OF LIGHT ON HITTING ENEMIES -- weapon-agnostic. ONE light per monster (refreshed, never
    // stacked), follows the body, distance-culled, hard-capped -> spam-proof in a horde.
    // Damage hook: attach/refresh one GITD_HitLight on the struck monster (the hit-flash system).
    override void WorldThingDamaged(WorldEvent e)
    {
        let cv = CVar.FindCVar("gitd_hitlight");
        if (!cv || cv.GetInt() == 0) return;
        Actor mo = e.Thing;
        if (!mo || !mo.bIsMonster) return;

        // distance cull: skip hits far from the local player
        let pl = players[consoleplayer].mo;
        if (pl && (mo.pos - pl.pos).Length() > 1800.0) return;

        // prune dead entries + find a light already riding this monster
        GITD_HitLight existing = null;
        for (int i = hitLights.Size() - 1; i >= 0; i--)
        {
            let hl = hitLights[i];
            if (!hl) { hitLights.Delete(i); continue; }   // drop destroyed lights
            if (hl.mon == mo) existing = hl;              // this monster is already lit
        }
        impactCount++;
        Color c = ModeColor(HealthTier(mo), impactCount);
        let sc = CVar.FindCVar("gitd_hitlight_size"); int rad = sc ? sc.GetInt() : 140;

        if (existing) { existing.Refresh(c, rad); return; }   // already lit -> refresh, no second light
        if (hitLights.Size() >= 28) return;                   // hard cap (only reachable on a rocket-into-a-pile)
        let nl = GITD_HitLight(Actor.Spawn("GITD_HitLight", mo.pos + (0, 0, mo.height * 0.5)));
        if (nl) { nl.mon = mo; nl.Refresh(c, rad); hitLights.Push(nl); }
    }

    // [GITD] Which surface did this shot strike? Compare the puff's z to the floor/ceiling planes
    // beneath it so a weapon impact can glow the EXACT surface it hit (ceiling shot -> ceiling glow),
    // independent of the death-glow plane setting. Returns 1 floor / 2 ceiling / 0 = unknown (wall or
    // mid-air -> caller falls back to the gitd_death_planes cvar).
    int DetectHitPlane(Actor hit)
    {
        if (!hit || !hit.CurSector) return 0;
        double fz = hit.CurSector.floorplane.ZatPoint(hit.pos.xy);     // floor height under the hit
        double cz = hit.CurSector.ceilingplane.ZatPoint(hit.pos.xy);   // ceiling height under the hit
        double dF = abs(hit.pos.z - fz);                               // distance to the floor plane
        double dC = abs(hit.pos.z - cz);                               // distance to the ceiling plane
        if (dC <= dF) { if (dC < 24.0) return 2; }   // struck the ceiling plane
        else          { if (dF < 24.0) return 1; }   // struck the floor plane
        return 4;                                    // wall / mid-air -> use wall plane flag (4)
    }

    // SPARK IMPACTS -- catch every bullet puff as it spawns (wall/floor/ceiling hit, ANY weapon)
    // and drop the chosen HF burst there. Robust whether or not `replaces` works.
    // Spawn hook: when a BulletPuff appears, drop the chosen HF spark burst AND/OR a GITD glow-shape impact.
    override void WorldThingSpawned(WorldEvent e)
    {
        Actor a = e.Thing;
        if (!a || !(a is "BulletPuff")) return;

        // (1) SPARK BURST (HF sprites) at the hit point
        int st = CIntDef("gitd_impactspark", 0);
        if (st > 0)
        {
            // st 7 = "Random": hash position+time into a 1..6 type so each hit varies; else use the fixed type
            int t = (st >= 7) ? 1 + (level.maptime + int(a.pos.x) * 3 + int(a.pos.y) * 7) % 6 : st;
            Actor.Spawn(HF_ImpactTypePicker.ClassFor(t), a.pos, ALLOW_REPLACE);
        }

        // (2) GLOW-SHAPE impact (gitd_impact_style) -- now works for HITSCAN too (floor/ceiling)
        int istyle = CIntDef("gitd_impact_style", 0);
        if (istyle > 0)
        {
            impactCount++;
            int s = (istyle == 11) ? 1 + (impactCount * 7) % 6 : istyle;   // 11 = Random (shapes 1-6); 12 = Inverse (pass through)
            let fx = GITD_DeathEffect(Actor.Spawn(ImpactClass(s), a.pos));
            if (fx)
            {
                fx.isImpact = true; fx.impactPlane = DetectHitPlane(a); fx.bornTic = level.totaltime; fx.tier = 0;   // impact context: no tier, no monster; glow the struck surface
                fx.tint = ModeColor(0, impactCount); fx.faceAngle = a.angle;
                fx.killCount = impactCount; fx.mon = null; fx.EffectSpawn();
                TrackImpact(fx);   // [GITD] recycle oldest past the cap -> full-auto spray stays alive
            }
        }
    }

    // Death hook: the main dispatcher -- route projectiles to impact stamps, monsters to death FX + accents.
    override void WorldThingDied(WorldEvent e)
    {
        Actor mo = e.Thing;
        if (!mo) return;
        if (mo.bMissile) { SpawnImpactFX(mo); return; }   // a projectile hit something -> impact stamp (gitd_impact_style)
        if (mo.bIsMonster) HeatAccumulate(mo.pos.x, mo.pos.y);   // [GITD] battlefield memory: log every monster kill
        if (mo.bIsMonster) KillCombo(mo);                         // [GITD] kill-counter combo number
        let cv = CVar.FindCVar("gitd_death_enabled");
        if (cv && !cv.GetBool()) return;                          // death FX globally off (heat map/counter still ran above)
        if (!mo.bIsMonster) return;
        killCount++;

        int tier; string kw; Color tint;
        [tier, kw, tint] = Resolve(mo);                           // resolve the death context

        let fx = GITD_DeathEffect(Actor.Spawn(PickEffect(mo, kw, tier), mo.pos));
        if (fx)
        {
            // stamp the resolved context onto the effect, THEN fire EffectSpawn (which reads it)
            fx.bornTic   = level.totaltime;
            fx.tier      = tier;
            fx.tint      = tint;
            fx.keywords  = kw;
            fx.faceAngle = mo.angle;
            fx.killCount = killCount;
            fx.mon       = mo;
            fx.EffectSpawn();   // now that the context (mon/tint/face) is set
        }

        // ACCENT layer: an optional garnish fired alongside the primary (gitd_death_accent).
        int acc = CIntDef("gitd_death_accent", 0);
        if (acc > 0)
        {
            string ac = (acc == 1) ? "GITD_FX_AccentLightning" : (acc == 2) ? "GITD_FX_AccentShrapnel" : "GITD_FX_AccentSparks";
            let ax = GITD_DeathEffect(Actor.Spawn(ac, mo.pos));
            if (ax)
            {
                ax.bornTic = level.totaltime; ax.tier = tier; ax.tint = tint; ax.keywords = kw;
                ax.faceAngle = mo.angle; ax.killCount = killCount; ax.mon = mo; ax.EffectSpawn();
            }
        }
    }

    // Choose the death-effect class: explicit class-name cvar wins, else style index (14 = random-per-kill).
    string PickEffect(Actor mo, string kw, int tier)
    {
        let sc = CVar.FindCVar("gitd_death_style_class");
        if (sc) { string cn = sc.GetString(); if (cn.Length() > 0 && cn != "0") return cn; }   // direct class override
        int st = CIntDef("gitd_death_style", 0);
        if (st == 14)   // Random: a different style every kill (hash the kill count)
        {
            int h = killCount * 374761393 + 668265263; h = (h ^ (h >> 13)) * 1274126177; h = h ^ (h >> 16);  // integer hash
            st = (h & 0x7FFFFFFF) % 14;
        }
        return StyleClass(st);
    }
    // Map a death-style index (0..13) to its effect class name.
    static string StyleClass(int s)
    {
        switch (s)
        {
            case 1:  return "GITD_FX_SeamReveal";
            case 2:  return "GITD_FX_GhostWalk";
            case 3:  return "GITD_FX_DeathPing";
            case 4:  return "GITD_FX_StylizedX";
            case 5:  return "GITD_FX_HexField";
            case 6:  return "GITD_FX_HexRings";
            case 7:  return "GITD_FX_Spiral";
            case 8:  return "GITD_FX_Detector";
            case 9:  return "GITD_FX_Firework";
            case 10: return "GITD_FX_SquareRings";
            case 11: return "GITD_FX_Star";
            case 12: return "GITD_FX_Sunburst";
            case 13: return "GITD_FX_Grid";
            default: return "GITD_FX_DeathPool";   // 0 / unknown = the default pool
        }
    }

    // Resolve the death context: tier from health + (unused-here) keywords + the mode colour.
    int, string, Color Resolve(Actor mo)
    {
        int tier = HealthTier(mo);
        return tier, "", ModeColor(tier, killCount);
    }

    // colour from the active colour-mode, no monster required (deaths AND impacts use this)
    // gitd_death_color_mode: 0 = tier ramp, 1 = fixed cvar colour, 2 = hashed random, 3 = per-seed spectrum.
    Color ModeColor(int tier, int seed)
    {
        int mode = CIntDef("gitd_death_color_mode", 0);
        if (mode == 1)
        {
            int v = CIntDef("gitd_death_color", 0x00C8FF);   // packed 0xRRGGBB, default cyan
            return Color(255, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF);
        }
        if (mode == 2) return GITD_Palette.Random(seed);
        if (mode == 3) { double h = double(seed) * 47.0; h -= 360.0 * floor(h / 360.0); return GITD_Palette.HSV(h, 0.9, 1.0); }  // 47deg per-seed spectrum step
        return GITD_Palette.ForTier(tier, 4);   // default: tier ramp
    }

    // a weapon impact stamps the chosen GITD shape at the hit point (no monster, no silhouette).
    // Projectile-impact path (called from WorldThingDied for missiles); mirrors the puff path's glow stamp.
    void SpawnImpactFX(Actor missile)
    {
        // [GITD] SPARK BURST on the projectile impact too. Hitscan gets this via the BulletPuff hook,
        // but plasma/rockets never spawn a puff -- so without this they produced no spark reaction.
        // Done before the glow-shape early-return so sparks fire even when impact SHAPES are off.
        int sp = CIntDef("gitd_impactspark", 0);
        if (sp > 0)
        {
            int t = (sp >= 7) ? 1 + (level.maptime + int(missile.pos.x) * 3 + int(missile.pos.y) * 7) % 6 : sp;
            Actor.Spawn(HF_ImpactTypePicker.ClassFor(t), missile.pos, ALLOW_REPLACE);
        }

        int istyle = CIntDef("gitd_impact_style", 0);
        if (istyle <= 0) return;                 // glow shape off (sparks already handled above)
        impactCount++;
        if (istyle == 11)                        // Random impact shape
        {
            int h = impactCount * 374761393 + 668265263; h = (h ^ (h >> 13)) * 1274126177; h = h ^ (h >> 16);  // integer hash
            istyle = 1 + (h & 0x7FFFFFFF) % 10;
        }
        let fx = GITD_DeathEffect(Actor.Spawn(ImpactClass(istyle), missile.pos));
        if (fx)
        {
            fx.isImpact  = true;
            fx.impactPlane = DetectHitPlane(missile);   // glow the exact surface the projectile struck
            fx.bornTic   = level.totaltime;
            fx.tier      = 0;
            fx.tint      = ModeColor(0, impactCount);
            fx.faceAngle = missile.angle;
            fx.killCount = impactCount;          // independent variety from kills
            fx.mon       = null;                 // -> no silhouette
            fx.EffectSpawn();
            TrackImpact(fx);   // [GITD] recycle oldest past the cap -> full-auto spray stays alive
        }
    }
    // Map an impact-style index to its glow-effect class (note the index<->class mapping differs from
    // StyleClass: impacts reuse the death FX shapes plus the InvertImpact special at 12).
    string ImpactClass(int istyle)
    {
        switch (istyle)
        {
            case 2:  return "GITD_FX_DeathPing";   // ring
            case 3:  return "GITD_FX_StylizedX";
            case 4:  return "GITD_FX_HexField";
            case 5:  return "GITD_FX_HexRings";
            case 6:  return "GITD_FX_Spiral";
            case 7:  return "GITD_FX_SquareRings";
            case 8:  return "GITD_FX_Star";
            case 9:  return "GITD_FX_Sunburst";
            case 10: return "GITD_FX_Grid";
            case 12: return "GITD_FX_InvertImpact";   // inverse glow within radius
            default: return "GITD_FX_DeathPool";   // 1 = glow
        }
    }

    // Read an int cvar with a fallback default (the float twin is GFloat on the effect base class).
    static int CIntDef(string n, int def) { let c = CVar.FindCVar(n); return c ? c.GetInt() : def; }
    // Classify a monster into a threat tier 0..3 from its boss flag / spawn health (drives tier colour + size).
    static int HealthTier(Actor mo)
    {
        if (!mo) return 0;
        if (mo.bBOSS || mo.SpawnHealth() >= 1000) return 3;   // boss / very tanky
        if (mo.SpawnHealth() >= 300) return 2;                // heavy
        if (mo.SpawnHealth() >= 120) return 1;                // medium
        return 0;                                             // fodder
    }
    // Read-only accessor for the running kill count (for HUD/other scripts).
    int GetKillCount() const { return killCount; }
}


// ==== PORTED FROM HF (hf_impact_types.zs) -- bright additive spark bursts, no dynamic lights ====
// ============================================================================
// hf_impact_types.zs -- WALL IMPACT TYPES (selectable feel for hitting a wall).
//
// Built entirely from HF's own sprites (DPUF/LPUF/SMOK/HFPF/SPRK) using punchy
// state-machine TECHNIQUES (not copied art):
//   - GROW-RAMP : A_SetScale increments each tic so the burst ERUPTS outward.
//   - FRAME-MARCH: many frames played fast = smooth, lively animation.
//   - RANDOM FLIP: A_SetScale with random signs -> no two impacts look alike.
//   - FADE-TAIL : hold a frame while A_FadeOut -> lingering smoke/dust.
//
// One selector cvar (hf_impact_type) routes the wall hit to a Type. Each Type
// is a single "burst" actor that composes the look; the dispatcher just spawns
// the chosen one. Add a Type = add a class + a case + a menu line.
//
//   1  Sparks      -- classic: kicked bright sparks, quick flash
//   2  Eruption    -- grow-ramp flash that blooms big then fades (punchy)
//   3  Dust Puff   -- earthy: dense smoke frame-march, low sparks (concrete feel)
//   4  Flak Burst  -- lots of fast random-flipped sparks, sharp pop (metal feel)
//   5  Scorch      -- dark smoke billow + ember glow, lingering (heavy feel)
//   6  Firecracker -- chaotic multi-pop: several offset mini-bursts (chained)
// ============================================================================
// NOTE: unlike the GITD glow effects above, these HF bursts ARE real sprite
// actors (additive puffs/smoke/embers) -- they are GITD's hard "no dynamic
// lights" rule still holds (RenderStyle Add, not a light), just sprite-based.

// ---- shared bits -----------------------------------------------------------

// A single kicked spark. Random scale+flip on spawn so each is unique.
class HF_ImpSpark : Actor
{
	Default
	{
		// Tiny bouncy clientside-only additive projectile -- a kicked spark that ricochets off walls.
		Radius 1; Height 1; Projectile;
		-NOGRAVITY +THRUACTORS +BOUNCEONWALLS +FORCEXYBILLBOARD +CLIENTSIDEONLY +DONTSPLASH;
		Gravity 0.4;
		BounceFactor 0.3;
		RenderStyle "Add";
		Scale 0.18;
		Alpha 1.0;
	}
	// Randomize scale + mirror per spark so no two look identical.
	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		// RANDOM FLIP technique: random sign on each axis -> sprite mirrored.
		double sx = (random(0,1) ? 1.0 : -1.0) * FRandom(0.14, 0.24);
		double sy = (random(0,1) ? 1.0 : -1.0) * FRandom(0.14, 0.24);
		scale = (sx, sy);
	}
	States
	{
	Spawn:
		// quick bright flicker that fades as it flies
		LPUF A 2 Bright A_FadeOut(0.06);
		LPUF B 2 Bright A_FadeOut(0.08);
		LPUF CD 2 Bright A_FadeOut(0.10);
		Loop;
	Death:
		Stop;
	}
}

// Smoke curl: dense SMOK frame-march that GROWS and fades (dust/scorch tail).
class HF_ImpSmoke : Actor
{
	Default
	{
		+NOGRAVITY +NOINTERACTION +FORCEXYBILLBOARD +CLIENTSIDEONLY;
		RenderStyle "Translucent";
		Alpha 0.35;
		Scale 0.2;
	}
	// Random horizontal mirror for variety.
	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		// random flip for variety
		if (random(0,1)) scale.x = -scale.x;
	}
	States
	{
	Spawn:
		// FRAME-MARCH + GROW-RAMP: step through SMOK frames while expanding.
		SMOK ABCDEFGH 2 { A_SetScale(scale.x*1.07, abs(scale.y)*1.07); vel.z += 0.04; }   // grow + drift up
		SMOK IJKLMNOP 2 { A_SetScale(scale.x*1.05, abs(scale.y)*1.05); A_FadeOut(0.06); } // keep growing while fading
		Stop;
	}
}

// Ember: a small glowing mote that drifts and fades (scorch/fire feel).
class HF_ImpEmber : Actor
{
	Default
	{
		+NOGRAVITY +NOINTERACTION +BRIGHT +FORCEXYBILLBOARD +CLIENTSIDEONLY;
		RenderStyle "Add";
		Alpha 0.9;
		Scale 0.12;
	}
	// Tint orange, switch to additive-shaded, and give it a random upward drift.
	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		SetShade("FF 80 20");   // ember orange
		A_SetRenderStyle(alpha, STYLE_AddShaded);   // additive + the shade tint
		vel = (FRandom(-1,1), FRandom(-1,1), FRandom(0.5,2.0));   // float upward, scatter sideways
	}
	States
	{
	Spawn:
		DPUF ABCDE 3 Bright A_FadeOut(0.08);
		Stop;
	}
}

// ---------------------------------------------------------------------------
// IMPACT INTENSITY -- a per-hit scalar (typically ~0.6 to ~1.8) that scales
// each Type's spark count, spread and flash size, so hits vary in punch.
// Sources (hf_impact_intensity cvar):
//   0 Fixed   -- always 1.0 (every hit identical)
//   1 Varied  -- random 0.7..1.5 per hit (no two look the same)
//   2 Dynamic -- random base, biased up; meant to scale with weapon power
// ---------------------------------------------------------------------------
// Base class for the six burst Types: rolls a per-hit intensity and exposes Scaled() to size counts/flash.
class HF_ImpactBase : Actor
{
	double intensity;
	Default { +NOINTERACTION +CLIENTSIDEONLY; }
	// Roll this hit's intensity and pre-scale the burst's own sprite to match.
	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		intensity = HF_ImpactIntensity.Roll();
		// scale the burst's own sprite up with intensity (2x toggle -> bigger flash)
		scale.x *= intensity;
		scale.y *= intensity;
	}
	// scale an int count by intensity, clamped to at least 1
	int Scaled(int base) { return max(1, int(round(base * intensity))); }
}

// Picks each hit's intensity multiplier from the hf_impact_intensity mode (+ optional 2x toggle).
class HF_ImpactIntensity
{
	// TODO(GlowInTheDark): dynamically adjust impact COLOR (and possibly
	// intensity) from GlowInTheDark's parameters. Hook the GITD query in here
	// so each impact tints to match the GITD lighting/value at the hit point.
	// (User to explain GITD's parameters; wire color source here.)
	static double Roll()
	{
		double mult = 1.0;
		CVar dbl = CVar.FindCVar("hf_impact_double");
		if (dbl && dbl.GetBool()) mult = 2.0;   // 2x size+punch toggle

		CVar c = CVar.FindCVar("hf_impact_intensity");
		int mode = c ? c.GetInt() : 1;
		if (mode == 0) return 1.0 * mult;                  // Fixed
		if (mode == 2) return FRandom(0.9, 1.8) * mult;    // Dynamic (biased big)
		return FRandom(0.7, 1.5) * mult;                   // Varied (default)
	}
}



// TYPE 1 -- SPARKS (classic clean: flash + a handful of kicked sparks)
class HF_ImpType1 : HF_ImpactBase
{
	Default { RenderStyle "Add"; Scale 0.5; }
	// Kick a few sparks (count scaled by intensity) and play the flash.
	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		int n = Scaled(3 + random(0,2));
		for (int i=0;i<n;i++) KickSpark(3.5*intensity, 5.0*intensity);   // spread + upward kick scale with intensity
	}
	// Spawn one spark with random horizontal spread and an upward kick.
	void KickSpark(double xy, double up)
	{
		Actor s = Spawn("HF_ImpSpark", pos, ALLOW_REPLACE);
		if (s) { s.vel.x=FRandom(-xy,xy); s.vel.y=FRandom(-xy,xy); s.vel.z=FRandom(1,up); }
	}
	States
	{
	Spawn:
		HFPF A 2 Bright A_SetScale(0.5*intensity, 0.5*intensity);
		HFPF B 3 Bright A_FadeOut(0.4);
		Stop;
	}
}

// TYPE 2 -- ERUPTION (grow-ramp flash that blooms BIG then fades: the punchy one)
class HF_ImpType2 : HF_ImpactBase
{
	Default { RenderStyle "Add"; Scale 0.2; Alpha 1.0; }
	// Fling a fan of fast sparks, then let the state machine grow-ramp the flash.
	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		int n = Scaled(4);
		for (int i=0;i<n;i++)
		{
			Actor s = Spawn("HF_ImpSpark", pos, ALLOW_REPLACE);
			if (s) { s.vel.x=FRandom(-4,4)*intensity; s.vel.y=FRandom(-4,4)*intensity; s.vel.z=FRandom(2,6)*intensity; }
		}
	}
	States
	{
	Spawn:
		// GROW-RAMP: scale climbs every tic -> the flash erupts outward.
		DPUF A 1 Bright A_SetScale(0.25*intensity,0.25*intensity);
		DPUF A 1 Bright A_SetScale(0.45*intensity,0.45*intensity);
		DPUF B 1 Bright A_SetScale(0.65*intensity,0.65*intensity);
		DPUF B 1 Bright A_SetScale(0.85*intensity,0.85*intensity);
		DPUF C 2 Bright { A_SetScale(1.0*intensity,1.0*intensity); A_FadeOut(0.25); }
		DPUF D 2 Bright A_FadeOut(0.4);
		Stop;
	}
}

// TYPE 3 -- DUST PUFF (concrete/earth: dense smoke march, few low sparks)
class HF_ImpType3 : HF_ImpactBase
{
	// One or two smoke curls (more on a strong hit) + a couple of low sparks.
	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		Spawn("HF_ImpSmoke", pos, ALLOW_REPLACE);
		if (random(0,255) > 100 || intensity > 1.2) Spawn("HF_ImpSmoke", pos, ALLOW_REPLACE);   // extra puff ~60% or on strong hits
		int n = Scaled(1 + random(0,2));
		for (int i=0;i<n;i++)
		{
			Actor s = Spawn("HF_ImpSpark", pos, ALLOW_REPLACE);
			if (s) { s.vel.x=FRandom(-2,2); s.vel.y=FRandom(-2,2); s.vel.z=FRandom(0.5,2.5); }   // low, gentle sparks
		}
	}
	States { Spawn: TNT1 A 1; Stop; }   // invisible driver; all visuals are the spawned sub-actors
}

// TYPE 4 -- FLAK BURST (metal: many fast random-flipped sparks + sharp pop)
class HF_ImpType4 : HF_ImpactBase
{
	Default { RenderStyle "Add"; Scale 0.4; }
	// Fling a dense fan of fast sparks for a sharp metallic pop.
	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		int n = Scaled(7 + random(0,5));   // dense
		for (int i=0;i<n;i++)
		{
			Actor s = Spawn("HF_ImpSpark", pos, ALLOW_REPLACE);
			if (s) { s.vel.x=FRandom(-6,6); s.vel.y=FRandom(-6,6); s.vel.z=FRandom(1,7); }   // wide, fast spread
		}
	}
	States
	{
	Spawn:
		HFPF A 1 Bright A_SetScale(0.6*intensity, 0.6*intensity);
		HFPF B 2 Bright A_FadeOut(0.5);
		Stop;
	}
}

// TYPE 5 -- SCORCH (heavy: dark smoke billow + ember glow, lingering)
class HF_ImpType5 : HF_ImpactBase
{
	// Two smoke billows + a scatter of drifting embers for a heavy lingering scorch.
	override void PostBeginPlay()
	{
		Super.PostBeginPlay();
		Spawn("HF_ImpSmoke", pos, ALLOW_REPLACE);
		Spawn("HF_ImpSmoke", pos, ALLOW_REPLACE);
		int n = Scaled(4 + random(0,3));
		for (int i=0;i<n;i++) Spawn("HF_ImpEmber", pos, ALLOW_REPLACE);
		Actor f = Spawn("HF_ImpEmber", pos, ALLOW_REPLACE);   // one guaranteed extra ember
	}
	States { Spawn: TNT1 A 1; Stop; }
}

// TYPE 6 -- FIRECRACKER (chaotic: several offset mini-pops over a few tics)
class HF_ImpType6 : HF_ImpactBase
{
	int pops;
	override void PostBeginPlay() { Super.PostBeginPlay(); pops = 0; }
	// One offset mini-burst: a small Type1 flash + a few sparks at a jittered position.
	void MiniPop()
	{
		// a small offset burst of sparks + a tiny flash
		Vector3 off = (FRandom(-12,12), FRandom(-12,12), FRandom(-8,8));
		Actor fl = Spawn("HF_ImpType1", pos + off, ALLOW_REPLACE);
		int n = 2 + random(0,2);
		for (int i=0;i<n;i++)
		{
			Actor s = Spawn("HF_ImpSpark", pos + off, ALLOW_REPLACE);
			if (s) { s.vel.x=FRandom(-4,4); s.vel.y=FRandom(-4,4); s.vel.z=FRandom(1,5); }
		}
	}
	States
	{
	Spawn:
		// chain four mini-pops over ~10 tics; the last one is only ~50% likely (ragged tail)
		TNT1 A 2 { MiniPop(); }
		TNT1 A 2 { MiniPop(); }
		TNT1 A 3 { MiniPop(); }
		TNT1 A 3 { if (random(0,255) > 120) MiniPop(); }
		Stop;
	}
}

// ---------------------------------------------------------------------------
// IMPACT TYPE DISPATCH -- pick the burst class for the chosen hf_impact_type.
// ---------------------------------------------------------------------------
// Maps the hf_impact_type index (1..6) to its burst class name; defaults to Sparks.
class HF_ImpactTypePicker
{
	static string ClassFor(int t)
	{
		switch (t)
		{
			case 1:  return "HF_ImpType1";   // Sparks
			case 2:  return "HF_ImpType2";   // Eruption
			case 3:  return "HF_ImpType3";   // Dust Puff
			case 4:  return "HF_ImpType4";   // Flak Burst
			case 5:  return "HF_ImpType5";   // Scorch
			case 6:  return "HF_ImpType6";   // Firecracker
			default: return "HF_ImpType1";
		}
	}
}


// Spark impacts are spawned by the handler's WorldThingSpawned hook (catches the BulletPuff as it
// spawns -- robust whether or not `replaces` is honored at puff-spawn).
