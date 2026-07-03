// ============================================================================
//  GITD_ScoreBurst -- the kill-reward burstScore display. Spawned by a combo's
//  Bank() at the spot where the chain ended. The final burstScore's digits CONVERGE
//  in from a scatter (shard-assemble), hold, then FADE out. Camera-facing so it
//  stays readable; one-shot (self-destructs). Built entirely on the glow-panel
//  primitive -- the first unfolding display wired to a real game event.
// ============================================================================
class GITD_ScoreBurst : Actor
{
	int burstScore;
	int owner;
	int life;
	int maxlife;

	Default { +NOINTERACTION +NOGRAVITY +NOBLOCKMAP +DONTSPLASH +NOTONAUTOMAP; RenderStyle "None"; }
	States { Spawn: TNT1 A 1; Loop; }

	static int Pow10(int p) { int v = 1; for (int k = 0; k < p; k++) v *= 10; return v; }

	override void Tick()
	{
		Super.Tick();
		life++;
		if (maxlife <= 0) maxlife = 90;
		if (life > maxlife) { Destroy(); return; }

		let pmo = players[consoleplayer].mo;
		if (!pmo) return;

		// asm: 1 (scattered) -> 0 (assembled) over the first 22 tics; hold; then fade out.
		double asm, fade = 1.0;
		if (life < 22)
			asm = 1.0 - double(life) / 22.0;
		else if (life < maxlife - 25)
			asm = 0.0;
		else { asm = 0.0; fade = 1.0 - double(life - (maxlife - 25)) / 25.0; }
		asm  = clamp(asm,  0.0, 1.0); asm  = asm  * asm  * (3.0 - 2.0 * asm);
		fade = clamp(fade, 0.0, 1.0); fade = fade * fade * (3.0 - 2.0 * fade);

		// digit count of the burstScore
		int n = 1, tmp = burstScore;
		while (tmp >= 10) { tmp /= 10; n++; }
		if (n > 5) n = 5;

		double a = pmo.angle;
		double rgtx = sin(a), rgty = -cos(a);   // camera right (horizontal)
		double h = 18.0;
		double spacing = h * 2.2;
		Color col = Color(255, 255, 150, 40);   // gold

		for (int i = 0; i < n; i++)
		{
			int digit = (burstScore / Pow10(n - 1 - i)) % 10;

			// assembled home: centred row along camera-right
			double off   = (double(i) - double(n - 1) / 2.0) * spacing;
			double homeX = pos.x + rgtx * off;
			double homeY = pos.y + rgty * off;

			// scatter burst direction per shard
			double sgnH = (i % 2 == 0) ? -1.0 : 1.0;
			double sgnV = (i < (n + 1) / 2) ? 1.0 : -1.0;
			double px = homeX + rgtx * sgnH * 80.0 * asm;
			double py = homeY + rgty * sgnH * 80.0 * asm;
			double pz = pos.z + sgnV * 60.0 * asm;

			level.AddGlowPanel(col, h, px, py, pz, 13, fade, 0.0, 0.0, digit);
		}
	}
}
