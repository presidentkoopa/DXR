#!/usr/bin/env python3
# Builds XR_WristThruster.pk3 - a prototype VR wrist thruster (double-jump-ish).
# Loads on the CURRENT engine build (uses only baked natives: OffhandPos/OffhandDir/
# OffhandAngle/OffhandPitch, Vel, Mass, player.cmd). Placeholder visuals: a small blue
# Stencil "cube" following the wrist + a downward wireframe-ish burst of blue sparks.
#
# Usage:  python build_wristthruster.py XR_WristThruster.pk3
#         doomxr.exe -file XR_WristThruster.pk3 [+map ...]   (great combined with GRAVCOASTER.pk3)
import sys, io, zipfile

ZSCRIPT = r'''version "4.10"

// ---- placeholder wrist unit: a small blue glow that follows the off-hand ----
// (stand-in for a proper cube MODEL later; Stencil billboard is the proven VR-visible path.)
class XR_ThrusterCube : Actor
{
    Default
    {
        +NOGRAVITY +NOCLIP +NOBLOCKMAP +NOINTERACTION +DONTSPLASH +NOTIMEFREEZE
        +FORCEXYBILLBOARD +CLIENTSIDEONLY
        RenderStyle "Stencil"; Alpha 0.9; Scale 0.10;
    }
    override void PostBeginPlay() { Super.PostBeginPlay(); SetShade("40 A0 FF"); } // plasma blue
    States { Spawn: BAL1 A -1 Bright; Stop; }
}

// ---- one burst spark (placeholder for a wireframe VFX) ----
class XR_ThrusterSpark : Actor
{
    Default
    {
        +NOGRAVITY +NOBLOCKMAP +DONTSPLASH +FORCEXYBILLBOARD +CLIENTSIDEONLY +NOINTERACTION +MISSILE
        RenderStyle "Stencil"; Alpha 1.0; Scale 0.08;
    }
    override void PostBeginPlay() { Super.PostBeginPlay(); SetShade("50 B0 FF"); }
    States
    {
    Spawn:
        BAL1 A 1 Bright;
        BAL1 A 1 Bright A_FadeOut(0.12);
        Loop;
    }
}

// ============================================================================
//  XR_WristThruster - the power. Auto-given. Fires on the JUMP button.
//  Impulse = mass-scaled deltaV along -OffhandDir; cancels opposing velocity,
//  keeps perpendicular momentum. Charges recharge on the ground.
// ============================================================================
class XR_WristThruster : Inventory
{
    int  charges;
    bool prevFire;
    XR_ThrusterCube cube;

    Default
    {
        Inventory.Amount 1;
        Inventory.MaxAmount 1;
        +INVENTORY.UNDROPPABLE
        +INVENTORY.UNTOSSABLE
        Tag "XR Wrist Thruster";
    }

    private double CF(Name n, double d) { let c = CVar.GetCVar(n, owner ? owner.player : null); return c ? c.GetFloat() : d; }
    private int    CI(Name n, int    d) { let c = CVar.GetCVar(n, owner ? owner.player : null); return c ? c.GetInt()   : d; }
    private bool   CB(Name n, bool   d) { let c = CVar.GetCVar(n, owner ? owner.player : null); return c ? c.GetBool()  : d; }

    override void DoEffect()
    {
        Super.DoEffect();
        let pmo = owner;
        if (!pmo || !pmo.player) return;

        int maxC = CI("xr_thrust_charges", 2);

        // wrist unit follows the off-hand every tick; dims when out of charge.
        if (!cube) cube = XR_ThrusterCube(Actor.Spawn("XR_ThrusterCube", pmo.OffhandPos));
        if (cube)
        {
            cube.SetOrigin(pmo.OffhandPos, true);
            cube.Angle = pmo.OffhandAngle;
            cube.Pitch = pmo.OffhandPitch;
            double s = (charges > 0) ? 0.11 : 0.06;
            cube.Scale = (s, s);
            cube.Alpha = (charges > 0) ? 0.9 : 0.3;
        }

        bool onGround = (pmo.pos.z <= pmo.floorz + 0.5);
        if (onGround) charges = maxC;                 // recharge on landing

        bool fireNow = (pmo.player.cmd.buttons & BT_JUMP);
        bool edge = fireNow && !prevFire;             // rising edge only
        prevFire = fireNow;

        if (edge && charges > 0 && (!onGround || CB("xr_thrust_ground", true)))
        {
            FireThruster(pmo);
            charges--;
        }
    }

    void FireThruster(Actor pmo)
    {
        // firing vector = off-hand aim; burst travels along it, thrust is opposite (Newton).
        Vector3 aim = pmo.OffhandDir(pmo, 0, pmo.OffhandPitch);
        double al = aim.Length();
        if (al < 0.0001) aim = (0.0, 0.0, -1.0); else aim = aim / al;
        Vector3 thrustDir = CB("xr_thrust_invert", false) ? aim : (-aim.x, -aim.y, -aim.z);

        double dv        = CF("xr_thrust_dv", 5.0);          // ~half a jump of delta-v; tune to taste
        double baseMass  = CF("xr_thrust_basemass", 100.0);
        double massScale = baseMass / max(double(pmo.Mass), 1.0);
        double deltaV    = dv * massScale;
        double maxSpd    = CF("xr_thrust_maxspeed", 40.0);

        // decompose current velocity along the thrust axis:
        //  - cancel the OPPOSING component (a fall can't eat the boost),
        //  - KEEP the perpendicular component (a dash carries your momentum),
        //  - then add deltaV along thrust.
        Vector3 v = pmo.Vel;
        double along = v.x*thrustDir.x + v.y*thrustDir.y + v.z*thrustDir.z;
        Vector3 perp = (v.x - thrustDir.x*along, v.y - thrustDir.y*along, v.z - thrustDir.z*along);
        double newAlong = ((along < 0.0) ? 0.0 : along) + deltaV;
        Vector3 nv = (perp.x + thrustDir.x*newAlong, perp.y + thrustDir.y*newAlong, perp.z + thrustDir.z*newAlong);

        double sp = nv.Length();
        if (sp > maxSpd && sp > 0.0001) nv = (nv.x*(maxSpd/sp), nv.y*(maxSpd/sp), nv.z*(maxSpd/sp));
        pmo.Vel = nv;

        SpawnBurst(pmo, aim);
        pmo.A_StartSound("weapons/plasmaf", CHAN_AUTO, CHANF_OVERLAP, 0.45);
    }

    void SpawnBurst(Actor pmo, Vector3 burstDir)
    {
        int cnt = CI("xr_thrust_spark_count", 10);
        double spd = CF("xr_thrust_spark_speed", 6.0);
        for (int i = 0; i < cnt; i++)
        {
            let s = XR_ThrusterSpark(Actor.Spawn("XR_ThrusterSpark", pmo.OffhandPos));
            if (!s) continue;
            Vector3 d = (burstDir.x + frandom[thrust](-0.28, 0.28),
                         burstDir.y + frandom[thrust](-0.28, 0.28),
                         burstDir.z + frandom[thrust](-0.28, 0.28));
            double dl = d.Length();
            if (dl > 0.0001) d = (d.x/dl, d.y/dl, d.z/dl);
            s.Vel = (d.x*spd, d.y*spd, d.z*spd);
        }
    }

    override void OnDestroy()
    {
        if (cube) { cube.Destroy(); cube = null; }
        Super.OnDestroy();
    }
}

class XR_WristThrusterGiver : EventHandler
{
    override void WorldThingSpawned(WorldEvent e)
    {
        let mo = e.thing;
        if (mo && mo.player && mo.player.mo == mo && !mo.FindInventory("XR_WristThruster"))
            mo.GiveInventory("XR_WristThruster", 1);
    }
}
'''

CVARINFO = r'''// XR Wrist Thruster tuning
user int   xr_thrust_charges     = 2;      // charges before you must land (2 = double-jump)
user float xr_thrust_dv          = 5.0;    // delta-v per fire (map units/tic) ~ half a jump
user float xr_thrust_basemass    = 100.0;  // mass that yields the full xr_thrust_dv
user float xr_thrust_maxspeed    = 40.0;   // clamp on resulting speed
user bool  xr_thrust_invert      = false;  // flip thrust vs firing vector if it feels backwards
user bool  xr_thrust_ground      = true;   // allow firing while grounded (launch), not just airborne
user int   xr_thrust_spark_count = 10;     // burst particles
user float xr_thrust_spark_speed = 6.0;    // burst spread speed
'''

out = sys.argv[1] if len(sys.argv) > 1 else "XR_WristThruster.pk3"
buf = io.BytesIO()
with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr("zscript.txt", ZSCRIPT)
    z.writestr("cvarinfo.txt", CVARINFO)
open(out, "wb").write(buf.getvalue())
print("wrote %s (%d bytes)" % (out, len(buf.getvalue())))
