#pragma once

#include "common/utility/vectors.h"   // DVector3 (is a typedef, not forward-declarable)

struct HWDrawInfo;
class FRenderState;
class VSMatrix;
class FGameTexture;
struct PalEntry;

// Public entry points onto the wheel's own world-space quad/disc draw primitives
// (DrawWorldQuad/DrawWorldDisc, internal to hw_vrwheel.cpp) so other native VR-UI
// renderers (e.g. VRHardpointGrid_Draw) can reuse them instead of re-deriving the
// vertex-buffer/render-state boilerplate.
void VRWorldUI_DrawQuad(HWDrawInfo* di, FRenderState& state, const DVector3& center, const DVector3& right, const DVector3& up, float width, float height, FGameTexture* texture, PalEntry color, bool textured, bool rotate180 = false);
void VRWorldUI_DrawDisc(HWDrawInfo* di, FRenderState& state, const DVector3& center, const DVector3& right, const DVector3& up, float radius, PalEntry color);

void VRWheel_OpenWeapon();
void VRWheel_CloseWeapon();
void VRWheel_OpenOffhandWeapon();
void VRWheel_CloseOffhandWeapon();
void VRWheel_OpenInventory();
void VRWheel_CloseInventory();
void VRWheel_Reset();
bool VRWheel_IsActive();
bool VRWheel_ShouldSuppressGameplayInput();
bool VRWheel_ShouldSuppressWeaponHand(int hand);
void VRWheel_Draw(HWDrawInfo* di, FRenderState& state);
bool VRWheel_GetTransform(VSMatrix& out);
