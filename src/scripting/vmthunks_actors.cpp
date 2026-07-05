//-----------------------------------------------------------------------------
//
// Copyright 2016-2018 Christoph Oelckers
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
// VM thunks for internal functions of actor classes
//
// Important note about this file: Since everything in here is supposed to be called
// from JIT-compiled VM code it needs to be very careful about calling conventions.
// As a result none of the integer sized struct types may be used as function
// arguments, because current C++ calling conventions require them to be passed
// by reference. The JIT code, however will pass them by value so any direct native function
// taking such an argument needs to receive it as a naked int.
//
//-----------------------------------------------------------------------------

#include "vm.h"
#include "r_defs.h"
#include "g_levellocals.h"
#include "s_sound.h"
#include "p_local.h"
#include "v_font.h"
#include "gstrings.h"
#include "a_keys.h"
#include "sbar.h"
#include "doomstat.h"
#include "p_acs.h"
#include "a_pickups.h"
#include "a_specialspot.h"
#include "actorptrselect.h"
#include "a_weapons.h"
#include "hw_vrmodes.h"        // VRMode::GetVRModeCached / GetGripValue / GetWeaponTransform
#include "vr_hardpoint.h"      // EHardpointAnchor/Action, FHardpointSlot, VR_MAX_HARDPOINTS, VRHardpointRuntime
#include "d_player.h"
#include "p_setup.h"
#include "i_music.h"
#include "p_terrain.h"
#include "p_checkposition.h"
#include "p_linetracedata.h"
#include "p_local.h"
#include "p_effect.h"
#include "p_spec.h"
#include "actorinlines.h"
#include "p_enemy.h"
#include "gi.h"
#include "shadowinlines.h"

DVector2 AM_GetPosition();
int Net_GetLatency(int *ld, int *ad);
void PrintPickupMessage(bool localview, const FString &str);
bool P_CheckForResurrection(AActor* self, bool usevilestates, FState* state = nullptr, FSoundID sound = NO_SOUND);

// FCheckPosition requires explicit construction and destruction when used in the VM

static void FCheckPosition_C(void *mem)
{
	new(mem) FCheckPosition;
}

DEFINE_ACTION_FUNCTION_NATIVE(_FCheckPosition, _Constructor, FCheckPosition_C)
{
	PARAM_SELF_STRUCT_PROLOGUE(FCheckPosition);
	FCheckPosition_C(self);
	return 0;
}

static void FCheckPosition_D(FCheckPosition *self)
{
	self->~FCheckPosition();
}

DEFINE_ACTION_FUNCTION_NATIVE(_FCheckPosition, _Destructor, FCheckPosition_D)
{
	PARAM_SELF_STRUCT_PROLOGUE(FCheckPosition);
	self->~FCheckPosition();
	return 0;
}

static void ClearLastRipped(FCheckPosition *self)
{
	self->LastRipped.Clear();
}

DEFINE_ACTION_FUNCTION_NATIVE(_FCheckPosition, ClearLastRipped, ClearLastRipped)
{
	PARAM_SELF_STRUCT_PROLOGUE(FCheckPosition);
	self->LastRipped.Clear();
	return 0;
}



DEFINE_ACTION_FUNCTION_NATIVE(DObject, SetMusicVolume, I_SetMusicVolume)
{
	PARAM_PROLOGUE;
	PARAM_FLOAT(vol);
	I_SetMusicVolume(vol);
	return 0;
}

//=====================================================================================
//
// AActor exports (this will be expanded)
//
//=====================================================================================

DEFINE_ACTION_FUNCTION_NATIVE(AActor, GetPointer, COPY_AAPTR)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_INT(ptr);
	ACTION_RETURN_OBJECT(COPY_AAPTR(self, ptr));
}


//==========================================================================
//
// Custom sound functions.
//
//==========================================================================

static void NativeStopSound(AActor *actor, int slot)
{
	S_StopSound(actor, slot);
}

DEFINE_ACTION_FUNCTION(AActor, A_StopSound)
{
	PARAM_ACTION_PROLOGUE(AActor);
	PARAM_INT(slot);
	
	if (ACTION_CALL_FROM_PSPRITE())
	{
		DPSprite *pspr = self->player->FindPSprite(stateinfo->mPSPIndex);
		if (pspr != nullptr && pspr->GetID() == PSP_OFFHANDWEAPON && slot == CHAN_WEAPON)
		{
			slot = CHAN_OFFWEAPON;
		}
	}

	S_StopSound(self, slot);
	return 0;
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, A_StopSounds, S_StopActorSounds)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_INT(chanmin);
	PARAM_INT(chanmax);
	S_StopActorSounds(self, chanmin, chanmax);
	return 0;
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, A_SoundPitch, S_ChangeActorSoundPitch)
{
	PARAM_ACTION_PROLOGUE(AActor);
	PARAM_INT(channel);
	PARAM_FLOAT(pitch);

	if (ACTION_CALL_FROM_PSPRITE())
	{
		DPSprite *pspr = self->player->FindPSprite(stateinfo->mPSPIndex);
		if (pspr != nullptr && pspr->GetID() == PSP_OFFHANDWEAPON && channel == CHAN_WEAPON)
		{
			channel = CHAN_OFFWEAPON;
		}
	}

	S_ChangeActorSoundPitch(self, channel, pitch);
	return 0;
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, A_SoundVolume, S_ChangeActorSoundVolume)
{
	PARAM_ACTION_PROLOGUE(AActor);
	PARAM_INT(channel);
	PARAM_FLOAT(volume);

	if (ACTION_CALL_FROM_PSPRITE())
	{
		DPSprite *pspr = self->player->FindPSprite(stateinfo->mPSPIndex);
		if (pspr != nullptr && pspr->GetID() == PSP_OFFHANDWEAPON && channel == CHAN_WEAPON)
		{
			channel = CHAN_OFFWEAPON;
		}
	}

	S_ChangeActorSoundVolume(self, channel, volume);
	return 0;
}

DEFINE_ACTION_FUNCTION(AActor, A_PlaySound)
{
	PARAM_ACTION_PROLOGUE(AActor);
	PARAM_INT(soundid);
	PARAM_INT(channel);
	PARAM_FLOAT(volume);
	PARAM_BOOL(looping);
	PARAM_FLOAT(attenuation);
	PARAM_BOOL(local);
	PARAM_FLOAT(pitch);

	if (ACTION_CALL_FROM_PSPRITE())
	{
		DPSprite *pspr = self->player->FindPSprite(stateinfo->mPSPIndex);
		if (pspr != nullptr && pspr->GetID() == PSP_OFFHANDWEAPON && (channel & 7) == CHAN_WEAPON)
		{
			channel &= ~7;
			channel |= CHAN_OFFWEAPON;
		}
	}

	A_PlaySound(self, soundid, channel, volume, looping, attenuation, local, pitch);
	return 0;
}

DEFINE_ACTION_FUNCTION(AActor, A_StartSound)
{
	PARAM_ACTION_PROLOGUE(AActor);
	PARAM_INT(soundid);
	PARAM_INT(channel);
	PARAM_INT(flags);
	PARAM_FLOAT(volume);
	PARAM_FLOAT(attenuation);
	PARAM_FLOAT(pitch);
	PARAM_FLOAT(startTime);

	if (ACTION_CALL_FROM_PSPRITE())
	{
		DPSprite *pspr = self->player->FindPSprite(stateinfo->mPSPIndex);
		if (pspr != nullptr && pspr->GetID() == PSP_OFFHANDWEAPON && channel == CHAN_WEAPON)
		{
			channel = CHAN_OFFWEAPON;
		}
	}

	A_StartSound(self, soundid, channel, flags, volume, attenuation, pitch, startTime);
	return 0;
}


void A_StartSoundIfNotSame(AActor *self, int soundid, int checksoundid, int channel, int flags, double volume, double attenuation, double pitch, double startTime)
{
	if (!S_AreSoundsEquivalent (self, FSoundID::fromInt(soundid), FSoundID::fromInt(checksoundid)))
		A_StartSound(self, soundid, channel, flags, volume, attenuation, pitch, startTime);
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, A_StartSoundIfNotSame, A_StartSoundIfNotSame)
{
	PARAM_ACTION_PROLOGUE(AActor);
	PARAM_INT(soundid);
	PARAM_INT(checksoundid);
	PARAM_INT(channel);
	PARAM_INT(flags);
	PARAM_FLOAT(volume);
	PARAM_FLOAT(attenuation);
	PARAM_FLOAT(pitch);
	PARAM_FLOAT(startTime);

	if (ACTION_CALL_FROM_PSPRITE())
	{
		DPSprite *pspr = self->player->FindPSprite(stateinfo->mPSPIndex);
		if (pspr != nullptr && pspr->GetID() == PSP_OFFHANDWEAPON && channel == CHAN_WEAPON)
		{
			channel = CHAN_OFFWEAPON;
		}
	}
	
	A_StartSoundIfNotSame(self, soundid, checksoundid, channel, flags, volume, attenuation, pitch, startTime);
	return 0;
}

// direct native scripting export.
static int S_IsActorPlayingSomethingID(AActor* actor, int channel, int sound_id)
{
	return S_IsActorPlayingSomething(actor, channel, FSoundID::fromInt(sound_id));
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, IsActorPlayingSound, S_IsActorPlayingSomethingID)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_INT(channel);
	PARAM_SOUND(soundid);
	ACTION_RETURN_BOOL(S_IsActorPlayingSomething(self, channel, soundid));
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, CheckKeys, P_CheckKeys)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_INT(locknum);
	PARAM_BOOL(remote);
	PARAM_BOOL(quiet);
	ACTION_RETURN_BOOL(P_CheckKeys(self, locknum, remote, quiet));
}

static double deltaangleDbl(double a1, double a2)
{
	return deltaangle(DAngle::fromDeg(a1), DAngle::fromDeg(a2)).Degrees();
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, deltaangle, deltaangleDbl)	// should this be global?
{
	PARAM_PROLOGUE;
	PARAM_FLOAT(a1);
	PARAM_FLOAT(a2);
	ACTION_RETURN_FLOAT(deltaangle(DAngle::fromDeg(a1), DAngle::fromDeg(a2)).Degrees());
}

static double absangleDbl(double a1, double a2)
{
	return absangle(DAngle::fromDeg(a1), DAngle::fromDeg(a2)).Degrees();
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, absangle, absangleDbl)	// should this be global?
{
	PARAM_PROLOGUE;
	PARAM_FLOAT(a1);
	PARAM_FLOAT(a2);
	ACTION_RETURN_FLOAT(absangle(DAngle::fromDeg(a1), DAngle::fromDeg(a2)).Degrees());
}

static double Distance2DSquared(AActor *self, AActor *other)
{
	return self->Distance2DSquared(PARAM_NULLCHECK(other, other));
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, Distance2DSquared, Distance2DSquared)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_OBJECT_NOT_NULL(other, AActor);
	ACTION_RETURN_FLOAT(self->Distance2DSquared(other));
}

static double Distance3DSquared(AActor *self, AActor *other)
{
	return self->Distance3DSquared(PARAM_NULLCHECK(other, other));
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, Distance3DSquared, Distance3DSquared)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_OBJECT_NOT_NULL(other, AActor);
	ACTION_RETURN_FLOAT(self->Distance3DSquared(other));
}

static double Distance2D(AActor *self, AActor *other)
{
	return self->Distance2D(PARAM_NULLCHECK(other, other));
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, Distance2D, Distance2D)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_OBJECT_NOT_NULL(other, AActor);
	ACTION_RETURN_FLOAT(self->Distance2D(other));
}

static double Distance3D(AActor *self, AActor *other)
{
	return self->Distance3D(PARAM_NULLCHECK(other, other));
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, Distance3D, Distance3D)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_OBJECT_NOT_NULL(other, AActor);
	ACTION_RETURN_FLOAT(self->Distance3D(other));
}

static void AddZ(AActor *self, double addz, bool moving)
{
	self->AddZ(addz, moving);
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, AddZ, AddZ)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_FLOAT(addz);
	PARAM_BOOL(moving);
	self->AddZ(addz, moving);
	return 0;
}

static void SetZ(AActor *self, double z)
{
	self->SetZ(z);
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, SetZ, SetZ)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_FLOAT(z);
	self->SetZ(z);
	return 0;
}

static void SetDamage(AActor *self, int dmg)
{
	self->SetDamage(dmg);
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, SetDamage, SetDamage)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_INT(dmg);
	self->SetDamage(dmg);
	return 0;
}

static double PitchFromVel(AActor* self)
{
	return self->Vel.Pitch().Degrees();
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, PitchFromVel, PitchFromVel)
{
	PARAM_SELF_PROLOGUE(AActor);
	ACTION_RETURN_FLOAT(PitchFromVel(self));
}


// This combines all 3 variations of the internal function
static void VelFromAngle(AActor *self, double speed, double angle)
{
	if (speed == 1e37)
	{
		self->VelFromAngle();
	}
	else
	{
		if (angle == 1e37)
			
		{
			self->VelFromAngle(speed);
		}
		else
		{
			self->VelFromAngle(speed, DAngle::fromDeg(angle));
		}
	}
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, VelFromAngle, VelFromAngle)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_FLOAT(speed);
	PARAM_FLOAT(angle);
	VelFromAngle(self, speed, angle);
	return 0;
}

static void Vel3DFromAngle(AActor *self, double speed, double angle, double pitch)
{
	self->Vel3DFromAngle(DAngle::fromDeg(angle), DAngle::fromDeg(pitch), speed);
}

// This combines all 3 variations of the internal function
DEFINE_ACTION_FUNCTION_NATIVE(AActor, Vel3DFromAngle, Vel3DFromAngle)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_FLOAT(speed);
	PARAM_ANGLE(angle);
	PARAM_ANGLE(pitch);
	self->Vel3DFromAngle(angle, pitch, speed);
	return 0;
}

// This combines all 3 variations of the internal function
static void Thrust(AActor *self, double speed, double angle)
{
	if (speed == 1e37)
	{
		self->Thrust();
	}
	else
	{
		if (angle == 1e37)
		{
			self->Thrust(speed);
		}
		else
		{
			self->Thrust(DAngle::fromDeg(angle), speed);
		}
	}
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, Thrust, Thrust)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_FLOAT(speed);
	PARAM_FLOAT(angle);
	Thrust(self, speed, angle);
	return 0;
}

static double AngleTo(AActor *self, AActor *targ, bool absolute)
{
	return self->AngleTo(PARAM_NULLCHECK(targ, targ), absolute).Degrees();
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, AngleTo, AngleTo)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_OBJECT_NOT_NULL(targ, AActor);
	PARAM_BOOL(absolute);
	ACTION_RETURN_FLOAT(self->AngleTo(targ, absolute).Degrees());
}

static void AngleToVector(double angle, double length, DVector2 *result)
{
	*result = DAngle::fromDeg(angle).ToVector(length);
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, AngleToVector, AngleToVector)
{
	PARAM_PROLOGUE;
	PARAM_ANGLE(angle);
	PARAM_FLOAT(length);
	ACTION_RETURN_VEC2(angle.ToVector(length));
}

static void RotateVector(double x, double y, double angle, DVector2 *result)
{
	*result = DVector2(x, y).Rotated(angle);
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, RotateVector, RotateVector)
{
	PARAM_PROLOGUE;
	PARAM_FLOAT(x);
	PARAM_FLOAT(y);
	PARAM_ANGLE(angle);
	ACTION_RETURN_VEC2(DVector2(x, y).Rotated(angle));
}

static double Normalize180(double angle)
{
	return DAngle::fromDeg(angle).Normalized180().Degrees();
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, Normalize180, Normalize180)
{
	PARAM_PROLOGUE;
	PARAM_ANGLE(angle);
	ACTION_RETURN_FLOAT(angle.Normalized180().Degrees());
}

static double DistanceBySpeed(AActor *self, AActor *targ, double speed)
{
	return self->DistanceBySpeed(PARAM_NULLCHECK(targ, targ), speed);
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, DistanceBySpeed, DistanceBySpeed)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_OBJECT_NOT_NULL(targ, AActor);
	PARAM_FLOAT(speed);
	ACTION_RETURN_FLOAT(self->DistanceBySpeed(targ, speed));
}

static void SetXYZ(AActor *self, double x, double y, double z)
{
	self->SetXYZ(x, y, z);
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, SetXYZ, SetXYZ)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_FLOAT(x);
	PARAM_FLOAT(y);
	PARAM_FLOAT(z);
	self->SetXYZ(x, y, z);
	return 0; 
}

static void Vec2Angle(AActor *self, double length, double angle, bool absolute, DVector2 *result)
{
	*result = self->Vec2Angle(length, DAngle::fromDeg(angle), absolute);
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, Vec2Angle, Vec2Angle)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_FLOAT(length);
	PARAM_ANGLE(angle);
	PARAM_BOOL(absolute);
	ACTION_RETURN_VEC2(self->Vec2Angle(length, angle, absolute));
}

static void Vec3To(AActor *self, AActor *t, DVector3 *result)
{
	*result = self->Vec3To(PARAM_NULLCHECK(t, other));
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, Vec3To, Vec3To)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_OBJECT_NOT_NULL(t, AActor)
	ACTION_RETURN_VEC3(self->Vec3To(t));
}

static void Vec2To(AActor *self, AActor *t, DVector2 *result)
{
	*result = self->Vec2To(PARAM_NULLCHECK(t, other));
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, Vec2To, Vec2To)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_OBJECT_NOT_NULL(t, AActor)
	ACTION_RETURN_VEC2(self->Vec2To(t));
}

static void Vec3Angle(AActor *self, double length, double angle, double z, bool absolute, DVector3 *result)
{
	*result = self->Vec3Angle(length, DAngle::fromDeg(angle), z, absolute);
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, Vec3Angle, Vec3Angle)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_FLOAT(length)
	PARAM_ANGLE(angle);
	PARAM_FLOAT(z);
	PARAM_BOOL(absolute);
	ACTION_RETURN_VEC3(self->Vec3Angle(length, angle, z, absolute));
}

static void Vec2OffsetZ(AActor *self, double x, double y, double z, bool absolute, DVector3 *result)
{
	*result = self->Vec2OffsetZ(x, y, z, absolute);
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, Vec2OffsetZ, Vec2OffsetZ)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_FLOAT(x);
	PARAM_FLOAT(y);
	PARAM_FLOAT(z);
	PARAM_BOOL(absolute);
	ACTION_RETURN_VEC3(self->Vec2OffsetZ(x, y, z, absolute));
}

static void Vec2Offset(AActor *self, double x, double y, bool absolute, DVector2 *result)
{
	*result = self->Vec2Offset(x, y, absolute);
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, Vec2Offset, Vec2Offset)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_FLOAT(x);
	PARAM_FLOAT(y);
	PARAM_BOOL(absolute);
	ACTION_RETURN_VEC2(self->Vec2Offset(x, y, absolute));
}

static void Vec3Offset(AActor *self, double x, double y, double z, bool absolute, DVector3 *result)
{
	*result = self->Vec3Offset(x, y, z, absolute);
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, Vec3Offset, Vec3Offset)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_FLOAT(x);
	PARAM_FLOAT(y);
	PARAM_FLOAT(z);
	PARAM_BOOL(absolute);
	ACTION_RETURN_VEC3(self->Vec3Offset(x, y, z, absolute));
}

static void ZS_PosRelative(AActor *self, sector_t *sec, DVector3 *result)
{
	*result = self->PosRelative(sec);
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, PosRelative, ZS_PosRelative)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_POINTER(sec, sector_t);
	ACTION_RETURN_VEC3(self->PosRelative(sec));
}

static void RestoreDamage(AActor *self)
{
	self->DamageVal = self->GetDefault()->DamageVal;
	self->DamageFunc = self->GetDefault()->DamageFunc;
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, RestoreDamage, RestoreDamage)
{
	PARAM_SELF_PROLOGUE(AActor);
	RestoreDamage(self);
	return 0;
}

static int PlayerNumber(AActor *self)
{
	return self->player ? self->Level->PlayerNum(self->player) : 0;
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, PlayerNumber, PlayerNumber)
{
	PARAM_SELF_PROLOGUE(AActor);
	ACTION_RETURN_INT(PlayerNumber(self));
}

static void SetFriendPlayer(AActor *self, player_t *player)
{
	self->SetFriendPlayer(player);
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, SetFriendPlayer, SetFriendPlayer)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_POINTER(player, player_t);
	self->SetFriendPlayer(player);
	return 0;
}

void ClearBounce(AActor *self)
{
	self->BounceFlags = 0;
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, ClearBounce, ClearBounce)
{
	PARAM_SELF_PROLOGUE(AActor);
	ClearBounce(self);
	return 0;
}

static int CountsAsKill(AActor *self)
{
	return self->CountsAsKill();
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, CountsAsKill, CountsAsKill)
{
	PARAM_SELF_PROLOGUE(AActor);
	ACTION_RETURN_BOOL(self->CountsAsKill());
}

static int IsZeroDamage(AActor *self)
{
	return self->IsZeroDamage();
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, IsZeroDamage, IsZeroDamage)
{
	PARAM_SELF_PROLOGUE(AActor);
	ACTION_RETURN_BOOL(self->IsZeroDamage());
}

static void ClearInterpolation(AActor *self)
{
	self->ClearInterpolation();
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, ClearInterpolation, ClearInterpolation)
{
	PARAM_SELF_PROLOGUE(AActor);
	self->ClearInterpolation();
	return 0;
}

DEFINE_ACTION_FUNCTION(AActor, ClearFOVInterpolation)
{
	PARAM_SELF_PROLOGUE(AActor);
	self->ClearFOVInterpolation();
	return 0;
}

static int ApplyDamageFactors(PClassActor *itemcls, int damagetype, int damage, int defdamage)
{
	DmgFactors &df = itemcls->ActorInfo()->DamageFactors;
	if (df.Size() != 0)
	{
		return (df.Apply(ENamedName(damagetype), damage));
	}
	else
	{
		return (defdamage);
	}
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, ApplyDamageFactors, ApplyDamageFactors)
{
	PARAM_PROLOGUE;
	PARAM_CLASS(itemcls, AActor);
	PARAM_NAME(damagetype);
	PARAM_INT(damage);
	PARAM_INT(defdamage);
	ACTION_RETURN_INT(ApplyDamageFactors(itemcls, damagetype.GetIndex(), damage, defdamage));
}

static void RestoreSpecialPosition(AActor *self)
{
	self->RestoreSpecialPosition();
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, A_RestoreSpecialPosition, RestoreSpecialPosition)
{
	PARAM_SELF_PROLOGUE(AActor);
	self->RestoreSpecialPosition();
	return 0;
}

static double GetBobOffset(AActor *self, double frac)
{
	return self->GetBobOffset(frac);
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, GetBobOffset, GetBobOffset)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_FLOAT(frac);
	ACTION_RETURN_FLOAT(self->GetBobOffset(frac));
}

static void SetIdle(AActor *self, bool nofunction)
{
	self->SetIdle(nofunction);
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, SetIdle, SetIdle)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_BOOL(nofunction);
	self->SetIdle(nofunction);
	return 0;
}

static int SpawnHealth(AActor *self)
{
	return self->SpawnHealth();
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, SpawnHealth, SpawnHealth)
{
	PARAM_SELF_PROLOGUE(AActor);
	ACTION_RETURN_INT(self->SpawnHealth());
}

// Why does this exist twice?
DEFINE_ACTION_FUNCTION_NATIVE(AActor, GetSpawnHealth, SpawnHealth)
{
	PARAM_SELF_PROLOGUE(AActor);
	ACTION_RETURN_INT(self->SpawnHealth());
}



void Revive(AActor *self)
{
	self->Revive();
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, Revive, Revive)
{
	PARAM_SELF_PROLOGUE(AActor);
	self->Revive();
	return 0;
}

static double GetCameraHeight(AActor *self)
{
	return self->GetCameraHeight();
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, GetCameraHeight, GetCameraHeight)
{
	PARAM_SELF_PROLOGUE(AActor);
	ACTION_RETURN_FLOAT(self->GetCameraHeight());
}

static FDropItem *GetDropItems(AActor *self)
{
	return self->GetDropItems();
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, GetDropItems, GetDropItems)
{
	PARAM_SELF_PROLOGUE(AActor);
	ACTION_RETURN_POINTER(self->GetDropItems());
}

static double GetGravity(AActor *self)
{
	return self->GetGravity();
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, GetGravity, GetGravity)
{
	PARAM_SELF_PROLOGUE(AActor);
	ACTION_RETURN_FLOAT(self->GetGravity());
}

static void GetTag(AActor *self, const FString &def, FString *result)
{
	*result = self->GetTag(def.Len() == 0 ? nullptr : def.GetChars());
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, GetTag, GetTag)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_STRING(def);
	FString res;
	GetTag(self, def, &res);
	ACTION_RETURN_STRING(res);
}

static void GetCharacterName(AActor *self, FString *result)
{
	*result = self->GetCharacterName();
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, GetCharacterName, GetCharacterName)
{
	PARAM_SELF_PROLOGUE(AActor);
	FString res;
	GetCharacterName(self, &res);
	ACTION_RETURN_STRING(res);
}

static void SetTag(AActor *self, const FString &def)
{
	if (def.IsEmpty()) self->Tag = nullptr;
	else self->Tag = self->mStringPropertyData.Alloc(def);
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, SetTag, SetTag)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_STRING(def);
	SetTag(self, def);
	return 0;
}

static void ClearCounters(AActor *self)
{
	self->ClearCounters();
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, ClearCounters, ClearCounters)
{
	PARAM_SELF_PROLOGUE(AActor);
	self->ClearCounters();
	return 0;
}

static int GetModifiedDamage(AActor *self, int type, int damage, bool passive, AActor *inflictor, AActor *source, int flags)
{
	return self->GetModifiedDamage(ENamedName(type), damage, passive, inflictor, source, flags);
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, GetModifiedDamage, GetModifiedDamage)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_NAME(type);
	PARAM_INT(damage);
	PARAM_BOOL(passive);
	PARAM_OBJECT(inflictor, AActor);
	PARAM_OBJECT(source, AActor);
	PARAM_INT(flags);
	ACTION_RETURN_INT(self->GetModifiedDamage(type, damage, passive, inflictor, source, flags));
}

static int ApplyDamageFactor(AActor *self, int type, int damage)
{
	return self->ApplyDamageFactor(ENamedName(type), damage);
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, ApplyDamageFactor, ApplyDamageFactor)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_NAME(type);
	PARAM_INT(damage);
	ACTION_RETURN_INT(self->ApplyDamageFactor(type, damage));
}

double GetDefaultSpeed(PClassActor *type);

DEFINE_ACTION_FUNCTION_NATIVE(AActor, GetDefaultSpeed, GetDefaultSpeed)
{
	PARAM_PROLOGUE;
	PARAM_CLASS(type, AActor);
	ACTION_RETURN_FLOAT(GetDefaultSpeed(type));
}

static int isTeammate(AActor *self, AActor *other)
{
	return self->IsTeammate(PARAM_NULLCHECK(other, other));
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, isTeammate, isTeammate)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_OBJECT_NOT_NULL(other, AActor);
	ACTION_RETURN_BOOL(self->IsTeammate(other));
}

static int GetSpecies(AActor *self)
{
	return self->GetSpecies().GetIndex();
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, GetSpecies, GetSpecies)
{
	PARAM_SELF_PROLOGUE(AActor);
	ACTION_RETURN_INT(GetSpecies(self));
}

static int isFriend(AActor *self, AActor *other)
{
	return self->IsFriend(PARAM_NULLCHECK(other, other));
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, isFriend, isFriend)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_OBJECT_NOT_NULL(other, AActor);
	ACTION_RETURN_BOOL(self->IsFriend(other));
}

static int isHostile(AActor *self, AActor *other)
{
	return self->IsHostile(PARAM_NULLCHECK(other, other));
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, isHostile, isHostile)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_OBJECT_NOT_NULL(other, AActor);
	ACTION_RETURN_BOOL(self->IsHostile(other));
}

static FTerrainDef *GetFloorTerrain(AActor *self)
{
	return &Terrains[P_GetThingFloorType(self)];
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, GetFloorTerrain, GetFloorTerrain)
{
	PARAM_SELF_PROLOGUE(AActor);
	ACTION_RETURN_POINTER(GetFloorTerrain(self));
}

static int P_FindUniqueTID(FLevelLocals *Level, int start, int limit)
{
	return Level->FindUniqueTID(start, limit);
}

DEFINE_ACTION_FUNCTION_NATIVE(FLevelLocals, FindUniqueTid, P_FindUniqueTID)
{
	PARAM_SELF_STRUCT_PROLOGUE(FLevelLocals);
	PARAM_INT(start);
	PARAM_INT(limit);
	ACTION_RETURN_INT(P_FindUniqueTID(self, start, limit));
}

static void RemoveFromHash(AActor *self)
{
	self->SetTID(0);
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, RemoveFromHash, RemoveFromHash)
{
	PARAM_SELF_PROLOGUE(AActor);
	RemoveFromHash(self);
	return 0;
}

static void ChangeTid(AActor *self, int tid)
{
	self->SetTID(tid);
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, ChangeTid, ChangeTid)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_INT(tid);
	ChangeTid(self, tid);
	return 0;
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, FindFloorCeiling, P_FindFloorCeiling)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_INT(flags);
	P_FindFloorCeiling(self, flags);
	return 0;
}

static int TeleportMove(AActor *self, double x, double y, double z, bool telefrag, bool modify)
{
	return P_TeleportMove(self, DVector3(x, y, z), telefrag, modify);
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, TeleportMove, TeleportMove)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_FLOAT(x);
	PARAM_FLOAT(y);
	PARAM_FLOAT(z);
	PARAM_BOOL(telefrag);
	PARAM_BOOL(modify);
	ACTION_RETURN_BOOL(P_TeleportMove(self, DVector3(x, y, z), telefrag, modify));
}

static double ZS_GetFriction(AActor *self, double *mf)
{
	double friction;
	*mf = P_GetMoveFactor(self, &friction);
	return friction;
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, GetFriction, ZS_GetFriction)
{
	PARAM_SELF_PROLOGUE(AActor);
	double friction, movefactor = P_GetMoveFactor(self, &friction);
	if (numret > 1) ret[1].SetFloat(movefactor);
	if (numret > 0)	ret[0].SetFloat(friction);
	return numret;
}

static int CheckPosition(AActor *self, double x, double y, bool actorsonly, FCheckPosition *tm)
{
	if (tm)
	{
		return (P_CheckPosition(self, DVector2(x, y), *tm, actorsonly));
	}
	else
	{
		return (P_CheckPosition(self, DVector2(x, y), actorsonly));
	}
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, CheckPosition, CheckPosition)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_FLOAT(x);
	PARAM_FLOAT(y);
	PARAM_BOOL(actorsonly);
	PARAM_POINTER(tm, FCheckPosition);
	ACTION_RETURN_BOOL(CheckPosition(self, x, y, actorsonly, tm));
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, TestMobjLocation, P_TestMobjLocation)
{
	PARAM_SELF_PROLOGUE(AActor);
	ACTION_RETURN_BOOL(P_TestMobjLocation(self));
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, TestMobjZ, P_TestMobjZ)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_BOOL(quick);
	
	AActor *on = nullptr;
	bool retv = P_TestMobjZ(self, quick, &on);
	if (numret > 1) ret[1].SetObject(on);
	if (numret > 0) ret[0].SetInt(retv);
	return numret;
}

static int TryMove(AActor *self ,double x, double y, int dropoff, bool missilecheck, FCheckPosition *tm)
{
	if (tm == nullptr)
	{
		return (P_TryMove(self, DVector2(x, y), dropoff, nullptr, missilecheck));
	}
	else
	{
		return (P_TryMove(self, DVector2(x, y), dropoff, nullptr, *tm, missilecheck));
	}
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, TryMove, TryMove)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_FLOAT(x);
	PARAM_FLOAT(y);
	PARAM_INT(dropoff);
	PARAM_BOOL(missilecheck);
	PARAM_POINTER(tm, FCheckPosition);
	ACTION_RETURN_BOOL(TryMove(self, x, y, dropoff, missilecheck, tm));
}

static int CheckMove(AActor *self ,double x, double y, int flags, FCheckPosition *tm)
{
	if (tm == nullptr)
	{
		return (P_CheckMove(self, DVector2(x, y), flags));
	}
	else
	{
		return (P_CheckMove(self, DVector2(x, y), *tm, flags));
	}
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, CheckMove, CheckMove)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_FLOAT(x);
	PARAM_FLOAT(y);
	PARAM_INT(flags);
	PARAM_POINTER(tm, FCheckPosition);
	ACTION_RETURN_BOOL(CheckMove(self, x, y, flags, tm));
}

static double AimLineAttack(AActor *self, double angle, double distance, FTranslatedLineTarget *pLineTarget, double vrange, int flags, AActor *target, AActor *friender)
{
	flags &= ~ALF_IGNORENOAUTOAIM; // just to be safe. This flag is not supposed to be accesible to scripting.
	return P_AimLineAttack(self, DAngle::fromDeg(angle), distance, pLineTarget, DAngle::fromDeg(vrange), flags, target, friender).Degrees();
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, AimLineAttack, AimLineAttack)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_ANGLE(angle);
	PARAM_FLOAT(distance);
	PARAM_OUTPOINTER(pLineTarget, FTranslatedLineTarget);
	PARAM_ANGLE(vrange);
	PARAM_INT(flags);
	PARAM_OBJECT(target, AActor);
	PARAM_OBJECT(friender, AActor);
	ACTION_RETURN_FLOAT(P_AimLineAttack(self, angle, distance, pLineTarget, vrange, flags, target, friender).Degrees());
}

static AActor *ZS_LineAttack(AActor *self, double angle, double distance, double pitch, int damage, int damageType, PClassActor *puffType, int flags, FTranslatedLineTarget *victim, double offsetz, double offsetforward, double offsetside, int *actualdamage)
{
	if (puffType == nullptr) puffType = PClass::FindActor(NAME_BulletPuff);	// P_LineAttack does not work without a puff to take info from.
	return P_LineAttack(self, DAngle::fromDeg(angle), distance, DAngle::fromDeg(pitch), damage, ENamedName(damageType), puffType, flags, victim, actualdamage, offsetz, offsetforward, offsetside);
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, LineAttack, ZS_LineAttack)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_FLOAT(angle);
	PARAM_FLOAT(distance);
	PARAM_FLOAT(pitch);
	PARAM_INT(damage);
	PARAM_INT(damageType);
	PARAM_CLASS(puffType, AActor);
	PARAM_INT(flags);
	PARAM_OUTPOINTER(victim, FTranslatedLineTarget);
	PARAM_FLOAT(offsetz);
	PARAM_FLOAT(offsetforward);
	PARAM_FLOAT(offsetside);
	
	int acdmg;
	auto puff = ZS_LineAttack(self, angle, distance, pitch, damage, damageType, puffType, flags, victim, offsetz, offsetforward, offsetside, &acdmg);
	if (numret > 0) ret[0].SetObject(puff);
	if (numret > 1) ret[1].SetInt(acdmg), numret = 2;
	return numret;
}

static int LineTrace(AActor *self, double angle, double distance, double pitch, int flags, double offsetz, double offsetforward, double offsetside, FLineTraceData *data)
{
	return P_LineTrace(self,DAngle::fromDeg(angle),distance,DAngle::fromDeg(pitch),flags,offsetz,offsetforward,offsetside,data);
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, LineTrace, LineTrace)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_FLOAT(angle);
	PARAM_FLOAT(distance);
	PARAM_FLOAT(pitch);
	PARAM_INT(flags);
	PARAM_FLOAT(offsetz);
	PARAM_FLOAT(offsetforward);
	PARAM_FLOAT(offsetside);
	PARAM_OUTPOINTER(data, FLineTraceData);
	ACTION_RETURN_BOOL(P_LineTrace(self,DAngle::fromDeg(angle),distance,DAngle::fromDeg(pitch),flags,offsetz,offsetforward,offsetside,data));
}

DEFINE_ACTION_FUNCTION(AActor, PerformShadowChecks)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_OBJECT(other, AActor); //If this pointer is null, the trace uses the facing direction instead.
	PARAM_FLOAT(x);
	PARAM_FLOAT(y);
	PARAM_FLOAT(z);

	double penaltyFactor = 0.0;
	AActor* shadow = PerformShadowChecks(self, other, DVector3(x, y, z), penaltyFactor);
	if (numret > 2) ret[2].SetFloat(penaltyFactor);
	if (numret > 1) ret[1].SetObject(shadow);
	if (numret > 0) ret[0].SetInt(bool(shadow));
	return numret;
}


static void TraceBleedAngle(AActor *self, int damage, double angle, double pitch)
{
	P_TraceBleed(damage, self, DAngle::fromDeg(angle), DAngle::fromDeg(pitch));
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, TraceBleedAngle, TraceBleedAngle)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_INT(damage);
	PARAM_FLOAT(angle);
	PARAM_FLOAT(pitch);
	
	P_TraceBleed(damage, self, DAngle::fromDeg(angle), DAngle::fromDeg(pitch));
	return 0;
}

static void TraceBleedTLT(FTranslatedLineTarget *self, int damage, AActor *missile)
{
	P_TraceBleed(damage, self, PARAM_NULLCHECK(missile, missile));
}

DEFINE_ACTION_FUNCTION_NATIVE(_FTranslatedLineTarget, TraceBleed, TraceBleedTLT)
{
	PARAM_SELF_STRUCT_PROLOGUE(FTranslatedLineTarget);
	PARAM_INT(damage);
	PARAM_OBJECT_NOT_NULL(missile, AActor);
	
	P_TraceBleed(damage, self, missile);
	return 0;
}

static void TraceBleedA(AActor *self, int damage, AActor *missile)
{
	if (missile) P_TraceBleed(damage, self, missile);
	else P_TraceBleed(damage, self);
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, TraceBleed, TraceBleedA)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_INT(damage);
	PARAM_OBJECT(missile, AActor);
	TraceBleedA(self, damage, missile);
	return 0;
}

static void RailAttack(AActor *self, FRailParams *p)
{
	p->source = self;
	P_RailAttack(p);
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, RailAttack, RailAttack)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_POINTER(p, FRailParams);
	RailAttack(self, p);
	return 0;
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, UsePuzzleItem, P_UsePuzzleItem)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_INT(puzznum);
	ACTION_RETURN_BOOL(P_UsePuzzleItem(self, puzznum));
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, GetRadiusDamage, P_GetRadiusDamage)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_OBJECT(thing, AActor);
	PARAM_INT(damage);
	PARAM_FLOAT(distance);
	PARAM_FLOAT(fulldmgdistance);
	PARAM_BOOL(oldradiusdmg);
	PARAM_BOOL(circular);
	ACTION_RETURN_INT(P_GetRadiusDamage(self, thing, damage, distance, fulldmgdistance, oldradiusdmg, circular));
}

static int RadiusAttack(AActor *self, AActor *bombsource, int bombdamage, double bombdistance, int damagetype, int flags, double fulldamagedistance, int species)
{
	return P_RadiusAttack(self, bombsource, bombdamage, bombdistance, ENamedName(damagetype), flags, fulldamagedistance, ENamedName(species));
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, RadiusAttack, RadiusAttack)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_OBJECT(bombsource, AActor);
	PARAM_INT(bombdamage);
	PARAM_FLOAT(bombdistance);
	PARAM_INT(damagetype);
	PARAM_INT(flags);
	PARAM_FLOAT(fulldamagedistance);
	PARAM_INT(species);
	ACTION_RETURN_INT(RadiusAttack(self, bombsource, bombdamage, bombdistance, damagetype, flags, fulldamagedistance, species));
}

static int ZS_GetSpriteIndex(int sprt)
{
	return GetSpriteIndex(FName(ENamedName(sprt)).GetChars(), false);
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, GetSpriteIndex, ZS_GetSpriteIndex)
{
	PARAM_PROLOGUE;
	PARAM_INT(sprt);
	ACTION_RETURN_INT(ZS_GetSpriteIndex(sprt));
}

static PClassActor *ZS_GetReplacement(PClassActor *c)
{
	return c->GetReplacement(currentVMLevel);
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, GetReplacement, ZS_GetReplacement)
{
	PARAM_PROLOGUE;
	PARAM_POINTER(c, PClassActor);
	ACTION_RETURN_POINTER(ZS_GetReplacement(c));
}

static PClassActor *ZS_GetReplacee(PClassActor *c)
{
	return c->GetReplacee(currentVMLevel);
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, GetReplacee, ZS_GetReplacee)
{
	PARAM_PROLOGUE;
	PARAM_POINTER(c, PClassActor);
	ACTION_RETURN_POINTER(ZS_GetReplacee(c));
}

static void DrawSplash(AActor *self, int count, double angle, int kind)
{
	P_DrawSplash(self->Level, count, self->Pos(), DAngle::fromDeg(angle), kind);
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, DrawSplash, DrawSplash)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_INT(count);
	PARAM_FLOAT(angle);
	PARAM_INT(kind);
	P_DrawSplash(self->Level, count, self->Pos(), DAngle::fromDeg(angle), kind);
	return 0;
}

static void UnlinkFromWorld(AActor *self, FLinkContext *ctx)
{
	self->UnlinkFromWorld(ctx);
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, UnlinkFromWorld, UnlinkFromWorld)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_POINTER(ctx, FLinkContext);
	self->UnlinkFromWorld(ctx); // fixme
	return 0;
}

static void LinkToWorld(AActor *self, FLinkContext *ctx)
{
	self->LinkToWorld(ctx);
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, LinkToWorld, LinkToWorld)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_POINTER(ctx, FLinkContext);
	self->LinkToWorld(ctx);
	return 0;
}

static void SetOrigin(AActor *self, double x, double y, double z, bool moving)
{
	self->SetOrigin(x, y, z, moving);
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, SetOrigin, SetOrigin)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_FLOAT(x);
	PARAM_FLOAT(y);
	PARAM_FLOAT(z);
	PARAM_BOOL(moving);
	self->SetOrigin(x, y, z, moving);
	return 0;
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, RoughMonsterSearch, P_RoughMonsterSearch)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_INT(distance);
	PARAM_BOOL(onlyseekable);
	PARAM_BOOL(frontonly);
	PARAM_FLOAT(fov);
	ACTION_RETURN_OBJECT(P_RoughMonsterSearch(self, distance, onlyseekable, frontonly, fov));
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, CheckSight, P_CheckSight)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_OBJECT_NOT_NULL(target, AActor);
	PARAM_INT(flags);
	ACTION_RETURN_BOOL(P_CheckSight(self, target, flags));
}

static void GiveSecret(AActor *self, bool printmessage, bool playsound)
{
	P_GiveSecret(self->Level, self, printmessage, playsound, -1);
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, GiveSecret, GiveSecret)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_BOOL(printmessage);
	PARAM_BOOL(playsound);
	GiveSecret(self, printmessage, playsound);
	return 0;
}

static int ZS_GetMissileDamage(AActor *self, int mask, int add, int pick_pointer)
{
	self = COPY_AAPTR(self, pick_pointer);
	return self ? self->GetMissileDamage(mask, add) : 0;
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, GetMissileDamage, ZS_GetMissileDamage)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_INT(mask);
	PARAM_INT(add);
	PARAM_INT(pick_pointer);
	ACTION_RETURN_INT(ZS_GetMissileDamage(self, mask, add, pick_pointer));
}
	
DEFINE_ACTION_FUNCTION_NATIVE(AActor, SoundAlert, P_NoiseAlert)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_OBJECT(target, AActor);
	PARAM_BOOL(splash);
	PARAM_FLOAT(maxdist);
	P_NoiseAlert(self, target, splash, maxdist);
	return 0;
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, HitFriend, P_HitFriend)
{
	PARAM_SELF_PROLOGUE(AActor);
	ACTION_RETURN_BOOL(P_HitFriend(self));
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, MonsterMove, P_SmartMove)
{
	PARAM_SELF_PROLOGUE(AActor);
	ACTION_RETURN_BOOL(P_SmartMove(self));
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, NewChaseDir, P_NewChaseDir)
{
	PARAM_SELF_PROLOGUE(AActor);
	P_NewChaseDir(self);
	return 0;
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, RandomChaseDir, P_RandomChaseDir)
{
	PARAM_SELF_PROLOGUE(AActor);
	P_RandomChaseDir(self);
	return 0;
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, IsVisible, P_IsVisible)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_OBJECT(other, AActor);
	PARAM_BOOL(allaround);
	PARAM_POINTER(params, FLookExParams);
	ACTION_RETURN_BOOL(P_IsVisible(self, other, allaround, params));
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, LookForMonsters, P_LookForMonsters)
{
	PARAM_SELF_PROLOGUE(AActor);
	ACTION_RETURN_BOOL(P_LookForMonsters(self));
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, LookForTID, P_LookForTID)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_BOOL(allaround);
	PARAM_POINTER(params, FLookExParams);
	ACTION_RETURN_BOOL(P_LookForTID(self, allaround, params));
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, LookForEnemies, P_LookForEnemies)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_BOOL(allaround);
	PARAM_POINTER(params, FLookExParams);
	ACTION_RETURN_BOOL(P_LookForEnemies(self, allaround, params));
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, LookForPlayers, P_LookForPlayers)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_BOOL(allaround);
	PARAM_POINTER(params, FLookExParams);
	ACTION_RETURN_BOOL(P_LookForPlayers(self, allaround, params));
}

static int CheckMonsterUseSpecials(AActor *self, line_t *blocking)
{
	spechit_t spec;
	int good = 0;

	if (!(self->flags6 & MF6_NOTRIGGER))
	{
		auto checkLine = blocking ? blocking : self->BlockingLine;
		while (spechit.Pop (spec))
		{
			// [RH] let monsters push lines, as well as use them
			if (((self->flags4 & MF4_CANUSEWALLS) && P_ActivateLine (spec.line, self, 0, SPAC_Use)) ||
				((self->flags2 & MF2_PUSHWALL) && P_ActivateLine (spec.line, self, 0, SPAC_Push)))
			{
				good |= spec.line == checkLine ? 1 : 2;
			}
		}
	}
	else spechit.Clear();

	return good;
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, CheckMonsterUseSpecials, CheckMonsterUseSpecials)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_POINTER(blocking, line_t);

	ACTION_RETURN_INT(CheckMonsterUseSpecials(self, blocking));
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, A_Wander, A_Wander)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_INT(flags);
	A_Wander(self, flags);
	return 0;
}
//==========================================================================
//
// A_Chase and variations
//
//==========================================================================

static void A_FastChase(AActor *self)
{
	A_DoChase(self, true, self->MeleeState, self->MissileState, true, true, false, 0);
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, A_FastChase, A_FastChase)
{
	PARAM_SELF_PROLOGUE(AActor);
	A_FastChase(self);
	return 0;
}

static void A_VileChase(AActor *self)
{
	if (!P_CheckForResurrection(self, true))
	{
		A_DoChase(self, false, self->MeleeState, self->MissileState, true, gameinfo.nightmarefast, false, 0);
	}
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, A_VileChase, A_VileChase)
{
	PARAM_SELF_PROLOGUE(AActor);
	A_VileChase(self);
	return 0;
}

static void A_ExtChase(AActor *self, bool domelee, bool domissile, bool playactive, bool nightmarefast)
{
	// Now that A_Chase can handle state label parameters, this function has become rather useless...
	A_DoChase(self, false,
		domelee ? self->MeleeState : NULL, domissile ? self->MissileState : NULL,
		playactive, nightmarefast, false, 0);
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, A_ExtChase, A_ExtChase)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_BOOL(domelee);
	PARAM_BOOL(domissile);
	PARAM_BOOL(playactive);
	PARAM_BOOL(nightmarefast);
	A_ExtChase(self, domelee, domissile, playactive, nightmarefast);
	return 0;
}

int CheckForResurrection(AActor *self, FState* state, int sound)
{
	return P_CheckForResurrection(self, false, state, FSoundID::fromInt(sound));
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, A_CheckForResurrection, CheckForResurrection)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_POINTER(state, FState);
	PARAM_INT(sound);
	ACTION_RETURN_BOOL(CheckForResurrection(self, state, sound));
}

static void ZS_Face(AActor *self, AActor *faceto, double max_turn, double max_pitch, double ang_offset, double pitch_offset, int flags, double z_add)
{
	A_Face(self, faceto, DAngle::fromDeg(max_turn), DAngle::fromDeg(max_pitch), DAngle::fromDeg(ang_offset), DAngle::fromDeg(pitch_offset), flags, z_add);
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, A_Face, ZS_Face)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_OBJECT(faceto, AActor)
	PARAM_ANGLE(max_turn)
	PARAM_ANGLE(max_pitch)
	PARAM_ANGLE(ang_offset)
	PARAM_ANGLE(pitch_offset)
	PARAM_INT(flags)
	PARAM_FLOAT(z_add)

	A_Face(self, faceto, max_turn, max_pitch, ang_offset, pitch_offset, flags, z_add);
	return 0;
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, CheckBossDeath, CheckBossDeath)
{
	PARAM_SELF_PROLOGUE(AActor);
	ACTION_RETURN_BOOL(CheckBossDeath(self));
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, A_BossDeath, A_BossDeath)
{
	PARAM_SELF_PROLOGUE(AActor);
	A_BossDeath(self);
	return 0;
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, MorphInto, MorphPointerSubstitution)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_OBJECT(to, AActor);
	ACTION_RETURN_INT(MorphPointerSubstitution(self, to));
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, GetSpawnableType, P_GetSpawnableType)
{
	PARAM_PROLOGUE;
	PARAM_INT(num);
	ACTION_RETURN_POINTER(P_GetSpawnableType(num));
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, A_NoBlocking, A_Unblock)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_BOOL(drop);
	A_Unblock(self, drop);
	return 0;
}

static void CopyBloodColor(AActor* self, AActor* other)
{
	if (self && other)
	{
		self->BloodColor = other->BloodColor;
		self->BloodTranslation = other->BloodTranslation;
	}
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, CopyBloodColor, CopyBloodColor)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_OBJECT(other, AActor);
	CopyBloodColor(self, other);
	return 0;
}

//=====================================================================================
//
// Inventory exports
//
//=====================================================================================

DEFINE_ACTION_FUNCTION_NATIVE(AInventory, PrintPickupMessage, PrintPickupMessage)
{
	PARAM_PROLOGUE;
	PARAM_BOOL(localview);
	PARAM_STRING(str);
	PrintPickupMessage(localview, str);
	return 0;
}

//=====================================================================================
//
// Key exports
//
//=====================================================================================

DEFINE_ACTION_FUNCTION_NATIVE(AKey, IsLockDefined, P_IsLockDefined)
{
	PARAM_PROLOGUE;
	PARAM_INT(locknum);
	ACTION_RETURN_BOOL(P_IsLockDefined(locknum));
}

DEFINE_ACTION_FUNCTION_NATIVE(AKey, GetMapColorForLock, P_GetMapColorForLock)
{
	PARAM_PROLOGUE;
	PARAM_INT(locknum);
	ACTION_RETURN_INT(P_GetMapColorForLock(locknum));
}

DEFINE_ACTION_FUNCTION_NATIVE(AKey, GetMapColorForKey, P_GetMapColorForKey)
{
	PARAM_PROLOGUE;
	PARAM_OBJECT(key, AActor);
	ACTION_RETURN_INT(P_GetMapColorForKey(key));
}

DEFINE_ACTION_FUNCTION_NATIVE(AKey, GetKeyTypeCount, P_GetKeyTypeCount)
{
	PARAM_PROLOGUE;
	ACTION_RETURN_INT(P_GetKeyTypeCount());
}

DEFINE_ACTION_FUNCTION_NATIVE(AKey, GetKeyType, P_GetKeyType)
{
	PARAM_PROLOGUE;
	PARAM_INT(num);
	ACTION_RETURN_POINTER(P_GetKeyType(num));
}

//=====================================================================================
//
// 3D Floor exports
//
//=====================================================================================
int CheckFor3DFloorHit(AActor *self, double z, bool trigger)
{
	return P_CheckFor3DFloorHit(self, z, trigger);
}
DEFINE_ACTION_FUNCTION_NATIVE(AActor, CheckFor3DFloorHit, CheckFor3DFloorHit)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_FLOAT(z);
	PARAM_BOOL(trigger);

	ACTION_RETURN_BOOL(P_CheckFor3DFloorHit(self, z, trigger));
}

int CheckFor3DCeilingHit(AActor *self, double z, bool trigger)
{
	return P_CheckFor3DCeilingHit(self, z, trigger);
}
DEFINE_ACTION_FUNCTION_NATIVE(AActor, CheckFor3DCeilingHit, CheckFor3DCeilingHit)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_FLOAT(z);
	PARAM_BOOL(trigger);

	ACTION_RETURN_BOOL(P_CheckFor3DCeilingHit(self, z, trigger));
}

//=====================================================================================
//
// Bounce exports
//
//=====================================================================================
DEFINE_ACTION_FUNCTION(AActor, BounceActor)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_OBJECT(blocking, AActor);
	PARAM_BOOL(onTop);

	ACTION_RETURN_BOOL(P_BounceActor(self, blocking, onTop));
}

DEFINE_ACTION_FUNCTION(AActor, BounceWall)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_POINTER(l, line_t);

	auto cur = self->BlockingLine;
	if (l)
		self->BlockingLine = l;

	bool res = P_BounceWall(self);
	self->BlockingLine = cur;

	ACTION_RETURN_BOOL(res);
}

DEFINE_ACTION_FUNCTION(AActor, BouncePlane)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_POINTER(plane, secplane_t);
	PARAM_BOOL(is3DFloor);

	ACTION_RETURN_BOOL(self->FloorBounceMissile(*plane, is3DFloor));
}

DEFINE_ACTION_FUNCTION(AActor, PlayBounceSound)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_BOOL(onFloor);
	PARAM_FLOAT(volume);

	self->PlayBounceSound(onFloor, volume);
	return 0;
}

DEFINE_ACTION_FUNCTION(AActor, ReflectOffActor)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_OBJECT(blocking, AActor);

	ACTION_RETURN_BOOL(P_ReflectOffActor(self, blocking));
}



static int isFrozen(AActor *self)
{
	return self->isFrozen();
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, isFrozen, isFrozen)
{
	PARAM_SELF_PROLOGUE(AActor);
	ACTION_RETURN_BOOL(isFrozen(self));
}

//===========================================================================
//
// PlayerPawn functions
//
//===========================================================================

DEFINE_ACTION_FUNCTION_NATIVE(APlayerPawn, MarkPlayerSounds, S_MarkPlayerSounds)
{
	PARAM_SELF_PROLOGUE(AActor);
	S_MarkPlayerSounds(self);
	return 0;
}

static void GetPrintableDisplayNameJit(PClassActor *cls, FString *result)
{
	*result = cls->GetDisplayName();
}

DEFINE_ACTION_FUNCTION_NATIVE(APlayerPawn, GetPrintableDisplayName, GetPrintableDisplayNameJit)
{
	PARAM_PROLOGUE;
	PARAM_CLASS(type, AActor);
	ACTION_RETURN_STRING(type->GetDisplayName());
}

static void SetViewPos(AActor *self, double x, double y, double z, int flags)
{
	if (!self->ViewPos)
	{
		self->ViewPos = Create<DViewPosition>();
	}

	DVector3 pos = { x,y,z };
	self->ViewPos->Set(pos, flags);
}

DEFINE_ACTION_FUNCTION_NATIVE(AActor, SetViewPos, SetViewPos)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_FLOAT(x);
	PARAM_FLOAT(y);
	PARAM_FLOAT(z);
	PARAM_INT(flags);
	SetViewPos(self, x, y, z, flags);
	return 0;
}

IMPLEMENT_CLASS(DViewPosition, false, false);
DEFINE_FIELD_X(ViewPosition, DViewPosition, Offset)
DEFINE_FIELD_X(ViewPosition, DViewPosition, Flags)

DEFINE_FIELD(DThinker, Level)
DEFINE_FIELD(AActor, snext)
DEFINE_FIELD(AActor, player)
DEFINE_FIELD_NAMED(AActor, __Pos, pos)
DEFINE_FIELD_NAMED(AActor, __Pos.X, x)
DEFINE_FIELD_NAMED(AActor, __Pos.Y, y)
DEFINE_FIELD_NAMED(AActor, __Pos.Z, z)
DEFINE_FIELD(AActor, SpriteOffset)
DEFINE_FIELD(AActor, WorldOffset)
DEFINE_FIELD(AActor, Prev)
DEFINE_FIELD(AActor, SpriteAngle)
DEFINE_FIELD(AActor, SpriteRotation)
DEFINE_FIELD(AActor, VisibleStartAngle)
DEFINE_FIELD(AActor, VisibleStartPitch)
DEFINE_FIELD(AActor, VisibleEndAngle)
DEFINE_FIELD(AActor, VisibleEndPitch)
DEFINE_FIELD_NAMED(AActor, Angles.Yaw, angle)
DEFINE_FIELD_NAMED(AActor, Angles.Pitch, pitch)
DEFINE_FIELD_NAMED(AActor, Angles.Roll, roll)
DEFINE_FIELD(AActor, Vel)
DEFINE_FIELD(AActor, GravityDir)
DEFINE_FIELD(AActor, GravityAnchor)
DEFINE_FIELD_NAMED(AActor, Vel.X, velx)
DEFINE_FIELD_NAMED(AActor, Vel.Y, vely)
DEFINE_FIELD_NAMED(AActor, Vel.Z, velz)
DEFINE_FIELD_NAMED(AActor, Vel.X, momx)
DEFINE_FIELD_NAMED(AActor, Vel.Y, momy)
DEFINE_FIELD_NAMED(AActor, Vel.Z, momz)
DEFINE_FIELD(AActor, Speed)
DEFINE_FIELD(AActor, FloatSpeed)
DEFINE_FIELD(AActor, sprite)
DEFINE_FIELD(AActor, frame)
DEFINE_FIELD(AActor, Scale)
DEFINE_FIELD_NAMED(AActor, Scale.X, scalex)
DEFINE_FIELD_NAMED(AActor, Scale.Y, scaley)
DEFINE_FIELD(AActor, RenderStyle)
DEFINE_FIELD(AActor, picnum)
DEFINE_FIELD(AActor, Alpha)
DEFINE_FIELD(AActor, fillcolor)
DEFINE_FIELD_NAMED(AActor, Sector, CurSector)	// clashes with type 'sector'.
DEFINE_FIELD(AActor, subsector)
DEFINE_FIELD(AActor, ceilingz)
DEFINE_FIELD(AActor, floorz)
DEFINE_FIELD(AActor, dropoffz)
DEFINE_FIELD(AActor, floorsector)
DEFINE_FIELD(AActor, floorpic)
DEFINE_FIELD(AActor, floorterrain)
DEFINE_FIELD(AActor, ceilingsector)
DEFINE_FIELD(AActor, ceilingpic)
DEFINE_FIELD(AActor, Height)
DEFINE_FIELD(AActor, radius)
DEFINE_FIELD(AActor, renderradius)
DEFINE_FIELD(AActor, projectilepassheight)
DEFINE_FIELD(AActor, tics)
DEFINE_FIELD_NAMED(AActor, state, curstate)		// clashes with type 'state'.
DEFINE_FIELD_NAMED(AActor, DamageVal, Damage)	// name differs for historic reasons
DEFINE_FIELD(AActor, projectileKickback)
DEFINE_FIELD(AActor, VisibleToTeam)
DEFINE_FIELD(AActor, special1)
DEFINE_FIELD(AActor, special2)
DEFINE_FIELD(AActor, specialf1)
DEFINE_FIELD(AActor, specialf2)
DEFINE_FIELD(AActor, weaponspecial)
DEFINE_FIELD(AActor, health)
DEFINE_FIELD(AActor, Keywords)
DEFINE_FIELD(AActor, msdf_enabled)
DEFINE_FIELD(AActor, msdf_glitch)
DEFINE_FIELD(AActor, msdf_color)
DEFINE_FIELD(AActor, movedir)
DEFINE_FIELD(AActor, visdir)
DEFINE_FIELD(AActor, movecount)
DEFINE_FIELD(AActor, strafecount)
DEFINE_FIELD(AActor, target)
DEFINE_FIELD(AActor, master)
DEFINE_FIELD(AActor, tracer)
DEFINE_FIELD(AActor, damagesource)
DEFINE_FIELD(AActor, LastHeard)
DEFINE_FIELD(AActor, lastenemy)
DEFINE_FIELD(AActor, LastLookActor)
DEFINE_FIELD(AActor, reactiontime)
DEFINE_FIELD(AActor, threshold)
DEFINE_FIELD(AActor, DefThreshold)
DEFINE_FIELD(AActor, SpawnPoint)
DEFINE_FIELD(AActor, SpawnAngle)
DEFINE_FIELD(AActor, StartHealth)
DEFINE_FIELD(AActor, WeaveIndexXY)
DEFINE_FIELD(AActor, WeaveIndexZ)
DEFINE_FIELD(AActor, skillrespawncount)
DEFINE_FIELD(AActor, args)
DEFINE_FIELD(AActor, Mass)
DEFINE_FIELD(AActor, special)
DEFINE_FIELD(AActor, tid)
DEFINE_FIELD(AActor, TIDtoHate)
DEFINE_FIELD(AActor, waterlevel)
DEFINE_FIELD(AActor, waterdepth)
DEFINE_FIELD(AActor, Score)
DEFINE_FIELD(AActor, accuracy)
DEFINE_FIELD(AActor, stamina)
DEFINE_FIELD(AActor, LastHitZone)   // [XR] VR locational damage zone (0=torso 1=head 2=chest 3=legs)
DEFINE_FIELD(AActor, LastHitHand)   // [XR] hand that landed the hit (0=main 1=offhand)
DEFINE_FIELD(AActor, meleerange)
DEFINE_FIELD(AActor, PainThreshold)
DEFINE_FIELD(AActor, Gravity)
DEFINE_FIELD(AActor, Floorclip)
DEFINE_FIELD(AActor, DamageType)
DEFINE_FIELD(AActor, DamageTypeReceived)
DEFINE_FIELD(AActor, FloatBobPhase)
DEFINE_FIELD(AActor, FloatBobStrength)
DEFINE_FIELD(AActor, FloatBobFactor)
DEFINE_FIELD(AActor, RipperLevel)
DEFINE_FIELD(AActor, RipLevelMin)
DEFINE_FIELD(AActor, RipLevelMax)
DEFINE_FIELD(AActor, Species)
DEFINE_FIELD(AActor, alternative)
DEFINE_FIELD(AActor, goal)
DEFINE_FIELD(AActor, MinMissileChance)
DEFINE_FIELD(AActor, missilechancemult)
DEFINE_FIELD(AActor, LastLookPlayerNumber)
DEFINE_FIELD(AActor, SpawnFlags)
DEFINE_FIELD(AActor, meleethreshold)
DEFINE_FIELD(AActor, maxtargetrange)
DEFINE_FIELD(AActor, bouncefactor)
DEFINE_FIELD(AActor, wallbouncefactor)
DEFINE_FIELD(AActor, bouncecount)
DEFINE_FIELD(AActor, Friction)
DEFINE_FIELD(AActor, FastChaseStrafeCount)
DEFINE_FIELD(AActor, pushfactor)
DEFINE_FIELD(AActor, lastpush)
DEFINE_FIELD(AActor, activationtype)
DEFINE_FIELD(AActor, lastbump)
DEFINE_FIELD(AActor, DesignatedTeam)
DEFINE_FIELD(AActor, BlockingMobj)
DEFINE_FIELD(AActor, BlockingLine)
DEFINE_FIELD(AActor, MovementBlockingLine)
DEFINE_FIELD(AActor, Blocking3DFloor)
DEFINE_FIELD(AActor, BlockingCeiling)
DEFINE_FIELD(AActor, BlockingFloor)
DEFINE_FIELD(AActor, freezetics)
DEFINE_FIELD(AActor, PoisonDamage)
DEFINE_FIELD(AActor, PoisonDamageType)
DEFINE_FIELD(AActor, PoisonDuration)
DEFINE_FIELD(AActor, PoisonPeriod)
DEFINE_FIELD(AActor, PoisonDamageReceived)
DEFINE_FIELD(AActor, PoisonDamageTypeReceived)
DEFINE_FIELD(AActor, PoisonDurationReceived)
DEFINE_FIELD(AActor, PoisonPeriodReceived)
DEFINE_FIELD(AActor, Poisoner)
DEFINE_FIELD_NAMED(AActor, Inventory, Inv)		// clashes with type 'Inventory'.
DEFINE_FIELD(AActor, smokecounter)
DEFINE_FIELD(AActor, FriendPlayer)
DEFINE_FIELD(AActor, Translation)
DEFINE_FIELD(AActor, AttackSound)
DEFINE_FIELD(AActor, DeathSound)
DEFINE_FIELD(AActor, SeeSound)
DEFINE_FIELD(AActor, PainSound)
DEFINE_FIELD(AActor, ActiveSound)
DEFINE_FIELD(AActor, UseSound)
DEFINE_FIELD(AActor, BounceSound)
DEFINE_FIELD(AActor, WallBounceSound)
DEFINE_FIELD(AActor, CrushPainSound)
DEFINE_FIELD(AActor, MaxDropOffHeight)
DEFINE_FIELD(AActor, MaxStepHeight)
DEFINE_FIELD(AActor, MaxSlopeSteepness)
DEFINE_FIELD(AActor, PainChance)
DEFINE_FIELD(AActor, PainType)
DEFINE_FIELD(AActor, DeathType)
DEFINE_FIELD(AActor, DamageFactor)
DEFINE_FIELD(AActor, DamageMultiply)
DEFINE_FIELD(AActor, TeleFogSourceType)
DEFINE_FIELD(AActor, TeleFogDestType)
DEFINE_FIELD(AActor, SpawnState)
DEFINE_FIELD(AActor, SeeState)
DEFINE_FIELD(AActor, MeleeState)
DEFINE_FIELD(AActor, MissileState)
DEFINE_FIELD(AActor, ConversationRoot)
DEFINE_FIELD(AActor, Conversation)
DEFINE_FIELD(AActor, DecalGenerator)
DEFINE_FIELD(AActor, fountaincolor)
DEFINE_FIELD(AActor, CameraHeight)
DEFINE_FIELD(AActor, CameraFOV)
DEFINE_FIELD(AActor, RadiusDamageFactor)
DEFINE_FIELD(AActor, SelfDamageFactor)
DEFINE_FIELD(AActor, StealthAlpha)
DEFINE_FIELD(AActor, WoundHealth)
DEFINE_FIELD(AActor, BloodColor)
DEFINE_FIELD(AActor, BloodTranslation)
DEFINE_FIELD(AActor, RenderHidden)
DEFINE_FIELD(AActor, RenderRequired)
DEFINE_FIELD(AActor, friendlyseeblocks)
DEFINE_FIELD(AActor, SpawnTime)
DEFINE_FIELD(AActor, InventoryID)
DEFINE_FIELD(AActor, ThruBits)
DEFINE_FIELD(AActor, ViewPos)
DEFINE_FIELD(AActor, OverrideAttackPosDir)
DEFINE_FIELD(AActor, AttackPos)
DEFINE_FIELD(AActor, AttackPitch)
DEFINE_FIELD(AActor, AttackRoll)
DEFINE_FIELD(AActor, AttackAngle)
DEFINE_FIELD(AActor, OffhandPos)
DEFINE_FIELD(AActor, OffhandPitch)
DEFINE_FIELD(AActor, OffhandRoll)
DEFINE_FIELD(AActor, OffhandAngle)
DEFINE_FIELD_NAMED(AActor, ViewAngles.Yaw, viewangle)
DEFINE_FIELD_NAMED(AActor, ViewAngles.Pitch, viewpitch)
DEFINE_FIELD_NAMED(AActor, ViewAngles.Roll, viewroll)
DEFINE_FIELD(AActor, LightLevel)
DEFINE_FIELD(AActor, ShadowAimFactor)
DEFINE_FIELD(AActor, ShadowPenaltyFactor)
DEFINE_FIELD(AActor, AutomapOffsets)
DEFINE_FIELD(AActor, LandingSpeed)
DEFINE_FIELD(AActor, UnmorphTime)
DEFINE_FIELD(AActor, MorphFlags)
DEFINE_FIELD(AActor, PremorphProperties)
DEFINE_FIELD(AActor, MorphExitFlash)

DEFINE_FIELD_X(FCheckPosition, FCheckPosition, thing);
DEFINE_FIELD_X(FCheckPosition, FCheckPosition, pos);
DEFINE_FIELD_NAMED_X(FCheckPosition, FCheckPosition, sector, cursector);
DEFINE_FIELD_X(FCheckPosition, FCheckPosition, floorz);
DEFINE_FIELD_X(FCheckPosition, FCheckPosition, ceilingz);
DEFINE_FIELD_X(FCheckPosition, FCheckPosition, dropoffz);
DEFINE_FIELD_X(FCheckPosition, FCheckPosition, floorpic);
DEFINE_FIELD_X(FCheckPosition, FCheckPosition, floorterrain);
DEFINE_FIELD_X(FCheckPosition, FCheckPosition, floorsector);
DEFINE_FIELD_X(FCheckPosition, FCheckPosition, ceilingpic);
DEFINE_FIELD_X(FCheckPosition, FCheckPosition, ceilingsector);
DEFINE_FIELD_X(FCheckPosition, FCheckPosition, touchmidtex);
DEFINE_FIELD_X(FCheckPosition, FCheckPosition, abovemidtex);
DEFINE_FIELD_X(FCheckPosition, FCheckPosition, floatok);
DEFINE_FIELD_X(FCheckPosition, FCheckPosition, FromPMove);
DEFINE_FIELD_X(FCheckPosition, FCheckPosition, ceilingline);
DEFINE_FIELD_X(FCheckPosition, FCheckPosition, stepthing);
DEFINE_FIELD_X(FCheckPosition, FCheckPosition, DoRipping);
DEFINE_FIELD_X(FCheckPosition, FCheckPosition, portalstep);
DEFINE_FIELD_X(FCheckPosition, FCheckPosition, portalgroup);
DEFINE_FIELD_X(FCheckPosition, FCheckPosition, PushTime);

DEFINE_FIELD_X(FRailParams, FRailParams, source);
DEFINE_FIELD_X(FRailParams, FRailParams, damage);
DEFINE_FIELD_X(FRailParams, FRailParams, offset_xy);
DEFINE_FIELD_X(FRailParams, FRailParams, offset_z);
DEFINE_FIELD_X(FRailParams, FRailParams, color1);
DEFINE_FIELD_X(FRailParams, FRailParams, color2);
DEFINE_FIELD_X(FRailParams, FRailParams, maxdiff);
DEFINE_FIELD_X(FRailParams, FRailParams, flags);
DEFINE_FIELD_X(FRailParams, FRailParams, puff);
DEFINE_FIELD_X(FRailParams, FRailParams, angleoffset);
DEFINE_FIELD_X(FRailParams, FRailParams, pitchoffset);
DEFINE_FIELD_X(FRailParams, FRailParams, distance);
DEFINE_FIELD_X(FRailParams, FRailParams, duration);
DEFINE_FIELD_X(FRailParams, FRailParams, sparsity);
DEFINE_FIELD_X(FRailParams, FRailParams, drift);
DEFINE_FIELD_X(FRailParams, FRailParams, spawnclass);
DEFINE_FIELD_X(FRailParams, FRailParams, SpiralOffset);
DEFINE_FIELD_X(FRailParams, FRailParams, limit);

DEFINE_FIELD_X(FLineTraceData, FLineTraceData, HitActor);
DEFINE_FIELD_X(FLineTraceData, FLineTraceData, HitLine);
DEFINE_FIELD_X(FLineTraceData, FLineTraceData, HitSector);
DEFINE_FIELD_X(FLineTraceData, FLineTraceData, Hit3DFloor);
DEFINE_FIELD_X(FLineTraceData, FLineTraceData, HitTexture);
DEFINE_FIELD_X(FLineTraceData, FLineTraceData, HitLocation);
DEFINE_FIELD_X(FLineTraceData, FLineTraceData, HitDir);
DEFINE_FIELD_X(FLineTraceData, FLineTraceData, Distance);
DEFINE_FIELD_X(FLineTraceData, FLineTraceData, NumPortals);
DEFINE_FIELD_X(FLineTraceData, FLineTraceData, LineSide);
DEFINE_FIELD_X(FLineTraceData, FLineTraceData, LinePart);
DEFINE_FIELD_X(FLineTraceData, FLineTraceData, SectorPlane);
DEFINE_FIELD_X(FLineTraceData, FLineTraceData, HitType);

DEFINE_FIELD_NAMED_X(FSpawnParticleParams, FSpawnParticleParams, color, color1);
DEFINE_FIELD_X(FSpawnParticleParams, FSpawnParticleParams, texture);
DEFINE_FIELD_X(FSpawnParticleParams, FSpawnParticleParams, style);
DEFINE_FIELD_X(FSpawnParticleParams, FSpawnParticleParams, flags);
DEFINE_FIELD_X(FSpawnParticleParams, FSpawnParticleParams, lifetime);
DEFINE_FIELD_X(FSpawnParticleParams, FSpawnParticleParams, size);
DEFINE_FIELD_X(FSpawnParticleParams, FSpawnParticleParams, sizestep);
DEFINE_FIELD_X(FSpawnParticleParams, FSpawnParticleParams, pos);
DEFINE_FIELD_X(FSpawnParticleParams, FSpawnParticleParams, vel);
DEFINE_FIELD_X(FSpawnParticleParams, FSpawnParticleParams, accel);
DEFINE_FIELD_X(FSpawnParticleParams, FSpawnParticleParams, startalpha);
DEFINE_FIELD_X(FSpawnParticleParams, FSpawnParticleParams, fadestep);
DEFINE_FIELD_X(FSpawnParticleParams, FSpawnParticleParams, startroll);
DEFINE_FIELD_X(FSpawnParticleParams, FSpawnParticleParams, rollvel);
DEFINE_FIELD_X(FSpawnParticleParams, FSpawnParticleParams, rollacc);

static void SpawnParticle(FLevelLocals *Level, FSpawnParticleParams *params)
{
	P_SpawnParticle(Level,	params->pos, params->vel, params->accel,
		params->color, params->startalpha, params->lifetime,
		params->size, params->fadestep, params->sizestep,
		params->flags, params->texture, ERenderStyle(params->style),
		params->startroll, params->rollvel, params->rollacc);
}

DEFINE_ACTION_FUNCTION_NATIVE(FLevelLocals, SpawnParticle, SpawnParticle)
{
	PARAM_SELF_STRUCT_PROLOGUE(FLevelLocals);
	PARAM_POINTER(p, FSpawnParticleParams);
	SpawnParticle(self, p);
	return 0;
}

//==========================================================================
//
// Procedural IQM bone posing -- lets ZScript drive an actor's model bones
// each tic (the physics whip's Tier-2 rigged rope). Rides the existing
// animationData override seam in CalculateBonesIQM via DActorModelData::
// proceduralPose (see r_data/models.cpp ProcessModelFrame). Lives here in the
// quiet thunks file; XR_EnsureModelData replicates the file-static
// EnsureModelData in p_actionfunctions.cpp so we don't touch that file.
//
//==========================================================================

static void XR_EnsureModelData(AActor *mobj)
{
	if (mobj->modelData == nullptr)
	{
		auto ptr = Create<DActorModelData>();
		ptr->flags = (mobj->hasmodel ? MODELDATA_HADMODEL : 0);
		ptr->modelDef = nullptr;
		mobj->modelData = ptr;
		mobj->hasmodel = true;
		GC::WriteBarrier(mobj, ptr);
	}
}

DEFINE_ACTION_FUNCTION(AActor, SetModelUseProceduralPose)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_BOOL(enable);
	XR_EnsureModelData(self);
	self->modelData->useProceduralPose = enable;
	return 0;
}

// [XR] Read-only IQM hotspot (empty-bone) introspection exposed to ZScript. All FModel access lives in
// p_actionfunctions.cpp (which has r_data/models.h); these thunks call plain-return wrappers by forward-decl,
// so this file never needs the FModel class definition. Static bind data -- NEVER touch proceduralPose / the
// whip write path (SetModelBonePose above).
int  VR_WeaponBoneIndex(AActor* weapon, FName boneName);          // p_actionfunctions.cpp
bool VR_WeaponBoneBindPosByIdx(AActor* weapon, int boneIndex, FVector3& out); // p_actionfunctions.cpp

DEFINE_ACTION_FUNCTION(AActor, GetBoneIndex)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_NAME(boneName);
	ACTION_RETURN_INT(VR_WeaponBoneIndex(self, boneName));   // -1 if none / not an IQM (case-insensitive)
}

DEFINE_ACTION_FUNCTION(AActor, GetBoneBindPos)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_INT(boneIndex);
	FVector3 p(0.f, 0.f, 0.f);
	VR_WeaponBoneBindPosByIdx(self, boneIndex, p);           // leaves p at (0,0,0) on failure
	ACTION_RETURN_VEC3(DVector3(p.X, p.Y, p.Z));
}

// [XR weapon handling] Map a style name to player_t::EReloadStyle. Unknown -> RS_NONE (safe no-op).
static int XR_ReloadStyleFromName(const char* s)
{
	if (s == nullptr)                 return 0; // RS_NONE
	if (stricmp(s, "boxmag")   == 0)  return 1; // RS_BOXMAG
	if (stricmp(s, "shell")    == 0)  return 2; // RS_SHELL
	if (stricmp(s, "break")    == 0)  return 3; // RS_BREAK
	if (stricmp(s, "internal") == 0)  return 4; // RS_INTERNAL
	if (stricmp(s, "cylinder") == 0)  return 4; // RS_INTERNAL alias (revolver cylinder + speedloader)
	if (stricmp(s, "pod")      == 0)  return 5; // RS_POD
	if (stricmp(s, "canister") == 0)  return 6; // RS_CANISTER
	if (stricmp(s, "heatvent") == 0)  return 6; // RS_CANISTER alias (energy heat-vent)
	return 0; // RS_NONE
}

// [XR weapon handling] DATA-ONLY modder API -- the WHOLE ZScript surface. One line per weapon declares its
// reload STYLE; the engine reads the hs_* bones itself. Records style into player->vr_weapon_handling and
// invalidates the bone cache. Accepts the weapon actor (Owner is a player) OR a player pawn.
DEFINE_ACTION_FUNCTION(AActor, AssignWeaponHandling)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_STRING(style);
	player_t* player = (self != nullptr) ? self->player : nullptr;   // pawn case
	// weapon-declares-own-handling case: Owner is a ZScript Inventory field, not a C++ AActor member, so
	// read it by reflection (idiom from p_mobj.cpp:5571). Guard on IsKindOf(Inventory) so a non-inventory
	// self can't mis-read the field.
	if (player == nullptr && self != nullptr && self->IsKindOf(NAME_Inventory))
	{
		AActor* invOwner = self->PointerVar<AActor>(NAME_Owner);
		if (invOwner != nullptr) player = invOwner->player;
	}
	if (player == nullptr) { ACTION_RETURN_INT(0); }

	auto& wh = player->vr_weapon_handling;
	wh.style    = XR_ReloadStyleFromName(style.GetChars());
	wh.assigned = (wh.style != 0 /*RS_NONE*/);
	wh.resolved      = false;   // force fresh bone resolve next per-tic pass
	wh.resolvedClass = nullptr;
	wh.resolvedModel = nullptr;
	wh.boneForegrip  = -1;
	wh.boneMagwell   = -1;
	wh.boneRack      = -1;
	ACTION_RETURN_INT(wh.style);
}

DEFINE_ACTION_FUNCTION(AActor, SetModelBonePose)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_INT(boneIndex);
	PARAM_FLOAT(tx); PARAM_FLOAT(ty); PARAM_FLOAT(tz);
	PARAM_FLOAT(qx); PARAM_FLOAT(qy); PARAM_FLOAT(qz); PARAM_FLOAT(qw);
	if (boneIndex < 0) return 0;
	XR_EnsureModelData(self);
	auto &pose = self->modelData->proceduralPose;
	if ((unsigned)boneIndex >= pose.Size())
	{
		unsigned oldsize = pose.Size();
		pose.Resize(boneIndex + 1);
		// TRS default-ctors with scaling (0,0,0) -- init new slots to identity so any
		// bone left unwritten renders at its bind size instead of collapsing to nothing.
		for (unsigned k = oldsize; k < pose.Size(); k++)
		{
			pose[k].translation = FVector3(0.f, 0.f, 0.f);
			pose[k].rotation    = FVector4(0.f, 0.f, 0.f, 1.f);
			pose[k].scaling     = FVector3(1.f, 1.f, 1.f);
		}
	}
	TRS &t = pose[boneIndex];
	t.translation = FVector3((float)tx, (float)ty, (float)tz);
	t.rotation    = FVector4((float)qx, (float)qy, (float)qz, (float)qw);
	t.scaling     = FVector3(1.f, 1.f, 1.f);
	return 0;
}

//==========================================================================
//
// Native VR hardpoint mounts + analog grip + arm-IK enable, exposed to
// ZScript. A modder declares slots with ONE line (AssignHardpoint); all the
// per-tic proximity/grip math lives in C++ (VR_UpdateHardpoints, p_user.cpp).
// These thunks are the write/query seam into player_t.vr_hardpoints[].
//
//==========================================================================

EXTERN_CVAR(Float, vr_hardpoint_radius)

// Resolve the player_t that owns this actor's hardpoint slots. The VR runtime
// lives on the pawn's player, so a slot can only be assigned to a player pawn.
static player_t *XR_HardpointOwner(AActor *self)
{
	return (self != nullptr) ? self->player : nullptr;
}

DEFINE_ACTION_FUNCTION(AActor, AssignHardpoint)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_INT(anchor);          // EHardpointAnchor: 0=body, 1=wrist
	PARAM_INT(action);          // EHardpointAction: 0=holster, 1=ability
	PARAM_INT(hand);            // -1 either, 0=main, 1=off
	PARAM_FLOAT(ox);
	PARAM_FLOAT(oy);
	PARAM_FLOAT(oz);
	PARAM_FLOAT(radius);
	PARAM_NAME(weaponClass);    // ability/preferred weapon class (config only)
	PARAM_NAME(abilityName);    // ZScript event fired for HP_ACT_ABILITY
	PARAM_INT(cells);           // visual grid footprint ("squares"); UI-only. ZScript-side default
	                            // (actor.zs: int cells = 1) fills this in when a caller omits it.

	player_t *player = XR_HardpointOwner(self);
	if (player == nullptr) { ACTION_RETURN_INT(-1); }

	int idx = player->vr_hardpoint_count;
	if (idx < 0 || idx >= VR_MAX_HARDPOINTS) { ACTION_RETURN_INT(-1); }

	auto &slot = player->vr_hardpoints[idx];
	slot.anchor   = (anchor == HP_ANCHOR_WRIST) ? HP_ANCHOR_WRIST : HP_ANCHOR_BODY;
	slot.action   = (action == HP_ACT_ABILITY)  ? HP_ACT_ABILITY  : HP_ACT_HOLSTER;
	slot.hand     = (hand == 0 || hand == 1) ? hand : -1;
	slot.ox       = (float)ox;
	slot.oy       = (float)oy;
	slot.oz       = (float)oz;
	slot.radius   = (float)radius;   // <=0 => VR_UpdateHardpoints falls back to cvar
	slot.cells    = max(1, cells);
	slot.occupied = false;
	slot.enabled  = true;
	slot.stowedWeapon = nullptr;     // TObjPtr::operator=(nullptr_t); nothing stowed yet

	// weaponClass / abilityName are config-only hints resolved in the per-tic C++
	// subsystem; not stored in the fixed-size runtime struct (serialization parity
	// with vr_climbing_lines[2][10]). The config table keeps them.
	(void)weaponClass;
	(void)abilityName;

	player->vr_hardpoint_count = idx + 1;
	ACTION_RETURN_INT(idx);
}

DEFINE_ACTION_FUNCTION(AActor, ClearHardpoint)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_INT(slotIndex);

	player_t *player = XR_HardpointOwner(self);
	if (player == nullptr) return 0;
	if (slotIndex < 0 || slotIndex >= player->vr_hardpoint_count) return 0;

	auto &slot = player->vr_hardpoints[slotIndex];
	slot.enabled  = false;
	slot.occupied = false;
	slot.stowedWeapon = nullptr;   // drop the GC reference to any stowed weapon
	return 0;
}

DEFINE_ACTION_FUNCTION(AActor, IsHardpointNear)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_INT(hand);               // 0=main, 1=off

	player_t *player = XR_HardpointOwner(self);
	if (player == nullptr || player->mo == nullptr) { ACTION_RETURN_INT(-1); }
	const VRMode *vrmode = VRMode::GetVRModeCached(false);
	if (vrmode == nullptr) { ACTION_RETURN_INT(-1); }
	if (hand != 0) hand = 1;       // clamp to {0,1}

	// Read this hand's world position from the render-side hand matrix.
	// VSMatrix::get() (matrix.h:80) is const -> ok on a local. Column-major with the
	// engine-wide Y/Z swap: m[12]=X, m[14]=Z(map-up), m[13]=Y.
	VSMatrix handTransform;
	if (!vrmode->GetWeaponTransform(&handTransform, hand)) { ACTION_RETURN_INT(-1); }
	const float *m = handTransform.get();
	DVector3 handPos(m[12], m[14], m[13]);

	// Body anchor: playsim-safe head/eye pos (AttackPos), updated per-frame
	// from the VR device; r_viewpoint is render-thread only and invalid here.
	DVector3 bodyAnchor = player->mo->AttackPos;
	const double yawRad = player->mo->Angles.Yaw.Radians();
	const double cy = cos(yawRad), sy = sin(yawRad);

	int best = -1;
	double bestDistSq = 0.0;
	for (int i = 0; i < player->vr_hardpoint_count; ++i)
	{
		const auto &slot = player->vr_hardpoints[i];
		if (!slot.enabled) continue;
		if (slot.hand != -1 && slot.hand != hand) continue;

		DVector3 slotPos;
		if (slot.anchor == HP_ANCHOR_WRIST)
		{
			// Wrist slot rides the OTHER hand's transform + local offset.
			VSMatrix otherT;
			if (!vrmode->GetWeaponTransform(&otherT, hand ^ 1)) continue;
			const float *om = otherT.get();
			DVector3 otherPos(om[12], om[14], om[13]);
			slotPos = otherPos + DVector3(slot.ox, slot.oy, slot.oz);
		}
		else
		{
			// Body slot: anchor + yaw-rotated local offset (X/Y plane rotate; Z up).
			double rx = slot.ox * cy - slot.oy * sy;
			double ry = slot.ox * sy + slot.oy * cy;
			slotPos = bodyAnchor + DVector3(rx, ry, slot.oz);
		}

		double reach = (slot.radius > 0.f) ? (double)slot.radius : (double)vr_hardpoint_radius;
		double distSq = (handPos - slotPos).LengthSquared();
		if (distSq < reach * reach && (best == -1 || distSq < bestDistSq))
		{
			best = i;
			bestDistSq = distSq;
		}
	}
	ACTION_RETURN_INT(best);
}

DEFINE_ACTION_FUNCTION(AActor, GetHardpointStowed)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_INT(slotIndex);

	player_t *player = XR_HardpointOwner(self);
	if (player == nullptr) { ACTION_RETURN_OBJECT(nullptr); }
	if (slotIndex < 0 || slotIndex >= player->vr_hardpoint_count) { ACTION_RETURN_OBJECT(nullptr); }

	AActor *w = player->vr_hardpoints[slotIndex].stowedWeapon;
	ACTION_RETURN_OBJECT(w);
}

DEFINE_ACTION_FUNCTION(AActor, GetGripValue)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_INT(hand);

	// Analog squeeze 0..1 straight off the VRMode bridge (default 0 when not in VR).
	const VRMode *vrmode = VRMode::GetVRModeCached(false);
	double v = (vrmode != nullptr) ? (double)vrmode->GetGripValue(hand) : 0.0;
	ACTION_RETURN_FLOAT(v);
}

// [XR haptics] Pulse one controller from ZScript. hand: 0=LEFT, 1=RIGHT (raw controller
// index, same convention as GetGripValue). intensity 0..1 amplitude, duration in seconds
// (capped at 1s so a bad script value can't pin a controller on -- ProcessHaptics clamps
// amplitude but NOT duration). Calls Vibrate directly, bypassing VR_HapticEvent's int /100.
DEFINE_ACTION_FUNCTION(AActor, VR_HapticPulse)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_INT(hand);
	PARAM_FLOAT(intensity);
	PARAM_FLOAT(duration);

	const VRMode *vrmode = VRMode::GetVRModeCached(false);
	if (vrmode == nullptr) return 0;

	double a = intensity; if (a < 0.0) a = 0.0; if (a > 1.0) a = 1.0;
	float amp = (float)a;
	if (amp <= 0.0f) return 0;

	double d = duration; if (d < 0.0) d = 0.0; if (d > 1.0) d = 1.0;
	float dur = (float)d;
	if (dur <= 0.0f) return 0;

	int channel = (hand == 0) ? 0 : 1; // Vibrate CHANNEL: 0=Left, 1=Right
	vrmode->Vibrate(dur, channel, amp);
	return 0;
}

// [XR grip arbiter] Read the per-hand grip-ownership verdict (EGripOwner) that VR_ResolveGripOwner
// published this tic. PHYSICAL controller index (0=L,1=R). Returns GRIP_NONE(0) off-player/out-of-range.
DEFINE_ACTION_FUNCTION(AActor, VR_GetGripOwner)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_INT(physHand);
	player_t* p = self->player;
	if (p == nullptr || physHand < 0 || physHand > 1) ACTION_RETURN_INT(0 /*GRIP_NONE*/);
	ACTION_RETURN_INT(p->vr_grip_owner[physHand]);
}

// [XR grip arbiter] WEAPON-SLOT (VR_MAINHAND 0 / VR_OFFHAND 1) -> PHYSICAL controller index, handedness-correct.
// Delegates to the single authority in hw_vrmodes.cpp so ZScript never hand-rolls vr_control_scheme math.
DEFINE_ACTION_FUNCTION(AActor, VR_PhysicalHandForSlot)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_INT(slot);
	ACTION_RETURN_INT(VR_PhysicalHandForSlot(slot));
}

// [XR grip arbiter] The whip publishes rope-attached (GM_ATTACHED only) under the free hand's PHYSICAL
// index, so the arbiter can grant that hand GRIP_WHIP and the pump reads it back consistently.
DEFINE_ACTION_FUNCTION(AActor, VR_SetWhipRopeAttached)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_INT(physHand);
	PARAM_BOOL(attached);
	player_t* p = self->player;
	if (p != nullptr && physHand >= 0 && physHand <= 1) p->vr_whip_rope_attached[physHand] = attached;
	return 0;
}

DEFINE_ACTION_FUNCTION(AActor, SetArmIKEnabled)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_BOOL(enable);

	player_t *player = XR_HardpointOwner(self);
	if (player == nullptr) return 0;

	// Per-player ENABLE gate read by VR_UpdateArmIK (p_user.cpp:2347, alongside the
	// vr_ik_enable cvar). Must write vr_ik_ENABLED (the input gate) -- NOT vr_ik_active,
	// which is the solver's per-tic OUTPUT flag (overwritten to anySolved every tic), so
	// writing it here would be a silent no-op. When turned off, drop the solved pose too.
	player->vr_ik_enabled = enable;
	if (!enable)
	{
		player->vr_ik_pose.Clear();   // TArray<TRS>::Clear() -> IK subsystem sees empty = inactive
	}
	return 0;
}

// Number of currently-configured hardpoint slots for this player (for a ZScript
// marker-spawner to iterate 0..count-1). Read-only query, no side effects.
DEFINE_ACTION_FUNCTION(AActor, GetHardpointCount)
{
	PARAM_SELF_PROLOGUE(AActor);
	player_t *player = XR_HardpointOwner(self);
	ACTION_RETURN_INT(player ? player->vr_hardpoint_count : 0);
}

// Anchor type of a slot (EHardpointAnchor: 0=body, 1=wrist), for a marker script
// to pick a distinct color/icon per mount kind. -1 if the slot index is invalid.
DEFINE_ACTION_FUNCTION(AActor, GetHardpointAnchorType)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_INT(slotIndex);
	player_t *player = XR_HardpointOwner(self);
	if (player == nullptr || slotIndex < 0 || slotIndex >= player->vr_hardpoint_count) { ACTION_RETURN_INT(-1); }
	ACTION_RETURN_INT(player->vr_hardpoints[slotIndex].anchor);
}

// WORLD position of ANY slot, regardless of hand proximity -- for a visible-marker
// spawner to draw every configured hardpoint every tic (not just the "nearest to a
// gripping hand" query IsHardpointNear provides). Reuses the EXACT anchor math
// VR_UpdateHardpoints (p_user.cpp) applies, so a drawn marker always sits exactly
// where a real draw/stow grip would actually trigger -- no drift between the two.
//
// Factored out (not just inlined in the thunk below) so the native VRHardpointGrid_Draw
// renderer (hw_vr_hardpoint_grid.cpp) can call the SAME math directly -- declared in
// vr_hardpoint.h, external linkage, no header for DVector3 needed by callers (raw out[3]).
bool VR_ResolveHardpointWorldPos(player_t* player, int slotIndex, int forHand, double out[3])
{
	out[0] = out[1] = out[2] = 0.0;
	if (player == nullptr || player->mo == nullptr) return false;
	if (slotIndex < 0 || slotIndex >= player->vr_hardpoint_count) return false;

	const auto &slot = player->vr_hardpoints[slotIndex];
	if (forHand != 0) forHand = 1;

	const VRMode *vrmode = VRMode::GetVRModeCached(false);
	DVector3 result(0, 0, 0);

	if (slot.anchor == HP_ANCHOR_WRIST && vrmode != nullptr)
	{
		int other = forHand ^ 1;
		VSMatrix otherT;
		if (vrmode->GetWeaponTransform(&otherT, other))
		{
			const float *om = otherT.get();
			DVector3 otherPos(om[12], om[14], om[13]);
			result = otherPos + DVector3(slot.ox, slot.oy, slot.oz);
		}
	}
	else
	{
		DVector3 bodyAnchor = player->mo->AttackPos;
		const double yawRad = player->mo->Angles.Yaw.Radians();
		const double cy = cos(yawRad), sy = sin(yawRad);
		double rx = slot.ox * cy - slot.oy * sy;
		double ry = slot.ox * sy + slot.oy * cy;
		result = bodyAnchor + DVector3(rx, ry, slot.oz);
	}

	out[0] = result.X; out[1] = result.Y; out[2] = result.Z;
	return true;
}

DEFINE_ACTION_FUNCTION(AActor, GetHardpointWorldPos)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_INT(slotIndex);
	PARAM_INT(forHand);   // which hand's "other hand" to use for a WRIST slot; 0 or 1

	player_t *player = XR_HardpointOwner(self);
	double out[3];
	VR_ResolveHardpointWorldPos(player, slotIndex, forHand, out);
	ACTION_RETURN_VEC3(DVector3(out[0], out[1], out[2]));
}

DEFINE_ACTION_FUNCTION(AActor, VR_HolsterHand)
{
	PARAM_SELF_PROLOGUE(AActor);
	PARAM_INT(hand);          // 0=main, 1=off
	PARAM_INT(slotIndex);

	player_t *player = XR_HardpointOwner(self);
	if (player == nullptr || player->mo == nullptr) return 0;
	if (slotIndex < 0 || slotIndex >= player->vr_hardpoint_count) return 0;
	if (hand != 0) hand = 1;

	auto &slot = player->vr_hardpoints[slotIndex];

	// Capture the weapon actor being stowed off the correct hand slot.
	AActor *wpn = (hand == 0) ? player->ReadyWeapon : player->OffhandWeapon;
	slot.stowedWeapon = wpn;
	slot.occupied     = (wpn != nullptr);

	// The PSprite tear-down MUST run through the VM (no native PSprite mutator is
	// exposed). Call PlayerPawn.VR_DoHolster(hand, slotIndex) -- it clears the
	// weapon PSprite state and detaches ReadyWeapon/OffhandWeapon.
	IFVM(PlayerPawn, VR_DoHolster)
	{
		VMValue params[3] = { player->mo, hand, slotIndex };
		VMCall(func, params, 3, nullptr, 0);
	}
	return 0;
}
