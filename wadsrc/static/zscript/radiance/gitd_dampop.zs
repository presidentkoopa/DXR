// ============================================================================
//  GITD_DamPop -- a per-HIT neon damage number. One spawns every time the
//  player damages a monster, launches up-and-out from the body, arcs, and
//  fades. Rapid fire => dozens flying across the view: the arcade storm.
//  Camera-facing so each pop stays readable as it flies. Pure choreography on
//  the glow-panel primitive.
//
//  NOTE: the launch speed / lifetime / size below are PLACEHOLDER feel values
//  for the user to dial -- not tuned. (gitd_dampop_enabled gates the whole thing.)
// ============================================================================
class GITD_DamPop : Actor
{
	int dmg;
	int life;
	Vector3 vel;
	Color col;

	Default { +NOINTERACTION +NOGRAVITY +NOBLOCKMAP +DONTSPLASH +NOTONAUTOMAP; RenderStyle "None"; }
	States { Spawn: TNT1 A 1; Loop; }

	static void Fire(Vector3 at, int damage)
	{
		let p = GITD_DamPop(Spawn("GITD_DamPop", at));
		if (!p) return;
		p.dmg = damage;
		p.life = 0;
		// jumpy up-and-out spread
		p.vel = (frandom(-1.2, 1.2), frandom(-1.2, 1.2), frandom(3.0, 5.5));
		
		CVar cc = CVar.FindCVar("gitd_damage_numbers_color");
		p.col = cc ? cc.GetColor() : Color(255, 255, 240, 190);
	}

	override void Tick()
	{
		Super.Tick();
		life++;
		int maxl = 26;
		if (life > maxl) { Destroy(); return; }

		// integrate the little arc
		SetOrigin(pos + vel, true);
		vel.z  -= 0.45;     // gravity pull
		vel.xy *= 0.93;     // horizontal drag

		double fade = 1.0 - double(life) / double(maxl);
		fade = clamp(fade, 0.0, 1.0);
		fade = fade * fade * (3.0 - 2.0 * fade);

		double h = 11.0;                              // small pop
		level.AddGlowPanel(col, h, pos.x, pos.y, pos.z, 13, fade, 0.0, 0.0, dmg);
	}
}
