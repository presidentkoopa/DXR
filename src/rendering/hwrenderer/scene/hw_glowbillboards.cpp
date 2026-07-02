//
//---------------------------------------------------------------------------
//
// [GITD-AIR] In-air glow panels.
//
// Draws the billboard glow spots (FGlowSpot with gflags&1) published into
// FLevelLocals::GlowSpots. Milestone 1: a flat, additive, camera-facing
// colored quad floating at a world position. No texture, no custom shader.
//
// Coordinate mapping (matches HWSprite::CalculateVertices / FFlatVertex):
//   game (x, y, z)  ->  render (x, z, y)
// i.e. the engine's "up" axis is the SECOND FFlatVertex slot. The glow spot
// stores its horizontal centre in center.X/center.Y (game x/y) and its world
// height in zoff (game z). So a vertex at game (gx, gy, gz) is emitted as
//   vp.Set(gx, gz, gy, u, v).
//
//---------------------------------------------------------------------------
//

#include "r_defs.h"
#include "r_utility.h"
#include "doomstat.h"
#include "g_levellocals.h"
#include "matrix.h"
#include "hw_drawinfo.h"
#include "flatvertices.h"
#include "hw_renderstate.h"
#include "hw_material.h"
#include "texturemanager.h"

//==========================================================================
//
// HWDrawInfo::DrawGlowBillboards
//
// Called once per eye, after the opaque scene geometry, before translucent.
//
//==========================================================================

void HWDrawInfo::DrawGlowBillboards(FRenderState &state)
{
	TArray<FGlowSpot> &spots = Level->GlowSpots;
	if (spots.Size() == 0) return;

	// [GITD-AIR] We need main.fp (the material/textured path) to actually RUN on the panel,
	// because the wgType==13 7-seg digit branch lives in that fragment shader and is keyed off
	// the interpolated vTexCoord. A textureless quad (EnableTexture(false)) skips the material
	// path entirely, so vTexCoord is never populated and the digit code never executes — which is
	// why the panel reads as a uniform solid colour. Bind a guaranteed-loaded engine texture and
	// force TM_STENCIL so main.fp's getTexel() case 1 overrides texel.rgb = (1,1,1): the texture
	// CONTENT is irrelevant, we only need a valid material so the shader runs and UVs interpolate.
	// glstuff/mirror.png is an internal MiscPatch loaded at startup (same handle hw_walls.cpp uses
	// for the mirror), so it is always present regardless of the current map's texture set.
	// [GITD-AIR] Bind the SDF FONT ATLAS (textures/neonfont.png, 16x16 ASCII grid). The panel shader
	// samples it directly via texture(tex, glyphUV) to draw REAL-FONT glyphs as neon tubes. TM_STENCIL
	// (below) only affects getTexel()'s base path; the direct sample reads the raw SDF regardless.
	// Fall back to the mirror stencil if the atlas isn't loaded so panels still draw.
	FTextureID fontID = TexMan.CheckForTexture("neonfont", ETextureType::Any);
	FGameTexture *stencilTex = fontID.isValid() ? TexMan.GetGameTexture(fontID, false) : nullptr;
	if (stencilTex == nullptr || !stencilTex->isValid())
		stencilTex = TexMan.mirrorTexture.isValid() ? TexMan.GetGameTexture(TexMan.mirrorTexture, false) : nullptr;
	if (stencilTex == nullptr || !stencilTex->isValid()) return;

	// Camera world position (game coords: X, Y horizontal, Z up).
	const DVector3 &camPos = Viewpoint.Pos;

	// We render straight into the persistent flat-vertex buffer like the
	// corona / portal paths do; make sure it is the bound source.
	state.SetVertexBuffer(screen->mVertexData);

	// Additive, untextured, depth-tested but no depth write so panels never
	// occlude each other or punch holes in the depth buffer.
	state.SetDepthMask(false);
	state.SetDepthFunc(DF_LEqual);
	state.AlphaFunc(Alpha_GEqual, 0.f);
	state.SetRenderStyle(STYLE_Add);
	// [GITD-AIR] Bind the stencil material (NOT EnableTexture(false)) so the FULL material shader
	// runs and vTexCoord reaches main.fp's wgType==13 digit branch. TM_STENCIL forces texel.rgb to
	// white in getTexel(), so the panel's visible colour still comes entirely from the object colour
	// + the additive wall-glow/digit output, exactly as the textureless path used to. CLAMP_XY_NOMIP
	// keeps the 0..1 UV from wrapping and avoids mip selection on this screen-facing quad.
	state.EnableTexture(true);
	state.SetMaterial(stencilTex, UF_Texture, 0, CLAMP_XY_NOMIP, NO_TRANSLATION, -1);
	state.EnableBrightmap(false);
	state.SetTextureMode(TM_STENCIL);
	state.SetLightIndex(-1);

	for (unsigned i = 0; i < spots.Size(); i++)
	{
		const FGlowSpot &s = spots[i];
		if (!(s.gflags & 1)) continue;   // billboards only
		if (s.radius <= 0.0) continue;

		// World centre in RENDER coords: render x = game x, render y(up) =
		// zoff, render z = game y.
		float cx = (float)s.center.X;
		float cy = (float)s.zoff;
		float cz = (float)s.center.Y;

		// [GITD-AIR] Two orientation modes, chosen by the stored wipeDir (dirX,dirY game x,y):
		//   wipeDir == 0    -> CAMERA-FACING billboard (yaw-only): width always squares to the
		//                      camera. Used by single readable panels (combo digit, etc).
		//   wipeDir != 0    -> FIXED orientation: the panel's outward normal IS wipeDir, so it
		//                      hangs at a chosen world angle regardless of the camera. This is the
		//                      keystone for unfolding multi-plane displays (triptych / fan / cube /
		//                      helix) - ZScript places each plane at its own fixed yaw.
		// In both modes "up" stays world-up, so the panel is vertical (no pitch/roll) and readable.
		float rx, rz;
		float dlen = sqrtf((float)(s.wipeDir.X * s.wipeDir.X + s.wipeDir.Y * s.wipeDir.Y));
		if (dlen > 1e-4f)
		{
			// FIXED: outward normal = normalized wipeDir. We feed the camera path's algebra by
			// setting forward = -normal (forward points INTO the panel, away from the lit face).
			float inv = 1.0f / dlen;
			float fx = -(float)s.wipeDir.X * inv;   // forward (into panel), horizontal
			float fz = -(float)s.wipeDir.Y * inv;
			rx = -fz;
			rz =  fx;
		}
		else
		{
			// CAMERA-FACING: forward = camera -> panel, projected onto the ground plane (render XZ).
			float dx = cx - (float)camPos.X;        // render x
			float dz = cz - (float)camPos.Y;        // render z (game y)
			float len = sqrtf(dx * dx + dz * dz);
			if (len > 1e-4f)
			{
				float inv = 1.0f / len;
				float fx = dx * inv;                // forward (camera->panel), horizontal
				float fz = dz * inv;
				rx = -fz;                           // right = forward rotated 90 deg about world-up
				rz =  fx;
			}
			else
			{
				// Camera sitting on top of the panel: pick an arbitrary axis.
				rx = 1.0f;
				rz = 0.0f;
			}
		}

		float h = (float)s.radius;   // half-size (a square: half-width == half-height)

		// right * h and up * h
		float rX = rx * h, rZ = rz * h;
		float uY = h;

		// [GITD-AIR] Face normal (render coords) = the horizontal forward vector from the
		// panel to the camera. It is horizontal (y == 0) so the fragment shader's
		// abs(vWorldNormal.y) < 0.5 "isWall" test is TRUE for the panel, routing it down the
		// wall path where the wgType==13 digit branch lives. NormalModelMatrix is identity for
		// these flat-buffer draws, so this is also the world normal.
		state.SetNormal(-rz, 0.0f, rx);

		// 4 corners for a TriangleStrip: (TL, TR, BL, BR)
		//   TL = c - right + up
		//   TR = c + right + up
		//   BL = c - right - up
		//   BR = c + right - up
		auto vert = screen->mVertexData->AllocVertices(4);
		auto vp = vert.first;
		unsigned int vertexindex = vert.second;

		vp[0].Set(cx - rX, cy + uY, cz - rZ, 0.0f, 0.0f); // top-left
		vp[1].Set(cx + rX, cy + uY, cz + rZ, 1.0f, 0.0f); // top-right
		vp[2].Set(cx - rX, cy - uY, cz - rZ, 0.0f, 1.0f); // bottom-left
		vp[3].Set(cx + rX, cy - uY, cz + rZ, 1.0f, 1.0f); // bottom-right

		// Flat colour. The textureless material path reads the OBJECT colour, so set
		// both object + vertex colour to be safe. SetColor drives light to full so the
		// additive quad is FULLBRIGHT (otherwise the map's dark ambient kills it).
		state.SetObjectColor(s.color);
		state.SetColorAlpha(s.color, 1.0f, 0);
		state.SetColor(1.0f, 1.0f, 1.0f, 1.0f);   // fullbright tint

		// [GITD-AIR] Drive the 7-seg digit through main.fp's wall-glow path. We bind a SINGLE
		// wgType==13 "panel" wall-glow spot scoped to JUST this quad (set here, restored after
		// the loop), so real scene walls/flats — drawn in earlier passes with their own state —
		// never see it. Packing mirrors hw_flats.cpp:385-387:
		//   wsp = (center.x, center.y(world), packedRGB, radius)
		//   wmk = (wgType, progress, spareZ, spareW)
		// The colour packs into wsp.z exactly as the floor path does. The NUMBER cannot ride the
		// colour slot for a coloured panel, so it goes into the spare wmk.z lane and the shader
		// reads the digit value from uWallGlowMask[0].z (see main.fp panel branch).
		{
			PalEntry pc = s.color;
			float packedRGB = pc.r * 65536.0f + pc.g * 256.0f + pc.b;
			// Radius in wsp.w only gates the shader's `wgDist < radius` early-out (wgDist is the
			// HORIZONTAL distance from the spot centre). The quad spans +/-h horizontally, so a
			// fragment at the left/right edge sits ~h away; pad the gate to 2*h so the WHOLE panel
			// face passes and the UV-space digit never clips at the edges. The digit layout itself
			// is UV-based and independent of this radius.
			FVector4 wsp((float)s.center.X, (float)s.center.Y, packedRGB, h * 2.0f);
			FVector4 wmk((float)s.wipeType, (float)s.wipeProgress, (float)s.counter, 0.0f);   // wgType=s.wipeType, progress=s.wipeProgress, counter in .z
			state.SetWallGlowSpots(1, &wsp, &wmk);
			state.EnableWallGlow(true);
		}

		state.Draw(DT_TriangleStrip, vertexindex, 4);
	}

	// [GITD-AIR] Drop the panel wall-glow spot so following passes are untouched.
	state.EnableWallGlow(false);

	// Restore state for the passes that follow. We forced TM_STENCIL above, so put the texture
	// mode back to TM_NORMAL or the next textured pass would draw white-keyed.
	state.EnableTexture(true);
	state.SetTextureMode(TM_NORMAL);
	state.SetRenderStyle(STYLE_Translucent);
	state.ResetColor();
	state.SetDepthMask(true);
}
