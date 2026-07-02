#pragma once

#include "zstring.h"
#include "name.h"
#include "tarray.h"
#include "c_cvars.h"
#include "info.h"

EXTERN_CVAR(Bool, vr_weapon_shell)
EXTERN_CVAR(Bool, vr_weapon_hands)
EXTERN_CVAR(Bool, vr_weapon_dts)

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
    struct FState* Current3DState = nullptr;
    int Current3DTics = 0;
    int Max3DTics = 0;
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
