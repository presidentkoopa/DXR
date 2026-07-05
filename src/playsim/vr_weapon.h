#pragma once

#include "zstring.h"
#include "name.h"
#include "tarray.h"
#include "c_cvars.h"
#include "info.h"

EXTERN_CVAR(Bool, vr_weapon_shell)
EXTERN_CVAR(Bool, vr_weapon_dts)
EXTERN_CVAR(Int, vr_weapon_model_format)

enum class EVRWeaponArchetype {
    Unknown,
    Fist,
    Chainsaw,
    Pistol,
    Shotgun,
    SSG,
    Chaingun,
    RocketLauncher,
    PlasmaRifle,
    BFG,
    Rifle,
    SMG,
    Revolver,
    Flamethrower
};

struct VRWeaponData {
    EVRWeaponArchetype Archetype = EVRWeaponArchetype::Unknown;
    FString ModelName;
    FString SkinName;
    
    // Transform
    float ScaleX = 1.0f;
    float ScaleY = 1.0f;
    float ScaleZ = 1.0f;
    float OffsetX = 0.0f;
    float OffsetY = 0.0f;
    float OffsetZ = 0.0f;
    
    // Animation overrides
    FString CustomReloadState;

    // Animation Synchronization Tracking
    struct FState* Current3DState = nullptr;   // 3D state currently displayed (the render hook reads this)
    int Current3DTics = 0;                       // legacy 1:1 path: tics elapsed within Current3DState
    int Max3DTics = 0;                            // total tic length of the mapped 3D state sequence

    // Frame-perfect sync (DTS): time-scale the 3D animation onto the 2D action's exact duration.
    struct FState* Anim3DStart = nullptr;        // label-anchor start of the mapped 3D sequence (re-walked each tic)
    int Max2DTics = 0;                            // total tic length of the mapped 2D state sequence
    int Elapsed2DTics = 0;                        // game tics since the 2D state sequence was entered
};

class FVRWeaponResolver {
public:
    static void Init();
    static void ResolveWeapons();
    static void LoadJSONOverrides();
    static void SaveJSONOverrides();
    static EVRWeaponArchetype GetArchetypeFromName(const FString& name);
    static const char* GetArchetypeName(EVRWeaponArchetype arch);
    static PClassActor* GetActorClassForArchetype(EVRWeaponArchetype arch);
};
