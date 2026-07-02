// ============================================================================
//  GITD_PanelTest -- a SINGLE clean panel floating in front of the player with a
//  big "1234" on it. No combat, no blood, no other panels. Pure read of whether
//  the digit renders. Look straight ahead. Delete after the VR digit is fixed.
// ============================================================================
class GITD_PanelTest : EventHandler
{
	override void WorldTick()
	{
		let pmo = players[consoleplayer].mo;
		if (!pmo) return;
		double a  = pmo.angle;
		double px = pmo.pos.x + cos(a) * 140.0;
		double py = pmo.pos.y + sin(a) * 140.0;
		double pz = pmo.pos.z + 38.0;   // ~eye height
		// dir 0,0 = camera-facing; radius 32 = big & readable; counter 1234.
		level.AddGlowPanel(Color(255, 60, 160, 255), 32.0, px, py, pz, 13, 1.0, 0.0, 0.0, 1234);
	}
}
