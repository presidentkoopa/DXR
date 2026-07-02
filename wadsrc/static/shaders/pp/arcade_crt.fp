layout(location=0) in vec2 TexCoord;
layout(location=0) out vec4 FragColor;
layout(binding=0) uniform sampler2D SceneTexture;

// Uniforms are injected by the engine

void main()
{
	vec4 scene = texture(SceneTexture, TexCoord);

	// PS1/Arcade style CRT Scanlines
	float scanline = sin(TexCoord.y * Resolution.y * 2.0) * 0.05 + 0.95;
	
	// RGB Chromatic Aberration for bright elements
	vec3 chromAberration;
	chromAberration.r = texture(SceneTexture, TexCoord + vec2(0.003, 0.0)).r;
	chromAberration.g = scene.g;
	chromAberration.b = texture(SceneTexture, TexCoord - vec2(0.003, 0.0)).b;
	
	// Isolate bright parts for overdrive
	float brightness = max(max(chromAberration.r, chromAberration.g), chromAberration.b);
	vec3 overdrive = chromAberration * smoothstep(0.7, 1.0, brightness) * 1.5;

	// Composite
	vec3 outColor = scene.rgb * scanline + overdrive;
	
	// Rolling VHS/CRT noise
	float roll = fract(TexCoord.y - Timer * 0.2);
	if (roll < 0.05) 
	{
		outColor += vec3(0.05) * (1.0 - (roll / 0.05));
	}

	FragColor = vec4(clamp(outColor, 0.0, 1.0), scene.a);
}
