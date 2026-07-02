void main()
{
    vec2 uv = TexCoord;
    
    // Glitch distortion
    float glitchTime = timer * 10.0;
    float noise = fract(sin(dot(vec2(floor(uv.y * 20.0), glitchTime), vec2(12.9898, 78.233))) * 43758.5453);
    
    if (noise > 0.8) {
        uv.x += (noise - 0.9) * 0.1;
    }
    
    vec4 scene = texture(InputTexture, uv);
    
    // RGB Split
    float split = 0.01 * u_FatalStrength;
    scene.r = texture(InputTexture, uv + vec2(split, 0.0)).r;
    scene.b = texture(InputTexture, uv - vec2(split, 0.0)).b;
    
    // Tint towards "Blue Screen"
    vec4 bsood = vec4(0.0, 0.2, 0.8, 1.0);
    scene = mix(scene, bsood, u_FatalStrength * 0.5);
    
    // Scanlines
    float scan = sin(uv.y * 800.0) * 0.1;
    scene.rgb -= scan;
    
    FragColor = scene;
}
