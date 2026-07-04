# DoomXR Whip — IQM Procedural Rigging Patch Spec
### Technical companion to `DoomXR_Physics_Whip.md` §Q · 2026-07-03

---

## 0. Correction, stated plainly

An earlier pass on this document framed "ZScript cannot write IQM bone transforms" as a dead end. That
framing was wrong. The engine has a mature native/ZScript bridge (`DEFINE_ACTION_FUNCTION`, `DEFINE_FIELD`)
used everywhere in this fork — `AttackPos`, `OffhandPos`, `Level.AddGlowPanel`, `player.OffhandWeapon`,
`msdf_*`, dozens more. **ZScript already speaks to C++ constantly in this engine.** The correct statement was
never "impossible" — it's **"no thunk has been written for this yet, and here is exactly the one to write."**
This document is that spec, and it's grounded in code I read directly this session, not secondhand summary.

---

## 1. What already exists — the pipeline, verified by direct read

DoomXR's IQM stack (stock GZDoom 4.12+ lineage, present unmodified in this fork) already has a **per-bone
pose primitive** and an **override seam** designed into it. Nobody has connected the seam to ZScript. That's
the entire gap.

### 1.1 `TRS` — the per-bone pose primitive
`src\common\utility\TRS.h` (verified, full file read):
```cpp
class TRS
{
public:
    FVector3 translation;
    FVector4 rotation;   // quaternion, (x,y,z,w)
    FVector3 scaling;
    // default ctor: translation=(0,0,0), rotation=(0,0,0,1) [identity], scaling=(0,0,0)  <-- GOTCHA, see §6
};
```
This is the exact unit a procedural whip needs to push per bone, per tic: a translation + a rotation
quaternion (+ scale). **⚠️ Note the default `scaling = (0,0,0)`** — a naively-constructed `TRS` collapses the
bone to nothing. Any code that builds one must explicitly set `scaling = FVector3(1,1,1)` unless it means to.

### 1.2 `IQMJoint` — the bind-pose skeleton
`src\common\models\model_iqm.h:68-75` (verified):
```cpp
struct IQMJoint
{
    FString  Name;
    int32_t  Parent;      // parent < 0 means root
    FVector3 Translate;
    FVector4 Quaternion;
    FVector3 Scale;
};
```
`IQMModel` holds `TArray<IQMJoint> Joints;` (`model_iqm.h:146`) — **but it's `private:`**. There is currently
no public accessor for bone name→index or hierarchy. (§3.3 below adds one.)

### 1.3 `IQMModel::TRSData` — the baked animation
`model_iqm.h:159`: `TArray<TRS> TRSData;` — a flat `num_frames × num_bones` array of baked keyframes, filled
once at `Load()` (`models_iqm.cpp:178-207`) straight from the `.iqm` file's authored animation data. This is
what a named `SetAnimation()` call ultimately plays back.

### 1.4 The override seam — `animationData`, already designed in
This is the load-bearing discovery. Three functions in the render path **already accept an externally-supplied
pose buffer** instead of the model's own baked `TRSData`:

`src\common\models\model.h:107-111` (base class `FModel`, verified):
```cpp
virtual const TArray<TRS>* AttachAnimationData() { return nullptr; }
virtual ModelAnimFrame PrecalculateFrame(const ModelAnimFrame&, const ModelAnimFrameInterp&, float,
                                          const TArray<TRS>* animationData) { return nullptr; }
virtual const TArray<VSMatrix>* CalculateBones(const ModelAnimFrame&, const ModelAnimFrameInterp&, float,
                                                const TArray<TRS>* animationData) { return nullptr; }
```
`src\common\models\models_iqm.cpp:680-682` (`IQMModel::CalculateBonesIQM`, verified — I read this function
body directly):
```cpp
const TArray<VSMatrix>* IQMModel::CalculateBonesIQM(int frame1, int frame2, float inter, ..., const TArray<TRS>* animationData)
{
    const TArray<TRS>& animationFrames = animationData ? *animationData : TRSData;   // <-- THE SEAM
    ...
    for (int i = 0; i < numbones; i++)
    {
        // pulls animationFrames[offset1+i] / [offset2+i], interpolates, builds VSMatrix, writes boneData[i]
    }
}
```
**If `animationData` is non-null, the model's own baked animation is ignored entirely** and the engine
interpolates/renders whatever buffer was handed in — using the exact same code path, same GPU upload, same
everything. This was clearly built for a future procedural-animation feature that was never finished (per the
engine comment at `models.cpp:624`, "*while per-model animations aren't done...*"). **It is finished enough
for us.**

### 1.5 The call site — `ProcessModelFrame`
`src\r_data\models.cpp:573-609` (verified, full function read):
```cpp
const TArray<VSMatrix>* ProcessModelFrame(FModel* animation, bool nextFrame, int i,
    const FSpriteModelFrame* smf, DActorModelData* modelData,
    const CalcModelFrameInfo& frameinfo, ModelDrawInfo& drawinfo, bool is_decoupled, double tic)
{
    const TArray<TRS>* animationData = nullptr;
    if (drawinfo.animationid >= 0)
    {
        animation = Models[drawinfo.animationid];
        animationData = animation->AttachAnimationData();     // <-- only source today: the model's OWN baked data
    }
    const TArray<VSMatrix>* boneData = nullptr;
    if (is_decoupled) { boneData = animation->CalculateBones(..., animationData); }
    else              { boneData = animation->CalculateBones(..., animationData); }
    return boneData;
}
```
`modelData` (a `DActorModelData*`, the **per-actor** native model state) is *already a parameter here* — it's
just not consulted for pose data. That's the one-line gap.

### 1.6 `DActorModelData` — the per-actor container to extend
`src\playsim\actor.h:733-752` (verified, full class read):
```cpp
class DActorModelData : public DObject
{
    DECLARE_CLASS(DActorModelData, DObject);
public:
    PClass*                   modelDef;
    TArray<ModelOverride>     models;
    TArray<FTextureID>        skinIDs;
    TArray<AnimModelOverride> animationIDs;
    TArray<int>                modelFrameGenerators;
    int flags, overrideFlagsSet, overrideFlagsClear;
    ModelAnim      curAnim;
    ModelAnimFrame prevAnim;
    // NO bone/pose field today — this is exactly what the patch adds.
};
```
This is the native object that ZScript's `A_ChangeModel`/`SetAnimation` already mutate today, via the
existing model-override machinery. Adding a pose buffer here follows the file's own established pattern.

---

## 2. The patch — file by file

**Lane check: every file below is ✅ non-shader.** The bone matrices still upload through the existing GPU
bone buffer (`screen->mBones->UploadBones`) — no shader, no `hw_renderstate.h`, no `.fp` file is touched.
This entire patch lives in the whip's own lane.

### 2.1 `src\playsim\actor.h` — add the pose buffer to `DActorModelData`
```cpp
class DActorModelData : public DObject
{
    ...
    ModelAnim      curAnim;
    ModelAnimFrame prevAnim;

    TArray<TRS>    proceduralPose;     // NEW — one TRS per bone, ZScript-writable
    bool           useProceduralPose = false;  // NEW — explicit opt-in flag
    ...
};
```
(`TRS.h` needs including here — it's a small, dependency-light header, already pulled in by `model.h`.)

### 2.2 `src\r_data\models.cpp` — the one-line override in `ProcessModelFrame`
```cpp
const TArray<TRS>* animationData = nullptr;
if (modelData && modelData->useProceduralPose && modelData->proceduralPose.Size() > 0)
{
    animationData = &modelData->proceduralPose;               // NEW — takes priority
}
else if (drawinfo.animationid >= 0)
{
    animation = Models[drawinfo.animationid];
    animationData = animation->AttachAnimationData();
}
```
Everything downstream — `CalculateBones`, `CalculateBonesIQM`, the GPU upload — needs **zero changes**. It
already branches on `animationData ? *animationData : TRSData` (§1.4). This is the entire render-path patch.

### 2.3 `src\common\models\model.h` + `models_iqm.cpp` — bone introspection
The base class needs a way to answer "how many bones, what are they called, what's the hierarchy" so
ZScript can address bones by name instead of guessing indices. Add to `FModel` (mirroring the existing
`AttachAnimationData` virtual-with-default pattern):
```cpp
// model.h, FModel
virtual int   NumBones() { return 0; }
virtual FName BoneName(int index) { return NAME_None; }
virtual int   BoneParent(int index) { return -1; }
```
Override in `IQMModel` (`models_iqm.cpp`), reading the existing private `Joints` array:
```cpp
int   IQMModel::NumBones() { return Joints.SSize(); }
FName IQMModel::BoneName(int i) { return (i>=0 && i<Joints.SSize()) ? FName(Joints[i].Name) : NAME_None; }
int   IQMModel::BoneParent(int i) { return (i>=0 && i<Joints.SSize()) ? Joints[i].Parent : -1; }
```

### 2.4 Native ZScript thunks — `src\scripting\vmthunks_actors.cpp` (or `p_actionfunctions.cpp`, matching where `SetAnimation` lives, `p_actionfunctions.cpp:5221`)
Following the exact convention already used for `Thrust`/`SetAnimation` in this file:
```cpp
DEFINE_ACTION_FUNCTION_NATIVE(AActor, SetModelUseProceduralPose, SetModelUseProceduralPose)
{
    PARAM_SELF_PROLOGUE(AActor);
    PARAM_BOOL(enable);
    auto data = self->GetModelData(true);      // existing lazy-create accessor (mirrors A_ChangeModel's pattern)
    data->useProceduralPose = enable;
    return 0;
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, SetModelBonePose, SetModelBonePose)
{
    PARAM_SELF_PROLOGUE(AActor);
    PARAM_INT(boneIndex);
    PARAM_FLOAT(tx); PARAM_FLOAT(ty); PARAM_FLOAT(tz);
    PARAM_FLOAT(qx); PARAM_FLOAT(qy); PARAM_FLOAT(qz); PARAM_FLOAT(qw);
    auto data = self->GetModelData(true);
    if (boneIndex >= data->proceduralPose.Size())
        data->proceduralPose.Resize(boneIndex + 1);
    TRS& t = data->proceduralPose[boneIndex];
    t.translation = FVector3(tx, ty, tz);
    t.rotation    = FVector4(qx, qy, qz, qw);
    t.scaling     = FVector3(1, 1, 1);           // MUST set — TRS default is (0,0,0), see §1.1
    return 0;
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, GetModelBoneIndex, GetModelBoneIndex)
{
    PARAM_SELF_PROLOGUE(AActor);
    PARAM_NAME(boneName);
    FModel* m = /* resolve from self's current model index, per ProcessModelFrame's Models[drawinfo.modelid] */;
    int n = m ? m->NumBones() : 0;
    for (int i = 0; i < n; i++) if (m->BoneName(i) == boneName) { ACTION_RETURN_INT(i); }
    ACTION_RETURN_INT(-1);
}
```
`self->GetModelData(true)` is written here as *the pattern to reuse* — `A_ChangeModel` already lazily
creates/fetches a `DActorModelData` on the actor; the patch should hook into that same accessor rather than
invent a second one. (Exact accessor name to confirm against `p_actionfunctions.cpp`'s `A_ChangeModel` impl
when this is actually implemented — see §6.)

### 2.5 `wadsrc\static\zscript\actors\actor.zs` — the ZScript surface
Alongside the existing model API (`SetAnimation` is declared around line 1343):
```
native void SetModelUseProceduralPose(bool enable);
native void SetModelBonePose(int boneIndex, double tx, double ty, double tz, double qx, double qy, double qz, double qw);
native int  GetModelBoneIndex(Name boneName);
native int  GetModelBoneCount();
```

---

## 3. Whip-side usage — per tic (UPDATED: rotation-only + Y-up coord space, swarm-verified §7)

`TRS.translation` is LOCAL to parent bone space (confirmed, §5 Item 1). The whip uses the standard
**rotation-only** rope technique: bone translations are constant (the rest-distance to the next node), and
only rotations change to curve the chain — exactly how every production rope/spine rig works.

**⚠️ COORDINATE SPACE (swarm-corrected):** procedural TRS bone data is consumed in **IQM Y-up space**, *before*
the engine applies its `swapYZ` (see §7 Finding 2). Do **NOT** pre-swap your values. The bone forward axis in
this space is best-current **engine +Y `(0,1,0)`**, held in `BONE_FWD` below — a single constant so a 20-minute
two-bone empirical test can flip it to `(0,0,1)` if the specific IQM export differs (§7 Finding 2 open item).

`Quat` is a **confirmed first-class ZScript type** (§7 Finding 1): `qA * qB`, `myQuat * vec3`, `.Conjugate()`,
`.Inverse()`, `QuatStruct.AxisAngle/FromAngles/SLerp` all work.

```zscript
// In XRWhip (or XRWhipController).Tick():
//   P[0..N] = Verlet node positions this tic (see §E)
//   SEGMENT_LENGTH = bind-pose bone length (fixed — depends on IQM bone spacing)
//   BONE_FWD = (0,1,0) engine +Y — the axis a rest-pose bone points along (verify via 2-bone test, §7)

const BONE_FWD_X = 0.0, BONE_FWD_Y = 1.0, BONE_FWD_Z = 0.0;   // the ONE value the empirical test locks

whipModelActor.SetModelUseProceduralPose(true);

Quat parentWorldRot = QuatStruct.FromAngles(0, 0, 0);   // identity; accumulate down the chain

for (int i = 0; i < NUM_SEGMENTS; i++)
{
    Vector3 segDir = (P[i + 1] - P[i]).Unit();          // world-space segment direction

    // Rotate BONE_FWD onto segDir (build a shortest-arc quat — helper below)
    Quat worldRot = QuatFromTo((BONE_FWD_X, BONE_FWD_Y, BONE_FWD_Z), segDir);

    // Convert to LOCAL by subtracting accumulated parent rotation.
    // Use .Conjugate() (1 opcode) not .Inverse() (3 opcodes) — all our quats are unit (§7 Finding 1 gotcha).
    Quat localRot = parentWorldRot.Conjugate() * worldRot;

    // translation stays along BONE_FWD at rest length; ONLY rotation curves the chain
    whipModelActor.SetModelBonePose(
        i,
        BONE_FWD_X * SEGMENT_LENGTH, BONE_FWD_Y * SEGMENT_LENGTH, BONE_FWD_Z * SEGMENT_LENGTH,
        localRot.X, localRot.Y, localRot.Z, localRot.W
    );

    parentWorldRot = worldRot;             // this bone's world rotation parents the next
}
```

`QuatFromTo(a, b)` is a small pure-ZScript static helper (shortest-arc rotation from unit vector `a` to unit
vector `b`): `axis = a cross b; angle = acos(clamp(a dot b, -1, 1)); return QuatStruct.AxisAngle(axis.Unit(),
angle_deg)` — with the antiparallel guard (`|axis| ~ 0 && a·b < 0` → 180° about any perpendicular). All the
pieces (`cross`, `dot`, `.Unit()`, `QuatStruct.AxisAngle`) are confirmed-present ZScript primitives.

The root bone (bone 0, the handle) is the only bone whose translation varies — set it to the handle's
actor-local position. All child bones use the fixed `BONE_FWD * SEGMENT_LENGTH`.

---

## 4. Why this is a small, low-risk, in-lane patch

- **No shader file touched.** Bone matrices already upload through the existing GPU bone buffer
  (`screen->mBones->UploadBones`, per the render path) — the same path every rigged model already uses.
  Nothing about *how* bones reach the GPU changes; only *where the CPU-side pose numbers come from* changes.
- **No render-path branching risk beyond one `if`.** §2.2 is a single conditional inserted before existing
  logic; every other actor's models (monsters, weapons, the player's own hand model) are completely
  unaffected because `useProceduralPose` defaults `false`.
- **Rides an existing, designed extension point** (`animationData` override) rather than inventing a new
  pipeline — the interpolation, hierarchy composition, and GPU skinning code is untouched and already tested
  by every IQM model in the game.
- **Entirely in the non-shader lane** — `actor.h`, `models.cpp`, `model.h`, `models_iqm.cpp`,
  `vmthunks_actors.cpp`/`p_actionfunctions.cpp`, `actor.zs`. None of these appear in `SESSION_LANES.md`'s
  shader list.

---

## 5. Open items — ALL CLOSED (2026-07-03, second read session)

**Verified by direct read this session** (not swarm paraphrase): `TRS.h` (full file), `IQMJoint`/`IQMModel`
class layout (`model_iqm.h`, full file), `FModel`'s `AttachAnimationData`/`CalculateBones` virtuals
(`model.h`), `IQMModel::CalculateBonesIQM` (`models_iqm.cpp:680-767`, full function including hierarchy loop),
`ProcessModelFrame` (`models.cpp:573-609`, full function), `DActorModelData` (`actor.h:733-752`, full class),
`ChangeModelNative` (`p_actionfunctions.cpp:5461-5507`, accessor call site).

---

### ✅ Item 1 — TRS coordinate space (resolved: LOCAL, not world)

Read `models_iqm.cpp:740-761` (the bone-hierarchy composition loop):
```cpp
VSMatrix m;
m.translate(bone.translation.X, bone.translation.Y, bone.translation.Z);
m.multQuaternion(bone.rotation);
m.scale(bone.scaling.X, bone.scaling.Y, bone.scaling.Z);

VSMatrix& result = boneData[i];
if (Joints[i].Parent >= 0)
{
    result = boneData[Joints[i].Parent];  // start from parent's accumulated world matrix
    result.multMatrix(swapYZ);
    result.multMatrix(baseframe[Joints[i].Parent]);
    result.multMatrix(m);                 // LOCAL TRS applied as delta
    result.multMatrix(inversebaseframe[i]);
}
```

**`TRS.translation` is a LOCAL delta transform in the parent bone's coordinate space, not a world position.**
`m` is multiplied INTO the parent's accumulated matrix — standard parent-relative bone chain composition.

**Consequence for whip ZScript:** do NOT write Verlet world positions into `translation`. Instead use the
**rotation-only technique**:
- Bone translations in `proceduralPose` are fixed to `BONE_FWD * segment_length` — the bind-pose rest distance
- Only bone ROTATIONS vary each tic, encoding how each segment bends relative to its parent
- This is how every spine/rope rig works in production: constant-length bones, varying rotations

**⚠️ Coordinate-space correction (swarm-verified, §7 Finding 2):** the local TRS is consumed in **IQM Y-up
space, before the engine's `swapYZ`**. `BONE_FWD = (0,1,0)` (engine +Y) is the best-current forward axis; do
not pre-swap. The exact axis for a given `.iqm` is the single empirical unknown a two-bone test resolves.

The per-tic ZScript math (see §3 below, updated):
```
// Verlet gives world-space positions P[0..N]
// Track accumulated world rotation as you walk down the chain
Quat parentWorldRot = Quat.Identity();
for (int i = 0; i < NUM_SEGS; i++)
{
    Vector3 dir = (P[i+1] - P[i]).Unit();               // world-space segment direction
    Quat worldRot = QuatFromForward(dir, worldUp);       // world-space rotation for this segment
    Quat localRot  = parentWorldRot.Inverse() * worldRot; // subtract accumulated parent = LOCAL rotation
    SetModelBonePose(i, 0, 0, SEGMENT_LENGTH,
                     localRot.X, localRot.Y, localRot.Z, localRot.W);
    parentWorldRot = worldRot;  // becomes next bone's parent
}
```

---

### ✅ Item 2 — `DActorModelData` lazy-create accessor (resolved: `EnsureModelData`, free function)

Read `p_actionfunctions.cpp:5507`:
```cpp
EnsureModelData(mobj);   // free function — NOT a method on self/actor
```

The §2.4 thunks must call `EnsureModelData(self)` then directly access `self->modelData`:
```cpp
DEFINE_ACTION_FUNCTION_NATIVE(AActor, SetModelBonePose, SetModelBonePose)
{
    PARAM_SELF_PROLOGUE(AActor);
    PARAM_INT(boneIndex);
    // ...params...
    EnsureModelData(self);    // ← correct call
    TRS& t = self->modelData->proceduralPose[boneIndex];
    // ...
}
```
Not `self->GetModelData(true)` — that was a stand-in name, now corrected.

---

### ✅ Item 3 — per-actor vs per-slot (resolved: per-actor, flat array is correct)

`DActorModelData` is a single object per actor (`AActor::modelData` — one pointer). The multi-slot model
handling lives INSIDE it (`TArray<ModelOverride> models` for index remapping). A flat `TArray<TRS> proceduralPose`
on the `DActorModelData` struct applies to whichever IQM is currently active on the actor — which for the
whip is exactly one. No per-slot nesting needed.

---

## 6. Relationship to the living doc's model strategies (§Q)

This is **Strategy D** from `DoomXR_Physics_Whip.md` §Q — "push the sim's node transforms straight onto the
model's bones each tic." With this seam now mapped, Strategy D is not a hypothetical fourth option — it's a
concretely scoped, non-shader, low-risk patch that rides infrastructure the engine already half-built.
Strategies A/B/C remain valid **ship-now** paths while this patch is written and tested; D is the "true 1:1
leather whip" upgrade once ready. Recommend: prototype A/B first (zero engine risk, playable today), and
schedule this patch as the follow-up that turns the segmented/hybrid whip into the fully rigged one.

---

## 7. Confidence audit — 3-topic adversarial swarm (2026-07-03)

A 7-agent workflow (3 parallel deep-reads → 3 adversarial refutation passes → 1 synthesis) independently
verified the three highest-risk assumptions in this spec against DOOM_FRESH source. Full transcript retained.

### Finding 1 — ZScript `Quat` type · CONFIRMED · **98/100** (adversarial: NONE refuted)
`Quat` is a **first-class ZScript value type** (`types.cpp:445-453`, registered as `NAME_Quat`, X/Y/Z/W
doubles). Everything the whip's bone math needs is present and dedicated-opcode backed:
- `qA * qB` → `MULQQ_RR` (`codegen.cpp:3689`, exec `vmexec.h:1903`)
- `myQuat * vec3` → `MULQV3_RR` (`codegen.cpp:3697`), returns rotated `Vector3` via Hamilton sandwich (`quaternion.h:288`)
- `.Conjugate()` → `OP_CONJQ`; `.Inverse()` → `DOTV4_RR`+`CONJQ`+`DIVVF4_RR` — **both compiler intrinsics**
  (`codegen.cpp:9066`, 10419-10429), working even though **commented out in `base.zs:969-971`**
- `QuatStruct.SLerp/NLerp/FromAngles(yaw,pitch,roll)/AxisAngle(vec3,deg)` static factories (`base.zs:960-972`)
- `.Length()/.LengthSquared()/.Unit()` also intrinsics (`codegen.cpp:9066`)
- JIT path wired (`jit_math.cpp:1620-1686`); a past JIT bug in Conjugate/Inverse is **already fixed** in this build (metainfo changelog)

**Gotchas:** type name is `Quat` not `Quaternion`; fields X/Y/Z/W with W=scalar; for unit quats prefer
`.Conjugate()` (1 opcode) over `.Inverse()` (3). **No** `FromMatrix`/`ToMatrix` bridge (irrelevant — we build
from direction vectors). This retires the biggest prior risk: no manual `Vector4` quaternion math is needed.

### Finding 2 — IQM bone axis / `swapYZ` · CONFIRMED · **91/100** (adversarial: WEAK)
The coordinate flow is now source-traced:
- `LoadPosition` (`models_iqm.cpp:332-334`) and `LoadNormal` (:373) swap Y↔Z on load → IQM Y-up becomes Doom Z-up for geometry
- `baseframe` built with **no** swapYZ (:154-176) → lives in IQM Y-up
- `CalculateBonesIQM` sandwiches every bone in `swapYZ`: `swapYZ * ... * m * ... * swapYZ` (:749-761) → **bone-local TRS operates in IQM Y-up**, outer swapYZ converts final skin matrices to Z-up to match the swapped vertices
- **⇒ procedural TRS you write is consumed in IQM Y-up, before swapYZ — do NOT pre-swap. `BONE_FWD = (0,1,0)`.**

**Hazard surfaced by adversary (real, added to spec):** `GetBasePose()` (`model_iqm.h:161`) returns raw Y-up
`baseframe` **with no swapYZ** — this fires on `MDL_MODELSAREATTACHMENTS`/`DECOUPLEDANIMATIONS` when no anim
frame is active. **Keep the whip on the standard animated path**; never mix base-pose bone output with
animated bone output.

**The single remaining empirical unknown:** the exact rest axis baked into a specific `.iqm` depends on the
Blender exporter version, and `vhand.iqm` isn't in the repo to inspect. **Resolution = a 20-minute two-bone
test export** (known orientation → load → observe Doom-space direction). This is a test, not a code-reading
gap — it's why this is 91 and not 98. `BONE_FWD` is a single constant so flipping it is a one-line change.

### Finding 3 — `MDL_FOLLOW` flag · **REFUTED · flag does not exist** (adversarial: NONE — refutation stands 99/100)
**`MDL_FOLLOW` was invented in an earlier draft. It is not in the engine.** Exhaustive grep = zero matches.
The real `MDL_` enum (`models.h:44-63`) has exactly 15 flags; none is FOLLOW or WEAPONTOPLAYER. (`CMDL_WEAPONTOPLAYER`
exists but is an `A_ChangeModel` target-selector, unrelated to VR tracking.)

**The real VR-hand positioning mechanism — no MODELDEF flag at all:**
- HUD weapon models get the live controller matrix in C++ (`RenderHUDModel` → `GetWeaponTransform`, `models.cpp:254`) — HUD psprite path only
- **World-space actors (the whip's segments/anchors) track the hand by reading `AttackPos`/`OffhandPos` each tic and calling `SetOrigin()`**. These are readonly native fields (`actor.zs:273,277`), written every render frame by the OpenXR/OpenVR thread.
- **Live precedent to copy:** `weaponshieldsaw.zs:89` (OffhandPos), `gitd_dark.zs:361,367` (AttackPos/OffhandPos).

**Caveat:** world-space actors are one render-frame behind the controller (AttackPos is written during render).
For a handle that must be sub-frame glued to the hand, keep *that piece* a PSprite HUD layer; the flexible
thong/segments as world actors is fine.

### Net effect on the two build tiers
- **Tier 1 — segment-actor chain (Strategy A):** now **fully de-risked, zero C++ patch.** Verlet → `SetOrigin`
  from `AttackPos`, with working precedent files. Ship-today path.
- **Tier 2 — single skinned IQM procedural bones (Strategy D, this doc):** all primitives confirmed real
  (`Quat` math ✅, `animationData` seam ✅, `EnsureModelData` accessor ✅). Only the bone rest-axis needs the
  empirical lock. The C++ patch itself is unchanged in shape.
