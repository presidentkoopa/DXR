// ===== NEW FILE: src/playsim/vr_hardpoint.h =====
// Single source of truth for the native VR hardpoint-mount system's shared
// enums + config struct. Pure declarations. Included by:
//   - src/playsim/vr_config.h        (static default table FVRConfig::Hardpoints)
//   - src/playsim/p_user.cpp         (VR_UpdateHardpoints / VR_InitHardpoints)
//   - src/scripting/vmthunks_actors.cpp (AssignHardpoint / ClearHardpoint / IsHardpointNear ...)
// so all three agree on ONE definition.
//
// Grounding:
//   FName + NAME_None -> src/common/utility/name.h. name.h:40-50 defines
//     `enum ENamedName { ... }` whose FIRST enumerator is NAME_None (value 0),
//     and name.h:54 defines class FName. vr_config.h:5 already includes "name.h"
//     with a bare path, confirming this include resolves in the build.
//   NOTE: FName()'s defaulted ctor (name.h:57) does NOT zero-init its protected
//     `int Index` member (name.h:98) -- so the explicit `= NAME_None` member
//     initializers below are REQUIRED, not redundant. FName(ENamedName) (name.h:64)
//     makes `= NAME_None` well-formed.
//   The runtime per-player state (VRHardpointRuntime + player_t.vr_hardpoints[]) lives in
//   d_player.h (that edit is a SEPARATE file target); it references VR_MAX_HARDPOINTS from here.

#pragma once

#include "name.h"   // FName, NAME_None  (matches vr_config.h include set at line 5)

// Where a slot's world position is computed from each tic.
enum EHardpointAnchor
{
	HP_ANCHOR_BODY   = 0,  // body-relative: chest/head playsim pos (mo->AttackPos) + yaw-rotated offset
	HP_ANCHOR_WRIST  = 1,  // hand-relative: OTHER hand's GetWeaponTransform * local offset
};

// What a grip rising-edge at this slot does.
enum EHardpointAction
{
	HP_ACT_HOLSTER   = 0,  // stow/draw the hand's weapon (default)
	HP_ACT_ABILITY   = 1,  // fire a ZScript ability hook instead of a weapon swap
};

// Fixed cap on configurable slots. Extensible via config up to this cap.
// Matches the fixed-array style of vr_climbing_lines[2][10] (d_player.h) for
// serialization parity. Raised to 16 to hold the default layout (4 body weapon
// holsters + 3 wrist ability mounts) with generous headroom for modder slots.
#define VR_MAX_HARDPOINTS 16

// Data-driven slot definition. Loaded from config (vr_hardpoints.json / keywords.db.json
// "hardpoints" array) into the static default table FVRConfig::Hardpoints, and mirrored
// per-player into player_t.vr_hardpoints[] at pawn spawn by VR_InitHardpoints.
//
// Fixed-size fields only in the per-player runtime mirror (VRHardpointRuntime, defined in
// d_player.h) -- FName here is config-side only (resolved at load), so the runtime array
// stays trivially serializable.
struct FHardpointSlot
{
	int      anchor      = HP_ANCHOR_BODY;   // EHardpointAnchor
	int      action      = HP_ACT_HOLSTER;   // EHardpointAction
	int      hand        = -1;               // -1 = either hand may reach; 0/1 = restrict to that hand
	float    ox          = 0.0f;             // local offset X (map units) from anchor
	float    oy          = 0.0f;             // local offset Y (map units) from anchor
	float    oz          = 0.0f;             // local offset Z (map units) from anchor
	float    radius      = 0.0f;             // per-slot reach; <=0 => use cvar vr_hardpoint_radius
	int      cells       = 1;                // visual grid footprint ("squares"), UI-only -- does not
	                                          // change the one-weapon-per-slot holster mechanic, just
	                                          // how many squares VRHardpointGrid_Draw renders for it
	FName    weaponClass = NAME_None;        // ability/preferred weapon class (config only)
	FName    abilityName = NAME_None;        // ZScript event name fired for HP_ACT_ABILITY
	bool     enabled     = true;
};

// player_t is defined in d_player.h; forward-declared here to avoid pulling that (and its
// transitive includes) into this lightweight shared header.
struct player_t;

// Resolves hardpoint slot `slotIndex`'s CURRENT world position (body-yaw-relative or
// wrist-relative, exactly matching the math VR_UpdateHardpoints applies for real grip/proximity
// checks in p_user.cpp) into `out` (x,y,z, map units). Returns false if player/mo/slotIndex is
// invalid. Defined once in vmthunks_actors.cpp (shared by the GetHardpointWorldPos ZScript thunk
// and the native VRHardpointGrid_Draw renderer) so the mechanic and its visual marker can never
// drift apart.
bool VR_ResolveHardpointWorldPos(player_t* player, int slotIndex, int forHand, double out[3]);
