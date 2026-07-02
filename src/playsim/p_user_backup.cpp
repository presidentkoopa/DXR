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
#include "p_maputl.h"
#include "textures.h"
#include "texturemanager.h"
#include "p_linetracedata.h"
#include "p_trace.h"
#include "keyword_dispatcher.h"
#include "gametexture.h"

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
			S_Sound (self, CHAN_VOICE, 0, self->DeathSound, 1, ATTN_NORM);
		}
		else
		{
			S_Sound (self, CHAN_VOICE, 0, "*death", 1, ATTN_NORM);
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
	S_Sound (self, chan, 0, sound, 1, ATTN_NORM);
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
		S_Sound (actor, CHAN_AUTO, 0, "*land", 1, ATTN_NORM);
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
			S_Sound(player->mo, CHAN_VOICE, 0, id, 1, ATTN_NORM);
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

void VR_UpdateClimbing(player_t* player);
void VR_UpdateGravityGloves(player_t* player);

void P_PlayerThink (player_t *player)
{
	ticcmd_t *cmd = &player->cmd;

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

	VR_UpdateGravityGloves(player);
	VR_UpdateClimbing(player);
}

EXTERN_CVAR(Float, vr_grab_cone_angle)
EXTERN_CVAR(Float, vr_grab_max_dist)
EXTERN_CVAR(Float, vr_grab_magnet_speed)
EXTERN_CVAR(Bool, vr_autoequip)
EXTERN_CVAR(Int, vr_control_scheme)
EXTERN_CVAR(Float, vr_climb_radius)
EXTERN_CVAR(Float, vr_climb_speed_mult)
EXTERN_CVAR(Bool, vr_grab_debug)
EXTERN_CVAR(Float, vr_throw_force)
EXTERN_CVAR(Float, vr_scale_meters_to_units)

EXTERN_CVAR(Bool, vr_grab_debug_cone)
EXTERN_CVAR(Bool, vr_grab_debug_sphere)

void VR_UpdateClimbing(player_t* player);
void VR_UpdateGravityGloves(player_t* player);
void VR_UpdateGravityGloves(player_t* player)
{
	if (!player || !player->mo || !VRMode::GetVRModeCached(false)) return;
	if (vr_grab_max_dist <= 0) return;

	for (int hand = 0; hand < 2; hand++)
	{
		bool isGripPressed = VRMode::GetVRModeCached(false)->IsGripPressed(hand);
		bool wasGripPressed = player->vr_was_grip_pressed[hand];
		player->vr_was_grip_pressed[hand] = isGripPressed;

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
				// Throw Logic (Using Smoothed Velocity)
				double itemMass = heldItem->Mass > 0 ? heldItem->Mass : 100.0;
				double massScale = 100.0 / itemMass;
				double throwForce = vr_throw_force * massScale;
				
				heldItem->Vel = handVelocity * (vr_scale_meters_to_units / 35.0) * throwForce;
				heldItem->flags &= ~MF_NOGRAVITY;
				heldItem->flags &= ~MF_NOBLOCKMAP;
				player->vr_held_items[hand] = nullptr;
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
					if (!(mo->flags & MF_SPECIAL) && !(mo->flags & MF_MISSILE)) continue;
					if (mo->Distance3D(player->mo) > vr_grab_max_dist) continue;

					DVector3 toItem = mo->Pos() - handPos;
					double distSq = toItem.LengthSquared();
					toItem.MakeUnit();

					double dot = toItem | handForward;
					double coneThreshold = cos(vr_grab_cone_angle * M_PI / 360.0);

					if (dot > coneThreshold)
					{
						double score = dot * (1.0 - (sqrt(distSq) / vr_grab_max_dist));
						if (score > bestScore)
						{
							bestScore = score;
							bestItem = mo;
						}
					}
				}
				player->vr_grab_candidate[hand] = bestItem;

				if (vr_grab_debug)
				{
					// Draw holographic grab cone
					if (vr_grab_debug_cone)
					{
						// Longitudinal Beams
						for (int b = 0; b < 4; b++)
						{
							double ang = b * M_PI / 2.0;
							DVector3 right = handForward.Z != 0 || handForward.X != 0 ? DVector3(-handForward.Z, 0, handForward.X) : DVector3(0, 1, 0);
							right.MakeUnit();
							DVector3 up = handForward ^ right;
							DVector3 beamDir = (handForward + (right * cos(ang) + up * sin(ang)) * tan(vr_grab_cone_angle * M_PI / 360.0));
							beamDir.MakeUnit();
							
							for (int d = 1; d <= 10; d++)
							{
								DVector3 beamPos = handPos + beamDir * (vr_grab_max_dist * d / 10.0);
								P_SpawnParticle(player->mo->Level, beamPos, DVector3(0,0,0), DVector3(0,0,0), PalEntry(150, 0, 255, 255), 0.6, 1, 1.5, 1.0, 0.0, 0);
							}
						}

						// Concentric Rings
						for (int d = 1; d <= 8; ++d)
						{
							double dist = (vr_grab_max_dist / 8.0) * d;
							double radius = dist * tan(vr_grab_cone_angle * M_PI / 360.0);
							PalEntry color = bestItem ? PalEntry(200, 0, 255, 255) : PalEntry(100, 0, 180, 255);
							
							for (int i = 0; i < 12; ++i)
							{
								double ang = i * M_PI / 6.0;
								DVector3 right = handForward.Z != 0 || handForward.X != 0 ? DVector3(-handForward.Z, 0, handForward.X) : DVector3(0, 1, 0);
								right.MakeUnit();
								DVector3 up = handForward ^ right;
								DVector3 ringPos = handPos + (handForward * dist) + (right * cos(ang) + up * sin(ang)) * radius;
								
								P_SpawnParticle(player->mo->Level, ringPos, DVector3(0,0,0), DVector3(0,0,0), color, 0.5, 1, 2.0, 1.0, 0.0, 0);
							}
						}
					}

					// Grab Sphere Visual
					if (vr_grab_debug_sphere)
					{
						for (int i = 0; i < 24; i++)
						{
							double phi = acos(1.0 - 2.0 * (i + 0.5) / 24.0);
							double theta = M_PI * (1.0 + pow(5.0, 0.5)) * (i + 0.5);
							DVector3 spherePos = handPos + DVector3(cos(theta) * sin(phi), sin(theta) * sin(phi), cos(phi)) * 32.0;
							P_SpawnParticle(player->mo->Level, spherePos, DVector3(0,0,0), DVector3(0,0,0), PalEntry(150, 0, 255, 0), 0.8, 1, 1.8, 1.0, 0.0, 0);
						}
					}

					if (bestItem)
					{
						// Target Pulse Visual Cue
						double time = player->mo->Level->time / 5.0;
						double pulseRadius = bestItem->radius + 4.0 + sin(time) * 4.0;
						for (int i = 0; i < 8; i++)
						{
							double ang = i * M_PI / 4.0;
							DVector3 pulsePos = bestItem->Pos() + DVector3(cos(ang) * pulseRadius, sin(ang) * pulseRadius, bestItem->Height / 2.0);
							P_SpawnParticle(player->mo->Level, pulsePos, DVector3(0,0,0), DVector3(0,0,0), PalEntry(255, 255, 255, 255), 1.0, 1, 4.0, 1.0, 0.0, 0);
						}
					}
				}
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
			if (vr_grab_debug)
			{
				double itemMass = heldItem->Mass > 0 ? heldItem->Mass : 100.0;
				double massScale = 100.0 / itemMass;
				double velocityScale = (vr_scale_meters_to_units / 35.0) * vr_throw_force * massScale;
				DVector3 tVel = handVelocity * velocityScale;
				DVector3 tPos = handPos;

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
						P_SpawnParticle(player->mo->Level, res.HitPos, DVector3(0,0,0), DVector3(0,0,0), PalEntry(255, 255, 0, 0), 1.0, 1, 8.0, 1.0, 0.0, 0);
						break;
					}

					tVel.Z -= (player->mo->Level->gravity * heldItem->Gravity);
					tPos = nextPos;

					P_SpawnParticle(player->mo->Level, tPos, DVector3(0,0,0), DVector3(0,0,0), PalEntry(255, 0, 255, 255), 0.7, 1, 2.5, 1.0, 0.0, 0);
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
					P_TouchSpecialThing(heldItem, player->mo);
					player->vr_held_items[hand] = nullptr;
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
						player->vr_held_items[hand] = target;
						player->vr_grab_is_locked[hand] = false;
						player->vr_grab_is_pulling[hand] = false;
						player->vr_grab_is_waiting_catch[hand] = false;
						player->vr_grab_candidate[hand] = nullptr;
					}
				}
				else if (player->vr_grab_candidate[hand])
				{
					// Initial Lock
					player->vr_grab_is_locked[hand] = true;
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

void VR_UpdateClimbing(player_t* player)
{
    if (!player || !player->mo || !VRMode::GetVRModeCached(false)) return;
    if (vr_climb_radius <= 0) return;

    bool anyGrip = false;
    DVector3 climbDelta(0, 0, 0);

    for (int hand = 0; hand < 2; hand++)
    {
        bool isGripPressed = VRMode::GetVRModeCached(false)->IsGripPressed(hand);
        
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
                    VR_HapticEvent("grip_climb", hand, 60, 0, 0);
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
                        VR_HapticEvent("climb_texture", hand, 20, 0, 0);
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

    if (isClimbingOverall)
    {
        player->mo->flags |= MF_NOGRAVITY;
        player->mo->Vel = climbDelta * vr_climb_speed_mult;
    }
    else
    {
        player->mo->flags &= ~MF_NOGRAVITY;
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
