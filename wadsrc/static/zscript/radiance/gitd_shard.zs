// ============================================================================
//  GITD_ShardTest -- TEMP verification of the "shard explode / assemble" display.
//  The number's four digits are FOUR separate camera-facing panels. They sit
//  assembled as "1234", then burst apart to scattered offsets, hold, and snap
//  back together -- looping. Camera-facing (dir 0,0) so every shard stays
//  readable as it flies. Pure choreography on the panel primitive; no engine
//  change. Delete after the unfolding-display milestone.
// ============================================================================
class GITD_ShardTest : EventHandler
{
	int t;

	override void WorldTick()
	{
		let pmo = players[consoleplayer].mo;
		if (!pmo) return;
		t++;

		double a    = pmo.angle;
		double fwdx = cos(a), fwdy = sin(a);
		double rgtx = sin(a), rgty = -cos(a);   // camera right (horizontal)
		double dist = 170.0;
		double cx = pmo.pos.x + fwdx * dist;
		double cy = pmo.pos.y + fwdy * dist;
		double cz = pmo.pos.z + 122.0;          // float ABOVE the triptych demo

		double h       = 16.0;
		double spacing = h * 2.2;

		// --- explode factor: assembled -> burst -> hold -> snap back, looping ---
		int period = 150;
		int ph = t % period;
		double ex;
		if      (ph <  35) ex = 0.0;                          // assembled hold
		else if (ph <  70) ex = double(ph - 35) / 35.0;       // exploding out
		else if (ph < 105) ex = 1.0;                          // scattered hold
		else               ex = 1.0 - double(ph - 105) / 45.0;// snapping back
		ex = clamp(ex, 0.0, 1.0);
		ex = ex * ex * (3.0 - 2.0 * ex);                      // ease

		Color col = Color(255, 255, 150, 40);   // gold demo

		for (int i = 0; i < 4; i++)
		{
			int digit = i + 1;                                // 1,2,3,4

			// assembled home: a centred row along camera-right
			double off   = (double(i) - 1.5) * spacing;
			double homeX = cx + rgtx * off;
			double homeY = cy + rgty * off;

			// scatter burst: corners of a spread, plus vertical fan
			double sgnH = (i == 0 || i == 2) ? -1.0 : 1.0;    // left/right
			double sgnV = (i < 2)            ?  1.0 : -1.0;   // up/down
			double px = homeX + rgtx * sgnH * 75.0 * ex;
			double py = homeY + rgty * sgnH * 75.0 * ex;
			double pz = cz    +         sgnV * 60.0 * ex;

			level.AddGlowPanel(col, h, px, py, pz, 13, 1.0, 0.0, 0.0, digit);
		}
	}
}
