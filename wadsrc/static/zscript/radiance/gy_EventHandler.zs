/* Copyright Alexander 'm8f' Kromm (mmaulwurff@gmail.com) 2020-2021
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
 */

class gy_EventHandler : EventHandler
{

  override
  void worldTick()
  {
    if (_isFired)
    {
      return;
    }

    _isFired = true;
    removeStonesOnMap();

    // 2.8 merge: master toggle. When off, existing graves are not re-spawned
    // (the stones already removed above stay gone for this session).
    let cv = CVar.GetCVar("gy_enabled", players[consoleplayer]);
    if (cv && !cv.GetBool()) { return; }

    let storage = gy_Storage.of();

    gy_Death death;
    while (death = storage.next())
    {
      sendNetworkEvent("gy_spawn" .. death.toString());
    }
  }

  override
  void worldThingDied(WorldEvent event)
  {
    if (event.thing == NULL || event.thing.player == NULL) { return; }

    // 2.8 merge: master toggle. When off, deaths are not recorded (no new graves).
    let cv = CVar.GetCVar("gy_enabled", players[consoleplayer]);
    if (cv && !cv.GetBool()) { return; }

    String name = event.thing.player.getUserName();
    String obituaryPart;
    if (event.thing.target != NULL)
    {
      String killerName = (event.thing.target.player != NULL)
        ? event.thing.target.player.getUserName()
        : event.thing.target.getTag();
      obituaryPart = ", killed by " .. killerName;
    }
    String obituary = String.format( "Here lies %s%s.\n%s\n%s"
                                   , name
                                   , obituaryPart
                                   , SystemTime.format("%F %T", _now)
                                   , level.TimeFormatted()
                                   );

    let storage = gy_Storage.of();
    let death   = gy_Death.of(event.thing.pos, obituary);
    storage.registerDeath(death);

    if (multiplayer) { sendNetworkEvent("gy_spawnlive" .. death.toString()); }
  }

  override
  void networkProcess(ConsoleEvent event)
  {
    if (event.name.left(8) == "gy_spawn")
    {
      bool live = (event.name.left(12) == "gy_spawnlive");
      String payload = live ? event.name.mid(12) : event.name.mid(8);
      let death = gy_Death.fromString(payload);
      let pos   = death.getLocation();

      // pick a marker set (cvar-selectable; defaults to tombstones)
      let cvType = CVar.GetCVar("gy_marker_type", players[consoleplayer]);
      int markerType = (cvType != NULL) ? cvType.GetInt() : 0;
      Array<String> classes;
      gy_MarkerRegistry.getSet(markerType, classes);

      // deterministic per-location pick within the set, so the same grave
      // always uses the same marker across sessions
      int i     = abs(int(pos.x + pos.y + pos.z)) % classes.size();
      let c     = classes[i];
      let stone = gy_Stone(Actor.spawn(c, death.getLocation(), ALLOW_REPLACE));
      stone.setObituary(death.getObituary());
      stone.setTint(gy_pickColor(death.getObituary()));
      if (live) { stone.setInstantPopin(); }  // your own fresh death pops now
    }
    else if (event.name == "gy_remove_all")
    {
      gy_Storage.of().clearAll();
      removeStonesOnMap();
      print("GY_REMOVE_ALL_MESSAGE");
    }
    else if (event.name == "gy_remove_map")
    {
      gy_Storage.of().clearThisMap();
      removeStonesOnMap();
      print("GY_REMOVE_MAP_MESSAGE");
    }
  }

  override
  void renderOverlay(RenderEvent event)
  {
    // Workaround to get the current time, which is UI-scoped.
    // Part 1/2.
    int second = level.time / 35 + 1;
    if (second > _lastSecond)
    {
      setNow(second, SystemTime.Now());
    }
  }

// private: ////////////////////////////////////////////////////////////////////////////////////////

  private
  void print(String message)
  {
    Console.printf("%s", StringTable.localize(message, false));
  }

  // Tint the marker by what killed the player. Returns white (no tint) when
  // nothing matches. Reads the obituary string the mod already builds.
  private
  Color gy_pickColor(String obituary)
  {
    String o = obituary.MakeLower();
    if      (o.IndexOf("imp")      != -1) return Color(255, 139,  69,  19); // brown
    else if (o.IndexOf("zombie")   != -1 || o.IndexOf("former") != -1) return Color(255,  85, 107,  47); // olive
    else if (o.IndexOf("demon")    != -1 || o.IndexOf("pinky")  != -1) return Color(255, 170,  51,  51); // red
    else if (o.IndexOf("caco")     != -1) return Color(255,  68,  68, 204); // blue
    else if (o.IndexOf("baron")    != -1 || o.IndexOf("knight") != -1) return Color(255, 221, 102, 170); // pink
    else if (o.IndexOf("revenant") != -1) return Color(255, 221, 221, 221); // bone
    else if (o.IndexOf("lava")     != -1 || o.IndexOf("slime") != -1 || o.IndexOf("nukage") != -1) return Color(255,  51, 204,  51); // toxic
    return Color(255, 255, 255, 255); // default: no tint
  }

  private
  void removeStonesOnMap()
  {
    let i = ThinkerIterator.create("gy_Stone");
    Actor a;
    while (a = Actor(i.Next()))
    {
      a.Destroy();
    }
  }

  // Workaround to get the current time, which is UI-scoped.
  // Part 2/2.
  private
  void setNow(int lastSecond, int now) const
  {
    _lastSecond = lastSecond;
    _now = now;
  }

  private transient bool _isFired;
  private int _lastSecond;
  private int _now;

} // class gy_EventHandler
