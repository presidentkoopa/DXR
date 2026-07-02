// ============================================================================
//  GITD_TriptychTest -- TEMP verification of FIXED-ORIENTATION glow panels.
//  Emits a 3-panel triptych in front of the player every tic: a centre panel
//  facing the player, plus two arms HINGED at the centre's edges and fanned
//  back by a fixed angle. Proves "connected glows across multiple planes in
//  air" -- the foundation for the unfolding score displays.
//
//  Fixed orientation is selected by passing a NON-ZERO (dirX,dirY) to
//  AddGlowPanel: that vector becomes the panel's outward normal. (dir 0,0 =
//  camera-facing, used by the combo digit.) Delete after the milestone.
// ============================================================================
class GITD_TriptychTest : EventHandler
{
	int t;   // global tic counter driving the unfold animation

	override void WorldTick()
	{
		let pmo = players[consoleplayer].mo;
		if (!pmo) return;
		t++;

		// triptych centre: a fixed point out in front of the player
		double a    = pmo.angle;
		double dist = 170.0;
		double cx = pmo.pos.x + cos(a) * dist;
		double cy = pmo.pos.y + sin(a) * dist;
		double cz = pmo.pos.z + 50.0;

		// facing dir = from the panel centre back to the player (horizontal, unit)
		double dx = pmo.pos.x - cx, dy = pmo.pos.y - cy;
		double dl = sqrt(dx*dx + dy*dy);
		if (dl < 0.001) return;
		dx /= dl; dy /= dl;

		// --- UNFOLD animation: flat -> open -> hold -> close -> hold, looping ---
		int period = 150;
		int ph = t % period;
		double openf;
		if      (ph <  40) openf = double(ph) / 40.0;            // arms swing open
		else if (ph <  95) openf = 1.0;                          // held open
		else if (ph < 135) openf = 1.0 - double(ph - 95) / 40.0; // arms swing closed
		else               openf = 0.0;                          // held flat
		openf = openf * openf * (3.0 - 2.0 * openf);             // smoothstep ease

		double h  = 22.0;                       // panel half-size
		double th = openf * 48.0;               // fan angle: 0 (flat strip) .. 48 deg (deployed)
		Color  col = Color(255, 60, 200, 255);  // cyan demo

		// the centre panel's horizontal RIGHT vector (matches the engine: right = (n.y, -n.x))
		double rxx = dy, ryy = -dx;

		// --- centre: fixed, facing the player ---
		level.AddGlowPanel(col, h, cx, cy, cz, 13, 1.0, dx, dy, 1234);

		// --- right arm: hinged at centre's right edge, normal turned by -th ---
		double eRx = cx + rxx*h, eRy = cy + ryy*h;        // centre right edge
		double nRx = dx*cos(-th) - dy*sin(-th);           // facing rotated -th
		double nRy = dx*sin(-th) + dy*cos(-th);
		double rRx = nRy, rRy = -nRx;                     // arm's right vector
		level.AddGlowPanel(col, h, eRx + rRx*h, eRy + rRy*h, cz, 13, 1.0, nRx, nRy, 1234);

		// --- left arm: hinged at centre's left edge, normal turned by +th ---
		double eLx = cx - rxx*h, eLy = cy - ryy*h;        // centre left edge
		double nLx = dx*cos(th) - dy*sin(th);             // facing rotated +th
		double nLy = dx*sin(th) + dy*cos(th);
		double rLx = nLy, rLy = -nLx;                     // arm's right vector
		level.AddGlowPanel(col, h, eLx - rLx*h, eLy - rLy*h, cz, 13, 1.0, nLx, nLy, 1234);
	}
}
