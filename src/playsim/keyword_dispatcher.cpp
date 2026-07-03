#include "keyword_dispatcher.h"
#include "printf.h"
#include "filesystem.h"

#include "rapidjson/document.h"
#include "rapidjson/error/en.h"
#include <sstream>
#include <algorithm>
#include <cctype>

std::unordered_map<std::string, KeywordProfile> KeywordDispatcher::profiles;

uint8_t KeywordDispatcher::floor_r = 0;
uint8_t KeywordDispatcher::floor_g = 255;
uint8_t KeywordDispatcher::floor_b = 255;
uint8_t KeywordDispatcher::ceil_r = 255;
uint8_t KeywordDispatcher::ceil_g = 0;
uint8_t KeywordDispatcher::ceil_b = 255;

void KeywordDispatcher::Init() {
    profiles.clear();

    int lump = fileSystem.CheckNumForFullName("KEYWORDS.json", true);
    if (lump == -1) {
        Printf("KeywordDispatcher: KEYWORDS.json not found in filesystem.\n");
        return;
    }

    auto lumpdata = fileSystem.ReadFile(lump);
    std::string json_data(lumpdata.string(), lumpdata.size());

    rapidjson::Document doc;
    doc.Parse(json_data.c_str());

    if (doc.HasParseError()) {
        Printf(TEXTCOLOR_RED "KeywordDispatcher: KEYWORDS.json parse error: %s (at offset %zu)\n", 
            rapidjson::GetParseError_En(doc.GetParseError()), doc.GetErrorOffset());
        return;
    }

    if (doc.HasMember("theme") && doc["theme"].IsObject()) {
        const auto& theme = doc["theme"];
        if (theme.HasMember("floor_color") && theme["floor_color"].IsArray()) {
            const auto& col = theme["floor_color"];
            if (col.Size() >= 3) {
                floor_r = col[0].GetInt();
                floor_g = col[1].GetInt();
                floor_b = col[2].GetInt();
            }
        }
        if (theme.HasMember("ceiling_color") && theme["ceiling_color"].IsArray()) {
            const auto& col = theme["ceiling_color"];
            if (col.Size() >= 3) {
                ceil_r = col[0].GetInt();
                ceil_g = col[1].GetInt();
                ceil_b = col[2].GetInt();
            }
        }
    }

    if (doc.HasMember("namespaces") && doc["namespaces"].IsObject()) {
        const auto& ns = doc["namespaces"];

        // Parse color namespace
        if (ns.HasMember("color") && ns["color"].IsObject()) {
            const auto& colors = ns["color"];
            for (auto it = colors.MemberBegin(); it != colors.MemberEnd(); ++it) {
                std::string name = "color:" + std::string(it->name.GetString());
                const auto& val = it->value;
                if (val.IsObject()) {
                    KeywordProfile prof;
                    if (val.HasMember("rgb") && val["rgb"].IsArray()) {
                        const auto& rgb = val["rgb"];
                        if (rgb.Size() >= 3) {
                            prof.r = rgb[0].GetInt();
                            prof.g = rgb[1].GetInt();
                            prof.b = rgb[2].GetInt();
                        }
                    }
                    if (val.HasMember("pulse") && val["pulse"].IsBool()) {
                        prof.pulse = val["pulse"].GetBool();
                    }
                    if (val.HasMember("freq") && val["freq"].IsNumber()) {
                        prof.freq = val["freq"].GetFloat();
                    }
                    profiles[name] = prof;
                }
            }
        }

        // Parse climb namespace
        if (ns.HasMember("climb") && ns["climb"].IsObject()) {
            const auto& climb = ns["climb"];
            for (auto it = climb.MemberBegin(); it != climb.MemberEnd(); ++it) {
                std::string name = "climb:" + std::string(it->name.GetString());
                const auto& val = it->value;
                if (val.IsObject()) {
                    KeywordProfile prof;
                    prof.climbable = true;
                    if (val.HasMember("climb_speed") && val["climb_speed"].IsNumber()) {
                        prof.climb_speed = val["climb_speed"].GetFloat();
                    }
                    profiles[name] = prof;
                }
            }
        }

        // Parse mass namespace
        if (ns.HasMember("mass") && ns["mass"].IsObject()) {
            const auto& massObj = ns["mass"];
            for (auto it = massObj.MemberBegin(); it != massObj.MemberEnd(); ++it) {
                std::string name = "mass:" + std::string(it->name.GetString());
                const auto& val = it->value;
                if (val.IsObject()) {
                    KeywordProfile prof;
                    if (val.HasMember("mass") && val["mass"].IsNumber()) {
                        prof.mass = val["mass"].GetInt();
                    }
                    profiles[name] = prof;
                }
            }
        }

        // Parse role namespace. Keys are the role values themselves (e.g. "fodder", "boss")
        // with no extra fields in KEYWORDS.json; token "role:<name>" carries it via prof.role.
        if (ns.HasMember("role") && ns["role"].IsObject()) {
            const auto& roleObj = ns["role"];
            for (auto it = roleObj.MemberBegin(); it != roleObj.MemberEnd(); ++it) {
                std::string rawName = std::string(it->name.GetString());
                std::string name = "role:" + rawName;
                const auto& val = it->value;
                if (val.IsObject()) {
                    KeywordProfile prof;
                    prof.role = rawName.c_str();
                    profiles[name] = prof;
                }
            }
        }

        // Parse trait namespace. Keys are the trait values themselves (e.g. "hitscan", "melee")
        // with no extra fields in KEYWORDS.json; token "trait:<name>" carries it via prof.trait.
        if (ns.HasMember("trait") && ns["trait"].IsObject()) {
            const auto& traitObj = ns["trait"];
            for (auto it = traitObj.MemberBegin(); it != traitObj.MemberEnd(); ++it) {
                std::string rawName = std::string(it->name.GetString());
                std::string name = "trait:" + rawName;
                const auto& val = it->value;
                if (val.IsObject()) {
                    KeywordProfile prof;
                    prof.trait = rawName.c_str();
                    profiles[name] = prof;
                }
            }
        }

        // Parse anatomy namespace. Each entry carries gore-reaction data for what the actor is
        // made of (blood_color, sparks, shatter, oil_color).
        if (ns.HasMember("anatomy") && ns["anatomy"].IsObject()) {
            const auto& anatomyObj = ns["anatomy"];
            for (auto it = anatomyObj.MemberBegin(); it != anatomyObj.MemberEnd(); ++it) {
                std::string name = "anatomy:" + std::string(it->name.GetString());
                const auto& val = it->value;
                if (val.IsObject()) {
                    KeywordProfile prof;
                    if (val.HasMember("blood_color") && val["blood_color"].IsArray()) {
                        const auto& col = val["blood_color"];
                        if (col.Size() >= 3) {
                            prof.blood_r = col[0].GetInt();
                            prof.blood_g = col[1].GetInt();
                            prof.blood_b = col[2].GetInt();
                        }
                    }
                    if (val.HasMember("sparks") && val["sparks"].IsBool()) {
                        prof.sparks = val["sparks"].GetBool();
                    }
                    if (val.HasMember("shatter") && val["shatter"].IsBool()) {
                        prof.shatter = val["shatter"].GetBool();
                    }
                    if (val.HasMember("oil_color") && val["oil_color"].IsArray()) {
                        const auto& col = val["oil_color"];
                        if (col.Size() >= 3) {
                            prof.oil_r = col[0].GetInt();
                            prof.oil_g = col[1].GetInt();
                            prof.oil_b = col[2].GetInt();
                        }
                    }
                    profiles[name] = prof;
                }
            }
        }

        // Parse vulnerability namespace. Entries carry a damage multiplier (head_crit, eye_crit,
        // explosive, melee) or a stun_duration in tics (core_stun, plasma_stun).
        if (ns.HasMember("vulnerability") && ns["vulnerability"].IsObject()) {
            const auto& vulnObj = ns["vulnerability"];
            for (auto it = vulnObj.MemberBegin(); it != vulnObj.MemberEnd(); ++it) {
                std::string name = "vulnerability:" + std::string(it->name.GetString());
                const auto& val = it->value;
                if (val.IsObject()) {
                    KeywordProfile prof;
                    if (val.HasMember("multiplier") && val["multiplier"].IsNumber()) {
                        prof.vuln_multiplier = val["multiplier"].GetFloat();
                    }
                    if (val.HasMember("stun_duration") && val["stun_duration"].IsNumber()) {
                        prof.stun_duration = val["stun_duration"].GetInt();
                    }
                    profiles[name] = prof;
                }
            }
        }
        // Parse flags namespace
        if (ns.HasMember("flags") && ns["flags"].IsObject()) {
            const auto& flagsObj = ns["flags"];
            for (auto it = flagsObj.MemberBegin(); it != flagsObj.MemberEnd(); ++it) {
                std::string name = "flags:" + std::string(it->name.GetString());
                const auto& val = it->value;
                if (val.IsObject()) {
                    KeywordProfile prof;
                    if (val.HasMember("throwable") && val["throwable"].IsBool()) prof.throwable = val["throwable"].GetBool();
                    if (val.HasMember("primable") && val["primable"].IsBool()) prof.primable = val["primable"].GetBool();
                    profiles[name] = prof;
                }
            }
        }

        // Parse ballistics namespace. Keyed "ballistics:x" (lowercase) to match the Keywords
        // token now carried by the matching projectile actor (Rocket/ThrownGrenade/PlasmaBall).
        // Previously this namespace was never parsed at all, so bullet_drop could never
        // become non-zero regardless of what the JSON said.
        if (ns.HasMember("ballistics") && ns["ballistics"].IsObject()) {
            const auto& ballisticsObj = ns["ballistics"];
            for (auto it = ballisticsObj.MemberBegin(); it != ballisticsObj.MemberEnd(); ++it) {
                std::string rawName = std::string(it->name.GetString());
                std::string lowerName = rawName;
                std::transform(lowerName.begin(), lowerName.end(), lowerName.begin(),
                    [](unsigned char c) { return std::tolower(c); });
                std::string name = "ballistics:" + lowerName;
                const auto& val = it->value;
                if (val.IsObject()) {
                    KeywordProfile prof;
                    if (val.HasMember("bullet_drop") && val["bullet_drop"].IsNumber()) prof.bullet_drop = val["bullet_drop"].GetFloat();
                    if (val.HasMember("air_resistance") && val["air_resistance"].IsNumber()) prof.air_resistance = val["air_resistance"].GetFloat();
                    profiles[name] = prof;
                }
            }
        }

        // Parse weapons namespace. Keyed to match the actual "class:x" tokens weapons carry in
        // their ZScript Keywords (e.g. Pistol's Keywords include "class:pistol") -- NOT
        // "weapons:X", which no weapon has ever carried, and NOT case-sensitive to the JSON's
        // capitalized names (e.g. "Pistol"), which never matched the lowercase ZScript token either.
        if (ns.HasMember("weapons") && ns["weapons"].IsObject()) {
            const auto& weaponsObj = ns["weapons"];
            for (auto it = weaponsObj.MemberBegin(); it != weaponsObj.MemberEnd(); ++it) {
                std::string rawName = std::string(it->name.GetString());
                std::string lowerName = rawName;
                std::transform(lowerName.begin(), lowerName.end(), lowerName.begin(),
                    [](unsigned char c) { return std::tolower(c); });
                std::string name = "class:" + lowerName;
                const auto& val = it->value;
                if (val.IsObject()) {
                    KeywordProfile prof;
                    prof.is_weapon = true;
                    if (val.HasMember("twohand_offset_x") && val["twohand_offset_x"].IsNumber()) prof.twohand_offset_x = val["twohand_offset_x"].GetFloat();
                    if (val.HasMember("twohand_offset_y") && val["twohand_offset_y"].IsNumber()) prof.twohand_offset_y = val["twohand_offset_y"].GetFloat();
                    if (val.HasMember("twohand_offset_z") && val["twohand_offset_z"].IsNumber()) prof.twohand_offset_z = val["twohand_offset_z"].GetFloat();
                    if (val.HasMember("twohand_radius") && val["twohand_radius"].IsNumber()) prof.twohand_radius = val["twohand_radius"].GetFloat();
                    if (val.HasMember("parry_extent") && val["parry_extent"].IsArray()) {
                        const auto& pe = val["parry_extent"];
                        if (pe.Size() >= 3) {
                            prof.parry_extent_x = pe[0].GetFloat();
                            prof.parry_extent_y = pe[1].GetFloat();
                            prof.parry_extent_z = pe[2].GetFloat();
                        }
                    }
                    if (val.HasMember("parry_sound") && val["parry_sound"].IsString()) {
                        prof.parry_sound = val["parry_sound"].GetString();
                    }
                    profiles[name] = prof;
                }
            }
        }
    }
    Printf("KeywordDispatcher: Loaded %zu keyword profiles from KEYWORDS.json\n", profiles.size());
}

bool KeywordDispatcher::ResolveKeywordColor(const FString& keywords, uint8_t& out_r, uint8_t& out_g, uint8_t& out_b, uint8_t& out_a, bool& out_pulse, float& out_freq) {
    if (keywords.IsEmpty()) return false;

    std::stringstream ss(keywords.GetChars());
    std::string token;
    while (ss >> token) {
        auto it = profiles.find(token);
        if (it != profiles.end() && !it->second.climbable) {
            out_r = it->second.r;
            out_g = it->second.g;
            out_b = it->second.b;
            out_a = it->second.a;
            out_pulse = it->second.pulse;
            out_freq = it->second.freq;
            return true;
        }
    }
    return false;
}

bool KeywordDispatcher::IsClimbable(const FString& keywords, float& out_speed) {
    if (keywords.IsEmpty()) return false;

    std::stringstream ss(keywords.GetChars());
    std::string token;
    while (ss >> token) {
        auto it = profiles.find(token);
        if (it != profiles.end() && it->second.climbable) {
            out_speed = it->second.climb_speed;
            return true;
        }
    }
    return false;
}

bool KeywordDispatcher::ResolveKeywordMass(const FString& keywords, int& out_mass) {
    if (keywords.IsEmpty()) return false;

    std::stringstream ss(keywords.GetChars());
    std::string token;
    while (ss >> token) {
        if (token.rfind("mass:", 0) == 0) {
            try {
                out_mass = std::stoi(token.substr(5));
                return true;
            } catch (...) {
                // Ignore parse errors
            }
        }
        
        auto it = profiles.find(token);
        if (it != profiles.end() && it->second.mass > 0) {
            out_mass = it->second.mass;
            return true;
        }
    }
    return false;
}
bool KeywordDispatcher::ResolveMetadata(const FString& keywords, KeywordProfile& out_profile) {
    if (keywords.IsEmpty()) return false;

    std::stringstream ss(keywords.GetChars());
    std::string token;
    bool found = false;
    while (ss >> token) {
        auto it = profiles.find(token);
        if (it != profiles.end()) {
            // Merge metadata
            if (it->second.role.IsNotEmpty()) out_profile.role = it->second.role;
            if (it->second.trait.IsNotEmpty()) out_profile.trait = it->second.trait;
            if (it->second.faction.IsNotEmpty()) out_profile.faction = it->second.faction;
            if (it->second.head_height > 0) out_profile.head_height = it->second.head_height;
            if (it->second.score_set.IsNotEmpty()) out_profile.score_set = it->second.score_set;
            if (it->second.item_type.IsNotEmpty()) out_profile.item_type = it->second.item_type;
            if (it->second.rarity > 0) out_profile.rarity = it->second.rarity;
            if (it->second.value > 0) out_profile.value = it->second.value;
            if (it->second.points > 0) out_profile.points = it->second.points;
            if (it->second.bullet_drop > 0) out_profile.bullet_drop = it->second.bullet_drop;
            if (it->second.air_resistance > 0) out_profile.air_resistance = it->second.air_resistance;
            found = true;
        }
    }
    return found;
}

bool KeywordDispatcher::IsThrowable(const FString& keywords) {
    if (keywords.IsEmpty()) return false;

    std::stringstream ss(keywords.GetChars());
    std::string token;
    while (ss >> token) {
        auto it = profiles.find(token);
        if (it != profiles.end() && it->second.throwable) {
            return true;
        }
    }
    return false;
}

bool KeywordDispatcher::IsGrenade(const FString& keywords) {
    if (keywords.IsEmpty()) return false;

    std::stringstream ss(keywords.GetChars());
    std::string token;
    while (ss >> token) {
        auto it = profiles.find(token);
        if (it != profiles.end() && it->second.primable) {
            return true;
        }
    }
    return false;
}

bool KeywordDispatcher::GetWeaponOffsets(const FString& keywords, float& ox, float& oy, float& oz, float& radius) {
    if (keywords.IsEmpty()) return false;

    std::stringstream ss(keywords.GetChars());
    std::string token;
    while (ss >> token) {
        auto it = profiles.find(token);
        if (it != profiles.end() && it->second.is_weapon) {
            ox = it->second.twohand_offset_x;
            oy = it->second.twohand_offset_y;
            oz = it->second.twohand_offset_z;
            radius = it->second.twohand_radius;
            return true;
        }
    }
    return false;
}

float KeywordDispatcher::GetBulletDrop(const FString& keywords) {
    if (keywords.IsEmpty()) return 0;
    std::stringstream ss(keywords.GetChars());
    std::string token;
    while (ss >> token) {
        auto it = profiles.find(token);
        if (it != profiles.end() && it->second.bullet_drop > 0) return it->second.bullet_drop;
    }
    return 0;
}

float KeywordDispatcher::GetRecoilForce(const FString& keywords) {
    if (keywords.IsEmpty()) return 1.0f;
    std::stringstream ss(keywords.GetChars());
    std::string token;
    while (ss >> token) {
        auto it = profiles.find(token);
        if (it != profiles.end() && it->second.is_weapon) return it->second.recoil_force;
    }
    return 1.0f;
}

KeywordProfile* KeywordDispatcher::GetProfile(const char* name) {
    auto it = profiles.find(name);
    if (it != profiles.end()) return &it->second;
    return nullptr;
}
