// ============================================================================
//  XR Gravity Path — off-hand POWER
//  Palm-out (OffhandRoll) -> paint a gravity ribbon along the surface you aim at.
//  Walk onto it -> your personal gravity (native AActor.GravityDir, C++ core)
//  reorients to that surface. Fire your grapple anywhere -> it pulls you off the
//  ribbon and out of range, and gravity auto-restores.
//  Nodes render as bright markers (v1 placeholder); the SDF neon ribbon skin
//  (vr_sdf_procedural.fp bit 512) is the follow-up visual layer.
// ============================================================================

class XR_GravityPathNode : Actor
{
	Vector3 SurfaceNormal;   // outward-facing; -SurfaceNormal = local "down"
	Vector3 Tangent;         // forward along the ribbon

	Default
	{
		Radius 6;
		Height 6;
		+NOGRAVITY +NOCLIP +NOBLOCKMAP +DONTSPLASH +NOTIMEFREEZE
		RenderStyle "Add";
		Alpha 0.9;
		Scale 0.12;
	}
	States
	{
	Spawn:
		BAL1 A -1 Bright;
		Stop;
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

		if (nodes.Size() == 0 || (t.HitLocation - lastNodePos).Length() > NODE_SPACING)
		{
			let n = XR_GravityPathNode(Actor.Spawn("XR_GravityPathNode", t.HitLocation));
			if (n)
			{
				n.SurfaceNormal = DeriveNormal(t, aim);
				Vector3 tv = t.HitLocation - lastNodePos;
				double tl = tv.Length();
				if (nodes.Size() > 0 && tl > 0.0001) n.Tangent = tv / tl;
				nodes.Push(n);
				lastNodePos = t.HitLocation;
			}
		}
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

		// WALK: near a ribbon node -> reorient personal gravity to its surface.
		let near = FindNearNode();
		if (near)
		{
			onRoad = true;
			owner.GravityDir = -near.SurfaceNormal;   // <-- native C++ per-actor gravity core
			owner.GravityAnchor = near.pos;           // <-- the virtual rest plane's anchor point
		}
		else if (onRoad)
		{
			// Left the ribbon (e.g. grappled away) -> restore normal gravity.
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
