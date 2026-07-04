//
//---------------------------------------------------------------------------
//
// Copyright(C) 2005-2016 Christoph Oelckers
// All rights reserved.
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Lesser General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Lesser General Public License for more details.
//
// You should have received a copy of the GNU Lesser General Public License
// along with this program.  If not, see http://www.gnu.org/licenses/
//
//--------------------------------------------------------------------------
//
/*
** gl_models.cpp
**
** General model handling code
**
**/

#include "filesystem.h"
#include "cmdlib.h"
#include "sc_man.h"
#include "m_crc32.h"
#include "c_console.h"
#include "g_game.h"
#include "doomstat.h"
#include "g_level.h"
#include "r_state.h"
#include "d_player.h"
#include "g_levellocals.h"
#include "r_utility.h"
#include "models.h"
#include "model_kvx.h"
#include "i_time.h"
#include "texturemanager.h"
#include "modelrenderer.h"
#include "actor.h"
#include "actorinlines.h"
#include "v_video.h"
#include "hw_bonebuffer.h"
#include "hw_vrmodes.h"


#ifdef _MSC_VER
#pragma warning(disable:4244) // warning C4244: conversion from 'double' to 'float', possible loss of data
#endif

CVAR(Bool, gl_interpolate_model_frames, true, CVAR_ARCHIVE)
EXTERN_CVAR(Bool, r_drawvoxels)
EXTERN_CVAR(Int, vr_control_scheme)
EXTERN_CVAR(Float, vr_weaponScale)
EXTERN_CVAR(Float, vr_3dweaponOffsetX);
EXTERN_CVAR(Float, vr_3dweaponOffsetY);
EXTERN_CVAR(Float, vr_3dweaponOffsetZ);
EXTERN_CVAR(Int, vr_mode)   // [XR] real VR-on check; vrmode->IsVR() lies (returns 0) in the render path

// [XR] Local VR body avatar tuning. vr_body_scale shrinks ONLY the local player's own body model,
// anchored at its feet (the mesh origin), so the head drops below the HMD while the feet stay on the
// floor -- fixes "my face is at chest level, I'm inside the mesh". vr_body_z is an extra vertical
// nudge in map units (+up) for fine-tuning. Both are live-tunable in the console. Default 0.70 puts a
// ~56u marine's head just under a standing eye; dial to taste.
CVAR(Float, vr_body_scale, 0.70f, CVAR_ARCHIVE | CVAR_GLOBALCONFIG)
CVAR(Float, vr_body_z,     0.0f,  CVAR_ARCHIVE | CVAR_GLOBALCONFIG)
// [XR] Yaw correction (degrees) for the local VR body only -- the marine mesh is authored ~90 off,
// so it faces sideways relative to the pawn. Added to the body's render yaw. Live-tunable; if it
// faces the wrong way at 90, try -90 / 180 / 270.
CVAR(Float, vr_body_yaw,   90.0f, CVAR_ARCHIVE | CVAR_GLOBALCONFIG)
// [XR] Auto-fit the body to the player's REAL height. When on (default), vr_body_scale is IGNORED and
// the body is scaled every frame so the marine's head sits vr_body_headroom map-units below the live
// HMD eye height (read from r_viewpoint.CenterEyePos, i.e. OpenXR floor-relative tracking), feet
// planted. Fits any player, standing or seated, with no tuning. vr_body_scale is the manual fallback
// when auto-fit is off.
CVAR(Bool,  vr_body_autofit,  true, CVAR_ARCHIVE | CVAR_GLOBALCONFIG)
CVAR(Float, vr_body_headroom, 4.0f, CVAR_ARCHIVE | CVAR_GLOBALCONFIG)

// [XR] The live body-fit scale actually applied to the local avatar this frame (autofit smoothed
// value, or the manual vr_body_scale when autofit is off). Published so the playsim arm-IK
// (p_user.cpp VR_UpdateArmIK) can divide the world hand target by the SAME scale the renderer used,
// converting the target from rendered-body space into the unscaled baseframe the IK solves in.
// Written on the render thread, read on the playsim thread: a plain float, at worst one frame stale,
// and the value is heavily smoothed, so no sync is needed.
float g_xr_vrBodyRenderScale = 0.70f;

extern TDeletingArray<FVoxel *> Voxels;
extern TDeletingArray<FVoxelDef *> VoxelDefs;

void RenderFrameModels(FModelRenderer* renderer, FLevelLocals* Level, const FSpriteModelFrame *smf, const FState* curState, const int curTics, FTranslationID translation, AActor* actor);


void RenderModel(FModelRenderer *renderer, float x, float y, float z, FSpriteModelFrame *smf, AActor *actor, double ticFrac)
{
	// Setup transformation.

	int smf_flags = smf->getFlags(actor->modelData);

	FTranslationID translation = NO_TRANSLATION;
	if (!(smf_flags & MDL_IGNORETRANSLATION))
		translation = actor->Translation;

	// y scale for a sprite means height, i.e. z in the world!
	float scaleFactorX = actor->Scale.X * smf->xscale;
	float scaleFactorY = actor->Scale.X * smf->yscale;
	float scaleFactorZ = actor->Scale.Y * smf->zscale;

	// [XR] Local VR body avatar: shrink ONLY the player's own body model, anchored at its feet (the
	// mesh origin -- the scale at objectToWorldMatrix.scale() below is applied around model space 0,0,0
	// which for the marine is between the feet). This drops the head below the HMD while the feet stay
	// planted. Every other actor renders unchanged. vr_body_z adds a vertical nudge for fine-tuning.
	const bool isVRBody = ((int)vr_mode != 0 && actor == players[consoleplayer].mo);
	if (isVRBody)
	{
		float bodyScale = vr_body_scale;   // manual fallback
		if (vr_body_autofit)
		{
			// CenterEyePos.Z - actor->Z() == the live HMD eye height above the floor in map units
			// (OpenXR floor-relative tracking, already * vr_vunits_per_meter). Smooth it so head-bob
			// doesn't pulse the body -- only the slow standing height tracks. Then scale the marine so
			// its head (~actor Height at scale 1) sits vr_body_headroom units below the eyes, feet planted.
			double eyeAboveFeet = r_viewpoint.CenterEyePos.Z - actor->Z();
			static double smoothedEye = 0.0;
			if (eyeAboveFeet > 1.0)
			{
				if (smoothedEye <= 0.0) smoothedEye = eyeAboveFeet;
				else                    smoothedEye += (eyeAboveFeet - smoothedEye) * 0.03;
			}
			const double headH = (actor->Height > 1.0) ? actor->Height : 56.0;
			if (smoothedEye > 1.0)
				bodyScale = (float)clamp((smoothedEye - (double)vr_body_headroom) / headH, 0.25, 1.6);
		}
		// [XR] Publish the exact scale we're about to apply so the playsim arm-IK divides the hand
		// target by the SAME factor (see g_xr_vrBodyRenderScale decl above). Do this even when the
		// scale is 1.0 so a stale value never lingers.
		if (bodyScale > 0.05f && bodyScale < 8.0f) g_xr_vrBodyRenderScale = bodyScale;
		if (bodyScale > 0.f && bodyScale != 1.f)
		{
			scaleFactorX *= bodyScale;
			scaleFactorY *= bodyScale;
			scaleFactorZ *= bodyScale;
		}
	}
	float pitch = 0;
	float roll = 0;
	double rotateOffset = 0;
	DRotator angles;
	if (actor->renderflags & RF_INTERPOLATEANGLES) // [Nash] use interpolated angles
		angles = actor->InterpolatedAngles(ticFrac);
	else
		angles = actor->Angles;
	float angle = angles.Yaw.Degrees();

	// [BB] Workaround for the missing pitch information.
	if ((smf_flags & MDL_PITCHFROMMOMENTUM))
	{
		const double x = actor->Vel.X;
		const double y = actor->Vel.Y;
		const double z = actor->Vel.Z;

		if (actor->Vel.LengthSquared() > EQUAL_EPSILON)
		{
			// [BB] Calculate the pitch using spherical coordinates.
			if (z || x || y) pitch = float(atan(z / sqrt(x*x + y*y)) / M_PI * 180);

			// Correcting pitch if model is moving backwards
			if (fabs(x) > EQUAL_EPSILON || fabs(y) > EQUAL_EPSILON)
			{
				if ((x * cos(angle * M_PI / 180) + y * sin(angle * M_PI / 180)) / sqrt(x * x + y * y) < 0) pitch *= -1;
			}
			else pitch = fabs(pitch);
		}
	}

	if (smf_flags & MDL_ROTATING)
	{
		if (smf->rotationSpeed > 0.0000000001 || smf->rotationSpeed < -0.0000000001)
		{
			double turns = (I_GetTime() + I_GetTimeFrac()) / (200.0 / smf->rotationSpeed);
			turns -= floor(turns);
			rotateOffset = turns * 360.0;
		}
		else
		{
			rotateOffset = 0.0;
		}
	}

	// Added MDL_USEACTORPITCH and MDL_USEACTORROLL flags processing.
	// If both flags MDL_USEACTORPITCH and MDL_PITCHFROMMOMENTUM are set, the pitch sums up the actor pitch and the velocity vector pitch.
	if (smf_flags & MDL_USEACTORPITCH)
	{
		double d = angles.Pitch.Degrees();
		if (smf_flags & MDL_BADROTATION) pitch += d;
		else pitch -= d;
	}
	if (smf_flags & MDL_USEACTORROLL) roll += angles.Roll.Degrees();

	VSMatrix objectToWorldMatrix;
	objectToWorldMatrix.loadIdentity();

	// Model space => World space ([XR] +vr_body_z raises/lowers the local VR body only)
	objectToWorldMatrix.translate(x, z + (isVRBody ? (double)vr_body_z : 0.0), y);

	// [Nash] take SpriteRotation into account
	angle += actor->SpriteRotation.Degrees();

	// [XR] correct the local VR body's facing (marine mesh authored ~90 off). Body only.
	if (isVRBody) angle += vr_body_yaw;

	// [XR] Decouple the body facing from the HMD: the pawn yaw follows the headset, so without this the
	// whole torso spins when you turn your head ("no neck"). If P_PlayerThink has a valid decoupled
	// body yaw, render the body at THAT heading (plus the mesh-correction + sprite rotation) instead of
	// the raw HMD-slaved pawn yaw. Pawn Angles.Yaw is untouched, so gameplay + arm-IK targets are as-is.
	if (isVRBody && actor->player != nullptr && actor->player->vr_body_facing_valid)
	{
		angle = actor->player->vr_body_facing_yaw + vr_body_yaw + actor->SpriteRotation.Degrees();
	}

	// consider the pixel stretching. For non-voxels this must be factored out here
	float stretch = 1.f;

	// [MK] distortions might happen depending on when the pixel stretch is compensated for
	// so we make the "undistorted" behavior opt-in
	if ((smf_flags & MDL_CORRECTPIXELSTRETCH) && smf->modelIDs.Size() > 0)
	{
		stretch = (smf->modelIDs[0] >= 0 ? Models[smf->modelIDs[0]]->getAspectFactor(actor->Level->info->pixelstretch) : 1.f) / actor->Level->info->pixelstretch;
		objectToWorldMatrix.scale(1, stretch, 1);
	}

	// Applying model transformations:
	// 1) Applying actor angle, pitch and roll to the model
	if (smf_flags & MDL_USEROTATIONCENTER)
	{
		objectToWorldMatrix.translate(smf->rotationCenterX, smf->rotationCenterZ/stretch, smf->rotationCenterY);
	}
	objectToWorldMatrix.rotate(-angle, 0, 1, 0);
	objectToWorldMatrix.rotate(pitch, 0, 0, 1);
	objectToWorldMatrix.rotate(-roll, 1, 0, 0);
	if (smf_flags & MDL_USEROTATIONCENTER)
	{
		objectToWorldMatrix.translate(-smf->rotationCenterX, -smf->rotationCenterZ/stretch, -smf->rotationCenterY);
	}

	// 2) Applying Doomsday like rotation of the weapon pickup models
	// The rotation angle is based on the elapsed time.

	if (smf_flags & MDL_ROTATING)
	{
		objectToWorldMatrix.translate(smf->rotationCenterX, smf->rotationCenterY/stretch, smf->rotationCenterZ);
		objectToWorldMatrix.rotate(rotateOffset, smf->xrotate, smf->yrotate, smf->zrotate);
		objectToWorldMatrix.translate(-smf->rotationCenterX, -smf->rotationCenterY/stretch, -smf->rotationCenterZ);
	}

	// 3) Scaling model.
	objectToWorldMatrix.scale(scaleFactorX, scaleFactorZ, scaleFactorY);

	// 4) Aplying model offsets (model offsets do not depend on model scalings).
	objectToWorldMatrix.translate(smf->xoffset / smf->xscale, smf->zoffset / (smf->zscale*stretch), smf->yoffset / smf->yscale);

	// 5) Applying model rotations.
	objectToWorldMatrix.rotate(-smf->angleoffset, 0, 1, 0);
	objectToWorldMatrix.rotate(smf->pitchoffset, 0, 0, 1);
	objectToWorldMatrix.rotate(-smf->rolloffset, 1, 0, 0);

	if (!(smf_flags & MDL_CORRECTPIXELSTRETCH) && smf->modelIDs.Size() > 0)
	{
		stretch = (smf->modelIDs[0] >= 0 ? Models[smf->modelIDs[0]]->getAspectFactor(actor->Level->info->pixelstretch) : 1.f) / actor->Level->info->pixelstretch;
		objectToWorldMatrix.scale(1, stretch, 1);
	}

	float orientation = scaleFactorX * scaleFactorY * scaleFactorZ;

	renderer->BeginDrawModel(actor->RenderStyle, smf_flags, objectToWorldMatrix, orientation < 0);
	RenderFrameModels(renderer, actor->Level, smf, actor->state, actor->tics, translation, actor);
	renderer->EndDrawModel(actor->RenderStyle, smf_flags);
}

void RenderHUDModel(FModelRenderer *renderer, DPSprite *psp, FVector3 translation, FVector3 rotation, FVector3 rotation_pivot, FSpriteModelFrame *smf, int forceHand)
{
	auto vrmode = VRMode::GetVRModeCached(true);
	AActor * playermo = players[consoleplayer].camera;

	// [XR] TEMP hand-swap diagnostic (throttled per process run): does the fist-swap fire, and does
	// the VRHandModel model actually resolve a frame? handFrame=0 => the hand model isn't loading
	// (hands would never render even when punching); fistKW=0 => the held weapon just isn't a fist.
	// Remove once hands are confirmed.
	{
		static int s_hudHandDbg = 0;
		if (s_hudHandDbg < 16)
		{
			s_hudHandDbg++;
			bool isFist = psp && psp->Caller && psp->Caller->Keywords.IndexOf("fist") != -1;
			PClassActor* hc = PClass::FindActor("VRHandModel");
			int handFrame = 0;
			if (hc) { FState* st = hc->FindState(NAME_Spawn); if (st) handFrame = (FindModelFrame(hc, st->sprite, st->GetFrame(), true) != nullptr); }
			Printf("[VRHUDHAND] isVR=%d caller=%s fistKW=%d handClass=%d handFrame=%d\n",
				(int)vrmode->IsVR(),
				(psp && psp->Caller ? psp->Caller->GetClass()->TypeName.GetChars() : "none"),
				(int)isFist, (int)(hc != nullptr), handFrame);
		}
	}

	// Intercept fist rendering for VR Hand Hot-Swapping. Gate on vr_mode (the actual setting) OR
	// IsVR() -- IsVR() returns 0 in the render path even in VR (see hw_sprites body-avatar note), which
	// was silently disabling the fist->hand swap entirely, i.e. "no hands even when punching".
	if (((int)vr_mode != 0 || vrmode->IsVR()) && psp->Caller && psp->Caller->Keywords.IndexOf("fist") != -1)
	{
		// Try to find the global VRHandModel class
		PClassActor* handClass = PClass::FindActor("VRHandModel");
		if (handClass)
		{
			// Determine which hand we are rendering (0 = main, 1 = offhand)
			int handIdx = (forceHand >= 0) ? forceHand : (psp->GetCaller() == playermo->player->OffhandWeapon ? 1 : 0);
			int handState = playermo->player->vr_hand_state[handIdx];

			// Map hand state to ZScript State name
			// 0 = Idle (Spawn), 1 = Grip, 2 = Climb, 3 = Point
			FName stateName = NAME_Spawn;
			if (handState == 1) stateName = "Grip";
			else if (handState == 2) stateName = "Climb";
			else if (handState == 3) stateName = "Point";

			FState* targetState = handClass->FindState(stateName);
			
			if (targetState)
			{
				FSpriteModelFrame* handSmf = FindModelFrame(handClass, targetState->sprite, targetState->GetFrame(), true);
				if (handSmf) 
				{
					smf = handSmf;
				}
			}
		}
	}

	// [BB] No model found for this sprite, so we can't render anything.
	if (smf == nullptr)
		return;

	// [XR] Is the model being drawn the VR hand -- either the fist-swap above set smf = VRHandModel, or
	// the standalone gun-hands path (hw_weapon.cpp) passed it in as smf? If so, resolve its flags from
	// its OWN modeldef (nullptr modelData), NOT the weapon's: the weapon's overrideFlagsClear can strip
	// the hand's MDL_MODELSAREATTACHMENTS, which gates the bind-pose bone upload -- and stripping it left
	// vhand.iqm (0-baked-frame rig) uploading no bones -> the hand rendered as zero geometry.
	static const PClass* s_vrHandClass = PClass::FindActor("VRHandModel");
	const bool handSwapped = (smf->type != nullptr && smf->type == s_vrHandClass);

	int smf_flags = smf->getFlags(handSwapped ? nullptr : (psp->Caller ? psp->Caller->modelData : nullptr));

	// The model position and orientation has to be drawn independently from the position of the player,
	// but we need to position it correctly in the world for light to work properly.
	VSMatrix objectToWorldMatrix = renderer->GetViewToWorldMatrix();
	int hand = (forceHand >= 0) ? forceHand : ((psp && psp->GetCaller() == playermo->player->OffhandWeapon) ? 1 : 0);
	if (vrmode->GetWeaponTransform(&objectToWorldMatrix, hand))
	{
		float scale = 0.01f;
		objectToWorldMatrix.scale(scale, scale, scale);
		objectToWorldMatrix.translate(0, 5, 30);
	}
	else if (vrmode->IsVR())
	{
		DVector3 pos = playermo->Pos();
		objectToWorldMatrix.translate(pos.X, pos.Z + 40, pos.Y);
		objectToWorldMatrix.rotate(-playermo->Angles.Yaw.Degrees() - 90, 0, 1, 0);
	}

	// [Nash] Optional scale weapon FOV
	float fovscale = 1.0f;
	if (smf_flags & MDL_SCALEWEAPONFOV)
	{
		fovscale = tan(players[consoleplayer].DesiredFOV * (0.5f * M_PI / 180.f));
		fovscale = 1.f + (fovscale - 1.f) * cl_scaleweaponfov;
	}

	// Scaling model (y scale for a sprite means height, i.e. z in the world!).
	objectToWorldMatrix.scale(smf->xscale, smf->zscale, smf->yscale / fovscale);

	// Aplying model offsets (model offsets do not depend on model scalings).
	objectToWorldMatrix.translate(smf->xoffset / smf->xscale, smf->zoffset / smf->zscale, smf->yoffset / smf->yscale);

	// Applying player custom offsets
	objectToWorldMatrix.translate(-vr_3dweaponOffsetX, vr_3dweaponOffsetY, vr_3dweaponOffsetZ);

	// [BB] Weapon bob, very similar to the normal Doom weapon bob.

	

	objectToWorldMatrix.translate(rotation_pivot.X, rotation_pivot.Y, rotation_pivot.Z);
	
	objectToWorldMatrix.rotate(rotation.X, 0, 1, 0);
	objectToWorldMatrix.rotate(rotation.Y, 1, 0, 0);
	objectToWorldMatrix.rotate(rotation.Z, 0, 0, 1);

	objectToWorldMatrix.translate(-rotation_pivot.X, -rotation_pivot.Y, -rotation_pivot.Z);
	
	objectToWorldMatrix.translate(translation.X, translation.Y, translation.Z);
	

	// [BB] For some reason the jDoom models need to be rotated.
	objectToWorldMatrix.rotate(90.f, 0, 1, 0);

	// Applying angleoffset, pitchoffset, rolloffset.
	objectToWorldMatrix.rotate(-smf->angleoffset, 0, 1, 0);
	objectToWorldMatrix.rotate(smf->pitchoffset, 0, 0, 1);
	objectToWorldMatrix.rotate(-smf->rolloffset, 1, 0, 0);

	//Scale weapon
	objectToWorldMatrix.scale(vr_weaponScale, vr_weaponScale, vr_weaponScale);

	float orientation = smf->xscale * smf->yscale * smf->zscale;

	renderer->BeginDrawHUDModel(playermo->RenderStyle, objectToWorldMatrix, orientation < 0, smf_flags);
	auto trans = psp->GetTranslation();
	if ((psp->Flags & PSPF_PLAYERTRANSLATED)) trans = psp->Owner->mo->Translation;

	// [XR] Defense-in-depth for the VR hand: if the WEAPON (psp->Caller) is DECOUPLEDANIMATIONS,
	// CalcModelFrame substitutes BaseSpriteModelFrames[weapon->GetClass()] for our swapped hand smf,
	// discarding the hand frame before any bones upload. Temporarily clear the flag across just this
	// hand render so the substitution can't fire, then restore it (single call, fully reverted).
	decltype(psp->Caller->flags9) xr_savedFlags9{}; bool xr_clearedDecouple = false;   // ActorFlags9, not uint
	if (handSwapped && psp->Caller && (psp->Caller->flags9 & MF9_DECOUPLEDANIMATIONS))
	{
		xr_savedFlags9 = psp->Caller->flags9;
		psp->Caller->flags9 &= ~MF9_DECOUPLEDANIMATIONS;
		xr_clearedDecouple = true;
	}
	RenderFrameModels(renderer, playermo->Level, smf, psp->GetState(), psp->GetTics(), trans, psp->Caller);
	if (xr_clearedDecouple) psp->Caller->flags9 = xr_savedFlags9;
	renderer->EndDrawHUDModel(playermo->RenderStyle, smf_flags);
}

double getCurrentFrame(const ModelAnim &anim, double tic, bool *looped)
{
	if(anim.framerate <= 0) return anim.startFrame;

	double frame = ((tic - anim.startTic) / GameTicRate) * anim.framerate; // position in frames

	double duration = double(anim.lastFrame) - anim.startFrame;

	if((anim.flags & MODELANIM_LOOP) && frame >= duration)
	{
		if(looped) *looped = true;
		frame = frame - duration;
		return fmod(frame, anim.lastFrame - anim.loopFrame) + anim.loopFrame;
	}
	else
	{
		return min(frame, duration) + anim.startFrame;
	}
}

void calcFrame(const ModelAnim &anim, double tic, ModelAnimFrameInterp &inter)
{
	bool looped = false;

	double frame = getCurrentFrame(anim, tic, &looped);

	inter.frame1 = int(floor(frame));

	inter.inter = frame - inter.frame1;

	inter.frame2 = int(ceil(frame));

	int startFrame = (looped ? anim.loopFrame : anim.startFrame);

	if(inter.frame1 < startFrame) inter.frame1 = anim.lastFrame;
	if(inter.frame2 > anim.lastFrame) inter.frame2 = startFrame;
}

void calcFrames(const ModelAnim &curAnim, double tic, ModelAnimFrameInterp &to, float &inter)
{
	if(curAnim.startTic > tic)
	{
		inter = (tic - (curAnim.startTic - curAnim.switchOffset)) / curAnim.switchOffset;

		calcFrame(curAnim, curAnim.startTic, to);
	}
	else
	{
		inter = -1.0f;
		calcFrame(curAnim, tic, to);
	}
}

CalcModelFrameInfo CalcModelFrame(FLevelLocals *Level, const FSpriteModelFrame *smf, const FState *curState, const int curTics, DActorModelData* data, AActor* actor, bool is_decoupled, double tic)
{
	// [BB] Frame interpolation: Find the FSpriteModelFrame smfNext which follows after smf in the animation
	// and the scalar value inter ( element of [0,1) ), both necessary to determine the interpolated frame.

	int smf_flags = smf->getFlags(data);

	const FSpriteModelFrame * smfNext = nullptr;
	float inter = 0.;

	ModelAnimFrameInterp decoupled_frame;
	ModelAnimFrame * decoupled_frame_prev = nullptr;

	// if prev_frame == -1: interpolate(main_frame, next_frame, inter), else: interpolate(interpolate(main_prev_frame, main_frame, inter_main), interpolate(next_prev_frame, next_frame, inter_next), inter)
	// 4-way interpolation is needed to interpolate animation switches between animations that aren't 35hz

	if(is_decoupled)
	{
		smfNext = smf = &BaseSpriteModelFrames[actor->GetClass()];
		if(data && !(data->curAnim.flags & MODELANIM_NONE))
		{
			calcFrames(data->curAnim, tic, decoupled_frame, inter);
			decoupled_frame_prev = &data->prevAnim;
		}
	}
	else if (gl_interpolate_model_frames && !(smf_flags & MDL_NOINTERPOLATION))
	{
		FState *nextState = curState->GetNextState();
		if (curState != nextState && nextState)
		{
			// [BB] To interpolate at more than 35 fps we take tic fractions into account.
			float ticFraction = 0.;
			// [BB] In case the tic counter is frozen we have to leave ticFraction at zero.
			if ((ConsoleState == c_up || ConsoleState == c_rising) && (menuactive == MENU_Off || menuactive == MENU_OnNoPause) && !Level->isFrozen())
			{
				ticFraction = I_GetTimeFrac();
			}
			inter = static_cast<double>(curState->Tics - curTics + ticFraction) / static_cast<double>(curState->Tics);

			// [BB] For some actors (e.g. ZPoisonShroom) spr->actor->tics can be bigger than curState->Tics.
			// In this case inter is negative and we need to set it to zero.
			if (curState->Tics < curTics)
				inter = 0.;
			else
			{
				// [BB] Workaround for actors that use the same frame twice in a row.
				// Most of the standard Doom monsters do this in their see state.
				if ((smf_flags & MDL_INTERPOLATEDOUBLEDFRAMES))
				{
					const FState *prevState = curState - 1;
					if ((curState->sprite == prevState->sprite) && (curState->Frame == prevState->Frame))
					{
						inter /= 2.;
						inter += 0.5;
					}
					if (nextState && ((curState->sprite == nextState->sprite) && (curState->Frame == nextState->Frame)))
					{
						inter /= 2.;
						nextState = nextState->GetNextState();
					}
				}
				if (nextState && inter != 0.0)
					smfNext = FindModelFrame(actor, nextState->sprite, nextState->Frame, false);
			}
		}
	}

	unsigned modelsamount = smf->modelsAmount;
	//[SM] - if we added any models for the frame to also render, then we also need to update modelsAmount for this smf
	if (data != nullptr)
	{
		if (data->models.Size() > modelsamount)
			modelsamount = data->models.Size();
	}

	return
	{
		smf_flags,
		smfNext,
		inter,
		is_decoupled,
		decoupled_frame,
		decoupled_frame_prev,
		modelsamount
	};
}

bool CalcModelOverrides(int i, const FSpriteModelFrame *smf, DActorModelData* data, const CalcModelFrameInfo &info, ModelDrawInfo &out, bool is_decoupled)
{
	//reset drawinfo
	out.modelid = -1;
	out.animationid = -1;
	out.modelframe = -1;
	out.modelframenext = -1;
	out.skinid.SetNull();
	out.surfaceskinids.Clear();

	if (data)
	{
		//modelID
		if (data->models.Size() > i && data->models[i].modelID >= 0)
		{
			out.modelid = data->models[i].modelID;
		}
		else if(data->models.Size() > i && data->models[i].modelID == -2)
		{
			return false;
		}
		else if(smf->modelsAmount > i)
		{
			out.modelid = smf->modelIDs[i];
		}

		//animationID
		if (data->animationIDs.Size() > i && data->animationIDs[i] >= 0)
		{
			out.animationid = data->animationIDs[i];
		}
		else if(smf->modelsAmount > i)
		{
			out.animationid = smf->animationIDs[i];
		}
		if(!is_decoupled)
		{
			//modelFrame
			if (data->modelFrameGenerators.Size() > i
				&& (unsigned)data->modelFrameGenerators[i] < info.modelsamount
				&& smf->modelframes[data->modelFrameGenerators[i]] >= 0
				) {
				out.modelframe = smf->modelframes[data->modelFrameGenerators[i]];

				if (info.smfNext) 
				{
					if(info.smfNext->modelframes[data->modelFrameGenerators[i]] >= 0)
					{
						out.modelframenext = info.smfNext->modelframes[data->modelFrameGenerators[i]];
					}
					else
					{
						out.modelframenext = info.smfNext->modelframes[i];
					}
				}
			}
			else if(smf->modelsAmount > i)
			{
				out.modelframe = smf->modelframes[i];
				if (info.smfNext) out.modelframenext = info.smfNext->modelframes[i];
			}
		}

		//skinID
		if (data->skinIDs.Size() > i && data->skinIDs[i].isValid())
		{
			out.skinid = data->skinIDs[i];
		}
		else if(smf->modelsAmount > i)
		{
			out.skinid = smf->skinIDs[i];
		}

		//surfaceSkinIDs
		if(data->models.Size() > i && data->models[i].surfaceSkinIDs.Size() > 0)
		{
			unsigned sz1 = smf->surfaceskinIDs.Size();
			unsigned sz2 = data->models[i].surfaceSkinIDs.Size();
			unsigned start = i * MD3_MAX_SURFACES;

			out.surfaceskinids = data->models[i].surfaceSkinIDs;
			out.surfaceskinids.Resize(MD3_MAX_SURFACES);

			for (unsigned surface = 0; surface < MD3_MAX_SURFACES; surface++)
			{
				if (sz2 > surface && (data->models[i].surfaceSkinIDs[surface].isValid()))
				{
					continue;
				}
				if((surface + start) < sz1)
				{
					out.surfaceskinids[surface] = smf->surfaceskinIDs[surface + start];
				}
				else
				{
					out.surfaceskinids[surface].SetNull();
				}
			}
		}
	}
	else
	{
		out.modelid = smf->modelIDs[i];
		out.animationid = smf->animationIDs[i];
		out.modelframe = smf->modelframes[i];
		if (info.smfNext) out.modelframenext = info.smfNext->modelframes[i];
		out.skinid = smf->skinIDs[i];
	}

	return (out.modelid >= 0 && out.modelid < Models.size());
}


const TArray<VSMatrix> * ProcessModelFrame(FModel * animation, bool nextFrame, int i, const FSpriteModelFrame *smf, DActorModelData* modelData, const CalcModelFrameInfo &frameinfo, ModelDrawInfo &drawinfo, bool is_decoupled, double tic)
{
	const TArray<TRS>* animationData = nullptr;

	if (modelData && modelData->useProceduralPose && modelData->proceduralPose.Size() > 0)
	{
		// ZScript-supplied per-bone pose (e.g. the physics whip) overrides any baked animation.
		// CalculateBonesIQM already branches on (animationData ? *animationData : TRSData).
		animationData = &modelData->proceduralPose;
		{ static int s_vrRenderDbg = 0; if (s_vrRenderDbg < 20) { s_vrRenderDbg++; Printf("[VRIK_RENDER] useProc=1 poseSize=%d is_decoupled=%d modelframe=%d\n", (int)modelData->proceduralPose.Size(), (int)is_decoupled, drawinfo.modelframe); } }
	}
	else if (drawinfo.animationid >= 0)
	{
		animation = Models[drawinfo.animationid];
		animationData = animation->AttachAnimationData();
	}

	const TArray<VSMatrix> *boneData = nullptr;

	if(is_decoupled)
	{
		if(frameinfo.decoupled_frame.frame1 >= 0)
		{
			boneData = animation->CalculateBones(
				frameinfo.decoupled_frame_prev ? *frameinfo.decoupled_frame_prev : nullptr,
				frameinfo.decoupled_frame,
				frameinfo.inter,
				animationData);
		}
	}
	else
	{
		boneData = animation->CalculateBones(
			nullptr,
			{
				nextFrame ? frameinfo.inter : -1.0f,
				drawinfo.modelframe,
				drawinfo.modelframenext
			},
			-1.0f,
			animationData);
	}

	if (animationData != nullptr) { static int s_vrRenderDbg2 = 0; if (s_vrRenderDbg2 < 20) { s_vrRenderDbg2++; Printf("[VRIK_RENDER2] boneData=%p size=%d\n", boneData, boneData ? (int)boneData->Size() : -1); } }

	return boneData;
}

static inline void RenderModelFrame(FModelRenderer *renderer, int i, const FSpriteModelFrame *smf, DActorModelData* modelData, const CalcModelFrameInfo &frameinfo, ModelDrawInfo &drawinfo, bool is_decoupled, double tic, FTranslationID translation, int &boneStartingPosition, bool &evaluatedSingle)
{
	FModel * mdl = Models[drawinfo.modelid];
	auto tex = drawinfo.skinid.isValid() ? TexMan.GetGameTexture(drawinfo.skinid, true) : nullptr;
	mdl->BuildVertexBuffer(renderer);

	auto ssidp = drawinfo.surfaceskinids.Size() > 0
		? drawinfo.surfaceskinids.Data()
		: (((i * MD3_MAX_SURFACES) < smf->surfaceskinIDs.Size()) ? &smf->surfaceskinIDs[i * MD3_MAX_SURFACES] : nullptr);

	bool nextFrame = frameinfo.smfNext && drawinfo.modelframe != drawinfo.modelframenext;

	// [Jay] while per-model animations aren't done, DECOUPLEDANIMATIONS does the same as MODELSAREATTACHMENTS
	if(!evaluatedSingle)
	{  // [Jay] TODO per-model decoupled animations
		const TArray<VSMatrix> *boneData = ProcessModelFrame(mdl, nextFrame, i, smf, modelData, frameinfo, drawinfo, is_decoupled, tic);

		if(frameinfo.smf_flags & MDL_MODELSAREATTACHMENTS || is_decoupled)
		{
			if(!boneData)
			{
				boneData = mdl->GetBasePose();
			}

			boneStartingPosition = boneData ? screen->mBones->UploadBones(*boneData) : -1;
			evaluatedSingle = true;
		}
	}

	mdl->RenderFrame(renderer, tex, drawinfo.modelframe, nextFrame ? drawinfo.modelframenext : drawinfo.modelframe, nextFrame ? frameinfo.inter : -1.f, translation, ssidp, boneStartingPosition);
}

void RenderFrameModels(FModelRenderer *renderer, FLevelLocals *Level, const FSpriteModelFrame *smf, const FState *curState, const int curTics, FTranslationID translation, AActor* actor)
{
	double tic = actor->Level->totaltime;
	if ((ConsoleState == c_up || ConsoleState == c_rising) && (menuactive == MENU_Off || menuactive == MENU_OnNoPause) && !actor->isFrozen())
	{
		tic += I_GetTimeFrac();
	}

	bool is_decoupled = (actor->flags9 & MF9_DECOUPLEDANIMATIONS);

	DActorModelData* modelData = actor ? actor->modelData.ForceGet() : nullptr;

	CalcModelFrameInfo frameinfo = CalcModelFrame(Level, smf, curState, curTics, modelData, actor, is_decoupled, tic);
	ModelDrawInfo drawinfo;

	int boneStartingPosition = -1;
	bool evaluatedSingle = false;

	for (unsigned i = 0; i < frameinfo.modelsamount; i++)
	{
		if (CalcModelOverrides(i, smf, modelData, frameinfo, drawinfo, is_decoupled))
		{
			RenderModelFrame(renderer, i, smf, modelData, frameinfo, drawinfo, is_decoupled, tic, translation, boneStartingPosition, evaluatedSingle);
		}
	}
}


static TArray<int> SpriteModelHash;
//TArray<FStateModelFrame> StateModelFrames;

//===========================================================================
//
// InitModels
//
//===========================================================================

void ParseModelDefLump(int Lump);

void InitModels()
{
	Models.DeleteAndClear();
	SpriteModelFrames.Clear();
	SpriteModelHash.Clear();

	// First, create models for each voxel
	for (unsigned i = 0; i < Voxels.Size(); i++)
	{
		FVoxelModel *md = new FVoxelModel(Voxels[i], false);
		Voxels[i]->VoxelIndex = Models.Push(md);
	}
	// now create GL model frames for the voxeldefs
	for (unsigned i = 0; i < VoxelDefs.Size(); i++)
	{
		FVoxelModel *md = (FVoxelModel*)Models[VoxelDefs[i]->Voxel->VoxelIndex];
		FSpriteModelFrame smf;
		memset(&smf, 0, sizeof(smf));
		smf.isVoxel = true;
		smf.modelsAmount = 1;
		smf.modelframes.Alloc(1);
		smf.modelframes[0] = -1;
		smf.modelIDs.Alloc(1);
		smf.modelIDs[0] = VoxelDefs[i]->Voxel->VoxelIndex;
		smf.skinIDs.Alloc(1);
		smf.skinIDs[0] = md->GetPaletteTexture();
		smf.animationIDs.Alloc(1);
		smf.animationIDs[0] = -1;
		smf.xscale = smf.yscale = smf.zscale = VoxelDefs[i]->Scale;
		smf.angleoffset = VoxelDefs[i]->AngleOffset.Degrees();
		smf.xoffset = VoxelDefs[i]->xoffset;
		smf.yoffset = VoxelDefs[i]->yoffset;
		smf.zoffset = VoxelDefs[i]->zoffset;
		// this helps catching uninitialized data.
		assert(VoxelDefs[i]->PitchFromMomentum == true || VoxelDefs[i]->PitchFromMomentum == false);
		if (VoxelDefs[i]->PitchFromMomentum) smf.flags |= MDL_PITCHFROMMOMENTUM;
		if (VoxelDefs[i]->UseActorPitch) smf.flags |= MDL_USEACTORPITCH;
		if (VoxelDefs[i]->UseActorRoll) smf.flags |= MDL_USEACTORROLL;
		if (VoxelDefs[i]->PlacedSpin != 0)
		{
			smf.yrotate = 1.f;
			smf.rotationSpeed = VoxelDefs[i]->PlacedSpin / 55.55f;
			smf.flags |= MDL_ROTATING;
		}
		VoxelDefs[i]->VoxeldefIndex = SpriteModelFrames.Push(smf);
		if (VoxelDefs[i]->PlacedSpin != VoxelDefs[i]->DroppedSpin)
		{
			if (VoxelDefs[i]->DroppedSpin != 0)
			{
				smf.yrotate = 1.f;
				smf.rotationSpeed = VoxelDefs[i]->DroppedSpin / 55.55f;
				smf.flags |= MDL_ROTATING;
			}
			else
			{
				smf.yrotate = 0;
				smf.rotationSpeed = 0;
				smf.flags &= ~MDL_ROTATING;
			}
			SpriteModelFrames.Push(smf);
		}
	}

	int Lump;
	int lastLump = 0;
	while ((Lump = fileSystem.FindLump("MODELDEF", &lastLump)) != -1)
	{
		ParseModelDefLump(Lump);
	}

	// create a hash table for quick access
	SpriteModelHash.Resize(SpriteModelFrames.Size ());
	memset(SpriteModelHash.Data(), 0xff, SpriteModelFrames.Size () * sizeof(int));

	for (unsigned int i = 0; i < SpriteModelFrames.Size (); i++)
	{
		int j = ModelFrameHash(&SpriteModelFrames[i]) % SpriteModelFrames.Size ();

		SpriteModelFrames[i].hashnext = SpriteModelHash[j];
		SpriteModelHash[j]=i;
	}
}

void ParseModelDefLump(int Lump)
{
	FScanner sc(Lump);
	while (sc.GetString())
	{
		if (sc.Compare("model"))
		{
			int index, surface;
			FString path = "";
			sc.MustGetString();

			FSpriteModelFrame smf;
			memset(&smf, 0, sizeof(smf));
			smf.xscale=smf.yscale=smf.zscale=1.f;

			auto type = PClass::FindClass(sc.String);
			if (!type || type->Defaults == nullptr)
			{
				sc.ScriptError("MODELDEF: Unknown actor type '%s'\n", sc.String);
			}
			smf.type = type;
			FScanner::SavedPos scPos = sc.SavePos();
			sc.MustGetStringName("{");
			while (!sc.CheckString("}"))
			{
				sc.MustGetString();
				if (sc.Compare("model"))
				{
					sc.MustGetNumber();
					index = sc.Number;
					if (index < 0)
					{
						sc.ScriptError("Model index must be 0 or greater in %s", type->TypeName.GetChars());
					}
					smf.modelsAmount = index + 1;
				}
			}
			//Make sure modelsAmount is at least equal to MIN_MODELS(4) to ensure compatibility with old mods
			if (smf.modelsAmount < MIN_MODELS)
			{
				smf.modelsAmount = MIN_MODELS;
			}

			const auto initArray = [](auto& array, const unsigned count, const auto value)
			{
				array.Alloc(count);
				std::fill(array.begin(), array.end(), value);
			};

			initArray(smf.modelIDs, smf.modelsAmount, -1);
			initArray(smf.skinIDs, smf.modelsAmount, FNullTextureID());
			initArray(smf.surfaceskinIDs, smf.modelsAmount * MD3_MAX_SURFACES, FNullTextureID());
			initArray(smf.animationIDs, smf.modelsAmount, -1);
			initArray(smf.modelframes, smf.modelsAmount, 0);

			sc.RestorePos(scPos);
			sc.MustGetStringName("{");
			while (!sc.CheckString("}"))
			{
				sc.MustGetString();
				if (sc.Compare("path"))
				{
					sc.MustGetString();
					FixPathSeperator(sc.String);
					path = sc.String;
					if (path[(int)path.Len()-1]!='/') path+='/';
				}
				else if (sc.Compare("model"))
				{
					sc.MustGetNumber();
					index = sc.Number;
					if (index < 0)
					{
						sc.ScriptError("Model index must be 0 or greater in %s", type->TypeName.GetChars());
					}
					else if (index >= smf.modelsAmount)
					{
						sc.ScriptError("Too many models in %s", type->TypeName.GetChars());
					}
					sc.MustGetString();
					FixPathSeperator(sc.String);
					smf.modelIDs[index] = FindModel(path.GetChars(), sc.String);
					if (smf.modelIDs[index] == -1)
					{
						Printf("%s: model not found in %s\n", sc.String, path.GetChars());
					}
				}
				else if (sc.Compare("animation"))
				{
					sc.MustGetNumber();
					index = sc.Number;
					if (index < 0)
					{
						sc.ScriptError("Animation index must be 0 or greater in %s", type->TypeName.GetChars());
					}
					else if (index >= smf.modelsAmount)
					{
						sc.ScriptError("Too many models in %s", type->TypeName.GetChars());
					}
					sc.MustGetString();
					FixPathSeperator(sc.String);
					smf.animationIDs[index] = FindModel(path.GetChars(), sc.String);
					if (smf.animationIDs[index] == -1)
					{
						Printf("%s: animation model not found in %s\n", sc.String, path.GetChars());
					}
				}
				else if (sc.Compare("scale"))
				{
					sc.MustGetFloat();
					smf.xscale = sc.Float;
					sc.MustGetFloat();
					smf.yscale = sc.Float;
					sc.MustGetFloat();
					smf.zscale = sc.Float;
				}
				// [BB] Added zoffset reading.
				// Now it must be considered deprecated.
				else if (sc.Compare("zoffset"))
				{
					sc.MustGetFloat();
					smf.zoffset=sc.Float;
				}
				// Offset reading.
				else if (sc.Compare("offset"))
				{
					sc.MustGetFloat();
					smf.xoffset = sc.Float;
					sc.MustGetFloat();
					smf.yoffset = sc.Float;
					sc.MustGetFloat();
					smf.zoffset = sc.Float;
				}
				// angleoffset, pitchoffset and rolloffset reading.
				else if (sc.Compare("angleoffset"))
				{
					sc.MustGetFloat();
					smf.angleoffset = sc.Float;
				}
				else if (sc.Compare("pitchoffset"))
				{
					sc.MustGetFloat();
					smf.pitchoffset = sc.Float;
				}
				else if (sc.Compare("rolloffset"))
				{
					sc.MustGetFloat();
					smf.rolloffset = sc.Float;
				}
				// [BB] Added model flags reading.
				else if (sc.Compare("ignoretranslation"))
				{
					smf.flags |= MDL_IGNORETRANSLATION;
				}
				else if (sc.Compare("pitchfrommomentum"))
				{
					smf.flags |= MDL_PITCHFROMMOMENTUM;
				}
				else if (sc.Compare("inheritactorpitch"))
				{
					smf.flags |= MDL_USEACTORPITCH | MDL_BADROTATION;
				}
				else if (sc.Compare("inheritactorroll"))
				{
					smf.flags |= MDL_USEACTORROLL;
				}
				else if (sc.Compare("useactorpitch"))
				{
					smf.flags |= MDL_USEACTORPITCH;
				}
				else if (sc.Compare("useactorroll"))
				{
					smf.flags |= MDL_USEACTORROLL;
				}
				else if (sc.Compare("noperpixellighting"))
				{
					smf.flags |= MDL_NOPERPIXELLIGHTING;
				}
				else if (sc.Compare("scaleweaponfov"))
				{
					smf.flags |= MDL_SCALEWEAPONFOV;
				}
				else if (sc.Compare("modelsareattachments"))
				{
					smf.flags |= MDL_MODELSAREATTACHMENTS;
				}
				else if (sc.Compare("rotating"))
				{
					smf.flags |= MDL_ROTATING;
					smf.xrotate = 0.;
					smf.yrotate = 1.;
					smf.zrotate = 0.;
					smf.rotationCenterX = 0.;
					smf.rotationCenterY = 0.;
					smf.rotationCenterZ = 0.;
					smf.rotationSpeed = 1.;
				}
				else if (sc.Compare("rotation-speed"))
				{
					sc.MustGetFloat();
					smf.rotationSpeed = sc.Float;
				}
				else if (sc.Compare("rotation-vector"))
				{
					sc.MustGetFloat();
					smf.xrotate = sc.Float;
					sc.MustGetFloat();
					smf.yrotate = sc.Float;
					sc.MustGetFloat();
					smf.zrotate = sc.Float;
				}
				else if (sc.Compare("rotation-center"))
				{
					sc.MustGetFloat();
					smf.rotationCenterX = sc.Float;
					sc.MustGetFloat();
					smf.rotationCenterY = sc.Float;
					sc.MustGetFloat();
					smf.rotationCenterZ = sc.Float;
				}
				else if (sc.Compare("interpolatedoubledframes"))
				{
					smf.flags |= MDL_INTERPOLATEDOUBLEDFRAMES;
				}
				else if (sc.Compare("nointerpolation"))
				{
					smf.flags |= MDL_NOINTERPOLATION;
				}
				else if (sc.Compare("skin"))
				{
					sc.MustGetNumber();
					index=sc.Number;
					if (index<0 || index>= smf.modelsAmount)
					{
						sc.ScriptError("Too many models in %s", type->TypeName.GetChars());
					}
					sc.MustGetString();
					FixPathSeperator(sc.String);
					if (sc.Compare(""))
					{
						smf.skinIDs[index]=FNullTextureID();
					}
					else
					{
						smf.skinIDs[index] = LoadSkin(path.GetChars(), sc.String);
						if (!smf.skinIDs[index].isValid())
						{
							Printf("Skin '%s' not found in '%s'\n",
								sc.String, type->TypeName.GetChars());
						}
					}
				}
				else if (sc.Compare("surfaceskin"))
				{
					sc.MustGetNumber();
					index = sc.Number;
					sc.MustGetNumber();
					surface = sc.Number;

					if (index<0 || index >= smf.modelsAmount)
					{
						sc.ScriptError("Too many models in %s", type->TypeName.GetChars());
					}

					if (surface<0 || surface >= MD3_MAX_SURFACES)
					{
						sc.ScriptError("Invalid MD3 Surface %d in %s", MD3_MAX_SURFACES, type->TypeName.GetChars());
					}

					sc.MustGetString();
					FixPathSeperator(sc.String);
					int ssIndex = surface + index * MD3_MAX_SURFACES;
					if (sc.Compare(""))
					{
						smf.surfaceskinIDs[ssIndex] = FNullTextureID();
					}
					else
					{
						smf.surfaceskinIDs[ssIndex] = LoadSkin(path.GetChars(), sc.String);
						if (!smf.surfaceskinIDs[ssIndex].isValid())
						{
							Printf("Surface Skin '%s' not found in '%s'\n",
								sc.String, type->TypeName.GetChars());
						}
					}
				}
				else if (sc.Compare("baseframe"))
				{
					FSpriteModelFrame *smfp = &BaseSpriteModelFrames.Insert(type, smf);
					for(int modelID : smf.modelIDs)
					{
						if(modelID >= 0)
							Models[modelID]->baseFrame = smfp;
					}
					GetDefaultByType(type)->hasmodel = true;
				}
				else if (sc.Compare("frameindex") || sc.Compare("frame"))
				{
					bool isframe=!!sc.Compare("frame");

					sc.MustGetString();
					smf.sprite = -1;
					for (int i = 0; i < (int)sprites.Size (); ++i)
					{
						if (strnicmp (sprites[i].name, sc.String, 4) == 0)
						{
							if (sprites[i].numframes==0)
							{
								//sc.ScriptError("Sprite %s has no frames", sc.String);
							}
							smf.sprite = i;
							break;
						}
					}
					if (smf.sprite==-1)
					{
						sc.ScriptError("Unknown sprite %s in model definition for %s", sc.String, type->TypeName.GetChars());
					}

					sc.MustGetString();
					FString framechars = sc.String;

					sc.MustGetNumber();
					index=sc.Number;
					if (index<0 || index>= smf.modelsAmount)
					{
						sc.ScriptError("Too many models in %s", type->TypeName.GetChars());
					}
					if (isframe)
					{
						sc.MustGetString();
						if (smf.modelIDs[index] >= 0)
						{
							FModel *model = Models[smf.modelIDs[index]];
							if (smf.animationIDs[index] >= 0)
							{
								model = Models[smf.animationIDs[index]];
							}
							smf.modelframes[index] = model->FindFrame(sc.String);
							if (smf.modelframes[index]==-1) sc.ScriptError("Unknown frame '%s' in %s", sc.String, type->TypeName.GetChars());
						}
						else smf.modelframes[index] = -1;
					}
					else
					{
						sc.MustGetNumber();
						smf.modelframes[index] = sc.Number;
					}

					for(int i=0; framechars[i]>0; i++)
					{
						char map[29]={0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
						int c = toupper(framechars[i])-'A';

						if (c<0 || c>=29)
						{
							sc.ScriptError("Invalid frame character %c found", c+'A');
						}
						if (map[c]) continue;
						smf.frame=c;
						SpriteModelFrames.Push(smf);
						GetDefaultByType(type)->hasmodel = true;
						map[c]=1;
					}
				}
				else if (sc.Compare("dontcullbackfaces"))
				{
					smf.flags |= MDL_DONTCULLBACKFACES;
				}
				else if (sc.Compare("userotationcenter"))
				{
					smf.flags |= MDL_USEROTATIONCENTER;
					smf.rotationCenterX = 0.;
					smf.rotationCenterY = 0.;
					smf.rotationCenterZ = 0.;
				}
				else if (sc.Compare("correctpixelstretch"))
				{
					smf.flags |= MDL_CORRECTPIXELSTRETCH;
				}
				else if (sc.Compare("forcecullbackfaces"))
				{
					smf.flags |= MDL_FORCECULLBACKFACES;
				}
				else
				{
					sc.ScriptMessage("Unrecognized string \"%s\"", sc.String);
				}
			}
		}
		else if (sc.Compare("#include"))
		{
			sc.MustGetString();
			// This is not using sc.Open because it can print a more useful error message when done here
			int includelump = fileSystem.CheckNumForFullName(sc.String, true);
			if (includelump == -1)
			{
				if (strcmp(sc.String, "sentinel.modl") != 0) // Gene Tech mod has a broken #include statement
					sc.ScriptError("Lump '%s' not found", sc.String);
			}
			else
			{
				ParseModelDefLump(includelump);
			}
		}
	}
}

//===========================================================================
//
// FindModelFrame
//
//===========================================================================

FSpriteModelFrame * FindModelFrameRaw(const AActor * actorDefaults, const PClass * ti, int sprite, int frame, bool dropped, bool forceVoxel = false, bool cullVoxel = false)
{
	if(actorDefaults->hasmodel)
	{
		FSpriteModelFrame smf;

		memset(&smf, 0, sizeof(smf));
		smf.type = ti;
		smf.sprite = sprite;
		smf.frame = frame;

		int hash = SpriteModelHash[ModelFrameHash(&smf) % SpriteModelFrames.Size()];

		while (hash>=0)
		{
			FSpriteModelFrame * smff = &SpriteModelFrames[hash];
			if (smff->type == ti && smff->sprite == sprite && smff->frame == frame) return smff;
			hash = smff->hashnext;
		}
	}

	// Check for voxel replacements. cullVoxel wins over BOTH r_drawvoxels and forceVoxel -- it's
	// set by distance-based voxel culling (vr_voxel_cull_items/vr_voxel_cull_monsters), which must
	// revert to the flat sprite past its threshold even when voxels are globally on or this specific
	// actor was force-shown (e.g. a grab candidate that also happens to be far -- shouldn't happen in
	// practice since grab range is short, but this keeps the two systems from fighting either way).
	//
	// PlayerPawn is HARD-excluded from ever falling through to a voxel replacement, unconditionally.
	// We ship a native VR player IK/hardpoint IQM model for the player body; if a loaded pk3 (e.g. a
	// third-party voxel pack) happens to define PLAYA-PLAYW voxel entries, r_drawvoxels being on
	// would otherwise silently steal the player body render away from that model whenever a frame
	// isn't covered by hasmodel's SpriteModelFrames lookup above -- IsKindOf is cheap and this check
	// only runs once we've already missed the model-frame hash lookup, so it costs nothing on the
	// normal (model-hit) path. actorDefaults is safe to call IsKindOf on: it's a real AActor (the
	// class's default/template instance), and IsKindOf only walks the class hierarchy, not runtime
	// state -- exact same idiom used throughout this codebase (a_action.cpp, p_acs.cpp, p_mobj.cpp).
	if (!cullVoxel && !actorDefaults->IsKindOf(NAME_PlayerPawn) && (r_drawvoxels || forceVoxel))
	{
		spritedef_t *sprdef = &sprites[sprite];
		if (frame < sprdef->numframes)
		{
			spriteframe_t *sprframe = &SpriteFrames[sprdef->spriteframes + frame];
			if (sprframe->Voxel != nullptr)
			{
				int index = sprframe->Voxel->VoxeldefIndex;
				if (dropped && sprframe->Voxel->DroppedSpin != sprframe->Voxel->PlacedSpin) index++;
				return &SpriteModelFrames[index];
			}
		}
	}

	return nullptr;
}

FSpriteModelFrame * FindModelFrame(const PClass * ti, int sprite, int frame, bool dropped)
{
	auto def = GetDefaultByType(ti);

	if (def->hasmodel)
	{
		if(def->flags9 & MF9_DECOUPLEDANIMATIONS)
		{
			FSpriteModelFrame * smf = BaseSpriteModelFrames.CheckKey(ti);
			if(smf) return smf;
		}
	}

	return FindModelFrameRaw(def, ti, sprite, frame, dropped);
}

FSpriteModelFrame * FindModelFrame(const PClass * ti, bool is_decoupled, int sprite, int frame, bool dropped, bool forceVoxel, bool cullVoxel)
{
	if(!ti) return nullptr;

	if(is_decoupled)
	{
		return BaseSpriteModelFrames.CheckKey(ti);
	}
	else
	{
		return FindModelFrameRaw(GetDefaultByType(ti), ti, sprite, frame, dropped, forceVoxel, cullVoxel);
	}
}

FSpriteModelFrame * FindModelFrame(AActor * thing, int sprite, int frame, bool dropped, bool cullVoxel)
{
	if(!thing) return nullptr;

	return FindModelFrame((thing->modelData != nullptr && thing->modelData->modelDef != nullptr) ? thing->modelData->modelDef : thing->GetClass(), (thing->flags9 & MF9_DECOUPLEDANIMATIONS), sprite, frame, dropped, thing->bForceShowVoxel, cullVoxel);
}

//===========================================================================
//
// IsHUDModelForPlayerAvailable
//
//===========================================================================

bool IsHUDModelForPlayerAvailable (player_t * player)
{
	if (player == nullptr || player->psprites == nullptr)
		return false;

	// [MK] check that at least one psprite uses models
	for (DPSprite *psp = player->psprites; psp != nullptr && psp->GetID() < PSP_TARGETCENTER; psp = psp->GetNext())
	{
		if ( FindModelFrame(psp->Caller, psp->GetSprite(), psp->GetFrame(), false) != nullptr ) return true;
	}
	return false;
}


unsigned int FSpriteModelFrame::getFlags(class DActorModelData * defs) const
{
	return (defs && defs->flags & MODELDATA_OVERRIDE_FLAGS)? (flags | defs->overrideFlagsSet) & ~(defs->overrideFlagsClear) : flags;
}