class GITD_SDFImp : DoomImp
{
    float matrix_glitch;
    int   matrix_id;
    float matrix_alpha;

    Default
    {
        +BRIGHT;
        RenderStyle "Add";
        Alpha 0.8;
    }

    override void PostBeginPlay()
    {
        Super.PostBeginPlay();
        matrix_id = random(100, 999);
        matrix_glitch = 0.0;
        matrix_alpha = 1.0;
        
        // Use the SIGL sprite which we use as a 'bounding box' for the SDF shader
        sprite = GetSpriteIndex("SIGL");
    }

    override void Tick()
    {
        Super.Tick();
        
        // Handle logic for 'reconstruction'
        if (target != NULL)
        {
            // Alert: bits pull together
            matrix_glitch = max(0.0, matrix_glitch - 0.05);
        }
        else
        {
            // Idle: bits drift
            matrix_glitch = min(1.0, matrix_glitch + 0.01);
        }

        // Damage pulse
        if (health < spawnhealth())
        {
            matrix_glitch += 0.1;
        }

        // Pass to shader
        // u_IsMSDF bit 9 (512) signals "Monster Mode"
        msdf_enabled = 512 | (matrix_id % 16);
        msdf_glitch = matrix_glitch;
        msdf_color = (0.2, 0.8, 1.0); // Cyan data-ghost
    }

    override void Die(Actor source, Actor inflictor, int dmgflags, Name MeansOfDeath)
    {
        // Don't die immediately; enter a 'shatter' state
        Super.Die(source, inflictor, dmgflags, MeansOfDeath);
    }
}

// Replacement for the standard Imp if the user wants it global, 
// but for now we'll just keep it as a new actor they can spawn.
class GITD_SDFImp_Shatter : Actor
{
    float glitch;
    Default
    {
        +NOBLOCKMAP; +NOGRAVITY; +NOINTERACTION;
        RenderStyle "Add";
        Alpha 1.0;
    }
    States
    {
        Spawn:
            SIGL A 1 {
                invoker.glitch += 0.1;
                A_FadeOut(0.05);
                msdf_enabled = 512 | 16; // Shatter mode
                msdf_glitch = invoker.glitch;
            }
            Loop;
    }
}
