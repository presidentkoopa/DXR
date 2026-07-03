
class VRTestingPillar : Actor
{
	Default
	{
		Radius 16;
		Height 128;
		+SOLID
		Keywords "climb:CLIMBABLE";
	}
	States
	{
	Spawn:
		POL1 A -1; // Standard pillar sprite
		Stop;
	}
}

class VRTestingGrabbable : Actor
{
	Default
	{
		Radius 16;
		Height 16;
		+SOLID
		+PUSHABLE
		Mass 100;
		Keywords "flags:throwable";
	}
	States
	{
	Spawn:
		BON1 ABCDCB 6; // Blue bottle or something shiny
		Loop;
	}
}

class VRTestingRig : StaticEventHandler
{
	override void WorldLoaded(WorldEvent e)
	{
		if (e.IsSaveGame) return;

		// Only spawn on the dedicated grab-testing map.
		if (level.MapName != "GRABMAP") return;
		
		// Find player start
		for (int i = 0; i < MAXPLAYERS; i++)
		{
			if (!playeringame[i] || players[i].mo == null) continue;
			
			Vector3 pPos = players[i].mo.Pos;
			Vector3 offset = (64, 0, 0);
			
			// Spawn a circle of test items
			for (int j = 0; j < 8; j++)
			{
				double ang = j * 45;
				Vector3 spawnPos = pPos + (cos(ang) * 128, sin(ang) * 128, 0);
				
				if (j % 3 == 0)
					Actor.Spawn("VRTestingPillar", spawnPos);
				else if (j % 3 == 1)
					Actor.Spawn("VRTestingGrabbable", spawnPos);
				else
					Actor.Spawn("HandGrenade", spawnPos);
			}
			
			Console.Printf("VR Testing Rig Spawned around you!");
			break;
		}
	}
}
