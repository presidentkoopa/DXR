
class VRHandModel : Actor
{
    Default
    {
        +NOBLOCKMAP
        +NOGRAVITY
        +DONTSPLASH
        +NOTONAUTOMAP
    }
    States
    {
    Spawn:
        VHAN A -1; // Idle
        Stop;
    Grip:
        VHAN B -1; // Grip/Fist
        Stop;
    Climb:
        VHAN C -1; // Climb/Grab
        Stop;
    Point:
        VHAN D -1; // Point
        Stop;
    }
}

class VRFlashModel : Actor
{
    Default
    {
        +NOBLOCKMAP
        +NOGRAVITY
        +DONTSPLASH
        +NOTONAUTOMAP
    }
    States
    {
    Ready:
        VFLA A -1;
        Stop;
    }
}
