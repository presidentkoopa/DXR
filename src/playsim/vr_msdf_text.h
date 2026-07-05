#pragma once

#include "p_visualthinker.h"
#include "vr_msdf.h"

// Master thinker that manages a string of MSDF glyphs
class FVRMSDFTextThinker : public DVisualThinker
{
    DECLARE_CLASS(FVRMSDFTextThinker, DVisualThinker);
public:
    void Construct();
    void OnDestroy() override;
    void Tick() override;

    enum ETextStyle
    {
        STYLE_Classic,
        STYLE_Pulse,
        STYLE_Glitch,
        STYLE_Ticker,
        STYLE_Explode
    };

    enum ETextBehavior
    {
        BEHAVIOR_TrackTarget,
        BEHAVIOR_FloatFree,
        BEHAVIOR_Gravity,
        BEHAVIOR_Anchor       // static world label: no movement (Tick leaves moveStep at 0)
    };

    static FVRMSDFTextThinker* SpawnText(FLevelLocals* Level, const DVector3& pos, FName keyword, const FString& text, int lifetime, double scale = 1.0, FName tribe = NAME_None, ETextStyle style = STYLE_Classic, ETextBehavior behavior = BEHAVIOR_FloatFree);
    void UpdateText(const FString& newText);

    FString Text;
    FName FontKeyword;
    int LifeTimer;
    int MaxLifeTimer;
    double BaseScale;
    ETextStyle Style;
    ETextBehavior Behavior;
    
    // Physics data
    DVector3 Velocity;

    // Tribe visual data
    FVector3 MSDFColor;
    double MSDFGlitch;

    // Children glyphs
    TArray<DVisualThinker*> Glyphs;

private:
    void RebuildGlyphs();
};

// Lightweight particle for environmental impacts
class FVRMSDFImpactParticle : public DVisualThinker
{
    DECLARE_CLASS(FVRMSDFImpactParticle, DVisualThinker);
public:
    void Construct();
    void Tick() override;

    static void SpawnImpact(FLevelLocals* Level, const DVector3& pos, const DVector3& vel, FName keyword, int unicode, int lifetime, double scale, FVector3 color);

    DVector3 Velocity;
    int LifeTimer;
    int MaxLifeTimer;
    FVector3 MSDFColor;
    double MSDFGlitch;
};

void VR_SpawnWiredImpact(FLevelLocals* Level, const DVector3& pos, const DVector3& normal);

// Thinker to handle cumulative damage numbers
class FVRMSDFDamageCounter : public DThinker
{
    DECLARE_CLASS(FVRMSDFDamageCounter, DThinker);
public:
    FVRMSDFDamageCounter() {}
    void Construct();
    void Tick() override;

    static void RecordDamage(AActor* target, int damage);

    TObjPtr<AActor*> Target;
    TObjPtr<FVRMSDFTextThinker*> TextThinker;
    int TotalDamage;
    int AccumulationTimer;
};
