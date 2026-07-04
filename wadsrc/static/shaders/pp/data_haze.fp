layout(location=0) in vec2 TexCoord;
layout(location=0) out vec4 FragColor;
layout(binding=0) uniform sampler2D SceneTexture;
layout(binding=1) uniform sampler2D DepthTexture;

// Uniforms are injected by the engine (Timer, Density, plus the LinearizeDepth*/InverseDepthRange*
// reflected fields on DataHazeUniforms -- same names/values the SSAO LinearDepth pass uses).

float normalizeDepth(float depth)
{
	float normalizedDepth = clamp(InverseDepthRangeA * depth + InverseDepthRangeB, 0.0, 1.0);
	return 1.0 / (normalizedDepth * LinearizeDepthA + LinearizeDepthB);
}

void main()
{
	vec4 scene = texture(SceneTexture, TexCoord);
	float rawDepth = texture(DepthTexture, TexCoord).r;

	// Real linear distance in map units to the surface under this pixel (was previously
	// pow(rawDepth, 8.0), a naive heuristic on the raw non-linear hardware depth that collapsed
	// to ~0 for anything but very distant geometry -- the haze never accumulated in ordinary
	// close-quarters corridors, only when looking into open vistas/skyboxes).
	float linDist = normalizeDepth(rawDepth);

	// March a fixed number of map-unit-sized steps out to maxRange. Close geometry means the
	// march breaks early (little haze close up, as intended); long sightlines let it run the full
	// 16 steps (thicker haze looking down a long hall or into open space) -- genuinely volumetric
	// and distance-reactive now, instead of only ever triggering near the far clip plane.
	int steps = 16;
	float maxRange = 1024.0;
	float stepSize = maxRange / float(steps);

	float accumulatedHaze = 0.0;
	vec2 marchUV = TexCoord;

	for (int i = 0; i < steps; ++i)
	{
		float currentDist = float(i) * stepSize;
		if (currentDist > linDist) break;

		// 3D pseudo-noise based on UV and march-distance step
		vec3 noisePos = vec3(marchUV * 10.0, currentDist * 0.05 - Timer);
		float noise = fract(sin(dot(noisePos, vec3(12.9898, 78.233, 45.164))) * 43758.5453);

		// Accumulate only if the noise hits a certain threshold (digital structure)
		if (noise > 0.8)
		{
			accumulatedHaze += 0.05 * Density;
		}
	}

	// Matrix green
	vec3 hazeColor = vec3(0.1, 1.0, 0.4);
	
	vec3 finalColor = mix(scene.rgb, hazeColor, clamp(accumulatedHaze, 0.0, 1.0));
	
	FragColor = vec4(finalColor, scene.a);
}
