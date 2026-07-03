class VRSigilGraphic : Actor
{
    int visualHash;
    float complexity;
    vector3 sigilColor;
    int lifeTimer;

    Default
    {
        +NOBLOCKMAP
        +NOGRAVITY
        +DONTSPLASH
        +NOINTERACTION
        +CLIENTSIDEONLY
        +FORCEXYBILLBOARD
        RenderStyle "Add";
        Alpha 1.0;
        Scale 0.2;
    }

    override void Tick()
    {
        if (lifeTimer-- <= 0)
        {
            Destroy();
            return;
        }

        // Set to our registered SIGL sprite
        sprite = GetSpriteIndex("SIGL");
        frame = 0;

        // Pass parameters to shader via u_IsMSDF and u_MSDFGlitch
        msdf_enabled = visualHash;
        msdf_glitch = complexity;
        msdf_color = sigilColor;

        // Float upwards
        SetOrigin(Pos + (0, 0, 1.0), true);
        
        // Fade out
        if (lifeTimer < 20)
        {
            Alpha = lifeTimer / 20.0;
        }
    }
}

class VRSigilManager play
{
    static void SpawnSigil(Actor target, String keywords, String weaponKeywords)
    {
        int hash = 0;
        // Base Customization
        float baseComplexity = CVar.GetCVar("vr_sigil_base_complexity", players[consoleplayer]).GetFloat();
        bool doRandom = CVar.GetCVar("vr_sigil_randomize_patterns", players[consoleplayer]).GetBool();
        
        float complexity = baseComplexity;
        vector3 clr = (0.0, 0.0, 0.0);   // was CVar.GetColor() (no such method); real value is set from GetInt() at line ~66
        
        // Convert color int to vector3 float
        int cDefault = CVar.GetCVar("vr_sigil_color_default", players[consoleplayer]).GetInt();
        int cHead = CVar.GetCVar("vr_sigil_color_head", players[consoleplayer]).GetInt();
        int cLegs = CVar.GetCVar("vr_sigil_color_legs", players[consoleplayer]).GetInt();
        
        clr = ((cDefault >> 16) & 255, (cDefault >> 8) & 255, cDefault & 255) / 255.0;

        // Map keywords to visual traits
        if (keywords.IndexOf("dmg:fire") != -1 || weaponKeywords.IndexOf("dmg:fire") != -1) { hash |= 0; clr = (1.0, 0.4, 0.0); }
        if (keywords.IndexOf("anatomy:cybernetic") != -1) { hash |= 1; complexity += 0.4; }
        if (keywords.IndexOf("role:boss") != -1) { hash |= 3; complexity += 0.5; }
        if (keywords.IndexOf("trait:demonic") != -1) { hash |= 2; clr = (1.0, 0.0, 0.0); }
        
        // Locational Visual Overrides
        if (keywords.IndexOf("head") != -1) { 
            hash |= 8; complexity += 0.3; 
            clr = ((cHead >> 16) & 255, (cHead >> 8) & 255, cHead & 255) / 255.0; 
        }
        if (keywords.IndexOf("legs") != -1) { 
            hash |= 16; complexity -= 0.1; 
            clr = ((cLegs >> 16) & 255, (cLegs >> 8) & 255, cLegs & 255) / 255.0; 
        }
        
        // Hand Tracking Visuals
        if (keywords.IndexOf("hand:off") != -1) { hash |= 32; complexity += 0.2; }
        
        // Randomization
        if (doRandom)
        {
            hash ^= random[sigils](0, 255);
            complexity += frandom[sigils](-0.1, 0.1);
        }        
        // Weapon styles
        if (weaponKeywords.IndexOf("style:precision") != -1) hash |= 4;
        if (weaponKeywords.IndexOf("style:rapid") != -1) complexity += 0.2;

        VRSigilGraphic sigil = VRSigilGraphic(Actor.Spawn("VRSigilGraphic", target.Pos + (0, 0, target.Height + 20)));
        if (sigil)
        {
            sigil.visualHash = hash;
            sigil.complexity = complexity;
            sigil.sigilColor = clr;
            sigil.lifeTimer = 70;
        }
    }
}
