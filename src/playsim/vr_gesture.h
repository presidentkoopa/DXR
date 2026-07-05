// ============================================================================
// vr_gesture.h -- the DoomXR native VR gesture engine.
//
// ONE engine, not 90 hand-coded gestures. This detects hand motion each tic and
// matches it against a DECLARATIVE table (vr_gestures.json). Every gesture is a
// data row: anchor + hand + motion-verb + gate-button + action. When a row's
// recipe is satisfied, the engine fires gesture_fired("<id>") to ZScript, which
// owns the EFFECT. C++ owns DETECTION + DISPATCH; ZScript owns consequence; JSON
// is the glue. Adding/retuning a gesture = editing JSON, no recompile. A new
// *kind* of motion (a new verb) is the only thing that touches this C++ again.
//
// Reads only EXISTING engine signals (hand pos AttackPos/OffhandPos, GetHandVelocity,
// grip via the arbiter, body anchors via the hardpoint system, button bits). The
// one genuinely-new thing here is the per-hand RING BUFFER (motion history), which
// shape/verb recognition needs and which the engine did not expose before.
//
// Integration points (kept minimal, coordinated with the IK/p_user lane):
//   * one call to FVRGestureEngine::Get().Update(player) in P_PlayerThink.
//   * a ZScript virtual PlayerPawn.VR_GestureFired(Name id) for the effect table.
//   * thunks (vmthunks_actors.cpp) for VR_HandIntent / VR_AnchorNear (content reads).
// ============================================================================
#pragma once

#include "vectors.h"
#include "tarray.h"
#include "name.h"
#include "zstring.h"

struct player_t;

// ---- how much motion history we keep, per hand ----------------------------
// ~1 second at 35 tics/sec. Enough for flick arcs, circles, lasso loops.
static const int VR_GESTURE_HISTORY = 40;

// ---- the motion VERBS the classifier emits --------------------------------
// A gesture's JSON "motion" field names one of these. Adding a verb is the ONE
// change that needs a recompile; everything else is data.
enum EGestureVerb
{
	GV_NONE = 0,
	GV_FLICK,        // sharp out-and-back velocity spike
	GV_THRUST,       // sustained directional push
	GV_SHOVE,        // thrust while overlapping a target (melee push)
	GV_ARC,          // curved sweep (whip/blade)
	GV_CIRCLE_CW,    // closed clockwise loop
	GV_CIRCLE_CCW,   // closed counter-clockwise loop
	GV_SLASH,        // fast straight swipe
	GV_GUARD,        // both hands drawn inward (block / X-brace)
	GV_CATCH,        // open hand intercepting an incoming actor
	GV_PLACE,        // downward reach-and-release
	GV_REVERSAL,     // velocity flips direction sharply (recall/yank)
	GV_NUMVERBS
};

// ---- body anchors a gesture can key off ------------------------------------
// World positions come from the hardpoint system (GetHardpointWorldPos) so there
// is ONE source of anchor math; these are just the ids the JSON references.
enum EGestureAnchor
{
	GA_NONE = 0,
	GA_CHEST,
	GA_HIP_L,
	GA_HIP_R,
	GA_SHOULDER_L,
	GA_SHOULDER_R,
	GA_TEMPLE,
	GA_WRIST_MAIN,
	GA_WRIST_OFF,
	GA_BELT,
	GA_BACK,
	GA_NUMANCHORS
};

// ---- per-hand motion history ----------------------------------------------
// A tiny ring buffer of world positions + velocities, pushed once per tic in
// Update(). All the verb/shape math reads from here so detection is decoupled
// from the per-tic pose read.
struct FVRHandHistory
{
	DVector3 pos[VR_GESTURE_HISTORY];
	DVector3 vel[VR_GESTURE_HISTORY];
	int      head = 0;      // index of the most-recent sample
	int      count = 0;     // how many valid samples (ramps up to HISTORY)

	void Clear() { head = 0; count = 0; }
	void Push(const DVector3& p, const DVector3& v);

	// newest-first indexed access (0 = this tic, 1 = last tic, ...). Safe past count.
	const DVector3& Pos(int backTics) const;
	const DVector3& Vel(int backTics) const;

	// derived queries the classifier uses ----------------------------------
	double PeakSpeed(int windowTics) const;              // max |vel| over a window
	DVector3 NetDisplacement(int windowTics) const;      // pos[now] - pos[back]
	double AngularSweep(int windowTics) const;           // total turn of the vel vector (deg) -> circles
	bool   VelReversed(int windowTics, double minSpeed) const; // sharp direction flip -> reversal
};

// ---- one gesture definition (a row of vr_gestures.json) --------------------
struct FVRGestureDef
{
	FName    id;                 // "pouch_reload"
	FName    action;             // ZScript action to run (defaults to id)
	int      anchor = GA_NONE;   // EGestureAnchor
	int      hand = -1;          // 0 main, 1 off, -1 either
	int      verb = GV_NONE;     // EGestureVerb the motion must match
	int      gateButton = 0;     // button-bit that must be pressed (0 = pose-only, net-unsafe)
	double   radius = 24.0;      // how close to the anchor counts (map units)
	int      dwellTics = 0;      // pose must hold this long before the verb fires
	bool     enabled = true;     // shop can flip this per player (owned:true)

	// live per-hand latch state (not from JSON) ----------------------------
	int      dwellCounter[2] = { 0, 0 };
	bool     wasReady[2] = { false, false };  // fire-edge latch: full condition held last tic
};

// ---- the engine ------------------------------------------------------------
class FVRGestureEngine
{
public:
	static FVRGestureEngine& Get();

	// Load / reload the gesture table from vr_gestures.json (+ any mod overrides).
	void LoadDefs();

	// Called once per tic from P_PlayerThink (the ONE p_user.cpp touch).
	// Pushes the ring buffers, classifies verbs, evaluates every def, fires hits.
	void Update(player_t* player);

	// Content-facing reads (exposed to ZScript via thunks):
	int  HandIntent(player_t* player, int hand) const;          // current EGestureVerb
	bool AnchorNear(player_t* player, int anchor, int hand) const;

private:
	int      ClassifyVerb(const FVRHandHistory& h) const;       // buffer -> EGestureVerb
	DVector3 AnchorPos(player_t* player, int anchor, int hand) const; // -> hardpoint world pos
	bool     GateDown(player_t* player, int gateButton) const;  // button-bit read
	void     Fire(player_t* player, const FVRGestureDef& def, int hand); // -> gesture_fired

	TArray<FVRGestureDef> Defs;
	FVRHandHistory        History[2];      // [0]=main, [1]=off
	int                   Verb[2] = { GV_NONE, GV_NONE }; // this-tic classified verb per hand
	bool                  Loaded = false;
};
