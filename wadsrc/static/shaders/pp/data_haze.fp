layout(location=0) in vec2 TexCoord;
layout(location=0) out vec4 FragColor;
layout(binding=0) uniform sampler2D SceneTexture;
layout(binding=1) uniform sampler2D DepthTexture;

// Uniforms are injected by the engine

void main()
{
	vec4 scene = texture(SceneTexture, TexCoord);
	float rawDepth = texture(DepthTexture, TexCoord).r;

	// Simple heuristic depth
	float depth = pow(rawDepth, 8.0); // push it back

	// Screen-space UNCHAINED volumetric digital haze
	// We'll march 16 steps into the screen
	int steps = 16;
	float stepSize = 1.0 / float(steps);
	
	float accumulatedHaze = 0.0;
	vec2 marchUV = TexCoord;
	
	for (int i = 0; i < steps; ++i)
	{
		float currentDepth = float(i) * stepSize;
		if (currentDepth > depth) break;
		
		// 3D pseudo-noise based on UV and Depth step
		vec3 noisePos = vec3(marchUV * 10.0, currentDepth * 5.0 - Timer);
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
