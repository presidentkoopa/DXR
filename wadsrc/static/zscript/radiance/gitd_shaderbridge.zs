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
		if (e.Thing is "RocketExplosion" || e.Thing is "BulletPuff" || e.Thing is "Explosion")
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
			if (pi.WeaponState & WF_WEAPONREADYINV) { /* not firing */ }
			else if (pi.mo.player.ReadyWeapon && pi.mo.player.WeaponState & WF_WEAPONBOBBING) { /* not firing */ }
			else { lastFireTime = level.maptime; }
		}
	}

	// Sync every UI tick to ensure sliders and reactive effects feel responsive.
	override void UiTick()
	{
		// --- Atmospheric Fog Suite ---
		Shader.SetUniformInt("main", "u_gitd_fog_mode",      CVar.GetCVar("gitd_fog_mode").GetInt());
		Shader.SetUniformFloat("main", "u_gitd_fog_density",  CVar.GetCVar("gitd_fog_density").GetFloat());
		Shader.SetUniformFloat("main", "u_gitd_fog_height",   CVar.GetCVar("gitd_fog_height").GetFloat());
		Shader.SetUniformFloat("main", "u_gitd_fog_quantize", CVar.GetCVar("gitd_fog_quantize").GetFloat());
		Shader.SetUniformFloat("main", "u_gitd_fog_rim_power", CVar.GetCVar("gitd_fog_rim_power").GetFloat());
		Shader.SetUniformInt("main", "u_gitd_fog_lightlink",  CVar.GetCVar("gitd_fog_lightlink").GetBool());
		Shader.SetUniformFloat("main", "u_gitd_fog_speed",    CVar.GetCVar("gitd_fog_speed").GetFloat());

		// --- Global Visual Regimes ---
		Shader.SetUniformInt("main", "u_vr_visual_regime",    CVar.GetCVar("vr_visual_regime").GetInt());
		Shader.SetUniformFloat("main", "u_vr_regime_param1",  CVar.GetCVar("vr_regime_param1").GetFloat());
		Shader.SetUniformFloat("main", "u_vr_regime_param2",  CVar.GetCVar("vr_regime_param2").GetFloat());
		Shader.SetUniformFloat("main", "u_vr_regime_speed",   CVar.GetCVar("vr_regime_speed").GetFloat());
		
		// Reactive CVars
		Shader.SetUniformInt("main", "u_vr_regime_react",     CVar.GetCVar("vr_regime_react").GetBool());
		Shader.SetUniformInt("main", "u_vr_regime_center_mask", CVar.GetCVar("vr_regime_center_mask").GetBool());
		Shader.SetUniformFloat("main", "u_vr_regime_bubble_size", CVar.GetCVar("vr_regime_bubble_size").GetFloat());
		Shader.SetUniformFloat("main", "u_vr_regime_jitter",   CVar.GetCVar("vr_regime_jitter").GetFloat());
		Shader.SetUniformInt("main", "u_vr_regime_speed_link", CVar.GetCVar("vr_regime_speed_link").GetBool());
		Shader.SetUniformFloat("main", "u_vr_regime_ping_inten", CVar.GetCVar("vr_regime_ping_inten").GetFloat());

		// Advanced Customization
		Shader.SetUniformVec3("main", "u_vr_blueprint_col",   CVar.GetCVar("vr_regime_blueprint_col").GetColor());
		Shader.SetUniformFloat("main", "u_vr_thermal_inten",  CVar.GetCVar("vr_regime_thermal_inten").GetFloat());
		Shader.SetUniformFloat("main", "u_vr_noir_sat",       CVar.GetCVar("vr_regime_noir_sat").GetFloat());
		Shader.SetUniformInt("main", "u_vr_ripples_enabled",  CVar.GetCVar("vr_regime_ripples").GetBool());
		Shader.SetUniformFloat("main", "u_vr_ripple_scale",   CVar.GetCVar("vr_regime_ripple_scale").GetFloat());

		// Impact Data Sync
		Shader.SetUniformVec3("main", "u_gitd_last_impact_pos", lastImpactPos);
		Shader.SetUniformFloat("main", "u_gitd_last_impact_time", float(lastImpactTime) / 35.0);

		// --- Gameplay Event Uniforms ---
		Shader.SetUniformFloat("main", "u_gitd_last_hit_time",  float(lastHitTime) / 35.0);
		Shader.SetUniformFloat("main", "u_gitd_last_fire_time", float(lastFireTime) / 35.0);
		
		PlayerInfo pi = players[consoleplayer];
		if (pi && pi.mo)
		{
			Shader.SetUniformFloat("main", "u_gitd_player_speed", pi.mo.Vel.Length() / 32.0); // Normalized speed
		}
		
		// Sync Killstreak Heat
		Shader.SetUniformFloat("main", "u_gitd_kill_streak",  CVar.GetCVar("hf_glow_killstreak").GetBool() ? GetKillstreakHeat() : 0.0);

		// --- BloomBoost & Adrenaline Bloom ---
		syncBloomBoost();
	}

	void syncBloomBoost()
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
		// Find the global handler to get smooth heat value
		ThinkerIterator it = ThinkerIterator.Create("HF_GlowHandler", Stat_Static);
		HF_GlowHandler h = HF_GlowHandler(it.Next());
		return h ? h.ksHeat : 0.0;
	}
}
