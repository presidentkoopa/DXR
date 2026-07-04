#pragma once

#include "vectors.h"
#include "matrix.h"
#include "hw_material.h"
#include "texmanip.h"
#include "version.h"
#include "i_interface.h"
#include "v_video.h"
#include "hw_cvars.h"

struct FColormap;
class IVertexBuffer;
class IIndexBuffer;

enum EClearTarget
{
	CT_Depth = 1,
	CT_Stencil = 2,
	CT_Color = 4
};

enum ERenderEffect
{
	EFF_NONE = -1,
	EFF_FOGBOUNDARY,
	EFF_SPHEREMAP,
	EFF_BURN,
	EFF_STENCIL,
	EFF_DITHERTRANS,
	MAX_EFFECTS
};

enum EAlphaFunc
{
	Alpha_GEqual = 0,
	Alpha_Greater = 1
};

enum EDrawType
{
	DT_Points = 0,
	DT_Lines = 1,
	DT_Triangles = 2,
	DT_TriangleFan = 3,
	DT_TriangleStrip = 4
};

enum EDepthFunc
{
	DF_Less,
	DF_LEqual,
	DF_Always
};

enum EStencilFlags
{
	SF_AllOn = 0,
	SF_ColorMaskOff = 1,
	SF_DepthMaskOff = 2,
};

enum EStencilOp
{
	SOP_Keep = 0,
	SOP_Increment = 1,
	SOP_Decrement = 2
};

enum ECull
{
	Cull_None,
	Cull_CCW,
	Cull_CW
};



struct FStateVec4
{
	float vec[4];

	void Set(float r, float g, float b, float a)
	{
		vec[0] = r;
		vec[1] = g;
		vec[2] = b;
		vec[3] = a;
	}
};

struct FMaterialState
{
	FMaterial *mMaterial = nullptr;
	int mClampMode;
	int mTranslation;
	int mOverrideShader;
	bool mChanged;

	void Reset()
	{
		mMaterial = nullptr;
		mTranslation = 0;
		mClampMode = CLAMP_NONE;
		mOverrideShader = -1;
		mChanged = false;
	}
};

struct FDepthBiasState
{
	float mFactor;
	float mUnits;
	bool mChanged;

	void Reset()
	{
		mFactor = 0;
		mUnits = 0;
		mChanged = false;
	}
};

enum EPassType
{
	NORMAL_PASS,
	GBUFFER_PASS,
	MAX_PASS_TYPES
};

struct FVector4PalEntry
{
	float r, g, b, a;

	bool operator==(const FVector4PalEntry &other) const
	{
		return r == other.r && g == other.g && b == other.b && a == other.a;
	}

	bool operator!=(const FVector4PalEntry &other) const
	{
		return r != other.r || g != other.g || b != other.b || a != other.a;
	}

	FVector4PalEntry &operator=(PalEntry newvalue)
	{
		const float normScale = 1.0f / 255.0f;
		r = newvalue.r * normScale;
		g = newvalue.g * normScale;
		b = newvalue.b * normScale;
		a = newvalue.a * normScale;
		return *this;
	}

	FVector4PalEntry& SetIA(PalEntry newvalue)
	{
		const float normScale = 1.0f / 255.0f;
		r = newvalue.r * normScale;
		g = newvalue.g * normScale;
		b = newvalue.b * normScale;
		a = newvalue.a;
		return *this;
	}

	FVector4PalEntry& SetFlt(float v1, float v2, float v3, float v4)	
	{
		r = v1;
		g = v2;
		b = v3;
		a = v4;
		return *this;
	}

};

// [GITD] max simultaneous localized glow spots packed into one draw (mirrored as a #define in
// every backend's shader prelude — GL/GLES/Vulkan — so C++ and GLSL agree on the array size).
#define MAX_WALL_GLOW_SPOTS 16

struct StreamData
{
	FVector4PalEntry uObjectColor;
	FVector4PalEntry uObjectColor2;
	FVector4 uDynLightColor;
	FVector4PalEntry uAddColor;
	FVector4PalEntry uTextureAddColor;
	FVector4PalEntry uTextureModulateColor;
	FVector4PalEntry uTextureBlendColor;
	FVector4PalEntry uFogColor;
	float uDesaturationFactor;
	float uInterpolationFactor;
	float timer;
	int useVertexData;
	FVector4 uVertexColor;
	FVector4 uVertexNormal;

	FVector4 uGlowTopPlane;
	FVector4 uGlowTopColor;
	FVector4 uGlowBottomPlane;
	FVector4 uGlowBottomColor;

	FVector4 uWallGlowSpots[MAX_WALL_GLOW_SPOTS]; // [i]: .xy=center(world x,z), .z=packed rgb, .w=radius(<=0 empty)
	int uWallGlowSpotCount;
	int uWallGlowPad0, uWallGlowPad1, uWallGlowPad2; // pad count up to a full vec4 (std140)

	FVector4 uWallGlowMask[MAX_WALL_GLOW_SPOTS]; // [i]: .x=wipeType(0 none,1 seam), .y=progress 0..1, .zw=wipe dir

	FVector4 uGradientTopPlane;
	FVector4 uGradientBottomPlane;

	FVector4 uSplitTopPlane;
	FVector4 uSplitBottomPlane;

	FVector4 uDetailParms;
	FVector4 uNpotEmulation;

	FVector4PalEntry uGlobalFadeColor;
	int uGlobalFade;
	int uGlobalFadeMode;
	float uGlobalFadeDensity;
	float uGlobalFadeGradient;
	int uLightRangeLimit;

	float u_IsMSDF;
	float u_MSDFGlitch;
	int padding2;
	int padding3;
	int padding4; // [std140 align] FVector4/FVector4PalEntry are bare floats (align-4, no alignas),
	int padding5; // so C++ does NOT round the next vec4 up to 16 the way GLSL std140 does. The
	int padding6; // uGlobalFade..padding3 run is 9 scalars (36B); these 3 pads make u_MSDFColor land
	              // on a 16B boundary matching GLSL, else every field after it (all GITD fog/regime
	              // uniforms) shifts 12 bytes -> corrupt reads (black world + mis-coloured glyph spray).

	FVector4 u_MSDFColor;

	// ===== GITD OMNI-FOG & REGIMES (global; fed per-frame; see gitd_shaderbridge -> GITDShader natives) =====
	// KEEP byte-identical (field order + std140 layout) with the GLSL StreamData in vk_shader.cpp.
	int   u_gitd_fog_mode;
	float u_gitd_fog_density;
	float u_gitd_fog_height;
	float u_gitd_fog_quantize;
	float u_gitd_fog_rim_power;
	float u_gitd_fog_speed;
	int   u_gitd_fog_lightlink;
	int   u_vr_visual_regime;
	float u_vr_regime_param1;
	float u_vr_regime_param2;
	float u_vr_regime_speed;
	int   u_vr_regime_react;
	int   u_vr_regime_center_mask;
	float u_vr_regime_bubble_size;
	float u_vr_regime_jitter;
	int   u_vr_regime_speed_link;
	float u_vr_regime_ping_inten;
	float u_gitd_last_hit_time;
	float u_gitd_last_fire_time;
	float u_gitd_player_speed;
	float u_gitd_kill_streak;
	float u_vr_thermal_inten;
	float u_vr_noir_sat;
	int   u_vr_ripples_enabled;
	float u_vr_ripple_scale;
	float u_gitd_last_impact_time;
	int   u_gitd_pad0;
	int   u_gitd_pad1;
	FVector4 u_vr_blueprint_col;      // .rgb
	FVector4 u_gitd_last_impact_pos;  // .xyz

	// ===== MONSTER NEON OUTLINES (global; fed per-frame directly from the CVARINFO cvars via
	// FindCVar() in hw_drawinfo.cpp -- NOT via ZScript/Shader.SetUniform, which cannot reach a
	// Sprite material shader like monster_neon.fp; gitd_shaderbridge.zs's own comment confirms that
	// API only exists for PostProcess shaders. KEEP byte-identical with GLSL StreamData in vk_shader.cpp.
	float u_BlackoutMode;
	float u_NeonThickness;
	float u_NeonThreshold;
	float u_NeonGlow;
	float u_NeonPulseSpeed;
	int   u_neon_pad0;
	int   u_neon_pad1;
	int   u_neon_pad2; // pad 20B->32B (std140 align) so the FVector4s below land on a 16B boundary
	FVector4 u_NeonColorA; // .rgb
	FVector4 u_NeonColorB; // .rgb
};

// Cheap once-per-frame cache for the monster-neon-outline values. Populated by
// HWDrawInfo::StartScene() (hw_drawinfo.cpp) via FindCVar() -- ONCE per scene/eye, not per draw
// call. FRenderState::Reset() (below, called per draw call) just copies from this; it must never
// do the FindCVar lookup itself, that would be a hash lookup on every single draw call.
struct FNeonOutlineState
{
	float BlackoutMode = 0.0f;
	float NeonThickness = 1.0f;
	float NeonThreshold = 0.2f;
	float NeonGlow = 3.0f;
	float NeonPulseSpeed = 2.0f;
	FVector4 NeonColorA = { 0.0f, 1.0f, 1.0f, 1.0f };
	FVector4 NeonColorB = { 1.0f, 0.0f, 1.0f, 1.0f };
};
extern FNeonOutlineState GNeonOutlineState;

// Same idiom as FNeonOutlineState above: cheap once-per-frame cache for the visual-regime and
// GITD fog tuning cvars, populated by HWDrawInfo::StartScene() via FindCVar(). FRenderState::Reset()
// just copies from this. The four *Pulse/KillStreak/PlayerSpeed-style reactive fields are NOT
// cvars -- PlayerSpeed is computed live from the viewpoint each frame; LastHitTime/LastFireTime/
// KillStreak/LastImpact have no producer yet (no combat-event tracker wired to them), so they
// stay at their harmless defaults (0) until that tracker exists -- regimes read them for reactive
// polish only, never to gate the base effect.
struct FVisualRegimeState
{
	float RegimeSelect = 0.0f;
	float FogMode = 0.0f;
	float FogDensity = 0.5f;
	float FogHeight = 0.0f;
	float FogQuantize = 32.0f;
	float FogRimPower = 2.0f;
	float FogSpeed = 1.0f;
	float FogLightLink = 0.0f;
	float RegimeParam1 = 1.0f;
	float RegimeParam2 = 1.0f;
	float RegimeSpeed = 1.0f;
	float RegimeReact = 0.0f;
	float RegimeCenterMask = 0.0f;
	float RegimeBubbleSize = 1.0f;
	float RegimeJitter = 0.0f;
	float RegimeSpeedLink = 0.0f;
	float RegimePingInten = 1.0f;
	FVector4 RegimeBlueprintCol = { 0.25f, 0.75f, 1.0f, 1.0f };
	float RegimeThermalInten = 1.0f;
	float RegimeNoirSat = 0.15f;
	float RegimeRipplesEnabled = 0.0f;
	float RegimeRippleScale = 1.0f;
	float PlayerSpeed = 0.0f;
	float LastHitTime = 0.0f;
	float LastFireTime = 0.0f;
	float LastImpactTime = 0.0f;
	FVector4 LastImpactPos = { 0.0f, 0.0f, 0.0f, 0.0f };
	float KillStreak = 0.0f;
};
extern FVisualRegimeState GVisualRegimeState;

class FRenderState
{
protected:
	uint8_t mFogEnabled;
	uint8_t mTextureEnabled:1;
	uint8_t mGlowEnabled : 1;
	uint8_t mWallGlowEnabled : 1;
	uint8_t mGradientEnabled : 1;
	uint8_t mModelMatrixEnabled : 1;
	uint8_t mTextureMatrixEnabled : 1;
	uint8_t mSplitEnabled : 1;
	uint8_t mBrightmapEnabled : 1;

	int mLightIndex;
	int mBoneIndexBase;
	int mSpecialEffect;
	int mTextureMode;
	int mTextureClamp;
	int mTextureModeFlags;
	int mSoftLight;
	float mLightParms[4];

	float mAlphaThreshold;
	float mClipSplit[2];


	int mColorMapSpecial;
	float mColorMapFlash;

	StreamData mStreamData = {};
	PalEntry mFogColor;
	PalEntry mFadeColor;
	PalEntry mSceneColor;
	FStateVec4 mDetailParms;
	FRenderStyle mRenderStyle;

	FMaterialState mMaterial;
	FDepthBiasState mBias;

	IVertexBuffer *mVertexBuffer;
	int mVertexOffsets[2];	// one per binding point
	IIndexBuffer *mIndexBuffer;

	EPassType mPassType = NORMAL_PASS;

public:

	uint64_t firstFrame = 0;
	VSMatrix mModelMatrix;
	VSMatrix mTextureMatrix;

public:

	void Reset()
	{
		mTextureEnabled = true;
		mBrightmapEnabled = mGradientEnabled = mFogEnabled = mGlowEnabled = mWallGlowEnabled = false;
		mFogColor = 0xffffffff;
		mStreamData.uFogColor = mFogColor;
		mStreamData.uWallGlowSpotCount = 0;
		mTextureMode = -1;
		mTextureClamp = 0;
		mTextureModeFlags = 0;
		mStreamData.uDesaturationFactor = 0.0f;
		mAlphaThreshold = 0.5f;
		mModelMatrixEnabled = false;
		mTextureMatrixEnabled = false;
		mSplitEnabled = false;
		mStreamData.uAddColor = 0;
		mStreamData.uObjectColor = 0xffffffff;
		mStreamData.uObjectColor2 = 0;
		mStreamData.uTextureBlendColor = 0;
		mStreamData.uTextureAddColor = 0;
		mStreamData.uTextureModulateColor = 0;
		mSoftLight = 0;
		mLightParms[0] = mLightParms[1] = mLightParms[2] = 0.0f;
		mLightParms[3] = -1.f;
		mSpecialEffect = EFF_NONE;
		mLightIndex = -1;
		mBoneIndexBase = -1;
		mStreamData.uInterpolationFactor = 0;
		mRenderStyle = DefaultRenderStyle();
		mMaterial.Reset();
		mBias.Reset();
		mPassType = NORMAL_PASS;

		mColorMapSpecial = 0;
		mColorMapFlash = 1;

		mVertexBuffer = nullptr;
		mVertexOffsets[0] = mVertexOffsets[1] = 0;
		mIndexBuffer = nullptr;

		mStreamData.uVertexColor = { 1.0f, 1.0f, 1.0f, 1.0f };
		mStreamData.uGlowTopColor = { 0.0f, 0.0f, 0.0f, 0.0f };
		mStreamData.uGlowBottomColor = { 0.0f, 0.0f, 0.0f, 0.0f };
		mStreamData.uGlowTopPlane = { 0.0f, 0.0f, 0.0f, 0.0f };
		mStreamData.uGlowBottomPlane = { 0.0f, 0.0f, 0.0f, 0.0f };
		mStreamData.uGradientTopPlane = { 0.0f, 0.0f, 0.0f, 0.0f };
		mStreamData.uGradientBottomPlane = { 0.0f, 0.0f, 0.0f, 0.0f };
		mStreamData.uSplitTopPlane = { 0.0f, 0.0f, 0.0f, 0.0f };
		mStreamData.uSplitBottomPlane = { 0.0f, 0.0f, 0.0f, 0.0f };
		mStreamData.uDynLightColor = { 0.0f, 0.0f, 0.0f, 1.0f };
		mStreamData.uDetailParms = { 0.0f, 0.0f, 0.0f, 0.0f };
#ifdef NPOT_EMULATION
		mStreamData.uNpotEmulation = { 0,0,0,0 };
#endif

		mStreamData.uGlobalFadeColor = 0;
		mStreamData.uGlobalFade = 0;
		mStreamData.uGlobalFadeMode = -1;
		mStreamData.uGlobalFadeDensity = 0.001f;
		mStreamData.uGlobalFadeGradient = 1.5f;
		mStreamData.uLightRangeLimit = 64;

		mStreamData.u_IsMSDF = 0.0f;
		mStreamData.u_MSDFGlitch = 0.0f;
		mStreamData.padding4 = mStreamData.padding5 = mStreamData.padding6 = 0;
		mStreamData.u_MSDFColor = { 1.0f, 1.0f, 1.0f, 1.0f };

		// GITD fog/regime: cheap copy from the once-per-frame cache (see FVisualRegimeState /
		// GVisualRegimeState above), same idiom as the neon-outline copy just below. Reset() must
		// never do the FindCVar lookup itself -- that's StartScene()'s job, once per scene/eye.
		mStreamData.u_gitd_fog_mode = (int)GVisualRegimeState.FogMode;
		mStreamData.u_gitd_fog_density = GVisualRegimeState.FogDensity;
		mStreamData.u_gitd_fog_height = GVisualRegimeState.FogHeight;
		mStreamData.u_gitd_fog_quantize = GVisualRegimeState.FogQuantize;
		mStreamData.u_gitd_fog_rim_power = GVisualRegimeState.FogRimPower;
		mStreamData.u_gitd_fog_speed = GVisualRegimeState.FogSpeed;
		mStreamData.u_gitd_fog_lightlink = (int)GVisualRegimeState.FogLightLink;
		mStreamData.u_vr_visual_regime = (int)GVisualRegimeState.RegimeSelect;
		mStreamData.u_vr_regime_param1 = GVisualRegimeState.RegimeParam1;
		mStreamData.u_vr_regime_param2 = GVisualRegimeState.RegimeParam2;
		mStreamData.u_vr_regime_speed = GVisualRegimeState.RegimeSpeed;
		mStreamData.u_vr_regime_react = (int)GVisualRegimeState.RegimeReact;
		mStreamData.u_vr_regime_center_mask = (int)GVisualRegimeState.RegimeCenterMask;
		mStreamData.u_vr_regime_bubble_size = GVisualRegimeState.RegimeBubbleSize;
		mStreamData.u_vr_regime_jitter = GVisualRegimeState.RegimeJitter;
		mStreamData.u_vr_regime_speed_link = (int)GVisualRegimeState.RegimeSpeedLink;
		mStreamData.u_vr_regime_ping_inten = GVisualRegimeState.RegimePingInten;
		mStreamData.u_gitd_last_hit_time = GVisualRegimeState.LastHitTime;
		mStreamData.u_gitd_last_fire_time = GVisualRegimeState.LastFireTime;
		mStreamData.u_gitd_player_speed = GVisualRegimeState.PlayerSpeed;
		mStreamData.u_gitd_kill_streak = GVisualRegimeState.KillStreak;
		mStreamData.u_vr_thermal_inten = GVisualRegimeState.RegimeThermalInten;
		mStreamData.u_vr_noir_sat = GVisualRegimeState.RegimeNoirSat;
		mStreamData.u_vr_ripples_enabled = (int)GVisualRegimeState.RegimeRipplesEnabled;
		mStreamData.u_vr_ripple_scale = GVisualRegimeState.RegimeRippleScale;
		mStreamData.u_gitd_last_impact_time = GVisualRegimeState.LastImpactTime;
		mStreamData.u_gitd_pad0 = 0;
		mStreamData.u_gitd_pad1 = 0;
		mStreamData.u_vr_blueprint_col = GVisualRegimeState.RegimeBlueprintCol;
		mStreamData.u_gitd_last_impact_pos = GVisualRegimeState.LastImpactPos;

		// Cheap copy from the once-per-frame cache (see FNeonOutlineState / GNeonOutlineState
		// above) -- populated by HWDrawInfo::StartScene() via FindCVar(), never looked up here.
		mStreamData.u_BlackoutMode = GNeonOutlineState.BlackoutMode;
		mStreamData.u_NeonThickness = GNeonOutlineState.NeonThickness;
		mStreamData.u_NeonThreshold = GNeonOutlineState.NeonThreshold;
		mStreamData.u_NeonGlow = GNeonOutlineState.NeonGlow;
		mStreamData.u_NeonPulseSpeed = GNeonOutlineState.NeonPulseSpeed;
		mStreamData.u_neon_pad0 = mStreamData.u_neon_pad1 = mStreamData.u_neon_pad2 = 0;
		mStreamData.u_NeonColorA = GNeonOutlineState.NeonColorA;
		mStreamData.u_NeonColorB = GNeonOutlineState.NeonColorB;

		mModelMatrix.loadIdentity();
		mTextureMatrix.loadIdentity();
		ClearClipSplit();
	}

	void SetNormal(FVector3 norm)
	{
		mStreamData.uVertexNormal = { norm.X, norm.Y, norm.Z, 0.f };
	}

	void SetNormal(float x, float y, float z)
	{
		mStreamData.uVertexNormal = { x, y, z, 0.f };
	}

	void SetColor(float r, float g, float b, float a = 1.f, int desat = 0)
	{
		mStreamData.uVertexColor = { r, g, b, a };
		mStreamData.uDesaturationFactor = desat * (1.0f / 255.0f);
	}

	void SetColor(PalEntry pe, int desat = 0)
	{
		const float scale = 1.0f / 255.0f;
		mStreamData.uVertexColor = { pe.r * scale, pe.g * scale, pe.b * scale, pe.a * scale };
		mStreamData.uDesaturationFactor = desat * (1.0f / 255.0f);
	}

	void SetColorAlpha(PalEntry pe, float alpha = 1.f, int desat = 0)
	{
		const float scale = 1.0f / 255.0f;
		mStreamData.uVertexColor = { pe.r * scale, pe.g * scale, pe.b * scale, alpha };
		mStreamData.uDesaturationFactor = desat * (1.0f / 255.0f);
	}

	void ResetColor()
	{
		mStreamData.uVertexColor = { 1.0f, 1.0f, 1.0f, 1.0f };
		mStreamData.uDesaturationFactor = 0.0f;
	}

	FVector4 GetColor() const
	{
		return mStreamData.uVertexColor;
	}

	float GetDesaturationFactor() const
	{
		return mStreamData.uDesaturationFactor;
	}

	void RestoreColor(FVector4 color, float desat)
	{
		mStreamData.uVertexColor = color;
		mStreamData.uDesaturationFactor = desat;
	}

	void SetTextureClamp(bool on)
	{
		if (on) mTextureClamp = TM_CLAMPY;
		else mTextureClamp = 0;
	}

	void SetTextureMode(int mode)
	{
		mTextureMode = mode;
	}

	void SetTextureMode(FRenderStyle style)
	{
		if (style.Flags & STYLEF_RedIsAlpha)
		{
			SetTextureMode(TM_ALPHATEXTURE);
		}
		else if (style.Flags & STYLEF_ColorIsFixed)
		{
			SetTextureMode(TM_STENCIL);
		}
		else if (style.Flags & STYLEF_InvertSource)
		{
			SetTextureMode(TM_INVERSE);
		}
	}

	int GetTextureMode()
	{
		return mTextureMode;
	}

	int GetTextureModeAndFlags(int tempTM)
	{
		int f = mTextureModeFlags;
		if (!mBrightmapEnabled) f &= ~(TEXF_Brightmap | TEXF_Glowmap);
		if (mTextureClamp) f |= TEXF_ClampY;
		return (mTextureMode == TM_NORMAL && tempTM == TM_OPAQUE ? TM_OPAQUE : mTextureMode) | f;
	}

	void EnableTexture(bool on)
	{
		mTextureEnabled = on;
	}

	void EnableFog(uint8_t on)
	{
		mFogEnabled = on;
	}

	void SetEffect(int eff)
	{
		mSpecialEffect = eff;
	}

	void EnableGlow(bool on)
	{
		if (mGlowEnabled && !on)
		{
			mStreamData.uGlowTopColor = { 0.0f, 0.0f, 0.0f, 0.0f };
			mStreamData.uGlowBottomColor = { 0.0f, 0.0f, 0.0f, 0.0f };
		}
		mGlowEnabled = on;
	}

	void EnableGradient(bool on)
	{
		mGradientEnabled = on;
	}

	void EnableBrightmap(bool on)
	{
		mBrightmapEnabled = on;
	}

	void EnableSplit(bool on)
	{
		if (mSplitEnabled && !on)
		{
			mStreamData.uSplitTopPlane = { 0.0f, 0.0f, 0.0f, 0.0f };
			mStreamData.uSplitBottomPlane = { 0.0f, 0.0f, 0.0f, 0.0f };
		}
		mSplitEnabled = on;
	}

	void EnableModelMatrix(bool on)
	{
		mModelMatrixEnabled = on;
	}

	void EnableTextureMatrix(bool on)
	{
		mTextureMatrixEnabled = on;
	}

	void SetGlowParams(float *t, float *b)
	{
		mStreamData.uGlowTopColor = { t[0], t[1], t[2], t[3] };
		mStreamData.uGlowBottomColor = { b[0], b[1], b[2], b[3] };
	}

	void SetSoftLightLevel(int llevel, int blendfactor = 0)
	{
		if (blendfactor == 0) mLightParms[3] = llevel / 255.f;
		else mLightParms[3] = -1.f;
	}

	void SetNoSoftLightLevel()
	{
		 mLightParms[3] = -1.f;
	}

	void SetGlowPlanes(const FVector4 &tp, const FVector4& bp)
	{
		mStreamData.uGlowTopPlane = tp;
		mStreamData.uGlowBottomPlane = bp;
	}

	// [GITD] localized glow SPOTS cast onto floors/ceilings (N radial pools per draw).
	void EnableWallGlow(bool on)
	{
		if (mWallGlowEnabled && !on)
		{
			mStreamData.uWallGlowSpotCount = 0;
		}
		mWallGlowEnabled = on;
	}

	// spots[i] = FVector4(center.x, center.y(world z), packedRGB, radius); masks[i] = wipe (see struct).
	void SetWallGlowSpots(int count, const FVector4 *spots, const FVector4 *masks)
	{
		if (count > MAX_WALL_GLOW_SPOTS) count = MAX_WALL_GLOW_SPOTS;
		for (int i = 0; i < MAX_WALL_GLOW_SPOTS; i++)
		{
			if (i < count) { mStreamData.uWallGlowSpots[i] = spots[i]; mStreamData.uWallGlowMask[i] = masks[i]; }
			else { mStreamData.uWallGlowSpots[i] = { 0.0f, 0.0f, 0.0f, 0.0f }; mStreamData.uWallGlowMask[i] = { 0.0f, 0.0f, 0.0f, 0.0f }; }
		}
		mStreamData.uWallGlowSpotCount = count;
	}

	void SetGradientPlanes(const FVector4& tp, const FVector4& bp)
	{
		mStreamData.uGradientTopPlane = tp;
		mStreamData.uGradientBottomPlane = bp;
	}

	void SetSplitPlanes(const FVector4& tp, const FVector4& bp)
	{
		mStreamData.uSplitTopPlane = tp;
		mStreamData.uSplitBottomPlane = bp;
	}

	void SetDetailParms(float xscale, float yscale, float bias)
	{
		mStreamData.uDetailParms = { xscale, yscale, bias, 0 };
	}

	void SetDynLight(float r, float g, float b)
	{
		mStreamData.uDynLightColor.X = r;
		mStreamData.uDynLightColor.Y = g;
		mStreamData.uDynLightColor.Z = b;
	}

	void SetScreenFade(float f)
	{
		// This component is otherwise unused.
		mStreamData.uDynLightColor.W = f;
	}

	void SetObjectColor(PalEntry pe)
	{
		mStreamData.uObjectColor = pe;
	}

	void SetObjectColor2(PalEntry pe)
	{
		mStreamData.uObjectColor2 = pe;
	}

	void SetSceneColor(PalEntry sceneColor)
	{
		mSceneColor = sceneColor;
	}

	void SetAddColor(PalEntry pe)
	{
		mStreamData.uAddColor = pe;
	}

	void SetNpotEmulation(float factor, float offset)
	{
#ifdef NPOT_EMULATION
		mStreamData.uNpotEmulation = { offset, factor, 0, 0 };
#endif
	}

	void SetMSDFParams(float enabled, float glitch, const FVector3& color)
	{
		mStreamData.u_IsMSDF = enabled;
		mStreamData.u_MSDFGlitch = glitch;
		mStreamData.u_MSDFColor = { (float)color.X, (float)color.Y, (float)color.Z, 1.0f };
	}

	void ApplyTextureManipulation(TextureManipulation* texfx)
	{
		if (!texfx || texfx->AddColor.a == 0)
		{
			mStreamData.uTextureAddColor.a = 0;	// we only need to set the flags to 0
		}
		else
		{
			// set up the whole thing
			mStreamData.uTextureAddColor.SetIA(texfx->AddColor);
			auto pe = texfx->ModulateColor;
			mStreamData.uTextureModulateColor.SetFlt(pe.r * pe.a / 255.f, pe.g * pe.a / 255.f, pe.b * pe.a / 255.f, texfx->DesaturationFactor);
			mStreamData.uTextureBlendColor = texfx->BlendColor;
		}
	}
	void SetTextureColors(float* modColor, float* addColor, float* blendColor)
	{
		mStreamData.uTextureAddColor.SetFlt(addColor[0], addColor[1], addColor[2], addColor[3]);
		mStreamData.uTextureModulateColor.SetFlt(modColor[0], modColor[1], modColor[2], modColor[3]);
		mStreamData.uTextureBlendColor.SetFlt(blendColor[0], blendColor[1], blendColor[2], blendColor[3]);
	}

	void SetFog(PalEntry c, float d)
	{
		const float LOG2E = 1.442692f;	// = 1/log(2)
		mFogColor = c;
		mStreamData.uFogColor = mFogColor;
		if (d >= 0.0f) mLightParms[2] = d * (-LOG2E / 64000.f);
	}

	void SetLightParms(float f, float d)
	{
		mLightParms[1] = f;
		mLightParms[0] = d;
	}

	PalEntry GetFogColor() const
	{
		return mFogColor;
	}

	void AlphaFunc(int func, float thresh)
	{
		if (func == Alpha_Greater) mAlphaThreshold = thresh;
		else mAlphaThreshold = thresh - 0.001f;
	}

	void SetLightIndex(int index)
	{
		mLightIndex = index;
	}

	void SetBoneIndexBase(int index)
	{
		mBoneIndexBase = index;
	}

	void SetRenderStyle(FRenderStyle rs)
	{
		mRenderStyle = rs;
	}

	void SetRenderStyle(ERenderStyle rs)
	{
		mRenderStyle = rs;
	}

	FRenderStyle GetRenderStyle() const
	{
		return mRenderStyle;
	}


	auto GetDepthBias()
	{
		return mBias;
	}

	void SetDepthBias(float a, float b)
	{
		mBias.mChanged |= mBias.mFactor != a || mBias.mUnits != b;
		mBias.mFactor = a;
		mBias.mUnits = b;
	}

	void SetDepthBias(FDepthBiasState& bias)
	{
		SetDepthBias(bias.mFactor, bias.mUnits);
	}

	void ClearDepthBias()
	{
		mBias.mChanged |= mBias.mFactor != 0 || mBias.mUnits != 0;
		mBias.mFactor = 0;
		mBias.mUnits = 0;
	}

private:
	void SetMaterial(FMaterial *mat, int clampmode, int translation, int overrideshader)
	{
		mMaterial.mMaterial = mat;
		mMaterial.mClampMode = clampmode;
		mMaterial.mTranslation = translation;
		mMaterial.mOverrideShader = overrideshader;
		mMaterial.mChanged = true;
		mTextureModeFlags = mat->GetLayerFlags();
		auto scale = mat->GetDetailScale();
		mStreamData.uDetailParms = { scale.X, scale.Y, 2, 0 };
	}

public:
	void SetMaterial(FGameTexture* tex, EUpscaleFlags upscalemask, int scaleflags, int clampmode, int translation, int overrideshader)
	{
		tex->setSeen();
		if (!sysCallbacks.PreBindTexture || !sysCallbacks.PreBindTexture(this, tex, upscalemask, scaleflags, clampmode, translation, overrideshader))
		{
			if (shouldUpscale(tex, upscalemask)) scaleflags |= CTF_Upscale;
		}
		auto mat = FMaterial::ValidateTexture(tex, scaleflags);
		assert(mat);
		SetMaterial(mat, clampmode, translation, overrideshader);
	}

	void SetMaterial(FGameTexture* tex, EUpscaleFlags upscalemask, int scaleflags, int clampmode, FTranslationID translation, int overrideshader)
	{
		SetMaterial(tex, upscalemask, scaleflags, clampmode, translation.index(), overrideshader);
	}


	void SetClipSplit(float bottom, float top)
	{
		mClipSplit[0] = bottom;
		mClipSplit[1] = top;
	}

	void SetClipSplit(float *vals)
	{
		memcpy(mClipSplit, vals, 2 * sizeof(float));
	}

	void GetClipSplit(float *out)
	{
		memcpy(out, mClipSplit, 2 * sizeof(float));
	}

	void ClearClipSplit()
	{
		mClipSplit[0] = -1000000.f;
		mClipSplit[1] = 1000000.f;
	}

	void SetVertexBuffer(IVertexBuffer *vb, int offset0, int offset1)
	{
		assert(vb);
		mVertexBuffer = vb;
		mVertexOffsets[0] = offset0;
		mVertexOffsets[1] = offset1;
	}

	void SetIndexBuffer(IIndexBuffer *ib)
	{
		mIndexBuffer = ib;
	}

	template <class T> void SetVertexBuffer(T *buffer)
	{
		auto ptrs = buffer->GetBufferObjects(); 
		SetVertexBuffer(ptrs.first, 0, 0);
		SetIndexBuffer(ptrs.second);
	}

	void SetInterpolationFactor(float fac)
	{
		mStreamData.uInterpolationFactor = fac;
	}

	float GetInterpolationFactor()
	{
		return mStreamData.uInterpolationFactor;
	}

	void EnableDrawBufferAttachments(bool on) // Used by fog boundary drawer
	{
		EnableDrawBuffers(on ? GetPassDrawBufferCount() : 1);
	}

	int GetPassDrawBufferCount()
	{
		return mPassType == GBUFFER_PASS ? 3 : 1;
	}

	void SetPassType(EPassType passType)
	{
		mPassType = passType;
	}

	EPassType GetPassType()
	{
		return mPassType;
	}

	void SetSpecialColormap(int cm, float flash)
	{
		mColorMapSpecial = cm;
		mColorMapFlash = flash;
	}

	// API-dependent render interface

	// Draw commands
	virtual void ClearScreen() = 0;
	virtual void Draw(int dt, int index, int count, bool apply = true) = 0;
	virtual void DrawIndexed(int dt, int index, int count, bool apply = true) = 0;

	// Immediate render state change commands. These only change infrequently and should not clutter the render state.
	virtual bool SetDepthClamp(bool on) = 0;					// Deactivated only by skyboxes.
	virtual void SetDepthMask(bool on) = 0;						// Used by decals and indirectly by portal setup.
	virtual void SetDepthFunc(int func) = 0;					// Used by models, portals and mirror surfaces.
	virtual void SetDepthRange(float min, float max) = 0;		// Used by portal setup.
	virtual void SetColorMask(bool r, bool g, bool b, bool a) = 0;	// Used by portals.
	virtual void SetStencil(int offs, int op, int flags=-1) = 0;	// Used by portal setup and render hacks.
	virtual void SetCulling(int mode) = 0;						// Used by model drawer only.
	virtual void EnableClipDistance(int num, bool state) = 0;	// Use by sprite sorter for vertical splits.
	virtual void Clear(int targets) = 0;						// not used during normal rendering
	virtual void EnableStencil(bool on) = 0;					// always on for 3D, always off for 2D
	virtual void SetScissor(int x, int y, int w, int h) = 0;	// constant for 3D, changes for 2D
	virtual void SetViewport(int x, int y, int w, int h) = 0;	// constant for all 3D and all 2D
	virtual void EnableDepthTest(bool on) = 0;					// used by 2D, portals and render hacks.
	virtual void EnableMultisampling(bool on) = 0;				// only active for 2D
	virtual void EnableLineSmooth(bool on) = 0;					// constant setting for each 2D drawer operation
	virtual void EnableDrawBuffers(int count, bool apply = false) = 0;	// Used by SSAO and EnableDrawBufferAttachments

	void SetColorMask(bool on)
	{
		SetColorMask(on, on, on, on);
	}

	void ResetFadeColor()
	{
		mFadeColor = gl_global_fade_color;
		mStreamData.uGlobalFadeColor = mFadeColor;
		mStreamData.uGlobalFade = gl_global_fade ? 1 : 0;
		mStreamData.uGlobalFadeMode = gl_global_fade_debug ? 2 : -1;
		mStreamData.uGlobalFadeDensity = gl_global_fade_density;
		mStreamData.uGlobalFadeGradient = gl_global_fade_gradient;
		mStreamData.uLightRangeLimit = gl_light_range_limit;
	}

	void InitSceneClearColor()
	{
		float r, g, b;
		if (gl_global_fade)
		{
			mSceneColor = mFadeColor;
		}
		r = g = b = 1.f;
		screen->mSceneClearColor[0] = mSceneColor.r * r / 255.f;
		screen->mSceneClearColor[1] = mSceneColor.g * g / 255.f;
		screen->mSceneClearColor[2] = mSceneColor.b * b / 255.f;
	}

};

