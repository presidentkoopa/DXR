// ============================================================================
//  XR GRABMAP TEXT  -  fills the GRABMAP test range with helpful signage drawn
//  by the native neonfont / MSDF text renderer via level.SpawnSDFText().
//
//  CORE-ONLY: SpawnSDFText is a native function added alongside this handler, so
//  this file must NOT ship in the loadable XRTestMenu.pk3 (that has to stay
//  compile-clean on the older exe). Registered in mapinfo/common.txt.
// ============================================================================
class XRGrabmapText : StaticEventHandler
{
    // pillar textures, left -> right, matching tools/testmaps/build_grabmap.py
    static const string PILLARS[] = {
        "SUPPORT2", "SUPPORT3", "PIPE1", "PIPE2", "PIPE4", "PIPE6",
        "LADDER", "METLADR", "CLIMBABLE", "METAL", "BROWN96", "COMPTALL", "TEKWALL", "STARTAN2  NO CLIMB" };

    override void WorldLoaded(WorldEvent e)
    {
        if (e.IsSaveGame) return;
        if (!(level.MapName ~== "GRABMAP")) return;
        PlaceLabels();
    }

    // shorthand
    void L(double x, double y, double z, string t, double s)
    {
        level.SpawnSDFText(x, y, z, t, s);
    }

    void PlaceLabels()
    {
        // spawn / entrance (player at y=-1250 facing +y / north)
        L(0, -1050, 240, "GRABMAP", 2.8);
        L(0, -1066, 160, "NINJA WARRIOR RANGE", 1.6);
        L(0, -1092,  96, "POINT OFFHAND AT TILES  PRESS USE", 0.85);

        // throwing pit (barrel ring at x~-500, target stack at x~500)
        L(-500, -850, 210, "GRAB AND THROW BARRELS", 1.0);
        L( 500, -560, 190, "TARGET STACK", 1.1);

        // climb zone: texture pillars (row at y=1300) + climb wall (y~1630)
        L(0, 1150, 340, "CLIMB TEST", 2.2);
        L(0, 1118, 260, "GRIP A WALL AND PULL DOWN", 0.85);
        double startx = -1040.0;
        for (int i = 0; i < PILLARS.Size(); i++)
            L(startx + i * 160.0, 1232, 150, PILLARS[i], 0.7);
        L(0, 1500, 300, "CLIMB THE WALL", 1.4);

        // whip gauntlet (east, rising platforms with gaps)
        L(830, -520, 380, "WHIP GAUNTLET", 2.2);
        L(830, -560, 320, "GRAPPLE AND SWING UP", 0.85);
        L(1000, 1400, 340, "GOAL", 1.8);

        // firing range (west, live targets downrange)
        L(-1350, -1000, 320, "FIRING RANGE", 2.2);
        L(-1350, -1040, 250, "LIVE TARGETS DOWNRANGE", 0.85);
    }
}
