// MSDF Atlas Shader for Animated GIF Entities
// Samples from a Multi-channel Signed Distance Field atlas

float median(float r, float g, float b) {
    return max(min(r, g), min(max(r, g), b));
}

void main() {
    // Basic setup
    vec2 uv = vTexCoord.st;
    
    // Atlas Logic:
    // We assume the atlas is a horizontal strip for now.
    // u_IsMSDF = Frame Index
    // We need to know total frames, let's assume 16 for the prototype 
    // or pass it in. For now, we'll hardcode a 4x4 grid.
    
    float frameIdx = floor(u_IsMSDF);
    vec2 frameCoord = vec2(mod(frameIdx, 4.0), floor(frameIdx / 4.0));
    vec2 atlasUV = (uv + frameCoord) / 4.0;

    // Sample MSDF texture
    vec3 msd = texture(tex, atlasUV).rgb;
    float sd = median(msd.r, msd.g, msd.b);
    
    // Screen-space derivative for sharp edges
    float screenPxDistance = screenPxRange() * (sd - 0.5);
    float opacity = clamp(screenPxDistance + 0.5, 0.0, 1.0);

    // Glitch effect
    float glitch = sin(timer * 50.0) * u_MSDFGlitch;
    vec3 color = u_MSDFColor.rgb;
    
    // Final output
    FragColor = vec4(color, opacity * u_MSDFColor.a * vColor.a);
}
