class SDFCombo
{
	String name;
	String type;
	String klass;
	String trig;
	String val;
	String flavor;
	String gate;
}

class SDFComboArbiter : StaticEventHandler
{
	Array<SDFCombo> combos;
	
	override void OnRegister()
	{
		// Hardcode the baseline combos for high-performance immediate access
		AddCombo("Base", "Base", "", "any kill", "+1.0 multiplier", "", "");
		AddCombo("Point-Blank", "Danger", "", "distance < 64", "+0.1", "POINT BLANK", "");
		AddCombo("Brawler", "Danger", "fist", "style:melee", "+0.5", "BRAWLER", "");
		AddCombo("Executioner", "Skill", "", "head", "+0.25", "EXECUTIONER", "");
		AddCombo("Twin Strike", "Skill", "", "head + hand:off", "+0.5", "TWIN STRIKE", "");
		AddCombo("Kneecapper", "Skill", "", "legs", "+0.15", "KNEECAPPER", "");
		AddCombo("Gunslinger", "Style", "", "head + hand:main", "+0.3", "GUNSLINGER", "");
		
		AddCombo("System Crash", "Skill", "", "dmg:energy + anatomy:cybernetic", "+0.5", "SYSTEM CRASH", "");
		
		// New Weapon Specific "Kickass" Combos
		AddCombo("Overheat", "Elemental", "flamethrower", "dmg:fire + size:large", "+0.4", "EXTRA CRISPY", "");
		AddCombo("Long Shot", "Skill", "rifle", "distance > 1024", "+0.6", "GHOST SNIPER", "");
		AddCombo("Big Iron", "Style", "revolver", "role:boss", "+1.0", "BIG IRON ON HIS HIP", "");
		AddCombo("Lead Rain", "Base", "smg", "fire:auto + count:multi", "+0.2", "LEAD STORM", "");
		AddCombo("Airburst", "Skill", "grenade", "state:airborne", "+0.5", "AIRBURST", "");
		AddCombo("Shredded", "Gore", "chainsaw", "dmg:shredder", "+0.3", "MEAT GRINDER", "");
		
		// Interaction Combos
		AddCombo("Barrel Bomber", "Environment", "", "dmg:barrel_explosion", "+0.3", "BARREL BOMBER", "");
		AddCombo("Return to Sender", "Skill", "fist", "projectile:reflected", "+1.0", "RETURN TO SENDER", "");
		AddCombo("Drunken Master", "Style", "", "status:intoxicated", "+2.0", "DRUNKEN MASTER", "");
		AddCombo("Overkill", "Gore", "", "dmg:overkill", "+0.1", "OVERKILL", "");
		
		// Monster Type Combos
		AddCombo("Exorcist", "Divine", "", "trait:demonic", "+0.1", "EXORCIST", "");
		AddCombo("Scrap Metal", "Tech", "", "anatomy:robotic", "+0.2", "SCRAP METAL", "");
		AddCombo("Pest Control", "Bio", "", "size:tiny", "+0.05", "PEST CONTROL", "");
	}
	
	void AddCombo(String cname, String ctype, String cklass, String ctrig, String cval, String cflavor, String cgate)
	{
		SDFCombo c = new("SDFCombo");
		c.name = cname;
		c.type = ctype;
		c.klass = cklass;
		c.trig = ctrig;
		c.val = cval;
		c.flavor = cflavor;
		c.gate = cgate;
		combos.Push(c);
	}
	
	override void WorldThingDied(WorldEvent e)
	{
		if (!e.Thing || !e.Thing.bIsMonster || !e.Inflictor) return;
		
		Actor victim = e.Thing;
		Actor inflictor = e.Inflictor; 
		Actor killer = e.DamageSource; 
		
		if (!killer || !killer.player) return; 
		
		// Extract keywords from victim + locational data + hand data
		String fullContext = victim.GetTag() .. "," .. victim.lastHitZone .. "," .. victim.lastHitHand;
		
		Console.Printf("\cj[SDF ARBITER]\c- Evaluating kill: \cc%s\c- (\cy%s\c-)", victim.GetClassName(), fullContext);
		
		// Distance check
		double dist = (killer.Vec3To(victim)).Length();
		
		// Iterate over combos and check conditions
		for (int i = 0; i < combos.Size(); i++)
		{
			SDFCombo c = combos[i];
			bool match = false;
			
			if (c.trig == "any kill") match = true;
			else if (c.trig == "distance < 64" && dist < 64) match = true;
			else if (c.trig == "distance > 512" && dist > 512) match = true;
			else if (c.trig != "")
			{
				// Support multi-variable matching with '+'
				Array<String> subTrigs;
				c.trig.Split(subTrigs, " + ");
				bool allMet = true;
				for (int j = 0; j < subTrigs.Size(); j++)
				{
					if (fullContext.IndexOf(subTrigs[j]) == -1)
					{
						allMet = false;
						break;
					}
				}
				match = allMet;
			}
			
			// Class check
			if (c.klass != "" && inflictor.GetClassName() != c.klass) match = false;

			if (match)
			{
				Console.Printf("\cd>>> COMBO TRIGGERED: \cf%s \c-(%s) : %s", c.name, c.type, c.flavor != "" ? c.flavor : c.val);
				
				// Call the procedural sigil system with the full context
				VRSigilManager.SpawnSigil(victim, fullContext, inflictor.GetTag());
			}
		}
	}
}
