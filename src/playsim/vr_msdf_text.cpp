#include "vr_msdf_text.h"
#include "vr_msdf.h"
#include "p_local.h"
#include "d_player.h"
#include "m_random.h"
#include "g_levellocals.h"
#include "i_time.h"
#include "actor.h"

IMPLEMENT_CLASS(FVRMSDFTextThinker, false, false);

static FRandom pr_msdftext("MSDFText");

CVAR(Bool, vr_wired_impacts, true, CVAR_ARCHIVE | CVAR_GLOBALCONFIG)
CVAR(Int, vr_wired_impact_type, 0, CVAR_ARCHIVE | CVAR_GLOBALCONFIG) // 0: Binary, 1: Geometry, 2: Matrix
CVAR(Int, vr_wired_impact_color_mode, 1, CVAR_ARCHIVE | CVAR_GLOBALCONFIG) // 0: Fixed, 1: Random, 2: Rainbow
CVAR(Color, vr_wired_impact_color, 0x00FF00, CVAR_ARCHIVE | CVAR_GLOBALCONFIG)
CVAR(Float, vr_wired_impact_scale, 0.4f, CVAR_ARCHIVE | CVAR_GLOBALCONFIG)
CVAR(Int, vr_wired_impact_count, 8, CVAR_ARCHIVE | CVAR_GLOBALCONFIG)


CVAR(Bool, vr_show_damage_numbers, true, CVAR_ARCHIVE | CVAR_GLOBALCONFIG)
CVAR(Int, vr_damage_number_style, 0, CVAR_ARCHIVE | CVAR_GLOBALCONFIG) // 0: Classic, 1: Pulse, 2: Glitch, 3: Ticker, 4: Explode
CVAR(Float, vr_damage_number_scale, 1.0f, CVAR_ARCHIVE | CVAR_GLOBALCONFIG)
CVAR(Int, vr_damage_number_behavior, 0, CVAR_ARCHIVE | CVAR_GLOBALCONFIG) // 0: Track, 1: Float Free, 2: Gravity
CVAR(Int, vr_damage_number_lifetime, 60, CVAR_ARCHIVE | CVAR_GLOBALCONFIG)
CVAR(Int, vr_damage_number_color_mode, 0, CVAR_ARCHIVE | CVAR_GLOBALCONFIG) // 0: Heat, 1: Fixed, 2: Rainbow, 3: Random
CVAR(Color, vr_damage_number_color, 0xFF0000, CVAR_ARCHIVE | CVAR_GLOBALCONFIG)

void FVRMSDFTextThinker::Construct()
{
    Super::Construct();
    LifeTimer = 0;
    MaxLifeTimer = 35; // Default 1 second
    BaseScale = 1.0;
    MSDFColor = FVector3(1.f, 1.f, 1.f);
    MSDFGlitch = 0;
    Style = STYLE_Classic;
    Behavior = BEHAVIOR_FloatFree;
    Velocity = DVector3(0, 0, 0);
}

void FVRMSDFTextThinker::OnDestroy()
{
    for (DVisualThinker* glyph : Glyphs)
    {
        if (glyph) glyph->Destroy();
    }
    Glyphs.Clear();
    Super::OnDestroy();
}

void FVRMSDFTextThinker::Tick()
{
    Super::Tick();

    if (LifeTimer >= MaxLifeTimer)
    {
        Destroy();
        return;
    }

    LifeTimer++;

    // float animation based on style
    DVector3 moveStep(0, 0, 0);
    
    if (Behavior == BEHAVIOR_Gravity)
    {
        Velocity.Z -= 0.05; // Gravity
        moveStep = Velocity;
        
        // Simple floor bounce
        if (PT.Pos.Z + moveStep.Z < cursector->floorplane.ZatPoint(PT.Pos))
        {
            moveStep.Z = (cursector->floorplane.ZatPoint(PT.Pos) - PT.Pos.Z);
            Velocity.Z = -Velocity.Z * 0.5; // Dampen
            Velocity.X *= 0.8;
            Velocity.Y *= 0.8;
        }
    }
    else if (Behavior == BEHAVIOR_FloatFree || Behavior == BEHAVIOR_TrackTarget)
    {
        if (Style == STYLE_Classic)
        {
            moveStep = DVector3(0, 0, 0.5);
        }
        else if (Style == STYLE_Pulse)
        {
            double pulse = sin(LifeTimer * 0.5) * 0.2;
            moveStep = DVector3(0, 0, 0.4 + pulse);
        }
        else if (Style == STYLE_Ticker)
        {
            moveStep = DVector3(sin(LifeTimer * 0.2) * 2.0, 0, 0.6);
        }
        else if (Style == STYLE_Explode)
        {
            moveStep = DVector3(0, 0, 0.2 + (LifeTimer < 10 ? LifeTimer * 0.1 : 0));
        }
    }

    Prev = PT.Pos;
    PT.Pos += moveStep;
    UpdateSector();

    // Apply glitch based on remaining life
    double lifeFrac = (double)LifeTimer / MaxLifeTimer;
    
    // Update children glyphs
    for (DVisualThinker* glyph : Glyphs)
    {
        if (!glyph) continue;
        
        glyph->Prev = glyph->PT.Pos;
        glyph->PT.Pos += moveStep;
        glyph->UpdateSector();
        
        // Scale and Glitch effects based on Style
        double currentScale = BaseScale;
        double currentGlitch = MSDFGlitch;

        if (Style == STYLE_Explode)
        {
            if (LifeTimer < 10) currentScale = BaseScale * (LifeTimer * 0.2);
            else currentScale = BaseScale * (1.0 + sin(LifeTimer * 0.1) * 0.1);
        }
        else if (Style == STYLE_Pulse)
        {
            currentScale = BaseScale * (1.0 + sin(LifeTimer * 0.3) * 0.15);
        }
        else if (Style == STYLE_Glitch)
        {
            currentGlitch = MSDFGlitch + (pr_msdftext() % 100) / 100.0;
            if (LifeTimer % 4 == 0) currentScale *= 1.2;
        }

        // Standard fade out
        if (LifeTimer < 5 && Style != STYLE_Explode)
        {
            currentScale = currentScale * (1.0 + (5 - LifeTimer) * 0.1);
        }
        else if (lifeFrac > 0.8)
        {
            currentScale = currentScale * (1.0 - (lifeFrac - 0.8) * 5.0);
        }
        
        glyph->Scale = DVector2(currentScale, currentScale);
        glyph->LightLevel = (int16_t)(255 * (1.0 - lifeFrac));
        // We'll use the fractional part of MSDFGlitch to pass current glitch to shader
        // Since we don't have custom fields, we could try to hijack something else or just wait for the shader update
    }
}

FVRMSDFTextThinker* FVRMSDFTextThinker::SpawnText(FLevelLocals* Level, const DVector3& pos, FName keyword, const FString& text, int lifetime, double scale, FName tribeName, ETextStyle style, ETextBehavior behavior)
{
    FMSDFFont* font = FVRMSDFManager::GetInstance().GetFontAsset(keyword);
    if (!font) return nullptr;

    FVRMSDFTextThinker* master = static_cast<FVRMSDFTextThinker*>(NewVisualThinker(Level, RUNTIME_CLASS(FVRMSDFTextThinker)));
    master->PT.Pos = pos;
    master->UpdateSector();
    master->Prev = pos;
    master->FontKeyword = keyword;
    master->Text = text;
    master->MaxLifeTimer = lifetime;
    master->BaseScale = scale;
    master->Style = style;
    master->Behavior = behavior;
    
    if (behavior == BEHAVIOR_Gravity)
    {
        master->Velocity = DVector3((pr_msdftext() - 128) / 64.0, (pr_msdftext() - 128) / 64.0, 1.5 + (pr_msdftext() % 100) / 50.0);
    }
    master->cursector = Level->PointInSector(pos);

    // Determine tribe colors and glitch
    if (tribeName != NAME_None)
    {
        for (const auto& tribe : font->visualTribes)
        {
            if (tribe.tribeName == tribeName)
            {
                if (tribe.colorPalette.Size() > 0)
                {
                    PalEntry col = tribe.colorPalette[pr_msdftext() % tribe.colorPalette.Size()];
                    master->MSDFColor = FVector3((float)(col.r / 255.0), (float)(col.g / 255.0), (float)(col.b / 255.0));
                }
                master->BaseScale *= tribe.scaleMultiplier;
                master->MSDFGlitch = tribe.jitterRange[0] + pr_msdftext() * (tribe.jitterRange[1] - tribe.jitterRange[0]) / 255.0;
                break;
            }
        }
    }

    master->RebuildGlyphs();
    return master;
}

void FVRMSDFTextThinker::UpdateText(const FString& newText)
{
    if (Text == newText) return;
    Text = newText;
    RebuildGlyphs();
}

void FVRMSDFTextThinker::RebuildGlyphs()
{
    FMSDFFont* font = FVRMSDFManager::GetInstance().GetFontAsset(FontKeyword);
    if (!font || !font->atlasTexture.isValid()) return;

    for (DVisualThinker* glyph : Glyphs)
    {
        if (glyph) glyph->Destroy();
    }
    Glyphs.Clear();

    double currentX = 0;
    
    // We treat 1 unit in font coordinates as N units in world space
    double fontScaleToWorld = 0.5 * BaseScale; 

    // Find full width to center text
    double totalWidth = 0;
    for (int i = 0; i < Text.Len(); i++)
    {
        int unicode = Text[i];
        auto it = font->glyphs.find(unicode);
        if (it != font->glyphs.end())
        {
            totalWidth += it->second.advance * fontScaleToWorld;
        }
    }

    currentX = -totalWidth / 2.0;

    for (int i = 0; i < Text.Len(); i++)
    {
        int unicode = Text[i];
        auto it = font->glyphs.find(unicode);
        if (it != font->glyphs.end())
        {
            const FMSDFGlyph& g = it->second;
            
            // Skip spaces
            if (g.planeBounds[2] > g.planeBounds[0]) 
            {
                DVisualThinker* glyphThinker = NewVisualThinker(Level, RUNTIME_CLASS(DVisualThinker));
                
                double charCenterOffsetX = currentX + ((g.planeBounds[0] + g.planeBounds[2]) / 2.0) * fontScaleToWorld;
                double charCenterOffsetY = ((g.planeBounds[1] + g.planeBounds[3]) / 2.0) * fontScaleToWorld;

                DVector3 glyphPos = PT.Pos;
                
                // Align relative to camera (assume drawing facing player)
                // For a 3D billboard, we'll set the position and use VTF_IsParticle | VTF_ParticleDefault to let the engine billboard it
                // We'll calculate a local offset. However, since the engine handles billboarding per-particle, 
                // we actually need the offset to be in screen-space or view-space.
                // DVisualThinker offsets (Offset.X, Offset.Y) are added after billboarding!
                glyphThinker->PT.Pos = glyphPos;
                glyphThinker->UpdateSector();
                glyphThinker->Prev = glyphPos;
                glyphThinker->Offset = DVector2(charCenterOffsetX, charCenterOffsetY);
                
                glyphThinker->Scale = DVector2(BaseScale, BaseScale);
                glyphThinker->flags = VTF_IsParticle | VTF_ParticleSquare | VTF_AddLightLevel;
                glyphThinker->AnimatedTexture = font->atlasTexture;
                glyphThinker->cursector = cursector;
                
                Glyphs.Push(glyphThinker);
            }
            
            currentX += g.advance * fontScaleToWorld;
        }
    }
}

/////////////////////////////////////////////////////////////////////////////

IMPLEMENT_CLASS(FVRMSDFImpactParticle, false, false);

void FVRMSDFImpactParticle::Construct()
{
    Super::Construct();
    LifeTimer = 0;
    MaxLifeTimer = 35;
    MSDFColor = FVector3(1.f, 1.f, 1.f);
    MSDFGlitch = 0;
    Velocity = DVector3(0, 0, 0);
}

void FVRMSDFImpactParticle::Tick()
{
    Super::Tick();

    if (LifeTimer >= MaxLifeTimer)
    {
        Destroy();
        return;
    }

    LifeTimer++;

    // Apply velocity and gravity (light)
    Prev = PT.Pos;
    PT.Pos += Velocity;
    Velocity.Z -= 0.05; // Light gravity
    UpdateSector();

    double lifeFrac = (double)LifeTimer / MaxLifeTimer;
    LightLevel = (int16_t)(255 * (1.0 - lifeFrac));
    
    // Slight spin or jitter
    double jitter = (pr_msdftext() - 128) / 512.0;
    Offset.X += jitter;
    Offset.Y += jitter;
}

void FVRMSDFImpactParticle::SpawnImpact(FLevelLocals* Level, const DVector3& pos, const DVector3& vel, FName keyword, int unicode, int lifetime, double scale, FVector3 color)
{
    FMSDFFont* font = FVRMSDFManager::GetInstance().GetFontAsset(keyword);
    if (!font) return;

    auto it = font->glyphs.find(unicode);
    if (it == font->glyphs.end()) return;

    const FMSDFGlyph& g = it->second;
    if (g.planeBounds[2] <= g.planeBounds[0]) return;

    FVRMSDFImpactParticle* p = static_cast<FVRMSDFImpactParticle*>(NewVisualThinker(Level, RUNTIME_CLASS(FVRMSDFImpactParticle)));
    p->PT.Pos = pos;
    p->Prev = pos;
    p->Velocity = vel;
    p->MaxLifeTimer = lifetime;
    p->MSDFColor = color;
    p->Scale = DVector2(scale, scale);
    p->flags = VTF_IsParticle | VTF_ParticleSquare | VTF_AddLightLevel;
    p->AnimatedTexture = font->atlasTexture;
    p->cursector = Level->PointInSector(pos);
    p->UpdateSector();

    // Center the glyph
    double fontScaleToWorld = 0.5 * scale;
    p->Offset = DVector2(((g.planeBounds[0] + g.planeBounds[2]) / 2.0) * fontScaleToWorld, 
                         ((g.planeBounds[1] + g.planeBounds[3]) / 2.0) * fontScaleToWorld);
}

void VR_SpawnWiredImpact(FLevelLocals* Level, const DVector3& pos, const DVector3& normal)
{
    if (!vr_wired_impacts) return;
    
    int count = vr_wired_impact_count;
    for (int i = 0; i < count; i++)
    {
        DVector3 vel;
        vel.X = normal.X * (1.0 + (pr_msdftext() % 100) / 25.0) + (pr_msdftext() - 128) / 64.0;
        vel.Y = normal.Y * (1.0 + (pr_msdftext() % 100) / 25.0) + (pr_msdftext() - 128) / 64.0;
        vel.Z = normal.Z * (1.0 + (pr_msdftext() % 100) / 25.0) + (pr_msdftext() - 128) / 64.0;
        
        int unicode = '0';
        if (vr_wired_impact_type == 0) unicode = '0' + (pr_msdftext() % 2);
        else if (vr_wired_impact_type == 1) {
            static const int geo[] = {'+', '-', '*', '/', '#', '@', '[', ']'};
            unicode = geo[pr_msdftext() % 8];
        }
        else unicode = 33 + (pr_msdftext() % 94);
        
        FVector3 color;
        if (vr_wired_impact_color_mode == 0) {
            PalEntry c = *vr_wired_impact_color;
            color = FVector3(c.r/255.f, c.g/255.f, c.b/255.f);
        } else if (vr_wired_impact_color_mode == 1) {
             color = FVector3((pr_msdftext()%255)/255.f, (pr_msdftext()%255)/255.f, (pr_msdftext()%255)/255.f);
        } else {
             // Rainbow
             double t = (I_msTime() / 500.0) + i * 0.2;
             color = FVector3((float)(sin(t) * 0.5 + 0.5), (float)(sin(t + 2.0) * 0.5 + 0.5), (float)(sin(t + 4.0) * 0.5 + 0.5));
        }
        
        FVRMSDFImpactParticle::SpawnImpact(Level, pos, vel, FName("Arcade"), unicode, 15 + pr_msdftext() % 15, vr_wired_impact_scale, color);
    }
}

/////////////////////////////////////////////////////////////////////////////

IMPLEMENT_CLASS(FVRMSDFDamageCounter, false, false);

void FVRMSDFDamageCounter::Construct()
{
    TotalDamage = 0;
    AccumulationTimer = 0;
    Target = nullptr;
    TextThinker = nullptr;
}

void FVRMSDFDamageCounter::Tick()
{
    Super::Tick();

    if (!Target)
    {
        Destroy();
        return;
    }

    AccumulationTimer++;

    // If target died or timer too long, finish
    if (Target->health <= 0 || AccumulationTimer > 35)
    {
        Destroy();
        return;
    }

    // Keep text thinker following target
    if (TextThinker)
    {
        TextThinker->PT.Pos = Target->PosPlusZ(Target->Height + 8);
        TextThinker->UpdateSector();
    }
}

void FVRMSDFDamageCounter::RecordDamage(AActor* target, int damage)
{
    if (!vr_show_damage_numbers || !target) return;

    // Search for existing counter for this actor
    FVRMSDFDamageCounter* counter = nullptr;
    TThinkerIterator<FVRMSDFDamageCounter> it(target->Level);
    while ((counter = it.Next()))
    {
        if (counter->Target == target) break;
    }

    if (!counter)
    {
        counter = target->Level->CreateThinker<FVRMSDFDamageCounter>();
        counter->Target = target;
    }

    counter->TotalDamage += damage;
    counter->AccumulationTimer = 0; // Reset timer to keep accumulating

    FString damageText;
    damageText.Format("%d", counter->TotalDamage);
    
    FVRMSDFTextThinker::ETextStyle style = (FVRMSDFTextThinker::ETextStyle)clamp<int>(vr_damage_number_style, 0, 4);
    FVRMSDFTextThinker::ETextBehavior behavior = (FVRMSDFTextThinker::ETextBehavior)clamp<int>(vr_damage_number_behavior, 0, 2);

    if (!counter->TextThinker)
    {
        counter->TextThinker = FVRMSDFTextThinker::SpawnText(target->Level, target->PosPlusZ(target->Height + 8), FName("Arcade"), damageText, vr_damage_number_lifetime, vr_damage_number_scale, NAME_None, style, behavior);
    }
    else
    {
        counter->TextThinker->UpdateText(damageText);
        counter->TextThinker->MaxLifeTimer = vr_damage_number_lifetime;
        counter->TextThinker->LifeTimer = 0; // Reset lifetime so it stays visible while counting
        counter->TextThinker->Style = style;
        counter->TextThinker->Behavior = behavior;
    }

    // Apply Color Mode
    FVector3 finalColor;
    if (vr_damage_number_color_mode == 0)
    {
        // Heat Map
        if (counter->TotalDamage < 50) finalColor = FVector3(1, 1, 1);
        else if (counter->TotalDamage < 100) finalColor = FVector3(1, 1, 0);
        else finalColor = FVector3(1, 0, 0);
    }
    else if (vr_damage_number_color_mode == 1)
    {
        // Fixed Color
        PalEntry c = *vr_damage_number_color;
        finalColor = FVector3(c.r / 255.f, c.g / 255.f, c.b / 255.f);
    }
    else if (vr_damage_number_color_mode == 2)
    {
        // Rainbow Cycle
        double t = I_msTime() / 500.0;
        finalColor = FVector3((float)(sin(t) * 0.5 + 0.5), (float)(sin(t + 2.0) * 0.5 + 0.5), (float)(sin(t + 4.0) * 0.5 + 0.5));
    }
    else
    {
        // Random Neon
        finalColor = FVector3((pr_msdftext() % 255) / 255.f, (pr_msdftext() % 255) / 255.f, (pr_msdftext() % 255) / 255.f);
    }

    counter->TextThinker->MSDFColor = finalColor;
}
