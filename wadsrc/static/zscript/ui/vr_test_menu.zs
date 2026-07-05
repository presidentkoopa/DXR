// ============================================================================
//  XR TEST MENU  -  in-world (worldspace) VR menu proof-of-concept.
//
//  Renders a row of neon glow-panel tiles floating in front of you, point at
//  one with the OFF-HAND (VR) or your view (flatscreen), press USE to select.
//  Auto-opens on GRABMAP; elsewhere bind a key to `netevent xrmenu` to toggle.
//
//  Rendering: level.AddGlowPanel() pushes an FGlowSpot that the flat billboard
//  pass draws; GlowSpots is cleared every game tic (p_tick.cpp), so we simply
//  re-emit the tiles every WorldTick -- no accumulation, no cleanup needed.
//  Registered via mapinfo/common.txt GameInfo.AddEventHandlers.
// ============================================================================
class XRTestMenuHandler : StaticEventHandler
{
    const NUM   = 5;
    const DIST  = 130.0;    // forward distance from the eye when opened
    const SPAN  = 260.0;    // total horizontal width of the tile row
    const HITR  = 34.0;     // pointer hit radius per tile (generous)

    bool    menuOpen;
    bool    autoOpened;
    int     hovered;
    int     prevButtons;
    Vector3 anchor;         // frozen tile-row centre (captured on open)
    Vector3 rightv;         // frozen right axis of the row

    void OpenMenu(PlayerPawn pmo)
    {
        if (!pmo) return;
        double a = pmo.angle;
        Vector3 fwd = (cos(a), sin(a), 0);
        Vector3 rt  = (cos(a - 90), sin(a - 90), 0);
        Vector3 eye = pmo.pos + (0, 0, 48);
        anchor = eye + fwd * DIST;
        rightv = rt;
        menuOpen = true;
        hovered = -1;
        Console.Printf("\c[Gold]== XR TEST MENU ==  point off-hand, press USE to select:");
        Console.Printf("  \c[White]1\c- Give All Weapons    \c[White]2\c- Give IceHook (climb any wall)    \c[White]3\c- Give XRWhip    \c[White]4\c- Full Health    \c[White]5\c- Close");
    }

    Vector3 TilePos(int i)
    {
        double off = -SPAN * 0.5 + i * (SPAN / double(NUM - 1));
        return anchor + rightv * off;
    }

    override void WorldTick()
    {
        Actor pm = players[consoleplayer].mo;
        PlayerPawn pmo = pm ? PlayerPawn(pm) : null;
        if (!pmo || pmo.health <= 0)
        {
            prevButtons = players[consoleplayer].cmd.buttons;
            return;
        }

        // auto-open once when the test range loads
        if (!autoOpened && (level.MapName ~== "GRABMAP"))
        {
            autoOpened = true;
            OpenMenu(pmo);
        }
        if (!menuOpen)
        {
            prevButtons = players[consoleplayer].cmd.buttons;
            return;
        }

        // ---- pointer ray: VR off-hand, else flatscreen view aim ----
        Vector3 origin;
        double aang, apit;
        CVar vm = CVar.FindCVar("vr_mode");
        bool vr = vm && vm.GetInt() != 0;
        if (vr)
        {
            origin = pmo.OffhandPos;
            aang   = pmo.OffhandAngle;
            apit   = pmo.OffhandPitch;
        }
        else
        {
            origin = pmo.pos + (0, 0, 41);   // flatscreen: eye ~= standard Doom view height
            aang   = pmo.angle;
            apit   = pmo.pitch;
        }
        Vector3 dir = (cos(aang) * cos(apit), sin(aang) * cos(apit), -sin(apit));

        // ---- hit test (ray vs tile spheres, nearest in front wins) ----
        hovered = -1;
        double bestProj = 1e9;
        for (int i = 0; i < NUM; i++)
        {
            Vector3 T   = TilePos(i);
            Vector3 toT = T - origin;
            double proj = toT.x * dir.x + toT.y * dir.y + toT.z * dir.z;
            if (proj <= 8) continue;
            Vector3 closest = origin + dir * proj;
            double d = (T - closest).Length();
            if (d < HITR && proj < bestProj) { bestProj = proj; hovered = i; }
        }

        // ---- draw tiles (re-emitted every tic) ----
        for (int i = 0; i < NUM; i++)
        {
            Vector3 T = TilePos(i);
            Color c;
            double r;
            if (i == hovered) { c = Color(255, 130, 255, 255); r = 30.0; }  // hover: bright cyan-white, bigger
            else              { c = Color(255,  40,  90, 200); r = 22.0; }  // idle: dim blue
            level.AddGlowPanel(c, r, T.x, T.y, T.z, 14, 1.0, 0.0, 0.0, i + 1);
        }

        // ---- select on USE rising edge ----
        int btn = players[consoleplayer].cmd.buttons;
        if ((btn & BT_USE) && !(prevButtons & BT_USE) && hovered >= 0)
            DoAction(hovered, pmo);
        prevButtons = btn;
    }

    void DoAction(int idx, PlayerPawn pmo)
    {
        switch (idx)
        {
        case 0:
            // string LITERALS convert to Class<Inventory> at compile time (a runtime String does not).
            // Vanilla-slot guns:
            pmo.GiveInventory("Pistol", 1);       pmo.GiveInventory("Shotgun", 1);
            pmo.GiveInventory("SuperShotgun", 1); pmo.GiveInventory("Chaingun", 1);
            pmo.GiveInventory("RocketLauncher", 1);pmo.GiveInventory("PlasmaRifle", 1);
            pmo.GiveInventory("BFG9000", 1);      pmo.GiveInventory("Chainsaw", 1);
            // [XR] the VR-specific arsenal was MISSING from "give all" -- which is why the sword and
            // shieldsaw were never seen. Give the whole roster incl. the melee/grab tools.
            pmo.GiveInventory("Rifle", 1);        pmo.GiveInventory("SMG", 1);
            pmo.GiveInventory("Revolver", 1);     pmo.GiveInventory("M79", 1);
            pmo.GiveInventory("Flamethrower", 1); pmo.GiveInventory("VRSword", 1);
            pmo.GiveInventory("ShieldSaw", 1);    pmo.GiveInventory("IceHook", 1);
            pmo.GiveInventory("XRWhip", 1);
            pmo.GiveInventory("Clip", 400);
            pmo.GiveInventory("Shell", 200);
            pmo.GiveInventory("RocketAmmo", 100);
            pmo.GiveInventory("Cell", 600);
            Console.Printf("\c[Green]Gave the FULL arsenal + ammo (incl. Sword, ShieldSaw, Whip, IceHook).");
            break;
        case 1:
            pmo.GiveInventory("IceHook", 1);
            Console.Printf("\c[Cyan]Gave IceHook - grip any solid wall to climb it.");
            break;
        case 2:
            pmo.GiveInventory("XRWhip", 1);
            Console.Printf("\c[Cyan]Gave XRWhip.");
            break;
        case 3:
            pmo.GiveBody(200);
            Console.Printf("\c[Green]Full health.");
            break;
        case 4:
            menuOpen = false;
            Console.Printf("\c[Gray]XR Test Menu closed. Bind a key to 'netevent xrmenu' to reopen.");
            break;
        }
    }

    override void NetworkProcess(ConsoleEvent e)
    {
        if (!(e.Name ~== "xrmenu")) return;
        if (menuOpen) { menuOpen = false; return; }
        Actor pm = players[consoleplayer].mo;
        if (pm) OpenMenu(PlayerPawn(pm));
    }

    override void WorldUnloaded(WorldEvent e)
    {
        menuOpen = false;
        autoOpened = false;
    }
}
