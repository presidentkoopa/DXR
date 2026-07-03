// ============================================================================
// gitd_shaderbridge.zs -- Radiance Shader Bridge
// ============================================================================
// Syncs User CVars and Gameplay Events to the main fragment shader (main.fp)
// ============================================================================

class GITD_ShaderBridge : StaticEventHandler
{
	int lastHitTime;
	int lastFireTime;
	int lastImpactTime;
	Vector3 lastImpactPos;
	int lastHealth;   // was an illegal function-local 'static' -- ZScript has no persistent local statics

	override void OnRegister()
	{
		lastHitTime = -9999;
		lastFireTime = -9999;
		lastImpactTime = -9999;
		lastImpactPos = (0,0,0);
	}

	override void WorldThingSpawned(WorldEvent e)
	{
		if (!e.Thing) return;
		
		// Catch common impact/explosion markers
		if (e.Thing is "BulletPuff" || e.Thing is "GrenadeExplosionEffect" || e.Thing is "BFGExtra")
		{
			lastImpactPos = e.Thing.Pos;
			lastImpactTime = level.maptime;
		}
	}

	override void WorldTick()
	{
		// Monitor player damage and firing in Play Scope
		PlayerInfo pi = players[consoleplayer];
		if (pi && pi.mo)
		{
			// Damage detection (simple health drop check)
			if (pi.health < lastHealth) { lastHitTime = level.maptime; }
			lastHealth = pi.health;

			// Firing detection
			if (pi.WeaponState & WF_WEAPONREADY) { /* not firing */ }
			else if (pi.mo.player.ReadyWeapon && pi.mo.player.WeaponState & WF_WEAPONBOBBING) { /* not firing */ }
			else { lastFireTime = level.maptime; }
		}
	}

	// Sync every UI tick to ensure sliders and reactive effects feel responsive.
	override void UiTick()
	{
		// GITD fog / visual-regime / impact / gameplay-event uniforms were pushed here via
		// Shader.SetUniform{Int,Float,Vec3}("main", ...) -- methods that DO NOT EXIST for the scene
		// shader (and would target a post-process path that can't reach main.fp anyway). Those uniforms
		// now live in the StreamData UBO (hw_renderstate.h + vk_shader.cpp), defaulting to OFF. A live
		// per-frame feed (cvars + events -> a C++ global copied in FRenderState::Reset) is the B2 follow-up.

		// --- BloomBoost & Adrenaline Bloom ---
		syncBloomBoost();
	}

	ui void syncBloomBoost()
	{
		PlayerInfo pi = players[consoleplayer];
		if (!pi) return;

		bool enabled = CVar.GetCVar("gitd_bloom").GetBool();
		if (!enabled)
		{
			Shader.SetEnabled(pi, "BloomBoostPre", false);
			Shader.SetEnabled(pi, "BloomBoostPost", false);
			return;
		}

		float gamma = CVar.GetCVar("gitd_bloomboost_gamma").GetFloat();
		float contrast = CVar.GetCVar("gitd_bloomboost_contrast").GetFloat() * 0.01;
		float brightness = CVar.GetCVar("gitd_bloomboost_brightness").GetFloat() * 0.01;

		// Adrenaline Spike
		if (CVar.GetCVar("gitd_bloom_reactive").GetBool())
		{
			float reactAmt = CVar.GetCVar("gitd_bloom_react_amt").GetFloat();
			float reactSpeed = CVar.GetCVar("gitd_bloom_react_speed").GetFloat();

			// Calculate decay since last events
			float fireAge = (level.maptime - lastFireTime) / 35.0;
			float hitAge = (level.maptime - lastHitTime) / 35.0;

			float fireSpike = max(0.0, 1.0 - fireAge / reactSpeed) * reactAmt;
			float hitSpike = max(0.0, 1.0 - hitAge / (reactSpeed * 2.0)) * (reactAmt * 1.5);

			gamma *= (1.0 + fireSpike * 0.5);
			contrast *= (1.0 + hitSpike);
			brightness += (fireSpike * 0.1);
		}

		Shader.SetUniform1f(pi, "BloomBoostPre", "gamma", 1.0 / max(0.01, gamma));
		Shader.SetUniform1f(pi, "BloomBoostPre", "contrast", contrast);
		Shader.SetUniform1f(pi, "BloomBoostPre", "brightness", brightness);
		Shader.SetEnabled(pi, "BloomBoostPre", true);

		Shader.SetUniform1f(pi, "BloomBoostPost", "gamma", gamma);
		Shader.SetUniform1f(pi, "BloomBoostPost", "contrast", 1.0 / max(0.01, contrast));
		Shader.SetUniform1f(pi, "BloomBoostPost", "brightness", brightness);
		Shader.SetEnabled(pi, "BloomBoostPost", true);
	}

	float GetKillstreakHeat()
	{
		// HF_GlowHandler is an EventHandler singleton, not a Thinker -- ThinkerIterator can never
		// see it. The real native lookup for a StaticEventHandler/EventHandler instance is
		// StaticEventHandler.Find() (events.zs), which is clearscope.
		HF_GlowHandler h = HF_GlowHandler(StaticEventHandler.Find("HF_GlowHandler"));
		return h ? h.ksHeat : 0.0;
	}
}
