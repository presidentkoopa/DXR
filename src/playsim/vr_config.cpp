#include "vr_config.h"
#include "c_dispatch.h"
#include "d_main.h"
#include "i_system.h"
#include "printf.h"
#include "rapidjson/document.h"
#include "rapidjson/filereadstream.h"
#include <cstdio>
#include <ctype.h>

TArray<FString> FVRConfig::ClimbableTextures;
TMap<FName, FVRTaxonomy> FVRConfig::Taxonomies;
TArray<FHardpointSlot> FVRConfig::Hardpoints;

static int VR_ParseHardpointAnchor(const rapidjson::Value& v)
{
    // Accept either an int (0/1) or a string ("body"/"wrist"). Default: body.
    if (v.IsInt())
    {
        int a = v.GetInt();
        return (a == HP_ANCHOR_WRIST) ? HP_ANCHOR_WRIST : HP_ANCHOR_BODY;
    }
    if (v.IsString())
    {
        FString s = v.GetString();
        s.ToUpper();
        if (s.IndexOf("WRIST") != -1 || s.IndexOf("HAND") != -1) return HP_ANCHOR_WRIST;
    }
    return HP_ANCHOR_BODY;
}

static int VR_ParseHardpointAction(const rapidjson::Value& v)
{
    // Accept either an int (0/1) or a string ("holster"/"ability"). Default: holster.
    if (v.IsInt())
    {
        int a = v.GetInt();
        return (a == HP_ACT_ABILITY) ? HP_ACT_ABILITY : HP_ACT_HOLSTER;
    }
    if (v.IsString())
    {
        FString s = v.GetString();
        s.ToUpper();
        if (s.IndexOf("ABILITY") != -1) return HP_ACT_ABILITY;
    }
    return HP_ACT_HOLSTER;
}

FVRTaxonomy* FVRConfig::GetTaxonomy(const FString& className)
{
    FName name(className.GetChars(), true);
    FVRTaxonomy* tax = Taxonomies.CheckKey(name);
    return tax;
}

void FVRConfig::LoadConfig()
{
    // ---- Hardpoint slot defaults (must run before the early returns below) ----
    // Seeded at the TOP of LoadConfig, not before the closing brace: this function
    // has early returns (below, and on a JSON parse error further down) that would
    // otherwise skip hardpoint seeding entirely.
    Hardpoints.Clear();
    {
        // ---- BODY WEAPON HOLSTERS (HP_ACT_HOLSTER) ----------------------------------
        // Generic draw/stow mounts -- ANY weapon (sword / whip / ice hooks) can be
        // holstered in ANY of these. offsets are ox=right, oy=forward, oz=up (map units),
        // relative to the VR head/chest anchor, yaw-rotated with the body. CALIBRATE in
        // headset via the Native Hardpoints menu (they are also overridable per-user via
        // vr_hardpoints.json). hand=-1 => either hand may draw/stow here.
        FHardpointSlot rShoulder;      // over-the-right-shoulder (rifle/whip draw)
        rShoulder.anchor = HP_ANCHOR_BODY; rShoulder.action = HP_ACT_HOLSTER; rShoulder.hand = -1;
        rShoulder.ox = 7.0f;  rShoulder.oy = -2.0f; rShoulder.oz = -6.0f;
        Hardpoints.Push(rShoulder);

        FHardpointSlot lShoulder;      // over-the-left-shoulder
        lShoulder.anchor = HP_ANCHOR_BODY; lShoulder.action = HP_ACT_HOLSTER; lShoulder.hand = -1;
        lShoulder.ox = -7.0f; lShoulder.oy = -2.0f; lShoulder.oz = -6.0f;
        Hardpoints.Push(lShoulder);

        FHardpointSlot rHip;           // right hip (sidearm / sword)
        rHip.anchor = HP_ANCHOR_BODY; rHip.action = HP_ACT_HOLSTER; rHip.hand = -1;
        rHip.ox = 8.0f;  rHip.oy = 2.0f;  rHip.oz = -26.0f;
        Hardpoints.Push(rHip);

        FHardpointSlot lHip;           // left hip (ice hooks / off-hand tool)
        lHip.anchor = HP_ANCHOR_BODY; lHip.action = HP_ACT_HOLSTER; lHip.hand = -1;
        lHip.ox = -8.0f; lHip.oy = 2.0f;  lHip.oz = -26.0f;
        Hardpoints.Push(lHip);

        // ---- WRIST ABILITY MOUNTS (HP_ACT_ABILITY) ----------------------------------
        // Three mounts ride the OFF hand's wrist (top / bottom / side), reached by tapping
        // with the MAIN hand -- a natural "wrist gauntlet" gesture. A grip rising-edge here
        // fires PlayerPawn.VR_HardpointAbility(hand, slotIndex) (a virtual a mod overrides to
        // launch e.g. the gravity walkway, a whip cast, a sword special). abilityName is a
        // config-side hint; the dispatch itself is by slotIndex. hand=0 => reached by main hand.
        // wrist offsets: ox=out from wrist, oy=along forearm, oz=around the wrist face.
        FHardpointSlot wristTop;       // top of the off-hand wrist
        wristTop.anchor = HP_ANCHOR_WRIST; wristTop.action = HP_ACT_ABILITY; wristTop.hand = 0;
        wristTop.ox = 0.0f; wristTop.oy = -3.0f; wristTop.oz = 3.0f;
        wristTop.abilityName = FName("wrist_top");
        Hardpoints.Push(wristTop);

        FHardpointSlot wristBottom;    // underside of the off-hand wrist
        wristBottom.anchor = HP_ANCHOR_WRIST; wristBottom.action = HP_ACT_ABILITY; wristBottom.hand = 0;
        wristBottom.ox = 0.0f; wristBottom.oy = -3.0f; wristBottom.oz = -3.0f;
        wristBottom.abilityName = FName("wrist_bottom");
        Hardpoints.Push(wristBottom);

        FHardpointSlot wristSide;      // outer side of the off-hand wrist
        wristSide.anchor = HP_ANCHOR_WRIST; wristSide.action = HP_ACT_ABILITY; wristSide.hand = 0;
        wristSide.ox = 3.0f; wristSide.oy = -3.0f; wristSide.oz = 0.0f;
        wristSide.abilityName = FName("wrist_side");
        Hardpoints.Push(wristSide);
    }
    // External override: vr_hardpoints.json { "hardpoints": [ { ... }, ... ] }.
    // Read HERE (top of LoadConfig) so it also survives the early returns below.
    {
        FILE* fpHp = fopen("vr_hardpoints.json", "rb");
        if (fpHp)
        {
            char hpBuffer[65536];
            rapidjson::FileReadStream isHp(fpHp, hpBuffer, sizeof(hpBuffer));
            rapidjson::Document dHp;
            dHp.ParseStream(isHp);
            fclose(fpHp);

            if (dHp.HasParseError())
            {
                Printf("Error parsing vr_hardpoints.json\n");
            }
            else if (dHp.HasMember("hardpoints") && dHp["hardpoints"].IsArray())
            {
                Hardpoints.Clear(); // valid file replaces defaults
                const rapidjson::Value& arr = dHp["hardpoints"];
                for (rapidjson::SizeType i = 0; i < arr.Size(); i++)
                {
                    if (Hardpoints.Size() >= VR_MAX_HARDPOINTS) break; // honor fixed cap
                    if (!arr[i].IsObject()) continue;
                    const rapidjson::Value& o = arr[i];

                    FHardpointSlot slot; // ctor defaults per contract

                    if (o.HasMember("anchor"))  slot.anchor = VR_ParseHardpointAnchor(o["anchor"]);
                    if (o.HasMember("action"))  slot.action = VR_ParseHardpointAction(o["action"]);
                    if (o.HasMember("hand") && o["hand"].IsInt()) slot.hand = o["hand"].GetInt();

                    if (o.HasMember("offset") && o["offset"].IsArray() && o["offset"].Size() >= 3)
                    {
                        const rapidjson::Value& off = o["offset"];
                        if (off[0].IsNumber()) slot.ox = off[0].GetFloat();
                        if (off[1].IsNumber()) slot.oy = off[1].GetFloat();
                        if (off[2].IsNumber()) slot.oz = off[2].GetFloat();
                    }
                    else
                    {
                        if (o.HasMember("ox") && o["ox"].IsNumber()) slot.ox = o["ox"].GetFloat();
                        if (o.HasMember("oy") && o["oy"].IsNumber()) slot.oy = o["oy"].GetFloat();
                        if (o.HasMember("oz") && o["oz"].IsNumber()) slot.oz = o["oz"].GetFloat();
                    }

                    if (o.HasMember("radius") && o["radius"].IsNumber()) slot.radius = o["radius"].GetFloat();
                    if (o.HasMember("weapon_class") && o["weapon_class"].IsString())
                        slot.weaponClass = FName(o["weapon_class"].GetString());
                    if (o.HasMember("ability") && o["ability"].IsString())
                        slot.abilityName = FName(o["ability"].GetString());
                    if (o.HasMember("enabled") && o["enabled"].IsBool()) slot.enabled = o["enabled"].GetBool();

                    Hardpoints.Push(slot);
                }
            }
        }
    }
    // ---- end hardpoint defaults; existing ClimbableTextures / taxonomy code follows ----

    ClimbableTextures.Clear();

    // Default built-in textures
    ClimbableTextures.Push("LADDER");
    ClimbableTextures.Push("PIPE");
    ClimbableTextures.Push("GRATE");
    ClimbableTextures.Push("RUNG");

    // Load external json
    FILE* fp = fopen("vr_climb_textures.json", "rb");
    if (!fp)
    {
        return; // File not found, stick to defaults
    }

    char readBuffer[65536];
    rapidjson::FileReadStream is(fp, readBuffer, sizeof(readBuffer));

    rapidjson::Document d;
    d.ParseStream(is);
    fclose(fp);

    if (d.HasParseError())
    {
        Printf("Error parsing vr_climb_textures.json\n");
        return;
    }

    if (d.HasMember("climbable_textures") && d["climbable_textures"].IsArray())
    {
        const rapidjson::Value& texArray = d["climbable_textures"];
        for (rapidjson::SizeType i = 0; i < texArray.Size(); i++)
        {
            if (texArray[i].IsString())
            {
                FString texName = texArray[i].GetString();
                texName.ToUpper();
                ClimbableTextures.Push(texName);
            }
        }
    }

    // Load Taxonomy JSON
    FILE* fpTax = fopen("keywords.db.json", "rb");
    if (fpTax)
    {
        char taxBuffer[65536];
        rapidjson::FileReadStream isTax(fpTax, taxBuffer, sizeof(taxBuffer));
        rapidjson::Document dTax;
        dTax.ParseStream(isTax);
        fclose(fpTax);

        if (!dTax.HasParseError() && dTax.HasMember("classes") && dTax["classes"].IsObject())
        {
            const rapidjson::Value& classes = dTax["classes"];
            for (rapidjson::Value::ConstMemberIterator it = classes.MemberBegin(); it != classes.MemberEnd(); ++it)
            {
                if (it->name.IsString() && it->value.IsObject())
                {
                    FName className(it->name.GetString(), true);
                    FVRTaxonomy tax;
                    
                    const rapidjson::Value& props = it->value;
                    if (props.HasMember("score_value") && props["score_value"].IsInt()) tax.score_value = props["score_value"].GetInt();
                    if (props.HasMember("faction") && props["faction"].IsString()) tax.faction = props["faction"].GetString();
                    if (props.HasMember("head_ratio") && props["head_ratio"].IsNumber()) tax.head_ratio = props["head_ratio"].GetFloat();
                    if (props.HasMember("leg_ratio") && props["leg_ratio"].IsNumber()) tax.leg_ratio = props["leg_ratio"].GetFloat();
                    if (props.HasMember("arm_width") && props["arm_width"].IsNumber()) tax.arm_width = props["arm_width"].GetFloat();
                    
                    if (props.HasMember("damage_mults") && props["damage_mults"].IsObject())
                    {
                        const rapidjson::Value& mults = props["damage_mults"];
                        if (mults.HasMember("head") && mults["head"].IsNumber()) tax.dmg_head = mults["head"].GetFloat();
                        if (mults.HasMember("legs") && mults["legs"].IsNumber()) tax.dmg_legs = mults["legs"].GetFloat();
                        if (mults.HasMember("arms") && mults["arms"].IsNumber()) tax.dmg_arms = mults["arms"].GetFloat();
                    }

                    if (props.HasMember("rarity") && props["rarity"].IsString()) tax.rarity = props["rarity"].GetString();
                    if (props.HasMember("loot_pool_weight") && props["loot_pool_weight"].IsNumber()) tax.loot_pool_weight = props["loot_pool_weight"].GetFloat();
                    if (props.HasMember("vr_auto_use") && props["vr_auto_use"].IsBool()) tax.vr_auto_use = props["vr_auto_use"].GetBool();
                    if (props.HasMember("holster_slot") && props["holster_slot"].IsString()) tax.holster_slot = props["holster_slot"].GetString();

                    Taxonomies.Insert(className, tax);
                }
            }
        }
    }
}

bool FVRConfig::IsClimbableTexture(const FString& texName)
{
    FString upperTex = texName;
    upperTex.ToUpper();

    for (unsigned int i = 0; i < ClimbableTextures.Size(); i++)
    {
        if (upperTex.IndexOf(ClimbableTextures[i]) != -1)
        {
            return true;
        }
    }
    return false;
}
