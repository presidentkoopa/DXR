#pragma once

#include <string>
#include <unordered_map>
#include "common/utility/zstring.h"

struct KeywordProfile {
    uint8_t r = 255;
    uint8_t g = 255;
    uint8_t b = 255;
    uint8_t a = 255;
    bool pulse = false;
    float freq = 2.0f;
    bool climbable = false;
    float climb_speed = 1.0f;
    int mass = 0;

    // Flags
    bool throwable = false;
    bool primable = false;

    // Weapons
    bool is_weapon = false;
    float twohand_offset_x = 0;
    float twohand_offset_y = 0;
    float twohand_offset_z = 0;
    float twohand_radius = 0;
    float recoil_force = 1.0f;
    float parry_extent_x = 0;
    float parry_extent_y = 0;
    float parry_extent_z = 0;

    // Ballistics
    float bullet_drop = 0.0f;
    float air_resistance = 0.0f;

    // Metadata
    FString role;
    FString trait;
    FString faction;
    double head_height = 0;
    FString score_set;
    FString item_type;
    int rarity = 0;
    int value = 0;
    int points = 0;

    // Anatomy
    uint8_t blood_r = 200;
    uint8_t blood_g = 0;
    uint8_t blood_b = 0;
    bool sparks = false;
    bool shatter = false;
    uint8_t oil_r = 0;
    uint8_t oil_g = 0;
    uint8_t oil_b = 0;

    // Vulnerability
    float vuln_multiplier = 1.0f;
    int stun_duration = 0;

    // Haptics
    FString haptic_type;
    float haptic_intensity = 1.0f;
};

class KeywordDispatcher {
public:
    static void Init();
    static bool ResolveKeywordColor(const FString& keywords, uint8_t& out_r, uint8_t& out_g, uint8_t& out_b, uint8_t& out_a, bool& out_pulse, float& out_freq);
    static bool IsClimbable(const FString& keywords, float& out_speed);
    static bool ResolveKeywordMass(const FString& keywords, int& out_mass);
    static bool ResolveMetadata(const FString& keywords, KeywordProfile& out_profile);
    static bool IsThrowable(const FString& keywords);
    static bool IsGrenade(const FString& keywords);
    static bool GetWeaponOffsets(const FString& keywords, float& ox, float& oy, float& oz, float& radius);
    static float GetBulletDrop(const FString& keywords);
    static float GetRecoilForce(const FString& keywords);
    static KeywordProfile* GetProfile(const char* name);

    static uint8_t floor_r;
    static uint8_t floor_g;
    static uint8_t floor_b;
    static uint8_t ceil_r;
    static uint8_t ceil_g;
    static uint8_t ceil_b;

private:
    static std::unordered_map<std::string, KeywordProfile> profiles;
};
