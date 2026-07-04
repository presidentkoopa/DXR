#pragma once

#include "tarray.h"
#include "zstring.h"
#include "name.h"
#include "vr_hardpoint.h"   // FHardpointSlot, EHardpointAnchor/Action, VR_MAX_HARDPOINTS

struct FVRTaxonomy
{
    int score_value = 0;
    FString faction = "";
    float head_ratio = 0.0f;
    float leg_ratio = 0.0f;
    float arm_width = 0.0f;
    float dmg_head = 1.0f;
    float dmg_legs = 1.0f;
    float dmg_arms = 1.0f;

    FString rarity = "";
    float loot_pool_weight = 0.0f;
    bool vr_auto_use = false;
    FString holster_slot = "";
};

struct FVRConfig
{
    static TArray<FString> ClimbableTextures;
    static TMap<FName, FVRTaxonomy> Taxonomies;

    // Data-driven hardpoint slot defaults, loaded from vr_hardpoints.json.
    // Mirrored per-player into player_t.vr_hardpoints[] at pawn spawn (VR_InitHardpoints).
    static TArray<FHardpointSlot> Hardpoints;

    // Taxonomy Dictionary
    static FVRTaxonomy* GetTaxonomy(const FString& className);

    static void LoadConfig();
    static bool IsClimbableTexture(const FString& texName);
};
