//-----------------------------------------------------------------------------
//
// Copyright 1993-1996 id Software
// Copyright 1994-1996 Raven Software
// Copyright 1998-1998 Chi Hoang, Lee Killough, Jim Flynn, Rand Phares, Ty Halderman
// Copyright 1999-2016 Randy Heit
// Copyright 2002-2016 Christoph Oelckers
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see http://www.gnu.org/licenses/
//
//-----------------------------------------------------------------------------
//


#ifndef __D_PLAYER_H__
#define __D_PLAYER_H__

// Finally, for odd reasons, the player input
// is buffered within the player data struct,
// as commands per game tick.
#include "d_protocol.h"
#include "doomstat.h"

#include "a_weapons.h"

#include "d_netinf.h"

// The player data structure depends on a number
// of other structs: items (internal inventory),
// animation states (closely tied to the sprites
// used to represent them, unfortunately).
#include "p_pspr.h"

// In addition, the player is just a special
// case of the generic moving object/actor.
#include "actor.h"
#include "vr_hardpoint.h"   // EHardpointAnchor / EHardpointAction / FHardpointSlot / VR_MAX_HARDPOINTS
#include "TRS.h"            // TRS (per-bone procedural pose element) for vr_ik_pose

//Added by MC:
#include "b_bot.h"

class player_t;

// Standard pre-defined skin colors
struct FPlayerColorSet
{
	struct ExtraRange
	{
		uint8_t RangeStart, RangeEnd;	// colors to remap
		uint8_t FirstColor, LastColor;	// colors to map to
	};

	FName Name;			// Name of this color

	int Lump;			// Lump to read the translation from, otherwise use next 2 fields
	uint8_t FirstColor, LastColor;		// Describes the range of colors to use for the translation

	uint8_t RepresentativeColor;		// A palette entry representative of this translation,
									// for map arrows and status bar backgrounds and such
	uint8_t NumExtraRanges;
	ExtraRange Extra[6];
};

typedef TArray<std::tuple<PClass*, FName, PalEntry>> PainFlashList;
typedef TArray<std::tuple<PClass*, int, FPlayerColorSet>> ColorSetList;

extern PainFlashList PainFlashes;
extern ColorSetList ColorSets;

FString GetPrintableDisplayName(PClassActor *cls);

void PlayIdle(AActor *player);


//
// PlayerPawn flags
//
enum
{
	PPF_NOTHRUSTWHENINVUL = 1,	// Attacks do not thrust the player if they are invulnerable.
};

//
// Player states.
//
typedef enum
{
	PST_LIVE,	// Playing or camping.
	PST_DEAD,	// Dead on the ground, view follows killer.
	PST_REBORN,	// Ready to restart/respawn???
	PST_ENTER,	// [BC] Entered the game
	PST_GONE	// Player has left the game
} playerstate_t;


//
// Player internal flags, for cheats and debug.
//
typedef enum
{
	CF_NOCLIP			= 1 << 0,		// No clipping, walk through barriers.
	CF_GODMODE			= 1 << 1,		// No damage, no health loss.
	CF_NOVELOCITY		= 1 << 2,		// Not really a cheat, just a debug aid.
	CF_NOTARGET			= 1 << 3,		// [RH] Monsters don't target
	CF_FLY				= 1 << 4,		// [RH] Flying player
	CF_CHASECAM			= 1 << 5,		// [RH] Put camera behind player
	CF_FROZEN			= 1 << 6,		// [RH] Don't let the player move
	CF_REVERTPLEASE		= 1 << 7,		// [RH] Stick camera in player's head if (s)he moves
	CF_STEPLEFT			= 1 << 9,		// [RH] Play left footstep sound next time
	CF_FRIGHTENING		= 1 << 10,		// [RH] Scare monsters away
	CF_INSTANTWEAPSWITCH= 1 << 11,		// [RH] Switch weapons instantly
	CF_TOTALLYFROZEN	= 1 << 12,		// [RH] All players can do is press +use
	CF_PREDICTING		= 1 << 13,		// [RH] Player movement is being predicted
	CF_INTERPVIEW		= 1 << 14,		// [RH] view was changed outside of input, so interpolate one frame
	CF_INTERPVIEWANGLES	= 1 << 15,		// [MR] flag for interpolating view angles without interpolating the entire frame
	CF_NOFOVINTERP		= 1 << 16,		// [B] Disable FOV interpolation when instantly zooming
	CF_SCALEDNOLERP		= 1 << 17,		// [MR] flag for applying angles changes in the ticrate without interpolating the frame
	CF_NOVIEWPOSINTERP	= 1 << 18,		// Disable view position interpolation.
	CF_EXTREMELYDEAD	= 1 << 22,		// [RH] Reliably let the status bar know about extreme deaths.
	CF_BUDDHA2			= 1 << 24,		// [MC] Absolute buddha. No voodoo can kill it either.
	CF_GODMODE2			= 1 << 25,		// [MC] Absolute godmode. No voodoo can kill it either.
	CF_BUDDHA			= 1 << 27,		// [SP] Buddha mode - take damage, but don't die
	CF_NOCLIP2			= 1 << 30,		// [RH] More Quake-like noclip
} cheat_t;

enum
{
	WF_WEAPONREADY		= 1 << 0,		// [RH] Weapon is in the ready state and can fire its primary attack
	WF_WEAPONBOBBING	= 1 << 1,		// [HW] Bob weapon while the player is moving
	WF_WEAPONREADYALT	= 1 << 2,		// Weapon can fire its secondary attack
	WF_WEAPONSWITCHOK	= 1 << 3,		// It is okay to switch away from this weapon
	WF_DISABLESWITCH	= 1 << 4,		// Disable weapon switching completely
	WF_WEAPONRELOADOK	= 1 << 5,		// [XA] Okay to reload this weapon.
	WF_WEAPONZOOMOK		= 1 << 6,		// [XA] Okay to use weapon zoom function.
	WF_REFIRESWITCHOK	= 1 << 7,		// Mirror WF_WEAPONSWITCHOK for A_ReFire
	WF_USER1OK			= 1 << 8,		// [MC] Allow pushing of custom state buttons 1-4
	WF_USER2OK			= 1 << 9,
	WF_USER3OK			= 1 << 10,
	WF_USER4OK			= 1 << 11,

	WF_OFFHANDREADY          = 1 << 12,
	WF_OFFHANDBOBBING        = 1 << 13,
	WF_OFFHANDREADYALT       = 1 << 14,
	WF_OFFHANDSWITCHOK       = 1 << 15,
	WF_OFFHANDDISABLESWITCH  = 1 << 16,
	WF_OFFHANDRELOADOK       = 1 << 17,
	WF_OFFHANDZOOMOK         = 1 << 18,
	WF_OFFHANDREFIRESWITCHOK = 1 << 19,
	WF_OFFHANDUSER1OK        = 1 << 20,
	WF_OFFHANDUSER2OK        = 1 << 21,
	WF_OFFHANDUSER3OK        = 1 << 22,
	WF_OFFHANDUSER4OK        = 1 << 23,

	WF_TWOHANDSTABILIZED     = 1 << 24
};

// The VM cannot deal with this as an invalid pointer because it performs a read barrier on every object pointer read.
// This doesn't have to point to a valid weapon, though, because WP_NOCHANGE is never dereferenced, but it must point to a valid object
// and the class descriptor just works fine for that.
extern DObject *WP_NOCHANGE;


// [GRB] Custom player classes
enum
{
	PCF_NOMENU			= 1,	// Hide in new game menu
};

class FPlayerClass
{
public:
	FPlayerClass ();
	FPlayerClass (const FPlayerClass &other) = default;
	~FPlayerClass ();

	bool CheckSkin (int skin);

	PClassActor *Type;
	uint32_t Flags;
	TArray<int> Skins;
};

extern TArray<FPlayerClass> PlayerClasses;

// User info (per-player copies of each CVAR_USERINFO cvar)
struct userinfo_t : TMap<FName,FBaseCVar *>
{
	~userinfo_t();

	double GetAimDist() const
	{
		if (dmflags2 & DF2_NOAUTOAIM)
		{
			return 0;
		}

		float aim = *static_cast<FFloatCVar *>(*CheckKey(NAME_Autoaim));
		if (aim > 35 || aim < 0)
		{
			return 35.;
		}
		else
		{
			return aim;
		}
	}
	// Same but unfiltered.
	double GetAutoaim() const
	{
		return *static_cast<FFloatCVar *>(*CheckKey(NAME_Autoaim));
	}
	const char *GetName(unsigned int charLimit = 0u) const
	{
		const char* name = *static_cast<FStringCVar*>(*CheckKey(NAME_Name));
		if (charLimit)
		{
			FString temp = name;
			if (temp.CharacterCount() > charLimit)
			{
				int next = 0;
				for (unsigned int i = 0u; i < charLimit; ++i)
					temp.GetNextCharacter(next);

				temp.Truncate(next);
				temp += "...";
				name = temp.GetChars();
			}
		}

		return name;
	}
	int GetTeam() const
	{
		return *static_cast<FIntCVar *>(*CheckKey(NAME_Team));
	}
	int GetColorSet() const
	{
		return *static_cast<FIntCVar *>(*CheckKey(NAME_ColorSet));
	}
	uint32_t GetColor() const
	{
		return *static_cast<FColorCVar *>(*CheckKey(NAME_Color));
	}
	bool GetNeverSwitch() const
	{
		return *static_cast<FBoolCVar *>(*CheckKey(NAME_NeverSwitchOnPickup));
	}
	double GetMoveBob() const
	{
		return *static_cast<FFloatCVar *>(*CheckKey(NAME_MoveBob));
	}
	bool GetFViewBob() const
	{
		return *static_cast<FBoolCVar *>(*CheckKey(NAME_FViewBob));
	}
	double GetStillBob() const
	{
		return *static_cast<FFloatCVar *>(*CheckKey(NAME_StillBob));
	}
	float GetWBobSpeed() const
	{
		return *static_cast<FFloatCVar *>(*CheckKey(NAME_WBobSpeed));
	}
	double GetWBobFire() const
	{
		return *static_cast<FFloatCVar *>(*CheckKey(NAME_WBobFire));
	}
	int GetPlayerClassNum() const
	{
		return *static_cast<FIntCVar *>(*CheckKey(NAME_PlayerClass));
	}
	bool GetClassicFlight() const
	{
		return *static_cast<FBoolCVar *>(*CheckKey(NAME_ClassicFlight));
	}
	PClassActor *GetPlayerClassType() const
	{
		return PlayerClasses[GetPlayerClassNum()].Type;
	}
	int GetSkin() const
	{
		return *static_cast<FIntCVar *>(*CheckKey(NAME_Skin));
	}
	int GetGender() const
	{
		auto cvar = CheckKey(NAME_Gender);
		return cvar ? *static_cast<FIntCVar *>(*cvar) : 0;
	}
	bool GetNoAutostartMap() const
	{
		return *static_cast<FBoolCVar *>(*CheckKey(NAME_Wi_NoAutostartMap));
	}

	void Reset(int pnum);
	int TeamChanged(int team);
	int SkinChanged(const char *skinname, int playerclass);
	int SkinNumChanged(int skinnum);
	int GenderChanged(const char *gendername);
	int PlayerClassChanged(const char *classname);
		uint32_t ColorChanged(const char *colorname);
	uint32_t ColorChanged(uint32_t colorval);
	int ColorSetChanged(int setnum);
};

void ReadUserInfo(FSerializer &arc, userinfo_t &info, FString &skin);
void WriteUserInfo(FSerializer &arc, userinfo_t &info);

//
// Extended player object info: player_t
//
class player_t
{
public:
	player_t() { angleOffsetTargets.Zero(); }
	~player_t();
	player_t &operator= (const player_t &p) = delete;
	void CopyFrom(player_t &src, bool copyPSP);

	void Serialize(FSerializer &arc);
	size_t PropagateMark();

	void SetLogNumber (int num);
	void SetLogText (const char *text);
	void SendPitchLimits() const;
	void SetSubtitle(int num, FSoundID soundid);

	AActor *mo = nullptr;
	uint8_t		playerstate = 0;
	ticcmd_t	cmd = {};
	usercmd_t	original_cmd = {};
	uint32_t		original_oldbuttons = 0;

	userinfo_t	userinfo;				// [RH] who is this?
	
	PClassActor *cls = nullptr;				// class of associated PlayerPawn

	float		DesiredFOV = 0;				// desired field of vision
	float		FOV = 0;					// current field of vision
	double		viewz = 0;					// focal origin above r.z
	double		viewheight = 0;				// base height above floor for viewz
	double		deltaviewheight = 0;		// squat speed.
	double		bob = 0;					// bounded/scaled total velocity

	// killough 10/98: used for realistic bobbing (i.e. not simply overall speed)
	// mo->velx and mo->vely represent true velocity experienced by player.
	// This only represents the thrust that the player applies himself.
	// This avoids anomalies with such things as Boom ice and conveyors.
	DVector2 Vel = { 0.0, 0.0 };

	bool		centering = false;
	uint8_t		turnticks = 0;
	bool		resetDoomYaw = false;


	bool		attackdown = false;
	bool		ohattackdown = false;
	bool		usedown = false;
	uint32_t	oldbuttons = false;
	int			health = 0;					// only used between levels, mo->health
										// is used during levels

	int			inventorytics = 0;
	uint8_t		CurrentPlayerClass = 0;		// class # for this player instance

	int			frags[MAXPLAYERS] = {};		// kills of other players
	int			fragcount = 0;				// [RH] Cumulative frags for this player
	int			lastkilltime = 0;			// [RH] For multikills
	uint8_t		multicount = 0;
	uint8_t		spreecount = 0;				// [RH] Keep track of killing sprees
	uint32_t	WeaponState = 0;

	AActor	   *ReadyWeapon = nullptr;
	AActor	   *PendingWeapon = nullptr;			// WP_NOCHANGE if not changing
	AActor     *OffhandWeapon = nullptr;
	TObjPtr<DPSprite*> psprites = MakeObjPtr<DPSprite*>(nullptr); // view sprites (gun, etc)

	int			cheats = 0;					// bit flags
	int			timefreezer = 0;			// Player has an active time freezer
	short		refire = 0;					// refired shots are less accurate
	short		inconsistant = 0;
	bool		waiting = 0;
	int			killcount = 0, itemcount = 0, secretcount = 0;		// for intermission
	uint32_t	damagecount = 0, bonuscount = 0;// for screen flashing
	int			hazardcount = 0;			// for delayed Strife damage
	int			hazardinterval = 0;			// Frequency of damage infliction
	FName		hazardtype = NAME_None;				// Damage type of last hazardous damage encounter.
	int			poisoncount = 0;			// screen flash for poison damage
	FName		poisontype = NAME_None;				// type of poison damage to apply
	FName		poisonpaintype = NAME_None;			// type of Pain state to enter for poison damage
	TObjPtr<AActor*>		poisoner = MakeObjPtr<AActor*>(nullptr);		// NULL for non-player actors
	
	DVector3 vr_recoil_offset[2];      // Linear displacement (x, y, z) for each hand
	DVector3 vr_recoil_rotation[2];    // Angular displacement (p, y, r) for each hand
	float vr_recoil_pitch_accum = 0;   // Accumulated aim climb pitch
	float vr_recoil_yaw_accum = 0;     // Accumulated aim climb yaw
	int vr_recoil_reset_tic = 0;       // Tic counter for recoil decay


	TObjPtr<AActor*>		attacker = MakeObjPtr<AActor*>(nullptr);		// who did damage (NULL for floors)
	int			extralight = 0;				// so gun flashes light up areas
	short		fixedcolormap = 0;			// can be set to REDCOLORMAP, etc.
	short		fixedlightlevel = 0;
	int			morphTics = 0;				// player is a chicken/pig if > 0
	PClassActor *MorphedPlayerClass = nullptr;		// [MH] (for SBARINFO) class # for this player instance when morphed
	int			MorphStyle = 0;				// which effects to apply for this player instance when morphed
	PClassActor *MorphExitFlash = nullptr;		// flash to apply when demorphing (cache of value given to MorphPlayer)
	TObjPtr<AActor*>	PremorphWeapon = MakeObjPtr<AActor*>(nullptr);		// ready weapon before morphing
	TObjPtr<AActor*>	PremorphWeaponOffhand = MakeObjPtr<AActor*>(nullptr);	// offhand weapon before morphing
	int			chickenPeck = 0;			// chicken peck countdown
	int			jumpTics = 0;				// delay the next jump for a moment
	bool		onground = 0;				// Identifies if this player is on the ground or other object
	bool		keepmomentum = 0;			// keep momentum until velocity reach 0, override vr_momentum
	bool		crossingPortal = 0;			// Crossing a portal (disables sprite from showing up)

	int			respawn_time = 0;			// [RH] delay respawning until this tic
	TObjPtr<AActor*>	camera = MakeObjPtr<AActor*>(nullptr);			// [RH] Whose eyes this player sees through

	int			air_finished = 0;			// [RH] Time when you start drowning

	FName		LastDamageType = NAME_None;			// [RH] For damage-specific pain and death sounds

	TObjPtr<AActor*> MUSINFOactor = MakeObjPtr<AActor*>(nullptr);		// For MUSINFO purposes
	int8_t		MUSINFOtics = 0;

	bool		settings_controller = false;	// Player can control game settings.
	int8_t		crouching = 0;
	int8_t		crouchdir = 0;
	int			Wallet = 0;
	int			score = 0;
	DVector3	vr_prev_hand_pos[2];
	DVector3	vr_hand_vel_buffer[2][4];
	int			vr_hand_vel_index[2];

	//Added by MC:
	TObjPtr<DBot*> Bot = MakeObjPtr<DBot*>(nullptr);

	float		BlendR = 0;		// [RH] Final blending values
	float		BlendG = 0;
	float		BlendB = 0;
	float		BlendA = 0;

	FString		SoundClass;
	FString		LogText;	// [RH] Log for Strife
	FString		SubtitleText;
	int			SubtitleCounter = 0;

	DAngle			MinPitch = nullAngle;	// Viewpitch limits (negative is up, positive is down)
	DAngle			MaxPitch = nullAngle;

	double crouchfactor = 0;
	double crouchoffset = 0;
	double crouchviewdelta = 0;

	FWeaponSlots weapons;

	// [CW] I moved these here for multiplayer conversation support.
	TObjPtr<AActor*> ConversationNPC = MakeObjPtr<AActor*>(nullptr), ConversationPC = MakeObjPtr<AActor*>(nullptr);
	DAngle ConversationNPCAngle = nullAngle;
	bool ConversationFaceTalker = false;

	DVector3 LastSafePos = {}; // Mark the last known safe location the player was standing.

	TObjPtr<AActor*> vr_held_items[2] = { MakeObjPtr<AActor*>(nullptr), MakeObjPtr<AActor*>(nullptr) };
	TObjPtr<AActor*> vr_grab_candidate[2] = { MakeObjPtr<AActor*>(nullptr), MakeObjPtr<AActor*>(nullptr) };
	bool vr_grab_is_locked[2] = { false, false };
	bool vr_grab_is_pulling[2] = { false, false };
	bool vr_grab_is_waiting_catch[2] = { false, false };
	double vr_held_item_distances[2] = { 0.0, 0.0 };
	bool vr_was_grip_pressed[2] = { false, false };

	struct line_t* vr_climbing_lines[2][10];
	int vr_climbing_cache_time[2];
	double vr_climbing_haptic_dist[2];
	double vr_climbing_speed[2];
	bool vr_is_climbing[2] = { false, false };
	// [XR grip arbiter] published by the whip (GM_ATTACHED + AltFire held), read by native climb via
	// P_VRWhipSwingActive so climb yields its Vel write + gravity flag to a live pendulum swing (fling fix).
	// Per-player (grappleActive is single-actor state, one whip per player). POD bool, zero-init like the
	// climb flags above -- NOT subject to the AActor-defaults FString-clobber. TRANSIENT: do NOT serialize.
	bool vr_whip_swing_live = false;
	DVector3 vr_climb_start_pos[2];

	int vr_hand_state[2] = { 0, 0 }; // 0: Idle, 1: Grip, 2: Climb, 3: Point
	bool vr_two_hand_stabilized = false;

	// ---- VR HARDPOINT MOUNTS (native, per-tic; see VR_UpdateHardpoints in p_user.cpp) ----
	// Per-player runtime hardpoint state. Fixed array (parity with vr_climbing_lines[2][10] above);
	// TObjPtr<AActor*> for the stowed weapon mirrors the vr_held_items GC pattern (line 473).
	struct VRHardpointRuntime
	{
		int   anchor  = HP_ANCHOR_BODY;   // EHardpointAnchor: body- vs wrist-relative world anchor
		int   action  = HP_ACT_HOLSTER;   // EHardpointAction: holster/draw vs fire an ability hook
		int   hand    = -1;               // -1 = either hand may reach; 0/1 = restrict to one hand
		float ox = 0.f, oy = 0.f, oz = 0.f; // local offset (map units) from the anchor
		float radius  = 0.f;              // per-slot reach; <=0 => use cvar vr_hardpoint_radius
		int   cells   = 1;                // visual grid footprint ("squares"); UI-only, copied
		                                   // from FHardpointSlot::cells at seed/AssignHardpoint time
		bool  occupied = false;           // a weapon is currently stowed at this slot
		bool  enabled  = false;           // slot is active
		TObjPtr<AActor*> stowedWeapon = MakeObjPtr<AActor*>(nullptr); // holstered weapon actor (GC-safe)
	};
	VRHardpointRuntime vr_hardpoints[VR_MAX_HARDPOINTS];
	int  vr_hardpoint_count = 0;
	bool vr_hardpoint_was_grip[2] = { false, false }; // OWN grip latch; does not fight vr_was_grip_pressed above
	bool vr_hardpoints_initialized = false;           // lazy one-shot seed from FVRConfig::Hardpoints on first VR_UpdateHardpoints tic

	// ---- ARM IK SOLVED POSE (native; written by VR_UpdateArmIK in p_user.cpp, read by the model-render path) ----
	// One parent-local TRS per whole skeleton so the render path can point proceduralPose straight at it
	// (same TArray<TRS> element type as DActorModelData::proceduralPose). Sized to the avatar model's
	// joint count on first solve; empty => IK inactive this tic.
	// TRANSIENT / CLIENT-PRESENTATION-ONLY: vr_ik_pose is derived each tic from the local render-side hand
	// transform (GetWeaponTransform), NOT authoritative playsim state -- it must be EXCLUDED from the
	// player_t FSerializer << list (do not add these 4 fields there), or transient render state gets
	// persisted into savegames/net, reintroducing the VR-aim-leak antipattern.
	TArray<TRS> vr_ik_pose;                       // bind TRS for non-arm joints, solved TRS for the arm chain
	bool        vr_ik_active = false;             // true when VR_UpdateArmIK wrote a valid pose this tic
	bool        vr_ik_enabled = true;             // per-player gate toggled by the SetArmIKEnabled thunk
	float       vr_grip_value[2] = { 0.f, 0.f };  // ANALOG squeeze 0..1, mirrored from VRMode::GetGripValue each tic
	// ---- CENTRAL GRIP-INTENT ARBITER (native; VR_ResolveGripOwner writes, all grip consumers + whip thunks read) ----
	// EGripOwner (file-scope enum in p_user.cpp): 0 NONE,1 CLIMB,2 GLOVE,3 WHIP,4 HARDPOINT,5 TWOHAND.
	// ALL PHYSICAL-controller-indexed (0=LEFT,1=RIGHT) -- same space as VR_IsGripPressed / vr_hand_vel_buffer.
	// TRANSIENT CLIENT-PRESENTATION STATE -- EXCLUDE from the player_t FSerializer << list (same rule as
	// vr_ik_pose / vr_body_facing_yaw below), or grip ownership leaks into savegames/net.
	int  vr_grip_owner[2]         = { 0, 0 };            // GRIP_NONE; the arbiter verdict this tic
	int  vr_grip_owner_prev[2]    = { 0, 0 };            // last tic (edge detection + continuation latch)
	bool vr_grip_raw[2]           = { false, false };    // ONE canonical grip read this tic (sanitized ticcmd)
	bool vr_grip_raw_prev[2]      = { false, false };    // replaces vr_was_grip_pressed + vr_hardpoint_was_grip
	bool vr_grip_committed[2]     = { false, false };    // Schmitt latch for the analog commit gate
	bool vr_whip_rope_attached[2] = { false, false };    // whip publishes (PHYSICAL index) on GM_ATTACHED only; arbiter reads
	// [XR] Decoupled body-avatar facing (deg). The pawn yaw follows the HMD, so drawing the body at it
	// spins the whole torso when you turn your head ("no neck"). The render reads this instead for the
	// local VR body; P_PlayerThink holds it steady until the head turns past a dead-zone, then catches
	// up. Transient client-presentation state -- do NOT serialize (same rule as vr_ik_pose above).
	float       vr_body_facing_yaw = 0.f;
	bool        vr_body_facing_valid = false;

	double GetDeltaViewHeight() const
	{
		return (mo->FloatVar(NAME_ViewHeight) + crouchviewdelta - viewheight) / 8;
	}

	double DefaultViewHeight() const
	{
		return mo->FloatVar(NAME_ViewHeight);
	}

	void Uncrouch()
	{
		if (crouchfactor != 1)
		{
			crouchfactor = 1;
			crouchoffset = 0;
			crouchdir = 0;
			crouching = 0;
			crouchviewdelta = 0;
			viewheight = mo ? mo->FloatVar(NAME_ViewHeight) : 0;
		}
	}
	
	int GetSpawnClass();

	// PSprite layers
	void TickPSprites();
	void DestroyPSprites();
	DPSprite *FindPSprite(int layer);
	// Used ONLY for compatibility with the old hardcoded layers.
	// Make sure that a state is properly set after calling this unless
	// you are 100% sure the context already implies the layer exists.
	DPSprite *GetPSprite(PSPLayers layer, AActor *newcaller = nullptr);

	// [Nash] set player FOV
	void SetFOV(float fov);
	bool HasWeaponsInSlot(int slot) const;
	bool Resurrect();

	// Scaled angle adjustment info. Not for direct manipulation.
	DRotator angleOffsetTargets;

	bool PlayInVR = false;	// Identifies if this player is playing in VR
};

// Bookkeeping on players - state.
extern player_t players[MAXPLAYERS];

void P_CheckPlayerSprite(AActor *mo, int &spritenum, DVector2 &scale);
void EnumColorSets(PClassActor *pc, TArray<int> *out);
FPlayerColorSet *GetColorSet(PClassActor *pc, int setnum);

inline void AActor::SetFriendPlayer(player_t *player)
{
	if (player == NULL)
	{
		FriendPlayer = 0;
	}
	else
	{
		FriendPlayer = int(player - players) + 1;
	}
}

inline bool AActor::IsNoClip2() const
{
	if (player != NULL && player->mo == this)
	{
		return (player->cheats & CF_NOCLIP2) != 0;
	}
	return false;
}

bool P_IsPlayerTotallyFrozen(const player_t *player);

bool P_NoInterpolation(player_t const *player, AActor const *actor);

#endif // __D_PLAYER_H__
