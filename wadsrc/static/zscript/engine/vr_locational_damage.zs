// [XR] Locational damage is now FULLY NATIVE (src/playsim/p_interaction.cpp, P_DamageMobj): zone detection
// (head/chest/torso/legs), damage multipliers, legshot stumble, and hit-zone storage are all in C++. The
// zone/hand are stored on the native int fields Actor.LastHitZone (0=torso 1=head 2=chest 3=legs) and
// Actor.LastHitHand (0=main 1=off), tunable from VR Options > Combat > Locational Damage.
//
// The old ZScript VRLocationalArbiter StaticEventHandler (WorldThingDamaged) was RETIRED here: it
// duplicated the native zone math AND crashed on every monster hit by assigning FString zone tags onto
// native actors (see dxr-actor-defaults-fstring-clobber). This file now only exposes string-name helpers
// so mods (e.g. the SDF combo system) can read the native zone without touching FStrings on actors.
extend class Actor
{
    // Human-readable zone name for mods. Mirrors the native LastHitZone enum.
    String GetHitZoneName()
    {
        switch (LastHitZone)
        {
            case 1: return "head";
            case 2: return "chest";
            case 3: return "legs";
            default: return "torso";
        }
    }

    // Which hand landed the hit, as the combo system's tag form.
    String GetHitHandName() { return LastHitHand == 1 ? "hand:off" : "hand:main"; }
}
