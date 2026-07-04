// ============================================================================
//  vr_hardpoint_markers.zs  --  ENGINE feature. Visible billboards at every
//  configured native hardpoint slot (holsters + wrist ability mounts) so the VR
//  player can SEE where to reach to draw/stow a weapon or fire a wrist ability.
//
//  Reads slot geometry ENTIRELY through the native queries (GetHardpointCount /
//  GetHardpointAnchorType / GetHardpointWorldPos) -- there is no second copy of
//  the anchor math on the ZScript side, so a marker can never drift from where the
//  native draw/stow/ability trigger (VR_UpdateHardpoints, p_user.cpp) actually is.
//
//  Uses the +FORCEXYBILLBOARD glow-billboard technique (the same one the VR damage
//  counters use) -- NOT particle rendering, which does not reach the VR stereo pass.
//  Ships in the core pk3 alongside the native thunks, so no rebuild-gating needed.
//  Registered via mapinfo/common.txt GameInfo.AddEventHandlers = "...VRHardpointMarkerHandler".
// ============================================================================

class VRHardpointMarker : Actor
{
	int   slotIndex;
	Actor pawnOwner;

	Default
	{
		+NOBLOCKMAP
		+NOGRAVITY
		+DONTSPLASH
		+NOINTERACTION
		+CLIENTSIDEONLY
		+FORCEXYBILLBOARD
		RenderStyle "Add";
		Alpha 0.5;
		Scale 0.22;
	}

	override void Tick()
	{
		if (!pawnOwner || !pawnOwner.player || pawnOwner.health <= 0)
		{
			Destroy();
			return;
		}

		let showCv = CVar.GetCVar("vr_hardpoint_markers_show", pawnOwner.player);
		if (showCv && !showCv.GetBool()) { Alpha = 0.0; return; }

		int anchor = pawnOwner.GetHardpointAnchorType(slotIndex);
		if (anchor < 0) { Destroy(); return; }   // slot no longer exists

		// forHand 0 by convention: a consistent, visible position (the native side
		// still resolves the real per-hand reach independently in VR_UpdateHardpoints).
		vector3 pos = pawnOwner.GetHardpointWorldPos(slotIndex, 0);
		SetOrigin(pos, true);

		sprite = GetSpriteIndex("JGRN");   // placeholder billboard sprite
		frame = 0;

		// Body holsters slightly larger than wrist ability mounts, so the two kinds
		// read differently at a glance (anchor 1 == HP_ANCHOR_WRIST).
		Alpha = 0.6;
		Scale = (anchor == 1) ? (0.16, 0.16) : (0.22, 0.22);
	}
}

class VRHardpointMarkerHandler : StaticEventHandler
{
	Array<VRHardpointMarker> markers;

	override void WorldTick()
	{
		for (int i = markers.Size() - 1; i >= 0; i--)
		{
			if (markers[i] == null || markers[i].bDestroyed) markers.Delete(i);
		}

		PlayerInfo pl = players[consoleplayer];
		if (!pl || !pl.mo || pl.health <= 0) return;

		let showCv = CVar.GetCVar("vr_hardpoint_markers_show", pl);
		if (showCv && !showCv.GetBool()) return;

		int count = pl.mo.GetHardpointCount();
		for (int s = 0; s < count; s++)
		{
			bool have = false;
			for (int i = 0; i < markers.Size(); i++)
			{
				if (markers[i] && markers[i].slotIndex == s && markers[i].pawnOwner == pl.mo) { have = true; break; }
			}
			if (have) continue;

			vector3 pos = pl.mo.GetHardpointWorldPos(s, 0);
			let m = VRHardpointMarker(Actor.Spawn("VRHardpointMarker", pos));
			if (m) { m.slotIndex = s; m.pawnOwner = pl.mo; markers.Push(m); }
		}
	}
}
