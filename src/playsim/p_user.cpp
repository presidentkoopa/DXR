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
// DESCRIPTION:
//		Player related stuff.
//		Bobbing POV/weapon, movement.
//		Pending weapon.
//
//-----------------------------------------------------------------------------

/* For code that originates from ZDoom the following applies:
**
**---------------------------------------------------------------------------
**
** Redistribution and use in source and binary forms, with or without
** modification, are permitted provided that the following conditions
** are met:
**
** 1. Redistributions of source code must retain the above copyright
**    notice, this list of conditions and the following disclaimer.
** 2. Redistributions in binary form must reproduce the above copyright
**    notice, this list of conditions and the following disclaimer in the
**    documentation and/or other materials provided with the distribution.
** 3. The name of the author may not be used to endorse or promote products
**    derived from this software without specific prior written permission.
**
** THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
** IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
** OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
** IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
** INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
** NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
** DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
** THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
** (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
** THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
**---------------------------------------------------------------------------
**
*/

#include <QzDoom/VrCommon.h>

#include "doomdef.h"
#include "d_event.h"
#include "p_local.h"
#include "doomstat.h"
#include "s_sound.h"
#include "gi.h"
#include "m_random.h"
#include "p_pspr.h"
#include "p_enemy.h"
#include "a_sharedglobal.h"
#include "a_keys.h"
#include "filesystem.h"
#include "cmdlib.h"
#include "sbar.h"
#include "intermission/intermission.h"
#include "c_console.h"
#include "c_dispatch.h"
#include "d_net.h"
#include "serializer_doom.h"
#include "serialize_obj.h"
#include "d_player.h"
#include "r_utility.h"
#include "p_blockmap.h"
#include "a_morph.h"
#include "p_spec.h"
#include "vm.h"
#include "g_levellocals.h"
#include "actorinlines.h"
#include "p_acs.h"
#include "events.h"
#include "g_game.h"
#include "v_video.h"
#include "gstrings.h"
#include "s_music.h"
#include "d_main.h"
#include "hw_vrmodes.h"
#include "model.h"          // FModel, extern TDeletingArray<FModel*> Models -- VR_UpdateArmIK reads joint data
#include "vr_hardpoint.h"   // EHardpointAnchor/Action, FHardpointSlot, VR_MAX_HARDPOINTS, VRHardpointRuntime
#include "vr_config.h"      // FVRConfig::Hardpoints (seeded in vr_config.cpp LoadConfig)
#include "p_maputl.h"
#include "textures.h"
#include "texturemanager.h"
#include "p_linetracedata.h"
#include "p_trace.h"
#include "keyword_dispatcher.h"
#include "gametexture.h"

EXTERN_CVAR(Bool, vr_autoequip)
EXTERN_CVAR(Int, vr_control_scheme)
EXTERN_CVAR(Bool, vr_twohand_whitelist_only)
EXTERN_CVAR(Float, vr_twohand_radius)
EXTERN_CVAR(Float, vr_twohand_length)
EXTERN_CVAR(Float, vr_climb_radius)
EXTERN_CVAR(Float, vr_climb_speed_mult)
EXTERN_CVAR(Bool, vr_grab_debug)
EXTERN_CVAR(Float, vr_throw_force)
EXTERN_CVAR(Bool, vr_throw_equip)
EXTERN_CVAR(Float, vr_throw_equip_min_speed)
EXTERN_CVAR(Bool, vr_easy_grab_props)
EXTERN_CVAR(Float, vr_easy_grab_scale)
EXTERN_CVAR(Float, vr_scale_meters_to_units)
EXTERN_CVAR(Bool, vr_allow_bullet_snatching)
EXTERN_CVAR(Float, vr_catch_radius)
EXTERN_CVAR(Bool, vr_catch_haptic)
EXTERN_CVAR(Bool, vr_catch_spark)
EXTERN_CVAR(Bool, vr_two_handed_weapons)
// [XR grip arbiter]
EXTERN_CVAR(Bool,  vr_grip_arbiter)
EXTERN_CVAR(Bool,  vr_grip_arbiter_hysteresis)
EXTERN_CVAR(Float, vr_grip_commit_arm)
EXTERN_CVAR(Float, vr_grip_commit_release)
EXTERN_CVAR(Bool,  vr_whip_grip_pump)
// [XR weapon handling] master toggle + hotspot/foregrip/reload tuning (declared in hw_vrmodes.cpp)
EXTERN_CVAR(Bool,  vr_new_weapon_handling)
EXTERN_CVAR(Float, vr_weapon_hotspot_radius)
EXTERN_CVAR(Float, vr_foregrip_radius)
EXTERN_CVAR(Float, vr_reload_assist)
EXTERN_CVAR(Float, vr_reload_magwell_radius)
EXTERN_CVAR(Float, vr_reload_rack_radius)
EXTERN_CVAR(Float, vr_reload_rack_travel)
EXTERN_CVAR(Bool,  vr_reload_chamber)
EXTERN_CVAR(Int,   vr_reload_perfect_window)
EXTERN_CVAR(Int,   vr_reload_perfect_life)
EXTERN_CVAR(Int,   vr_reload_heat_per_shot)
EXTERN_CVAR(Int,   vr_reload_heat_max)
EXTERN_CVAR(Bool,  vr_reload_toss_catch)
EXTERN_CVAR(Float, vr_climb_radius)
EXTERN_CVAR(Float, vr_climb_speed_mult)
EXTERN_CVAR(Float, vr_grab_cone_angle)
EXTERN_CVAR(Float, vr_grab_max_dist)
// [XR hand-world collision] declared in hw_vrmodes.cpp
EXTERN_CVAR(Bool,  vr_hand_collision)
EXTERN_CVAR(Float, vr_hand_collision_radius)
EXTERN_CVAR(Bool,  vr_hand_collision_glow)
EXTERN_CVAR(Float, vr_hand_glow_range)
EXTERN_CVAR(Float, vr_hand_glow_min_radius)
EXTERN_CVAR(Float, vr_hand_glow_max_radius)
EXTERN_CVAR(Color, vr_hand_glow_color)
EXTERN_CVAR(Color, vr_hand_glow_climb_color)
EXTERN_CVAR(Bool,  vr_hand_ik_clamp)

// [XR interaction glows] declared in hw_vrmodes.cpp
EXTERN_CVAR(Float, vr_catch_glow_radius)
EXTERN_CVAR(Color, vr_catch_glow_color)
EXTERN_CVAR(Bool,  vr_throw_arc_glow_enable)
EXTERN_CVAR(Float, vr_throw_arc_glow_radius)
EXTERN_CVAR(Color, vr_throw_arc_glow_color)
EXTERN_CVAR(Bool,  vr_grab_highlight_enable)
EXTERN_CVAR(Float, vr_grab_highlight_radius)
EXTERN_CVAR(Color, vr_grab_highlight_color)
EXTERN_CVAR(Bool,  vr_twohand_glow_enable)
EXTERN_CVAR(Float, vr_twohand_glow_radius)
EXTERN_CVAR(Color, vr_twohand_glow_color)
EXTERN_CVAR(Bool,  vr_hardpoint_glow_enable)
EXTERN_CVAR(Float, vr_hardpoint_glow_range)
EXTERN_CVAR(Float, vr_hardpoint_glow_min_radius)
EXTERN_CVAR(Float, vr_hardpoint_glow_max_radius)
EXTERN_CVAR(Color, vr_hardpoint_glow_color_body)
EXTERN_CVAR(Color, vr_hardpoint_glow_color_wrist)
EXTERN_CVAR(Bool,  vr_reload_glow_enable)
EXTERN_CVAR(Float, vr_reload_glow_radius)
EXTERN_CVAR(Color, vr_reload_glow_color)
EXTERN_CVAR(Float, vr_grab_weight_dist)
EXTERN_CVAR(Float, vr_grab_weight_align)
EXTERN_CVAR(Float, vr_grab_weight_mass)

// [XR] shared airborne glow-spot push (def'd near VR_UpdateHandCollision, later in this file) --
// forward-declared this early since VR_CalculateTwoHanding/VR_UpdateGravityGloves use it too.
static void VR_PushWorldGlow(FLevelLocals* lvl, const DVector3& pos, PalEntry color, double radius);

static FRandom pr_skullpop ("SkullPop");

// [SP] Allows respawn in single player
CVAR(Bool, sv_singleplayerrespawn, false, CVAR_SERVERINFO | CVAR_CHEAT)
CVAR(Float, snd_footstepvolume, 1.f, CVAR_ARCHIVE | CVAR_GLOBALCONFIG)

// Variables for prediction
CVAR(Bool, cl_predict_specials, true, CVAR_ARCHIVE | CVAR_GLOBALCONFIG)
// Deprecated
CVAR(Bool, cl_noprediction, false, CVAR_ARCHIVE | CVAR_GLOBALCONFIG)
CVAR(Float, cl_predict_lerpscale, 0.05f, CVAR_ARCHIVE | CVAR_GLOBALCONFIG)
CVAR(Float, cl_predict_lerpthreshold, 2.00f, CVAR_ARCHIVE | CVAR_GLOBALCONFIG)

CUSTOM_CVAR(Float, cl_rubberband_scale, 0.3f, CVAR_ARCHIVE | CVAR_GLOBALCONFIG)
{
	if (self < 0.0f)
		self = 0.0f;
	else if (self > 1.0f)
		self = 1.0f;
}
CUSTOM_CVAR(Float, cl_rubberband_threshold, 20.0f, CVAR_ARCHIVE | CVAR_GLOBALCONFIG)
{
	if (self < 0.1f)
		self = 0.1f;
}
CUSTOM_CVAR(Float, cl_rubberband_minmove, 20.0f, CVAR_ARCHIVE | CVAR_GLOBALCONFIG)
{
	if (self < 0.1f)
		self = 0.1f;
}
CUSTOM_CVAR(Float, cl_rubberband_limit, 756.0f, CVAR_ARCHIVE | CVAR_GLOBALCONFIG)
{
	if (self < 0.0f)
		self = 0.0f;
}

ColorSetList ColorSets;
PainFlashList PainFlashes;

// [Nash] FOV cvar setting
CUSTOM_CVAR(Float, fov, 90.f, CVAR_ARCHIVE | CVAR_USERINFO | CVAR_NOINITCALL)
{
	player_t *p = &players[consoleplayer];
	p->SetFOV(fov);
}

static DVector3 LastPredictedPosition;
static int LastPredictedPortalGroup;
static int LastPredictedTic;

static TArray<FRandom> PredictionRNG;

static player_t PredictionPlayerBackup;
static AActor *PredictionActor;
static TArray<uint8_t> PredictionActorBackupArray;
static TArray<AActor *> PredictionSectorListBackup;

static TArray<sector_t *> PredictionTouchingSectorsBackup;
static TArray<msecnode_t *> PredictionTouchingSectors_sprev_Backup;

static TArray<sector_t *> PredictionRenderSectorsBackup;
static TArray<msecnode_t *> PredictionRenderSectors_sprev_Backup;

static TArray<sector_t *> PredictionPortalSectorsBackup;
static TArray<msecnode_t *> PredictionPortalSectors_sprev_Backup;

static TArray<FLinePortal *> PredictionPortalLinesBackup;
static TArray<portnode_t *> PredictionPortalLines_sprev_Backup;

struct
{
	DVector3 Pos = {};
	int Flags = 0;
} static PredictionViewPosBackup;

// [GRB] Custom player classes
TArray<FPlayerClass> PlayerClasses;

FPlayerClass::FPlayerClass ()
{
	Type = NULL;
	Flags = 0;
}

FPlayerClass::~FPlayerClass ()
{
}

bool FPlayerClass::CheckSkin (int skin)
{
	for (unsigned int i = 0; i < Skins.Size (); i++)
	{
		if (Skins[i] == skin)
			return true;
	}

	return false;
}

DEFINE_ACTION_FUNCTION(FPlayerClass, CheckSkin)
{
	PARAM_SELF_STRUCT_PROLOGUE(FPlayerClass);
	PARAM_INT(skin);
	ACTION_RETURN_BOOL(self->CheckSkin(skin));
}

//===========================================================================
//
// GetDisplayName
//
//===========================================================================

FString GetPrintableDisplayName(PClassActor *cls)
{ 
	// Fixme; This needs a decent way to access the string table without creating a mess.
	// [RH] ????
	return cls->GetDisplayName();
}

bool ValidatePlayerClass(PClassActor *ti, const char *name)
{
	if (ti == NULL)
	{
		Printf("Unknown player class '%s'\n", name);
		return false;
	}
	else if (!ti->IsDescendantOf(NAME_PlayerPawn))
	{
		Printf("Invalid player class '%s'\n", name);
		return false;
	}
	else if (ti->GetDisplayName().IsEmpty())
	{
		Printf ("Missing displayname for player class '%s'\n", name);
		return false;
	}
	return true;
}

void SetupPlayerClasses ()
{
	FPlayerClass newclass;

	PlayerClasses.Clear();
	for (unsigned i = 0; i < gameinfo.PlayerClasses.Size(); i++)
	{
		PClassActor *cls = PClass::FindActor(gameinfo.PlayerClasses[i]);
		if (ValidatePlayerClass(cls, gameinfo.PlayerClasses[i].GetChars()))
		{
			newclass.Flags = 0;
			newclass.Type = cls;
			if ((GetDefaultByType(cls)->flags6 & MF6_NOMENU))
			{
				newclass.Flags |= PCF_NOMENU;
			}
			PlayerClasses.Push(newclass);
		}
	}
}

CCMD (playerclasses)
{
	for (unsigned int i = 0; i < PlayerClasses.Size (); i++)
	{
		Printf ("%3d: Class = %s, Name = %s\n", i,
			PlayerClasses[i].Type->TypeName.GetChars(),
			PlayerClasses[i].Type->GetDisplayName().GetChars());
	}
}

//
// Movement.
//

player_t::~player_t()
{
	DestroyPSprites();
}

void player_t::CopyFrom(player_t &p, bool copyPSP)
{
	mo = p.mo;
	playerstate = p.playerstate;
	cmd = p.cmd;
	original_cmd = p.original_cmd;
	original_oldbuttons = p.original_oldbuttons;
	// Intentionally not copying userinfo!
	cls = p.cls;
	DesiredFOV = p.DesiredFOV;
	FOV = p.FOV;
	viewz = p.viewz;
	viewheight = p.viewheight;
	deltaviewheight = p.deltaviewheight;
	bob = p.bob;
	Vel = p.Vel;
	centering = p.centering;
	turnticks = p.turnticks;
	attackdown = p.attackdown;
	ohattackdown = p.ohattackdown;
	usedown = p.usedown;
	oldbuttons = p.oldbuttons;
	health = p.health;
	inventorytics = p.inventorytics;
	CurrentPlayerClass = p.CurrentPlayerClass;
	memcpy(frags, &p.frags, sizeof(frags));
	fragcount = p.fragcount;
	lastkilltime = p.lastkilltime;
	multicount = p.multicount;
	spreecount = p.spreecount;
	WeaponState = p.WeaponState;
	ReadyWeapon = p.ReadyWeapon;
	PendingWeapon = p.PendingWeapon;
	OffhandWeapon = p.OffhandWeapon;
	cheats = p.cheats;
	timefreezer = p.timefreezer;
	refire = p.refire;
	inconsistant = p.inconsistant;
	waiting = p.waiting;
	killcount = p.killcount;
	itemcount = p.itemcount;
	secretcount = p.secretcount;
	damagecount = p.damagecount;
	bonuscount = p.bonuscount;
	hazardcount = p.hazardcount;
	hazardtype = p.hazardtype;
	hazardinterval = p.hazardinterval;
	poisoncount = p.poisoncount;
	poisontype = p.poisontype;
	poisonpaintype = p.poisonpaintype;
	poisoner = p.poisoner;
	attacker = p.attacker;
	extralight = p.extralight;
	fixedcolormap = p.fixedcolormap;
	fixedlightlevel = p.fixedlightlevel;
	morphTics = p.morphTics;
	MorphedPlayerClass = p.MorphedPlayerClass;
	MorphStyle = p.MorphStyle;
	MorphExitFlash = p.MorphExitFlash;
	PremorphWeapon = p.PremorphWeapon;
	PremorphWeaponOffhand = p.PremorphWeaponOffhand;
	chickenPeck = p.chickenPeck;
	jumpTics = p.jumpTics;
	onground = p.onground;
	respawn_time = p.respawn_time;
	camera = p.camera;
	air_finished = p.air_finished;
	LastDamageType = p.LastDamageType;
	Bot = p.Bot;
	settings_controller = p.settings_controller;
	BlendR = p.BlendR;
	BlendG = p.BlendG;
	BlendB = p.BlendB;
	BlendA = p.BlendA;
	LogText = p.LogText;
	MinPitch = p.MinPitch;
	MaxPitch = p.MaxPitch;
	crouching = p.crouching;
	crouchdir = p.crouchdir;
	crouchfactor = p.crouchfactor;
	crouchoffset = p.crouchoffset;
	crouchviewdelta = p.crouchviewdelta;
	weapons = p.weapons;
	ConversationNPC = p.ConversationNPC;
	ConversationPC = p.ConversationPC;
	ConversationNPCAngle = p.ConversationNPCAngle;
	ConversationFaceTalker = p.ConversationFaceTalker;
	MUSINFOactor = p.MUSINFOactor;
	MUSINFOtics = p.MUSINFOtics;
	SoundClass = p.SoundClass;
	LastSafePos = p.LastSafePos;
	angleOffsetTargets = p.angleOffsetTargets;
	if (copyPSP)
	{
		// This needs to transfer ownership completely.
		psprites = p.psprites;
		p.psprites = nullptr;
	}
}

size_t player_t::PropagateMark()
{
	GC::Mark(mo);
	GC::Mark(poisoner);
	GC::Mark(attacker);
	GC::Mark(camera);
	GC::Mark(Bot);
	GC::Mark(ReadyWeapon);
	GC::Mark(OffhandWeapon);
	GC::Mark(ConversationNPC);
	GC::Mark(ConversationPC);
	GC::Mark(MUSINFOactor);
	GC::Mark(PremorphWeapon);
	GC::Mark(PremorphWeaponOffhand);
	GC::Mark(psprites);
	if (PendingWeapon != WP_NOCHANGE)
	{
		GC::Mark(PendingWeapon);
	}
	// VR hardpoint slots may hold a stowed weapon that has been detached from the
	// live inventory chain (ReadyWeapon/OffhandWeapon nulled on holster). Without a
	// mark here that weapon becomes GC-collectible and silently vanishes from its slot.
	for (int i = 0; i < vr_hardpoint_count; ++i)
	{
		if (vr_hardpoints[i].occupied)
		{
			GC::Mark(vr_hardpoints[i].stowedWeapon);
		}
	}
	// [XR weapon handling] vr_reload_weapon aliases the live ReadyWeapon (already marked), but mark it
	// defensively so a mid-reload weapon swap can never leave a dangling tracked pointer.
	GC::Mark(vr_reload_weapon);
	return sizeof(*this);
}

void player_t::SetLogNumber (int num)
{
	char lumpname[26];
	int lumpnum;

	// First look up TXT_LOGTEXT%d in the string table
	mysnprintf(lumpname, countof(lumpname), "$TXT_LOGTEXT%d", num);
	auto text = GStrings.CheckString(lumpname+1);
	if (text)
	{
		SetLogText(lumpname);	// set the label, not the content, so that a language change can be picked up.
		return;
	}

	mysnprintf (lumpname, countof(lumpname), "LOG%d", num);
	lumpnum = fileSystem.CheckNumForName (lumpname);
	if (lumpnum != -1)
	{
		auto fn = fileSystem.GetFileContainer(lumpnum);
		auto wadname = fileSystem.GetResourceFileName(fn);
		if (!stricmp(wadname, "STRIFE0.WAD") || !stricmp(wadname, "STRIFE1.WAD") || !stricmp(wadname, "SVE.WAD"))
		{
			// If this is an original IWAD text, try looking up its lower priority string version first.

			mysnprintf(lumpname, countof(lumpname), "$TXT_ILOG%d", num);
			auto text = GStrings.CheckString(lumpname + 1);
			if (text)
			{
				SetLogText(lumpname);	// set the label, not the content, so that a language change can be picked up.
				return;
			}
		}

		auto lump = fileSystem.ReadFile(lumpnum);
		SetLogText (lump.string());
	}
}

DEFINE_ACTION_FUNCTION(_PlayerInfo, SetLogNumber)
{
	PARAM_SELF_STRUCT_PROLOGUE(player_t);
	PARAM_INT(log);
	self->SetLogNumber(log);
	return 0;
}

void player_t::SetLogText (const char *text)
{
	 LogText = text;

	if (mo && mo->CheckLocalView())
	{
		// Print log text to console
		Printf(PRINT_HIGH | PRINT_NONOTIFY, TEXTCOLOR_GOLD "%s\n", LogText[0] == '$' ? GStrings.GetString(text + 1) : text);
	}
}

DEFINE_ACTION_FUNCTION(_PlayerInfo, SetLogText)
{
	PARAM_SELF_STRUCT_PROLOGUE(player_t);
	PARAM_STRING(log);
	self->SetLogText(log.GetChars());
	return 0;
}

void player_t::SetSubtitle(int num, FSoundID soundid)
{
	char lumpname[36];

	if (gameinfo.flags & GI_SHAREWARE) return;	// Subtitles are only for the full game.

	// Do we have a subtitle for this log entry's voice file?
	mysnprintf(lumpname, countof(lumpname), "$TXT_SUB_LOG%d", num);
	auto text = GStrings.GetLanguageString(lumpname+1, FStringTable::default_table);
	if (text != nullptr)
	{
		SubtitleText = lumpname;
		int sl = soundid == NO_SOUND ? 7000 : max<int>(7000, S_GetMSLength(soundid));
		SubtitleCounter = sl * TICRATE / 1000;
	}
}

DEFINE_ACTION_FUNCTION(_PlayerInfo, SetSubtitleNumber)
{
	PARAM_SELF_STRUCT_PROLOGUE(player_t);
	PARAM_INT(log);
	PARAM_SOUND(soundid);
	self->SetSubtitle(log, soundid);
	return 0;
}



int player_t::GetSpawnClass()
{
	const PClass * type = PlayerClasses[CurrentPlayerClass].Type;
	return GetDefaultByType(type)->IntVar(NAME_SpawnMask);
}

// [Nash] Set FOV
void player_t::SetFOV(float fov)
{
	player_t *p = &players[consoleplayer];
	if (p != nullptr && p->mo != nullptr)
	{
		if (dmflags & DF_NO_FOV)
		{
			if (consoleplayer == Net_Arbitrator)
			{
				Net_WriteInt8(DEM_MYFOV);
			}
			else
			{
				Printf("A setting controller has disabled FOV changes.\n");
				return;
			}
		}
		else
		{
			Net_WriteInt8(DEM_MYFOV);
		}
		Net_WriteFloat(clamp<float>(fov, 5.f, 179.f));
	}
}

DEFINE_ACTION_FUNCTION(_PlayerInfo, SetFOV)
{
	PARAM_SELF_STRUCT_PROLOGUE(player_t);
	PARAM_FLOAT(fov);
	self->SetFOV((float)fov);
	return 0;
}

DEFINE_ACTION_FUNCTION(_PlayerInfo, SetSkin)
{
	PARAM_SELF_STRUCT_PROLOGUE(player_t);
	PARAM_INT(skinIndex);
	if (skinIndex >= 0 && skinIndex < Skins.size())
	{
		// commented code - cvar_set calls this automatically, along with saving the skin selection.
		//self->userinfo.SkinNumChanged(skinIndex);
		cvar_set("skin", Skins[skinIndex].Name.GetChars());
		ACTION_RETURN_INT(self->userinfo.GetSkin());
	}
	else
	{
		ACTION_RETURN_INT(-1);
	}
}

//===========================================================================
//
// EnumColorsets
//
// Only used by the menu so it doesn't really matter that it's a bit
// inefficient.
//
//===========================================================================

static int intcmp(const void *a, const void *b)
{
	return *(const int *)a - *(const int *)b;
}

void EnumColorSets(PClassActor *cls, TArray<int> *out)
{
	TArray<int> deleteds;

	out->Clear();
	for (int i = ColorSets.Size() - 1; i >= 0; i--)
	{
		if (std::get<0>(ColorSets[i])->IsAncestorOf(cls))
		{
			int v = std::get<1>(ColorSets[i]);
			if (out->Find(v) == out->Size() && deleteds.Find(v) == deleteds.Size())
			{
				if (std::get<2>(ColorSets[i]).Name == NAME_None) deleteds.Push(v);
				else out->Push(v);
			}
		}
	}
	qsort(&(*out)[0], out->Size(), sizeof(int), intcmp);
}

DEFINE_ACTION_FUNCTION(FPlayerClass, EnumColorSets)
{
	PARAM_SELF_STRUCT_PROLOGUE(FPlayerClass);
	PARAM_POINTER(out, TArray<int>);
	EnumColorSets(self->Type, out);
	return 0;
}

//==========================================================================
//
//
//==========================================================================

FPlayerColorSet *GetColorSet(PClassActor *cls, int setnum)
{
	for (int i = ColorSets.Size() - 1; i >= 0; i--)
	{
		if (std::get<1>(ColorSets[i]) == setnum &&
			std::get<0>(ColorSets[i])->IsAncestorOf(cls))
		{
			auto c = &std::get<2>(ColorSets[i]);
			return c->Name != NAME_None ? c : nullptr;
		}
	}
	return nullptr;
}

DEFINE_ACTION_FUNCTION(FPlayerClass, GetColorSetName)
{
	PARAM_SELF_STRUCT_PROLOGUE(FPlayerClass);
	PARAM_INT(setnum);
	auto p = GetColorSet(self->Type, setnum);
	ACTION_RETURN_INT(p ? p->Name.GetIndex() : 0);
}

//==========================================================================
//
//
//==========================================================================

static int GetPainFlash(AActor *info, int type)
{
	// go backwards through the list and return the first item with a 
	// matching damage type for an ancestor of our class. 
	// This will always return the best fit because any parent class
	// must be processed before its children.
	for (int i = PainFlashes.Size() - 1; i >= 0; i--)
	{
		if (std::get<1>(PainFlashes[i]) == ENamedName(type) &&
			std::get<0>(PainFlashes[i])->IsAncestorOf(info->GetClass()))
		{
			return std::get<2>(PainFlashes[i]);
		}
	}
	return 0;
}

DEFINE_ACTION_FUNCTION_NATIVE(APlayerPawn, GetPainFlashForType, GetPainFlash)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_INT(type);
	ACTION_RETURN_INT(GetPainFlash(self, type));
}

//===========================================================================
//
// player_t :: SendPitchLimits
//
// Ask the local player's renderer what pitch restrictions should be imposed
// and let everybody know. Only sends data for the consoleplayer, since the
// local player is the only one our data is valid for.
//
//===========================================================================

EXTERN_CVAR(Float, maxviewpitch)
EXTERN_CVAR(Bool, cl_oldfreelooklimit);


static int GetSoftPitch(bool down)
{
	int MAX_DN_ANGLE = min(56, (int)maxviewpitch); // Max looking down angle
	int MAX_UP_ANGLE = min(32, (int)maxviewpitch); // Max looking up angle
	return (down ? MAX_DN_ANGLE : ((cl_oldfreelooklimit) ? MAX_UP_ANGLE : MAX_DN_ANGLE));
}

void player_t::SendPitchLimits() const
{
	if (this - players == consoleplayer)
	{
		int uppitch, downpitch;

		if (!V_IsHardwareRenderer())
		{
			uppitch = GetSoftPitch(false);
			downpitch = GetSoftPitch(true);
		}
		else
		{
			uppitch = downpitch = (int)maxviewpitch;
		}

		Net_WriteInt8(DEM_SETPITCHLIMIT);
		Net_WriteInt8(uppitch);
		Net_WriteInt8(downpitch);
	}
}

DEFINE_ACTION_FUNCTION(_PlayerInfo, SendPitchLimits)
{
	PARAM_SELF_STRUCT_PROLOGUE(player_t);
	self->SendPitchLimits();
	return 0;
}


bool player_t::HasWeaponsInSlot(int slot) const
{
	for (int i = 0; i < weapons.SlotSize(slot); i++)
	{
		PClassActor *weap = weapons.GetWeapon(slot, i);
		if (weap != NULL && mo->FindInventory(weap)) return true;
	}
	return false;
}

DEFINE_ACTION_FUNCTION(_PlayerInfo, HasWeaponsInSlot)
{
	PARAM_SELF_STRUCT_PROLOGUE(player_t);
	PARAM_INT(slot);
	ACTION_RETURN_BOOL(self->HasWeaponsInSlot(slot));
}


bool player_t::Resurrect()
{
	if (mo == nullptr || mo->IsKindOf(NAME_PlayerChunk)) return false;
	mo->Revive();
	playerstate = PST_LIVE;
	health = mo->health = mo->GetDefault()->health;
	viewheight = DefaultViewHeight();
	mo->renderflags &= ~RF_INVISIBLE;
	mo->Height = mo->GetDefault()->Height;
	mo->radius = mo->GetDefault()->radius;
	mo->special1 = 0;	// required for the Hexen fighter's fist attack. 
								// This gets set by AActor::Die as flag for the wimpy death and must be reset here.
	mo->SetState(mo->SpawnState);
	int pnum = mo->Level->PlayerNum(this);
	if (!(mo->flags2 & MF2_DONTTRANSLATE))
	{
		mo->Translation = TRANSLATION(TRANSLATION_Players, uint8_t(pnum));
	}
	if (ReadyWeapon != nullptr)
	{
		PendingWeapon = ReadyWeapon;
		P_BringUpWeapon(this);
	}
	if (OffhandWeapon != nullptr)
	{
		PendingWeapon = OffhandWeapon;
		P_BringUpWeapon(this);
	}

	if (mo->alternative != nullptr)
	{
		P_UnmorphActor(mo, mo);
	}

	// player is now alive.
	// fire E_PlayerRespawned and start the ACS SCRIPT_Respawn.
	mo->Level->localEventManager->PlayerRespawned(pnum);
	mo->Level->Behaviors.StartTypedScripts(SCRIPT_Respawn, mo, true);
	return true;
}

DEFINE_ACTION_FUNCTION(_PlayerInfo, Resurrect)
{
	PARAM_SELF_STRUCT_PROLOGUE(player_t);
	ACTION_RETURN_BOOL(self->Resurrect());
}


DEFINE_ACTION_FUNCTION(_PlayerInfo, GetUserName)
{
	PARAM_SELF_STRUCT_PROLOGUE(player_t);
	PARAM_UINT(charLimit);
	ACTION_RETURN_STRING(self->userinfo.GetName(charLimit));
}

DEFINE_ACTION_FUNCTION(_PlayerInfo, GetNeverSwitch)
{
	PARAM_SELF_STRUCT_PROLOGUE(player_t);
	ACTION_RETURN_BOOL(self->userinfo.GetNeverSwitch());
}

DEFINE_ACTION_FUNCTION(_PlayerInfo, GetClassicFlight)
{
	PARAM_SELF_STRUCT_PROLOGUE(player_t);
	ACTION_RETURN_BOOL(self->userinfo.GetClassicFlight());
}

DEFINE_ACTION_FUNCTION(_PlayerInfo, GetColor)
{
	PARAM_SELF_STRUCT_PROLOGUE(player_t);
	ACTION_RETURN_INT(self->userinfo.GetColor());
}

DEFINE_ACTION_FUNCTION(_PlayerInfo, GetColorSet)
{
	PARAM_SELF_STRUCT_PROLOGUE(player_t);
	ACTION_RETURN_INT(self->userinfo.GetColorSet());
}

DEFINE_ACTION_FUNCTION(_PlayerInfo, GetPlayerClassNum)
{
	PARAM_SELF_STRUCT_PROLOGUE(player_t);
	ACTION_RETURN_INT(self->userinfo.GetPlayerClassNum());
}

DEFINE_ACTION_FUNCTION(_PlayerInfo, GetSkin)
{
	PARAM_SELF_STRUCT_PROLOGUE(player_t);
	ACTION_RETURN_INT(self->userinfo.GetSkin());
}

DEFINE_ACTION_FUNCTION(_PlayerInfo, GetSkinCount)
{
	PARAM_SELF_STRUCT_PROLOGUE(player_t);
	ACTION_RETURN_INT(Skins.size());
}

DEFINE_ACTION_FUNCTION(_PlayerInfo, GetGender)
{
	PARAM_SELF_STRUCT_PROLOGUE(player_t);
	ACTION_RETURN_INT(self->userinfo.GetGender());
}

DEFINE_ACTION_FUNCTION(_PlayerInfo, GetAutoaim)
{
	PARAM_SELF_STRUCT_PROLOGUE(player_t);
	ACTION_RETURN_FLOAT(self->userinfo.GetAutoaim());
}

DEFINE_ACTION_FUNCTION(_PlayerInfo, GetTeam)
{
	PARAM_SELF_STRUCT_PROLOGUE(player_t);
	ACTION_RETURN_INT(self->userinfo.GetTeam());
}

DEFINE_ACTION_FUNCTION(_PlayerInfo, GetNoAutostartMap)
{
	PARAM_SELF_STRUCT_PROLOGUE(player_t);
	ACTION_RETURN_INT(self->userinfo.GetNoAutostartMap());
}

DEFINE_ACTION_FUNCTION(_PlayerInfo, GetWBobSpeed)
{
	PARAM_SELF_STRUCT_PROLOGUE(player_t);
	ACTION_RETURN_FLOAT(self->userinfo.GetWBobSpeed());
}

DEFINE_ACTION_FUNCTION(_PlayerInfo, GetWBobFire)
{
	PARAM_SELF_STRUCT_PROLOGUE(player_t);
	ACTION_RETURN_FLOAT(self->userinfo.GetWBobFire());
}

DEFINE_ACTION_FUNCTION(_PlayerInfo, GetMoveBob)
{
	PARAM_SELF_STRUCT_PROLOGUE(player_t);
	ACTION_RETURN_FLOAT(self->userinfo.GetMoveBob());
}

DEFINE_ACTION_FUNCTION(_PlayerInfo, GetFViewBob)
{
	PARAM_SELF_STRUCT_PROLOGUE(player_t);
	ACTION_RETURN_BOOL(self->userinfo.GetFViewBob());
}

DEFINE_ACTION_FUNCTION(_PlayerInfo, GetStillBob)
{
	PARAM_SELF_STRUCT_PROLOGUE(player_t);
	ACTION_RETURN_FLOAT(self->userinfo.GetStillBob());
}


//===========================================================================
//
// 
//
//===========================================================================

static int SetupCrouchSprite(AActor *self, int crouchsprite)
{
	// Check whether a PWADs normal sprite is to be combined with the base WADs
	// crouch sprite. In such a case the sprites normally don't match and it is
	// best to disable the crouch sprite.
	if (crouchsprite > 0)
	{
		// This assumes that player sprites always exist in rotated form and
		// that the front view is always a separate sprite. So far this is
		// true for anything that exists.
		FString normspritename = sprites[self->SpawnState->sprite].name;
		FString crouchspritename = sprites[crouchsprite].name;

		int spritenorm = fileSystem.CheckNumForName((normspritename + "A1").GetChars(), FileSys::ns_sprites);
		if (spritenorm == -1)
		{
			spritenorm = fileSystem.CheckNumForName((normspritename + "A0").GetChars(), FileSys::ns_sprites);
		}

		int spritecrouch = fileSystem.CheckNumForName((crouchspritename + "A1").GetChars(), FileSys::ns_sprites);
		if (spritecrouch == -1)
		{
			spritecrouch = fileSystem.CheckNumForName((crouchspritename + "A0").GetChars(), FileSys::ns_sprites);
		}

		if (spritenorm == -1 || spritecrouch == -1)
		{
			// Sprites do not exist so it is best to disable the crouch sprite.
			return false;
		}

		int wadnorm = fileSystem.GetFileContainer(spritenorm);
		int wadcrouch = fileSystem.GetFileContainer(spritenorm);

		if (wadnorm > fileSystem.GetMaxIwadNum() && wadcrouch <= fileSystem.GetMaxIwadNum())
		{
			// Question: Add an option / disable crouching or do what?
			return false;
		}
	}
	return true;
}

DEFINE_ACTION_FUNCTION_NATIVE(APlayerPawn, SetupCrouchSprite, SetupCrouchSprite)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_INT(crouchsprite);
	ACTION_RETURN_INT(SetupCrouchSprite(self, crouchsprite));
}

//===========================================================================
//
// Animations
//
//===========================================================================

void PlayIdle (AActor *player)
{
	IFVIRTUALPTRNAME(player, NAME_PlayerPawn, PlayIdle)
	{
		VMValue params[1] = { (DObject*)player };
		VMCall(func, params, 1, nullptr, 0);
	}
}

//===========================================================================
//
// A_PlayerScream
//
// try to find the appropriate death sound and use suitable 
// replacements if necessary
//
//===========================================================================

DEFINE_ACTION_FUNCTION(AActor, A_PlayerScream)
{
	PARAM_SELF_PROLOGUE(AActor);

	FSoundID sound = NO_SOUND;
	int chan = CHAN_VOICE;

	if (self->player == NULL || self->DeathSound != NO_SOUND)
	{
		if (self->DeathSound != NO_SOUND)
		{
			S_Sound (self, CHAN_VOICE, CHANF_NONE, self->DeathSound, 1, ATTN_NORM);
		}
		else
		{
			S_Sound (self, CHAN_VOICE, CHANF_NONE, "*death", 1, ATTN_NORM);
		}
		return 0;
	}

	// Handle the different player death screams
	if ((((self->Level->flags >> 15) | (dmflags)) &
		(DF_FORCE_FALLINGZD | DF_FORCE_FALLINGHX)) &&
		self->Vel.Z <= -39)
	{
		sound = S_FindSkinnedSound (self, S_FindSound("*splat"));
		chan = CHAN_BODY;
	}

	if (!sound.isvalid() && self->special1<10)
	{ // Wimpy death sound
		sound = S_FindSkinnedSoundEx (self, "*wimpydeath", self->player->LastDamageType.GetChars());
	}
	if (!sound.isvalid() && self->health <= -50)
	{
		if (self->health > -100)
		{ // Crazy death sound
			sound = S_FindSkinnedSoundEx (self, "*crazydeath", self->player->LastDamageType.GetChars());
		}
		if (!sound.isvalid())
		{ // Extreme death sound
			sound = S_FindSkinnedSoundEx (self, "*xdeath", self->player->LastDamageType.GetChars());
			if (!sound.isvalid())
			{
				sound = S_FindSkinnedSoundEx (self, "*gibbed", self->player->LastDamageType.GetChars());
				chan = CHAN_BODY;
			}
		}
	}
	if (!sound.isvalid())
	{ // Normal death sound
		sound = S_FindSkinnedSoundEx (self, "*death", self->player->LastDamageType.GetChars());
	}

	if (chan != CHAN_VOICE)
	{
		for (int i = 0; i < 8; ++i)
		{ // Stop most playing sounds from this player.
		  // This is mainly to stop *land from messing up *splat.
			if (i != CHAN_WEAPON && i != CHAN_VOICE)
			{
				S_StopSound (self, i);
			}
		}
	}
	S_Sound (self, chan, CHANF_NONE, sound, 1, ATTN_NORM);
	return 0;
}


//===========================================================================
//
// P_CheckPlayerSprites
//
// Here's the place where crouching sprites are handled.
// R_ProjectSprite() calls this for any players.
//
//===========================================================================

void P_CheckPlayerSprite(AActor *actor, int &spritenum, DVector2 &scale)
{
	player_t *player = actor->player;
	int crouchspriteno;

	if (player->userinfo.GetSkin() != 0 && !(actor->flags4 & MF4_NOSKIN))
	{
		// Convert from default scale to skin scale.
		DVector2 defscale = actor->GetDefault()->Scale;
		scale.X *= Skins[player->userinfo.GetSkin()].Scale.X / double(defscale.X);
		scale.Y *= Skins[player->userinfo.GetSkin()].Scale.Y / double(defscale.Y);
	}

	// Set the crouch sprite?
	if (player->mo == actor && player->crouchfactor < 0.75)
	{
		int crouchsprite = player->mo->IntVar(NAME_crouchsprite);
		if (spritenum == actor->SpawnState->sprite || spritenum == crouchsprite) 
		{
			crouchspriteno = crouchsprite;
		}
		else if (!(actor->flags4 & MF4_NOSKIN) &&
				(spritenum == Skins[player->userinfo.GetSkin()].sprite ||
				 spritenum == Skins[player->userinfo.GetSkin()].crouchsprite))
		{
			crouchspriteno = Skins[player->userinfo.GetSkin()].crouchsprite;
		}
		else
		{ // no sprite -> squash the existing one
			crouchspriteno = -1;
		}

		if (crouchspriteno > 0) 
		{
			spritenum = crouchspriteno;
		}
		else if (player->playerstate != PST_DEAD && player->crouchfactor < 0.75)
		{
			scale.Y *= 0.5;
		}
	}
}

CUSTOM_CVAR (Float, sv_aircontrol, 0.00390625f, CVAR_SERVERINFO|CVAR_NOSAVE|CVAR_NOINITCALL)
{
	primaryLevel->aircontrol = self;
	primaryLevel->AirControlChanged ();
}

//==========================================================================
//
// P_FallingDamage
//
//==========================================================================

void P_FallingDamage (AActor *actor)
{
	int damagestyle;
	int damage;
	double vel;

	damagestyle = ((actor->Level->flags >> 15) | (dmflags)) &
		(DF_FORCE_FALLINGZD | DF_FORCE_FALLINGHX);

	if (damagestyle == 0)
		return;
		
	if (actor->floorsector->Flags & SECF_NOFALLINGDAMAGE)
		return;

	vel = fabs(actor->Vel.Z);

	// Since Hexen falling damage is stronger than ZDoom's, it takes
	// precedence. ZDoom falling damage may not be as strong, but it
	// gets felt sooner.

	switch (damagestyle)
	{
	case DF_FORCE_FALLINGHX:		// Hexen falling damage
		if (vel <= 23)
		{ // Not fast enough to hurt
			return;
		}
		if (vel >= 63)
		{ // automatic death
			damage = TELEFRAG_DAMAGE;
		}
		else
		{
			vel *= (16. / 23);
			damage = int((vel * vel) / 10 - 24);
			if (actor->Vel.Z > -39 && damage > actor->health
				&& actor->health != 1)
			{ // No-death threshold
				damage = actor->health-1;
			}
		}
		break;
	
	case DF_FORCE_FALLINGZD:		// ZDoom falling damage
		if (vel <= 19)
		{ // Not fast enough to hurt
			return;
		}
		if (vel >= 84)
		{ // automatic death
			damage = TELEFRAG_DAMAGE;
		}
		else
		{
			damage = int((vel*vel*(11 / 128.) - 30) / 2);
			if (damage < 1)
			{
				damage = 1;
			}
		}
		break;

	case DF_FORCE_FALLINGST:		// Strife falling damage
		if (vel <= 20)
		{ // Not fast enough to hurt
			return;
		}
		// The minimum amount of damage you take from falling in Strife
		// is 52. Ouch!
		damage = int(vel / (25000./65536.));
		break;

	default:
		return;
	}

	if (actor->player)
	{
		S_Sound (actor, CHAN_AUTO, CHANF_NONE, "*land", 1, ATTN_NORM);
		P_NoiseAlert (actor, actor, true);
		if (damage >= TELEFRAG_DAMAGE && ((actor->player->cheats & (CF_GODMODE | CF_BUDDHA) ||
			(actor->FindInventory(PClass::FindActor(NAME_PowerBuddha), true) != nullptr))))
		{
			damage = TELEFRAG_DAMAGE - 1;
		}
	}
	P_DamageMobj (actor, NULL, NULL, damage, NAME_Falling);
}

//----------------------------------------------------------------------------
//
// PROC P_CheckMusicChange
//
//----------------------------------------------------------------------------

void P_CheckMusicChange(player_t *player)
{
	// MUSINFO stuff
	if (player->MUSINFOtics >= 0 && player->MUSINFOactor != NULL)
	{
		if (--player->MUSINFOtics < 0)
		{
			if (player == player->mo->Level->GetConsolePlayer())
			{
				if (player->MUSINFOactor->args[0] != 0)
				{
					FName *music = player->MUSINFOactor->Level->info->MusicMap.CheckKey(player->MUSINFOactor->args[0]);

					if (music != NULL)
					{
						S_ChangeMusic(music->GetChars(), player->MUSINFOactor->args[1]);
					}
				}
				else
				{
					S_ChangeMusic("*");
				}
			}
			DPrintf(DMSG_NOTIFY, "MUSINFO change for player %d to %d\n", (int)player->mo->Level->PlayerNum(player), player->MUSINFOactor->args[0]);
		}
	}
}

DEFINE_ACTION_FUNCTION(APlayerPawn, CheckMusicChange)
{
	PARAM_SELF_PROLOGUE(AActor);
	P_CheckMusicChange(self->player);
	return 0;
}

//----------------------------------------------------------------------------
//
// PROC P_CheckEnviroment
//
//----------------------------------------------------------------------------

void P_CheckEnvironment(player_t *player)
{
	if (player->mo->Vel.Z <= -player->mo->FloatVar(NAME_FallingScreamMinSpeed) &&
		player->mo->Vel.Z >= -player->mo->FloatVar(NAME_FallingScreamMaxSpeed) && player->mo->alternative == nullptr &&
		player->mo->waterlevel == 0)
	{
		auto id = S_FindSkinnedSound(player->mo, S_FindSound("*falling"));
		if (id != NO_SOUND && !S_IsActorPlayingSomething(player->mo, CHAN_VOICE, id))
		{
			S_Sound(player->mo, CHAN_VOICE, CHANF_NONE, id, 1, ATTN_NORM);
		}
	}
}

DEFINE_ACTION_FUNCTION(APlayerPawn, CheckEnvironment)
{
	PARAM_SELF_PROLOGUE(AActor);
	P_CheckEnvironment(self->player);
	return 0;
}

//----------------------------------------------------------------------------
//
// PROC P_CheckUse
//
//----------------------------------------------------------------------------

void P_CheckUse(player_t *player)
{
	// check for use
	if (player->cmd.ucmd.buttons & BT_USE)
	{
		if (!player->usedown)
		{
			player->usedown = true;
			if (!P_TalkFacing(player->mo))
			{
				P_UseLines(player);
			}
		}
	}
	else
	{
		player->usedown = false;
	}
}


DEFINE_ACTION_FUNCTION(APlayerPawn, CheckUse)
{
	PARAM_SELF_PROLOGUE(AActor);
	P_CheckUse(self->player);
	return 0;
}

//----------------------------------------------------------------------------
//
// PROC P_PlayerThink
//
//----------------------------------------------------------------------------


// [XR grip arbiter] Per-hand grip ownership. File-scope (header stays enum-free; player_t fields are plain int).
// ZScript gets matching const values in actor.zs. PHYSICAL-controller-indexed everywhere. Declared HERE (before
// VR_CalculateTwoHanding, its first user) so the foregrip two-hand upgrade below can reference GRIP_TWOHAND.
enum EGripOwner { GRIP_NONE = 0, GRIP_CLIMB, GRIP_GLOVE, GRIP_WHIP, GRIP_HARDPOINT, GRIP_TWOHAND };

// [XR weapon handling] Defined in p_actionfunctions.cpp. Forward-declared HERE (its first user,
// VR_CalculateTwoHanding, is above the existing decl at ~line 1520) so this TU sees it before use.
bool VR_WeaponHotspotWorld(AActor* weapon, FName name, DVector3& out);

// [XR] Keyword-driven per-weapon two-hand style. Reads "grip:<style>" from the weapon's Keywords so MOD
// weapons inherit the behavior just by carrying the keyword; falls back to "class:<type>" (which our weapons
// and the archetype resolver already tag), then a rifle default. Fills capsule LENGTH (how far forward the
// off-hand can grab) + MODE (0 = foregrip capsule along the barrel, 1 = hilt / both-hands-on-grip for swords,
// 2 = none / not two-handable). This is the ONE place a weapon's two-hand feel is decided.
static void VR_GripStyleFromKeywords(const FString& kw, double& outLen, int& outMode)
{
    outLen = 30.0; outMode = 0;   // default: full-length foregrip (unkeyworded mod guns still two-hand)
    static const struct { const char* tag; double len; int mode; } ktab[] = {
        { "grip:none",   0.0,  2 },
        { "grip:pistol", 10.0, 0 },
        { "grip:smg",    18.0, 0 },
        { "grip:rifle",  30.0, 0 },
        { "grip:heavy",  34.0, 0 },   // chaingun / rocket / bfg
        { "grip:hilt",   12.0, 1 },   // sword: both hands on the hilt
    };
    for (auto& e : ktab) if (kw.IndexOf(e.tag) != -1) { outLen = e.len; outMode = e.mode; return; }
    // fallback: derive from the class:<type> tag our weapons + the archetype resolver already carry.
    if      (kw.IndexOf("class:pistol")   != -1) outLen = 10.0;
    else if (kw.IndexOf("class:revolver") != -1) outLen = 12.0;
    else if (kw.IndexOf("class:smg")      != -1) outLen = 18.0;
    // else: full-length rifle default (30).
}

void VR_CalculateTwoHanding(player_t* player)
{
    player->vr_two_hand_stabilized = false;
    if (player) player->vr_foregrip_engaged = false;   // clear busy-off-hand latch each tic; re-set below

    if (!vr_two_handed_weapons || !player || !player->ReadyWeapon)
        return;

    // [XR weapon handling] NEW native path: grip-gated engage at the authored hs_foregrip hotspot. Falls
    // through to the legacy capsule branch on ANY of: toggle off, no foregrip bone on this weapon (unconverted
    // MD3 -> VR_WeaponHotspotWorld returns false), or the arbiter not leaving the off-hand free -> toggle-off
    // and every not-yet-converted weapon reproduce today's behavior bit-for-bit.
    if (vr_new_weapon_handling)
    {
        DVector3 foregripWorld;
        if (VR_WeaponHotspotWorld(player->ReadyWeapon, NAME_hs_foregrip, foregripWorld)) // true only for a REAL authored bone
        {
            const int offPhys = VR_PhysicalHandForSlot(VR_OFFHAND);
            const VRMode* vrm = VRMode::GetVRModeCached(false);
            VSMatrix offHandM;
            if (vrm && vrm->GetWeaponTransform(&offHandM, VR_OFFHAND))
            {
                const float* om = offHandM.get();
                DVector3 offPos(om[12], om[14], om[13]);
                const double rr = vr_foregrip_radius;
                const bool nearForegrip = (offPos - foregripWorld).LengthSquared() <= (rr * rr);
                const bool gripHeld   = player->vr_grip_raw[offPhys];
                const int  curOwner   = player->vr_grip_owner[offPhys];
                const bool freeToGrab = (curOwner == GRIP_NONE) || (curOwner == GRIP_TWOHAND);
                if (nearForegrip && gripHeld && freeToGrab)
                {
                    player->vr_two_hand_stabilized = true;
                    player->vr_foregrip_engaged    = true;          // busy-off-hand swap + trigger-suspend read this
                    player->vr_grip_owner[offPhys] = GRIP_TWOHAND;  // publish ownership
                    player->vr_foregrip_world[0]   = (float)foregripWorld.X;
                    player->vr_foregrip_world[1]   = (float)foregripWorld.Y;
                    player->vr_foregrip_world[2]   = (float)foregripWorld.Z;
                    if (vr_twohand_glow_enable)
                    {
                        VR_PushWorldGlow(player->mo->Level, foregripWorld, PalEntry((int)vr_twohand_glow_color), vr_twohand_glow_radius);
                    }
                }
            }
            return;   // NEW path made the decision; do NOT also run the capsule test.
        }
        // else: no foregrip bone on this weapon -> fall through to legacy capsule (safe for unconverted guns).
    }

    // [XR] Per-weapon two-hand style from the weapon's Keywords (mod weapons inherit via the keyword).
    double length; int mode;
    VR_GripStyleFromKeywords(player->ReadyWeapon->Keywords, length, mode);
    if (mode == 2) return;   // grip:none -> not two-handable (fists, thrown, off-hand-only tools)

    // Whitelist gate + per-weapon perpendicular radius still come from the KEYWORDS.json profile.
    float ox = 0, oy = 0, oz = 0, radius = vr_twohand_radius;
    bool isWeapon = KeywordDispatcher::GetWeaponOffsets(player->ReadyWeapon->Keywords, ox, oy, oz, radius);
    if (vr_twohand_whitelist_only && !isWeapon)
        return;

    VSMatrix mainHand, offHand;
    if (!VRMode::GetVRModeCached(false)->GetWeaponTransform(&mainHand, VR_MAINHAND)) return;
    if (!VRMode::GetVRModeCached(false)->GetWeaponTransform(&offHand, VR_OFFHAND)) return;

    DVector3 p1(mainHand.get()[12], mainHand.get()[14], mainHand.get()[13]);   // main (weapon) hand pos
    DVector3 p2(offHand.get()[12], offHand.get()[14], offHand.get()[13]);      // off hand pos

    // [XR DETERMINISM] The off-hand must be GRIPPING, and the grip arbiter must leave it free (not owned by
    // climb / whip / glove / hardpoint). This is the "keyword-assigned deterministic" grip: one squeeze on
    // the barrel/hilt = two-hand, and it can't fight another system for the same hand. On engage it publishes
    // GRIP_TWOHAND so those systems yield. (The legacy proximity-only behavior is gone on purpose -- it was
    // non-deterministic, firing whenever the off-hand drifted near, even mid-grab.)
    const int  offPhys  = VR_PhysicalHandForSlot(VR_OFFHAND);
    const bool offGrip  = player->vr_grip_raw[offPhys];
    const int  offOwner = player->vr_grip_owner[offPhys];
    const bool offFree  = (offOwner == GRIP_NONE) || (offOwner == GRIP_TWOHAND);
    if (!offGrip || !offFree) return;

    bool engaged = false;
    DVector3 engagePoint = p1;
    if (mode == 1)
    {
        // HILT (sword): both hands ON the grip. Off-hand within `length` of the MAIN grip point (a sphere,
        // not a forward capsule) -- you clasp the hilt, you don't reach down a blade.
        engaged = ((p2 - p1).LengthSquared() <= (length * length));
        engagePoint = p1;
    }
    else
    {
        // FOREGRIP (guns): off-hand near the weapon's AXIS LINE, up to `length` forward from the grip.
        // A weapon is a long object, so engage on the barrel line (small perpendicular tolerance) anywhere
        // along the per-weapon length -- pistols cup short, SMGs reach mid, rifles/heavies reach full.
        const float* m = mainHand.get();
        DVector3 fwd(-m[8], -m[10], -m[9]);
        double fl = fwd.Length();
        if (fl > 1e-6) fwd /= fl; else fwd = DVector3(0, 0, 1);
        DVector3 d = p2 - p1;
        double t = d | fwd;
        if (t < 0.0) t = 0.0; else if (t > length) t = length;
        DVector3 closest = p1 + fwd * t;
        engaged = ((p2 - closest).LengthSquared() <= (radius * radius));
        engagePoint = closest;
    }

    if (engaged)
    {
        player->vr_two_hand_stabilized = true;
        player->vr_grip_owner[offPhys] = GRIP_TWOHAND;   // deterministic ownership publish
        if (vr_twohand_glow_enable)
        {
            VR_PushWorldGlow(player->mo->Level, engagePoint, PalEntry((int)vr_twohand_glow_color), vr_twohand_glow_radius);
        }
    }
}

bool VR_IsGripPressed(player_t* player, int hand)
{
    if (hand < 0 || hand > 1 || !player) return false;

    // [XR] Read raw hardware grip state, NOT the ucmd BT_VR_LGRIP/RGRIP bit. When
    // vr_secondary_button_mappings is on (default), the dominant hand's grip key is
    // intentionally suppressed at the input layer (used as a shift-modifier instead --
    // see vk_openxrdevice.cpp emitGameplayHandButtons / gl_openvr.cpp HandleInput_Default),
    // so ucmd.buttons never carries a real press for that hand. Climb/gloves/hardpoints/
    // the grip arbiter all need the true physical squeeze regardless of that UI feature;
    // VRMode::IsGripPressed reads the controller state directly on both backends and is
    // unaffected by the shift-layer suppression. BT_VR_LGRIP/RGRIP remain valid for the
    // separate rebindable-menu-action path (menudef grip bind), which still wants the
    // shift-layer behavior.
    // TODO(net): this is a local-only hardware read, not carried in the recorded ticcmd,
    // so gameplay grip state (climb/grab/gloves) is not demo-replay-safe or net-deterministic.
    // Same tradeoff already accepted for vr_grip_value (VR_ResolveGripOwner, above) -- flag
    // for whoever resumes VR ticcmd net-sanitization.
    const VRMode* vrm = VRMode::GetVRModeCached(false);
    return vrm && vrm->IsGripPressed(hand);
}


// [XR grip arbiter / fling fix] The whip publishes player->vr_whip_swing_live true every tic a live
// pendulum swing owns the pawn (GM_ATTACHED + AltFire held), false in EndGrapple. Native climb reads this
// and YIELDS its Vel write + gravity-flag management to the swing, so at most one system writes pawn Vel
// per tic (CHANGE 1 below). See d_player.h vr_whip_swing_live and vr_whip.zs UpdateGrapple/EndGrapple.
static inline bool P_VRWhipSwingActive(player_t* player)
{
    return player && player->vr_whip_swing_live;
}

// [XR grip arbiter] The single decision site. Runs once per tic in P_PlayerThink, BEFORE the grip
// consumers, and publishes exactly one owner per hand into player->vr_grip_owner[] (PHYSICAL-indexed).
//
// SCOPE (v1, deliberately conservative for build-safety without a headless compiler): the arbiter
// COMPUTES the verdict from state the consumers already maintain (vr_is_climbing / vr_grab_candidate /
// vr_held_items / vr_whip_rope_attached), and the ONLY consumer wired to obey it is the whip rope-pump
// (reads GRIP_WHIP via VR_GetGripOwner). Climb/gloves/hardpoints keep their existing grip reads, so this
// is behavior-neutral for them -- the verdict is available (loggable, and the whip acts on it) without the
// deep consumer surgery. Priority still follows the design: CLIMB > WHIP > GLOVE > HARDPOINT.
//
// Inputs are read at 1-tic latency by construction: climb runs AFTER this (later in P_PlayerThink),
// gloves' scan and the whip's rope-attached publish run in the actor-thinker pass AFTER P_PlayerThink.
// For the whip pump this is imperceptible (the rope stays attached for many tics); documented in the spec.
void VR_ResolveGripOwner(player_t* player)
{
    if (!player || !player->mo) return;
    if (!vr_grip_arbiter) return;   // master escape hatch: leave owners at GRIP_NONE, consumers use legacy paths
    const VRMode* vrm = VRMode::GetVRModeCached(false);

    for (int hand = 0; hand < 2; ++hand)
    {
        // STEP 0 -- fill the (previously dead) analog mirror, then the ONE canonical grip read.
        player->vr_grip_value[hand] = vrm ? vrm->GetGripValue(hand) : 0.f;
        const bool raw       = VR_IsGripPressed(player, hand);
        const int  prevOwner = player->vr_grip_owner[hand];
        int owner = GRIP_NONE;

        if (raw)
        {
            // STEP 1 -- analog commit gate (Schmitt trigger). arm<=0 => always committed = today's digital behavior.
            const float gv  = player->vr_grip_value[hand];
            const float arm = vr_grip_commit_arm, rel = vr_grip_commit_release;
            bool committed;
            if (arm <= 0.f)                           committed = true;
            else if (player->vr_grip_committed[hand]) committed = (gv > rel);   // stay claimed until below LOW rail
            else                                      committed = (gv >= arm);  // don't claim until HIGH rail
            player->vr_grip_committed[hand] = committed;

            if (committed)
            {
                // STEP 2 -- ONSET priority: CLIMB > WHIP > GLOVE > HARDPOINT. Reuses consumer-maintained
                // state so no divergent geometry query. (Continuation is implicit: these flags persist
                // across tics while the interaction is live.)
                if (player->vr_is_climbing[hand])                 owner = GRIP_CLIMB;        // climb latched last tic
                else if (player->vr_whip_rope_attached[hand])     owner = GRIP_WHIP;         // rope on this hand (pump reads this)
                else if (player->vr_held_items[hand]
                      || player->vr_grab_candidate[hand] != nullptr
                      || player->vr_grab_is_locked[hand]
                      || player->vr_grab_is_pulling[hand])        owner = GRIP_GLOVE;
                // HARDPOINT/TWOHAND left to their own edge/proximity paths in v1 (not consumed here).
            }
        }
        else
        {
            player->vr_grip_committed[hand] = false;
        }

        player->vr_grip_owner_prev[hand] = prevOwner;
        player->vr_grip_owner[hand]      = owner;
        player->vr_grip_raw_prev[hand]   = player->vr_grip_raw[hand];
        player->vr_grip_raw[hand]        = raw;
    }
}

void VR_UpdateClimbing(player_t* player);
void VR_UpdateGravityGloves(player_t* player);
void VR_UpdateHandCollision(player_t* player); // [XR] hand-vs-wall proximity + growing touch glow
void VR_UpdateHardpointGlow(player_t* player); // [XR] hardpoint draw/stow proximity glow
void VR_UpdateHardpoints(player_t* player);   // proximity+grip draw/holster, native hardpoint mounts
void VR_UpdateWeaponReload(player_t* player); // [XR] native box-mag manual-reload FSM (gated vr_new_weapon_handling)
void VR_UpdateWeaponAnim(player_t* player);   // [XR] procedural weapon recoil -> weapon IQM hs_grip bone (gated vr_weapon_recoil)
void VR_UpdateArmIK(player_t* player);        // two-bone IK -> player->vr_ik_pose
// [XR weapon handling] name -> bind-LOCAL hotspot pos (p_actionfunctions.cpp; confines FModel to that file).
bool VR_WeaponBoneBindLocal(AActor* weapon, FName boneName, FVector3& out);
// [XR weapon handling] canonical hotspot WORLD-pos primitive (defined below): false if no authored bone.
bool VR_WeaponHotspotWorld(AActor* weapon, FName name, DVector3& out);
FModel* VR_EnsureAvatarModelDataAndGetModel(AActor* mo);   // p_actionfunctions.cpp: gives the pawn a modelData (pose target) + returns its rigged model
FModel* VR_EnsureWeaponModelDataAndGetModel(AActor* weapon); // p_actionfunctions.cpp: same, for a HELD weapon actor (pose target for recoil)

void P_PlayerThink (player_t *player)
{
	ticcmd_t *cmd = &player->cmd;

	if (VRMode::GetVRModeCached(false))
	{
		VR_UpdateRecoil(player);
	}

	if (player->mo == NULL)
	{
		I_Error ("No player %td start\n", player - players + 1);
	}

    static int previous_health = 0;

    if (previous_health != player->health)
    {
        if (player->health > previous_health)
        {
            VR_HapticEvent("healstation", 0, 100 * C_GetExternalHapticLevelValue("healstation"), 0, 0);
        }
    }
    else if (player->health > 0 && player->health <= 25)
    {
        //heartbeat is a special case that uses intensity for a different purpose
        VR_HapticEvent("heartbeat", 0, player->health * C_GetExternalHapticLevelValue("heartbeat"), 0, 0);
    }

	for (unsigned int i = 0u; i < 3u; ++i)
	{
		if (fabs(player->angleOffsetTargets[i].Degrees()) >= EQUAL_EPSILON)
		{
			player->mo->Angles[i] += player->angleOffsetTargets[i];
			player->mo->PrevAngles[i] = player->mo->Angles[i];
		}

		player->angleOffsetTargets[i] = nullAngle;
	}

	if (player->SubtitleCounter > 0)
	{
		player->SubtitleCounter--;
	}

	if (player->playerstate == PST_LIVE
		&& player->mo->Z() <= player->mo->floorz
		&& !player->mo->Sector->IsDangerous(player->mo->Pos(), player->mo->Height))
	{
		player->LastSafePos = player->mo->Pos();
	}

	// Bots do not think in freeze mode.
	if (player->mo->Level->isFrozen() && player->Bot != nullptr)
	{
		return;
	}

	if (debugfile && !(player->cheats & CF_PREDICTING))
	{
		fprintf (debugfile, "tic %d for pl %d: (%f, %f, %f, %f) b:%02x p:%d y:%d f:%d s:%d u:%d\n",
			gametic, (int)(player-players), player->mo->X(), player->mo->Y(), player->mo->Z(),
			player->mo->Angles.Yaw.Degrees(), player->cmd.ucmd.buttons,
			player->cmd.ucmd.pitch, player->cmd.ucmd.yaw, player->cmd.ucmd.forwardmove,
			player->cmd.ucmd.sidemove, player->cmd.ucmd.upmove);
	}

	// Make unmodified copies for ACS's GetPlayerInput.
	player->original_oldbuttons = player->original_cmd.buttons;
	player->original_cmd = cmd->ucmd;
	// Don't interpolate the view for more than one tic
	player->cheats &= ~CF_INTERPVIEW;
	player->cheats &= ~CF_INTERPVIEWANGLES;
	player->cheats &= ~CF_SCALEDNOLERP;
	player->cheats &= ~CF_NOFOVINTERP;
	player->cheats &= ~CF_NOVIEWPOSINTERP;
	player->mo->FloatVar("prevBob") = player->bob;


	IFVIRTUALPTRNAME(player->mo, NAME_PlayerPawn, PlayerThink)
	{
		VMValue param = player->mo;
		VMCall(func, &param, 1, nullptr, 0);
	}

    previous_health = player->health;

    // Grip Priority: Climb > Gravity Gloves > Two-Handing > Hardpoints ; IK is pose-only, last
    VR_ResolveGripOwner(player);   // [XR grip arbiter] publish vr_grip_owner[] before any consumer runs
    VR_UpdateClimbing(player);
    VR_UpdateGravityGloves(player);
    VR_UpdateHandCollision(player); // [XR] hand-vs-wall proximity + growing touch glow (independent of grip)
    VR_UpdateHardpointGlow(player); // [XR] hardpoint draw/stow proximity glow
    VR_CalculateTwoHanding(player);
    VR_UpdateHardpoints(player);
    VR_UpdateWeaponReload(player);   // [XR] native box-mag FSM (no-op unless vr_new_weapon_handling)
    VR_UpdateWeaponAnim(player);     // [XR] procedural weapon recoil on the held IQM (no-op unless vr_weapon_recoil)
    VR_UpdateArmIK(player);

    // [XR] Decoupled body-avatar facing: hold the rendered body yaw steady while the head looks around
    // within a dead-zone, then let it catch up once the head turns past it. Fixes "body spins with my
    // head / no neck". Pawn Angles.Yaw is untouched (still HMD-slaved for gameplay + arm-IK targets);
    // only the body MODEL render reads vr_body_facing_yaw (models.cpp RenderModel, isVRBody).
    {
        const double headYaw = player->mo->Angles.Yaw.Degrees();
        if (!player->vr_body_facing_valid)
        {
            player->vr_body_facing_yaw = (float)headYaw;
            player->vr_body_facing_valid = true;
        }
        else
        {
            double diff = headYaw - (double)player->vr_body_facing_yaw;
            while (diff >  180.0) diff -= 360.0;
            while (diff < -180.0) diff += 360.0;
            const double deadzone = 50.0;   // deg the head can turn before the body starts to follow
            if (diff >  deadzone) player->vr_body_facing_yaw = (float)(headYaw - deadzone);
            else if (diff < -deadzone) player->vr_body_facing_yaw = (float)(headYaw + deadzone);
        }
    }

    for (int hand = 0; hand < 2; hand++)
    {
        if (player->vr_is_climbing[hand])
            player->vr_hand_state[hand] = 2; // Climb
        else if (player->vr_held_items[hand] || player->vr_grab_is_locked[hand] || player->vr_grab_is_pulling[hand])
            player->vr_hand_state[hand] = 1; // Grip
        else if (player->vr_two_hand_stabilized && hand == VR_OFFHAND)
            player->vr_hand_state[hand] = 1; // Grip (supporting weapon)
        else
            player->vr_hand_state[hand] = 0; // Idle
    }
}

EXTERN_CVAR(Float, vr_grab_cone_angle)
EXTERN_CVAR(Float, vr_grab_max_dist)
EXTERN_CVAR(Float, vr_grab_magnet_speed)

EXTERN_CVAR(Bool, vr_grab_debug_cone)
EXTERN_CVAR(Bool, vr_grab_debug_sphere)

void VR_UpdateClimbing(player_t* player);
void VR_UpdateGravityGloves(player_t* player);

// ---------------------------------------------------------------------------
// VR_EquipToHand -- native equip seam (canonical weapon-hand ruleset, Rule 1.3 /
// 3.1 / toss-backfill spine). The native layer OWNS the equip DECISION and the
// per-hand routing; the weapon-raise animation itself stays in the ZScript weapon
// state machine (MoveWeaponToHand -> BringUpWeapon / A_Raise), which is correctly
// the actor's business, not something to re-implement in C++.
//
// For a SINGLE weapon instance this delegates to the hand-aware ZScript
// MoveWeaponToHand (same proven native->ZScript seam the weapon wheel uses). The
// akimbo case (Rule 2.2 -- two instances of one class, one per hand) will branch
// here later to bypass MoveWeaponToHand's same-class collapse; keeping ONE native
// entry point means callers (grab, catch, backfill) never touch the ZScript
// helpers directly.
void VR_EquipToHand(player_t* player, AActor* weapon, int hand)
{
	if (player == nullptr || player->mo == nullptr || weapon == nullptr) return;
	if (hand != 0 && hand != 1) hand = 0;

	IFVIRTUALPTRNAME(player->mo, NAME_PlayerPawn, MoveWeaponToHand)
	{
		VMValue param[] = { player->mo, weapon, hand };
		VMCall(func, param, 3, nullptr, 0);
	}
}

void VR_UpdateGravityGloves(player_t* player)
{
	if (!player || !player->mo || !VRMode::GetVRModeCached(false)) return;
	if (vr_grab_max_dist <= 0) return;

	for (int hand = 0; hand < 2; hand++)
	{
		bool isGripPressed = VR_IsGripPressed(player, hand);

		if (player->vr_is_climbing[hand])
		{
		    isGripPressed = false; // Override grip if climbing
		}
		if (player->vr_whip_rope_attached[hand])
		{
		    // [XR grip priority] CLIMB > WHIP > GLOVE: a live rope on this hand already owns the
		    // squeeze (whip pump reads it via the arbiter). Without this, gloves would run its
		    // candidate-search/grab-lock logic on the same hand at the same time -- this function
		    // already treats whip-attached as exclusive for the Rule-5 fling-throw check below
		    // (freeGrip), so apply the same exclusion up here where the grip is first read.
		    isGripPressed = false;
		}
		bool wasGripPressed = player->vr_was_grip_pressed[hand];
		player->vr_was_grip_pressed[hand] = isGripPressed;

		// `hand` here is a PHYSICAL controller index (0=left,1=right). Weapon slots
		// (ReadyWeapon=main / OffhandWeapon=off) are a SEPARATE concept that maps to a
		// physical hand via the control scheme -- so convert before touching weapons.
		// Canonical mapping mirrors VR_UpdateClimbing (this file).
		const int weapSlot = (hand == VR_PhysicalHandForSlot(VR_OFFHAND)) ? VR_OFFHAND : VR_MAINHAND;

		VSMatrix handTransform;
		if (!VRMode::GetVRModeCached(false)->GetWeaponTransform(&handTransform, hand)) continue;

		const float* m = handTransform.get();
		DVector3 handPos(m[12], m[14], m[13]);
		DVector3 handForward(-m[8], -m[10], -m[9]);
		handForward.MakeUnit();

		DVector3 rawVelocity;
		VRMode::GetVRModeCached(false)->GetHandVelocity(hand, rawVelocity);
		
		// Velocity Smoothing (Rolling Average)
		player->vr_hand_vel_buffer[hand][player->vr_hand_vel_index[hand] % 4] = rawVelocity;
		player->vr_hand_vel_index[hand]++;
		
		DVector3 handVelocity(0, 0, 0);
		for (int i = 0; i < 4; i++) handVelocity += player->vr_hand_vel_buffer[hand][i];
		handVelocity /= 4.0;
		
		AActor* heldItem = player->vr_held_items[hand];

		if (!isGripPressed)
		{
			if (heldItem)
			{
				bool isThrowable = false;
				if (heldItem->flags & MF_MISSILE) isThrowable = true; // Projectiles are always throwable
				else if (KeywordDispatcher::IsThrowable(heldItem->Keywords)) isThrowable = true;

				if (isThrowable)
				{
					// Throw Logic (Using Smoothed Velocity)
					double itemMass = heldItem->Mass > 0 ? heldItem->Mass : 100.0;
					// "Easier Grabbing" gameplay toggle: scales EFFECTIVE mass (throw force only,
					// not the actor's real Mass/collision physics) for flags:grabprop props. Was a
					// hardcoded 0.5; now vr_easy_grab_scale so it's user-tunable (default unchanged).
					if (vr_easy_grab_props && heldItem->Keywords.IndexOf("flags:grabprop") != -1)
						itemMass *= vr_easy_grab_scale;
					double massScale = 100.0 / itemMass;
					double throwForce = vr_throw_force * massScale;
					
					heldItem->Vel = handVelocity * (vr_scale_meters_to_units / 35.0) * throwForce;
				}
				else
				{
					// Drop item straight down
					heldItem->Vel.Zero();
				}
				
				heldItem->flags &= ~MF_NOGRAVITY;
				heldItem->flags &= ~MF_NOBLOCKMAP;
				player->vr_held_items[hand] = nullptr;
			}
			else if (wasGripPressed && vr_throw_equip)
			{
				// Rule 5: throw your EQUIPPED weapon. A grip-fling-release on this hand,
				// when nothing else claimed the grip (not climb / whip / grab), flings the
				// live gun into the world as a catchable, re-grabbable pickup. This sits at
				// the BOTTOM of the grip priority chain by construction -- it only fires when
				// the grip owned nothing else, so it can never steal a climb or a catch.
				// Also exclude a hand that is BRACING a two-handed weapon: two-hand stabilize
				// is proximity-driven (no grip of its own), so a grip-fling to un-brace must
				// not toss that hand's own weapon. Only the off-hand ever braces.
				const bool bracingHand = player->vr_two_hand_stabilized && (hand == VR_PhysicalHandForSlot(VR_OFFHAND));
				const bool freeGrip =
					!player->vr_is_climbing[hand] &&
					!player->vr_whip_rope_attached[hand] &&
					player->vr_grab_candidate[hand] == nullptr &&
					!player->vr_grab_is_locked[hand] &&
					!player->vr_grab_is_pulling[hand] &&
					!bracingHand;

				if (freeGrip && handVelocity.Length() > vr_throw_equip_min_speed)
				{
					// Select and throw the weapon in the SLOT this physical hand controls.
					AActor* equipped = (weapSlot == VR_OFFHAND) ? player->OffhandWeapon : player->ReadyWeapon;
					if (equipped != nullptr)
					{
						// Native owns the trigger + slot routing + velocity source; the ZScript
						// helper does the un-equip / world-spawn surgery (inventory + PSprite),
						// which is correctly the weapon actor's business.
						const DVector3 throwVel = handVelocity * (vr_scale_meters_to_units / 35.0) * vr_throw_force;
						IFVIRTUALPTRNAME(player->mo, NAME_PlayerPawn, VR_ThrowEquippedWeapon)
						{
							VMValue param[] = { player->mo, weapSlot, throwVel.X, throwVel.Y, throwVel.Z };
							VMCall(func, param, 5, nullptr, 0);
						}
					}
				}
			}

			if (wasGripPressed)
			{
				// We just released grip. Trigger flick or cancel lock.
				if (player->vr_grab_is_locked[hand] && !player->vr_grab_is_pulling[hand] && player->vr_grab_candidate[hand])
				{
					// Check flick velocity
					double flickSpeed = handVelocity.Length();
					if (flickSpeed > 10.0) // vr_grab_flick_threshold
					{
						player->vr_grab_is_pulling[hand] = true;
						player->vr_grab_is_waiting_catch[hand] = true;
					}
					else
					{
						player->vr_grab_is_locked[hand] = false;
						player->vr_grab_candidate[hand] = nullptr;
					}
				}
				else if (player->vr_grab_is_waiting_catch[hand])
				{
					// missed catch
					player->vr_grab_is_locked[hand] = false;
					player->vr_grab_is_pulling[hand] = false;
					player->vr_grab_is_waiting_catch[hand] = false;
					player->vr_grab_candidate[hand] = nullptr;
				}
				
				// Reset all grab states if grip is released and no pull triggered
				if (!player->vr_grab_is_pulling[hand])
				{
					player->vr_grab_is_locked[hand] = false;
					player->vr_grab_candidate[hand] = nullptr;
				}
			}

			// Search for candidate
			if (!player->vr_grab_is_locked[hand] && !player->vr_grab_is_pulling[hand])
			{
				AActor* bestItem = nullptr;
				double bestScore = -1.0;

				FBoundingBox box(handPos.X, handPos.Y, vr_grab_max_dist);
				FBlockThingsIterator it(player->mo->Level, box);
				AActor* mo;
				while ((mo = it.Next()))
				{
					if (mo == player->mo) continue;
					// "flags:grabprop" is a dedicated, narrowly-scoped opt-in for actors that are
					// neither a pickup (MF_SPECIAL) nor a projectile (MF_MISSILE) but should still be
					// VR-grabbable -- e.g. ExplosiveBarrel (+SOLID +SHOOTABLE, no pickup semantics).
					// Deliberately NOT the bare "grab" token: that one is tagged on nearly every
					// actor in the game (every monster included, always paired with "mass:N") as a
					// general mass-namespace marker, not a "this is VR-grabbable" flag -- reusing it
					// here would have made every monster in the game grabbable/throwable. Same
					// Keywords.IndexOf idiom already used for "fist" (models.cpp).
					bool keywordGrabbable = mo->Keywords.IndexOf("flags:grabprop") != -1;
					if (!(mo->flags & MF_SPECIAL) && !(mo->flags & MF_MISSILE) && !keywordGrabbable) continue;
					if (mo->Distance3D(player->mo) > vr_grab_max_dist) continue;

					DVector3 toItem = mo->Pos() - handPos;
					double distSq = toItem.LengthSquared();
					toItem.MakeUnit();

					double dot = toItem | handForward;
					double coneThreshold = cos(vr_grab_cone_angle * M_PI / 360.0);

					if (dot > coneThreshold)
					{
						// [XR bugfix] vr_grab_weight_dist/align/mass back the VRGrabOptions "Distance/
						// Alignment/Mass Penalty Weight" sliders, which existed with NO real cvar behind
						// them anywhere (dead UI, not just unread). Defaults (dist=1, align=1, mass=0)
						// collapse this to the EXACT old formula (`dot * (1-normDist)`, no mass term) --
						// this only changes behavior once a player actually moves a slider.
						double normDist = sqrt(distSq) / vr_grab_max_dist;
						double alignFactor = 1.0 + (dot - 1.0) * vr_grab_weight_align;
						double distFactor  = 1.0 + ((1.0 - normDist) - 1.0) * vr_grab_weight_dist;
						double itemMass    = mo->Mass > 0 ? mo->Mass : 100.0;
						double massPenalty = 1.0 - vr_grab_weight_mass * clamp<double>(itemMass / 1000.0, 0.0, 1.0);
						double score = alignFactor * distFactor * massPenalty;
						if (score > bestScore)
						{
							bestScore = score;
							bestItem = mo;
						}
					}
				}
				AActor* prevCandidate = player->vr_grab_candidate[hand];
				if (prevCandidate != bestItem)
				{
					if (prevCandidate) prevCandidate->bForceShowVoxel = false;
					if (bestItem) bestItem->bForceShowVoxel = true;
				}
				player->vr_grab_candidate[hand] = bestItem;

				// [XR] bForceShowVoxel above only helps on voxel-model actors; a generic glow at the
				// candidate works regardless of model type, telling the player what they're about to
				// grab before they squeeze.
				if (vr_grab_highlight_enable && bestItem)
				{
					VR_PushWorldGlow(player->mo->Level, bestItem->Pos(), PalEntry((int)vr_grab_highlight_color), vr_grab_highlight_radius);
				}

				// [XR] The grab-cone / grab-sphere / target-pulse debug visualisation used to be
				// drawn here with P_SpawnParticle -- which does NOT reach the VR stereo render, so
				// it was invisible in-headset. It is fully superseded by the ONE working system:
				// the render-thread wireframe+solid geometry in hw_weapon.cpp (DrawXRDebugCones,
				// gated by the same vr_grab_debug / vr_grab_debug_cone / vr_grab_debug_sphere cvars),
				// which renders real tube/quad geometry visible in VR. The redundant particle version
				// was removed so there is a single debug path. (The throw-trajectory ARC below is a
				// separate feature and is intentionally kept.)
			}
			continue;
		}

		// Grip IS pressed
		if (heldItem)
		{
			DVector3 diff = handPos - heldItem->Pos();
			double dist = diff.Length();
			
			// Line of sight check to prevent geometry clipping
			if (!P_CheckSight(player->mo, heldItem, SF_IGNOREVISIBILITY))
			{
				// Item clipped behind a wall, drop it
				player->vr_held_items[hand] = nullptr;
				heldItem->flags &= ~MF_NOGRAVITY;
				heldItem->flags &= ~MF_NOBLOCKMAP;
				continue;
			}

			// Render Trajectory Arc
			bool isThrowable = false;
			if (heldItem->flags & MF_MISSILE) isThrowable = true; // Snatched projectiles are throwable
			else if (KeywordDispatcher::IsThrowable(heldItem->Keywords)) isThrowable = true;

			if (vr_throw_arc_glow_enable && (vr_grab_debug || isThrowable))
			{
				double itemMass = heldItem->Mass > 0 ? heldItem->Mass : 100.0;
				// Match the real throw's "Easier Grabbing" mass scale so this preview arc lines
				// up with where the item will actually go.
				if (vr_easy_grab_props && heldItem->Keywords.IndexOf("flags:grabprop") != -1)
					itemMass *= vr_easy_grab_scale;
				double massScale = 100.0 / itemMass;
				double velocityScale = (vr_scale_meters_to_units / 35.0) * vr_throw_force * massScale;
				DVector3 tVel = handVelocity * velocityScale;
				DVector3 tPos = handPos;
				const PalEntry arcColor((int)vr_throw_arc_glow_color);

				// [XR bugfix] This preview used to draw with P_SpawnParticle, which does NOT reach
				// the VR stereo render (see dxr-particles-invisible-in-vr) -- invisible in headset.
				// Glow spots are the visible equivalent; strided (every 4th step, ~10 spots) since
				// GlowSpots is uncapped but a spot every one of 40 steps/tic per held item is wasteful.
				for (int step = 0; step < 40; ++step)
				{
					DVector3 nextPos = tPos + tVel;

					// Simple wall/floor collision for the arc
					FTraceResults res;
					DVector3 dir = tVel;
					double dist = dir.Length();
					dir.MakeUnit();

					if (Trace(tPos, player->mo->Level->PointInSector(tPos.XY()), dir, dist, 0, ML_BLOCKING, player->mo, res, TRACE_HitSky))
					{
						VR_PushWorldGlow(player->mo->Level, res.HitPos, arcColor, vr_throw_arc_glow_radius * 1.5);
						break;
					}

					tVel.Z -= (player->mo->Level->gravity * heldItem->Gravity);
					tPos = nextPos;

					if ((step % 4) == 0)
						VR_PushWorldGlow(player->mo->Level, tPos, arcColor, vr_throw_arc_glow_radius);
				}
			}

			if (dist > 12.0) 
			{
				diff.MakeUnit();
				heldItem->Vel = diff * vr_grab_magnet_speed;
			}
			else
			{
				heldItem->SetXYZ(handPos);
				heldItem->Vel.Zero();
				heldItem->flags |= (MF_NOGRAVITY | MF_NOBLOCKMAP);
				
				if (vr_autoequip && (heldItem->flags & MF_SPECIAL))
				{
					// Rule 1.3: a grabbed WEAPON must equip to the GRABBING hand, not
					// vanilla's hand-blind main-hand give. Capture the class BEFORE the
					// give (P_TouchSpecialThing may euthanize the world actor), then route
					// the now-owned instance to this hand via the native equip seam. A
					// non-weapon pickup (health/ammo/armor) keeps the plain auto-apply.
					const bool wasWeapon = heldItem->IsKindOf(NAME_Weapon);
					PClassActor* const weapClass = wasWeapon ? static_cast<PClassActor*>(heldItem->GetClass()) : nullptr;
					// Only a NEWLY-acquired weapon routes to the grabbing hand. Grabbing a
					// duplicate of a weapon you already own grants ammo only (vanilla) and
					// must NOT hand-swap/weapon-switch your existing instance -- so gate the
					// equip on ownership captured BEFORE the give.
					const bool alreadyOwned = (weapClass != nullptr) && (player->mo->FindInventory(weapClass) != nullptr);

					P_TouchSpecialThing(heldItem, player->mo);
					player->vr_held_items[hand] = nullptr;

					if (wasWeapon && weapClass != nullptr && !alreadyOwned)
					{
						// The give routes hand-blind (main hand); move the owned instance
						// to the WEAPON SLOT of the hand that actually grabbed it.
						AActor* owned = player->mo->FindInventory(weapClass);
						if (owned != nullptr)
						{
							VR_EquipToHand(player, owned, weapSlot);
						}
					}

					if (heldItem->ObjectFlags & OF_EuthanizeMe) continue;
					heldItem->flags &= ~(MF_NOGRAVITY | MF_NOBLOCKMAP);
				}
			}
		}
		else
		{
			// Grip pressed, not holding item.
			if (!wasGripPressed)
			{
				if (player->vr_grab_is_waiting_catch[hand] && player->vr_grab_candidate[hand])
				{
					// Catch!
					AActor* target = player->vr_grab_candidate[hand];
					if (target->Distance3D(player->mo) < 64.0) // catch radius
					{
						// Rule 3.1: catching a WEAPON pickup into this (empty) hand equips
						// it to the catching hand and makes it fireable, rather than leaving
						// it a dumb held prop. Same give-then-route pattern as the magnet
						// grab (Rule 1.3); capture class before the give may euthanize the
						// world actor. Non-weapon catches (props/missiles) stay held props.
						const bool caughtWeapon = (target->flags & MF_SPECIAL) && target->IsKindOf(NAME_Weapon);
						if (caughtWeapon)
						{
							PClassActor* const weapClass = static_cast<PClassActor*>(target->GetClass());
							// As Rule 1.3: only a NEWLY-acquired weapon equips to the catching
							// hand; a duplicate you already own grants ammo only, no hand-swap.
							const bool alreadyOwned = (weapClass != nullptr) && (player->mo->FindInventory(weapClass) != nullptr);
							P_TouchSpecialThing(target, player->mo);
							if (weapClass != nullptr && !alreadyOwned)
							{
								AActor* owned = player->mo->FindInventory(weapClass);
								if (owned != nullptr) VR_EquipToHand(player, owned, weapSlot);
							}
						}
						else
						{
							player->vr_held_items[hand] = target;
							// Whoever's now holding this is responsible for what it does next (kill
							// credit if it later explodes/detonates) -- same convention already used
							// for the bullet-snatch case below (cand->target = player->mo).
							target->target = player->mo;
						}
						player->vr_grab_is_locked[hand] = false;
						player->vr_grab_is_pulling[hand] = false;
						player->vr_grab_is_waiting_catch[hand] = false;
						player->vr_grab_candidate[hand] = nullptr;
					}
				}
				else if (player->vr_grab_candidate[hand])
				{
					AActor* cand = player->vr_grab_candidate[hand];
					double distToHand = (cand->Pos() - handPos).Length();

					if (vr_allow_bullet_snatching && (cand->flags & MF_MISSILE) && distToHand < vr_catch_radius)
					{
						// Snatch!
						player->vr_held_items[hand] = cand;
						cand->Vel.Zero();
						cand->flags |= MF_NOGRAVITY;
						cand->target = player->mo;
						
						if (vr_catch_haptic)
						{
							VR_HapticEvent("snatch", hand == 0 ? 1 : 2, 100, 0, 0);
						}
						
						if (vr_catch_spark)
						{
							// [XR bugfix] This was a P_SpawnParticle burst, which does NOT reach the VR
							// stereo render (see dxr-particles-invisible-in-vr) -- invisible in headset.
							// A single glow spot at the catch point is the visible equivalent.
							VR_PushWorldGlow(player->mo->Level, cand->Pos(), PalEntry((int)vr_catch_glow_color), vr_catch_glow_radius);
						}
					}
					else if ((cand->Pos() - handPos).Length() < 48.0)
					{
						// [XR] DIRECT GRAB: a candidate already within hand reach grabs on the squeeze
						// itself -- no flick-and-catch cycle. This is the intuitive "reach out and take it".
						// The flick-pull (Initial Lock below) still handles DISTANT items you can't touch.
						// Fixes the long-standing "squeeze does nothing" on things right in front of you:
						// the old path only ever locked a bool silently and required a wrist flick to pull.
						player->vr_held_items[hand] = cand;
						cand->Vel.Zero();
						cand->flags |= (MF_NOGRAVITY | MF_NOBLOCKMAP);
						cand->target = player->mo;
						cand->bForceShowVoxel = false;
						player->vr_grab_candidate[hand] = nullptr;
						player->vr_grab_is_locked[hand] = false;
						if (vr_catch_haptic)
							VR_HapticEvent("snatch", hand == 0 ? 1 : 2, 100, 0, 0);
					}
					else
					{
						// Initial Lock (distant item -> flick your hand to pull it in)
						player->vr_grab_is_locked[hand] = true;
					}
				}
			}

			if (player->vr_grab_is_pulling[hand] && player->vr_grab_candidate[hand])
			{
				AActor* target = player->vr_grab_candidate[hand];
				DVector3 diff = handPos - target->Pos();
				diff.MakeUnit();
				target->Vel = diff * vr_grab_magnet_speed;
			}
			
			/* Bullet Snatching logic (Swept Volume) - Tabled for now
			if (!heldItem)
			{
				DVector3 handA = player->vr_prev_hand_pos[hand];
				DVector3 handB = handPos;
				DVector3 handDir = handB - handA;
				double handMoveDistSq = handDir.LengthSquared();
				
				FBoundingBox box;
				box.AddToBox(DVector2(handA.X, handA.Y));
				box.AddToBox(DVector2(handB.X, handB.Y));
				// Expand 12.0 ... manually for now since Expand is missing
				
				FBlockThingsIterator it(player->mo->Level, box);
				AActor* mo;
				while ((mo = it.Next()))
				{
					if ((mo->flags & MF_MISSILE))
					{
						DVector3 p = mo->Pos();
						double distSq;
						if (handMoveDistSq < 0.01) {
							distSq = (p - handB).LengthSquared();
						} else {
							DVector3 AP = p - handA;
							double t = clamp((AP | handDir) / handMoveDistSq, 0.0, 1.0);
							DVector3 closest = handA + handDir * t;
							distSq = (p - closest).LengthSquared();
						}

						if (distSq < 144.0) // 12.0 squared
						{
							// Snatched!
							if (isGripPressed)
							{
								player->vr_held_items[hand] = mo;
								mo->Vel.Zero();
								mo->flags |= (MF_NOGRAVITY | MF_NOBLOCKMAP);
								mo->target = player->mo; 
								VR_HapticEvent("snatch", hand, 100, 0, 0);
							}
							else
							{
								// Deflect!
								mo->Vel = -mo->Vel;
								mo->target = player->mo;
								VR_HapticEvent("deflect", hand, 50, 0, 0);
							}
							break;
						}
					}
				}
			}
			*/
			player->vr_prev_hand_pos[hand] = handPos;
		}
	}
}

EXTERN_CVAR(Float, vr_hardpoint_radius)
EXTERN_CVAR(Bool,  vr_hardpoint_enable)

//----------------------------------------------------------------------------
//
// VR_InitHardpoints
//
// Copies the FVRConfig default hardpoint table into this player's runtime slots.
// Called once at pawn spawn. Idempotent.
// FHardpointSlot (config) -> VRHardpointRuntime (per-player) copy.
//
//----------------------------------------------------------------------------

void VR_InitHardpoints(player_t* player)
{
	if (!player) return;

	player->vr_hardpoint_count = 0;
	for (int i = 0; i < VR_MAX_HARDPOINTS; i++)
	{
		player->vr_hardpoints[i] = player_t::VRHardpointRuntime(); // reset (occupied=false, enabled=false, stowedWeapon=null)
	}

	// Seed from the config default table (FVRConfig::Hardpoints, a static
	// TArray<FHardpointSlot> populated by vr_config.cpp LoadConfig).
	const TArray<FHardpointSlot>& defs = FVRConfig::Hardpoints;
	unsigned n = defs.Size();
	if (n > (unsigned)VR_MAX_HARDPOINTS) n = (unsigned)VR_MAX_HARDPOINTS;

	for (unsigned i = 0; i < n; i++)
	{
		const FHardpointSlot& d = defs[i];
		if (!d.enabled) continue;

		player_t::VRHardpointRuntime& r = player->vr_hardpoints[player->vr_hardpoint_count];
		r.anchor       = d.anchor;
		r.action       = d.action;
		r.hand         = d.hand;
		r.ox           = d.ox;
		r.oy           = d.oy;
		r.oz           = d.oz;
		r.radius       = d.radius;
		r.cells        = max(1, d.cells);
		r.occupied     = false;
		r.enabled      = true;
		r.stowedWeapon = nullptr;
		player->vr_hardpoint_count++;
	}
}

//----------------------------------------------------------------------------
//
// VR_UpdateHardpoints
//
// Per-tic proximity + grip-edge draw/holster for the N configured slots.
// STRUCTURAL TEMPLATE: VR_UpdateGravityGloves (above). Differences:
//  - Slots are ANCHOR-relative (body: AttackPos + yaw-rotated offset; wrist:
//    OTHER hand's GetWeaponTransform * local offset) -> NO blockmap iterator,
//    just a distance-squared test against each slot's world pos.
//  - OWN grip latch (player->vr_hardpoint_was_grip[hand]) so it never fights the
//    gloves' player->vr_was_grip_pressed[hand].
//  - LOCAL-PLAYER-ONLY GATE: (player - players) != consoleplayer bails immediately
//    (same pointer-arithmetic idiom already used at this file's line ~1358).
//    GetWeaponTransform reads the single local OpenXR device with no player param,
//    while PendingWeapon/ReadyWeapon/OffhandWeapon are serialized playsim state --
//    driving a networked weapon switch from local-only headset pose on every
//    remote copy of P_PlayerThink would desync multiplayer. Gating to the console
//    player only means P_BringUpWeapon runs exactly once, same as any other local
//    player-triggered weapon change.
//
//----------------------------------------------------------------------------

void VR_UpdateHardpoints(player_t* player)
{
	if (!player || !player->mo || (player - players) != consoleplayer) return;

	// Lazy one-shot seed of the config default slots (FVRConfig::Hardpoints). No engine
	// spawn-path hook needed: the first tic this console player's VR hardpoint system runs,
	// mirror the config table into the runtime slots. Survives respawn (player_t persists);
	// re-seeds only on a fresh player_t (flag defaults false). WITHOUT this, vr_hardpoint_count
	// stays 0, the count guard below bails every tic, and the entire native hardpoint/holster
	// subsystem is dead out-of-the-box. Runs before the enable/radius guards so toggling
	// vr_hardpoint_enable on at runtime works immediately against already-seeded slots.
	if (!player->vr_hardpoints_initialized)
	{
		VR_InitHardpoints(player);
		player->vr_hardpoints_initialized = true;
	}

	if (!VRMode::GetVRModeCached(false)) return;
	if (!vr_hardpoint_enable) return;
	if (vr_hardpoint_radius <= 0) return;
	if (player->vr_hardpoint_count <= 0) return;

	// Body anchor reference: playsim head/eye world pos (AttackPos is the per-frame
	// VR head pos). NOT r_viewpoint (render-thread only).
	const DVector3 headPos = player->mo->AttackPos;
	const DAngle   yaw     = player->mo->Angles.Yaw;
	const double   cosY    = yaw.Cos();
	const double   sinY    = yaw.Sin();

	// Cache both hand transforms once (wrist-anchored slots need the OTHER hand).
	VSMatrix handXf[2];
	bool     handOk[2] = { false, false };
	DVector3 handPos[2];
	for (int h = 0; h < 2; h++)
	{
		handOk[h] = VRMode::GetVRModeCached(false)->GetWeaponTransform(&handXf[h], h);
		if (handOk[h])
		{
			const float* m = handXf[h].get();
			handPos[h] = DVector3(m[12], m[14], m[13]); // column-major; m14=world Z, m13=world Y
		}
	}

	for (int hand = 0; hand < 2; hand++)
	{
		if (!handOk[hand]) continue;

		// Grip edge detection against our OWN latch.
		bool isGripPressed  = VR_IsGripPressed(player, hand);
		bool wasGripPressed = player->vr_hardpoint_was_grip[hand];
		player->vr_hardpoint_was_grip[hand] = isGripPressed;

		// Only the RISING edge triggers a draw/holster toggle.
		bool risingEdge = isGripPressed && !wasGripPressed;
		if (!risingEdge) continue;

		// [XR grip priority] CLIMB > WHIP > GLOVE > TWOHAND > HARDPOINT (lowest). Don't steal a
		// rising edge from a hand any higher-priority system already has a claim on: mid-climb,
		// mid-whip-swing, already holding a glove-grabbed item, mid-reach for one (candidate
		// highlighted / flick-locked / being pulled in), or bracing a two-hand foregrip. The
		// TWOHAND check reads vr_grip_owner[] directly (not a legacy flag like the others) because
		// VR_CalculateTwoHanding is the one consumer that publishes it itself, immediately before
		// this function runs in the same tic (see P_PlayerThink call order) -- so it's same-tic
		// fresh here, unlike the arbiter's CLIMB/GLOVE verdicts which are one tic stale by
		// construction and why those still read the legacy per-hand flags directly instead.
		if (player->vr_is_climbing[hand]) continue;
		if (player->vr_whip_rope_attached[hand]) continue;
		if (player->vr_held_items[hand]) continue;
		if (player->vr_grab_candidate[hand] != nullptr) continue;
		if (player->vr_grab_is_locked[hand]) continue;
		if (player->vr_grab_is_pulling[hand]) continue;
		if (player->vr_grip_owner[hand] == GRIP_TWOHAND) continue;

		// Find the nearest reachable slot for this hand.
		int    bestSlot   = -1;
		double bestDistSq = 0.0;

		for (int s = 0; s < player->vr_hardpoint_count; s++)
		{
			player_t::VRHardpointRuntime& slot = player->vr_hardpoints[s];
			if (!slot.enabled) continue;
			if (slot.hand != -1 && slot.hand != hand) continue; // hand-restricted slot

			// Compute this slot's world position by anchor type.
			DVector3 slotWorldPos;
			if (slot.anchor == HP_ANCHOR_WRIST)
			{
				// Hand-relative: mount on the OTHER hand's transform.
				int other = hand ^ 1;
				if (!handOk[other]) continue;
				const float* om = handXf[other].get();
				DVector3 otherPos(om[12], om[14], om[13]);
				// Local offset rotated by the other hand's basis (column-major, world-remapped Y/Z).
				DVector3 axX(om[0], om[2], om[1]);
				DVector3 axY(om[8], om[10], om[9]);
				DVector3 axZ(om[4], om[6], om[5]);
				slotWorldPos = otherPos + axX * slot.ox + axY * slot.oy + axZ * slot.oz;
			}
			else // HP_ANCHOR_BODY
			{
				// Body-relative: head/chest world pos + yaw-rotated local offset.
				// ox = right, oy = forward, oz = up (map units).
				double wx = slot.ox * cosY - slot.oy * sinY;
				double wy = slot.ox * sinY + slot.oy * cosY;
				slotWorldPos = DVector3(headPos.X + wx, headPos.Y + wy, headPos.Z + slot.oz);
			}

			double reach   = (slot.radius > 0.f) ? (double)slot.radius : (double)vr_hardpoint_radius;
			double reachSq = reach * reach;

			double distSq = (handPos[hand] - slotWorldPos).LengthSquared();
			if (distSq > reachSq) continue;

			if (bestSlot < 0 || distSq < bestDistSq)
			{
				bestSlot   = s;
				bestDistSq = distSq;
			}
		}

		if (bestSlot < 0) continue; // no slot in reach for this hand

		player_t::VRHardpointRuntime& slot = player->vr_hardpoints[bestSlot];

		if (slot.action == HP_ACT_ABILITY)
		{
			// Ability slot: hand off to a ZScript hook. Native side just latches
			// the edge and pulses haptics; ZScript owns the ability dispatch.
			IFVIRTUALPTRNAME(player->mo, NAME_PlayerPawn, VR_HardpointAbility)
			{
				VMValue params[3] = { player->mo, hand, bestSlot };
				VMCall(func, params, 3, nullptr, 0);
			}
			VR_HapticEvent("hardpoint", hand == 0 ? 1 : 2, 60, 0, 0);
			continue;
		}

		// HP_ACT_HOLSTER -- toggle draw/stow.
		if (slot.occupied)
		{
			// DRAW: bring the stowed weapon back up. Fully native path.
			AActor* stowed = slot.stowedWeapon;
			if (stowed)
			{
				player->PendingWeapon = stowed;
				P_BringUpWeapon(player);
			}
			slot.stowedWeapon = nullptr;
			slot.occupied     = false;
			VR_HapticEvent("hardpoint", hand == 0 ? 1 : 2, 80, 0, 0);
		}
		else
		{
			// STOW: the PSprite clear + ReadyWeapon detach MUST run through the VM
			// (PSprite mutation is ZScript-side). Dispatch the VIRTUAL PlayerPawn helper
			// VR_DoHolster -- NOT the native VR_HolsterHand thunk, which is not a virtual
			// ZScript method and would null-deref GetVirtualIndex on the first holster.
			AActor* toStow = (hand == VR_OFFHAND) ? player->OffhandWeapon : player->ReadyWeapon;
			if (toStow)
			{
				IFVIRTUALPTRNAME(player->mo, NAME_PlayerPawn, VR_DoHolster)
				{
					VMValue params[3] = { player->mo, hand, bestSlot };
					VMCall(func, params, 3, nullptr, 0);
				}
				slot.stowedWeapon = toStow;
				slot.occupied     = true;
				VR_HapticEvent("hardpoint", hand == 0 ? 1 : 2, 80, 0, 0);
			}
		}
	}
}

//----------------------------------------------------------------------------
//
// [XR weapon handling] VR_WeaponHotspotWorld -- world position of an authored weapon hotspot this tic.
// Composition = MAIN-hand transform (the gun rides the main hand) x the hotspot's model-local bind pos
// (via VR_WeaponBoneBindLocal, which confines FModel to p_actionfunctions.cpp). Authored bone ALWAYS wins;
// an un-migrated MD3 weapon has no hs_* bone -> we fill a coarse GEOMETRIC DEFAULT and return FALSE so
// callers fall back / stay legacy. Pure READ: never sets Vel/SetOrigin; disjoint from the whip WRITE path.
//
//----------------------------------------------------------------------------

bool VR_WeaponHotspotWorld(AActor* weapon, FName name, DVector3& out)
{
	out = DVector3(0, 0, 0);
	if (weapon == nullptr) return false;
	const VRMode* vrmode = VRMode::GetVRModeCached(false);
	if (vrmode == nullptr) return false;
	VSMatrix handXf;
	if (!vrmode->GetWeaponTransform(&handXf, VR_MAINHAND)) return false;
	const float* m = handXf.get();
	const DVector3 handPos(m[12], m[14], m[13]);
	const DVector3 hx(m[0], m[2], m[1]);   // local +X
	const DVector3 hy(m[4], m[6], m[5]);   // local +Y (up off the gun)
	const DVector3 hz(m[8], m[10], m[9]);  // local +Z (down the barrel, engine convention)

	FVector3 bindLocal;
	if (VR_WeaponBoneBindLocal(weapon, name, bindLocal))   // authored bone WINS
	{
		out = handPos + hx * (double)bindLocal.X + hy * (double)bindLocal.Y + hz * (double)bindLocal.Z;
		return true;
	}
	// GEOMETRIC DEFAULT (bootstrap; authored bone always preferred). NEVER runs once a weapon authors hs_*.
	if (name == NAME_hs_magwell) { out = handPos + hz * 4.0  - hy * 5.0; return false; }
	if (name == NAME_hs_rack)    { out = handPos + hz * 10.0 + hy * 6.0; return false; }
	out = handPos + hz * 14.0;   // foregrip along the barrel
	return false;
}

// [XR manual reload] Native chamber refill. Ammo1 is the reserve total; re-arm the chamber to
// min(magSize, reserve) and clear the reloading latch (the ZScript fire-gate reads XRChamber). Sole writer
// while vr_new_weapon_handling is on -> no double-count.
static void VR_ReloadRefill(AActor* weap, AActor* ammo, int magSize)
{
	if (!weap) return;
	const int reserve = ammo ? ammo->IntVar(NAME_Amount) : 0;
	const int loaded  = (reserve < magSize) ? reserve : magSize;
	weap->IntVar(NAME_XRChamber)    = loaded;
	weap->BoolVar(NAME_XRReloading) = false;
}

// [XR reload juice] Seat exactly ONE round (shell-by-shell / single-load). Clamps to magSize and reserve.
// Returns true if a round was actually added (false = already full or no reserve).
static bool VR_ReloadSeatOne(AActor* weap, AActor* ammo, int magSize)
{
	if (!weap) return false;
	const int reserve = ammo ? ammo->IntVar(NAME_Amount) : 0;
	const int cur     = weap->IntVar(NAME_XRChamber);
	if (cur >= magSize || cur >= reserve) return false;
	weap->IntVar(NAME_XRChamber)    = cur + 1;
	weap->BoolVar(NAME_XRReloading) = false;
	return true;
}

// [XR reload juice] Open the perfect-timing window (records the tic). Idempotent while already open.
static void VR_ReloadOpenPerfectWindow(player_t* player)
{
	if (player->vr_reload_start_tic == 0) player->vr_reload_start_tic = gametic > 0 ? gametic : 1;
}

// [XR reload juice] A refill just landed -- decide PERFECT (inside the window) and close the window. The
// ZScript juice handler polls VR_GetReloadPerfect; the flag also self-clears after vr_reload_perfect_life tics.
static void VR_ReloadScorePerfect(player_t* player, bool forcePerfect)
{
	bool perfect = forcePerfect;
	if (!perfect && player->vr_reload_start_tic != 0)
	{
		const int elapsed = gametic - player->vr_reload_start_tic;
		perfect = (elapsed >= 0 && elapsed <= (int)vr_reload_perfect_window);
	}
	player->vr_reload_start_tic = 0;                 // window closes on any refill
	if (perfect)
	{
		player->vr_reload_perfect     = true;
		player->vr_reload_perfect_tic = gametic;
		VR_HapticEvent("reload_perfect", 0, 100, 0, 0);   // 0 = both hands, distinct envelope
	}
}

// [XR reload juice] TOSS-CATCH detection. Returns true if the gun is pointed sharply UP (barrel skyward),
// which is the physical showoff gesture that lets a mag drop into the well. Reads the cached MAIN-hand basis:
// GetWeaponTransform layout is column-major; -colZ is the barrel-forward direction (engine convention, matches
// VR_WeaponHotspotWorld's hz). Barrel-up => forward.Z strongly positive.
static bool VR_ReloadGunInverted(const VSMatrix& mainXf)
{
	const float* m = mainXf.get();
	DVector3 fwd(-m[8], -m[10], -m[9]);              // down-the-barrel (same basis as hz in VR_WeaponHotspotWorld)
	const double len = fwd.Length();
	if (len < 1e-6) return false;
	fwd /= len;
	return fwd.Z > 0.70;                             // ~>45deg above horizontal: pointed up to catch
}

// [XR reload juice] SHELL-by-shell FSM (Shotgun / SuperShotgun). Seat ONE shell per grip-at-magwell, repeatable
// until full; a rack pump chambers/settles. Partial reloads allowed; firing (which drops XRChamber via the
// ZScript fire-gate) simply reopens the loop. Self-contained: caches its own hands. Style-gated by the caller.
static void VR_ReloadStyleShell(player_t* player, const VRMode* vrm, AActor* weap)
{
	const int magSize = weap->IntVar(NAME_XRMagSize);
	if (magSize <= 0) return;
	AActor* ammo = weap->PointerVar<AActor>(NAME_Ammo1);

	VSMatrix handXf[2]; bool handOk[2] = { false, false }; DVector3 handPos[2];
	for (int h = 0; h < 2; ++h) { handOk[h] = vrm->GetWeaponTransform(&handXf[h], h); if (handOk[h]) { const float* mm = handXf[h].get(); handPos[h] = DVector3(mm[12], mm[14], mm[13]); } }
	const int chamber = weap->IntVar(NAME_XRChamber);

	switch (player->vr_reload_state)
	{
	case player_t::VRRL_READY:
		if (chamber < magSize) { player->vr_reload_state = player_t::VRRL_EMPTY; VR_ReloadOpenPerfectWindow(player); }
		break;

	case player_t::VRRL_EMPTY:
	case player_t::VRRL_MAG_OUT:
	case player_t::VRRL_MAG_IN:   // shell has no distinct MAG_IN; treat all seat-loop nodes the same
	{
		if (chamber >= magSize) { player->vr_reload_state = player_t::VRRL_RACKED; break; }
		DVector3 magwell; VR_WeaponHotspotWorld(weap, NAME_hs_magwell, magwell);
		const double r = vr_reload_magwell_radius;
		for (int hand = 0; hand < 2; ++hand)
		{
			if (!handOk[hand]) continue;
			// A shell may ride as a held xr_mag item OR be seated "empty-handed" from a shoulder pouch feel:
			// require a grip edge with the hand near the magwell (item optional -- shells are diegetically small).
			AActor* held = player->vr_held_items[hand];
			const bool hasShell = held && held->Keywords.IndexOf("xr_mag") != -1;
			const double distSq = hasShell ? (held->Pos() - magwell).LengthSquared() : (handPos[hand] - magwell).LengthSquared();
			if (vr_reload_assist > 0.f && hasShell && distSq <= (r * r * 4.0))
			{
				DVector3 np = held->Pos() + (magwell - held->Pos()) * (double)clamp((float)vr_reload_assist, 0.f, 1.f);
				held->SetXYZ(np);
			}
			const bool gripNow  = (player->vr_grip_owner[hand] != GRIP_NONE) || VR_IsGripPressed(player, hand);
			const bool seatEdge = gripNow && !player->vr_reload_mag_grip_prev[hand];
			player->vr_reload_mag_grip_prev[hand] = gripNow;
			if (distSq <= (r * r) && seatEdge)
			{
				if (VR_ReloadSeatOne(weap, ammo, magSize))
				{
					if (hasShell) { held->Destroy(); player->vr_held_items[hand] = nullptr; }
					VR_HapticEvent("reload_seat", hand == 0 ? 1 : 2, 60, 0, 0);
					if (weap->IntVar(NAME_XRChamber) >= magSize) player->vr_reload_state = player_t::VRRL_RACKED;
				}
				break;
			}
		}
		break;
	}

	case player_t::VRRL_RACKED:
	{
		// A pump (rack pull) closes out the reload. Same travel gesture as box-mag rack.
		DVector3 rackPt; VR_WeaponHotspotWorld(weap, NAME_hs_rack, rackPt);
		DVector3 back(0, 0, 0);
		if (handOk[VR_MAINHAND]) { const float* mm = handXf[VR_MAINHAND].get(); DVector3 fwd(-mm[8], -mm[10], -mm[9]); if (fwd.Length() > 1e-6) { fwd.MakeUnit(); back = -fwd; } }
		for (int hand = 0; hand < 2; ++hand)
		{
			if (!handOk[hand]) continue;
			const bool gripNow  = (player->vr_grip_owner[hand] != GRIP_NONE) || VR_IsGripPressed(player, hand);
			const bool grabEdge = gripNow && !player->vr_reload_rack_grip_prev[hand];
			player->vr_reload_rack_grip_prev[hand] = gripNow;
			const double r = vr_reload_rack_radius; const double dSq = (handPos[hand] - rackPt).LengthSquared();
			if (player->vr_reload_rack_hand == -1 && grabEdge && dSq <= (r * r))
			{ player->vr_reload_rack_hand = hand; player->vr_reload_rack_anchor = handPos[hand]; player->vr_reload_rack_travel = 0.0; VR_HapticEvent("reload_rack", hand == 0 ? 1 : 2, 40, 0, 0); }
			if (player->vr_reload_rack_hand == hand)
			{
				if (!gripNow) { player->vr_reload_rack_hand = -1; player->vr_reload_rack_travel = 0.0; break; }
				const double pull = (handPos[hand] - player->vr_reload_rack_anchor) | back;
				if (pull > player->vr_reload_rack_travel) player->vr_reload_rack_travel = pull;
				if (player->vr_reload_rack_travel >= vr_reload_rack_travel)
				{
					player->vr_reload_rack_hand = -1; player->vr_reload_rack_travel = 0.0;
					player->vr_reload_chambered = true; player->vr_reload_state = player_t::VRRL_READY;
					VR_ReloadScorePerfect(player, false);
					VR_HapticEvent("reload_chamber", hand == 0 ? 1 : 2, 90, 0, 0);
				}
			}
		}
		break;
	}
	}
}

// [XR reload juice] INTERNAL (revolver cylinder + speedloader). Swing-out on empty, ONE seat-at-magwell with a
// speedloader bulk-loads the WHOLE cylinder (VR_ReloadRefill), then a close settles it. Self-contained.
static void VR_ReloadStyleInternal(player_t* player, const VRMode* vrm, AActor* weap)
{
	const int magSize = weap->IntVar(NAME_XRMagSize);
	if (magSize <= 0) return;
	AActor* ammo = weap->PointerVar<AActor>(NAME_Ammo1);

	VSMatrix handXf[2]; bool handOk[2] = { false, false }; DVector3 handPos[2];
	for (int h = 0; h < 2; ++h) { handOk[h] = vrm->GetWeaponTransform(&handXf[h], h); if (handOk[h]) { const float* mm = handXf[h].get(); handPos[h] = DVector3(mm[12], mm[14], mm[13]); } }
	const int chamber = weap->IntVar(NAME_XRChamber);

	switch (player->vr_reload_state)
	{
	case player_t::VRRL_READY:
		if (chamber <= 0) { player->vr_reload_state = player_t::VRRL_EMPTY; player->vr_reload_cylinder_open = true; VR_ReloadOpenPerfectWindow(player); }
		break;

	case player_t::VRRL_EMPTY:
	case player_t::VRRL_MAG_OUT:
	{
		// Cylinder is swung out; a single seat gesture at the magwell with a speedloader loads all chambers.
		DVector3 magwell; VR_WeaponHotspotWorld(weap, NAME_hs_magwell, magwell);
		const double r = vr_reload_magwell_radius;
		for (int hand = 0; hand < 2; ++hand)
		{
			if (!handOk[hand]) continue;
			AActor* held = player->vr_held_items[hand];
			if (!held || held->Keywords.IndexOf("xr_mag") == -1) continue;   // need the speedloader item
			const double distSq = (held->Pos() - magwell).LengthSquared();
			if (vr_reload_assist > 0.f && distSq <= (r * r * 4.0))
			{ DVector3 np = held->Pos() + (magwell - held->Pos()) * (double)clamp((float)vr_reload_assist, 0.f, 1.f); held->SetXYZ(np); }
			const bool gripNow  = (player->vr_grip_owner[hand] != GRIP_NONE) || VR_IsGripPressed(player, hand);
			const bool seatEdge = gripNow && !player->vr_reload_mag_grip_prev[hand];
			player->vr_reload_mag_grip_prev[hand] = gripNow;
			if (distSq <= (r * r) && seatEdge)
			{
				held->Destroy(); player->vr_held_items[hand] = nullptr;
				VR_ReloadRefill(weap, ammo, magSize);       // bulk load the whole cylinder at once
				player->vr_reload_mag_seated = true;
				player->vr_reload_state = player_t::VRRL_MAG_IN;   // MAG_IN == "cylinder loaded, awaiting close"
				VR_HapticEvent("reload_seat", hand == 0 ? 1 : 2, 75, 0, 0);
				break;
			}
		}
		break;
	}

	case player_t::VRRL_MAG_IN:
	{
		// CLOSE the cylinder: a flick/grip near the rack point (or auto-close when chamber toggle is off).
		if (!vr_reload_chamber)
		{
			player->vr_reload_cylinder_open = false; player->vr_reload_chambered = true;
			player->vr_reload_mag_seated = false; player->vr_reload_state = player_t::VRRL_READY;
			VR_ReloadScorePerfect(player, false);
			VR_HapticEvent("reload_chamber", 0, 85, 0, 0);   // 0 = both hands
			break;
		}
		DVector3 rackPt; VR_WeaponHotspotWorld(weap, NAME_hs_rack, rackPt);
		const double r = vr_reload_rack_radius;
		for (int hand = 0; hand < 2; ++hand)
		{
			if (!handOk[hand]) continue;
			const bool gripNow  = (player->vr_grip_owner[hand] != GRIP_NONE) || VR_IsGripPressed(player, hand);
			const bool grabEdge = gripNow && !player->vr_reload_rack_grip_prev[hand];
			player->vr_reload_rack_grip_prev[hand] = gripNow;
			const double dSq = (handPos[hand] - rackPt).LengthSquared();
			if (grabEdge && dSq <= (r * r))
			{
				player->vr_reload_cylinder_open = false; player->vr_reload_chambered = true;
				player->vr_reload_mag_seated = false; player->vr_reload_state = player_t::VRRL_READY;
				VR_ReloadScorePerfect(player, false);
				VR_HapticEvent("reload_chamber", hand == 0 ? 1 : 2, 85, 0, 0);
				break;
			}
		}
		break;
	}

	case player_t::VRRL_RACKED:
		player->vr_reload_state = player_t::VRRL_READY;
		break;
	}
}

// [XR reload juice] CANISTER (heat-vent energy weapons -- Plasma / BFG alt). No empty chamber: a per-player heat
// meter (ZScript adds heat per shot via VR_AddReloadHeat; native vents). On overheat, rack out the hot canister
// (hs_rack pull) then seat a cold one (hs_magwell) to reset heat. Self-contained.
static void VR_ReloadStyleCanister(player_t* player, const VRMode* vrm, AActor* weap)
{
	AActor* ammo = weap->PointerVar<AActor>(NAME_Ammo1);
	const int magSize = weap->IntVar(NAME_XRMagSize);   // reused as the "cold canister" chamber count

	if (player->vr_reload_heat >= (int)vr_reload_heat_max) player->vr_reload_overheated = true;
	if (!player->vr_reload_overheated) { player->vr_reload_state = player_t::VRRL_READY; return; }

	VSMatrix handXf[2]; bool handOk[2] = { false, false }; DVector3 handPos[2];
	for (int h = 0; h < 2; ++h) { handOk[h] = vrm->GetWeaponTransform(&handXf[h], h); if (handOk[h]) { const float* mm = handXf[h].get(); handPos[h] = DVector3(mm[12], mm[14], mm[13]); } }

	switch (player->vr_reload_state)
	{
	case player_t::VRRL_READY:
		player->vr_reload_state = player_t::VRRL_EMPTY; VR_ReloadOpenPerfectWindow(player);
		break;

	case player_t::VRRL_EMPTY:
	case player_t::VRRL_MAG_IN:   // still awaiting the hot-canister rack-out
	{
		// RACK OUT the hot canister.
		DVector3 rackPt; VR_WeaponHotspotWorld(weap, NAME_hs_rack, rackPt);
		DVector3 back(0, 0, 0);
		if (handOk[VR_MAINHAND]) { const float* mm = handXf[VR_MAINHAND].get(); DVector3 fwd(-mm[8], -mm[10], -mm[9]); if (fwd.Length() > 1e-6) { fwd.MakeUnit(); back = -fwd; } }
		for (int hand = 0; hand < 2; ++hand)
		{
			if (!handOk[hand]) continue;
			const bool gripNow  = (player->vr_grip_owner[hand] != GRIP_NONE) || VR_IsGripPressed(player, hand);
			const bool grabEdge = gripNow && !player->vr_reload_rack_grip_prev[hand];
			player->vr_reload_rack_grip_prev[hand] = gripNow;
			const double r = vr_reload_rack_radius; const double dSq = (handPos[hand] - rackPt).LengthSquared();
			if (player->vr_reload_rack_hand == -1 && grabEdge && dSq <= (r * r))
			{ player->vr_reload_rack_hand = hand; player->vr_reload_rack_anchor = handPos[hand]; player->vr_reload_rack_travel = 0.0; VR_HapticEvent("reload_rack", hand == 0 ? 1 : 2, 50, 0, 0); }
			if (player->vr_reload_rack_hand == hand)
			{
				if (!gripNow) { player->vr_reload_rack_hand = -1; player->vr_reload_rack_travel = 0.0; break; }
				const double pull = (handPos[hand] - player->vr_reload_rack_anchor) | back;
				if (pull > player->vr_reload_rack_travel) player->vr_reload_rack_travel = pull;
				if (player->vr_reload_rack_travel >= vr_reload_rack_travel)
				{
					player->vr_reload_rack_hand = -1; player->vr_reload_rack_travel = 0.0;
					player->vr_reload_state = player_t::VRRL_MAG_OUT;   // hot canister ejected; awaiting a cold seat
					VR_HapticEvent("reload_rack", hand == 0 ? 1 : 2, 90, 0, 0);
				}
			}
		}
		break;
	}

	case player_t::VRRL_MAG_OUT:
	{
		// SEAT a cold canister to reset heat.
		DVector3 magwell; VR_WeaponHotspotWorld(weap, NAME_hs_magwell, magwell);
		const double r = vr_reload_magwell_radius;
		for (int hand = 0; hand < 2; ++hand)
		{
			if (!handOk[hand]) continue;
			AActor* held = player->vr_held_items[hand];
			const bool hasCan = held && held->Keywords.IndexOf("xr_mag") != -1;
			const double distSq = hasCan ? (held->Pos() - magwell).LengthSquared() : (handPos[hand] - magwell).LengthSquared();
			if (vr_reload_assist > 0.f && hasCan && distSq <= (r * r * 4.0))
			{ DVector3 np = held->Pos() + (magwell - held->Pos()) * (double)clamp((float)vr_reload_assist, 0.f, 1.f); held->SetXYZ(np); }
			const bool gripNow  = (player->vr_grip_owner[hand] != GRIP_NONE) || VR_IsGripPressed(player, hand);
			const bool seatEdge = gripNow && !player->vr_reload_mag_grip_prev[hand];
			player->vr_reload_mag_grip_prev[hand] = gripNow;
			if (distSq <= (r * r) && seatEdge)
			{
				if (hasCan) { held->Destroy(); player->vr_held_items[hand] = nullptr; }
				player->vr_reload_heat = 0; player->vr_reload_overheated = false;
				if (magSize > 0) VR_ReloadRefill(weap, ammo, magSize);   // re-arm the chamber if this weapon uses one
				player->vr_reload_state = player_t::VRRL_READY;
				VR_ReloadScorePerfect(player, false);
				VR_HapticEvent("reload_seat", hand == 0 ? 1 : 2, 80, 0, 0);
				break;
			}
		}
		break;
	}

	default:
		player->vr_reload_state = player_t::VRRL_READY;
		break;
	}
}

//----------------------------------------------------------------------------
//
// [XR manual reload] VR_UpdateWeaponReload -- native box-mag reload FSM, peer of VR_UpdateHardpoints.
// LOCAL-PLAYER-ONLY. Vel-only: NEVER writes pawn Vel or SetOrigin -- refills act on Ammo1/XRChamber; the
// held mag is an item (SetXYZ on the item, not the pawn). Only READS hotspot bind poses (disjoint from the
// whip SetModelBonePose WRITE path).
//
//----------------------------------------------------------------------------

void VR_UpdateWeaponReload(player_t* player)
{
	if (!vr_new_weapon_handling) return;                        // MASTER TOGGLE off => classic reload untouched
	if (!player || !player->mo) return;
	if ((player - players) != consoleplayer) return;            // local-only (desync guard)
	const VRMode* vrm = VRMode::GetVRModeCached(true);
	if (!vrm->IsVR()) return;                                   // FLATSCREEN => classic button reload only

	AActor* weap = player->ReadyWeapon;
	if (weap != player->vr_reload_weapon)                       // weapon switch (or none): reset runtime
	{
		player->vr_reload_weapon      = weap;
		player->vr_reload_state       = player_t::VRRL_READY;
		player->vr_reload_mag_seated  = false;
		player->vr_reload_chambered   = false;
		player->vr_reload_rack_hand   = -1;
		player->vr_reload_rack_travel = 0.0;
		for (int h = 0; h < 2; ++h) { player->vr_reload_mag_grip_prev[h] = false; player->vr_reload_rack_grip_prev[h] = false; }
		// [XR reload juice] reset the extra-style + perfect + tactical runtime on switch too (heat persists per-weapon
		// only while it is the ReadyWeapon; a swap resets it -- acceptable for the alt heat-vent path).
		player->vr_reload_heat        = 0;
		player->vr_reload_overheated  = false;
		player->vr_reload_cylinder_open = false;
		player->vr_reload_start_tic   = 0;
		player->vr_reload_perfect     = false;
		player->vr_reload_tactical    = false;
		// [XR crash fix] clear handling style on switch so a non-mixin weapon can NEVER inherit RS_BOXMAG and
		// reach IntVar(XRMagSize) on a class without that field. The new weapon re-declares via
		// AssignWeaponHandling on its Select if it is a native-boxmag weapon.
		player->vr_weapon_handling.style    = player_t::RS_NONE;
		player->vr_weapon_handling.assigned = false;
	}
	if (!weap) return;

	// [XR reload juice] auto-clear a stale PERFECT flag the ZScript juice handler never polled (window life guard).
	if (player->vr_reload_perfect && (gametic - player->vr_reload_perfect_tic) > (int)vr_reload_perfect_life)
		player->vr_reload_perfect = false;

	// [XR reload juice] STYLE DISPATCH. Every mapped style is an XR_ManualReload-mixin weapon (has XRMagSize/
	// XRChamber), so each self-contained handler may safely read those fields. RS_BOXMAG falls through to the
	// original switch below -- BYTE-IDENTICAL, untouched. Non-boxmag styles run their own handler and return so
	// the box-mag XRMagSize read can NEVER see a class without the mixin field.
	switch (player->vr_weapon_handling.style)
	{
	case player_t::RS_SHELL:    VR_ReloadStyleShell(player, vrm, weap);    return;
	case player_t::RS_INTERNAL: VR_ReloadStyleInternal(player, vrm, weap); return;
	case player_t::RS_CANISTER: VR_ReloadStyleCanister(player, vrm, weap); return;
	case player_t::RS_BOXMAG:   break;   // fall through to the original box-mag FSM below
	default:                    return;  // RS_NONE / RS_BREAK / RS_POD: not yet FSM-wired -> no-op
	}

	const int magSize = weap->IntVar(NAME_XRMagSize);           // safe: RS_BOXMAG weapon has the mixin field
	if (magSize <= 0) return;

	AActor* ammo = weap->PointerVar<AActor>(NAME_Ammo1);        // the ONE true resource

	// Cache both hand transforms once (parity with VR_UpdateHardpoints).
	VSMatrix handXf[2]; bool handOk[2] = { false, false }; DVector3 handPos[2];
	for (int h = 0; h < 2; ++h)
	{
		handOk[h] = vrm->GetWeaponTransform(&handXf[h], h);
		if (handOk[h]) { const float* mm = handXf[h].get(); handPos[h] = DVector3(mm[12], mm[14], mm[13]); }
	}

	const int chamber = weap->IntVar(NAME_XRChamber);          // rounds the fire-gate believes are loaded

	switch (player->vr_reload_state)
	{
	case player_t::VRRL_READY:
		if (chamber <= 0) { player->vr_reload_state = player_t::VRRL_EMPTY; player->vr_reload_chambered = false; VR_ReloadOpenPerfectWindow(player); }
		break;

	case player_t::VRRL_EMPTY:
	case player_t::VRRL_MAG_OUT:
	{
		DVector3 magwell;
		VR_WeaponHotspotWorld(weap, NAME_hs_magwell, magwell);
		// [XR] Show new players where to insert the mag -- weapon-riding, so airborne/billboard glow.
		if (vr_reload_glow_enable) VR_PushWorldGlow(player->mo->Level, magwell, PalEntry((int)vr_reload_glow_color), vr_reload_glow_radius);
		// [XR reload juice] TOSS-CATCH: when the gun is pointed sharply UP, a held mag that touches the magwell
		// seats WITHOUT the grip edge -- the showoff reload, always granting the perfect bonus. Cheap pre-scan.
		const bool tossReady = vr_reload_toss_catch && handOk[VR_MAINHAND] && VR_ReloadGunInverted(handXf[VR_MAINHAND]);
		for (int hand = 0; hand < 2; ++hand)
		{
			if (!handOk[hand]) continue;
			AActor* held = player->vr_held_items[hand];
			if (!held) continue;
			if (held->Keywords.IndexOf("xr_mag") == -1) continue;   // only a spawned reload mag counts
			const double r = vr_reload_magwell_radius;
			const double distSq = (held->Pos() - magwell).LengthSquared();
			if (vr_reload_assist > 0.f && distSq <= (r * r * 4.0))  // soft outer ring: magnetic assist on the MAG (an item)
			{
				DVector3 np = held->Pos() + (magwell - held->Pos()) * (double)clamp((float)vr_reload_assist, 0.f, 1.f);
				held->SetXYZ(np);
			}
			const bool gripNow  = (player->vr_grip_owner[hand] != GRIP_NONE) || VR_IsGripPressed(player, hand);
			const bool seatEdge = gripNow && !player->vr_reload_mag_grip_prev[hand];
			player->vr_reload_mag_grip_prev[hand] = gripNow;
			// ALTERNATE toss-catch seat: inverted gun + mag intersecting the well, no grip edge required.
			const bool tossSeat = tossReady && distSq <= (r * r);
			if ((distSq <= (r * r) && seatEdge) || tossSeat)
			{
				held->Destroy();
				player->vr_held_items[hand] = nullptr;
				player->vr_reload_mag_seated = true;
				player->vr_reload_state = player_t::VRRL_MAG_IN;
				VR_HapticEvent("reload_seat", hand == 0 ? 1 : 2, tossSeat ? 90 : 70, 0, 0);
				if (!vr_reload_chamber)                             // AUTO-CHAMBER: seating re-arms, no rack
				{
					VR_ReloadRefill(weap, ammo, magSize);
					player->vr_reload_chambered = true;
					player->vr_reload_state = player_t::VRRL_READY;
					VR_ReloadScorePerfect(player, tossSeat);        // toss-catch => forced perfect
				}
				break;
			}
		}
		break;
	}

	case player_t::VRRL_MAG_IN:
	{
		DVector3 rackPt;
		VR_WeaponHotspotWorld(weap, NAME_hs_rack, rackPt);
		// [XR] Show new players where/how far to rack -- weapon-riding, so airborne/billboard glow.
		if (vr_reload_glow_enable) VR_PushWorldGlow(player->mo->Level, rackPt, PalEntry((int)vr_reload_glow_color), vr_reload_glow_radius);
		DVector3 back(0, 0, 0);
		if (handOk[VR_MAINHAND]) { const float* mm = handXf[VR_MAINHAND].get(); DVector3 fwd(-mm[8], -mm[10], -mm[9]); if (fwd.Length() > 1e-6) { fwd.MakeUnit(); back = -fwd; } }
		for (int hand = 0; hand < 2; ++hand)
		{
			if (!handOk[hand]) continue;
			const bool gripNow  = (player->vr_grip_owner[hand] != GRIP_NONE) || VR_IsGripPressed(player, hand);
			const bool grabEdge = gripNow && !player->vr_reload_rack_grip_prev[hand];
			player->vr_reload_rack_grip_prev[hand] = gripNow;
			const double r   = vr_reload_rack_radius;
			const double dSq = (handPos[hand] - rackPt).LengthSquared();
			if (player->vr_reload_rack_hand == -1 && grabEdge && dSq <= (r * r))
			{
				player->vr_reload_rack_hand   = hand;
				player->vr_reload_rack_anchor = handPos[hand];
				player->vr_reload_rack_travel = 0.0;
				VR_HapticEvent("reload_rack", hand == 0 ? 1 : 2, 40, 0, 0);
			}
			if (player->vr_reload_rack_hand == hand)
			{
				if (!gripNow) { player->vr_reload_rack_hand = -1; player->vr_reload_rack_travel = 0.0; break; }
				const double pull = (handPos[hand] - player->vr_reload_rack_anchor) | back; // travel backward along barrel
				if (pull > player->vr_reload_rack_travel) player->vr_reload_rack_travel = pull;
				if (player->vr_reload_rack_travel >= vr_reload_rack_travel)
				{
					VR_ReloadRefill(weap, ammo, magSize);          // rounds become live
					player->vr_reload_chambered   = true;
					player->vr_reload_mag_seated  = false;
					player->vr_reload_rack_hand   = -1;
					player->vr_reload_rack_travel = 0.0;
					player->vr_reload_state = player_t::VRRL_RACKED;
					VR_ReloadScorePerfect(player, false);          // rack landed the reload -> check the perfect window
					VR_HapticEvent("reload_chamber", hand == 0 ? 1 : 2, 90, 0, 0);
				}
			}
		}
		break;
	}

	case player_t::VRRL_RACKED:
		player->vr_reload_state = player_t::VRRL_READY;            // one-tic settle
		break;
	}
}

//----------------------------------------------------------------------------
// [XR debug/juice] ZScript accessors for the reload overlay + juice. STAGED: the
// ZScript callers live (commented) in vr_reload_debug.zs; enabling them also needs
// matching `native` decls added to the Actor class in actor.zs at this same rebuild.
//----------------------------------------------------------------------------
DEFINE_ACTION_FUNCTION(AActor, VR_GetWeaponHotspot)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_NAME(hs);
	DVector3 out(0, 0, 0);
	VR_WeaponHotspotWorld(self, hs, out);          // geometric fallback when no IQM bone
	ACTION_RETURN_VEC3(out);
}

DEFINE_ACTION_FUNCTION(AActor, VR_GetReloadState)
{
	PARAM_SELF_PROLOGUE(AActor);
	int st = 0;
	if (self->player) st = self->player->vr_reload_state;   // EVReloadState (0=READY..4=RACKED)
	ACTION_RETURN_INT(st);
}

// [XR reload juice] PERFECT-reload flag. Returns 1 if the last refill landed inside the perfect window, then
// CLEARS it (read-once). ZScript juice handler polls this to pop the "PERFECT" text + feed the combo meter.
DEFINE_ACTION_FUNCTION(AActor, VR_GetReloadPerfect)
{
	PARAM_SELF_PROLOGUE(AActor);
	int r = 0;
	if (self->player && self->player->vr_reload_perfect)
	{
		r = 1;
		self->player->vr_reload_perfect = false;            // consumed
	}
	ACTION_RETURN_INT(r);
}

// [XR reload juice] TACTICAL 1-in-the-barrel eject. Called by the ZScript eject when the chamber still has a
// round: keeps ONE chambered round, forfeits the rest of the partial mag, and drops the FSM into MAG_OUT so the
// seat loop re-arms. Returns 1 if a tactical eject was actually performed (chamber > 1 before the call).
DEFINE_ACTION_FUNCTION(AActor, VR_BeginTacticalEject)
{
	PARAM_SELF_PROLOGUE(AActor);
	player_t* pl = self ? self->player : nullptr;
	AActor* weap = pl ? pl->ReadyWeapon : nullptr;
	if (!pl || !weap) { ACTION_RETURN_INT(0); }
	const int cur = weap->IntVar(NAME_XRChamber);
	weap->IntVar(NAME_XRChamber) = (cur >= 1) ? 1 : 0;      // keep the chambered round (partial-mag rounds forfeit)
	pl->vr_reload_tactical  = true;
	pl->vr_reload_state     = player_t::VRRL_MAG_OUT;
	pl->vr_reload_mag_seated = false;
	pl->vr_reload_chambered = (weap->IntVar(NAME_XRChamber) > 0);
	VR_ReloadOpenPerfectWindow(pl);                         // tactical eject opens a fresh timing window
	ACTION_RETURN_INT(cur > 1 ? 1 : 0);
}

// [XR reload juice] FUMBLE / abort. Resets the reload runtime (state -> EMPTY if chamber is dry, else READY),
// clears the seat/rack latches, and returns 1 if a reload was actually IN PROGRESS (so a ZScript fumble handler
// can drop the loose mag). Does NOT touch XRChamber -- ammo state is untouched, only the in-flight gesture aborts.
DEFINE_ACTION_FUNCTION(AActor, VR_AbortReload)
{
	PARAM_SELF_PROLOGUE(AActor);
	player_t* pl = self ? self->player : nullptr;
	if (!pl) { ACTION_RETURN_INT(0); }
	const bool inProgress = (pl->vr_reload_state != player_t::VRRL_READY) || pl->vr_reload_mag_seated || (pl->vr_reload_rack_hand != -1);
	AActor* weap = pl->ReadyWeapon;
	const int chamber = weap ? weap->IntVar(NAME_XRChamber) : 0;
	pl->vr_reload_mag_seated   = false;
	pl->vr_reload_rack_hand    = -1;
	pl->vr_reload_rack_travel  = 0.0;
	pl->vr_reload_cylinder_open = false;
	pl->vr_reload_start_tic    = 0;                          // window closes on abort (no perfect from a fumble)
	pl->vr_reload_tactical     = false;
	for (int h = 0; h < 2; ++h) { pl->vr_reload_mag_grip_prev[h] = false; pl->vr_reload_rack_grip_prev[h] = false; }
	pl->vr_reload_state = (chamber <= 0) ? player_t::VRRL_EMPTY : player_t::VRRL_READY;
	ACTION_RETURN_INT(inProgress ? 1 : 0);
}

// [XR reload juice] Heat feed for RS_CANISTER. ZScript adds heat per shot (the fire path knows the weapon fired);
// the native FSM vents it. Clamps 0..vr_reload_heat_max; sets the overheat latch when the ceiling is reached.
// Returns the new heat value. No-op unless this weapon is the heat-vent style (guards accidental heat on others).
DEFINE_ACTION_FUNCTION(AActor, VR_AddReloadHeat)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_INT(delta);
	player_t* pl = self ? self->player : nullptr;
	if (!pl) { ACTION_RETURN_INT(0); }
	if (pl->vr_weapon_handling.style != player_t::RS_CANISTER) { ACTION_RETURN_INT(pl->vr_reload_heat); }
	int h = pl->vr_reload_heat + delta;
	if (h < 0) h = 0;
	if (h > (int)vr_reload_heat_max) h = (int)vr_reload_heat_max;
	pl->vr_reload_heat = h;
	if (h >= (int)vr_reload_heat_max) pl->vr_reload_overheated = true;
	ACTION_RETURN_INT(h);
}

// [XR reload juice] Read the RS_CANISTER heat 0..max (for a glow-bar HUD). Also exposes the overheat latch via
// the sign: returns heat, or -heat-1 when overheated so ZScript can branch without a second call.
DEFINE_ACTION_FUNCTION(AActor, VR_GetReloadHeat)
{
	PARAM_SELF_PROLOGUE(AActor);
	int r = 0;
	if (self->player) r = self->player->vr_reload_overheated ? (-self->player->vr_reload_heat - 1) : self->player->vr_reload_heat;
	ACTION_RETURN_INT(r);
}

//----------------------------------------------------------------------------
//
// VR_UpdateArmIK -- native two-bone shoulder/elbow IK helpers
//
// VSMatrix (common/utility/matrix.h) exposes no translation/rotation accessors -- only
// get() returning the raw column-major float[16] (VSMatrix::translate() writes indices
// 12/13/14, matrix.cpp:142-144; index = col*4+row throughout, confirmed against
// VSMatrix::multQuaternion's own forward construction at matrix.cpp:101-114). The two
// helpers below pull the translation column and reconstruct the rotation quaternion
// straight out of that same layout -- there is nothing else in this codebase to call.
//
//----------------------------------------------------------------------------

static FVector3 IK_MatTranslation(const VSMatrix& m)
{
	const float* d = m.get();
	return FVector3(d[12], d[13], d[14]);
}

// Standard trace-based (Shepperd) matrix->quaternion extraction. This is the exact closed-
// form inverse of VSMatrix::multQuaternion's own forward construction (matrix.cpp:101-114):
// that code writes element(row,col) = mMatrix[col*4+row] as the textbook active-rotation
// matrix for quaternion (X,Y,Z,W); what follows is the standard inverse of that matrix, not
// a guessed convention. CALIBRATE: assumes every ancestor joint's bind Scale is ~(1,1,1) --
// baseframe[] bakes each ancestor's scale into the 3x3 submatrix multiplicatively as it
// accumulates (models_iqm.cpp:166-167), so a non-uniform ancestor scale would skew this
// extraction. The column-normalize below is a cheap defensive guard against that, not a
// real fix -- a real fix would need Gram-Schmidt re-orthonormalization, not worth it unless
// a render test shows skewed elbows on a rig that actually uses non-uniform bone scale.
static FQuaternion IK_MatRotation(const VSMatrix& m)
{
	const float* d = m.get();

	FVector3 c0(d[0], d[1], d[2]);
	FVector3 c1(d[4], d[5], d[6]);
	FVector3 c2(d[8], d[9], d[10]);
	if (c0.LengthSquared() > 1.e-12f) c0.MakeUnit();
	if (c1.LengthSquared() > 1.e-12f) c1.MakeUnit();
	if (c2.LengthSquared() > 1.e-12f) c2.MakeUnit();

	float m00 = c0.X, m10 = c0.Y, m20 = c0.Z;
	float m01 = c1.X, m11 = c1.Y, m21 = c1.Z;
	float m02 = c2.X, m12 = c2.Y, m22 = c2.Z;

	float trace = m00 + m11 + m22;
	FQuaternion q(0.f, 0.f, 0.f, 1.f);
	if (trace > 0.f)
	{
		float s = sqrtf(trace + 1.f) * 2.f;
		q.W = 0.25f * s;
		q.X = (m21 - m12) / s;
		q.Y = (m02 - m20) / s;
		q.Z = (m10 - m01) / s;
	}
	else if (m00 > m11 && m00 > m22)
	{
		float s = sqrtf(1.f + m00 - m11 - m22) * 2.f;
		q.W = (m21 - m12) / s;
		q.X = 0.25f * s;
		q.Y = (m01 + m10) / s;
		q.Z = (m02 + m20) / s;
	}
	else if (m11 > m22)
	{
		float s = sqrtf(1.f + m11 - m00 - m22) * 2.f;
		q.W = (m02 - m20) / s;
		q.X = (m01 + m10) / s;
		q.Y = 0.25f * s;
		q.Z = (m12 + m21) / s;
	}
	else
	{
		float s = sqrtf(1.f + m22 - m00 - m11) * 2.f;
		q.W = (m10 - m01) / s;
		q.X = (m02 + m20) / s;
		q.Y = (m12 + m21) / s;
		q.Z = 0.25f * s;
	}
	q.MakeUnit();
	return q;
}

// Shortest-arc quaternion rotating unit vector a onto unit vector b. Same construction as
// the proven ZScript prototype (QuatFromTo, wadsrc/static/zscript/actors/doom/vr_whip.zs:
// 361-373), ported to FQuaternion/FVector3.
static FQuaternion IK_QuatFromTo(FVector3 a, FVector3 b)
{
	FVector3 axis = a ^ b;
	float al = (float)axis.Length();
	float d = (float)(a | b);
	if (al < 0.0001f)
	{
		if (d >= 0.f) return FQuaternion(0.f, 0.f, 0.f, 1.f); // identical -> identity
		// Opposite -> a 180 degree flip. Axis just needs to be perpendicular to a.
		FVector3 fallback = (fabsf(a.X) < fabsf(a.Y)) ? FVector3(1.f, 0.f, 0.f) : FVector3(0.f, 1.f, 0.f);
		FVector3 perp = a ^ fallback;
		if (perp.LengthSquared() < 1.e-8f) perp = a ^ FVector3(0.f, 0.f, 1.f);
		perp.MakeUnit();
		return FQuaternion::AxisAngle(perp, FAngle::fromDeg(180.0));
	}
	axis /= al;
	return FQuaternion::AxisAngle(axis, FAngle::fromRad(atan2f(al, d)));
}

// world -> model-local (baseframe/raw-joint) space -- see the COORDINATE FRAME note on
// VR_UpdateArmIK below. Two steps: (1) undo the actor's yaw in the Doom-world XY plane
// (Z passes through as "world up" for now), then (2) remap that Z-up actor-relative
// frame onto the model's raw joint-local axes, which this rig's IQM export uses Y as
// "up" for (see CalculateBonesIQM's own unconditional swapYZ sandwich, models_iqm.cpp
// ~line 700-761 -- it exists specifically because baseframe/inversebaseframe are NOT
// already in the same up-convention as the final Z-up render space). That swap is a
// literal (x,y,z)->(x,z,y) relabel, so step 2 here is the same relabel: local Y takes
// the world-up component, local Z takes the lateral (yaw-corrected off.Y) component.
// Local X (forward, from cosInvYaw/sinInvYaw) is untouched -- the swap never touches X.
// [XR] [[maybe_unused]]: the position path now inverts the renderer's objectToWorldMatrix directly
// (VR_UpdateArmIK), so this hand-rebuilt world->model-local helper is retained only as the documented
// reference for IK_ControllerModelRot's shared un-yaw algebra. Kept to avoid an unused-static warning.
[[maybe_unused]] static FVector3 IK_WorldToModelLocal(const DVector3& worldPos, const DVector3& actorPos, double cosInvYaw, double sinInvYaw)
{
	DVector3 off = worldPos - actorPos;
	double lx = off.X * cosInvYaw - off.Y * sinInvYaw; // forward
	double ly = off.X * sinInvYaw + off.Y * cosInvYaw; // lateral (Doom-world sense)
	// Y<->Z relabel into raw joint-local (Y-up) space: local Y = world up, local Z = lateral.
	return FVector3((float)lx, (float)off.Z, (float)ly);
}

// [XR] ROTATION analog of the POSITION path: pull the CONTROLLER's orientation out of the same
// GetWeaponTransform VSMatrix the position path reads, and land it in the EXACT baseframe the
// two-bone solve works in (the frame targetLocal[] lives in), so the wrist can be driven
// parent-relative off solve.lowerWorldRot.
//
// This now uses the SAME exact inverse the position path uses (Finv = swapYZ * objectToWorld^-1),
// applied to the controller's basis vectors as DIRECTIONS (w=0), so the wrist frame is consistent
// with the hand POSITION by construction -- NOT the old hand-rebuilt un-yaw/(Z,X,Y)-relabel/
// forward-flip approximation (which only un-yawed the pawn yaw, ignored the Y/Z-swapped bodyScale
// and the full drawn yaw baked into objectToWorldMatrix, and used an ad-hoc forward sign instead
// of swapYZ -> a frame mismatch that inverted the wrist). Steps, each mirroring the point path:
//   1. Read controller forward/up in raw GL layout (NO Doom remap): GL-forward = -colZ =
//      (-m[8],-m[9],-m[10]); GL-up = +colY = (m[4],m[5],m[6]) -- the same GL columns ptGL reads.
//   2. Transform each as a DIRECTION (w=0) through Finv (linear 3x3 only) -> baseframe space,
//      identically to how the point path lands the position; uniform bodyScale cancels on normalize.
//   3. Re-orthonormalize (fwd,up -> right = up^fwd, up = fwd^right) to strip any non-uniform
//      Y/Z-swapped-scale skew that Finv's non-orthonormal 3x3 leaves.
//   4. Load into a VSMatrix's rotation columns using the SAME column layout IK_MatRotation reads
//      (colX=[0..2], colY=[4..6], colZ=[8..10]) with GL-forward == -colZ, and extract the
//      quaternion with the proven IK_MatRotation. The returned quat is in the solve's baseframe
//      == solve.lowerWorldRot's frame, so localHand = lowerWorldRot^-1 * (ctrlModelRot*palmOffset)
//      is a valid same-frame composition and the wrist tracks correctly.
static bool IK_ControllerModelRot(const VSMatrix& handXf, VSMatrix& Finv, FQuaternion& outRot)
{
	const float* m = handXf.get();
	// (1) controller basis in the SAME raw GL layout the POSITION path reads (do NOT pre-remap to
	// Doom): GL-forward = -colZ = (-m[8],-m[9],-m[10]); GL-up = +colY = (m[4],m[5],m[6]). These are
	// the object->world (GL) axes objectToWorldMatrix^-1 expects, mirroring ptGL={m[12],m[13],m[14]}.
	FLOATTYPE fwdGL[4] = { -m[8], -m[9], -m[10], (FLOATTYPE)0 }; // -colZ == controller forward, as a DIRECTION (w=0)
	FLOATTYPE upGL [4] = {  m[4],  m[5],  m[6],  (FLOATTYPE)0 }; // +colY == controller up,      as a DIRECTION (w=0)

	// (2) transform both basis vectors as DIRECTIONS through the EXACT Finv (= swapYZ * objectToWorld^-1),
	// identically to how the point path lands the POSITION -- so the wrist frame == the target frame.
	// w=0 applies only Finv's linear 3x3 part (multMatrixPoint = column-major M*vec, matrix.cpp:357-367);
	// uniform bodyScale cancels on the normalize below.
	FLOATTYPE fwdB4[4], upB4[4];
	Finv.multMatrixPoint(fwdGL, fwdB4);
	Finv.multMatrixPoint(upGL,  upB4);
	FVector3 f((float)fwdB4[0], (float)fwdB4[1], (float)fwdB4[2]); // baseframe forward
	FVector3 u((float)upB4[0],  (float)upB4[1],  (float)upB4[2]);  // baseframe up
	if (f.LengthSquared() < 1.e-8f || u.LengthSquared() < 1.e-8f) return false;
	f.MakeUnit();

	// (3) Finv's 3x3 is NON-orthonormal (Y/Z-swapped, possibly non-uniform bodyScale), so the transformed
	// fwd/up are not guaranteed orthogonal -> re-orthonormalize off forward to strip the skew.
	// HANDEDNESS: Finv contains swapYZ (det -1) so its linear part is ORIENTATION-REVERSING. A textbook
	// right-handed cross order (right = up^fwd) on Finv's outputs yields a LEFT-handed basis (det -1) --
	// a MIRROR that IK_MatRotation silently collapses to the nearest rotation and that NO palmOffset can
	// correct (a reflection is unreachable by any rotation), which is what left the wrist mirrored/inverted.
	// Reverse the cross order (right = fwd^up, up = right^fwd) to compensate for the det(-1) map so the
	// reconstructed basis is a PROPER rotation (verified det +1 across 200 random controller poses).
	FVector3 right = f ^ u;
	if (right.LengthSquared() < 1.e-8f) return false; // fwd/up parallel -> degenerate, keep bind
	right.MakeUnit();
	u = right ^ f;      // re-orthonormalize up (right-handed given the reversed cross above)
	u.MakeUnit();

	// (4) orthonormal basis + matrix -> quat. GL-forward == -colZ, so colZ = -f (matches IK_MatRotation's read).
	FVector3 colZ = -f;
	VSMatrix rm;
	rm.loadIdentity();
	float* d = const_cast<float*>(rm.get());
	d[0] = right.X; d[1] = right.Y; d[2]  = right.Z; // colX
	d[4] = u.X;     d[5] = u.Y;     d[6]  = u.Z;     // colY
	d[8] = colZ.X;  d[9] = colZ.Y;  d[10] = colZ.Z;  // colZ
	outRot = IK_MatRotation(rm);
	return true;
}

// Two-bone (shoulder/elbow) IK solve for one arm, entirely in the model's own local/rest
// space. Returns the FULL desired model-space rotation for the upper-arm and lower-arm
// joints (i.e. the rotation component baseframe[joint] would have had, had the model been
// authored in this new pose) -- VR_UpdateArmIK still converts these into the LOCAL
// parent-relative rotation the engine actually wants.
struct FArmIKSolve
{
	FQuaternion upperWorldRot;
	FQuaternion lowerWorldRot;
	float stretch = 1.0f;  // [XR] >1 => arm stretched to reach a target beyond its natural span (written onto the upperArm bone scale)
};

static bool IK_SolveTwoBoneArm(
	const FVector3& shoulderPos, const FVector3& elbowBindPos, const FVector3& handBindPos,
	const FVector3& targetPos, const FVector3& poleDir,
	const FQuaternion& bindUpperWorldRot, const FQuaternion& bindLowerWorldRot,
	float upperLen, float forearmLen,
	FArmIKSolve& out)
{
	if (upperLen < 0.01f || forearmLen < 0.01f) return false;

	FVector3 bindUpperDir = elbowBindPos - shoulderPos;
	FVector3 bindLowerDir = handBindPos - elbowBindPos;
	if (bindUpperDir.LengthSquared() < 1.e-8f || bindLowerDir.LengthSquared() < 1.e-8f) return false;
	bindUpperDir.MakeUnit();
	bindLowerDir.MakeUnit();

	FVector3 toTarget = targetPos - shoulderPos;
	float rawReach = (float)toTarget.Length();
	if (rawReach < 0.0001f) return false; // target sits on the shoulder -- no aim direction
	FVector3 aimDir = toTarget / rawReach;

	// [XR] STRETCHY REACH: if the controller sits farther than the arm's natural span, scale BOTH bones so
	// the arm spans exactly rawReach -- the hand then lands ON the controller regardless of the marine's
	// (short) arm-to-height proportion. upperLen/forearmLen are by-value params, so overwriting them here
	// feeds the stretched lengths through the whole solve; out.stretch is written onto the upperArm bone's
	// pose scale in VR_UpdateArmIK so the MESH follows. == 1.0 (no change) whenever the target is in reach.
	{
		const float naturalArm = upperLen + forearmLen;
		out.stretch = (naturalArm > 0.01f && rawReach > naturalArm) ? (rawReach / naturalArm) : 1.0f;
		upperLen   *= out.stretch;
		forearmLen *= out.stretch;
	}

	// Reach-clamp: solve as if the target were at the nearest point still reachable by this
	// bone pair, along the SAME direction, instead of feeding law-of-cosines an out-of-domain
	// acos() argument when the real hand distance exceeds (or undershoots) what the arm can
	// physically span.
	float maxReach = (upperLen + forearmLen) * 0.999f;
	float minReach = fabsf(upperLen - forearmLen) * 1.001f + 0.01f;
	float reach = clamp(rawReach, minReach, maxReach);

	// Law of cosines: angle at the shoulder between aimDir (shoulder->target) and the
	// solved upper-arm direction.
	float cosShoulder = (upperLen * upperLen + reach * reach - forearmLen * forearmLen) / (2.f * upperLen * reach);
	cosShoulder = clamp(cosShoulder, -1.f, 1.f);
	float shoulderAngle = acosf(cosShoulder); // radians

	// Pole vector: the plane the elbow bends in. Project out the aimDir component so what's
	// left is purely perpendicular to the shoulder->target line ("which way the elbow points").
	FVector3 poleProj = poleDir - aimDir * (float)(poleDir | aimDir);
	float poleLen = (float)poleProj.Length();
	if (poleLen < 0.0001f)
	{
		poleProj = aimDir ^ FVector3(0.f, 0.f, 1.f);
		poleLen = (float)poleProj.Length();
		if (poleLen < 0.0001f)
		{
			poleProj = FVector3(1.f, 0.f, 0.f);
			poleLen = 1.f;
		}
	}
	poleProj /= poleLen;

	FVector3 rotAxis = aimDir ^ poleProj;
	float axisLen = (float)rotAxis.Length();
	if (axisLen < 0.0001f) return false; // aimDir parallel to the pole plane normal -- shouldn't happen post-projection
	rotAxis /= axisLen;

	FQuaternion shoulderSwing = FQuaternion::AxisAngle(rotAxis, FAngle::fromRad(shoulderAngle));
	FVector3 upperDirSolved = shoulderSwing * aimDir;
	upperDirSolved.MakeUnit();

	FVector3 elbowPos = shoulderPos + upperDirSolved * upperLen;
	FVector3 lowerDirSolved = targetPos - elbowPos;
	float lowerLen = (float)lowerDirSolved.Length();
	if (lowerLen > 0.0001f) lowerDirSolved /= lowerLen;
	else lowerDirSolved = bindLowerDir; // degenerate -- keep the bind direction rather than NaN

	FQuaternion deltaUpper = IK_QuatFromTo(bindUpperDir, upperDirSolved);
	FQuaternion deltaLower = IK_QuatFromTo(bindLowerDir, lowerDirSolved);

	out.upperWorldRot = deltaUpper * bindUpperWorldRot;
	out.lowerWorldRot = deltaLower * bindLowerWorldRot;
	out.upperWorldRot.MakeUnit();
	out.lowerWorldRot.MakeUnit();
	return true;
}

EXTERN_CVAR(Bool,  vr_ik_enable)
EXTERN_CVAR(Float, vr_ik_upperarm_len)
EXTERN_CVAR(Float, vr_ik_forearm_len)
EXTERN_CVAR(Bool,  vr_ik_hand_rot)
EXTERN_CVAR(Float, vr_ik_hand_pitch)
EXTERN_CVAR(Float, vr_ik_hand_yaw)
EXTERN_CVAR(Float, vr_ik_hand_roll)
EXTERN_CVAR(Float, vr_ik_hand_smooth)
EXTERN_CVAR(Float, vr_ik_hand_maxstep)

// [XR] Live-tunable CONSTANT nudge of the IK hand target in the model's own frame so the hand can be slid
// exactly onto the controller in-headset (same idea as per-weapon model offsets). Absorbs any fixed shift
// the frame math leaves (vr_body_z, feet-vs-mesh-origin, mesh authoring). 0,0,0 = no nudge. Dial in-console.
CVAR(Float, vr_ik_target_offx, 0.0f, CVAR_ARCHIVE | CVAR_GLOBALCONFIG) // +X = model LATERAL (+left / -right)
CVAR(Float, vr_ik_target_offy, 0.0f, CVAR_ARCHIVE | CVAR_GLOBALCONFIG) // +Y = model FORWARD (view direction)
CVAR(Float, vr_ik_target_offz, 0.0f, CVAR_ARCHIVE | CVAR_GLOBALCONFIG) // +Z = model UP
// [XR] PALM-SEAT correction. The two-bone IK places the marine WRIST joint on the controller/grip point, but
// the hand MESH is skinned FORWARD of the wrist -- so the palm/fingers (the part that wraps a gun grip) land a
// few units PAST the controller. This pulls the IK target back along model-FORWARD by that fixed wrist->palm
// length, so the PALM seats on the controller (and thus on the weapon's hs_grip, which sits at the model
// origin = the controller). Applied to BOTH hands (same mesh authoring) every tic. Default is a best-guess
// starting length; dial in headset until the palm sits in the controller sphere. Set 0 to disable (revert).
CVAR(Float, vr_ik_palm_back, 3.0f, CVAR_ARCHIVE | CVAR_GLOBALCONFIG)
// [XR] HAND GRIP CURL. The arm IK poses the wrist but leaves the 15 finger joints per hand at their OPEN bind
// pose, so the hand never closes on a held gun. When a hand holds a weapon, curl its finger joints into a fist.
// Rig fact (marine_novr.iqm, verified from bind geometry): finger bones point down local -Z and spread along X,
// so flexion is rotation about local +X -- the axis is derived, NOT guessed. Only the SIGN may need a flip:
// if fingers bend BACKWARD, negate vr_hand_grip_curl / _thumb. Set vr_hand_grip 0 to disable (open hands).
CVAR(Bool,  vr_hand_grip,       true,  CVAR_ARCHIVE | CVAR_GLOBALCONFIG) // curl fingers around a held weapon
CVAR(Float, vr_hand_grip_curl,  35.0f, CVAR_ARCHIVE | CVAR_GLOBALCONFIG) // per-segment finger flex angle (deg; negate to flip)
CVAR(Float, vr_hand_grip_thumb, 15.0f, CVAR_ARCHIVE | CVAR_GLOBALCONFIG) // thumb flex angle (deg; usually less than the fingers)
// [XR] Overall arm-length scale, wired into VR_UpdateArmIK's per-side bone lengths (both bones x this). 1.0 =
// the rig's own proportions; <1 shortens reach, >1 lengthens. Clamped 0.5..2.0 in the solver. Slider-tunable.
CVAR(Float, vr_ik_arm_scale,    1.0f,  CVAR_ARCHIVE | CVAR_GLOBALCONFIG)
// [XR] EXTRA palm rotation applied to the LEFT / OFF hand ONLY (side 1), on top of the shared
// vr_ik_hand_pitch/yaw/roll. The left hand's bind palm is a MIRROR of the right, so the offset that
// aligns the right hand is ~180 off for the left. Dial these (try vr_ik_offhand_roll 180 first) until
// the offhand palm matches the right; 0,0,0 = same as the main hand.
CVAR(Float, vr_ik_offhand_pitch, 0.0f, CVAR_ARCHIVE | CVAR_GLOBALCONFIG)
CVAR(Float, vr_ik_offhand_yaw,   0.0f, CVAR_ARCHIVE | CVAR_GLOBALCONFIG)
CVAR(Float, vr_ik_offhand_roll,  0.0f, CVAR_ARCHIVE | CVAR_GLOBALCONFIG)
// [XR] mesh-facing correction the RENDERER adds to the VR body (r_data/models.cpp:76, default 90).
// VR_UpdateArmIK must un-yaw the hand target by the SAME total yaw the renderer draws the body at
// (vr_body_facing_yaw + vr_body_yaw + SpriteRotation, models.cpp:223) so the IK frame == render frame.
EXTERN_CVAR(Float, vr_body_yaw)

// [XR] Body-fit scale used by the RENDERER (r_data/models.cpp:110-136) to shrink the local
// player's avatar about its feet (the mesh origin == actorPos). The IK solves in the UNSCALED
// baseframe, so the world hand target -- captured in that same rendered/scaled body space --
// has to be divided by this scale (about the feet pivot) to land in baseframe units. The
// live render autofit scale is exposed via g_xr_vrBodyRenderScale (models.cpp); vr_body_scale
// is the manual/fallback. The [VRIK_TGT2] probe below reveals any residual gap.
EXTERN_CVAR(Float, vr_body_scale)
EXTERN_CVAR(Bool,  vr_body_autofit)
extern float g_xr_vrBodyRenderScale;
// [XR] The renderer's OWN finalized VR-body objectToWorldMatrix (r_data/models.cpp), published so the IK
// can invert it exactly. target_baseframe = swapYZ * objectToWorldMatrix^-1 * controller_world_GL -- this
// single inverse subsumes the drawn yaw, vr_body_z, and the bodyScale divide, eliminating the hand-rebuilt
// un-yaw / axis-remap / feet-subtract / bodyFit-divide / forward-flip below.
extern VSMatrix g_xr_vrBodyObjectToWorld;
extern bool     g_xr_vrBodyObjToWorldValid;

//----------------------------------------------------------------------------
//
// [XR] PROCEDURAL WEAPON RECOIL -- VR_UpdateWeaponAnim
//
// Peer of VR_UpdateArmIK, but for the HELD WEAPON instead of the body. Drives the weapon IQM's hs_grip ROOT
// bone per-tic to kick the whole gun back-and-up on each shot, then springs it back to rest -- so firing reads
// as a fluid recoil instead of a static prop. NO baked animation frames, NO re-export: it writes the SAME
// proceduralPose channel the physics-whip and body-avatar already use (DActorModelData::proceduralPose +
// useProceduralPose), which the HUD weapon render consumes via RenderHUDModel -> RenderFrameModels(psp->Caller)
// -> ProcessModelFrame (r_data/models.cpp). hs_grip is the model's non-deforming weight-anchor ROOT (the whole
// mesh rides it, tools/weapon_iqm_build README), so translating its local TRS rigidly kicks the entire gun.
//
// SELF-CALIBRATING DIRECTION: the kickback axis is derived from the weapon's OWN bones -- normalize(hs_grip ->
// hs_foregrip) is the barrel line, so we push back along its negation (grip end, toward the shooter). No
// per-weapon axis table; a weapon with no foregrip falls back to model -X (the batch tool's barrel long-axis).
//
// FIRE SIGNAL: rising edge of the attack button (attackdown / ohattackdown) plus a re-kick whenever the refire
// counter climbs (sustained auto-fire re-fires without a fresh button edge). Zero ZScript hooks: works for the
// whole roster off state already on player_t. GATED on vr_weapon_recoil (default on); an un-migrated MD3 weapon
// resolves to no rigged model and is skipped, so the legacy roster is byte-for-byte unaffected.
//
// TRANSIENT / LOCAL-PRESENTATION-ONLY: reads inputs + writes a render-side kick envelope; NEVER touches Vel /
// SetOrigin / Ammo (disjoint from the reload FSM's ammo writes and the whip's world-bone writes).
//
//----------------------------------------------------------------------------

CVAR(Bool,  vr_weapon_recoil,        true, CVAR_ARCHIVE | CVAR_GLOBALCONFIG) // master: procedural weapon recoil on/off
CVAR(Float, vr_weapon_recoil_kick,   2.5f, CVAR_ARCHIVE | CVAR_GLOBALCONFIG) // map-units the gun slides BACK at full kick (negate to flip)
CVAR(Float, vr_weapon_recoil_rise,   1.0f, CVAR_ARCHIVE | CVAR_GLOBALCONFIG) // map-units the gun lifts UP (model +Z) at full kick (muzzle rise)
CVAR(Float, vr_weapon_recoil_decay,  0.55f,CVAR_ARCHIVE | CVAR_GLOBALCONFIG) // per-tic multiplier of the kick envelope (spring-back speed; 0..1)
CVAR(Float, vr_weapon_recoil_impulse,1.0f, CVAR_ARCHIVE | CVAR_GLOBALCONFIG) // envelope added per shot (clamped to 1); <1 = softer, stacks on auto

// Kick one hand's weapon: seed proceduralPose with the bind pose, then offset the hs_grip root by the recoil
// envelope along the self-derived back+up axes. amt is this hand's 0..1 envelope (already updated by caller).
static void VR_ApplyWeaponRecoil(player_t* player, int handSlot, AActor* weapon)
{
	const float amt = player->vr_weapon_recoil[handSlot];

	// Envelope spent: release OUR procedural-pose override (if we set it) so the gun renders its normal
	// static bind pose again. Only clear when we own it -- never stomp another system's pose on this actor.
	if (amt <= 0.f)
	{
		if (player->vr_weapon_pose_active[handSlot] && weapon != nullptr && weapon->modelData != nullptr)
			weapon->modelData->useProceduralPose = false;
		player->vr_weapon_pose_active[handSlot] = false;
		return;
	}
	if (weapon == nullptr) return;

	FModel* model = VR_EnsureWeaponModelDataAndGetModel(weapon);  // null => MD3 / unrigged: nothing to pose
	DActorModelData* md = weapon->modelData;
	if (model == nullptr || md == nullptr) return;

	const int jointCount = model->GetJointCount();
	if (jointCount <= 0) return;

	// (Re)seed the WHOLE skeleton to its bind pose every tic. Mandatory: a default-constructed TRS has
	// scaling (0,0,0) (utility/TRS.h), which would collapse the mesh -- and last tic's kick must be cleared
	// off every non-grip joint. GetJointBindTRS fills real translate/rotate/scale from the model.
	if ((int)md->proceduralPose.Size() != jointCount)
		md->proceduralPose.Resize(jointCount);
	for (int i = 0; i < jointCount; i++)
		model->GetJointBindTRS(i, md->proceduralPose[i]);

	int gripIdx = model->FindJointByNameCI(FName("hs_grip"));
	if (gripIdx < 0) gripIdx = 0;   // hs_grip is authored as joint 0 (the root); fall back to the root anyway

	// Back axis from the gun's OWN geometry: grip <- foregrip is "toward the shooter". Fall back to model -X
	// (the batch builder's barrel long-axis) when a weapon authors no foregrip (melee/pod styles).
	FVector3 back(-1.f, 0.f, 0.f);
	int foreIdx = model->FindJointByNameCI(FName("hs_foregrip"));
	FVector3 gripPos, forePos;
	if (foreIdx >= 0 && model->GetJointBaseframePos(gripIdx, gripPos) && model->GetJointBaseframePos(foreIdx, forePos))
	{
		FVector3 d = gripPos - forePos;          // muzzle-end -> grip-end
		if (d.Length() > 0.001f) back = d.Unit();
	}
	const FVector3 up(0.f, 0.f, 1.f);            // model +Z = up (hs_rack sits +Z of the bore)

	const FVector3 delta = back * ((float)vr_weapon_recoil_kick * amt) + up * ((float)vr_weapon_recoil_rise * amt);
	md->proceduralPose[gripIdx].translation += delta;   // rigid whole-gun kick (root carries all mesh weight)
	md->useProceduralPose = true;
	player->vr_weapon_pose_active[handSlot] = true;

	static int s_recoilDbg = 0;
	if (s_recoilDbg < 30)
	{
		s_recoilDbg++;
		Printf("[VRRECOIL] slot=%d amt=%.2f joints=%d grip=%d fore=%d back=(%.2f,%.2f,%.2f)\n",
			handSlot, amt, jointCount, gripIdx, foreIdx, back.X, back.Y, back.Z);
	}
}

void VR_UpdateWeaponAnim(player_t* player)
{
	if (!vr_weapon_recoil) return;               // master toggle off => weapons render static (legacy)
	if (!player || !player->mo) return;

	// ---- fire edges (no ZScript hook needed): a fresh trigger pull OR a climbing refire count = a shot ----
	const bool attackNow   = player->attackdown;
	const bool ohattackNow = player->ohattackdown;
	const int  refireNow   = player->refire;
	const bool mainFired = (attackNow   && !player->vr_weapon_attack_prev)   || (refireNow > player->vr_weapon_refire_prev);
	const bool offFired  = (ohattackNow && !player->vr_weapon_ohattack_prev);
	player->vr_weapon_attack_prev   = attackNow;
	player->vr_weapon_ohattack_prev = ohattackNow;
	player->vr_weapon_refire_prev   = refireNow;

	const float impulse = (float)vr_weapon_recoil_impulse;
	float decay = (float)vr_weapon_recoil_decay;
	if (decay < 0.f) decay = 0.f; if (decay > 0.98f) decay = 0.98f;

	// slot 0 = main-hand weapon (ReadyWeapon), slot 1 = off-hand weapon (OffhandWeapon, dual-wield)
	AActor* weapons[2] = { player->ReadyWeapon, player->OffhandWeapon };
	const bool fired[2] = { mainFired, offFired };

	for (int h = 0; h < 2; h++)
	{
		float amt = player->vr_weapon_recoil[h];
		if (fired[h]) { amt += impulse; if (amt > 1.f) amt = 1.f; }
		else          { amt *= decay;   if (amt < 0.02f) amt = 0.f; }
		player->vr_weapon_recoil[h] = amt;

		VR_ApplyWeaponRecoil(player, h, weapons[h]);
	}
}

//----------------------------------------------------------------------------
//
// VR_UpdateArmIK
//
// Native two-bone shoulder/elbow IK for the avatar's IQM arm joints. Writes ONLY
// player->vr_ik_pose (one parent-local TRS per skeleton joint: bind values for every
// joint except the 4 solved arm joints, which get a new ROTATION only -- translate/
// scale are never touched, bones don't stretch). A separate glue point (not this
// function, per the design brief) copies vr_ik_pose into player->mo->modelData->
// proceduralPose and flips useProceduralPose for the render path (see
// AActor::SetModelBonePose/SetModelUseProceduralPose, scripting/vmthunks_actors.cpp:
// 2328-2360).
//
// STRUCTURAL TEMPLATE: VR_UpdateGravityGloves (this file, ~line 1483) for the guard
// block shape, and VR_UpdateHardpoints (this file, immediately above) for the local-
// player-only gate rationale -- GetWeaponTransform reads the single LOCAL OpenXR
// device with no player parameter, so driving ANY playsim-visible state off it for a
// non-console player_t on this machine is meaningless local-headset data misattributed
// to someone else. vr_ik_pose itself is also explicitly excluded from FSerializer/net
// (see d_player.h:515-518's TRANSIENT/CLIENT-PRESENTATION-ONLY note).
//
// COORDINATE FRAME: FModel::GetBasePose() (model.h, overridden model_iqm.h) hands back
// baseframe -- a plain top-down accumulation of each joint's own RAW local bind TRS
// (models_iqm.cpp, the joint-read loop just above CalculateBonesIQM), i.e. MODEL-local/
// rest space with the actor's transform NOT applied and NO swapYZ baked in. The
// world-space hand targets from GetWeaponTransform must be converted into that SAME
// space in two steps: (1) subtract the actor's world position and undo the actor's yaw
// with a plain 2D rotation in the Doom-world XY plane, then (2) relabel the result onto
// the model's own raw joint-local axes via a Y<->Z swap (IK_WorldToModelLocal does both).
// That second step is required, NOT optional: CalculateBonesIQM (models_iqm.cpp
// ~line 700-761) sandwiches baseframe/inversebaseframe between an UNCONDITIONAL swapYZ
// on every joint (root and child alike) specifically because raw joint-local space is
// NOT already in the same up-convention as the final Z-up render/world space -- this
// project's own prior verified finding is that this IQM rig's bone TRS is Y-up, matching
// the swapYZ evidence exactly. So: local Y (not local Z) carries "world up", and local Z
// carries the lateral component; local X (forward) is untouched by the relabel, since
// swapYZ never touches the X row/column. The pole-vector down/back constants below are
// expressed in this SAME post-swap local frame. CALIBRATE (the one thing that still
// needs an in-headset render test, not provable from source alone): this Y<->Z relabel
// direction -- if elbows splay sideways/forward instead of down-and-back on a real
// render, the fix is swapping which of (off.Z, ly) lands on local Y vs Z in
// IK_WorldToModelLocal, and mirroring that in downLocal/backLocal below. The SIGN of the
// yaw un-rotation itself is lower-risk and well-grounded: Angles.Yaw.ToVector() = (Cos,
// Sin) (vectors.h), the same forward convention already used for real gameplay traces
// (p_map.cpp UseRange trace, p_switch.cpp dlu.dx/dlu.dy), and algebraic substitution
// confirms invYaw=-Yaw maps world-forward onto local +X here -- still worth eyeballing
// in the same render test, but not the primary suspect if arms look wrong.
//
//----------------------------------------------------------------------------

void VR_UpdateArmIK(player_t* player)
{
	if (!player || !player->mo) return;
	{ static int s_ikEntry=0; if (s_ikEntry++<20) Printf("[VRIK_ENTRY] sprite=%d frame=%d vr_ik_enable=%d vr_ik_enabled=%d\n", (int)player->mo->sprite, (int)player->mo->frame, (int)vr_ik_enable, (int)player->vr_ik_enabled); }

	// LOCAL PLAYER ONLY -- see the rationale block above.
	if (player != player->mo->Level->GetConsolePlayer())
	{
		{ static int s_gB=0; if (s_gB++<20) Printf("[VRIK_BAIL_B] player=%p console=%p\n", player, player->mo->Level->GetConsolePlayer()); }
		player->vr_ik_active = false;
		return;
	}

	if (!VRMode::GetVRModeCached(false))
	{
		{ static int s_gC=0; if (s_gC++<20) Printf("[VRIK_BAIL_C]\n"); }
		player->vr_ik_active = false;
		return;
	}

	// Two independent gates, per the design brief: the global feature cvar, and the
	// per-player runtime flag toggled by AActor::SetArmIKEnabled (vmthunks_actors.cpp).
	if (!vr_ik_enable || !player->vr_ik_enabled)
	{
		{ static int s_gD=0; if (s_gD++<20) Printf("[VRIK_BAIL_D] enable=%d enabled=%d\n", (int)vr_ik_enable, (int)player->vr_ik_enabled); }
		player->vr_ik_active = false;
		return;
	}

	// ---- locate the avatar's loaded IQM model ----
	// Scan every entry in modelData->models rather than assuming index 0 is the body --
	// GetJointCount() > 0 is itself the "this is a loaded IQM with a skeleton" signal, so
	// there is no need to RTTI/dynamic_cast to IQMModel at all (see model.h's GetJointCount
	// base-class comment).
	// The marine avatar is bound via its STATIC modeldef, so a plain player pawn never gets a
	// DActorModelData -- and the IK needs one to write the solved pose into (the renderer reads
	// modelData->proceduralPose). This creates it (models list left EMPTY -> render still uses the
	// static modeldef, body unchanged) and returns the rigged avatar model from that same modeldef.
	// THE FIX for "arms never move": before this, modelData was null every tic and the IK bailed here.
	FModel* model = VR_EnsureAvatarModelDataAndGetModel(player->mo);
	DActorModelData* modelData = player->mo->modelData;
	if (model == nullptr || modelData == nullptr)
	{
		player->vr_ik_active = false;
		return;
	}

	const TArray<VSMatrix>* baseframePtr = model->GetBasePose();
	if (baseframePtr == nullptr || baseframePtr->Size() == 0)
	{
		{ static int s_gF=0; if (s_gF++<20) Printf("[VRIK_BAIL_F] bf=%p size=%d\n", baseframePtr, baseframePtr?(int)baseframePtr->Size():-1); }
		player->vr_ik_active = false;
		return;
	}
	const TArray<VSMatrix>& baseframe = *baseframePtr;

	int jointCount = model->GetJointCount();
	if (jointCount <= 0 || (unsigned)jointCount > baseframe.Size())
	{
		{ static int s_gG=0; if (s_gG++<20) Printf("[VRIK_BAIL_G] jointCount=%d bfSize=%u\n", jointCount, (unsigned)baseframe.Size()); }
		player->vr_ik_active = false;
		return;
	}

	// ---- (re)size + fill the bind pose. Resize only on a genuine count mismatch (first
	// solve / model swap) to avoid per-tic heap churn; the fill loop itself runs every tic
	// regardless, since the 2 solved joints per side get overwritten below and everything
	// else must be re-seeded to bind in case a PREVIOUS tic's solve touched them. ----
	if (player->vr_ik_pose.Size() != (unsigned)jointCount)
	{
		player->vr_ik_pose.Resize(jointCount);
	}
	for (int i = 0; i < jointCount; i++)
	{
		model->GetJointBindTRS(i, player->vr_ik_pose[i]);
	}

	// ---- resolve the arm-chain joint indices: name lookup first, numeric fallback ----
	// Resolved ONCE per loaded model and cached, not redone every tic -- FindJointByName is
	// an O(Joints.Size()) linear scan and FName(const char*) is a global name-table
	// insert-or-find on first use, neither of which needs to run 2*4 times per tic forever
	// for data that cannot change between tics for a given loaded model (mirrors the
	// one-time-cost discipline already used for warnedNameFallback/vr_ik_pose.Resize just
	// above). Re-resolved only when the avatar model itself changes.
	struct ArmChain { int collar, upperArm, lowerArm, hand; };
	static FModel* cachedModel = nullptr;
	static ArmChain cachedChains[2];
	static bool cachedValid = false;

	if (model != cachedModel)
	{
		static const char* const names[2][4] =
		{
			{ "bip_collar_R", "bip_upperArm_R", "bip_lowerArm_R", "bip_hand_R" },
			{ "bip_collar_L", "bip_upperArm_L", "bip_lowerArm_L", "bip_hand_L" }
		};
		static const int fallbackIdx[2][4] =
		{
			{ 22, 25, 29, 37 }, // right: collar, upperArm, lowerArm, hand
			{ 24, 27, 33, 42 }  // left:  collar, upperArm, lowerArm, hand
		};

		ArmChain resolved[2];
		bool usedFallback = false;
		for (int side = 0; side < 2; side++)
		{
			// All-or-nothing PER SIDE: never mix a name-resolved index with a hardcoded
			// fallback index on the same chain. A partially-matching rig (e.g. has
			// "bip_collar_R" but not "bip_upperArm_R") would otherwise silently splice in
			// the marine's hardcoded index for an unrelated joint on an unrelated model --
			// it would pass the later bounds check clean (still just an in-range index on
			// THIS model) and run the solve on the wrong bone with no diagnostic.
			int found[4];
			bool sideNameOk = true;
			for (int j = 0; j < 4; j++)
			{
				found[j] = model->FindJointByName(FName(names[side][j]));
				if (found[j] < 0) sideNameOk = false;
			}
			int* dst = &resolved[side].collar;
			for (int j = 0; j < 4; j++)
			{
				dst[j] = sideNameOk ? found[j] : fallbackIdx[side][j];
			}
			if (!sideNameOk) usedFallback = true;
		}

		static bool warnedNameFallback = false;
		if (usedFallback && !warnedNameFallback)
		{
			Printf("VR_UpdateArmIK: joint name lookup failed for one or more arm bones -- "
				"falling back to hardcoded marine joint indices (specific to that rig).\n");
			warnedNameFallback = true;
		}

		// Bounds-validate every resolved index against THIS model's joint count -- the
		// hardcoded fallback indices are specific to the marine's rig and would be garbage
		// on a different avatar model that still happens to pass the IQM/joint-count gate
		// above. (Meaningful only for the fallback case: a genuine FindJointByName hit can
		// never be out of range on the same model it was just looked up on.)
		bool boundsOk = true;
		for (int side = 0; side < 2 && boundsOk; side++)
		{
			int idxs[4] = { resolved[side].collar, resolved[side].upperArm, resolved[side].lowerArm, resolved[side].hand };
			for (int j = 0; j < 4; j++)
			{
				if (idxs[j] < 0 || idxs[j] >= jointCount) { boundsOk = false; break; }
			}
		}

		cachedChains[0] = resolved[0];
		cachedChains[1] = resolved[1];
		cachedValid = boundsOk;
		cachedModel = model;
	}

	if (!cachedValid)
	{
		{ static int s_gH=0; if (s_gH++<20) Printf("[VRIK_BAIL_H]\n"); }
		player->vr_ik_active = false;
		return;
	}
	ArmChain (&chains)[2] = cachedChains; // reference to the cached (or freshly re-resolved) chain array

	// ---- world -> model-local space setup for the hand targets (see COORDINATE FRAME above) ----
	// [XR] actorPos (player->mo->Pos()) is no longer needed: the feet-relative subtract it fed
	// IK_WorldToModelLocal is now inverted for free inside objectToWorldMatrix (translate at models.cpp).
	// [XR] UN-YAW BASIS FIX (proven by [VRIK_TGT2] range-of-motion data + vk_openxrdevice.cpp:5345): the
	// hand WORLD position from GetWeaponTransform is placed at world yaw = -90 + doomYaw + controllerRelYaw,
	// where doomYaw == player->mo->Angles.Yaw (the live pawn/HMD yaw). So the target must be un-yawed by the
	// PAWN yaw, NOT the decoupled vr_body_facing_yaw the renderer draws the body at. Un-yawing by the render
	// facing left a residual of (pawnYaw - vr_body_facing_yaw) whenever the head turns inside the 50-deg body
	// dead-zone -- which rotated the horizontal plane (the apparent "90-deg off / sign flip") and inflated
	// reach (worst ~+70% at a ~100-deg head/body gap). Because doomYaw is baked into the hand placement,
	// un-yawing by that SAME doomYaw cancels head rotation cleanly (no HMD leak). The vr_body_yaw(90) /
	// SpriteRotation mesh terms must NOT be added (the -90 baked into the hand placement is their counterpart
	// and already cancels; the baseframe shoulders are authored in the frame that nets to a plain -pawnYaw).
	// Also: vr_body_facing_yaw is updated AFTER this function in P_PlayerThink, so it lagged a tic -- another
	// reason the in-sync pawn yaw is the right basis. Across the full log this gives 10% of rows over reach-25
	// vs ~35% for the old render-facing basis.
	// [XR] HEAD-SWING FIX: un-yaw by the EXACT yaw the RENDERER draws the body at (r_data/models.cpp:241-253):
	//   valid facing -> vr_body_facing_yaw + vr_body_yaw + SpriteRotation   (DECOUPLED from the HMD)
	//   else         -> pawn Angles.Yaw   + vr_body_yaw + SpriteRotation
	// The pawn Angles.Yaw follows the headset, but the body is DRAWN at the decoupled facing. Un-yawing by
	// the pawn yaw (the old basis) rotated the model-local hand target by (headYaw - bodyFacingYaw) every
	// time the head turned inside the body dead-zone, so the extended arm swung opposite the head. Matching
	// the renderer's ACTUAL drawn yaw makes the IK frame track the DRAWN body -> head-turn no longer moves
	// the arm. (This replaces the earlier pure-pawnYaw basis, which was measured before the facing-decouple
	// and body-yaw/sprite terms were folded into the render path.)
	double renderBodyYaw = (player->vr_body_facing_valid ? (double)player->vr_body_facing_yaw
	                                                     : player->mo->Angles.Yaw.Degrees())
	                     + (double)vr_body_yaw + player->mo->SpriteRotation.Degrees();
	const DAngle   invYaw   = DAngle::fromDeg(-renderBodyYaw); // undo the renderer's drawn body yaw (models.cpp:241-253)
	// [XR] cosInvYaw/sinInvYaw are no longer consumed by the wrist path: IK_ControllerModelRot now
	// derives the controller orientation from the EXACT Finv (= swapYZ * objectToWorld^-1), the same
	// inverse the position path uses, instead of this pawn-yaw-only un-yaw. invYaw itself is still read
	// by the [VRIK_TGT2] diagnostic below; the cos/sin are retained [[maybe_unused]] as the documented
	// reference for IK_WorldToModelLocal's shared algebra.
	[[maybe_unused]] const double   cosInvYaw = invYaw.Cos();
	[[maybe_unused]] const double   sinInvYaw = invYaw.Sin();

	// Real per-hand tracked targets. NOTE: player->mo->AttackPos is deliberately NOT used
	// here for either hand, even though the design notes floated it for the main hand --
	// AttackPos is set from PosAtZ(shootz) (common/rendering/hwrenderer/data/hw_vrmodes.cpp,
	// VRMode::SetUp), i.e. its X/Y are pinned to the actor's OWN center and only Z tracks
	// the headset height; it's a hitscan ray origin, not a 3D hand position, and would
	// leave the arms unable to reach sideways at all. GetWeaponTransform(hand) is the real
	// per-hand tracked transform -- the same source VR_UpdateGravityGloves and
	// VR_UpdateHardpoints (both this file) already use for both hands -- so it's used for
	// BOTH main and off hand here too.
	// [XR] Use the mode that is ACTUALLY VR. GetVRModeCached(false) returns the MONO mode
	// (hw_vrmodes.cpp:688 -- !toscreen -> mode 0), whose GetHandTransform returns false -- which is
	// exactly why the arms never got hand targets (haveTarget=0,0 every tic, gate i). In the playsim
	// tic the (true) cache resolves to the real OpenXR mode, whose GetHandTransform is populated from
	// the live controller pose. Prefer whichever mode IsVR(); fall back to (false) so non-VR is safe.
	const VRMode* vrmode = VRMode::GetVRModeCached(true);
	if (!vrmode->IsVR()) vrmode = VRMode::GetVRModeCached(false);
	bool rightHanded = vr_control_scheme < 10; // same remap GetWeaponTransform itself applies internally
	int rightHandEnum = rightHanded ? VR_MAINHAND : VR_OFFHAND;
	int leftHandEnum  = rightHanded ? VR_OFFHAND  : VR_MAINHAND;

	VSMatrix rightXf, leftXf;
	bool haveTarget[2];
	haveTarget[0] = vrmode->GetWeaponTransform(&rightXf, rightHandEnum);
	haveTarget[1] = vrmode->GetWeaponTransform(&leftXf,  leftHandEnum);

	// [XR hand-world collision] Clamp a hand's IK target to the wall when VR_UpdateHandCollision (this
	// file, runs earlier the same tic) found it touching solid geometry -- keeps the rendered hand from
	// clipping through walls. Deliberately placed HERE, upstream of everything below (including the
	// hs_foregrip pin a few lines down): overriding rightXf/leftXf's translation before either matrix is
	// consumed means a clamped, non-foregripping hand flows into the rest of the solve for free, with no
	// second write site. CONTRACT: a foregripping OFF-hand stays pinned to the gun, never the wall --
	// excluded here so this and the foregrip pin can never fight over the same hand in the same tic.
	// m[12]=X, m[13]=Z(map-up), m[14]=Y -- same layout every GetWeaponTransform consumer in this file
	// uses; const_cast<float*>(xf.get()) matches the existing write-through pattern used below (~line
	// 3399's rotation-matrix build) rather than adding a new mutator to VSMatrix.
	if (vr_hand_ik_clamp)
	{
		if (haveTarget[0] && player->vr_hand_touching_wall[rightHandEnum] &&
			!(rightHandEnum == VR_OFFHAND && player->vr_foregrip_engaged))
		{
			const DVector3& c = player->vr_hand_collision_clamp_pos[rightHandEnum];
			float* rm = const_cast<float*>(rightXf.get());
			rm[12] = (float)c.X; rm[13] = (float)c.Z; rm[14] = (float)c.Y;
		}
		if (haveTarget[1] && player->vr_hand_touching_wall[leftHandEnum] &&
			!(leftHandEnum == VR_OFFHAND && player->vr_foregrip_engaged))
		{
			const DVector3& c = player->vr_hand_collision_clamp_pos[leftHandEnum];
			float* lm = const_cast<float*>(leftXf.get());
			lm[12] = (float)c.X; lm[13] = (float)c.Z; lm[14] = (float)c.Y;
		}
	}

	{ static int s_ikMode=0; if (s_ikMode++<20) Printf("[VRIK_MODE] IsVR=%d haveTarget=%d,%d\n", (int)vrmode->IsVR(), (int)haveTarget[0], (int)haveTarget[1]); }
	if (!haveTarget[0] && !haveTarget[1])
	{
		{ static int s_gI=0; if (s_gI++<20) Printf("[VRIK_BAIL_I] haveT=%d,%d\n", (int)haveTarget[0], (int)haveTarget[1]); }
		player->vr_ik_active = false;
		return;
	}

	// [XR] EXACT F^-1: target_baseframe = swapYZ * objectToWorldMatrix^-1 * controller_world_GL.
	// This single inversion of the renderer's OWN published matrix (g_xr_vrBodyObjectToWorld, models.cpp)
	// REPLACES the whole hand-rebuilt world->model-local pipeline that used to live here -- the un-yaw
	// (IK_WorldToModelLocal), the (.Z,.X,.Y) skeleton relabel, the bodyFit divide, and the forward-Y flip.
	// The renderer draws  world = objectToWorldMatrix * boneData[i] * vertex,  boneData[i] == Identity at
	// bind, and the uploaded vertex is swapYZ * v_file while baseframe[] is built from the RAW file TRS with
	// no swap -- so the exact baseframe-space -> GL-world map is  F = objectToWorldMatrix * swapYZ,  and its
	// inverse lands the controller in the SAME baseframe space (Z-up, shoulder Z~59) the two-bone solver
	// reads shoulderPos = IK_MatTranslation(baseframe[upperArm]) from. objectToWorldMatrix already contains
	// the drawn yaw, vr_body_z, and the Y/Z-swapped bodyScale, so all of those are inverted for free: NO
	// manual remap / feet-subtract / scale-divide / forward-flip. (invYaw is retained ABOVE only for the
	// [VRIK_TGT2] diagnostic; the wrist path IK_ControllerModelRot now uses this SAME Finv, not invYaw.)
	// swapYZ = row-swap of Y and Z, its own inverse (models_iqm.cpp).
	static const FLOATTYPE kSwapYZ[16] = { 1,0,0,0,  0,0,1,0,  0,1,0,0,  0,0,0,1 };
	VSMatrix swapYZ; swapYZ.loadMatrix(kSwapYZ);
	VSMatrix objToWorldInv;
	if (!g_xr_vrBodyObjToWorldValid || !g_xr_vrBodyObjectToWorld.inverseMatrix(objToWorldInv))
	{
		// No published body matrix yet (pre-first-render) or a singular transform (e.g. bodyScale 0):
		// hold the bind pose this tic rather than solving to garbage.
		{ static int s_gM=0; if (s_gM++<20) Printf("[VRIK_BAIL_M] valid=%d\n", (int)g_xr_vrBodyObjToWorldValid); }
		player->vr_ik_active = false;
		return;
	}
	// F^-1 = swapYZ * objectToWorldMatrix^-1  (VSMatrix A.multMatrix(B) => A = A*B, so this composes swapYZ
	// on the LEFT of the inverse -- applied to the point AFTER the inverse, which is what F^-1 requires).
	VSMatrix Finv = swapYZ;
	Finv.multMatrix(objToWorldInv);

	// [XR] bodyFitScale is kept ONLY for the [VRIK_TGT2] diagnostic printf below; it no longer scales the
	// target (bodyScale is inverted inside objectToWorldMatrix). Remove with the probe once tracking is
	// confirmed.
	float bodyFitScale = g_xr_vrBodyRenderScale;
	if (!(bodyFitScale > 0.05f && bodyFitScale < 8.0f)) bodyFitScale = (float)vr_body_scale;
	if (!(bodyFitScale > 0.05f && bodyFitScale < 8.0f)) bodyFitScale = 0.70f;

	FVector3 targetLocal[2]; // [0]=right,[1]=left, in baseframe space (X=lateral, Y=forward, Z=up)
	for (int s = 0; s < 2; s++)
	{
		if (!haveTarget[s]) continue;

		// [XR] HAND-TO-HOTSPOT PIN (IQM weapons). When the OFF hand is foregripping the weapon's authored
		// hs_foregrip bone, drive THAT hand's IK target from the foregrip WORLD point instead of the raw
		// controller. This lands the marine hand exactly ON the gun's foregrip and keeps it glued there as
		// two-hand aim swings the gun -- instead of floating at wherever the physical controller drifted.
		//   * Gated on player->vr_foregrip_engaged, which VR_CalculateTwoHanding (called ONE line before this
		//     in P_PlayerThink, same tic -> fresh) sets ONLY when VR_WeaponHotspotWorld returns a REAL authored
		//     hs_foregrip bone AND the off hand grips within vr_foregrip_radius AND the grip arbiter frees it.
		//     MD3 / unconverted weapons never author the bone -> never engage -> this path is byte-for-byte
		//     unchanged for them (no behavioral risk to the existing roster).
		//   * MAIN hand is intentionally NOT pinned: the gun rides the main-hand transform and hs_grip sits at
		//     the model origin (0,0,0), so the main hand already lands on the grip by construction.
		//   * vr_foregrip_world is Doom world (x, y, z-up); the point path below wants GL (x, up, z) -- i.e.
		//     GLx=Doom.x, GLy=Doom.z, GLz=Doom.y -- the exact inverse of VR_WeaponHotspotWorld's own
		//     handPos(m[12],m[14],m[13]) Doom read. Wrist ORIENTATION is left on the controller (unchanged):
		//     the off hand is physically at the grip when engaged, so its real orientation reads as a natural
		//     grip, and this avoids disturbing the verified IK_ControllerModelRot wrist path.
		const int   handEnum    = (s == 0) ? rightHandEnum : leftHandEnum;
		const bool  pinForegrip = player->vr_foregrip_engaged && (handEnum == VR_OFFHAND);

		FLOATTYPE ptGL[4];
		if (pinForegrip)
		{
			ptGL[0] = (FLOATTYPE)player->vr_foregrip_world[0]; // Doom.x   -> GL.x
			ptGL[1] = (FLOATTYPE)player->vr_foregrip_world[2]; // Doom.z-up-> GL.y
			ptGL[2] = (FLOATTYPE)player->vr_foregrip_world[1]; // Doom.y   -> GL.z
			ptGL[3] = (FLOATTYPE)1;
		}
		else
		{
			// GetWeaponTransform columns m[12..14] are ALREADY in GL layout (GL-X=Doom.x, GL-Y=up=Doom.z,
			// GL-Z=Doom.y) -- exactly objectToWorldMatrix's output axes -- so feed them straight in, NO reorder.
			// (This is the same per-hand controller world pos the old m[12],m[14],m[13] Doom read used; here we
			// keep the raw GL columns because objectToWorldMatrix^-1 wants GL, not Doom. AttackPos is NOT used:
			// its X/Y are actor-center-pinned, per the note above, so it can't drive sideways reach.)
			const FLOATTYPE* m = (s == 0) ? rightXf.get() : leftXf.get();
			ptGL[0] = m[12]; ptGL[1] = m[13]; ptGL[2] = m[14]; ptGL[3] = (FLOATTYPE)1;
		}
		FLOATTYPE outBase[4];
		Finv.multMatrixPoint(ptGL, outBase);                 // swapYZ * objectToWorldMatrix^-1 * (ctrl | foregrip)_GL
		targetLocal[s] = FVector3((float)outBase[0], (float)outBase[1], (float)outBase[2]);

		if (pinForegrip)
		{
			static int s_pinLog = 0;
			if (s_pinLog < 40)
			{
				s_pinLog++;
				Printf("[VRIK_PIN] off-hand -> hs_foregrip world=(%.1f,%.1f,%.1f) local=(%.1f,%.1f,%.1f)\n",
					player->vr_foregrip_world[0], player->vr_foregrip_world[1], player->vr_foregrip_world[2],
					targetLocal[s].X, targetLocal[s].Y, targetLocal[s].Z);
			}
		}
	}

	// [XR] Live CONSTANT nudge so the hand can be dialed exactly onto the controller in-headset -- absorbs any
	// fixed shift the frame math leaves (vr_body_z, feet-vs-mesh-origin, authoring). Dial vr_ik_target_off* in
	// the console until the model hand sits in the sphere; the value is then baked into autoexec.
	if ((float)vr_ik_target_offx != 0.f || (float)vr_ik_target_offy != 0.f || (float)vr_ik_target_offz != 0.f)
		for (int s = 0; s < 2; s++)
			if (haveTarget[s])
				targetLocal[s] += FVector3((float)vr_ik_target_offx, (float)vr_ik_target_offy, (float)vr_ik_target_offz);

	// [XR] PALM-SEAT: pull each hand's target back along model-FORWARD (+Y) by the fixed wrist->palm length so
	// the palm (not the wrist) lands on the controller/grip. See vr_ik_palm_back decl. A foregripping OFF hand
	// is EXCLUDED: it is already pinned to hs_foregrip's WORLD point (above), whose palm seating is handled by
	// that bone's own authored placement -- shifting it here would double-correct and slide it off the barrel.
	if ((float)vr_ik_palm_back != 0.f)
		for (int s = 0; s < 2; s++)
		{
			if (!haveTarget[s]) continue;
			const int handEnum = (s == 0) ? rightHandEnum : leftHandEnum;
			if (player->vr_foregrip_engaged && handEnum == VR_OFFHAND) continue;
			targetLocal[s].Y -= (float)vr_ik_palm_back;
		}

	// ---- per-side bind-pose geometry, read straight from the model's own baseframe
	// (model-local space, no swapYZ / inversebaseframe -- see COORDINATE FRAME above) ----
	FVector3 shoulderPos[2], elbowBindPos[2], handBindPos[2];
	FQuaternion collarBindRot[2], upperBindRot[2], lowerBindRot[2];
	float upperLen[2], forearmLen[2];

	for (int side = 0; side < 2; side++)
	{
		shoulderPos[side]  = IK_MatTranslation(baseframe[chains[side].upperArm]);
		elbowBindPos[side] = IK_MatTranslation(baseframe[chains[side].lowerArm]);
		handBindPos[side]  = IK_MatTranslation(baseframe[chains[side].hand]);

		collarBindRot[side] = IK_MatRotation(baseframe[chains[side].collar]);
		upperBindRot[side]  = IK_MatRotation(baseframe[chains[side].upperArm]);
		lowerBindRot[side]  = IK_MatRotation(baseframe[chains[side].lowerArm]);

		float derivedUpper = (float)(elbowBindPos[side] - shoulderPos[side]).Length();
		float derivedFore  = (float)(handBindPos[side] - elbowBindPos[side]).Length();

		// Fall back to the cvars (default 0 => "prefer the model", per hw_vrmodes.cpp's own
		// vr_ik_upperarm_len/vr_ik_forearm_len comments) ONLY if the derived length is
		// degenerate; if the cvar is also unset, fall back to the bind-length constants
		// this session measured directly off this same rig (~11.05 / ~9.44 map units).
		upperLen[side]   = (derivedUpper > 0.1f) ? derivedUpper : ((float)vr_ik_upperarm_len > 0.1f ? (float)vr_ik_upperarm_len : 11.05f);
		forearmLen[side] = (derivedFore  > 0.1f) ? derivedFore  : ((float)vr_ik_forearm_len  > 0.1f ? (float)vr_ik_forearm_len  : 9.44f);

		// [XR] Live overall ARM-LENGTH scale (vr_ik_arm_scale, default 1.0). Scales BOTH bones together so the
		// hands reach nearer/farther from the shoulder without changing bend behaviour -- the tuning slider for
		// "my arms feel too short/long". Guarded to a sane range so a mis-set value can't zero or explode reach.
		float armScale = (float)vr_ik_arm_scale;
		if (armScale < 0.5f) armScale = 0.5f; else if (armScale > 2.0f) armScale = 2.0f;
		upperLen[side]   *= armScale;
		forearmLen[side] *= armScale;
	}

	// [XR] [VRIK_TGT2] POST-CORRECTION probe (frame remap + body-fit scale applied). If reach ~= armLen
	// (~15-20 for a natural chest reach vs armLen 20.5), the target is now REACHABLE and the arms will
	// bend to it. If reach is still >> armLen, bodyFitScale is wrong: too-big reach -> bodyFitScale too
	// small (over-divided), too-small -> too large. Also prints the raw target so a HEIGHT-only offset
	// (Z far from ~45 while X/Y sane) is distinguishable from a uniform scale error. Remove once tracking.
	{
		// [XR] periodic (every 15 tics, up to 400 logs) so it captures a full RANGE OF MOTION, not just the
		// startup burst. Also logs the yaw state (fv=facing_valid / rYaw=renderYaw used / aYaw=raw pawn yaw)
		// so the arm-frame error AND any HMD-yaw fallback (fv=0 -> uses aYaw -> head leak) are both visible.
		static int s_ikTgt2Call = 0;
		static int s_ikTgt2 = 0;
		const bool doLog = ((s_ikTgt2Call++ % 15) == 0) && s_ikTgt2 < 400;
		for (int s = 0; s < 2 && doLog; s++)
		{
			if (!haveTarget[s]) continue;
			s_ikTgt2++;
			FVector3 d = targetLocal[s] - shoulderPos[s];
			Printf("[VRIK_TGT2] side=%d fv=%d invYaw=%.1f aYaw=%.1f bodyFit=%.3f tgt=(%.1f,%.1f,%.1f) shoulder=(%.1f,%.1f,%.1f) reach=%.1f armLen=%.1f\n",
				s, (int)player->vr_body_facing_valid, invYaw.Degrees(), player->mo->Angles.Yaw.Degrees(), bodyFitScale,
				targetLocal[s].X, targetLocal[s].Y, targetLocal[s].Z,
				shoulderPos[s].X, shoulderPos[s].Y, shoulderPos[s].Z,
				(float)d.Length(), upperLen[s] + forearmLen[s]);
		}
	}

	// [XR] TEMP probe: is the solve TARGET actually tracking your controller and reachable, or is it
	// collapsed (near the shoulder/origin -> arms stay at bind)? If tgt moves as you wave and reach ~=
	// armLen, the target is good and the solve math is the issue. If tgt is ~constant or reach is huge/
	// tiny, the world->model target conversion is wrong. Remove once arms track.
	{
		static int s_ikTgt = 0;
		if (s_ikTgt < 40 && haveTarget[0])
		{
			s_ikTgt++;
			FVector3 d = targetLocal[0] - shoulderPos[0];
			Printf("[VRIK_TGT] tgt=(%.1f,%.1f,%.1f) shoulder=(%.1f,%.1f,%.1f) handBind=(%.1f,%.1f,%.1f) reach=%.1f armLen=%.1f\n",
				targetLocal[0].X, targetLocal[0].Y, targetLocal[0].Z,
				shoulderPos[0].X, shoulderPos[0].Y, shoulderPos[0].Z,
				handBindPos[0].X, handBindPos[0].Y, handBindPos[0].Z,
				(float)d.Length(), upperLen[0] + forearmLen[0]);
		}
	}

	// Pole vector per side: outward + down + back, so elbows splay naturally instead of
	// clipping through the torso.
	//  - "outward" is derived from the two shoulders' own bind positions (points away from
	//    the body centerline regardless of which raw model axis happens to be left/right),
	//    not a hardcoded axis letter.
	//  - "back" is the actor's own facing undone by the SAME yaw rotation used above, which
	//    is mathematically always local (+1,0,0) after that conversion: Doom's yaw=0 forward
	//    is (cos,sin,0); undoing yaw always maps the actor's own forward onto local (1,0,0)
	//    (see IK_WorldToModelLocal above) -- so "back" = local (-1,0,0), a derived constant,
	//    not a modeling guess. The Y<->Z relabel never touches X, so this is unaffected by it.
	//  - "down" is local (0,-1,0) -- NOT (0,0,-1) -- per the Y<->Z relabel documented in the
	//    COORDINATE FRAME note above: local Y carries "world up" in this raw joint-local
	//    (Y-up) space, so "down" points along -Y here, not -Z.
	// The 1.0/0.6/0.35 weights are a reasoned starting shape (mostly outward, some sag,
	// slight back), not a balance decision -- these are the first thing to retune from a
	// render test if the elbows splay the wrong way (see the CALIBRATE note above).
	FVector3 lateralRtoL = shoulderPos[1] - shoulderPos[0];
	if (lateralRtoL.LengthSquared() < 1.e-6f) lateralRtoL = FVector3(0.f, 0.f, 1.f); // shoulders coincide -- arbitrary fallback (lateral now lives on local Z)
	lateralRtoL.MakeUnit();
	// [XR] pole vectors in the skeleton's Z-up baseframe frame (lateral=X, forward=Y, up=Z), matching
	// the target-remap above: "down" = -Z, "back" = -forward = -Y.  (Was (0,-1,0)/(-1,0,0) for the old
	// mismatched Y-up target frame -- see the FRAME FIX note where targetLocal is remapped.)
	const FVector3 downLocal(0.f, 0.f, -1.f);
	const FVector3 backLocal(0.f, -1.f, 0.f);
	FVector3 poleDir[2];
	poleDir[0] = lateralRtoL * -1.0f + downLocal * 0.6f + backLocal * 0.35f; // right: outward = -lateralRtoL
	poleDir[1] = lateralRtoL *  1.0f + downLocal * 0.6f + backLocal * 0.35f; // left:  outward = +lateralRtoL
	// [XR] The old poleDir horizontal negation (lockstep partner of the removed targetLocal 180) has been
	// REMOVED along with it. poleDir.X = lateralRtoL is a BODY-FIXED direction (built from the model's own
	// baseframe shoulder positions at shoulderPos[side] = IK_MatTranslation(baseframe[...upperArm]) above)
	// -- it is already in the render frame and rotates WITH the body, so it must NOT be yaw-flipped.
	// Flipping it was swapping every elbow to the INBOARD side ("forearm pivots to the wrong lateral
	// side"). With the target now solved in the render frame, the per-side outward signs at 0=-lateralRtoL
	// (right) / 1=+lateralRtoL (left) and back = -Y are already correct: the elbow splays outward and
	// bends down-and-back with no negation.
	poleDir[0].MakeUnit();
	poleDir[1].MakeUnit();

	// ---- solve + write both arms ----
	bool anySolved = false;
	for (int side = 0; side < 2; side++)
	{
		if (!haveTarget[side]) continue;

		FArmIKSolve solve;
		bool ok = IK_SolveTwoBoneArm(
			shoulderPos[side], elbowBindPos[side], handBindPos[side],
			targetLocal[side], poleDir[side],
			upperBindRot[side], lowerBindRot[side],
			upperLen[side], forearmLen[side],
			solve);
		if (!ok) continue;

		// Chain per point 4 of the design brief: upperArm's parent reference is the
		// COLLAR's bind rotation (its real parent in the render composition --
		// baseframe[Parent] inside CalculateBonesIQM); lowerArm's parent reference is the
		// UPPER ARM's OWN JUST-SOLVED world rotation, NOT its bind rotation, because the
		// upper arm no longer sits at its bind orientation once solved (matches the whip's
		// own parentWorldRot=worldRot chaining, vr_whip.zs:397-417 DriveModelBones).
		FQuaternion localUpper = collarBindRot[side].Inverse() * solve.upperWorldRot;
		FQuaternion localLower = solve.upperWorldRot.Inverse() * solve.lowerWorldRot;
		localUpper.MakeUnit();
		localLower.MakeUnit();

		// Rotation only -- translate/scale were already seeded from GetJointBindTRS above
		// and must stay untouched (bones don't stretch).
		TRS& upperPose = player->vr_ik_pose[chains[side].upperArm];
		upperPose.rotation = FVector4(localUpper.X, localUpper.Y, localUpper.Z, localUpper.W);
		// [XR] STRETCHY: scale the upperArm bone by solve.stretch. Bone scale propagates down the chain
		// (forearm + hand inherit it), so BOTH arm segments lengthen and the mesh hand reaches the
		// controller even when the target is past the marine's natural arm span. 1.0 = untouched (in reach);
		// the pose is re-seeded to bind every tic above, so no stretch ever lingers.
		// [XR] STRETCH the arm bones so the hand PINS to the controller no matter the marine's arm-to-height
		// proportion. The frame is now an exact inverse (head no longer drags the shoulders), so the target is
		// correct; the only thing that can leave the hand short is the arm being physically too short, and the
		// stretch closes that gap. Allow a generous 2.5x (covers any human reach vs marine proportion) and only
		// guard against NaN / runaway (finite check) so a bad tic can't explode the arm. Solve.stretch is 1.0
		// for in-reach targets, so this is a no-op until you actually extend past the marine's natural span.
		if (solve.stretch > 1.001f && solve.stretch < 100.0f)
		{
			float s = (solve.stretch > 2.5f) ? 2.5f : solve.stretch;
			upperPose.scaling = FVector3(s, s, s);
		}

		TRS& lowerPose = player->vr_ik_pose[chains[side].lowerArm];
		lowerPose.rotation = FVector4(localLower.X, localLower.Y, localLower.Z, localLower.W);

		// [XR] WRIST FOLLOWS CONTROLLER. Without this the hand bone stays at its bind rotation
		// (re-seeded from GetJointBindTRS every tic above) and the palm locks facing inward no
		// matter how the controller twists. The hand's parent in the bip chain is the lowerArm,
		// so -- exactly like localLower = upperWorldRot^-1 * lowerWorldRot above -- the local
		// (parent-relative) hand rotation is lowerArm's JUST-SOLVED model rot ^-1 times the
		// desired hand model rot. desiredHandModel is the controller orientation brought into
		// this same solve frame by IK_ControllerModelRot (same VSMatrix rightXf/leftXf as the
		// position target, same invYaw un-yaw + skeleton relabel). palmOffset is the fixed
		// bind-palm-vs-controller correction, exposed as vr_ik_hand_pitch/yaw/roll (deg) and
		// applied on the MODEL-space side so it rotates the hand about its own axes; dial it
		// in-headset. Guarded by vr_ik_hand_rot so it can be killed without touching reach/bend,
		// and it only touches .rotation (translate/scale stay at bind -- the wrist doesn't move,
		// so the reach the elbow just solved to is not disturbed).
		if (vr_ik_hand_rot)
		{
			const VSMatrix& handXf = (side == 0) ? rightXf : leftXf;
			FQuaternion ctrlModelRot;
			// [XR] Pass the SAME exact Finv (= swapYZ * objectToWorld^-1) the POSITION path built at the
				// top of this function, so the wrist orientation lands in the SAME baseframe as
				// solve.lowerWorldRot -- consistent with the hand position by construction. (Was
				// cosInvYaw/sinInvYaw: the deleted pawn-yaw-only un-yaw + relabel + forward-flip approximation.)
				if (IK_ControllerModelRot(handXf, Finv, ctrlModelRot))
			{
				FQuaternion palmOffset =
					FQuaternion::AxisAngle(FVector3(0.f, 0.f, 1.f), FAngle::fromDeg((double)vr_ik_hand_roll))  *
					FQuaternion::AxisAngle(FVector3(0.f, 1.f, 0.f), FAngle::fromDeg((double)vr_ik_hand_yaw))   *
					FQuaternion::AxisAngle(FVector3(1.f, 0.f, 0.f), FAngle::fromDeg((double)vr_ik_hand_pitch));
				// [XR] LEFT/offhand (side 1) bind palm is mirrored vs the right, so it gets its OWN extra
				// alignment (vr_ik_offhand_*) on top of the shared palmOffset; side 0 (right) = identity.
				FQuaternion offhandFlip = (side == 1)
					? FQuaternion::AxisAngle(FVector3(0.f, 0.f, 1.f), FAngle::fromDeg((double)vr_ik_offhand_roll))
					  * FQuaternion::AxisAngle(FVector3(0.f, 1.f, 0.f), FAngle::fromDeg((double)vr_ik_offhand_yaw))
					  * FQuaternion::AxisAngle(FVector3(1.f, 0.f, 0.f), FAngle::fromDeg((double)vr_ik_offhand_pitch))
					: FQuaternion(0.f, 0.f, 0.f, 1.f);
					FQuaternion desiredHandModel = ctrlModelRot * palmOffset * offhandFlip;
				FQuaternion localHand = solve.lowerWorldRot.Inverse() * desiredHandModel;
				localHand.MakeUnit();

				// [XR] JITTER FIX: exponential smoothing of the wrist rotation. Raw controller
				// tracking is noisy, and if consecutive-tic wrist quats flip sign the renderer
				// interpolates them "the long way" -> violent jitter. SLerp(prev, target, a) fixes
				// BOTH: it damps the noise (a<1) AND enforces sign-continuity (it negates `target`
				// when dot<0), so my per-tic outputs are continuous and the render interp stays short.
				// vr_ik_hand_smooth: 1 = raw/instant, lower = smoother/laggier. Per-hand static state;
				// this is first-person local-player only, so a static [2] is safe/transient.
				static FQuaternion s_prevHand[2];
				static bool s_prevHandValid[2] = { false, false };
				if (s_prevHandValid[side])
				{
					// [XR] RATE LIMIT + smoothing. The euler round-trip (vk_openxrdevice.cpp) makes the
					// controller orientation gimbal-jump INSTANTANEOUSLY -- huge one-tic deltas a real
					// wrist can't produce. Measure the shortest angle prev->target (2*acos|dot|, |dot| for
					// quaternion double-cover), and if the smoothed step would exceed vr_ik_hand_maxstep
					// degrees this tic, clamp the SLerp fraction so the wrist rotates AT MOST that far --
					// violent spikes become bounded, human-speed motion and get averaged out, while normal
					// motion (small delta) passes at the vr_ik_hand_smooth rate. SLerp also fixes sign
					// continuity so the render never interpolates "the long way".
					float qd = clamp((float)(s_prevHand[side] | localHand), -1.0f, 1.0f);
					float angRad = 2.0f * acosf(fabsf(qd));                 // shortest prev->target angle
					float t = clamp((float)vr_ik_hand_smooth, 0.05f, 1.0f); // base smoothing fraction
					float maxStepRad = (float)(fabs((double)vr_ik_hand_maxstep) * (M_PI / 180.0));
					if (maxStepRad > 1.e-4f && angRad > 1.e-4f && angRad * t > maxStepRad)
						t = maxStepRad / angRad;                            // cap this tic's rotation
					localHand = FQuaternion::SLerp(s_prevHand[side], localHand, t);
				}
				localHand.MakeUnit();
				s_prevHand[side] = localHand;
				s_prevHandValid[side] = true;

				TRS& handPose = player->vr_ik_pose[chains[side].hand];
				handPose.rotation = FVector4(localHand.X, localHand.Y, localHand.Z, localHand.W);
			}
		}

		anySolved = true;
	}

	// ---- [XR] HAND GRIP CURL: close the fingers around a held weapon ------------------------------------
	// The solve loop above posed the wrist but left every finger joint at its OPEN bind rotation (seeded at
	// the top from GetJointBindTRS). Here we curl those joints into a fist for whichever hand holds a weapon.
	// proceduralPose is PARENT-LOCAL, so post-multiplying a finger joint's local bind rotation by a curl about
	// local +X flexes it relative to its parent -- independent of the wrist pose the IK just solved. Finger
	// names resolved ONCE per model and cached (same discipline as the arm chain), -1 = joint absent -> skipped.
	if (vr_hand_grip && anySolved)
	{
		// [side][finger][segment] joint names. side 0=right,1=left. 4 fingers x 3 flex segments + thumb x 3.
		static const char* const fingerNames[2][5][3] =
		{
			{ // RIGHT
				{ "bip_index_0_R",  "bip_index_1_R",  "bip_index_2_R"  },
				{ "bip_middle_0_R", "bip_middle_1_R", "bip_middle_2_R" },
				{ "bip_ring_0_R",   "bip_ring_1_R",   "bip_ring_2_R"   },
				{ "bip_pinky_0_R",  "bip_pinky_1_R",  "bip_pinky_2_R"  },
				{ "bip_thumb_0_R",  "bip_thumb_1_R",  "bip_thumb_2_R"  },
			},
			{ // LEFT
				{ "bip_index_0_L",  "bip_index_1_L",  "bip_index_2_L"  },
				{ "bip_middle_0_L", "bip_middle_1_L", "bip_middle_2_L" },
				{ "bip_ring_0_L",   "bip_ring_1_L",   "bip_ring_2_L"   },
				{ "bip_pinky_0_L",  "bip_pinky_1_L",  "bip_pinky_2_L"  },
				{ "bip_thumb_0_L",  "bip_thumb_1_L",  "bip_thumb_2_L"  },
			},
		};
		static FModel* fingerCachedModel = nullptr;
		static int     fingerIdx[2][5][3];
		if (model != fingerCachedModel)
		{
			for (int s = 0; s < 2; s++)
				for (int fng = 0; fng < 5; fng++)
					for (int seg = 0; seg < 3; seg++)
						fingerIdx[s][fng][seg] = model->FindJointByNameCI(FName(fingerNames[s][fng][seg]));
			fingerCachedModel = model;
		}

		const FVector3 flexAxis(1.f, 0.f, 0.f);   // local +X = derived finger-flex axis (bones down -Z, spread X)
		for (int side = 0; side < 2; side++)
		{
			const int handEnum = (side == 0) ? rightHandEnum : leftHandEnum;
			AActor* heldWeapon = (handEnum == VR_MAINHAND) ? player->ReadyWeapon : player->OffhandWeapon;
			if (heldWeapon == nullptr) continue;   // empty hand stays open (no curl)

			for (int fng = 0; fng < 5; fng++)
			{
				const bool isThumb = (fng == 4);
				const float deg = isThumb ? (float)vr_hand_grip_thumb : (float)vr_hand_grip_curl;
				if (deg == 0.f) continue;
				const FQuaternion curl = FQuaternion::AxisAngle(flexAxis, FAngle::fromDeg((double)deg));
				for (int seg = 0; seg < 3; seg++)
				{
					const int ji = fingerIdx[side][fng][seg];
					if (ji < 0 || (unsigned)ji >= player->vr_ik_pose.Size()) continue;
					const FVector4& r = player->vr_ik_pose[ji].rotation;
					FQuaternion bind(r.X, r.Y, r.Z, r.W);
					FQuaternion out = bind * curl;   // local post-multiply: flex in the joint's own frame
					out.MakeUnit();
					player->vr_ik_pose[ji].rotation = FVector4(out.X, out.Y, out.Z, out.W);
				}
			}
		}
	}

	player->vr_ik_active = anySolved;

	// [XR] TEMP probe (throttled): confirms the IK reached the solve and what it produced, so we can
	// see WHY the arms do/don't move without another blind round-trip. Remove once arms track.
	{
		static int s_ikDbg = 0;
		if (s_ikDbg < 20)
		{
			s_ikDbg++;
			Printf("[VRIK] joints=%d haveTarget=%d,%d anySolved=%d poseSize=%d\n",
				model ? model->GetJointCount() : -1, (int)haveTarget[0], (int)haveTarget[1],
				(int)anySolved, player->vr_ik_pose.Size());
		}
	}

	// ---- push the solved pose to the render path (the missing native glue) ----
	// vr_ik_pose is a private playsim buffer; the renderer ONLY reads
	// modelData->proceduralPose (r_data/models.cpp:577). Copy it across and flip
	// useProceduralPose so ProcessModelFrame consumes the solved bones this frame. On a
	// tic with no valid solve, clear the flag so the avatar reverts to its bind pose.
	// modelData is guaranteed non-null here (early-return gate at ~2415). NOTE: the avatar
	// MODELDEF block must also carry the `modelsareattachments` keyword for these bones to
	// upload to the GPU (models.cpp:635) -- +DECOUPLEDANIMATIONS alone fails on a 0-anim IQM.
	if (anySolved)
	{
		modelData->proceduralPose = player->vr_ik_pose;   // TArray<TRS> copy; identical element type
		modelData->useProceduralPose = true;
	}
	else
	{
		modelData->useProceduralPose = false;
	}
}

void VR_UpdateClimbing(player_t* player)
{
    if (!player || !player->mo || !VRMode::GetVRModeCached(false)) return;
    if (vr_climb_radius <= 0) return;

    bool anyGrip = false;
    DVector3 climbDelta(0, 0, 0);

    for (int hand = 0; hand < 2; hand++)
    {
        bool isGripPressed = VR_IsGripPressed(player, hand);
        
        if (isGripPressed)
        {
            // Check cache
            if (player->vr_climbing_cache_time[hand] < player->mo->Level->time - 10)
            {
                // Cache miss or expired, rebuild cache
                player->vr_climbing_cache_time[hand] = player->mo->Level->time;
                memset(player->vr_climbing_lines[hand], 0, sizeof(player->vr_climbing_lines[hand]));
                
                VSMatrix handTransform;
                if (VRMode::GetVRModeCached(false)->GetWeaponTransform(&handTransform, hand))
                {
                    // Map HW to world
                    const float* m = handTransform.get();
                    DVector3 handPos(m[12], m[14], m[13]);
                    
                    FBoundingBox box(handPos.X, handPos.Y, vr_climb_radius);
                    FBlockLinesIterator it(player->mo->Level, box);
                    line_t* line;
                    int cache_idx = 0;

                    // [XR pick-climb] If this hand holds an Ice Hook, ANY solid wall is climbable (not just
                    // KEYWORDS.json-tagged textures) -- picks bite anything but liquid, and liquids are floor
                    // planes, so wall-climbing excludes them by construction. Reuses the whole climb pipeline
                    // (velocity-driven pull below) + the CHANGE 1 fling-safety, so no separate code path.
                    AActor* handWeapon = nullptr;
                    if (hand == VR_PhysicalHandForSlot(VR_MAINHAND))      handWeapon = player->ReadyWeapon;
                    else if (hand == VR_PhysicalHandForSlot(VR_OFFHAND))  handWeapon = player->OffhandWeapon;
                    static PClass* const icehookCls = PClass::FindClass("IceHook");
                    const bool holdingPick = (handWeapon && icehookCls && handWeapon->IsKindOf(icehookCls));

                    while ((line = it.Next()) && cache_idx < 10)
                    {
                        float speedMult = 1.0f;
                        bool climbable = KeywordDispatcher::IsClimbable(line->Keywords, speedMult);
                        if (!climbable && line->sidedef[0] != nullptr)
                        {
                            FGameTexture* tex = TexMan.GetGameTexture(line->sidedef[0]->GetTexture(side_t::mid));
                            if (tex)
                            {
                                climbable = KeywordDispatcher::IsClimbable("climb:" + tex->GetName(), speedMult);
                            }
                        }
                        
                        if (!climbable && line->frontsector)
                        {
                            climbable = KeywordDispatcher::IsClimbable(line->frontsector->Keywords, speedMult);
                        }
                        if (!climbable && line->backsector)
                        {
                            climbable = KeywordDispatcher::IsClimbable(line->backsector->Keywords, speedMult);
                        }

                        // [XR pick-climb] Holding an Ice Hook: any SOLID wall (one-sided, or impassable
                        // two-sided) counts, so you can scale any surface -- the ice-climb fantasy.
                        if (!climbable && holdingPick &&
                            (line->sidedef[1] == nullptr || (line->flags & ML_BLOCKING)))
                        {
                            climbable = true;
                            speedMult = 1.0f;
                        }

                        if (climbable)
                        {
                            player->vr_climbing_lines[hand][cache_idx++] = line;
                            player->vr_climbing_speed[hand] = speedMult; // I'll use a local var for now if I didn't add it to struct
                        }
                    }
                }
            }

            // If we have a climbable line in cache
            if (player->vr_climbing_lines[hand][0] != nullptr)
            {
                if (!player->vr_was_grip_pressed[hand]) {
                    VR_HapticEvent("grip_climb", hand == 0 ? 1 : 2, 60, 0, 0);
                }

                anyGrip = true;
                DVector3 handVel;
                if (VRMode::GetVRModeCached(false)->GetHandVelocity(hand, handVel))
                {
                    DVector3 mapVel(handVel.X, handVel.Z, handVel.Y);
                    
                    // Apply speed multiplier from keywords
                    float speedMult = 1.0f;
                    // We just use the first line's speed for simplicity
                    KeywordDispatcher::IsClimbable(player->vr_climbing_lines[hand][0]->Keywords, speedMult);

                    DVector3 move = mapVel * (double)speedMult;
                    climbDelta -= move;

                    // Surface texture haptics
                    player->vr_climbing_haptic_dist[hand] += move.Length();
                    if (player->vr_climbing_haptic_dist[hand] > 8.0) // Pulse every 8 units
                    {
                        VR_HapticEvent("climb_texture", hand == 0 ? 1 : 2, 20, 0, 0);
                        player->vr_climbing_haptic_dist[hand] = 0;
                    }
                }
            }
        }
        else
        {
            player->vr_climbing_cache_time[hand] = 0;
            memset(player->vr_climbing_lines[hand], 0, sizeof(player->vr_climbing_lines[hand]));
        }
    }

    // Set climbing state per-hand but also handle gravity globally
    bool isClimbingOverall = false;
    for (int hand = 0; hand < 2; hand++)
    {
        player->vr_is_climbing[hand] = (anyGrip && player->vr_climbing_lines[hand][0] != nullptr && VRMode::GetVRModeCached(false)->IsGripPressed(hand));
        if (player->vr_is_climbing[hand]) isClimbingOverall = true;
    }

    // [XR fling fix / CHANGE 1] Is a live whip pendulum-swing owning the pawn this tic? If so climb YIELDS:
    // it writes NEITHER pawn Vel NOR the gravity flag, leaving owner.Vel exactly as the whip's taut-line
    // integrator set it and bNoGravity owned by the whip. Guarantees at most ONE Vel writer per tic (the
    // whip), closing the climb-vs-swing fling AND the gravity-strip-out-from-under-a-live-pendulum jerk.
    const bool whipSwingLive = P_VRWhipSwingActive(player);

    if (isClimbingOverall && !whipSwingLive)
    {
        player->mo->flags |= MF_NOGRAVITY;
        player->mo->Vel = climbDelta * vr_climb_speed_mult;
    }
    else if (!isClimbingOverall && !whipSwingLive)
    {
        player->mo->flags &= ~MF_NOGRAVITY;
    }
    // else (whipSwingLive): climb touches neither Vel nor MF_NOGRAVITY -- the whip owns both this tic.
}

// [XR interaction glows] Shared primitive for every "QoL helper glow" feature below: pushes one
// airborne/billboard FGlowSpot (same construction AddGlowPanel uses, vmthunks.cpp) at a world
// position. Unlike VR_UpdateHandCollision's wall-plane spots (planeFlags=4, anchored to a line),
// this is for spots that float free in space or ride a moving actor/weapon -- grab targets,
// two-hand grips, hardpoints, reload hotspots, catch bursts, throw arcs. Level->GlowSpots is
// cleared every tic (p_tick.cpp) and rebuilt by every publisher, so callers just re-push each tic
// they want the glow visible -- no lifetime/staleness bookkeeping needed here.
static void VR_PushWorldGlow(FLevelLocals* lvl, const DVector3& pos, PalEntry color, double radius)
{
    if (!lvl || radius <= 0.0) return;
    FGlowSpot gs;
    gs.center = DVector2(pos.X, pos.Y);
    gs.radius = radius;
    gs.color = color;
    gs.wipeType = 0;
    gs.wipeProgress = 0.0;
    gs.wipeDir = DVector2(0, 0);
    gs.planeFlags = 0;
    gs.zoff = pos.Z;
    gs.gflags = 1; // billboard/airborne, same as AddGlowPanel
    lvl->GlowSpots.Push(gs);
}

// [XR hand-world collision] Per-tic proximity check of each VR hand against solid wall linedefs,
// reusing the exact blockmap query VR_UpdateClimbing already runs (FBoundingBox + FBlockLinesIterator)
// -- broad-phase, not a new spatial-query path. On approach/contact this feeds a growing wall-glow
// spot (native Level->GlowSpots registry, hw_walls.cpp WALL bit -- ZERO dynamic lights, see
// glow-hard-constraint), tinted differently on KEYWORDS-tagged climbable lines vs plain solid walls
// (most solid walls are NOT climb-tagged, so this tells the player which is which before they grip),
// and a haptic bump on first contact. vr_hand_touching_wall[hand] + vr_hand_collision_clamp_pos[hand]
// are published on the player; VR_UpdateArmIK (below) reads both to clamp the rendered hand at the
// wall surface when vr_hand_ik_clamp is on.
void VR_UpdateHandCollision(player_t* player)
{
    if (!player || !player->mo || !VRMode::GetVRModeCached(false)) return;
    if (!vr_hand_collision) return;
    if (vr_hand_collision_radius <= 0) return;

    for (int hand = 0; hand < 2; hand++)
    {
        VSMatrix handTransform;
        if (!VRMode::GetVRModeCached(false)->GetWeaponTransform(&handTransform, hand))
        {
            player->vr_hand_collision_last_valid[hand] = false;
            player->vr_hand_touching_wall[hand] = false;
            continue;
        }

        const float* m = handTransform.get();
        DVector3 handPos(m[12], m[14], m[13]);

        // Search out to the largest of the relevant radii (collision, real climb range, glow ramp-in) so
        // a climbable wall further than the plain collision radius but within climb range still gets found.
        const double searchRadius = max<double>(max<double>(vr_hand_collision_radius, vr_climb_radius), vr_hand_glow_range);
        FBoundingBox box(handPos.X, handPos.Y, searchRadius);
        FBlockLinesIterator it(player->mo->Level, box);
        line_t* line;

        double bestDist = searchRadius;
        line_t* bestLine = nullptr;
        DVector2 bestPoint;
        bool bestClimbable = false;

        while ((line = it.Next()))
        {
            // Only solid (blocking) geometry counts as "world" to bump against -- open two-sided
            // passages (doorways, windows you can reach through) should not glow/block.
            const bool solid = (line->sidedef[1] == nullptr) || (line->flags & ML_BLOCKING);
            if (!solid) continue;

            const DVector2 v1 = line->v1->fPos();
            const DVector2 v2 = line->v2->fPos();
            const DVector2 seg = v2 - v1;
            const double segLenSq = seg.LengthSquared();
            if (segLenSq <= 0.0) continue;

            double t = ((handPos.X - v1.X) * seg.X + (handPos.Y - v1.Y) * seg.Y) / segLenSq;
            t = clamp<double>(t, 0.0, 1.0);
            const DVector2 closest = v1 + seg * t;
            const double dist = (DVector2(handPos.X, handPos.Y) - closest).Length();

            if (dist < bestDist)
            {
                // Z-gate: only count the wall if it actually spans the hand's height (uses whichever
                // sector is present so one-sided exterior lines still gate correctly).
                sector_t* sec = line->frontsector ? line->frontsector : line->backsector;
                if (sec)
                {
                    const double floorZ = sec->floorplane.ZatPoint(closest);
                    const double ceilZ = sec->ceilingplane.ZatPoint(closest);
                    if (handPos.Z < floorZ - 4.0 || handPos.Z > ceilZ + 4.0) continue;
                }

                bestDist = dist;
                bestLine = line;
                bestPoint = closest;

                // [XR] Same climbable test VR_UpdateClimbing runs (Keywords -> "climb:<tex>" -> sector
                // Keywords) so the glow tells the player "this one is grippable" before they commit a
                // grip -- most solid walls are NOT keyword-tagged, so this needs its own check per-line
                // rather than reusing climb's per-hand cache (which is grip-gated and only built on squeeze).
                float speedMult = 1.0f;
                bool climbable = KeywordDispatcher::IsClimbable(line->Keywords, speedMult);
                if (!climbable && line->sidedef[0] != nullptr)
                {
                    FGameTexture* tex = TexMan.GetGameTexture(line->sidedef[0]->GetTexture(side_t::mid));
                    if (tex) climbable = KeywordDispatcher::IsClimbable("climb:" + tex->GetName(), speedMult);
                }
                if (!climbable && line->frontsector) climbable = KeywordDispatcher::IsClimbable(line->frontsector->Keywords, speedMult);
                if (!climbable && line->backsector)  climbable = KeywordDispatcher::IsClimbable(line->backsector->Keywords, speedMult);
                bestClimbable = climbable;
            }
        }

        // A climbable line's REAL contact threshold is vr_climb_radius (the actual grab-distance the
        // climb system grips at, VR_UpdateClimbing above) -- not the generic wall-bump radius. A player
        // reaching for a climbable wall needs the glow to promise "you are in real climb range", so the
        // two ranges must be evaluated (and colored) independently, not collapsed onto one radius.
        const double contactRadius = bestClimbable ? (double)vr_climb_radius : (double)vr_hand_collision_radius;

        const bool wasTouching = player->vr_hand_touching_wall[hand];
        const bool touching = (bestLine != nullptr) && (bestDist <= contactRadius);
        player->vr_hand_touching_wall[hand] = touching;

        if (touching && !wasTouching)
        {
            VR_HapticEvent(bestClimbable ? "hand_climb_range" : "hand_wall_touch", hand == 0 ? 1 : 2, 40, 0, 0);
        }

        // [XR] The IK clamp target: when touching, pull the hand's XY back to sit exactly at
        // contactRadius from the wall point along the hand->wall direction (keeps the real
        // controller's Z so vertical reach still tracks naturally) -- read by VR_UpdateArmIK.
        if (touching)
        {
            DVector2 fromWall = DVector2(handPos.X, handPos.Y) - bestPoint;
            const double fromWallLen = fromWall.Length();
            if (fromWallLen > 1e-6) fromWall *= (contactRadius / fromWallLen);
            else fromWall = DVector2(contactRadius, 0.0);
            player->vr_hand_collision_clamp_pos[hand] = DVector3(bestPoint.X + fromWall.X, bestPoint.Y + fromWall.Y, handPos.Z);
        }
        else
        {
            player->vr_hand_collision_clamp_pos[hand] = handPos;
        }

        if (vr_hand_collision_glow && bestLine != nullptr)
        {
            // 0 = just entered glow range, 1 = at the real contact threshold for THIS surface type
            // (climb radius for climbable, collision radius for plain solid -- see contactRadius above).
            const double range = max<double>(max<double>(vr_hand_glow_range, contactRadius), 0.001);
            const double t = clamp<double>(1.0 - bestDist / range, 0.0, 1.0);
            const double radius = vr_hand_glow_min_radius + (vr_hand_glow_max_radius - vr_hand_glow_min_radius) * t;

            FGlowSpot gs;
            gs.center = bestPoint;
            gs.radius = radius;
            gs.color = PalEntry((int)(bestClimbable ? vr_hand_glow_climb_color : vr_hand_glow_color));
            gs.wipeType = 0;
            gs.wipeProgress = 0.0;
            gs.wipeDir = DVector2(0, 0);
            gs.planeFlags = 4; // WALL bit (hw_walls.cpp)
            player->mo->Level->GlowSpots.Push(gs);
        }

        player->vr_hand_collision_last_pos[hand] = handPos;
        player->vr_hand_collision_last_valid[hand] = true;
    }
}

// [XR hardpoint draw/stow glow] Per-tic proximity glow so players can see where their holster/ability
// mounts actually are without memorizing the motion. Mirrors the EXACT distance test IsHardpointNear
// (vmthunks_actors.cpp) already runs, but gets each slot's world position via the shared
// VR_ResolveHardpointWorldPos (vr_hardpoint.h) instead of recomputing the anchor math here. Body-anchored
// slots move with the player and wrist-anchored ones with the other hand -- both are fine to recompute
// fresh every tic since GlowSpots itself is rebuilt every tic (p_tick.cpp).
void VR_UpdateHardpointGlow(player_t* player)
{
    if (!player || !player->mo || !vr_hardpoint_glow_enable) return;
    if (player->vr_hardpoint_count <= 0) return;

    for (int hand = 0; hand < 2; hand++)
    {
        VSMatrix handTransform;
        if (!VRMode::GetVRModeCached(false)->GetWeaponTransform(&handTransform, hand)) continue;
        const float* m = handTransform.get();
        DVector3 handPos(m[12], m[14], m[13]);

        for (int i = 0; i < player->vr_hardpoint_count; i++)
        {
            const auto& slot = player->vr_hardpoints[i];
            if (!slot.enabled) continue;
            if (slot.hand != -1 && slot.hand != hand) continue;

            double slotPos[3];
            if (!VR_ResolveHardpointWorldPos(player, i, hand, slotPos)) continue;
            DVector3 pos(slotPos[0], slotPos[1], slotPos[2]);

            const double reach = (slot.radius > 0.f) ? (double)slot.radius : (double)vr_hardpoint_radius;
            const double range = max<double>(max<double>(vr_hardpoint_glow_range, reach), 0.001);
            const double dist = (handPos - pos).Length();
            if (dist > range) continue;

            const double t = clamp<double>(1.0 - dist / range, 0.0, 1.0);
            const double glowRadius = vr_hardpoint_glow_min_radius + (vr_hardpoint_glow_max_radius - vr_hardpoint_glow_min_radius) * t;
            const PalEntry color = (slot.anchor == HP_ANCHOR_WRIST) ? PalEntry((int)vr_hardpoint_glow_color_wrist) : PalEntry((int)vr_hardpoint_glow_color_body);
            VR_PushWorldGlow(player->mo->Level, pos, color, glowRadius);
        }
    }
}

void P_PredictionLerpReset()
{
	LastPredictedPosition = DVector3{};
	LastPredictedPortalGroup = 0;
	LastPredictedTic = -1;
}

void P_LerpCalculate(AActor* pmo, const DVector3& from, DVector3 &result, float scale, float threshold, float minMove)
{
	DVector3 diff = pmo->Pos() - from;
	diff.XY() += pmo->Level->Displacements.getOffset(pmo->Sector->PortalGroup, pmo->Level->PointInSector(from.XY())->PortalGroup);
	double dist = diff.Length();
	if (dist <= max<float>(threshold, minMove))
	{
		result = pmo->Pos();
		return;
	}

	diff /= dist;
	diff *= min<double>(dist * (1.0f - scale), dist - minMove);
	result = pmo->Vec3Offset(-diff.X, -diff.Y, -diff.Z);
}

template<class nodetype, class linktype>
void BackupNodeList(AActor *act, nodetype *head, nodetype *linktype::*otherlist, TArray<nodetype*, nodetype*> &prevbackup, TArray<linktype *, linktype *> &otherbackup)
{
	// The ordering of the touching_sectorlist needs to remain unchanged
	// Also store a copy of all previous sector_thinglist nodes
	prevbackup.Clear();
	otherbackup.Clear();

	for (auto mnode = head; mnode != nullptr; mnode = mnode->m_tnext)
	{
		otherbackup.Push(mnode->m_sector);

		for (auto snode = mnode->m_sector->*otherlist; snode; snode = snode->m_snext)
		{
			if (snode->m_thing == act)
			{
				prevbackup.Push(snode->m_sprev);
				break;
			}
		}
	}
}

template<class nodetype, class linktype>
nodetype *RestoreNodeList(AActor *act, nodetype *head, nodetype *linktype::*otherlist, TArray<nodetype*, nodetype*> &prevbackup, TArray<linktype *, linktype *> &otherbackup)
{
	// Destroy old refrences
	nodetype *node = head;
	while (node)
	{
		node->m_thing = NULL;
		node = node->m_tnext;
	}

	// Make the sector_list match the player's touching_sectorlist before it got predicted.
	P_DelSeclist(head, otherlist);
	head = NULL;
	for (auto i = otherbackup.Size(); i-- > 0;)
	{
		head = P_AddSecnode(otherbackup[i], act, head, otherbackup[i]->*otherlist);
	}
	//act->touching_sectorlist = ctx.sector_list;	// Attach to thing
	//ctx.sector_list = NULL;		// clear for next time

	// In the old code this block never executed because of the commented-out NULL assignment above. Needs to be checked
	node = head;
	while (node)
	{
		if (node->m_thing == NULL)
		{
			if (node == head)
				head = node->m_tnext;
			node = P_DelSecnode(node, otherlist);
		}
		else
		{
			node = node->m_tnext;
		}
	}

	nodetype *snode;

	// Restore sector thinglist order
	for (auto i = otherbackup.Size(); i-- > 0;)
	{
		// If we were already the head node, then nothing needs to change
		if (prevbackup[i] == NULL)
			continue;

		for (snode = otherbackup[i]->*otherlist; snode; snode = snode->m_snext)
		{
			if (snode->m_thing == act)
			{
				if (snode->m_sprev)
					snode->m_sprev->m_snext = snode->m_snext;
				else
					snode->m_sector->*otherlist = snode->m_snext;
				if (snode->m_snext)
					snode->m_snext->m_sprev = snode->m_sprev;

				snode->m_sprev = prevbackup[i];

				// At the moment, we don't exist in the list anymore, but we do know what our previous node is, so we set its current m_snext->m_sprev to us.
				if (snode->m_sprev->m_snext)
					snode->m_sprev->m_snext->m_sprev = snode;
				snode->m_snext = snode->m_sprev->m_snext;
				snode->m_sprev->m_snext = snode;
				break;
			}
		}
	}
	return head;
}

void P_PredictPlayer (player_t *player)
{
	int maxtic;

	if (singletics ||
		demoplayback ||
		player->mo == NULL ||
		player != player->mo->Level->GetConsolePlayer() ||
		player->playerstate != PST_LIVE ||
		!netgame ||
		/*player->morphTics ||*/
		(player->cheats & CF_PREDICTING))
	{
		return;
	}

	maxtic = maketic;

	if (gametic == maxtic)
	{
		return;
	}

	FRandom::SaveRNGState(PredictionRNG);

	// Save original values for restoration later
	PredictionPlayerBackup.CopyFrom(*player, false);

	auto act = player->mo;
	PredictionActor = player->mo;
	PredictionActorBackupArray.Resize(act->GetClass()->Size);
	memcpy(PredictionActorBackupArray.Data(), &act->snext, act->GetClass()->Size - ((uint8_t *)&act->snext - (uint8_t *)act));

	// Since this is a DObject it needs to have its fields backed up manually for restore, otherwise any changes
	// to it will be permanent while predicting. This is now auto-created on pawns to prevent creation spam.
	if (act->ViewPos != nullptr)
	{
		PredictionViewPosBackup.Pos = act->ViewPos->Offset;
		PredictionViewPosBackup.Flags = act->ViewPos->Flags;
	}

	act->flags &= ~MF_PICKUP;
	act->flags2 &= ~MF2_PUSHWALL;
	player->cheats |= CF_PREDICTING;

	BackupNodeList(act, act->touching_sectorlist, &sector_t::touching_thinglist, PredictionTouchingSectors_sprev_Backup, PredictionTouchingSectorsBackup);
	BackupNodeList(act, act->touching_rendersectors, &sector_t::touching_renderthings, PredictionRenderSectors_sprev_Backup, PredictionRenderSectorsBackup);
	BackupNodeList(act, act->touching_sectorportallist, &sector_t::sectorportal_thinglist, PredictionPortalSectors_sprev_Backup, PredictionPortalSectorsBackup);
	BackupNodeList(act, act->touching_lineportallist, &FLinePortal::lineportal_thinglist, PredictionPortalLines_sprev_Backup, PredictionPortalLinesBackup);

	// Keep an ordered list off all actors in the linked sector.
	PredictionSectorListBackup.Clear();
	if (!(act->flags & MF_NOSECTOR))
	{
		AActor *link = act->Sector->thinglist;
		
		while (link != NULL)
		{
			PredictionSectorListBackup.Push(link);
			link = link->snext;
		}
	}

	// Blockmap ordering also needs to stay the same, so unlink the block nodes
	// without releasing them. (They will be used again in P_UnpredictPlayer).
	FBlockNode *block = act->BlockNode;

	while (block != NULL)
	{
		if (block->NextActor != NULL)
		{
			block->NextActor->PrevActor = block->PrevActor;
		}
		*(block->PrevActor) = block->NextActor;
		block = block->NextBlock;
	}
	act->BlockNode = NULL;

	// This essentially acts like a mini P_Ticker where only the stuff relevant to the client is actually
	// called. Call order is preserved.
	bool rubberband = false, rubberbandLimit = false;
	DVector3 rubberbandPos = {};
	const bool canRubberband = LastPredictedTic >= 0 && cl_rubberband_scale > 0.0f && cl_rubberband_scale < 1.0f;
	const double rubberbandThreshold = max<float>(cl_rubberband_minmove, cl_rubberband_threshold);
	for (int i = gametic; i < maxtic; ++i)
	{
		// Make sure any portal paths have been cleared from the previous movement.
		R_ClearInterpolationPath();
		r_NoInterpolate = false;
		// Because we're always predicting, this will get set by teleporters and then can never unset itself in the renderer properly.
		player->mo->renderflags &= ~RF_NOINTERPOLATEVIEW;

		// Got snagged on something. Start correcting towards the player's final predicted position. We're
		// being intentionally generous here by not really caring how the player got to that position, only
		// that they ended up in the same spot on the same tick.
		if (canRubberband && LastPredictedTic == i)
		{
			DVector3 diff = player->mo->Pos() - LastPredictedPosition;
			diff += player->mo->Level->Displacements.getOffset(player->mo->Sector->PortalGroup, LastPredictedPortalGroup);
			double dist = diff.LengthSquared();
			if (dist >= EQUAL_EPSILON * EQUAL_EPSILON && dist > rubberbandThreshold * rubberbandThreshold)
			{
				rubberband = true;
				rubberbandPos = player->mo->Pos();
				rubberbandLimit = cl_rubberband_limit > 0.0f && dist > cl_rubberband_limit * cl_rubberband_limit;
			}
		}

		player->oldbuttons = player->cmd.ucmd.buttons;
		player->cmd = localcmds[i % LOCALCMDTICS];
		player->mo->ClearInterpolation();
		player->mo->ClearFOVInterpolation();
		P_PlayerThink(player);
		player->mo->CallTick();
	}

	if (rubberband)
	{
		DPrintf(DMSG_NOTIFY, "Prediction mismatch at (%.3f, %.3f, %.3f)\nExpected: (%.3f, %.3f, %.3f)\nCorrecting to (%.3f, %.3f, %.3f)\n",
			LastPredictedPosition.X, LastPredictedPosition.Y, LastPredictedPosition.Z,
			rubberbandPos.X, rubberbandPos.Y, rubberbandPos.Z,
			player->mo->X(), player->mo->Y(), player->mo->Z());

		if (rubberbandLimit)
		{
			// If too far away, instantly snap the player's view to their correct position.
			player->mo->renderflags |= RF_NOINTERPOLATEVIEW;
		}
		else
		{
			R_ClearInterpolationPath();
			player->mo->renderflags &= ~RF_NOINTERPOLATEVIEW;

			DVector3 snapPos = {};
			P_LerpCalculate(player->mo, LastPredictedPosition, snapPos, cl_rubberband_scale, cl_rubberband_threshold, cl_rubberband_minmove);
			player->mo->PrevPortalGroup = LastPredictedPortalGroup;
			player->mo->Prev = LastPredictedPosition;
			const double zOfs = player->viewz - player->mo->Z();
			player->mo->SetXYZ(snapPos);
			player->viewz = snapPos.Z + zOfs;
		}
	}

	// This is intentionally done after rubberbanding starts since it'll automatically smooth itself towards
	// the right spot until it reaches it.
	LastPredictedTic = maxtic;
	LastPredictedPosition = player->mo->Pos();
	LastPredictedPortalGroup = player->mo->Level->PointInSector(LastPredictedPosition)->PortalGroup;
}

void P_UnPredictPlayer ()
{
	player_t *player = &players[consoleplayer];

	if (player->cheats & CF_PREDICTING)
	{
		unsigned int i;
		AActor *act = player->mo;

		if (act != PredictionActor)
		{
			// Q: Can this happen? If yes, can we continue?
		}

		FRandom::RestoreRNGState(PredictionRNG);

		AActor *savedcamera = player->camera;

		auto &actInvSel = act->PointerVar<AActor*>(NAME_InvSel);
		auto InvSel = actInvSel;
		int inventorytics = player->inventorytics;
		const bool settings_controller = player->settings_controller;

		player->CopyFrom(PredictionPlayerBackup, false);

		player->settings_controller = settings_controller;
		// Restore the camera instead of using the backup's copy, because spynext/prev
		// could cause it to change during prediction.
		player->camera = savedcamera;

		FLinkContext ctx;
		// Unlink from all list, including those which are not being handled by UnlinkFromWorld.
		auto sectorportal_list = act->touching_sectorportallist;
		auto lineportal_list = act->touching_lineportallist;
		act->touching_sectorportallist = nullptr;
		act->touching_lineportallist = nullptr;

		act->UnlinkFromWorld(&ctx);
		memcpy(&act->snext, PredictionActorBackupArray.Data(), PredictionActorBackupArray.Size() - ((uint8_t *)&act->snext - (uint8_t *)act));

		if (act->ViewPos != nullptr)
		{
			act->ViewPos->Offset = PredictionViewPosBackup.Pos;
			act->ViewPos->Flags = PredictionViewPosBackup.Flags;
		}

		// The blockmap ordering needs to remain unchanged, too.
		// Restore sector links and refrences.
		// [ED850] This is somewhat of a duplicate of LinkToWorld(), but we need to keep every thing the same,
		// otherwise we end up fixing bugs in blockmap logic (i.e undefined behaviour with polyobject collisions),
		// which we really don't want to do here.
		if (!(act->flags & MF_NOSECTOR))
		{
			sector_t *sec = act->Sector;
			AActor *me, *next;
			AActor **link;// , **prev;

			// The thinglist is just a pointer chain. We are restoring the exact same things, so we can NULL the head safely
			sec->thinglist = NULL;

			for (i = PredictionSectorListBackup.Size(); i-- > 0;)
			{
				me = PredictionSectorListBackup[i];
				link = &sec->thinglist;
				next = *link;
				if ((me->snext = next))
					next->sprev = &me->snext;
				me->sprev = link;
				*link = me;
			}

			act->touching_sectorlist = RestoreNodeList(act, ctx.sector_list, &sector_t::touching_thinglist, PredictionTouchingSectors_sprev_Backup, PredictionTouchingSectorsBackup);
			act->touching_rendersectors = RestoreNodeList(act, ctx.render_list, &sector_t::touching_renderthings, PredictionRenderSectors_sprev_Backup, PredictionRenderSectorsBackup);
			act->touching_sectorportallist = RestoreNodeList(act, sectorportal_list, &sector_t::sectorportal_thinglist, PredictionPortalSectors_sprev_Backup, PredictionPortalSectorsBackup);
			act->touching_lineportallist = RestoreNodeList(act, lineportal_list, &FLinePortal::lineportal_thinglist, PredictionPortalLines_sprev_Backup, PredictionPortalLinesBackup);
		}

		// Now fix the pointers in the blocknode chain
		FBlockNode *block = act->BlockNode;

		while (block != NULL)
		{
			*(block->PrevActor) = block;
			if (block->NextActor != NULL)
			{
				block->NextActor->PrevActor = &block->NextActor;
			}
			block = block->NextBlock;
		}

		actInvSel = InvSel;
		player->inventorytics = inventorytics;
	}
}

void player_t::Serialize(FSerializer &arc)
{
	FString skinname;

	arc("class", cls)
		("mo", mo)
		("camera", camera)
		("playerstate", playerstate)
		("cmd", cmd);

	if (arc.isReading())
	{
		userinfo.Reset(mo->Level->PlayerNum(this));
		ReadUserInfo(arc, userinfo, skinname);
	}
	else
	{
		WriteUserInfo(arc, userinfo);
	}

	arc("desiredfov", DesiredFOV)
		("fov", FOV)
		("viewz", viewz)
		("viewheight", viewheight)
		("deltaviewheight", deltaviewheight)
		("bob", bob)
		("vel", Vel)
		("centering", centering)
		("health", health)
		("inventorytics", inventorytics)
		("fragcount", fragcount)
		("spreecount", spreecount)
		("multicount", multicount)
		("lastkilltime", lastkilltime)
		("readyweapon", ReadyWeapon)
		("offhandweapon", OffhandWeapon)
		("pendingweapon", PendingWeapon)
		("cheats", cheats)
		("refire", refire)
		("inconsistant", inconsistant)
		("killcount", killcount)
		("itemcount", itemcount)
		("secretcount", secretcount)
		("damagecount", damagecount)
		("bonuscount", bonuscount)
		("hazardcount", hazardcount)
		("poisoncount", poisoncount)
		("poisoner", poisoner)
		("attacker", attacker)
		("extralight", extralight)
		("fixedcolormap", fixedcolormap)
		("fixedlightlevel", fixedlightlevel)
		("morphTics", morphTics)
		("morphedplayerclass", MorphedPlayerClass)
		("morphstyle", MorphStyle)
		("morphexitflash", MorphExitFlash)
		("premorphweapon", PremorphWeapon)
		("premorphweaponoffhand", PremorphWeaponOffhand)
		("chickenpeck", chickenPeck)
		("jumptics", jumpTics)
		("respawntime", respawn_time)
		("airfinished", air_finished)
		("turnticks", turnticks)
		("oldbuttons", oldbuttons)
		("hazardtype", hazardtype)
		("hazardinterval", hazardinterval)
		("bot", Bot)
		("blendr", BlendR)
		("blendg", BlendG)
		("blendb", BlendB)
		("blenda", BlendA)
		("weaponstate", WeaponState)
		("logtext", LogText)
		("subtitletext", SubtitleText)
		("subtitlecounter", SubtitleCounter)
		("conversionnpc", ConversationNPC)
		("conversionpc", ConversationPC)
		("conversionnpcangle", ConversationNPCAngle)
		("conversionfacetalker", ConversationFaceTalker)
		.Array("frags", frags, MAXPLAYERS)
		("psprites", psprites)
		("currentplayerclass", CurrentPlayerClass)
		("crouchfactor", crouchfactor)
		("crouching", crouching)
		("crouchdir", crouchdir)
		("crouchviewdelta", crouchviewdelta)
		("original_cmd", original_cmd)
		("original_oldbuttons", original_oldbuttons)
		("poisontype", poisontype)
		("poisonpaintype", poisonpaintype)
		("timefreezer", timefreezer)
		("settings_controller", settings_controller)
		("onground", onground)
		("musinfoactor", MUSINFOactor)
		("musinfotics", MUSINFOtics)
		("soundclass", SoundClass)
		("angleoffsettargets", angleOffsetTargets)
		("lastsafepos", LastSafePos);

	if (arc.isWriting ())
	{
		// If the player reloaded because they pressed +use after dying, we
		// don't want +use to still be down after the game is loaded.
		oldbuttons = ~0;
		original_oldbuttons = ~0;
	}
	if (skinname.IsNotEmpty())
	{
		userinfo.SkinChanged(skinname.GetChars(), CurrentPlayerClass);
	}
}

bool P_IsPlayerTotallyFrozen(const player_t *player)
{
	return
		gamestate == GS_TITLELEVEL ||
		player->cheats & CF_TOTALLYFROZEN ||
		player->mo->isFrozen();
}


//==========================================================================
//
// native members
//
//==========================================================================

DEFINE_FIELD_X(PlayerInfo, player_t, mo)
DEFINE_FIELD_X(PlayerInfo, player_t, playerstate)
DEFINE_FIELD_X(PlayerInfo, player_t, original_oldbuttons)
DEFINE_FIELD_X(PlayerInfo, player_t, cls)
DEFINE_FIELD_X(PlayerInfo, player_t, DesiredFOV)
DEFINE_FIELD_X(PlayerInfo, player_t, FOV)
DEFINE_FIELD_X(PlayerInfo, player_t, viewz)
DEFINE_FIELD_X(PlayerInfo, player_t, viewheight)
DEFINE_FIELD_X(PlayerInfo, player_t, deltaviewheight)
DEFINE_FIELD_X(PlayerInfo, player_t, bob)
DEFINE_FIELD_X(PlayerInfo, player_t, Vel)
DEFINE_FIELD_X(PlayerInfo, player_t, centering)
DEFINE_FIELD_X(PlayerInfo, player_t, turnticks)
DEFINE_FIELD_X(PlayerInfo, player_t, resetDoomYaw)
DEFINE_FIELD_X(PlayerInfo, player_t, attackdown)
DEFINE_FIELD_X(PlayerInfo, player_t, ohattackdown)
DEFINE_FIELD_X(PlayerInfo, player_t, usedown)
DEFINE_FIELD_X(PlayerInfo, player_t, oldbuttons)
DEFINE_FIELD_X(PlayerInfo, player_t, health)
DEFINE_FIELD_X(PlayerInfo, player_t, inventorytics)
DEFINE_FIELD_X(PlayerInfo, player_t, CurrentPlayerClass)
DEFINE_FIELD_X(PlayerInfo, player_t, frags)
DEFINE_FIELD_X(PlayerInfo, player_t, fragcount)
DEFINE_FIELD_X(PlayerInfo, player_t, lastkilltime)
DEFINE_FIELD_X(PlayerInfo, player_t, multicount)
DEFINE_FIELD_X(PlayerInfo, player_t, spreecount)
DEFINE_FIELD_X(PlayerInfo, player_t, WeaponState)
DEFINE_FIELD_X(PlayerInfo, player_t, ReadyWeapon)
DEFINE_FIELD_X(PlayerInfo, player_t, PendingWeapon)
DEFINE_FIELD_X(PlayerInfo, player_t, OffhandWeapon)
DEFINE_FIELD_X(PlayerInfo, player_t, psprites)
DEFINE_FIELD_X(PlayerInfo, player_t, cheats)
DEFINE_FIELD_X(PlayerInfo, player_t, timefreezer)
DEFINE_FIELD_X(PlayerInfo, player_t, refire)
DEFINE_FIELD_NAMED_X(PlayerInfo, player_t, inconsistant, inconsistent)
DEFINE_FIELD_X(PlayerInfo, player_t, waiting)
DEFINE_FIELD_X(PlayerInfo, player_t, killcount)
DEFINE_FIELD_X(PlayerInfo, player_t, itemcount)
DEFINE_FIELD_X(PlayerInfo, player_t, secretcount)
DEFINE_FIELD_X(PlayerInfo, player_t, damagecount)
DEFINE_FIELD_X(PlayerInfo, player_t, bonuscount)
DEFINE_FIELD_X(PlayerInfo, player_t, hazardcount)
DEFINE_FIELD_X(PlayerInfo, player_t, hazardinterval)
DEFINE_FIELD_X(PlayerInfo, player_t, hazardtype)
DEFINE_FIELD_X(PlayerInfo, player_t, poisoncount)
DEFINE_FIELD_X(PlayerInfo, player_t, poisontype)
DEFINE_FIELD_X(PlayerInfo, player_t, poisonpaintype)
DEFINE_FIELD_X(PlayerInfo, player_t, poisoner)
DEFINE_FIELD_X(PlayerInfo, player_t, attacker)
DEFINE_FIELD_X(PlayerInfo, player_t, extralight)
DEFINE_FIELD_X(PlayerInfo, player_t, fixedcolormap)
DEFINE_FIELD_X(PlayerInfo, player_t, fixedlightlevel)
DEFINE_FIELD_X(PlayerInfo, player_t, morphTics)
DEFINE_FIELD_X(PlayerInfo, player_t, MorphedPlayerClass)
DEFINE_FIELD_X(PlayerInfo, player_t, MorphStyle)
DEFINE_FIELD_X(PlayerInfo, player_t, MorphExitFlash)
DEFINE_FIELD_X(PlayerInfo, player_t, PremorphWeapon)
DEFINE_FIELD_X(PlayerInfo, player_t, PremorphWeaponOffhand)
DEFINE_FIELD_X(PlayerInfo, player_t, chickenPeck)
DEFINE_FIELD_X(PlayerInfo, player_t, jumpTics)
DEFINE_FIELD_X(PlayerInfo, player_t, onground)
DEFINE_FIELD_X(PlayerInfo, player_t, keepmomentum)
DEFINE_FIELD_X(PlayerInfo, player_t, respawn_time)
DEFINE_FIELD_X(PlayerInfo, player_t, camera)
DEFINE_FIELD_X(PlayerInfo, player_t, air_finished)
DEFINE_FIELD_X(PlayerInfo, player_t, LastDamageType)
DEFINE_FIELD_X(PlayerInfo, player_t, MUSINFOactor)
DEFINE_FIELD_X(PlayerInfo, player_t, MUSINFOtics)
DEFINE_FIELD_X(PlayerInfo, player_t, settings_controller)
DEFINE_FIELD_X(PlayerInfo, player_t, crouching)
DEFINE_FIELD_X(PlayerInfo, player_t, crouchdir)
DEFINE_FIELD_X(PlayerInfo, player_t, Bot)
DEFINE_FIELD_X(PlayerInfo, player_t, BlendR)
DEFINE_FIELD_X(PlayerInfo, player_t, BlendG)
DEFINE_FIELD_X(PlayerInfo, player_t, BlendB)
DEFINE_FIELD_X(PlayerInfo, player_t, BlendA)
DEFINE_FIELD_X(PlayerInfo, player_t, LogText)
DEFINE_FIELD_X(PlayerInfo, player_t, MinPitch)
DEFINE_FIELD_X(PlayerInfo, player_t, MaxPitch)
DEFINE_FIELD_X(PlayerInfo, player_t, crouchfactor)
DEFINE_FIELD_X(PlayerInfo, player_t, crouchoffset)
DEFINE_FIELD_X(PlayerInfo, player_t, crouchviewdelta)
DEFINE_FIELD_X(PlayerInfo, player_t, ConversationNPC)
DEFINE_FIELD_X(PlayerInfo, player_t, ConversationPC)
DEFINE_FIELD_X(PlayerInfo, player_t, ConversationNPCAngle)
DEFINE_FIELD_X(PlayerInfo, player_t, ConversationFaceTalker)
DEFINE_FIELD_NAMED_X(PlayerInfo, player_t, cmd.ucmd, cmd)
DEFINE_FIELD_X(PlayerInfo, player_t, original_cmd)
DEFINE_FIELD_X(PlayerInfo, player_t, userinfo)
DEFINE_FIELD_X(PlayerInfo, player_t, weapons)
DEFINE_FIELD_NAMED_X(PlayerInfo, player_t, cmd.ucmd.buttons, buttons)
DEFINE_FIELD_X(PlayerInfo, player_t, SoundClass)
DEFINE_FIELD_X(PlayerInfo, player_t, PlayInVR)

DEFINE_FIELD_X(UserCmd, usercmd_t, buttons)
DEFINE_FIELD_X(UserCmd, usercmd_t, pitch)
DEFINE_FIELD_X(UserCmd, usercmd_t, yaw)
DEFINE_FIELD_X(UserCmd, usercmd_t, roll)
DEFINE_FIELD_X(UserCmd, usercmd_t, forwardmove)
DEFINE_FIELD_X(UserCmd, usercmd_t, sidemove)
DEFINE_FIELD_X(UserCmd, usercmd_t, upmove)

DEFINE_FIELD(FPlayerClass, Type)
DEFINE_FIELD(FPlayerClass, Flags)
DEFINE_FIELD(FPlayerClass, Skins)
