
extend class Actor
{
    String lastHitZone;
    String lastHitHand;
}

class VRLocationalArbiter : StaticEventHandler
{
    override void WorldThingDamaged(WorldEvent e)
    {
        if (!e.Thing || e.Damage <= 0 || !e.DamageSource) return;
        
        // We only care about attacks on shootable actors (monsters/players)
        if (!e.Thing.bShootable) return;

        // Calculate the hit ratio along the mathematical cylinder height
        // HitLocation is populated by the engine during LineAttack/FastProjectile impact
        double victimZ = e.Thing.Pos.Z;
        double victimHeight = e.Thing.Height;
        
        if (victimHeight <= 0) return;

        double hitZ = e.Thing.HitLocation.Z;
        double zRatio = (hitZ - victimZ) / victimHeight;

        // Fetch dynamic bounds from CVars
        double headThreshold = CVar.GetCVar("vr_locational_head_threshold").GetFloat();
        double legThreshold = CVar.GetCVar("vr_locational_leg_threshold").GetFloat();
        double headMult = CVar.GetCVar("vr_locational_head_mult").GetFloat();
        double legMult = CVar.GetCVar("vr_locational_leg_mult").GetFloat();

        int damageMultiplier = 1.0;
        String zoneTag = "torso";

        // Dynamic Bounding Logic
        if (zRatio > headThreshold)
        {
            // HEADSHOT
            zoneTag = "head";
            e.NewDamage = e.Damage * headMult;
            
            // Detect Hand Source for Combo System
            String handTag = "hand:main";
            Weapon weap = Weapon(e.Inflictor); // For hitscans, Inflictor is often the weapon or source
            if (!weap && e.Inflictor) weap = Weapon(e.Inflictor.master); // For projectiles, check master
            
            if (weap && weap.bOffhandWeapon) handTag = "hand:off";
            
            e.Thing.lastHitZone = "head";
            e.Thing.lastHitHand = handTag;

            if (e.Thing.Health <= 0 || (e.Thing.Health - e.NewDamage <= 0))
            {
                // Sigil spawning is now handled by SDFComboArbiter on death to prevent duplicates
                e.Thing.A_StartSound("vr/critical_hit", CHAN_AUTO, CHANF_OVERLAP);
            }
        }
        else if (zRatio < legThreshold)
        {
            // LEGSHOT
            zoneTag = "legs";
            e.NewDamage = e.Damage * legMult;
            
            e.Thing.lastHitZone = "legs";
            
            // Stumble Logic
            if (e.Thing.bIsMonster && !e.Thing.bNoPain)
            {
                e.Thing.TriggerPainChance("Pain", true);
                e.Thing.Vel.XY *= 0.1; // Massive speed reduction for stumble
            }
        }
        else
        {
            // TORSO
            zoneTag = "torso";
            e.NewDamage = e.Damage;
            e.Thing.lastHitZone = "torso";
        }

        // Debug output if enabled
        if (CVar.GetCVar("vr_debug_locational").GetBool())
        {
            Console.Printf("Hit Zone: %s | Ratio: %.2f | Final Damage: %d", zoneTag, zRatio, e.NewDamage);
        }
    }
}
