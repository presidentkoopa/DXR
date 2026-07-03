// u_BlackoutMode/u_NeonThickness/u_NeonThreshold/u_NeonGlow/u_NeonPulseSpeed/u_NeonColorA/
// u_NeonColorB are StreamData fields (hw_renderstate.h), resolved via #define aliases in the
// shared shader prelude -- same pattern as u_IsMSDF/u_MSDFColor in vr_damage_sdf.fp/msdf_atlas.fp.
// Do NOT redeclare them as loose "uniform" here (that's what left them permanently unfed before --
// no ZScript/PostProcess API can reach a Sprite material shader's loose uniforms).
//
// Material shader: must return ProcessTexel(), not define main() (main.fp already has main()).
vec4 ProcessTexel() {
    if (u_BlackoutMode < 0.5) {
        return texture(tex, vTexCoord.st) * vColor;
    }

    vec2 size = vec2(textureSize(tex, 0));
    vec2 uv = vTexCoord.st;
    
    // Use u_NeonThickness to scale the sample offset
    vec2 off = u_NeonThickness / size;

    // Sobel kernels
    float a[9];
    float l[9];
    
    for(int j = -1; j <= 1; j++) {
        for(int i = -1; i <= 1; i++) {
            vec4 col = texture(tex, uv + off * vec2(i, j));
            int idx = (j + 1) * 3 + (i + 1);
            a[idx] = col.a;
            l[idx] = dot(col.rgb, vec3(0.299, 0.587, 0.114));
        }
    }

    float sXA = a[0] + 2.0*a[3] + a[6] - a[2] - 2.0*a[5] - a[8];
    float sYA = a[0] + 2.0*a[1] + a[2] - a[6] - 2.0*a[7] - a[8];
    float edgeA = sqrt(sXA*sXA + sYA*sYA);

    float sXL = l[0] + 2.0*l[3] + l[6] - l[2] - 2.0*l[5] - l[8];
    float sYL = l[0] + 2.0*l[1] + l[2] - l[6] - 2.0*l[7] - l[8];
    float edgeL = sqrt(sXL*sXL + sYL*sYL);

    // Use u_NeonThreshold for edge sensitivity
    float edge = max(edgeA, edgeL * 0.8);
    edge = smoothstep(u_NeonThreshold, u_NeonThreshold + 0.4, edge);

    // Use pulsing colors and speed
    float pulse = sin(timer * u_NeonPulseSpeed) * 0.5 + 0.5;
    vec3 neonColor = mix(u_NeonColorA, u_NeonColorB, pulse);

    // Use u_NeonGlow for glow intensity
    float glow = exp(-2.0 * (1.0 - edge)) * u_NeonGlow;
    
    return vec4(neonColor * (edge * 2.0 + glow), edge * vColor.a);
}
