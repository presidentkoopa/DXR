#include "vr_weapon.h"
#include "info.h"
#include "a_weapons.h"
#include "c_console.h"
#include "c_cvars.h"
#include "printf.h"
#include "c_dispatch.h"
#include "rapidjson/writer.h"
#include "rapidjson/stringbuffer.h"
#include "gi.h"
#include "common/scripting/vm/vm.h"
#include "common/objects/dobjtype.h"

CVAR(Bool, vr_weapon_shell, true, CVAR_ARCHIVE | CVAR_GLOBALCONFIG)
CVAR(Bool, vr_weapon_hands, true, CVAR_ARCHIVE | CVAR_GLOBALCONFIG)
CVAR(Bool, vr_weapon_dts, true, CVAR_ARCHIVE | CVAR_GLOBALCONFIG)

void FVRWeaponResolver::Init()
{
    Printf("VR Weapon Resolver: Initializing Universal 3D Weapon Shell...\n");
    ResolveWeapons();
    LoadJSONOverrides();
}

void FVRWeaponResolver::ResolveWeapons()
{
    PClassActor* WeaponClass = PClass::FindActor("Weapon");
    if (!WeaponClass) return;

    for (PClass* cls : PClass::AllClasses)
    {
        if (cls->IsDescendantOf(WeaponClass) && cls != WeaponClass)
        {
            PClassActor* actorCls = static_cast<PClassActor*>(cls);
            
            // Auto-detect based on inheritance
            EVRWeaponArchetype archetype = EVRWeaponArchetype::Unknown;
            
            if (cls->IsDescendantOf(PClass::FindActor("Shotgun"))) archetype = EVRWeaponArchetype::Shotgun;
            else if (cls->IsDescendantOf(PClass::FindActor("SuperShotgun"))) archetype = EVRWeaponArchetype::SSG;
            else if (cls->IsDescendantOf(PClass::FindActor("Pistol"))) archetype = EVRWeaponArchetype::Pistol;
            else if (cls->IsDescendantOf(PClass::FindActor("Chaingun"))) archetype = EVRWeaponArchetype::Chaingun;
            else if (cls->IsDescendantOf(PClass::FindActor("RocketLauncher"))) archetype = EVRWeaponArchetype::RocketLauncher;
            else if (cls->IsDescendantOf(PClass::FindActor("PlasmaRifle"))) archetype = EVRWeaponArchetype::PlasmaRifle;
            else if (cls->IsDescendantOf(PClass::FindActor("BFG9000"))) archetype = EVRWeaponArchetype::BFG;
            else if (cls->IsDescendantOf(PClass::FindActor("Chainsaw"))) archetype = EVRWeaponArchetype::Chainsaw;
            else if (cls->IsDescendantOf(PClass::FindActor("Fist"))) archetype = EVRWeaponArchetype::Fist;
            
            if (archetype != EVRWeaponArchetype::Unknown)
            {
                AActor* defaultActor = GetDefaultByType(actorCls);
                if (defaultActor)
                {
                    if (!defaultActor->vr_weapon_data)
                    {
                        defaultActor->vr_weapon_data = new VRWeaponData();
                    }
                    defaultActor->vr_weapon_data->Archetype = archetype;
                }
            }
        }
    }
}

#include "rapidjson/document.h"
#include <fstream>
#include <sstream>

void FVRWeaponResolver::LoadJSONOverrides()
{
    std::ifstream file("doomxr_weapons.json");
    if (!file.is_open()) return;

    std::stringstream buffer;
    buffer << file.rdbuf();
    std::string jsonStr = buffer.str();

    rapidjson::Document doc;
    doc.Parse(jsonStr.c_str());

    if (doc.HasParseError() || !doc.IsObject()) return;

    for (auto i = doc.MemberBegin(); i != doc.MemberEnd(); ++i)
    {
        if (i->value.IsObject())
        {
            FString weaponName = i->name.GetString();
            PClassActor* actorCls = PClass::FindActor(weaponName);
            if (!actorCls) continue;

            AActor* defaultActor = GetDefaultByType(actorCls);
            if (!defaultActor) continue;

            if (!defaultActor->vr_weapon_data)
            {
                defaultActor->vr_weapon_data = new VRWeaponData();
            }

            if (i->value.HasMember("archetype") && i->value["archetype"].IsString())
            {
                defaultActor->vr_weapon_data->Archetype = GetArchetypeFromName(i->value["archetype"].GetString());
            }

            if (i->value.HasMember("custom_reload_state") && i->value["custom_reload_state"].IsString())
            {
                defaultActor->vr_weapon_data->CustomReloadState = i->value["custom_reload_state"].GetString();
            }
        }
    }
    Printf("VR Weapon Resolver: Applied JSON Overrides.\n");
}

EVRWeaponArchetype FVRWeaponResolver::GetArchetypeFromName(const FString& name)
{
    if (name.CompareNoCase("Shotgun") == 0) return EVRWeaponArchetype::Shotgun;
    if (name.CompareNoCase("SuperShotgun") == 0) return EVRWeaponArchetype::SSG;
    if (name.CompareNoCase("Pistol") == 0) return EVRWeaponArchetype::Pistol;
    if (name.CompareNoCase("Chaingun") == 0) return EVRWeaponArchetype::Chaingun;
    if (name.CompareNoCase("RocketLauncher") == 0) return EVRWeaponArchetype::RocketLauncher;
    if (name.CompareNoCase("PlasmaRifle") == 0) return EVRWeaponArchetype::PlasmaRifle;
    if (name.CompareNoCase("BFG9000") == 0) return EVRWeaponArchetype::BFG;
    if (name.CompareNoCase("Chainsaw") == 0) return EVRWeaponArchetype::Chainsaw;
    if (name.CompareNoCase("Fist") == 0) return EVRWeaponArchetype::Fist;
    if (name.CompareNoCase("Rifle") == 0) return EVRWeaponArchetype::Rifle;
    if (name.CompareNoCase("SMG") == 0) return EVRWeaponArchetype::SMG;
    if (name.CompareNoCase("Revolver") == 0) return EVRWeaponArchetype::Revolver;
    if (name.CompareNoCase("Flamethrower") == 0) return EVRWeaponArchetype::Flamethrower;
    return EVRWeaponArchetype::Unknown;
}

PClassActor* FVRWeaponResolver::GetActorClassForArchetype(EVRWeaponArchetype arch)
{
    switch (arch)
    {
        case EVRWeaponArchetype::Shotgun: return PClass::FindActor("Shotgun");
        case EVRWeaponArchetype::SSG: return PClass::FindActor("SuperShotgun");
        case EVRWeaponArchetype::Pistol: return PClass::FindActor("Pistol");
        case EVRWeaponArchetype::Chaingun: return PClass::FindActor("Chaingun");
        case EVRWeaponArchetype::RocketLauncher: return PClass::FindActor("RocketLauncher");
        case EVRWeaponArchetype::PlasmaRifle: return PClass::FindActor("PlasmaRifle");
        case EVRWeaponArchetype::BFG: return PClass::FindActor("BFG9000");
        case EVRWeaponArchetype::Chainsaw: return PClass::FindActor("Chainsaw");
        case EVRWeaponArchetype::Fist: return PClass::FindActor("Fist");
        case EVRWeaponArchetype::Rifle: return PClass::FindActor("Rifle");
        case EVRWeaponArchetype::SMG: return PClass::FindActor("SMG");
        case EVRWeaponArchetype::Revolver: return PClass::FindActor("Revolver");
        case EVRWeaponArchetype::Flamethrower: return PClass::FindActor("Flamethrower");
        default: return nullptr;
    }
}

void FVRWeaponResolver::SaveJSONOverrides()
{
    rapidjson::StringBuffer sb;
    rapidjson::Writer<rapidjson::StringBuffer> writer(sb);

    writer.StartObject();

    PClassActor* WeaponClass = PClass::FindActor("Weapon");
    for (PClass* cls : PClass::AllClasses)
    {
        if (cls->IsDescendantOf(WeaponClass) && cls != WeaponClass)
        {
            PClassActor* actorCls = static_cast<PClassActor*>(cls);
            AActor* defaultActor = GetDefaultByType(actorCls);
            if (defaultActor && defaultActor->vr_weapon_data)
            {
                if (defaultActor->vr_weapon_data->Archetype != EVRWeaponArchetype::Unknown)
                {
                    writer.Key(cls->TypeName.GetChars());
                    writer.StartObject();
                    writer.Key("archetype");
                    writer.String(GetArchetypeName(defaultActor->vr_weapon_data->Archetype));
                    
                    if (defaultActor->vr_weapon_data->CustomReloadState.Len() > 0)
                    {
                        writer.Key("custom_reload_state");
                        writer.String(defaultActor->vr_weapon_data->CustomReloadState.GetChars());
                    }
                    
                    writer.EndObject();
                }
            }
        }
    }

    writer.EndObject();

    std::ofstream file("doomxr_weapons.json");
    if (file.is_open())
    {
        file << sb.GetString();
        Printf("VR Weapon Resolver: Saved JSON Overrides.\n");
    }
}

const char* FVRWeaponResolver::GetArchetypeName(EVRWeaponArchetype arch)
{
    switch (arch)
    {
        case EVRWeaponArchetype::Fist: return "Fist";
        case EVRWeaponArchetype::Chainsaw: return "Chainsaw";
        case EVRWeaponArchetype::Pistol: return "Pistol";
        case EVRWeaponArchetype::Shotgun: return "Shotgun";
        case EVRWeaponArchetype::SSG: return "SuperShotgun";
        case EVRWeaponArchetype::Chaingun: return "Chaingun";
        case EVRWeaponArchetype::RocketLauncher: return "RocketLauncher";
        case EVRWeaponArchetype::PlasmaRifle: return "PlasmaRifle";
        case EVRWeaponArchetype::BFG: return "BFG9000";
        case EVRWeaponArchetype::Rifle: return "Rifle";
        case EVRWeaponArchetype::SMG: return "SMG";
        case EVRWeaponArchetype::Revolver: return "Revolver";
        case EVRWeaponArchetype::Flamethrower: return "Flamethrower";
        default: return "Unknown";
    }
}

CCMD(vr_weapon_set_archetype)
{
    if (argv.argc() < 3)
    {
        Printf("Usage: vr_weapon_set_archetype <WeaponClass> <Archetype>\n");
        return;
    }

    PClassActor* actorCls = PClass::FindActor(argv[1]);
    if (!actorCls)
    {
        Printf("Unknown weapon class: %s\n", argv[1]);
        return;
    }

    EVRWeaponArchetype arch = FVRWeaponResolver::GetArchetypeFromName(argv[2]);
    
    AActor* defaultActor = GetDefaultByType(actorCls);
    if (!defaultActor) return;

    if (!defaultActor->vr_weapon_data)
    {
        defaultActor->vr_weapon_data = new VRWeaponData();
    }
    
    defaultActor->vr_weapon_data->Archetype = arch;
    FVRWeaponResolver::SaveJSONOverrides();
}

DEFINE_ACTION_FUNCTION(DMenu, GetVRWeaponArchetype)
{
    PARAM_PROLOGUE;
    PARAM_CLASS(cls, AActor);
    if (!cls) { ACTION_RETURN_INT(0); }
    PClassActor* actorCls = static_cast<PClassActor*>(cls);
    AActor* defaultActor = GetDefaultByType(actorCls);
    if (defaultActor && defaultActor->vr_weapon_data)
        ACTION_RETURN_INT((int)defaultActor->vr_weapon_data->Archetype);
    else
        ACTION_RETURN_INT(0);
}
