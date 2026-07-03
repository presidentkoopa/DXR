class VoxelParticle : Actor
{
    Default
    {
        +NOBLOCKMAP
        +NOGRAVITY
        +DONTSPLASH
        +NOINTERACTION
        +CLIENTSIDEONLY
        RenderStyle "Add";
        Alpha 0.8;
        Scale 0.05;
    }

    States
    {
    Spawn:
        VOXL A 1 Bright 
        {
            // Gravitate toward player's weapon position
            if (players[consoleplayer].mo)
            {
                Actor pmo = players[consoleplayer].mo;
                // Simple attraction logic
                Vector3 target = pmo.Pos + (0, 0, players[consoleplayer].viewheight - 10);
                Vector3 dir = target - Pos;
                double dist = dir.Length();
                
                if (dist < 8) { Destroy(); return; }
                
                vel = dir.Unit() * 12;
            }
            A_FadeOut(0.01);
        }
        Loop;
    }
}

extend class StateProvider
{
    action void A_DataSiphonEquip()
    {
        if (!player || !player.mo) return;
        
        A_StartSound("system/powerup", CHAN_WEAPON, CHANF_UI);
        
        int fidelity = CVar.GetCVar("vr_visual_fidelity", player).GetInt();
        int vCount = 10 + (fidelity * 15); // 10, 25, 40, 55 particles
        
        for (int i = 0; i < vCount; i++)
        {
            // Spawn around the player and have them fly in
            Vector3 spawnPos = player.mo.Pos + (
                frandom(-64, 64), 
                frandom(-64, 64), 
                frandom(0, 96)
            );
            Actor.Spawn("VoxelParticle", spawnPos);
        }
    }
}
