// Was a nested 'struct WeaponEntry' with a 'PClass' field held by value in Array<WeaponEntry>.
// ZScript dynamic arrays can't hold structs by value, and 'PClass' is the C++ name (not a ZScript type).
// Promoted to a top-level ui class holding a Class<Actor> metaclass ref (arrays of object refs are legal).
class WeaponEntry ui
{
    Class<Actor> cls;
    string tag;
    int archetype;
}

class VRWeaponAssignmentMenu : GenericMenu
{
    Array<WeaponEntry> weapons;
    int scrollOffset;
    int selected;
    int hover[2];
    
    static const string archNames[] = {
        "Auto", "Fist", "Chainsaw", "Pistol", "Shotgun", "SuperShotgun", 
        "Chaingun", "RocketLauncher", "PlasmaRifle", "BFG9000", 
        "Rifle", "SMG", "Revolver", "Flamethrower"
    };

    override void Init(Menu parent)
    {
        Super.Init(parent);
        
        for (int i = 0; i < AllActorClasses.Size(); i++)
        {
            let cls = AllActorClasses[i];
            if (cls is "Weapon" && cls.GetClassName() != "Weapon")
            {
                WeaponEntry we = new("WeaponEntry");   // now a class -> must allocate (was a value struct)
                we.cls = cls;
                we.tag = GetDefaultByType(cls).GetTag();
                we.archetype = GetVRWeaponArchetype(cls);
                weapons.Push(we);
            }
        }
        
        scrollOffset = 0;
        selected = -1;
        hover[0] = -1;
        hover[1] = -1;
    }

    override void Drawer()
    {
        Screen.Dim("black", 0.85, 0, 0, Screen.GetWidth(), Screen.GetHeight());
        
        double x = 40;
        double y = 40;
        
        Screen.DrawText(BigFont, Font.CR_GOLD, (640 - BigFont.StringWidth("Weapon Archetype Scanner"))/2, 10, "Weapon Archetype Scanner", DTA_VirtualWidth, 640, DTA_VirtualHeight, 480);
        
        int count = 15;
        for (int i = scrollOffset; i < weapons.Size() && i < scrollOffset + count; i++)
        {
            int rowColor = Font.CR_GRAY;
            if (i == hover[0] || i == hover[1])
            {
                rowColor = Font.CR_WHITE;
                Screen.Dim("gold", 0.15, x - 5, y - 2, 560, 18);
            }

            Screen.DrawText(SmallFont, rowColor, x, y, weapons[i].tag .. " (" .. weapons[i].cls.GetClassName() .. ")", DTA_VirtualWidth, 640, DTA_VirtualHeight, 480);
            
            string archName = (weapons[i].archetype >= 0 && weapons[i].archetype < archNames.Size()) ? archNames[weapons[i].archetype] : "Unknown";
            int archColor = (weapons[i].archetype == 0) ? Font.CR_DARKGRAY : Font.CR_GREEN;
            
            Screen.DrawText(SmallFont, archColor, x + 400, y, "[ " .. archName .. " ]", DTA_VirtualWidth, 640, DTA_VirtualHeight, 480);
            
            y += 20;
        }
        
        // Scroll indicators
        if (scrollOffset > 0)
            Screen.DrawText(SmallFont, Font.CR_GOLD, 300, 32, "^ UP ^", DTA_VirtualWidth, 640, DTA_VirtualHeight, 480);
        if (scrollOffset + count < weapons.Size())
            Screen.DrawText(SmallFont, Font.CR_GOLD, 300, y + 2, "v DOWN v", DTA_VirtualWidth, 640, DTA_VirtualHeight, 480);

        // Footer
        Screen.DrawText(SmallFont, Font.CR_GOLD, 40, 440, "Use Scroll Wheel or Drag to scroll. Click an item to cycle its VR archetype.", DTA_VirtualWidth, 640, DTA_VirtualHeight, 480);
        Screen.DrawText(SmallFont, Font.CR_WHITE, 40, 455, "Changes are saved to doomxr_weapons.json immediately.", DTA_VirtualWidth, 640, DTA_VirtualHeight, 480);
    }

    override bool OnUIEvent(UiEvent ev)
    {
        int ptr = ev.PointerIndex;
        if (ptr < 0 || ptr > 1) ptr = 0;

        if (ev.Type == UiEvent.Type_MouseMove)
        {
            int idx = -1;
            if (ev.MouseX >= 40 && ev.MouseX < 600 && ev.MouseY >= 40 && ev.MouseY < 40 + 15 * 20)
            {
                idx = scrollOffset + (int(ev.MouseY) - 40) / 20;
                if (idx >= weapons.Size()) idx = -1;
            }
            hover[ptr] = idx;
        }
        else if (ev.Type == UiEvent.Type_LButtonDown)
        {
            if (hover[ptr] != -1)
            {
                CycleArchetype(hover[ptr]);
                MenuSound("menu/activate");
                return true;
            }
        }
        else if (ev.Type == UiEvent.Type_WheelUp)
        {
            scrollOffset = Max(0, scrollOffset - 2);
            return true;
        }
        else if (ev.Type == UiEvent.Type_WheelDown)
        {
            scrollOffset = Min(weapons.Size() - 1, scrollOffset + 2);
            return true;
        }
        
        return Super.OnUIEvent(ev);
    }

    void CycleArchetype(int idx)
    {
        weapons[idx].archetype = (weapons[idx].archetype + 1) % archNames.Size();

        // Persist immediately via the native bridge: sets the archetype on the weapon's
        // default actor and writes doomxr_weapons.json (src/playsim/vr_weapon.cpp).
        SetVRWeaponArchetype(weapons[idx].cls, weapons[idx].archetype);
    }
}
