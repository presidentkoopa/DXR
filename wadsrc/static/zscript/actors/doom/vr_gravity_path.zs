// ============================================================================
//  XR Gravity Path — off-hand POWER
//  Palm-out (OffhandRoll) -> sweep the off-hand across a floor/wall/ceiling to
//  draw a walkway of discrete rectangular SDF TILES, roughly player-width, that
//  connect edge-to-edge along their long sides. NOT a blended ribbon, not dots --
//  each tile is its own flat rectangle, physically abutting the next.
//  Walk onto the walkway -> your personal gravity (native AActor.GravityDir +
//  GravityAnchor, C++ core) reorients to that surface and you REST against it
//  (wall-standing collision core, not just a sideways pull).
//  Fire your grapple anywhere -> it pulls you off the walkway, and gravity
//  auto-restores to normal.
// ============================================================================

class XR_GravityPathNode : Actor
{
	Vector3 SurfaceNormal;   // outward-facing; -SurfaceNormal = local "down"
	Vector3 Tangent;         // unit direction along the walkway at this tile
	double  TileLength;      // this tile's length along Tangent (varies per segment)

	// [XR] TUNE THESE IN-HEADSET: SIGL's exact source pixel size isn't known here,
	// so Scale is a best-effort default, not a verified unit-exact conversion.
	const TILE_WIDTH   = 40.0;   // world units, roughly player diameter
	const XR_BASE_PX   = 64.0;   // assumed base graphic size backing "SIGL" -- adjust if tiles render the wrong size

	Default
	{
		+NOGRAVITY +NOCLIP +NOBLOCKMAP +DONTSPLASH +NOTIMEFREEZE
		+FLATSPRITE +ROLLCENTER
		RenderStyle "Add";
		Alpha 0.9;
	}
	States
	{
	Spawn:
		SIGL A -1 Bright;
		Stop;
	}

	// Standard Doom yaw/pitch decomposition of a direction vector (degrees).
	// This is the SAME Yaw-then-Pitch convention FLATSPRITE's own render matrix
	// applies (hw_sprites.cpp), so orienting Angle/Pitch this way rotates the
	// tile's local "up" (its flat-quad normal) to point along the given vector.
	static void XR_VectorToYawPitch(Vector3 n, out double yaw, out double pitch)
	{
		double horiz = sqrt(n.x * n.x + n.y * n.y);
		yaw = (horiz > 0.0001) ? VectorAngle(n.x, n.y) : 0.0;
		pitch = atan2(-n.z, horiz);
	}

	// Orient this tile so its flat-quad normal = SurfaceNormal and its long
	// (width) axis = Tangent, then size it to TILE_WIDTH x TileLength.
	// NOTE: Yaw/Pitch (which way the tile faces) use the engine's standard
	// vector-to-angle convention and are the well-grounded half of this. Roll
	// (spin around the resulting normal, i.e. which way "along the walkway"
	// points) is derived from first principles below -- correct in structure,
	// but FLATSPRITE's exact roll handedness hasn't been render-verified, so a
	// mirrored/rotated tile in-headset is a one-line sign flip here, not a
	// redesign.
	void XR_Orient()
	{
		double yaw, pitch;
		XR_VectorToYawPitch(SurfaceNormal, yaw, pitch);
		Angle = yaw;
		Pitch = pitch;

		// "Natural" width axis at Roll=0 for this yaw/pitch, using Doom's
		// standard forward/right basis (forward = (cos(yaw),sin(yaw),0) at
		// pitch 0; right = forward rotated -90 in the horizontal plane).
		double ryaw = yaw - 90.0;
		Vector3 baseRight = (cos(ryaw), sin(ryaw), 0.0);

		// Project Tangent onto the tile's own plane (perpendicular to normal).
		Vector3 n = SurfaceNormal.Unit();
		double tdotn = Tangent.x * n.x + Tangent.y * n.y + Tangent.z * n.z;
		Vector3 tproj = (Tangent.x - n.x * tdotn, Tangent.y - n.y * tdotn, Tangent.z - n.z * tdotn);
		double tlen = tproj.Length();
		if (tlen > 0.0001)
		{
			tproj /= tlen;
			// Signed angle from baseRight to tproj about axis n (cross/dot).
			Vector3 c = (baseRight.y * tproj.z - baseRight.z * tproj.y,
						 baseRight.z * tproj.x - baseRight.x * tproj.z,
						 baseRight.x * tproj.y - baseRight.y * tproj.x);
			double crossDotN = c.x * n.x + c.y * n.y + c.z * n.z;
			double dotRT = baseRight.x * tproj.x + baseRight.y * tproj.y + baseRight.z * tproj.z;
			Roll = atan2(crossDotN, dotRT);
		}

		Scale = (TileLength / XR_BASE_PX, TILE_WIDTH / XR_BASE_PX);
	}
}

class XR_GravityPath : Inventory
{
	Array<XR_GravityPathNode> nodes;
	bool casting;
	bool onRoad;
	Vector3 lastNodePos;

	const CAST_DIST    = 512.0;
	const NODE_SPACING = 24.0;
	const ROAD_RADIUS  = 48.0;
	const MAX_NODES    = 128;

	Default
	{
		Inventory.Amount 1;
		Inventory.MaxAmount 1;
		+INVENTORY.UNDROPPABLE
		+INVENTORY.UNTOSSABLE
		Tag "XR Gravity Path";
	}

	// Palm-out gate: cast while the off-hand is rolled outward (tunable band).
	private bool IsPalmOut()
	{
		if (!owner || !owner.player) return false;
		double r = abs(owner.OffhandRoll);
		return (r > 45.0 && r < 135.0);
	}

	// Derive the surface normal at a trace hit (FLineTraceData has no HitNormal).
	private Vector3 DeriveNormal(FLineTraceData t, Vector3 aimDir)
	{
		// 3D floor top/bottom
		if (t.Hit3DFloor &&
			(t.HitType == FLineTraceData.TRACE_HitFloor || t.HitType == FLineTraceData.TRACE_HitCeiling))
		{
			double tz = t.Hit3DFloor.top.ZatPoint(t.HitLocation.xy);
			double bz = t.Hit3DFloor.bottom.ZatPoint(t.HitLocation.xy);
			return (abs(t.HitLocation.z - tz) <= abs(t.HitLocation.z - bz))
				 ? t.Hit3DFloor.top.Normal : t.Hit3DFloor.bottom.Normal;
		}
		// Floor / ceiling incl. slopes
		if (t.HitSector &&
			(t.HitType == FLineTraceData.TRACE_HitFloor || t.HitType == FLineTraceData.TRACE_HitCeiling))
		{
			return (t.SectorPlane == 0) ? t.HitSector.floorplane.Normal
										: t.HitSector.ceilingplane.Normal;
		}
		// Wall: perpendicular of the line delta, disambiguated by aim
		if (t.HitType == FLineTraceData.TRACE_HitWall && t.HitLine)
		{
			Vector2 d = t.HitLine.delta;
			double dl = d.Length(); if (dl < 0.0001) dl = 1.0;
			double n1x = -d.y / dl, n1y = d.x / dl;
			double dv = n1x * aimDir.x + n1y * aimDir.y;
			return (dv > 0.0) ? (-n1x, -n1y, 0.0) : (n1x, n1y, 0.0);
		}
		return (0.0, 0.0, 1.0); // fallback: floor-up
	}

	private XR_GravityPathNode FindNearNode()
	{
		if (!owner) return null;
		XR_GravityPathNode best = null;
		double bestDist = ROAD_RADIUS;
		for (int i = 0; i < nodes.Size(); i++)
		{
			let n = nodes[i];
			if (!n) continue;
			double dd = (n.pos - owner.pos).Length();
			if (dd < bestDist) { bestDist = dd; best = n; }
		}
		return best;
	}

	// Spawn ONE rectangular tile spanning from lastNodePos to the new hit point --
	// not a marker AT the hit point. Consecutive tiles' long edges touch because
	// each tile's leading edge is the previous tile's trailing edge by construction.
	private void PaintTick()
	{
		let pmo = owner;
		Vector3 aim = pmo.OffhandDir(self, 0, pmo.OffhandPitch);
		FLineTraceData t;
		bool hit = pmo.LineTrace(pmo.OffhandAngle, CAST_DIST, pmo.OffhandPitch,
								 TRF_ISOFFHAND | TRF_THRUACTORS, 0, 0, 0, t);
		if (!hit || t.HitType == FLineTraceData.TRACE_HitActor || t.HitType == FLineTraceData.TRACE_HitNone)
			return;
		if (nodes.Size() >= MAX_NODES) return;

		if (nodes.Size() == 0)
		{
			lastNodePos = t.HitLocation;
			return;
		}

		Vector3 seg = t.HitLocation - lastNodePos;
		double segLen = seg.Length();
		if (segLen <= NODE_SPACING) return;

		Vector3 mid = lastNodePos + seg * 0.5;
		let n = XR_GravityPathNode(Actor.Spawn("XR_GravityPathNode", mid));
		if (n)
		{
			n.SurfaceNormal = DeriveNormal(t, aim);
			n.Tangent = seg / segLen;
			n.TileLength = segLen;
			n.XR_Orient();
			nodes.Push(n);
		}
		lastNodePos = t.HitLocation;
	}

	// Public exit hook (e.g. call from the grapple on fire for an instant detach).
	void ExitRoad()
	{
		onRoad = false;
		if (owner) owner.GravityDir = (0.0, 0.0, 0.0);
	}

	void ClearPath()
	{
		for (int i = 0; i < nodes.Size(); i++) if (nodes[i]) nodes[i].Destroy();
		nodes.Clear();
		lastNodePos = (0.0, 0.0, 0.0);
	}

	override void DoEffect()
	{
		Super.DoEffect();
		if (!owner || !owner.player) return;

		// PAINT while palm-out.
		if (IsPalmOut())
		{
			casting = true;
			PaintTick();
		}
		else
		{
			casting = false;
		}

		// WALK: near a tile -> reorient personal gravity to rest against its surface.
		let near = FindNearNode();
		if (near)
		{
			onRoad = true;
			owner.GravityDir = -near.SurfaceNormal;   // <-- native C++ per-actor gravity core
			owner.GravityAnchor = near.pos;           // <-- the virtual rest plane's anchor point
		}
		else if (onRoad)
		{
			// Left the walkway (e.g. grappled away) -> restore normal gravity.
			ExitRoad();
		}
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
