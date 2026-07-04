// ============================================================================
//  XR Gravity Path — off-hand POWER
//  Palm-out (OffhandRoll) -> sweep the off-hand across a floor/wall/ceiling (or
//  open air) to draw a walkway of discrete rectangular SDF TILES, ~player-width,
//  that connect edge-to-edge. Each tile is its own flat rectangle abutting the
//  next -- NOT a blended ribbon, not dots.
//  Get ON by entering a tile's CAPTURE BOX (a slab sitting on its walkable face,
//  sized to the tile footprint x capture-height) with your feet, from the face
//  side -- walk the path up from the floor, or jump/grapple/fall into it. Gravity
//  then LERPS smoothly to that tile's surface (native AActor.GravityDir +
//  GravityAnchor C++ core) and you REST on it. Fire your grapple / leave the box
//  -> gravity restores.
//  Everything tunable lives in xr_gp_* cvars (VR Options -> Gravity Path).
// ============================================================================

class XR_GravityPathNode : Actor
{
	Vector3 SurfaceNormal;   // outward-facing walk-face normal; -SurfaceNormal = local "down"
	Vector3 Tangent;         // unit direction along the walkway at this tile
	double  TileLength;      // CURRENT length along Tangent (animates while growing)
	double  TileWidth;       // width across (from cvar at spawn; fixed)

	// --- fire-and-extrude spawn animation ---
	bool    Growing;         // true until the plank has fully extruded and locked
	int     GrowTic;
	int     GrowDuration;    // ticks
	Vector3 AnchorPos;       // FIXED trailing edge -- the previous tile's leading edge
	double  FinalLen;        // target length once fully extruded
	int     LockFlashTic;    // brief brightness pop the tic it locks
	double  BaseAlpha;       // resting alpha (post-flash), set at spawn

	const XR_BASE_PX = 64.0; // assumed base pixel size backing "SIGL"; tune if tiles render wrong-sized

	Default
	{
		+NOGRAVITY +NOCLIP +NOBLOCKMAP +DONTSPLASH +NOTIMEFREEZE
		+FLATSPRITE +ROLLCENTER
		RenderStyle "Add";
	}
	States
	{
	Spawn:
		SIGL A -1 Bright;
		Stop;
	}

	// Kick off the fire-and-extrude animation: start as a small square anchored
	// at 'anchor' (the previous tile's edge -- stays fixed all the way through),
	// and grow forward along 'tangent' until TileLength reaches 'finalLen'.
	void XR_BeginGrow(Vector3 anchor, Vector3 normal, Vector3 tangent, double finalLen, double width, int growTicks)
	{
		AnchorPos = anchor;
		SurfaceNormal = normal;
		Tangent = tangent;
		FinalLen = finalLen;
		TileWidth = width;
		GrowDuration = max(growTicks, 1);
		GrowTic = 0;
		Growing = true;

		double seedLen = min(width, finalLen);
		TileLength = seedLen;
		SetOrigin(anchor + tangent * (seedLen * 0.5), true);
		XR_Orient();
	}

	override void Tick()
	{
		Super.Tick();
		// GrowDuration stays 0 unless XR_BeginGrow was ever called -- a beam (which
		// manages its own Alpha directly every tick from PaintTick) never calls it,
		// so this whole grow/flash system must stay hands-off for it.
		if (!Growing && LockFlashTic <= 0 && GrowDuration <= 0) return;

		// Lock-flash decays independently of Growing (it fires just AFTER growth ends).
		if (LockFlashTic > 0)
		{
			LockFlashTic--;
			Alpha = BaseAlpha * 1.6;
		}
		else if (!Growing)
		{
			Alpha = BaseAlpha;
		}

		if (!Growing) return;

		GrowTic++;
		double f = double(GrowTic) / double(GrowDuration);
		if (f > 1.0) f = 1.0;
		f = f * f * (3.0 - 2.0 * f);   // smoothstep ease

		double seedLen = min(TileWidth, FinalLen);
		TileLength = seedLen + (FinalLen - seedLen) * f;
		SetOrigin(AnchorPos + Tangent * (TileLength * 0.5), true);
		XR_Orient();

		if (GrowTic >= GrowDuration)
		{
			Growing = false;
			LockFlashTic = 4;   // brief brightness pop to sell "locked into place"
		}
	}

	// Yaw/pitch that tilt a FLATSPRITE quad (base pose = flat, facing world +Z,
	// like a floor decal) so its face-normal points along 'n'. NOT the usual
	// "look direction" yaw/pitch (where Pitch=0 is horizontal) -- here Pitch=0
	// means "no tilt" (still facing +Z) and Pitch=90 means "tilted to vertical",
	// because the yaw rotation (about the vertical axis) can never move a vector
	// that already IS vertical, so ALL of the tilt must come from Pitch alone.
	// Verified against 3 cases: floor n=(0,0,1)->pitch=0 (no tilt, already correct);
	// wall n=(1,0,0)->pitch=90 (full tilt to vertical); ceiling n=(0,0,-1)->pitch=180
	// (flip to face down). This is spherical coords (yaw=azimuth, pitch=polar angle
	// from the +Z pole), NOT the "look-direction" formula an earlier pass used here,
	// which gave pitch=0 for a WALL -- i.e. zero tilt for the single most common
	// case. Caught via adversarial self-review, not render-tested.
	static void XR_VectorToYawPitch(Vector3 n, out double yaw, out double pitch)
	{
		double horiz = sqrt(n.x * n.x + n.y * n.y);
		yaw = (horiz > 0.0001) ? VectorAngle(n.x, n.y) : 0.0;
		pitch = atan2(horiz, n.z);
	}

	// Orient tile so its flat-quad normal = SurfaceNormal, long axis = Tangent,
	// sized TileLength x TileWidth. Roll aligns Tangent via cross/dot against a
	// yaw-only "base right" reference -- re-derived by hand-tracing the render
	// matrix: the width axis IS the pitch-rotation's own axis, so pitch cannot
	// move it and yaw-only is structurally correct (not just an approximation).
	// The one thing that CANNOT be confirmed without rendering: the engine's
	// internal "270 - Yaw" offset may differ from this derivation's "yaw - 90" by
	// a fixed constant -- if every tile is consistently rotated by the same wrong
	// amount, that's a single constant to adjust here, not a redesign.
	void XR_Orient()
	{
		double yaw, pitch;
		XR_VectorToYawPitch(SurfaceNormal, yaw, pitch);
		Angle = yaw;
		Pitch = pitch;

		double ryaw = yaw - 90.0;
		Vector3 baseRight = (cos(ryaw), sin(ryaw), 0.0);

		Vector3 n = SurfaceNormal.Unit();
		double tdotn = Tangent.x * n.x + Tangent.y * n.y + Tangent.z * n.z;
		Vector3 tproj = (Tangent.x - n.x * tdotn, Tangent.y - n.y * tdotn, Tangent.z - n.z * tdotn);
		double tlen = tproj.Length();
		if (tlen > 0.0001)
		{
			tproj /= tlen;
			Vector3 c = (baseRight.y * tproj.z - baseRight.z * tproj.y,
						 baseRight.z * tproj.x - baseRight.x * tproj.z,
						 baseRight.x * tproj.y - baseRight.y * tproj.x);
			double crossDotN = c.x * n.x + c.y * n.y + c.z * n.z;
			double dotRT = baseRight.x * tproj.x + baseRight.y * tproj.y + baseRight.z * tproj.z;
			Roll = atan2(crossDotN, dotRT);
		}

		Scale = (TileLength / XR_BASE_PX, TileWidth / XR_BASE_PX);
	}
}

// A live paint-stream stretched from the hand to the current aim hit while
// casting -- reuses the tile's flat-quad orient math, just thinner and
// repositioned every tick instead of being placed permanently. Never pushed
// into XR_GravityPath.nodes (purely visual, no attach logic).
class XR_GravityBeam : XR_GravityPathNode
{
	Default
	{
		+NOINTERACTION
	}
}

// The wrist hardpoint: a small glowing orb that follows the off-hand every
// tick and pulses brighter while casting -- the visible "source" the planks
// and the beam shoot from.
class XR_GravityEmitter : Actor
{
	Default
	{
		+NOGRAVITY +NOCLIP +NOBLOCKMAP +DONTSPLASH +NOTIMEFREEZE +NOINTERACTION
		+FORCEXYBILLBOARD
		RenderStyle "Add";
		Scale 0.12;
	}
	States
	{
	Spawn:
		SIGL A -1 Bright;
		Stop;
	}
}

// A short-lived colored debug marker -- an ACTOR (billboard sprite) because
// particles are invisible in this VR build. RenderStyle Stencil draws the sprite
// as a solid flat silhouette in the shade color, so SetTint gives crisp colors.
// Lives 2 tics then self-destroys (Stop). Reuses the guaranteed BAL1 sprite.
class XR_GravityDebugMark : Actor
{
	Default
	{
		+NOGRAVITY +NOCLIP +NOBLOCKMAP +DONTSPLASH +FORCEXYBILLBOARD +CLIENTSIDEONLY
		RenderStyle "Stencil";
		Alpha 1.0;
		Scale 0.1;
	}
	States
	{
	Spawn:
		BAL1 A 2 Bright;
		Stop;
	}

	void SetTint(int t)
	{
		color c;
		switch (t)
		{
			case 0:  c = "00 ff ff"; break;   // cyan  (tile)
			case 1:  c = "00 ff 00"; break;   // green (attached / normal stub)
			case 2:  c = "ff 00 ff"; break;   // magenta (growing)
			case 3:  c = "ff ff 00"; break;   // yellow (aim ray)
			case 4:  c = "ff 88 00"; break;   // orange (hit point)
			default: c = "ff ff ff"; break;   // white (feet)
		}
		SetShade(c);
	}
}

class XR_GravityPath : Inventory
{
	Array<XR_GravityPathNode> nodes;
	XR_GravityEmitter emitter;
	XR_GravityBeam    beam;
	bool    casting;
	bool    wasAttached;
	Vector3 lastNodePos;
	Vector3 curGrav;         // the currently-applied (lerped) gravity direction
	XR_GravityPathNode attachedTile;   // last tile FindCaptureTile() resolved (read by Rail Guard)
	// Rail Guard direction results. Returned via FIELDS, not 'out Vector3' params: passing vector
	// out-params to XR_GetRailDirection from the JIT-compiled DoomPlayer.MovePlayer triggers a hard
	// "Unknown REGT value passed to EmitPARAM" JIT error. Field-write sidesteps that entirely.
	Vector3 railOutTangent;
	Vector3 railOutRight;

	Default
	{
		Inventory.Amount 1;
		Inventory.MaxAmount 1;
		+INVENTORY.UNDROPPABLE
		+INVENTORY.UNTOSSABLE
		Tag "XR Gravity Path";
	}

	// ---- cvar helpers (safe if a cvar is somehow missing) ----
	private double GetF(Name nm, double def)
	{
		let c = CVar.GetCVar(nm, owner ? owner.player : null);
		return c ? c.GetFloat() : def;
	}
	private int GetI(Name nm, int def)
	{
		let c = CVar.GetCVar(nm, owner ? owner.player : null);
		return c ? c.GetInt() : def;
	}
	private bool GetB(Name nm, bool def)
	{
		let c = CVar.GetCVar(nm, owner ? owner.player : null);
		return c ? c.GetBool() : def;
	}

	private bool IsPalmOut()
	{
		if (!owner || !owner.player) return false;
		double r = abs(owner.OffhandRoll);
		return (r > GetF("xr_gp_palm_lo", 45.0) && r < GetF("xr_gp_palm_hi", 135.0));
	}

	// Derive the surface normal at a trace hit (FLineTraceData has no HitNormal).
	private Vector3 DeriveNormal(FLineTraceData t, Vector3 aimDir)
	{
		if (t.Hit3DFloor &&
			(t.HitType == FLineTraceData.TRACE_HitFloor || t.HitType == FLineTraceData.TRACE_HitCeiling))
		{
			double tz = t.Hit3DFloor.top.ZatPoint(t.HitLocation.xy);
			double bz = t.Hit3DFloor.bottom.ZatPoint(t.HitLocation.xy);
			return (abs(t.HitLocation.z - tz) <= abs(t.HitLocation.z - bz))
				 ? t.Hit3DFloor.top.Normal : t.Hit3DFloor.bottom.Normal;
		}
		if (t.HitSector &&
			(t.HitType == FLineTraceData.TRACE_HitFloor || t.HitType == FLineTraceData.TRACE_HitCeiling))
		{
			return (t.SectorPlane == 0) ? t.HitSector.floorplane.Normal
										: t.HitSector.ceilingplane.Normal;
		}
		if (t.HitType == FLineTraceData.TRACE_HitWall && t.HitLine)
		{
			Vector2 d = t.HitLine.delta;
			double dl = d.Length(); if (dl < 0.0001) dl = 1.0;
			double n1x = -d.y / dl, n1y = d.x / dl;
			double dv = n1x * aimDir.x + n1y * aimDir.y;
			return (dv > 0.0) ? (-n1x, -n1y, 0.0) : (n1x, n1y, 0.0);
		}
		return (0.0, 0.0, 1.0);
	}

	// Find the tile whose CAPTURE BOX the player's feet are inside (face side only).
	// Box = tile footprint (length x width, +margin) x [ -floorSlop , capH ] along normal.
	private XR_GravityPathNode FindCaptureTile()
	{
		if (!owner) return null;
		double capH   = GetF("xr_gp_capture_h", 28.0);
		double margin = GetF("xr_gp_capture_margin", 8.0);
		bool   fallOK = GetB("xr_gp_fall_catch", true);

		Vector3 feet = owner.pos;   // actor origin = feet (bottom)
		XR_GravityPathNode best = null;
		double bestUp = 1e9;

		for (int i = 0; i < nodes.Size(); i++)
		{
			let n = nodes[i];
			if (!n || n.Growing) continue;   // not attachable until it's locked into place
			Vector3 nrm = n.SurfaceNormal;
			Vector3 tan = n.Tangent;
			Vector3 right = (nrm.y * tan.z - nrm.z * tan.y,
							 nrm.z * tan.x - nrm.x * tan.z,
							 nrm.x * tan.y - nrm.y * tan.x);
			Vector3 rel = feet - n.pos;
			double up = rel.x * nrm.x + rel.y * nrm.y + rel.z * nrm.z;   // along normal
			double al = rel.x * tan.x + rel.y * tan.y + rel.z * tan.z;   // along length
			double aw = rel.x * right.x + rel.y * right.y + rel.z * right.z; // along width

			if (up < -6.0 || up > capH) continue;                 // face side + height band
			if (abs(al) > n.TileLength * 0.5 + margin) continue;  // within length footprint
			if (abs(aw) > n.TileWidth  * 0.5 + margin) continue;  // within width footprint

			// Above the face: only grab if fall-catch is on OR you're moving into it.
			if (up > 6.0 && !fallOK)
			{
				double velUp = owner.Vel.x * nrm.x + owner.Vel.y * nrm.y + owner.Vel.z * nrm.z;
				if (velUp >= 0) continue;
			}
			if (up < bestUp) { bestUp = up; best = n; }
		}
		return best;
	}

	// Public: the smooth path-following direction at 'pos', blended between the
	// attached tile and its neighbor as pos nears that tile's edge, so a curving
	// strip of tiles gives a continuously-turning rail instead of a hard snap at
	// each tile boundary. Read by DoomPlayer.MovePlayer() for Rail Guard -- NOT
	// called from DoEffect's own render/attach pass (different timing domain,
	// see the design note on the MovePlayer override below).
	// Results returned via railOutTangent / railOutRight fields (see decl note) -- NOT out-params,
	// to avoid the vector-out-param JIT error when called from DoomPlayer.MovePlayer.
	bool XR_GetRailDirection(Vector3 pos)
	{
		let tile = attachedTile;
		if (!tile) return false;

		int idx = nodes.Find(tile);
		if (idx >= nodes.Size()) return false;   // shouldn't happen, but don't fault

		Vector3 tan = tile.Tangent;
		Vector3 nrm = tile.SurfaceNormal;
		Vector3 rel = pos - tile.pos;
		double al = rel.x * tan.x + rel.y * tan.y + rel.z * tan.z;   // signed distance along this tile's length
		double half = tile.TileLength * 0.5;
		if (half < 0.0001) half = 0.0001;
		double edgeFrac = al / half;   // -1 at trailing edge, 0 at center, +1 at leading edge

		XR_GravityPathNode neighbor = null;
		double blend = 0.0;
		double BLEND_ZONE = 0.5;   // start blending toward the neighbor in the outer half of the tile
		if (edgeFrac > (1.0 - BLEND_ZONE) && idx + 1 < nodes.Size())
		{
			neighbor = nodes[idx + 1];
			blend = clamp((edgeFrac - (1.0 - BLEND_ZONE)) / BLEND_ZONE, 0.0, 1.0);
		}
		else if (edgeFrac < -(1.0 - BLEND_ZONE) && idx - 1 >= 0)
		{
			neighbor = nodes[idx - 1];
			blend = clamp((-edgeFrac - (1.0 - BLEND_ZONE)) / BLEND_ZONE, 0.0, 1.0);
		}

		Vector3 blendedTan = tan;
		if (neighbor && !neighbor.Growing && blend > 0.0)
		{
			blendedTan = tan + (neighbor.Tangent - tan) * blend;
			double bl = blendedTan.Length();
			if (bl > 0.0001) blendedTan /= bl; else blendedTan = tan;
		}

		railOutTangent = blendedTan;
		railOutRight = (nrm.y * blendedTan.z - nrm.z * blendedTan.y,
					nrm.z * blendedTan.x - nrm.x * blendedTan.z,
					nrm.x * blendedTan.y - nrm.y * blendedTan.x);
		return true;
	}

	// Always-on wrist hardpoint: follows the hand every tick, brightens/pulses
	// while casting. This is the visible "source" everything shoots from.
	private void UpdateEmitter()
	{
		if (!owner) return;
		if (!emitter)
			emitter = XR_GravityEmitter(Actor.Spawn("XR_GravityEmitter", owner.OffhandPos));
		if (!emitter) return;

		emitter.SetOrigin(owner.OffhandPos, true);
		emitter.Angle = owner.OffhandAngle;
		emitter.Pitch = owner.OffhandPitch;

		int ci = GetI("xr_gp_color", 0x40c0ff);
		Vector3 col = (((ci >> 16) & 255), ((ci >> 8) & 255), (ci & 255)) / 255.0;
		emitter.msdf_enabled = 0;   // circle sigil (existing default primary==0 branch)
		emitter.msdf_color = col;

		if (casting)
		{
			emitter.msdf_glitch = 0.5;
			emitter.Alpha = 0.6 + 0.4 * sin(level.maptime * 12.0);
			emitter.Scale = (0.16, 0.16);
		}
		else
		{
			emitter.msdf_glitch = 0.1;
			emitter.Alpha = 0.25;
			emitter.Scale = (0.1, 0.1);
		}
	}

	// Hide the live paint-stream beam (kept alive, just invisible -- cheaper
	// than destroy/respawn every tick).
	private void HideBeam()
	{
		if (beam) beam.Alpha = 0.0;
	}

	private void PaintTick()
	{
		let pmo = owner;
		double castDist = GetF("xr_gp_cast_dist", 512.0);
		int    maxTiles = GetI("xr_gp_max_tiles", 128);
		double tileW    = GetF("xr_gp_tile_width", 40.0);
		double beamW    = GetF("xr_gp_beam_width", 10.0);
		double minSeg   = GetF("xr_gp_tile_length", 40.0);
		double alpha    = GetF("xr_gp_alpha", 0.9);
		int    ci       = GetI("xr_gp_color", 0x40c0ff);
		Vector3 col     = (((ci >> 16) & 255), ((ci >> 8) & 255), (ci & 255)) / 255.0;

		Vector3 handPos = pmo.OffhandPos;
		Vector3 aim = pmo.OffhandDir(self, 0, pmo.OffhandPitch);
		FLineTraceData t;
		bool hit = pmo.LineTrace(pmo.OffhandAngle, castDist, pmo.OffhandPitch,
								 TRF_ISOFFHAND | TRF_THRUACTORS, 0, 0, 0, t);
		if (!hit || t.HitType == FLineTraceData.TRACE_HitActor || t.HitType == FLineTraceData.TRACE_HitNone)
		{
			HideBeam();
			return;
		}

		// Live beam from hand to the current aim point -- the visible "shot".
		Vector3 beamSeg = t.HitLocation - handPos;
		double beamLen = beamSeg.Length();
		if (beamLen > 1.0)
		{
			if (!beam) beam = XR_GravityBeam(Actor.Spawn("XR_GravityBeam", handPos + beamSeg * 0.5));
			if (beam)
			{
				beam.SetOrigin(handPos + beamSeg * 0.5, true);
				beam.SurfaceNormal = DeriveNormal(t, aim);
				beam.Tangent = beamSeg / beamLen;
				beam.TileLength = beamLen;
				beam.TileWidth = beamW;
				beam.XR_Orient();
				beam.Alpha = 0.7 + 0.3 * sin(level.maptime * 16.0);
				beam.msdf_enabled = 512;
				beam.msdf_glitch = 0.25;
				beam.msdf_color = col;
			}
		}
		else HideBeam();

		if (nodes.Size() >= maxTiles) return;

		if (nodes.Size() == 0)
		{
			lastNodePos = t.HitLocation;
			return;
		}

		Vector3 seg = t.HitLocation - lastNodePos;
		double segLen = seg.Length();
		if (segLen <= minSeg) return;

		double growTime = GetF("xr_gp_grow_time", 0.15);
		int growTicks = int(max(growTime, 0.0) * 35.0 + 0.5);

		let n = XR_GravityPathNode(Actor.Spawn("XR_GravityPathNode", lastNodePos));
		if (n)
		{
			n.XR_BeginGrow(lastNodePos, DeriveNormal(t, aim), seg / segLen, segLen, tileW, growTicks);
			n.BaseAlpha = alpha;
			n.Alpha = alpha;
			n.msdf_enabled = 512;      // shader bit 9 = flat rectangular TILE mode
			n.msdf_glitch = 0.12;      // tile inset (seam width between abutting tiles)
			n.msdf_color = col;
			nodes.Push(n);
		}
		lastNodePos = t.HitLocation;
	}

	// Public exit hook (e.g. grapple-fire can call this for an instant detach).
	void ExitRoad()
	{
		if (owner) owner.GravityDir = (0.0, 0.0, 0.0);
		wasAttached = false;
		curGrav = (0.0, 0.0, -1.0);
	}

	override void OnDestroy()
	{
		if (emitter) { emitter.Destroy(); emitter = null; }
		if (beam) { beam.Destroy(); beam = null; }
		ClearPath();
		Super.OnDestroy();
	}

	void ClearPath()
	{
		for (int i = 0; i < nodes.Size(); i++) if (nodes[i]) nodes[i].Destroy();
		nodes.Clear();
		lastNodePos = (0.0, 0.0, 0.0);
	}

	// ---- debug overlay ----
	// Drawn with ACTOR sprites, NOT particles: p_user.cpp's grab-debug uses
	// P_SpawnParticle and is invisible in this VR build (particles don't reach the
	// stereo render). Billboard sprite actors render in VR like every fireball, so
	// the overlay uses short-lived XR_GravityDebugMark actors instead.
	// 'tint' colorizes via translation: 0=cyan 1=green 2=magenta 3=yellow 4=orange 5=white
	private void DbgPoint(Vector3 p, int tint, double sz)
	{
		let m = XR_GravityDebugMark(Actor.Spawn("XR_GravityDebugMark", p));
		if (m) { m.Scale = (sz, sz); m.SetTint(tint); }
	}
	private void DbgLine(Vector3 a, Vector3 b, int tint, int segs, double sz = 0.09)
	{
		for (int i = 0; i <= segs; i++)
			DbgPoint(a + (b - a) * (double(i) / double(segs)), tint, sz);
	}
	private void DrawDebug()
	{
		if (!owner) return;
		if (level.maptime & 1) return;   // throttle: every other tic keeps the actor count sane
		double capH = GetF("xr_gp_capture_h", 28.0);
		double castDist = GetF("xr_gp_cast_dist", 512.0);

		// Aim ray + hit + feet
		Vector3 handPos = owner.OffhandPos;
		FLineTraceData t;
		if (owner.LineTrace(owner.OffhandAngle, castDist, owner.OffhandPitch, TRF_ISOFFHAND | TRF_THRUACTORS, 0, 0, 0, t))
		{
			DbgLine(handPos, t.HitLocation, 3, 6, 0.08);   // 3=yellow aim
			DbgPoint(t.HitLocation, 4, 0.22);              // 4=orange hit
		}
		DbgPoint(owner.pos, 5, 0.2);                       // 5=white feet

		// Tiles: 4 face corners + capture-height normal stub; highlight attached
		let attached = FindCaptureTile();
		int drawn = 0;
		for (int i = 0; i < nodes.Size() && drawn < 12; i++)
		{
			let n = nodes[i];
			if (!n) continue;
			if ((n.pos - owner.pos).Length() > 512.0) continue;   // nearby only
			drawn++;
			Vector3 nrm = n.SurfaceNormal, tan = n.Tangent;
			Vector3 right = (nrm.y * tan.z - nrm.z * tan.y,
							 nrm.z * tan.x - nrm.x * tan.z,
							 nrm.x * tan.y - nrm.y * tan.x);
			double hl = n.TileLength * 0.5, hw = n.TileWidth * 0.5;
			Vector3 c = n.pos;
			int tint = (n == attached) ? 1 : (n.Growing ? 2 : 0);   // green / magenta / cyan
			double csz = (n == attached) ? 0.2 : 0.12;
			DbgPoint(c + tan * hl + right * hw, tint, csz);
			DbgPoint(c + tan * hl - right * hw, tint, csz);
			DbgPoint(c - tan * hl - right * hw, tint, csz);
			DbgPoint(c - tan * hl + right * hw, tint, csz);
			DbgLine(c, c + nrm * capH, 1, 3, 0.1);   // green normal stub = capture height
		}
	}

	override void DoEffect()
	{
		Super.DoEffect();
		if (!owner || !owner.player) return;

		UpdateEmitter();   // wrist hardpoint is always live, casting or not

		if (IsPalmOut()) { casting = true; PaintTick(); }
		else             { casting = false; HideBeam(); }

		// ATTACH: is the player standing in a tile's capture box?
		let tile = FindCaptureTile();
		attachedTile = tile;   // read by DoomPlayer.MovePlayer() for Rail Guard
		if (tile)
		{
			Vector3 target = -tile.SurfaceNormal;
			if (!wasAttached) curGrav = (0.0, 0.0, -1.0);   // fresh mount: start lerp from normal down

			double lerpT = GetF("xr_gp_lerp_time", 0.2);
			double step = (lerpT > 0.001) ? (1.0 / 35.0) / lerpT : 1.0;
			if (step > 1.0) step = 1.0;

			curGrav = curGrav + (target - curGrav) * step;    // nlerp toward target (mount + tile-to-tile)
			double cl = curGrav.Length();
			if (cl > 0.0001) curGrav /= cl; else curGrav = target;

			// Floor-facing gravity (within ~10 deg of straight down) IS normal gravity:
			// hand it back to the native path (GravityDir zero) so ordinary floor-tile
			// walking doesn't force the per-tic Z-movement the C++ gate now runs for
			// non-zero GravityDir. Walls/ceilings/tilts keep the directional override.
			if (curGrav.z < -0.985)
				owner.GravityDir = (0.0, 0.0, 0.0);
			else
				owner.GravityDir = curGrav;
			owner.GravityAnchor = tile.pos;
			wasAttached = true;
		}
		else if (wasAttached)
		{
			ExitRoad();   // left every capture box -> restore normal gravity
		}

		if (GetB("xr_gp_debug", false)) DrawDebug();
	}
}

// Auto-give the power to every player pawn on spawn (registered in common.txt).
class XR_GravityPathGiver : EventHandler
{
	override void WorldThingSpawned(WorldEvent e)
	{
		let mo = e.thing;
		if (mo && mo.player && mo.player.mo == mo && !mo.FindInventory("XR_GravityPath"))
			mo.GiveInventory("XR_GravityPath", 1);
	}
}

// ============================================================================
// Rail Guard. WHY THIS ISN'T IN XR_GravityPath.DoEffect: statnums.h orders
// STAT_PLAYER (the pawn's own movement/position-integration) strictly BEFORE
// STAT_INVENTORY (where an Inventory item's DoEffect runs) -- confirmed by
// reading statnums.h, not assumed. GravityDir survives being set "late" because
// nothing else ever writes it, so a one-tick-late DoEffect write is harmless.
// Vel does NOT have that luxury: native MovePlayer() recomputes it from the
// controller every tick, BEFORE DoEffect would run, so a DoEffect-based
// override would always land one tick behind and get fought by the next
// native recompute -- a permanent, jittery losing race, not a clean redirect.
// Fix: hook the SAME synchronous call native movement already uses. MovePlayer
// is `virtual` (player.zs) specifically for this kind of override. Super runs
// first (all native speed/friction/momentum/crouch logic happens exactly as
// before); this only re-projects the RESULT onto the path's own tangent/right
// basis instead of the view-facing basis -- so Rail Guard changes direction,
// never speed or feel.
// ============================================================================
extend class DoomPlayer
{
	override void MovePlayer()
	{
		Super.MovePlayer();

		if (!player || reactiontime) return;
		let path = XR_GravityPath(FindInventory("XR_GravityPath"));
		if (!path) return;
		let cv = CVar.GetCVar("xr_gp_railguard", player);
		if (!cv || !cv.GetBool()) return;

		// Results come back on the path's railOutTangent/railOutRight fields (see XR_GetRailDirection
		// note) -- no vector out-params, which would JIT-fault this MovePlayer override.
		if (!path.XR_GetRailDirection(pos)) return;
		Vector3 railTan = path.railOutTangent;
		Vector3 railRight = path.railOutRight;

		Vector2 fwdDir = (cos(Angle), sin(Angle));
		Vector2 rightDir = (cos(Angle - 90.0), sin(Angle - 90.0));
		double nativeFwd  = vel.x * fwdDir.x   + vel.y * fwdDir.y;
		double nativeSide = vel.x * rightDir.x + vel.y * rightDir.y;

		// Re-project the SAME magnitude native movement already computed onto
		// the path's own basis (full 3D -- a wall/ceiling tangent isn't purely
		// horizontal, and native MovePlayer only ever touches vel.xy).
		vel = railTan * nativeFwd + railRight * nativeSide;
	}
}
