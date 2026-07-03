class VRBlackoutHandler : StaticEventHandler
{
    override void WorldTick()
    {
        // BODY NEUTERED (VM-abort fix): this used to compute blackout/preset/ambient/contrast from
        // CVars and feed them to Shader.SetUniform calls -- but those calls were already disabled (they
        // used an invalid 3-arg form and targeted a Sprite material shader the post-process API can't
        // drive). With nothing consuming the values, the only thing this did was ABORT THE VM EVERY TICK:
        // vr_radiance_preset / vr_radiance_ambient / vr_radiance_contrast are not declared anywhere, so
        // CVar.GetCVar(...) returned null and the chained .GetInt()/.GetFloat() read address zero, which
        // froze the game at the "report this VM abort" screen the instant a map started. Left empty until
        // the blackout/radiance effect is rebuilt with real material-shader uniform plumbing.
    }
}
