void main()
{
    vec2 uv = TexCoord;
    
    // Scanline position (0.0 to 1.0, top to bottom)
    // scanline_pos is passed as a uniform from ZScript
    float scanline = scanline_pos;
    
    if (uv.y > scanline) {
        // Wireframe / Grid area
        vec2 gridUV = uv * vec2(120.0, 120.0 * (ScreenSize.y / ScreenSize.x));
        float grid = 0.0;
        if (fract(gridUV.x) < 0.08 || fract(gridUV.y) < 0.08) grid = 0.5;
        
        // Add a slight green tint to the "void"
        vec4 color = vec4(0.0, 0.1, 0.0, 1.0);
        color += vec4(0.0, 0.6, 0.2, 1.0) * grid;
        
        // Blue "flicker" at the scanline edge
        float dist = abs(uv.y - scanline);
        if (dist < 0.005) {
            color += vec4(0.5, 0.8, 1.0, 1.0) * (1.0 - dist/0.005);
        }
        
        FragColor = color;
    } else {
        // Compiled area
        vec4 scene = texture(InputTexture, uv);
        
        // Brief white flash exactly at the scanline
        float dist = abs(uv.y - scanline);
        if (dist < 0.002) {
            scene = mix(scene, vec4(1.0, 1.0, 1.0, 1.0), 1.0 - dist/0.002);
        }
        
        FragColor = scene;
    }
}
