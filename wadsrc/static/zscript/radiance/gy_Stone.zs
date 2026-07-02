/* Copyright Alexander 'm8f' Kromm (mmaulwurff@gmail.com) 2020
 *
 * This file is a part of Graveyard.
 *
 * Graveyard is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later
 * version.
 *
 * Graveyard is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
 * A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along with
 * Graveyard.  If not, see <https://www.gnu.org/licenses/>.
 *
 * --- Modifications: animation, culled dynamic light, marker abstraction. ---
 * --- These changes are likewise GPLv3.                                   ---
 */

// Base class: all animation, lighting, and culling live here so any marker
// set (tombstones, crosses, candles, ...) inherits the behavior for free.
class gy_Stone : Actor
{
  Default
  {
    Radius 16;
    Height 1;
    Gravity 1000;
    +FORCEXYBILLBOARD
  }

  void setObituary(String obituary) { _obituary = obituary; }
  void setTint(Color c) { SetShade(c); }

  override void PostBeginPlay()
  {
    Super.PostBeginPlay();
    _spawnTime    = level.time;
    _phaseOffset  = random(0, 1000);  // desync idle bounce (large range, uncorrelated)
    _base         = 1.0;
    _hasLight     = false;

    // Stagger the pop-in: when a whole graveyard spawns at map load, they
    // share a spawn tic. A random delay scatters the pops over ~1s instead
    // of one synchronized pop. Set to 0 for live deaths so your own grave
    // pops instantly (see setInstantPopin).
    _popinDelay   = random(0, 35);

    let cvPop = CVar.GetCVar("gy_popin_enabled", players[consoleplayer]);
    if (cvPop != NULL && cvPop.GetBool())
    {
      scale.x = 0.05;
      scale.y = 0.05;
    }
  }

  // Called by the spawner for a fresh death so it pops immediately.
  void setInstantPopin() { _popinDelay = 0; }

  override void Tick()
  {
    Super.Tick();

    let cvAnim = CVar.GetCVar("gy_anim_enabled", players[consoleplayer]);
    bool animOn = (cvAnim != NULL) ? cvAnim.GetBool() : true;

    if (animOn) { animate(); }
    else        { scale.x = 1.0; scale.y = 1.0; }

    updateLight();
  }

  // ---- SNES-style pop-in + idle squash & stretch ----
  private void animate()
  {
    int age = level.time - _spawnTime;

    let cvPop = CVar.GetCVar("gy_popin_enabled", players[consoleplayer]);
    bool popin = (cvPop != NULL) ? cvPop.GetBool() : true;

    if (popin)
    {
      if (age < _popinDelay)
      {
        // waiting its turn — stay tiny so the pop reads cleanly when it fires
        _base = 0.05;
        scale.x = _base;
        scale.y = _base;
        return;
      }

      int popAge = age - _popinDelay;   // time since THIS stone's pop began
      if (popAge < 24)
      {
        double t = popAge / 24.0;
        double settle = 1.0 - (1.0 - t) * (1.0 - t);          // ease-out
        double overshoot = 1.0 + 0.35 * Sin(t * 180.0) * (1.0 - t);
        _base = settle * overshoot;
      }
      else
      {
        _base = 1.0;
      }
    }
    else
    {
      _base = 1.0;
    }

    double amount = CVar.GetCVar("gy_bounce_amount", players[consoleplayer]).GetFloat();
    double speed  = CVar.GetCVar("gy_bounce_speed",  players[consoleplayer]).GetFloat();
    double squash = amount * Sin((level.time + _phaseOffset) * speed);

    scale.x = _base * (1.0 - squash);
    scale.y = _base * (1.0 + squash);
  }

  // ---- Heavily culled dynamic light, with smooth fade in/out ----
  // The light is still only "alive" within the cull distance, but instead of
  // snapping to full radius on the boundary it ramps a 0..1 fade level up (in
  // range) or down (out of range), and the attached light's radius tracks it.
  // The light actor is only removed once the fade reaches 0, so crossing the
  // cull edge looks like a candle brightening/dimming, never a pop.
  private void updateLight()
  {
    let cvOn = CVar.GetCVar("gy_light_enabled", players[consoleplayer]);
    bool lightOn = (cvOn != NULL) ? cvOn.GetBool() : false;

    let pmo = players[consoleplayer].mo;
    if (pmo == NULL) { return; }

    double cull = CVar.GetCVar("gy_light_cull", players[consoleplayer]).GetInt();
    bool inRange = lightOn && (Distance3D(pmo) <= cull);

    // Ramp the fade toward its target (~0.05/tic = about a third of a second
    // from dark to full at 35fps; reads as a candle warming up).
    double fadeStep = 0.05;
    double target = inRange ? 1.0 : 0.0;
    if (_lightFade < target)      _lightFade = min(target, _lightFade + fadeStep);
    else if (_lightFade > target) _lightFade = max(target, _lightFade - fadeStep);

    // Fully faded out -> make sure the light is gone.
    if (_lightFade <= 0.0)
    {
      if (_hasLight) { A_RemoveLight('gy_grave_light'); _hasLight = false; }
      return;
    }

    // Some fade -> (re)attach the light every tic at the faded radius. Re-
    // attaching the same named light overwrites it, so this animates smoothly.
    int r = CVar.GetCVar("gy_light_radius", players[consoleplayer]).GetInt();

    // optional candle flicker, folded into the same per-tic re-attach
    let cvFlick = CVar.GetCVar("gy_light_flicker", players[consoleplayer]);
    int flick = (cvFlick != NULL && cvFlick.GetBool()) ? random(0, 12) : 0;

    int radius = int(r * _lightFade) - flick;
    if (radius < 1) radius = 1;

    A_AttachLight( 'gy_grave_light'
                 , DynamicLight.PointLight
                 , _lightColor()
                 , radius, 0
                 , flags: DYNAMICLIGHT.LF_ATTENUATE
                 , ofs: (0, 0, 24) );
    _hasLight = true;
  }

  private Color _lightColor()
  {
    int b = CVar.GetCVar("gy_light_bright", players[consoleplayer]).GetInt();
    // warm candle tone, scaled by brightness
    return Color(255, b, int(b * 0.7), int(b * 0.4));
  }

  override bool Used(Actor user)
  {
    Console.Printf("%s", _obituary);
    return Super.Used(user);
  }

  private String  _obituary;
  private int     _spawnTime;
  private int     _phaseOffset;
  private int     _popinDelay;
  private double  _base;
  private bool    _hasLight;
  private double  _lightFade;   // 0..1 grave-light fade level (smooth in/out, no pop)
}

// ---- Marker registry ----------------------------------------------------
// gy_MarkerRegistry describes marker sets: the actor classes that make each up.
// To add a new marker type later, define its gy_Stone subclasses and append
// an entry below. The spawner picks a set by the gy_marker_type cvar.

class gy_MarkerRegistry
{
  static void getSet(int markerType, out Array<String> classes)
  {
    classes.Clear();
    switch (markerType)
    {
      // case 2: classes.Push("gy_Candle0"); break;
      case 3: // Ghost Stones (SDF)
        classes.Push("gy_GhostStone0");
        classes.Push("gy_GhostStone1");
        classes.Push("gy_GhostStone2");
        classes.Push("gy_GhostStone3");
        break;
      default:
        classes.Push("gy_Stone0");
        classes.Push("gy_Stone1");
        classes.Push("gy_Stone2");
        classes.Push("gy_Stone3");
        break;
    }
  }
}

// Default tombstone set.
class gy_Stone0 : gy_Stone { States { Spawn: gy_t a -1; Stop; } }
class gy_Stone1 : gy_Stone { States { Spawn: gy_t b -1; Stop; } }
class gy_Stone2 : gy_Stone { States { Spawn: gy_t c -1; Stop; } }
class gy_Stone3 : gy_Stone { States { Spawn: gy_t d -1; Stop; } }

// --- Ghost Stone (SDF) Variants ---
class gy_GhostStone : gy_Stone
{
    int markerType;
    float complexity;
    
    override void PostBeginPlay()
    {
        Super.PostBeginPlay();
        // Force the SIGL sprite for the SDF shader
        sprite = GetSpriteIndex("SIGL");
        frame = 0;
        
        complexity = CVar.GetCVar("gy_sdf_shiver", players[consoleplayer]).GetFloat();
    }

    override void Tick()
    {
        Super.Tick();
        
        // Pass parameters to shader via u_IsMSDF and u_MSDFGlitch
        // Bit 8 (256) signals "Graveyard Mode" to the shader
        msdf_enabled = 256 | (markerType << 4);
        msdf_glitch = complexity;
        
        // Use the actor's shade color for the holographic glow
        msdf_color = (fillcolor.r / 255.0, fillcolor.g / 255.0, fillcolor.b / 255.0);
    }
}

class gy_GhostStone0 : gy_GhostStone { override void PostBeginPlay() { markerType = 0; Super.PostBeginPlay(); } }
class gy_GhostStone1 : gy_GhostStone { override void PostBeginPlay() { markerType = 1; Super.PostBeginPlay(); } }
class gy_GhostStone2 : gy_GhostStone { override void PostBeginPlay() { markerType = 2; Super.PostBeginPlay(); } }
class gy_GhostStone3 : gy_GhostStone { override void PostBeginPlay() { markerType = 3; Super.PostBeginPlay(); } }
