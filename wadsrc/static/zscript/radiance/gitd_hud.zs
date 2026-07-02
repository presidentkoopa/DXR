// ============================================================================
//  GITD_Hud -- the IN-AIR HUD. Health / ammo / score lifted off the 2D bottom
//  bar into floating neon number-panels that ride in front of the player and
//  update live. Built on the glow-panel digit primitive (camera-facing, dir 0,0).
//  Score accumulates from the combo system's `hf_combo_bank` netevent.
//
//  v1 layout (anchored to the player's facing each tic, so it follows you):
//     HEALTH  lower-left   (green/amber/red by amount)
//     AMMO    lower-right  (cyan)
//     SCORE   upper-centre (gold)
//  Placeholder distances/offsets/colours -- the user's to tune.
// ============================================================================
class GITD_Hud : EventHandler
{
	int score;

	override void NetworkProcess(ConsoleEvent e)
	{
		if (e.Name == "hf_combo_bank") score += e.Args[1];   // pts from the combo bank
	}

	override void WorldTick()
	{
		let pmo = players[consoleplayer].mo;
		if (!pmo || pmo.health <= 0) return;

		double a  = pmo.angle;
		double fx = cos(a), fy = sin(a);     // forward (horizontal)
		double rx = sin(a), ry = -cos(a);    // right (horizontal)
		double eyeZ = pmo.pos.z + pmo.height * 0.72;
		double dist = 64.0;
		double cx = pmo.pos.x + fx * dist;   // HUD plane centre, out in front
		double cy = pmo.pos.y + fy * dist;

		// HEALTH -- lower-left, coloured by how hurt you are.  font 0 = ARCADECLASSIC
		int hp = max(pmo.health, 0);
		Color hcol = (hp > 50) ? Color(255, 60, 255, 90)
		           : (hp > 25) ? Color(255, 255, 200, 40)
		                       : Color(255, 255, 50, 50);
		EmitHud(cx, cy, eyeZ - 30.0, rx, ry, -40.0, hcol, hp, 0);

		// AMMO -- lower-right.  font 27 = digital808 (LED look)
		int ammo = 0;
		let w = pmo.player.ReadyWeapon;
		if (w && w.Ammo1) ammo = w.Ammo1.Amount;
		EmitHud(cx, cy, eyeZ - 30.0, rx, ry, 40.0, Color(255, 60, 200, 255), ammo, 27);

		// SCORE -- upper-centre.  font 46 = karmatic_arcade
		EmitHud(cx, cy, eyeZ + 20.0, rx, ry, 0.0, Color(255, 255, 170, 40), score, 46);
	}

	// font index rides in the wipeType hundreds digit: wipeType = 13 + font*100.
	void EmitHud(double cx, double cy, double cz, double rx, double ry, double off, Color col, int val, int font)
	{
		double px = cx + rx * off;
		double py = cy + ry * off;
		level.AddGlowPanel(col, 15.0, px, py, cz, 13 + font * 100, 1.0, 0.0, 0.0, val);
	}
}
