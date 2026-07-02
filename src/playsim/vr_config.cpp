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

FVRTaxonomy* FVRConfig::GetTaxonomy(const FString& className)
{
    FName name(className.GetChars(), true);
    FVRTaxonomy* tax = Taxonomies.CheckKey(name);
    return tax;
}

void FVRConfig::LoadConfig()
{
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
