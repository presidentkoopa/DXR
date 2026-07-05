// ============================================================================
// vr_gesture.cpp -- implementation of the DoomXR native VR gesture engine.
// See vr_gesture.h for the architecture. C++ detects; ZScript (VR_GestureFired)
// does the effect; vr_gestures.json is the table.
//
// STATUS: first cut. NOT compile-verified (no headless compiler in this tree).
// Reads only existing engine state; the one external dispatch (VR_GestureFired)
// uses the exact IFVIRTUALPTRNAME/VMCall idiom already used in p_user.cpp.
// Body-anchor positions are DERIVED here (feet + viewheight + yaw offset) as a
// standalone stand-in; TODO(unify): delegate to the hardpoint world-anchor math
// so there is ONE source of anchor truth.
// ============================================================================

#include "vr_gesture.h"
#include "d_player.h"
#include "actor.h"
#include "vm.h"
#include "printf.h"

#include <math.h>
#include <stdio.h>
#include "rapidjson/document.h"
#include "rapidjson/filereadstream.h"

// ============================================================================
//  FVRHandHistory -- the per-hand ring buffer + the derived motion queries.
// ============================================================================
void FVRHandHistory::Push(const DVector3& p, const DVector3& v)
{
	head = (head + 1) % VR_GESTURE_HISTORY;
	pos[head] = p;
	vel[head] = v;
	if (count < VR_GESTURE_HISTORY) count++;
}

const DVector3& FVRHandHistory::Pos(int back) const
{
	if (back < 0) back = 0;
	if (count > 0 && back >= count) back = count - 1;
	int i = (head - back + VR_GESTURE_HISTORY * 2) % VR_GESTURE_HISTORY;
	return pos[i];
}

const DVector3& FVRHandHistory::Vel(int back) const
{
	if (back < 0) back = 0;
	if (count > 0 && back >= count) back = count - 1;
	int i = (head - back + VR_GESTURE_HISTORY * 2) % VR_GESTURE_HISTORY;
	return vel[i];
}

double FVRHandHistory::PeakSpeed(int window) const
{
	int n = (window < count) ? window : count;
	double m = 0.0;
	for (int i = 0; i < n; i++)
	{
		const DVector3& v = Vel(i);
		double s = sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z);
		if (s > m) m = s;
	}
	return m;
}

DVector3 FVRHandHistory::NetDisplacement(int window) const
{
	int n = (window < count) ? window : count;
	if (n < 1) return DVector3(0, 0, 0);
	return Pos(0) - Pos(n - 1);
}

// Signed accumulated turn of the (XY-projected) velocity vector across the window.
// + = counter-clockwise, - = clockwise. |sweep| >~360 => a closed loop.
double FVRHandHistory::AngularSweep(int window) const
{
	int n = (window < count) ? window : count;
	if (n < 3) return 0.0;
	const double R2D = 57.29577951;
	double total = 0.0;
	for (int i = 0; i < n - 1; i++)
	{
		const DVector3& a = Vel(i + 1);   // older
		const DVector3& b = Vel(i);       // newer
		double la = sqrt(a.X * a.X + a.Y * a.Y);
		double lb = sqrt(b.X * b.X + b.Y * b.Y);
		if (la < 0.01 || lb < 0.01) continue;
		double ang = (atan2(b.Y, b.X) - atan2(a.Y, a.X)) * R2D;
		while (ang > 180.0)  ang -= 360.0;
		while (ang < -180.0) ang += 360.0;
		total += ang;
	}
	return total;
}

bool FVRHandHistory::VelReversed(int window, double minSpeed) const
{
	int n = (window < count) ? window : count;
	if (n < 3) return false;
	const DVector3& now = Vel(0);
	const DVector3& then = Vel(n - 1);
	double sn = sqrt(now.X * now.X + now.Y * now.Y + now.Z * now.Z);
	double st = sqrt(then.X * then.X + then.Y * then.Y + then.Z * then.Z);
	if (sn < minSpeed || st < minSpeed) return false;
	double dot = now.X * then.X + now.Y * then.Y + now.Z * then.Z;
	return dot < 0.0;
}

// ============================================================================
//  FVRGestureEngine
// ============================================================================
FVRGestureEngine& FVRGestureEngine::Get()
{
	static FVRGestureEngine inst;
	return inst;
}

// ---- small string->enum helpers for the JSON parser -----------------------
static int VerbFromName(const char* s)
{
	if (!s) return GV_NONE;
	if (!strcmp(s, "flick"))      return GV_FLICK;
	if (!strcmp(s, "thrust"))     return GV_THRUST;
	if (!strcmp(s, "shove"))      return GV_SHOVE;
	if (!strcmp(s, "arc"))        return GV_ARC;
	if (!strcmp(s, "circle_cw"))  return GV_CIRCLE_CW;
	if (!strcmp(s, "circle_ccw")) return GV_CIRCLE_CCW;
	if (!strcmp(s, "slash"))      return GV_SLASH;
	if (!strcmp(s, "guard"))      return GV_GUARD;
	if (!strcmp(s, "catch"))      return GV_CATCH;
	if (!strcmp(s, "place"))      return GV_PLACE;
	if (!strcmp(s, "reversal"))   return GV_REVERSAL;
	return GV_NONE;
}

static int AnchorFromName(const char* s)
{
	if (!s) return GA_NONE;
	if (!strcmp(s, "chest"))      return GA_CHEST;
	if (!strcmp(s, "hip_l"))      return GA_HIP_L;
	if (!strcmp(s, "hip_r"))      return GA_HIP_R;
	if (!strcmp(s, "shoulder_l")) return GA_SHOULDER_L;
	if (!strcmp(s, "shoulder_r")) return GA_SHOULDER_R;
	if (!strcmp(s, "temple"))     return GA_TEMPLE;
	if (!strcmp(s, "wrist_main")) return GA_WRIST_MAIN;
	if (!strcmp(s, "wrist_off"))  return GA_WRIST_OFF;
	if (!strcmp(s, "belt"))       return GA_BELT;
	if (!strcmp(s, "back"))       return GA_BACK;
	return GA_NONE;
}

static int HandFromName(const char* s)
{
	if (!s) return -1;
	if (!strcmp(s, "main")) return 0;
	if (!strcmp(s, "off"))  return 1;
	return -1;   // "either"
}

void FVRGestureEngine::LoadDefs()
{
	Loaded = true;
	Defs.Clear();

	// vr_gestures.json { "gestures": [ { id, anchor, hand, motion, gate, radius,
	// dwell, action, owned }, ... ] }. Read from the run dir like vr_hardpoints.json.
	FILE* fp = fopen("vr_gestures.json", "rb");
	if (fp)
	{
		char buffer[65536];
		rapidjson::FileReadStream is(fp, buffer, sizeof(buffer));
		rapidjson::Document d;
		d.ParseStream(is);
		fclose(fp);

		if (!d.HasParseError() && d.HasMember("gestures") && d["gestures"].IsArray())
		{
			for (auto& o : d["gestures"].GetArray())
			{
				if (!o.IsObject()) continue;
				FVRGestureDef g;
				if (o.HasMember("id") && o["id"].IsString())        g.id = FName(o["id"].GetString());
				else continue;   // an id is mandatory
				g.action = (o.HasMember("action") && o["action"].IsString()) ? FName(o["action"].GetString()) : g.id;
				if (o.HasMember("anchor") && o["anchor"].IsString()) g.anchor = AnchorFromName(o["anchor"].GetString());
				if (o.HasMember("hand")   && o["hand"].IsString())   g.hand   = HandFromName(o["hand"].GetString());
				if (o.HasMember("motion") && o["motion"].IsString()) g.verb   = VerbFromName(o["motion"].GetString());
				if (o.HasMember("gate")   && o["gate"].IsInt())      g.gateButton = o["gate"].GetInt();   // button-bit as int
				if (o.HasMember("radius") && o["radius"].IsNumber())  g.radius   = o["radius"].GetDouble();
				if (o.HasMember("dwell")  && o["dwell"].IsInt())      g.dwellTics = o["dwell"].GetInt();
				if (o.HasMember("owned")  && o["owned"].IsBool())     g.enabled  = o["owned"].GetBool();
				Defs.Push(g);
			}
			Printf("VR gestures: loaded %u from vr_gestures.json\n", Defs.Size());
			return;
		}
		Printf("VR gestures: vr_gestures.json present but unparseable -- using built-in defaults\n");
	}

	// No file (or bad file) -> a tiny built-in default so the engine does something.
	{
		FVRGestureDef g;
		g.id = FName("pouch_reload"); g.action = g.id;
		g.anchor = GA_CHEST; g.hand = 1; g.verb = GV_FLICK;
		g.gateButton = 0; g.radius = 22.0; g.dwellTics = 4;
		Defs.Push(g);
	}
}

// current-tic classified verb -> exposed to ZScript (VR_HandIntent).
int FVRGestureEngine::HandIntent(player_t* player, int hand) const
{
	if (hand < 0 || hand > 1) return GV_NONE;
	return Verb[hand];
}

bool FVRGestureEngine::AnchorNear(player_t* player, int anchor, int hand) const
{
	if (!player || !player->mo || hand < 0 || hand > 1) return false;
	const double DEFAULT_R = 24.0;   // def-eval uses def.radius directly; this is the generic query
	DVector3 handPos = (hand == 0) ? player->mo->AttackPos : player->mo->OffhandPos;
	DVector3 a = AnchorPos(player, anchor, hand);
	DVector3 d = handPos - a;
	return sqrt(d.X * d.X + d.Y * d.Y + d.Z * d.Z) <= DEFAULT_R;
}

// TODO(unify): delegate to the hardpoint system's world-anchor math so anchors
// have ONE source of truth. Derived stand-in: feet + viewheight-scaled up + a
// yaw-rotated local (forward,right) offset.
DVector3 FVRGestureEngine::AnchorPos(player_t* player, int anchor, int hand) const
{
	AActor* mo = player->mo;
	if (anchor == GA_WRIST_MAIN) return mo->AttackPos;   // the wrist anchors ARE the hands
	if (anchor == GA_WRIST_OFF)  return mo->OffhandPos;

	DVector3 feet = mo->Pos();
	double vh = player->viewheight;
	double yaw = mo->Angles.Yaw.Radians();
	double c = cos(yaw), s = sin(yaw);

	double fwd = 0, right = 0, up = 0;
	switch (anchor)
	{
		case GA_CHEST:      up = vh * 0.55; break;
		case GA_BELT:       up = vh * 0.30; break;
		case GA_HIP_L:      up = vh * 0.35; right = -10; break;
		case GA_HIP_R:      up = vh * 0.35; right = 10;  break;
		case GA_SHOULDER_L: up = vh * 0.85; right = -9;  break;
		case GA_SHOULDER_R: up = vh * 0.85; right = 9;   break;
		case GA_TEMPLE:     up = vh * 1.00; break;
		case GA_BACK:       up = vh * 0.70; fwd = -8;    break;
		default: break;
	}
	// world forward = (c, s); world right = (s, -c)
	DVector3 out = feet;
	out.X += c * fwd + s * right;
	out.Y += s * fwd - c * right;
	out.Z += up;
	return out;
}

bool FVRGestureEngine::GateDown(player_t* player, int gateButton) const
{
	if (gateButton == 0) return true;   // pose-only (net-unsafe; flagged in docs)
	return (player->cmd.ucmd.buttons & gateButton) != 0;
}

int FVRGestureEngine::ClassifyVerb(const FVRHandHistory& h) const
{
	if (h.count < 4) return GV_NONE;

	// thresholds are hardcoded for the first cut; move to CVARs/JSON when tuning.
	const double FLICK_SPEED = 6.0;    // units/tic peak
	const double THRUST_DISP = 12.0;   // net displacement (units) for a thrust/slash

	double peakShort = h.PeakSpeed(6);
	double peakLong  = h.PeakSpeed(VR_GESTURE_HISTORY);
	DVector3 disp = h.NetDisplacement(6);
	double dispLen = sqrt(disp.X * disp.X + disp.Y * disp.Y + disp.Z * disp.Z);
	double sweep = h.AngularSweep(VR_GESTURE_HISTORY);

	// CIRCLE: a big accumulated turn
	if (fabs(sweep) > 300.0 && peakLong > FLICK_SPEED * 0.5)
		return (sweep > 0) ? GV_CIRCLE_CCW : GV_CIRCLE_CW;
	// FLICK / REVERSAL: fast out-and-back
	if (peakShort > FLICK_SPEED && h.VelReversed(8, FLICK_SPEED * 0.5))
		return (dispLen < THRUST_DISP) ? GV_FLICK : GV_REVERSAL;
	// SLASH: fast straight swipe, big displacement, little turn
	if (peakShort > FLICK_SPEED && dispLen >= THRUST_DISP && fabs(sweep) < 120.0)
		return GV_SLASH;
	// THRUST: sustained push one direction
	if (dispLen >= THRUST_DISP && peakShort > FLICK_SPEED * 0.4)
		return GV_THRUST;

	// TODO: GV_SHOVE / GV_GUARD / GV_CATCH / GV_PLACE need cross-hand or actor
	// context (both hands inward, hand overlapping a monster, downward reach+release).
	// Handled in a later context pass, not from a single hand's buffer.
	return GV_NONE;
}

void FVRGestureEngine::Fire(player_t* player, const FVRGestureDef& def, int hand)
{
	if (!player || !player->mo) return;
	FName act = (def.action != NAME_None) ? def.action : def.id;

	IFVIRTUALPTRNAME(player->mo, NAME_PlayerPawn, VR_GestureFired)
	{
		VMValue param[] = { player->mo, act.GetIndex(), hand };
		VMCall(func, param, 3, nullptr, 0);
	}
}

void FVRGestureEngine::Update(player_t* player)
{
	if (!Loaded) LoadDefs();
	if (!player || !player->mo) return;

	// 1) push the ring buffers (velocity derived from the pos delta) + classify.
	for (int hand = 0; hand < 2; hand++)
	{
		DVector3 p = (hand == 0) ? player->mo->AttackPos : player->mo->OffhandPos;
		DVector3 prev = (History[hand].count > 0) ? History[hand].Pos(0) : p;
		DVector3 v = p - prev;                       // units per tic
		History[hand].Push(p, v);
		Verb[hand] = ClassifyVerb(History[hand]);
	}

	// 2) evaluate every def against each applicable hand; fire on the rising edge
	//    of (anchor near && verb match && gate && dwell satisfied).
	for (unsigned di = 0; di < Defs.Size(); di++)
	{
		FVRGestureDef& def = Defs[di];
		if (!def.enabled) continue;

		for (int hand = 0; hand < 2; hand++)
		{
			if (def.hand != -1 && def.hand != hand) { def.wasReady[hand] = false; def.dwellCounter[hand] = 0; continue; }

			// anchor proximity against THIS def's radius
			bool nearOk = true;
			if (def.anchor != GA_NONE)
			{
				DVector3 handPos = (hand == 0) ? player->mo->AttackPos : player->mo->OffhandPos;
				DVector3 a = AnchorPos(player, def.anchor, hand);
				DVector3 d = handPos - a;
				nearOk = sqrt(d.X * d.X + d.Y * d.Y + d.Z * d.Z) <= def.radius;
			}
			bool verbOk = (def.verb == GV_NONE) || (Verb[hand] == def.verb);
			bool gateOk = GateDown(player, def.gateButton);

			bool cond = nearOk && verbOk && gateOk;
			if (cond)
			{
				if (def.dwellCounter[hand] < def.dwellTics) def.dwellCounter[hand]++;
			}
			else
			{
				def.dwellCounter[hand] = 0;
			}
			bool ready = cond && (def.dwellCounter[hand] >= def.dwellTics);

			if (ready && !def.wasReady[hand])
				Fire(player, def, hand);         // rising edge -> fire once per hold
			def.wasReady[hand] = ready;
		}
	}
}
