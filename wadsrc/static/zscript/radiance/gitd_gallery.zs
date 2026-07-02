// ============================================================================
//  GLOW IN THE DARK -- Pattern previews (gallery + inline option rows)
//
//  Procedural, animated shape previews drawn on the flat 2D menu layer -- like
//  the tooltip panel, so they read correctly in VR. Nothing renders in-world.
//
//  GITD_GalleryMenu  : a full grid picker (one animated cell per value).
//  OptionMenuItemGITDPreview : an OPTION ROW that draws the animated preview of
//                              its current value inline, right on the list.
//
//  The drawing toolkit (DrawShape + primitives) is STATIC so both share it.
//  Animation is driven off real time (MSTimeF), like the spinning menu cursor.
// ============================================================================

class GITD_GalleryMenu : OptionMenu
{
	// ---- shape ids -------------------------------------------------------
	const SH_POOL    = 0;   const SH_SEAM   = 1;   const SH_GHOST  = 2;
	const SH_PING    = 3;   const SH_X      = 4;   const SH_HEXF   = 5;
	const SH_HEXR    = 6;   const SH_SPIRAL = 7;   const SH_SONAR  = 8;
	const SH_FIRE    = 9;   const SH_SQR    = 10;  const SH_STAR   = 11;
	const SH_SUN     = 12;  const SH_GRID   = 13;  const SH_RANDOM = 14;
	const SH_GLOW    = 15;  const SH_RING   = 16;  const SH_INVERSE= 17;
	const SH_OFF     = 18;  const SH_BARS   = 19;  const SH_SCAN   = 20;
	const SH_ERUPT   = 21;  const SH_DUST   = 22;
	// shape ids >= 100 mean "draw an animated preset colour swatch for id-100".
	const SH_PRESET  = 100;

	// ---- gallery config (filled by SetupGallery in subclasses) ----------
	string  galTitle;
	string  cvarName;
	int     cols;

	array<int>    vals;     // cvar value for each cell
	array<string> labels;   // caption under each cell
	array<int>    shapes;   // which procedural shape to draw

	int sel;                // highlighted cell
	int activeValue;        // value currently written in the cvar (or last preset applied)
	bool presetMode;        // true = cells fire gitd_preset_apply netevents, not a cvar

	// neon palette
	Color C_CYAN;
	Color C_GOLD;
	Color C_WHITE;
	Color C_DIMBG;
	Color C_RED;

	override void Init(Menu parent, OptionMenuDescriptor desc)
	{
		super.Init(parent, desc);
		C_CYAN  = Color(255,  60, 220, 255);
		C_GOLD  = Color(255, 255, 200,  60);
		C_WHITE = Color(255, 255, 255, 255);
		C_DIMBG = Color(255,  10,  16,  26);
		C_RED   = Color(255, 255,  70,  70);
		cols = 5;
		SetupGallery();

		CVar c = CVar.FindCVar(cvarName);
		activeValue = c ? c.GetInt() : 0;
		sel = 0;
		for (int i = 0; i < vals.Size(); i++)
			if (vals[i] == activeValue) { sel = i; break; }
	}

	// subclasses override this to fill galTitle / cvarName / the cell lists.
	virtual void SetupGallery() {}

	void AddCell(int v, string label, int shape)
	{
		vals.Push(v); labels.Push(label); shapes.Push(shape);
	}

	static double Frac(double x) { return x - floor(x); }

	// ===================== INPUT =========================================
	override bool MenuEvent(int mkey, bool fromcontroller)
	{
		int n = vals.Size();
		if (n == 0) return super.MenuEvent(mkey, fromcontroller);

		int rows = (n + cols - 1) / cols;
		int row  = sel / cols;
		int col  = sel % cols;

		switch (mkey)
		{
			case MKEY_Up:
				row = (row - 1 + rows) % rows;
				sel = ClampToGrid(row, col, n);
				MenuSound("menu/cursor");
				return true;
			case MKEY_Down:
				row = (row + 1) % rows;
				sel = ClampToGrid(row, col, n);
				MenuSound("menu/cursor");
				return true;
			case MKEY_Left:
				col = (col - 1 + cols) % cols;
				sel = ClampToGrid(row, col, n);
				MenuSound("menu/cursor");
				return true;
			case MKEY_Right:
				col = (col + 1) % cols;
				sel = ClampToGrid(row, col, n);
				MenuSound("menu/cursor");
				return true;
			case MKEY_Enter:
			{
				activeValue = vals[sel];
				if (presetMode)
				{
					EventHandler.SendNetworkEvent("gitd_preset_apply", vals[sel]);
				}
				else
				{
					CVar c = CVar.FindCVar(cvarName);
					if (c) c.SetInt(activeValue);
				}
				MenuSound("menu/choose");
				return true;
			}
		}
		return super.MenuEvent(mkey, fromcontroller);
	}

	// keep a grid move on a valid cell (last row may be short)
	int ClampToGrid(int row, int col, int n)
	{
		int idx = row * cols + col;
		if (idx >= n) idx = n - 1;
		return idx;
	}

	// ===================== DRAW (grid) ===================================
	override void Drawer()
	{
		int sw = Screen.GetWidth();
		int sh = Screen.GetHeight();
		double su = sh / 200.0;            // virtual-pixel scale
		double t  = MSTimeF() / 1000.0;    // seconds, smooth even when paused

		int n = vals.Size();
		if (n == 0) { super.Drawer(); return; }

		// ---- title ----
		Font big = BigFont;
		double tsc = su * 0.9;
		double tw  = big.StringWidth(galTitle) * tsc;
		Screen.DrawText(big, Font.CR_GOLD, int((sw - tw) / 2), int(6 * su),
			galTitle, DTA_ScaleX, tsc, DTA_ScaleY, tsc);

		// ---- grid metrics ----
		int rows      = (n + cols - 1) / cols;
		double cellW  = 58 * su;
		double cellH  = 56 * su;
		double shapeR = 19 * su;
		double gridW  = cols * cellW;
		double startX = (sw - gridW) / 2 + cellW / 2;
		double startY = 34 * su;

		for (int i = 0; i < n; i++)
		{
			int c = i % cols;
			int r = i / cols;
			double pcx = startX + c * cellW;
			double pcy = startY + r * cellH + shapeR;

			double bx = pcx - cellW / 2 + 2 * su;
			double by = pcy - shapeR - 4 * su;
			double bw = cellW - 4 * su;
			double bh = cellH - 4 * su;
			Screen.Dim(C_DIMBG, (i == sel) ? 0.85 : 0.45,
				int(bx), int(by), int(bw), int(bh));

			Color shapeCol = (i == sel) ? C_WHITE : C_CYAN;
			DrawShape(shapes[i], pcx, pcy, shapeR, t, shapeCol, C_DIMBG, (i == sel));

			Font fnt = smallfont;
			double lsc = su * 0.75;
			double lw  = fnt.StringWidth(labels[i]) * lsc;
			int lcol = (i == sel) ? Font.CR_GOLD :
				(vals[i] == activeValue ? Font.CR_WHITE : Font.CR_GREY);
			Screen.DrawText(fnt, lcol, int(pcx - lw / 2),
				int(pcy + shapeR + 3 * su), labels[i],
				DTA_ScaleX, lsc, DTA_ScaleY, lsc);

			if (vals[i] == activeValue)
			{
				double dx = pcx + cellW / 2 - 8 * su;
				double dy = by + 2 * su;
				Screen.Dim(C_GOLD, 0.9, int(dx), int(dy), int(4 * su), int(4 * su));
			}

			if (i == sel)
			{
				int a = int(150 + 105 * (0.5 + 0.5 * sin(t * 300)));
				DrawRectBorder(bx, by, bw, bh, 2.0 * su, C_GOLD, a);
			}
		}

		// ---- footer hint ----
		Font fnt = smallfont;
		double hsc = su * 0.8;
		string hint = "Arrows: Move      Fire / Enter: Select      Back: Exit";
		double hw = fnt.StringWidth(hint) * hsc;
		Screen.DrawText(fnt, Font.CR_DARKGRAY, int((sw - hw) / 2),
			int(sh - 14 * su), hint, DTA_ScaleX, hsc, DTA_ScaleY, hsc);
	}

	// map a pattern cvar's current value to a shape id (for inline previews)
	static int ShapeForCvar(Name cv, int v)
	{
		if (cv == 'gitd_death_style')
		{
			static const int D[] = { SH_POOL, SH_SEAM, SH_GHOST, SH_PING, SH_X,
				SH_HEXF, SH_HEXR, SH_SPIRAL, SH_SONAR, SH_FIRE, SH_SQR, SH_STAR,
				SH_SUN, SH_GRID, SH_RANDOM };
			if (v >= 0 && v < D.Size()) return D[v];
			return SH_RANDOM;
		}
		if (cv == 'gitd_impact_style')
		{
			static const int I[] = { SH_OFF, SH_GLOW, SH_RING, SH_X, SH_HEXF,
				SH_HEXR, SH_SPIRAL, SH_SQR, SH_STAR, SH_SUN, SH_GRID, SH_RANDOM,
				SH_INVERSE };
			if (v >= 0 && v < I.Size()) return I[v];
			return SH_RANDOM;
		}
		if (cv == 'gitd_impactspark')
		{
			static const int S[] = { SH_OFF, SH_FIRE, SH_ERUPT, SH_DUST, SH_FIRE,
				SH_POOL, SH_FIRE, SH_RANDOM };
			if (v >= 0 && v < S.Size()) return S[v];
			return SH_RANDOM;
		}
		if (cv == 'gitd_wall_pattern')
		{
			if (v == 0) return SH_BARS;
			if (v == 1) return SH_SCAN;
			if (v == 2) return SH_GRID;
			return SH_BARS;   // 5 = Pulse Bars
		}
		return SH_RING;
	}

	// ===================== STATIC DRAWING TOOLKIT ========================
	static void DrawRectBorder(double x, double y, double w, double h, double th, Color col, int a)
	{
		Screen.DrawThickLine(int(x),     int(y),     int(x + w), int(y),     th, col, a);
		Screen.DrawThickLine(int(x + w), int(y),     int(x + w), int(y + h), th, col, a);
		Screen.DrawThickLine(int(x + w), int(y + h), int(x),     int(y + h), th, col, a);
		Screen.DrawThickLine(int(x),     int(y + h), int(x),     int(y),     th, col, a);
	}

	static void Ngon(double cx, double cy, double rad, int sides, double rot, double th, Color col, int a)
	{
		if (sides < 3) sides = 3;
		double px, py;
		for (int i = 0; i <= sides; i++)
		{
			double ang = rot + i * 360.0 / sides;
			double x = cx + rad * cos(ang);
			double y = cy + rad * sin(ang);
			if (i > 0) Screen.DrawThickLine(int(px), int(py), int(x), int(y), th, col, a);
			px = x; py = y;
		}
	}

	static void StarShape(double cx, double cy, double rOut, double rIn, int points, double rot, double th, Color col, int a)
	{
		int seg = points * 2;
		double px, py;
		for (int i = 0; i <= seg; i++)
		{
			double rad = (i % 2 == 0) ? rOut : rIn;
			double ang = rot + i * 360.0 / seg;
			double x = cx + rad * cos(ang);
			double y = cy + rad * sin(ang);
			if (i > 0) Screen.DrawThickLine(int(px), int(py), int(x), int(y), th, col, a);
			px = x; py = y;
		}
	}

	static void Spiral(double cx, double cy, double rmax, double turns, double rot, double th, Color col, int a)
	{
		int seg = 56;
		double px, py;
		for (int i = 0; i <= seg; i++)
		{
			double f = double(i) / seg;
			double ang = rot + f * 360.0 * turns;
			double rad = rmax * f;
			double x = cx + rad * cos(ang);
			double y = cy + rad * sin(ang);
			if (i > 0) Screen.DrawThickLine(int(px), int(py), int(x), int(y), th, col, a);
			px = x; py = y;
		}
	}

	static void Rays(double cx, double cy, double r0, double r1, int count, double rot, double th, Color col, int a)
	{
		for (int i = 0; i < count; i++)
		{
			double ang = rot + i * 360.0 / count;
			Screen.DrawThickLine(int(cx + r0 * cos(ang)), int(cy + r0 * sin(ang)),
				int(cx + r1 * cos(ang)), int(cy + r1 * sin(ang)), th, col, a);
		}
	}

	static void Circle(double cx, double cy, double rad, double th, Color col, int a)
	{
		Ngon(cx, cy, rad, 24, 0, th, col, a);
	}

	static void SoftDot(double cx, double cy, double rad, Color col, double amt)
	{
		Screen.Dim(col, amt, int(cx - rad), int(cy - rad), int(rad * 2), int(rad * 2));
	}

	static Color HSV(double h, double s, double v)
	{
		h = h - floor(h / 360.0) * 360.0;
		double c = v * s;
		double k = h / 60.0;
		double m2 = k - 2.0 * floor(k / 2.0);
		double x = c * (1.0 - abs(m2 - 1.0));
		double m = v - c;
		double r = 0, g = 0, b = 0;
		int seg = int(k);
		if (seg == 0)      { r = c; g = x; b = 0; }
		else if (seg == 1) { r = x; g = c; b = 0; }
		else if (seg == 2) { r = 0; g = c; b = x; }
		else if (seg == 3) { r = 0; g = x; b = c; }
		else if (seg == 4) { r = x; g = 0; b = c; }
		else               { r = c; g = 0; b = x; }
		return Color(255, int((r + m) * 255), int((g + m) * 255), int((b + m) * 255));
	}

	static Color LerpC(Color a, Color b, double f)
	{
		return Color(255,
			int(a.r + (b.r - a.r) * f),
			int(a.g + (b.g - a.g) * f),
			int(a.b + (b.b - a.b) * f));
	}

	static void Swatch(double cx, double cy, double R, Color col, double amt)
	{
		double s = R * 1.6;
		Screen.Dim(col, amt, int(cx - s), int(cy - s), int(s * 2), int(s * 2));
	}

	static void GradSwatch(double cx, double cy, double R, Color top, Color bot)
	{
		int bands = 8;
		double s = R * 1.6;
		double bh = (s * 2) / bands;
		for (int i = 0; i < bands; i++)
		{
			double f = double(i) / (bands - 1);
			Screen.Dim(LerpC(top, bot, f), 0.92,
				int(cx - s), int(cy - s + i * bh), int(s * 2), int(bh) + 2);
		}
	}

	static void DrawPresetSwatch(int id, double cx, double cy, double R, double t)
	{
		double pls = 0.5 + 0.5 * sin(t * 150);
		Color cyan = Color(255,  60, 220, 255);
		Color red  = Color(255, 255,  60,  60);
		Color blue = Color(255,  40,  90, 255);
		Color white= Color(255, 240, 245, 255);
		Color mag  = Color(255, 255,  60, 200);
		Color grn  = Color(255,  80, 255,  90);
		Color orng = Color(255, 255, 150,  40);
		switch (id)
		{
			case 1:
				Swatch(cx, cy, R, Color(255, 8, 10, 16), 0.95);
				for (int i = 0; i < 5; i++)
				{
					double ang = t * 40 + i * 72;
					Color fl = HSV(i * 70 + t * 30, 1.0, 1.0);
					SoftDot(cx + R * cos(ang) * 0.9, cy + R * sin(ang) * 0.9, R * 0.12,
						fl, 0.4 + 0.4 * sin(t * 300 + i));
				}
				break;
			case 2:  Swatch(cx, cy, R, cyan, 0.55 + 0.4 * pls); break;
			case 3:  Swatch(cx, cy, R, HSV(t * 80, 1.0, 1.0), 0.9); break;
			case 4:  Swatch(cx, cy, R, red, 0.45 + 0.5 * pls); break;
			case 5:  GradSwatch(cx, cy, R, white, blue); break;
			case 6:  GradSwatch(cx, cy, R, mag, cyan); break;
			case 7:  Swatch(cx, cy, R, grn, 0.6 + 0.3 * (0.5 + 0.5 * sin(t * 500))); break;
			case 8:  Swatch(cx, cy, R, HSV(160 + 90 * sin(t * 40), 0.8, 1.0), 0.85); break;
			case 9:  Swatch(cx, cy, R, LerpC(orng, red, 0.5 + 0.5 * sin(t * 360)), 0.9); break;
			case 10:
				Swatch(cx, cy, R, Color(255, 10, 12, 16), 0.95);
				Swatch(cx, cy, R, white, 0.05 + 0.10 * pls);
				break;
			case 11: // Synthwave Dusk
				GradSwatch(cx, cy, R, Color(255, 255, 90, 20), Color(255, 106, 13, 173)); // orange to violet
				SoftDot(cx, cy, R * 0.4, Color(255, 255, 0, 127), 0.5 + 0.3 * pls); // pulsing magenta
				break;
			case 12: // Nuclear Waste
				GradSwatch(cx, cy, R, Color(255, 204, 255, 0), Color(255, 57, 255, 20)); // yellow to acid green
				SoftDot(cx, cy, R * 0.5, Color(255, 0, 75, 35), 0.7); // quiet green center
				break;
			case 13: // Glitch Matrix
				Swatch(cx, cy, R, Color(255, 8, 10, 16), 0.95); // black void
				DrawRectBorder(cx - R * 1.2, cy - R * 1.2, R * 2.4, R * 2.4, 1.5, Color(255, 0, 255, 0), int(150 + 105 * pls)); // glowing code-green border
				break;
			case 14: // Cyberpunk Rain
				GradSwatch(cx, cy, R, Color(255, 0, 240, 255), Color(255, 255, 0, 127)); // cyan to magenta
				for (int i = 0; i < 3; i++)
				{
					double ry = cy - R + Frac(t * 1.2 + i * 0.33) * (R * 2);
					SoftDot(cx + (i - 1) * R * 0.5, ry, R * 0.15, Color(255, 255, 255, 0), 0.8); // falling yellow drops
				}
				break;
			case 15: // Vaporwave Chill
				GradSwatch(cx, cy, R, Color(255, 255, 176, 124), Color(255, 147, 112, 219)); // peach to lavender
				SoftDot(cx, cy, R * 0.45, Color(255, 255, 105, 180), 0.4 + 0.2 * pls); // slow breathing hot-pink
				break;
			case 16: // Overdrive Rainbow
				Swatch(cx, cy, R, HSV(t * 120, 1.0, 1.0), 0.9);
				break;
			case 17: // Solar Flare
				GradSwatch(cx, cy, R, Color(255, 255, 215, 0), Color(255, 80, 0, 0)); // gold to crimson
				SoftDot(cx, cy, R * 0.5, Color(255, 255, 69, 0), 0.6 + 0.3 * pls); // blazing solar orange
				break;
			case 18: // Nebula Dream
				GradSwatch(cx, cy, R, Color(255, 255, 105, 180), Color(255, 75, 0, 130)); // pink to indigo
				SoftDot(cx, cy, R * 0.45, Color(255, 0, 128, 128), 0.7); // slow breathing teal
				break;
			case 19: // Chroma Overdrive
				GradSwatch(cx, cy, R, Color(255, 255, 0, 255), Color(255, 148, 0, 211)); // magenta to purple
				DrawRectBorder(cx - R * 1.2, cy - R * 1.2, R * 2.4, R * 2.4, 1.5, Color(255, 0, 255, 0), int(150 + 105 * pls)); // screaming neon-lime border
				break;
			case 20: // Grid Sweep
				Swatch(cx, cy, R, Color(255, 8, 10, 16), 0.95); // black void
				double sy = cy - R + Frac(t * 0.8) * (R * 2);
				Screen.DrawThickLine(int(cx - R), int(sy), int(cx + R), int(sy), 2.0, Color(255, 0, 255, 0), 255);
				SoftDot(cx, sy, R * 0.3, Color(255, 0, 255, 0), 0.6);
				break;
		}
		double s = R * 1.6;
		DrawRectBorder(cx - s, cy - s, s * 2, s * 2, 1.5, Color(255, 0, 0, 0), 120);
	}

	// ===================== SHAPE ROUTER (static) =========================
	static void DrawShape(int shape, double cx, double cy, double R, double t, Color col, Color bg, bool selected)
	{
		if (shape >= SH_PRESET) { DrawPresetSwatch(shape - SH_PRESET, cx, cy, R, t); return; }
		double th  = (selected ? 2.4 : 1.8) * (R / 19.0);
		double pls = 0.5 + 0.5 * sin(t * 150);
		double spin = t * 60;

		switch (shape)
		{
			case SH_POOL:
			{
				for (int k = 3; k >= 1; k--)
				{
					double rr = R * (0.35 * k) * (0.92 + 0.08 * pls);
					SoftDot(cx, cy, rr, col, 0.18);
				}
				Circle(cx, cy, R * 0.85 * (0.92 + 0.08 * pls), th, col, 220);
				break;
			}
			case SH_SEAM:
			{
				double gap = R * (0.15 + 0.55 * pls);
				Screen.DrawThickLine(int(cx - R), int(cy), int(cx - gap), int(cy), th, col, 230);
				Screen.DrawThickLine(int(cx + gap), int(cy), int(cx + R), int(cy), th, col, 230);
				Screen.DrawThickLine(int(cx), int(cy - R * 0.5), int(cx), int(cy + R * 0.5), th, col, int(120 + 120 * pls));
				break;
			}
			case SH_GHOST:
			{
				double ox = R * 0.35 * sin(t * 90);
				double oy = R * 0.25 * sin(t * 140);
				SoftDot(cx + ox, cy + oy, R * 0.55, col, 0.30);
				Circle(cx + ox, cy + oy, R * 0.6, th, col, 200);
				SoftDot(cx + ox - R * 0.22, cy + oy - R * 0.05, R * 0.08, bg, 0.9);
				SoftDot(cx + ox + R * 0.22, cy + oy - R * 0.05, R * 0.08, bg, 0.9);
				break;
			}
			case SH_PING:
			{
				for (int k = 0; k < 2; k++)
				{
					double ph = Frac(t * 0.6 + k * 0.5);
					int a = int(255 * (1.0 - ph));
					Circle(cx, cy, R * ph, th, col, a);
				}
				SoftDot(cx, cy, R * 0.10, col, 0.9);
				break;
			}
			case SH_X:
			{
				double rr = R * (0.85 + 0.10 * pls);
				double rot = spin * 0.15;
				for (int s = 0; s < 2; s++)
				{
					double ang = rot + 45 + s * 90;
					Screen.DrawThickLine(int(cx - rr * cos(ang)), int(cy - rr * sin(ang)),
						int(cx + rr * cos(ang)), int(cy + rr * sin(ang)), th * 1.3, col, 235);
				}
				break;
			}
			case SH_HEXF:
			{
				double s = R * 0.42;
				for (int gy = -1; gy <= 1; gy++)
				for (int gx = -1; gx <= 1; gx++)
				{
					double hx = cx + gx * s * 1.5;
					double hy = cy + gy * s * 1.5;
					int a = int(110 + 120 * (0.5 + 0.5 * sin(t * 220 + (gx + gy) * 60)));
					Ngon(hx, hy, s * 0.55, 6, 90, th * 0.8, col, a);
				}
				break;
			}
			case SH_HEXR:
			{
				for (int k = 0; k < 2; k++)
				{
					double ph = Frac(t * 0.6 + k * 0.5);
					int a = int(255 * (1.0 - ph));
					Ngon(cx, cy, R * ph, 6, 90 + spin * 0.2, th, col, a);
				}
				break;
			}
			case SH_SPIRAL:
				Spiral(cx, cy, R * 0.95, 2.5, spin, th, col, 235);
				break;
			case SH_SONAR:
			{
				for (int k = 1; k <= 3; k++)
					Circle(cx, cy, R * 0.3 * k, th, col, int((90 + 110 * pls)));
				SoftDot(cx, cy, R * 0.12, col, 0.9);
				break;
			}
			case SH_FIRE:
			{
				double ph = Frac(t * 0.7);
				int a = int(255 * (1.0 - ph));
				Rays(cx, cy, R * 0.1, R * ph, 10, spin * 0.3, th, col, a);
				for (int i = 0; i < 10; i++)
				{
					double ang = spin * 0.3 + i * 36;
					SoftDot(cx + R * ph * cos(ang), cy + R * ph * sin(ang), R * 0.06, col, a / 255.0);
				}
				break;
			}
			case SH_SQR:
			{
				for (int k = 0; k < 2; k++)
				{
					double ph = Frac(t * 0.6 + k * 0.5);
					int a = int(255 * (1.0 - ph));
					Ngon(cx, cy, R * ph, 4, 45, th, col, a);
				}
				break;
			}
			case SH_STAR:
				StarShape(cx, cy, R * (0.9 + 0.1 * pls), R * 0.4, 5, spin * 0.5 - 90, th, col, 235);
				break;
			case SH_SUN:
			{
				for (int i = 0; i < 16; i++)
				{
					double ang = spin * 0.4 + i * 22.5;
					double r1 = (i % 2 == 0) ? R * 0.95 : R * 0.6;
					Screen.DrawThickLine(int(cx + R * 0.15 * cos(ang)), int(cy + R * 0.15 * sin(ang)),
						int(cx + r1 * cos(ang)), int(cy + r1 * sin(ang)), th * 0.8, col, 220);
				}
				SoftDot(cx, cy, R * 0.14, col, 0.9);
				break;
			}
			case SH_GRID:
			{
				int a = int(120 + 120 * pls);
				for (int g = -2; g <= 2; g++)
				{
					Screen.DrawThickLine(int(cx + g * R * 0.4), int(cy - R), int(cx + g * R * 0.4), int(cy + R), th * 0.7, col, a);
					Screen.DrawThickLine(int(cx - R), int(cy + g * R * 0.4), int(cx + R), int(cy + g * R * 0.4), th * 0.7, col, a);
				}
				break;
			}
			case SH_RING:
				Circle(cx, cy, R * (0.8 + 0.15 * pls), th * 1.2, col, 235);
				break;
			case SH_GLOW:
			{
				for (int k = 4; k >= 1; k--)
					SoftDot(cx, cy, R * 0.22 * k * (0.9 + 0.1 * pls), col, 0.14);
				break;
			}
			case SH_INVERSE:
			{
				SoftDot(cx, cy, R * (0.8 + 0.15 * pls), col, 0.5);
				SoftDot(cx, cy, R * 0.4, bg, 0.95);
				break;
			}
			case SH_OFF:
			{
				Circle(cx, cy, R * 0.7, th * 0.8, col, 90);
				Screen.DrawThickLine(int(cx - R * 0.5), int(cy + R * 0.5),
					int(cx + R * 0.5), int(cy - R * 0.5), th, col, 120);
				break;
			}
			case SH_BARS:
			{
				for (int b = -2; b <= 2; b++)
				{
					double hh = R * (0.4 + 0.55 * (0.5 + 0.5 * sin(t * 240 + b * 70)));
					Screen.DrawThickLine(int(cx + b * R * 0.35), int(cy + R),
						int(cx + b * R * 0.35), int(cy + R - hh * 2), th * 1.6, col, 220);
				}
				break;
			}
			case SH_SCAN:
			{
				for (int s = 0; s < 4; s++)
				{
					double yy = cy - R + Frac(t * 0.5 + s * 0.25) * (R * 2);
					Screen.DrawThickLine(int(cx - R), int(yy), int(cx + R), int(yy), th, col, 200);
				}
				break;
			}
			case SH_ERUPT:
			{
				double ph = Frac(t * 0.8);
				int a = int(255 * (1.0 - ph));
				for (int i = -3; i <= 3; i++)
				{
					double ang = -90 + i * 14;
					Screen.DrawThickLine(int(cx), int(cy + R * 0.6),
						int(cx + R * ph * cos(ang)), int(cy + R * 0.6 + R * ph * sin(ang)),
						th, col, a);
				}
				break;
			}
			case SH_DUST:
			{
				for (int k = 0; k < 3; k++)
				{
					double ph = Frac(t * 0.5 + k * 0.33);
					SoftDot(cx, cy, R * ph, col, 0.22 * (1.0 - ph));
				}
				break;
			}
			case SH_RANDOM:
			default:
			{
				int cyc = int(t * 1.2) % 6;
				int pick = SH_STAR;
				if (cyc == 0) pick = SH_SPIRAL;
				else if (cyc == 1) pick = SH_STAR;
				else if (cyc == 2) pick = SH_HEXR;
				else if (cyc == 3) pick = SH_X;
				else if (cyc == 4) pick = SH_SUN;
				else pick = SH_SQR;
				DrawShape(pick, cx, cy, R, t, col, bg, selected);
				break;
			}
		}
	}
}

// ============================================================================
//  INLINE OPTION ROW -- draws the animated preview of its current value right
//  on the options list. Used in MENUDEF as:  GITDPreview "Label", "cvar", "Values"
//  (works exactly like Option; the extra Init args are optional).
// ============================================================================
class OptionMenuItemGITDPreview : OptionMenuItemOption
{
	override int Draw(OptionMenuDescriptor desc, int y, int indent, bool selected)
	{
		int baseIndent = Super.Draw(desc, y, indent, selected);

		// figure out the current value text so we can sit the preview after it
		int sIdx = GetSelection();
		String valText = (sIdx >= 0) ? StringTable.Localize(OptionValues.GetText(mValues, sIdx)) : "";
		int valW = Menu.OptionWidth(valText) * CleanXfac_1;

		double rowH = OptionMenuSettings.mLinespacing * CleanYfac_1;
		double rad = rowH * 0.40;
		double cy = y + rowH * 0.5;
		double cx = indent + CursorSpace() + valW + rowH * 1.1;

		CVar cv = CVar.FindCVar(mAction);
		int val = cv ? cv.GetInt() : 0;
		int shape = GITD_GalleryMenu.ShapeForCvar(mAction, val);

		double t = MSTimeF() / 1000.0;
		Color col = selected ? Color(255, 255, 255, 255) : Color(255, 60, 220, 255);
		Color bg  = Color(255, 10, 16, 26);
		GITD_GalleryMenu.DrawShape(shape, cx, cy, rad, t, col, bg, false);
		return baseIndent;
	}
}

// ============================================================================
//  Death Bloom gallery -- sets gitd_death_style (15 styles).
// ============================================================================
class GITD_GalleryDeathMenu : GITD_GalleryMenu
{
	override void SetupGallery()
	{
		galTitle = "DEATH BLOOM";
		cvarName = "gitd_death_style";
		cols = 5;
		AddCell(0,  "Death Pool",   SH_POOL);
		AddCell(1,  "Seam Reveal",  SH_SEAM);
		AddCell(2,  "Ghost Walk",   SH_GHOST);
		AddCell(3,  "Death-Ping",   SH_PING);
		AddCell(4,  "Stylized X",   SH_X);
		AddCell(5,  "Hex Field",    SH_HEXF);
		AddCell(6,  "Hex Rings",    SH_HEXR);
		AddCell(7,  "Spiral",       SH_SPIRAL);
		AddCell(8,  "Pulse Detect", SH_SONAR);
		AddCell(9,  "Firework",     SH_FIRE);
		AddCell(10, "Square Rings", SH_SQR);
		AddCell(11, "Star",         SH_STAR);
		AddCell(12, "Sunburst",     SH_SUN);
		AddCell(13, "Grid",         SH_GRID);
		AddCell(14, "Random",       SH_RANDOM);
	}
}

// ============================================================================
//  Impact Stamp gallery -- sets gitd_impact_style (13 styles).
// ============================================================================
class GITD_GalleryImpactMenu : GITD_GalleryMenu
{
	override void SetupGallery()
	{
		galTitle = "IMPACT STAMP";
		cvarName = "gitd_impact_style";
		cols = 5;
		AddCell(0,  "Off",          SH_OFF);
		AddCell(1,  "Glow",         SH_GLOW);
		AddCell(2,  "Ring",         SH_RING);
		AddCell(3,  "Stylized X",   SH_X);
		AddCell(4,  "Hex Field",    SH_HEXF);
		AddCell(5,  "Hex Rings",    SH_HEXR);
		AddCell(6,  "Spiral",       SH_SPIRAL);
		AddCell(7,  "Square Rings", SH_SQR);
		AddCell(8,  "Star",         SH_STAR);
		AddCell(9,  "Sunburst",     SH_SUN);
		AddCell(10, "Grid",         SH_GRID);
		AddCell(11, "Random",       SH_RANDOM);
		AddCell(12, "Inverse Glow", SH_INVERSE);
	}
}

// ============================================================================
//  Spark Burst gallery -- sets gitd_impactspark (7 styles + off).
// ============================================================================
class GITD_GallerySparkMenu : GITD_GalleryMenu
{
	override void SetupGallery()
	{
		galTitle = "SPARK BURST";
		cvarName = "gitd_impactspark";
		cols = 4;
		AddCell(0, "Off",         SH_OFF);
		AddCell(1, "Sparks",      SH_FIRE);
		AddCell(2, "Eruption",    SH_ERUPT);
		AddCell(3, "Dust Puff",   SH_DUST);
		AddCell(4, "Flak Burst",  SH_FIRE);
		AddCell(5, "Scorch",      SH_POOL);
		AddCell(6, "Firecracker", SH_FIRE);
		AddCell(7, "Random",      SH_RANDOM);
	}
}

// ============================================================================
//  Wall Pattern gallery -- sets gitd_wall_pattern (BETA).
// ============================================================================
class GITD_GalleryWallMenu : GITD_GalleryMenu
{
	override void SetupGallery()
	{
		galTitle = "WALL PATTERN";
		cvarName = "gitd_wall_pattern";
		cols = 4;
		AddCell(0, "Neon Pillar", SH_BARS);
		AddCell(1, "Scan Lines",  SH_SCAN);
		AddCell(2, "Light Grid",  SH_GRID);
		AddCell(5, "Pulse Bars",  SH_BARS);
	}
}

// ============================================================================
//  Presets gallery -- fires gitd_preset_apply netevents; animated colour
//  swatches instead of geometric shapes.
// ============================================================================
class GITD_GalleryPresetMenu : GITD_GalleryMenu
{
	override void SetupGallery()
	{
		galTitle = "PRESETS";
		cvarName = "";
		presetMode = true;
		cols = 5;
		AddCell(1,  "Blackout",    SH_PRESET + 1);
		AddCell(2,  "Neon Unison", SH_PRESET + 2);
		AddCell(3,  "Neon Chaos",  SH_PRESET + 3);
		AddCell(4,  "Red Alert",   SH_PRESET + 4);
		AddCell(5,  "Cold Front",  SH_PRESET + 5);
		AddCell(6,  "Vaporwave",   SH_PRESET + 6);
		AddCell(7,  "Acid",        SH_PRESET + 7);
		AddCell(8,  "Aurora",      SH_PRESET + 8);
		AddCell(9,  "Inferno",     SH_PRESET + 9);
		AddCell(10, "Ghost",       SH_PRESET + 10);
		AddCell(11, "Synthwave Dusk", SH_PRESET + 11);
		AddCell(12, "Nuclear Waste",  SH_PRESET + 12);
		AddCell(13, "Glitch Matrix",  SH_PRESET + 13);
		AddCell(14, "Cyberpunk Rain", SH_PRESET + 14);
		AddCell(15, "Vaporwave Chill", SH_PRESET + 15);
		AddCell(16, "Overdrive Rain", SH_PRESET + 16);
		AddCell(17, "Solar Flare",    SH_PRESET + 17);
		AddCell(18, "Nebula Dream",   SH_PRESET + 18);
		AddCell(19, "Chroma Overdrive", SH_PRESET + 19);
	}
}
