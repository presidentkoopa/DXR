#pragma once

#include <stdint.h>
#include "textureid.h"
#include "i_modelvertexbuffer.h"
#include "matrix.h"
#include "palettecontainer.h"
#include "TRS.h"
#include "tarray.h"
#include "name.h"
#include "fs_files.h"

#include "bonecomponents.h"

class DBoneComponents;
class FModelRenderer;
class FGameTexture;
class IModelVertexBuffer;
class FModel;
class PClass;
struct FSpriteModelFrame;

FTextureID LoadSkin(const char* path, const char* fn);
void FlushModels();


extern TDeletingArray<FModel*> Models;
extern TArray<FSpriteModelFrame> SpriteModelFrames;
extern TMap<const PClass*, FSpriteModelFrame> BaseSpriteModelFrames;

// [XR] Raised 32 -> 128: max separately-textured SURFACES per model (per-SurfaceSkin). The
// DOOM Eternal marine already uses 7; complex future assets (mechs, detailed characters with
// many material slots) can exceed 32. SAFE bump -- every MD3_MAX_SURFACES usage is a dynamic
// TArray Alloc/Resize, a bound check, or a stride multiply; there is NO fixed C-array, GPU
// uniform, or stack buffer sized by it, so this only grows dynamic allocations (a few KB per
// modeldef). NOTE: models-per-actor is NOT capped here -- modelsAmount is dynamic (highest
// Model index +1, floor MIN_MODELS), the only ceiling being its uint8_t type (255 models).
#define MD3_MAX_SURFACES	128
#define MIN_MODELS	4

struct FSpriteModelFrame
{
	uint8_t modelsAmount = 0;
	TArray<int> modelIDs;
	TArray<FTextureID> skinIDs;
	TArray<FTextureID> surfaceskinIDs;
	TArray<int> modelframes;
	TArray<int> animationIDs;
	float xscale, yscale, zscale;
	// [BB] Added zoffset, rotation parameters and flags.
	// Added xoffset, yoffset
	float xoffset, yoffset, zoffset;
	float xrotate, yrotate, zrotate;
	float rotationCenterX, rotationCenterY, rotationCenterZ;
	float rotationSpeed;
private:
	unsigned int flags;
public:
	const void* type;	// used for hashing, must point to something usable as identifier for the model's owner.
	short sprite;
	short frame;
	int hashnext;
	float angleoffset;
	// added pithoffset, rolloffset.
	float pitchoffset, rolloffset; // I don't want to bother with type transformations, so I made this variables float.
	bool isVoxel;
	unsigned int getFlags(class DActorModelData * defs) const;
	// [XR] OR extra render flags onto a runtime-built COPY of a frame. Used by the native weapon
	// MD3<->IQM format swap (hw_weapon.cpp) to force MDL_MODELSAREATTACHMENTS so a 0-baked-frame
	// rigged IQM uploads its bind pose -- without it a rigged 0-frame model renders no geometry.
	void XR_OrFlags(unsigned int f) { flags |= f; }
	friend void InitModels();
	friend void ParseModelDefLump(int Lump);
};


enum ModelRendererType
{
	GLModelRendererType,
	SWModelRendererType,
	PolyModelRendererType,
	NumModelRendererTypes
};

enum EFrameError
{
	FErr_NotFound = -1,
	FErr_Voxel = -2,
	FErr_Singleframe = -3
};

class FModel
{
public:
	enum LoadState
	{
		NONE = 0,
		LOADING = 1,
		READY = 2
	};

	FModel();
	virtual ~FModel();

	virtual bool Load(const char * fn, int lumpnum, const char * buffer, int length) = 0;

	virtual int FindFrame(const char * name, bool nodefault = false) = 0;

	// [RL0] these are used for decoupled iqm animations
	virtual int FindFirstFrame(FName name) { return FErr_NotFound; }
	virtual int FindLastFrame(FName name) { return FErr_NotFound; }
	virtual double FindFramerate(FName name) { return FErr_NotFound; }

	virtual void RenderFrame(FModelRenderer *renderer, FGameTexture * skin, int frame, int frame2, double inter, FTranslationID translation, const FTextureID* surfaceskinids, int boneStartPosition) = 0;
	virtual void BuildVertexBuffer(FModelRenderer *renderer) = 0;
	virtual void AddSkins(uint8_t *hitlist, const FTextureID* surfaceskinids) = 0;
	virtual float getAspectFactor(float vscale) { return 1.f; }
	virtual const TArray<TRS>* AttachAnimationData() { return nullptr; };

	virtual ModelAnimFrame PrecalculateFrame(const ModelAnimFrame &from, const ModelAnimFrameInterp &to, float inter, const TArray<TRS>* animationData) { return nullptr; };

	virtual const TArray<VSMatrix>* CalculateBones(const ModelAnimFrame &from, const ModelAnimFrameInterp &to, float inter, const TArray<TRS>* animationData) { return nullptr; };

	virtual const TArray<VSMatrix>* GetBasePose() {return nullptr;}

	// ---- VR arm-IK joint introspection (native; read-only bind-pose access used by
	// VR_UpdateArmIK in playsim/p_user.cpp). These are safe no-ops on the base class so
	// the IK solver can call them on ANY FModel* (MD3/voxel/etc) without an RTTI/type
	// check first -- GetJointCount()==0 on a non-IQM model is itself the "not an IQM"
	// signal the caller bails on. Only IQMModel (model_iqm.h) overrides these for real.
	virtual int GetJointCount() const { return 0; }
	virtual bool GetJointBindTRS(int jointIndex, TRS& out) const { return false; }
	virtual int GetJointParent(int jointIndex) const { return -1; }
	virtual int FindJointByName(FName name) const { return -1; }
	// [XR] Case-INSENSITIVE joint-name lookup (hs_* hotspots may not match ZScript-literal case).
	// Base no-op -> -1 on any non-IQM model, same pattern as FindJointByName above.
	virtual int FindJointByNameCI(FName name) const { return -1; }
	// [XR] Parent-resolved MODEL-LOCAL bind position of a joint (translation column of
	// baseframe[jointIndex]). Read-only static bind data; base no-op so callers can invoke on
	// ANY FModel* (MD3 -> false) with no dynamic_cast. Only IQMModel overrides it for real.
	virtual bool GetJointBaseframePos(int jointIndex, FVector3& out) const { return false; }

	void SetVertexBuffer(int type, IModelVertexBuffer *buffer) { mVBuf[type] = buffer; }
	IModelVertexBuffer *GetVertexBuffer(int type) const { return mVBuf[type]; }
	void DestroyVertexBuffer();
	LoadState GetLoadState() const { return loadState; }
	void SetLoadState(LoadState state) { loadState = state; }
	virtual void LoadGeometry(FileSys::FileData* lumpData);
	int GetLumpNum() const { return mLumpNum; }

	bool hasSurfaces = false;

	FString mFileName;
	std::pair<FString, FString> mFilePath;
	
	FSpriteModelFrame *baseFrame;
private:
	IModelVertexBuffer *mVBuf[NumModelRendererTypes];
	LoadState loadState = NONE;
protected:
	int mLumpNum = -1;
};

int ModelFrameHash(FSpriteModelFrame* smf);
unsigned FindModel(const char* path, const char* modelfile, bool silent = false);

