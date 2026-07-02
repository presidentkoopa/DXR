#pragma once

#include "basics.h"
#include "d_player.h"
#include "actor.h"
#include "textures.h"
#include <map>
#include <vector>

struct FMSDFGlyph
{
    int unicode;
    double advance;
    double planeBounds[4]; // left, bottom, right, top
    double atlasBounds[4]; // left, bottom, right, top
};

struct FMSDFFontMetrics
{
    double lineHeight;
    double ascender;
    double descender;
    double underlineY;
    double underlineThickness;
};

struct FMSDFVisualTribe
{
    FName tribeName;
    TArray<PalEntry> colorPalette;
    double jitterRange[2];
    double scaleMultiplier;
};

struct FMSDFFont
{
    FName keyword;
    FTextureID atlasTexture;
    FMSDFFontMetrics metrics;
    std::map<int, FMSDFGlyph> glyphs;
    TArray<FMSDFVisualTribe> visualTribes;
};

class FVRMSDFManager
{
public:
    static FVRMSDFManager& GetInstance()
    {
        static FVRMSDFManager instance;
        return instance;
    }

    void Init();
    FMSDFFont* GetFontAsset(FName keyword);
    void SpawnMSDFBillboard(AActor* target, FName keyword, FName tribe = NAME_None);

private:
    FVRMSDFManager() {}
    ~FVRMSDFManager() {}

    std::map<FName, FMSDFFont> LoadedFonts;

    void ScanLooseAssets();
    bool ParseMSDFJson(const char* jsonPath, const char* texturePath, FName keyword);
    bool ParseVisualTribeJson(const char* jsonPath, FMSDFFont& fontData);
};
