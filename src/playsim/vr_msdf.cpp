#include "vr_msdf.h"
#include "c_console.h"
#include "rapidjson/document.h"
#include "rapidjson/filereadstream.h"
#include "filesystem.h"
#include "v_text.h"
#include "cmdlib.h"
#include "m_random.h"
#include "c_dispatch.h"
#include "texturemanager.h"

#ifdef _WIN32
#include <windows.h>
#else
#include <dirent.h>
#include <sys/stat.h>
#endif

using namespace rapidjson;

static FRandom pr_msdf("VRMSDF");

void FVRMSDFManager::Init()
{
    Printf("VR MSDF Manager: Initializing Asset Pipeline...\n");
    LoadedFonts.clear();
    ScanLooseAssets();
}

void FVRMSDFManager::ScanLooseAssets()
{
    FString msdfDir = progdir + "vr_assets/msdf/";
    FString jsonDir = progdir + "vr_assets/json/";
    
    Printf("Scanning for MSDF fonts in %s\n", msdfDir.GetChars());

#ifdef _WIN32
    WIN32_FIND_DATAA fd;
    HANDLE hFind = FindFirstFileA((msdfDir + "*.json").GetChars(), &fd);
    
    if (hFind != INVALID_HANDLE_VALUE)
    {
        do
        {
            if (!(fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY))
            {
                FString jsonPath = msdfDir + fd.cFileName;
                FString baseName = fd.cFileName;
                baseName.StripRight(".json");
                
                // Expect a matching PNG for the texture atlas
                FString pngPath = msdfDir + baseName + ".png";
                FName keyword = FName(baseName.GetChars());

                if (ParseMSDFJson(jsonPath.GetChars(), pngPath.GetChars(), keyword))
                {
                    // Check if there's a visual tribe metadata file in the json dir
                    FString tribePath = jsonDir + baseName + "_tribe.json";
                    ParseVisualTribeJson(tribePath.GetChars(), LoadedFonts[keyword]);
                }
            }
        } while (FindNextFileA(hFind, &fd));
        FindClose(hFind);
    }
#else
    DIR* dir;
    struct dirent* ent;
    if ((dir = opendir(msdfDir.GetChars())) != NULL)
    {
        while ((ent = readdir(dir)) != NULL)
        {
            FString fileName = ent->d_name;
            if (fileName.IndexOf(".json") != -1)
            {
                FString baseName = fileName;
                baseName.StripRight(".json");
                
                FString jsonPath = msdfDir + fileName;
                FString pngPath = msdfDir + baseName + ".png";
                FName keyword = FName(baseName.GetChars());

                if (ParseMSDFJson(jsonPath.GetChars(), pngPath.GetChars(), keyword))
                {
                    FString tribePath = jsonDir + baseName + "_tribe.json";
                    ParseVisualTribeJson(tribePath.GetChars(), LoadedFonts[keyword]);
                }
            }
        }
        closedir(dir);
    }
#endif
}

bool FVRMSDFManager::ParseMSDFJson(const char* jsonPath, const char* texturePath, FName keyword)
{
    FILE* fp = fopen(jsonPath, "rb");
    if (!fp) return false;

    char readBuffer[65536];
    FileReadStream is(fp, readBuffer, sizeof(readBuffer));
    Document d;
    d.ParseStream(is);
    fclose(fp);

    if (d.HasParseError())
    {
        Printf(TEXTCOLOR_RED "MSDF JSON Parse Error (%s): %d\n", jsonPath, d.GetParseError());
        return false;
    }

    FMSDFFont newFont;
    newFont.keyword = keyword;
    
    // Register Texture dynamically
    // In GZDoom, loose files can be added to TexMan if we create an FImageSource.
    // For now, we assume the texture was added to a WAD/PK3 or we use a placeholder logic.
    // To load from disk dynamically, we would need to use FImageSource::GetImage or similar.
    // For this prototype, we'll try to find it by basenamel
    FString texName = ExtractFileBase(texturePath);
    newFont.atlasTexture = TexMan.CheckForTexture(texName.GetChars(), ETextureType::Any);
    
    if (!newFont.atlasTexture.isValid())
    {
        Printf(TEXTCOLOR_YELLOW "MSDF Atlas '%s' not found in loaded resources. Ensure it's in a PK3/WAD.\n", texName.GetChars());
        // We'll continue parsing metrics anyway for debugging
    }

    if (d.HasMember("metrics") && d["metrics"].IsObject())
    {
        auto& metrics = d["metrics"];
        if (metrics.HasMember("lineHeight")) newFont.metrics.lineHeight = metrics["lineHeight"].GetDouble();
        if (metrics.HasMember("ascender")) newFont.metrics.ascender = metrics["ascender"].GetDouble();
        if (metrics.HasMember("descender")) newFont.metrics.descender = metrics["descender"].GetDouble();
        if (metrics.HasMember("underlineY")) newFont.metrics.underlineY = metrics["underlineY"].GetDouble();
        if (metrics.HasMember("underlineThickness")) newFont.metrics.underlineThickness = metrics["underlineThickness"].GetDouble();
    }

    if (d.HasMember("glyphs") && d["glyphs"].IsArray())
    {
        for (auto& g : d["glyphs"].GetArray())
        {
            FMSDFGlyph glyph;
            glyph.unicode = g["unicode"].GetInt();
            glyph.advance = g["advance"].GetDouble();
            
            if (g.HasMember("planeBounds") && g["planeBounds"].IsObject())
            {
                glyph.planeBounds[0] = g["planeBounds"]["left"].GetDouble();
                glyph.planeBounds[1] = g["planeBounds"]["bottom"].GetDouble();
                glyph.planeBounds[2] = g["planeBounds"]["right"].GetDouble();
                glyph.planeBounds[3] = g["planeBounds"]["top"].GetDouble();
            }
            else
            {
                memset(glyph.planeBounds, 0, sizeof(glyph.planeBounds));
            }

            if (g.HasMember("atlasBounds") && g["atlasBounds"].IsObject())
            {
                glyph.atlasBounds[0] = g["atlasBounds"]["left"].GetDouble();
                glyph.atlasBounds[1] = g["atlasBounds"]["bottom"].GetDouble();
                glyph.atlasBounds[2] = g["atlasBounds"]["right"].GetDouble();
                glyph.atlasBounds[3] = g["atlasBounds"]["top"].GetDouble();
            }
            else
            {
                memset(glyph.atlasBounds, 0, sizeof(glyph.atlasBounds));
            }

            newFont.glyphs[glyph.unicode] = glyph;
        }
    }

    LoadedFonts[keyword] = newFont;
    Printf("Loaded MSDF Font: %s (%zu glyphs)\n", keyword.GetChars(), newFont.glyphs.size());
    return true;
}

bool FVRMSDFManager::ParseVisualTribeJson(const char* jsonPath, FMSDFFont& fontData)
{
    FILE* fp = fopen(jsonPath, "rb");
    if (!fp) return false;

    char readBuffer[4096];
    FileReadStream is(fp, readBuffer, sizeof(readBuffer));
    Document d;
    d.ParseStream(is);
    fclose(fp);

    if (d.HasParseError()) return false;

    if (d.HasMember("tribes") && d["tribes"].IsArray())
    {
        for (auto& t : d["tribes"].GetArray())
        {
            FMSDFVisualTribe tribe;
            tribe.tribeName = FName(t["name"].GetString());
            tribe.scaleMultiplier = t.HasMember("scale") ? t["scale"].GetDouble() : 1.0;
            
            if (t.HasMember("jitter_range") && t["jitter_range"].IsArray() && t["jitter_range"].Size() == 2)
            {
                tribe.jitterRange[0] = t["jitter_range"][0].GetDouble();
                tribe.jitterRange[1] = t["jitter_range"][1].GetDouble();
            }
            else
            {
                tribe.jitterRange[0] = 0.0;
                tribe.jitterRange[1] = 0.0;
            }

            if (t.HasMember("color_palette") && t["color_palette"].IsArray())
            {
                for (auto& c : t["color_palette"].GetArray())
                {
                    FString hexStr = c.GetString();
                    if (hexStr.Len() >= 7 && hexStr[0] == '#')
                    {
                        FString rStr = hexStr.Mid(1, 2);
                        FString gStr = hexStr.Mid(3, 2);
                        FString bStr = hexStr.Mid(5, 2);
                        
                        uint8_t r = (uint8_t)strtol(rStr.GetChars(), NULL, 16);
                        uint8_t g = (uint8_t)strtol(gStr.GetChars(), NULL, 16);
                        uint8_t b = (uint8_t)strtol(bStr.GetChars(), NULL, 16);
                        
                        tribe.colorPalette.Push(PalEntry(255, r, g, b));
                    }
                }
            }

            fontData.visualTribes.Push(tribe);
        }
    }
    Printf("Loaded %d Visual Tribes for %s\n", fontData.visualTribes.Size(), fontData.keyword.GetChars());
    return true;
}

FMSDFFont* FVRMSDFManager::GetFontAsset(FName keyword)
{
    auto it = LoadedFonts.find(keyword);
    if (it != LoadedFonts.end())
    {
        return &it->second;
    }
    return nullptr;
}

void FVRMSDFManager::SpawnMSDFBillboard(AActor* target, FName keyword, FName tribeName)
{
    FMSDFFont* font = GetFontAsset(keyword);
    if (!font) return;

    // TODO: Actually spawn the billboard actor here and apply the randomized tribe properties
    // For now, print a debug message
    Printf("Spawning MSDF Billboard for %s near target %p\n", keyword.GetChars(), target);
}

// CCmd for testing
CCMD(vr_debug_msdf)
{
    if (argv.argc() > 1)
    {
        FName keyword(argv[1]);
        FMSDFFont* font = FVRMSDFManager::GetInstance().GetFontAsset(keyword);
        if (font)
        {
            Printf("Successfully found MSDF font %s in registry.\n", keyword.GetChars());
        }
        else
        {
            Printf("Could not find MSDF font %s.\n", keyword.GetChars());
        }
    }
    else
    {
        Printf("Usage: vr_debug_msdf <keyword>\n");
    }
}
