
// Generative SDF Sigil Shader for HackFraud VR
// Procedurally generates "Math Art" based on keyword hashes

float circleSDF(vec2 p, float r) {
    return length(p) - r;
}

float boxSDF(vec2 p, vec2 b) {
    vec2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float hexSDF(vec2 p, float r) {
    const vec3 k = vec3(-0.866025404, 0.5, 0.577350269);
    p = abs(p);
    p -= 2.0 * min(dot(k.xy, p), 0.0) * k.xy;
    p -= vec2(clamp(p.x, -k.z * r, k.z * r), r);
    return length(p) * sign(p.y);
}

float starSDF(vec2 p, float r, int n, float m) {
    float an = 3.141593 / float(n);
    float en = 3.141593 / m;
    vec2 acs = vec2(cos(an), sin(an));
    vec2 ecs = vec2(cos(en), sin(en));
    float bn = mod(atan(p.x, p.y), 2.0 * an) - an;
    p = length(p) * vec2(cos(bn), abs(sin(bn)));
    p -= r * acs;
    p += ecs * clamp(-dot(p, ecs), 0.0, r * acs.y / ecs.y);
    return length(p) * sign(p.x);
}

// Graveyard Primitives
float slabSDF(vec2 p, vec2 sz, float r) {
    p.y += sz.y * 0.5;
    vec2 d = abs(p - vec2(0.0, sz.y * 0.5)) - (sz * 0.5 - r);
    float box = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
    float arch = length(p - vec2(0.0, sz.y - r)) - r - sz.x * 0.5 + r;
    return max(box, arch);
}

float obeliskSDF(vec2 p, vec2 sz) {
    p.x = abs(p.x);
    float taper = mix(sz.x, sz.x * 0.4, clamp((p.y + sz.y*0.5) / sz.y, 0.0, 1.0));
    float d = p.x - taper;
    return max(d, abs(p.y) - sz.y * 0.5);
}

// Material shader: must return ProcessTexel(), not define main() (main.fp already has main()).
vec4 ProcessTexel() {
    vec2 uv = vTexCoord.st * 2.0 - 1.0;

    // u_IsMSDF is our "Visual Hash"
    // u_MSDFGlitch is "Complexity"
    // u_MSDFColor is Color
    
    int hash = int(u_IsMSDF);
    float complexity = u_MSDFGlitch; // 0.0 to 1.0
    vec3 color = u_MSDFColor.rgb;
    
    float d = 1e10;

    // [XR] Gravity path TILE (Bit 9 / 512): a solid flat rectangle, inset slightly
    // from the tile's actor bounds so adjacent tiles show a visible seam where they
    // abut -- a paved walkway of discrete panels, NOT a blended ribbon/tube. Each
    // tile is its own independent rectangle; connection is physical (edges touch),
    // not a shader-side union. u_MSDFGlitch (complexity) controls the inset/seam width.
    if ((hash & 512) != 0)
    {
        float inset = clamp(complexity, 0.02, 0.25);
        d = boxSDF(uv, vec2(1.0 - inset));
    }
    // Check for Graveyard Marker Type (Bit 8)
    else if ((hash & 256) != 0)
    {
        // Graveyard Logic
        int type = (hash >> 4) & 3;
        if (type == 0) d = slabSDF(uv, vec2(0.8, 1.2), 0.2);
        else if (type == 1) d = obeliskSDF(uv, vec2(0.6, 1.4));
        else if (type == 2) {
            float a = timer * 1.5;
            mat2 m = mat2(cos(a), -sin(a), sin(a), cos(a));
            d = min(boxSDF(m * uv, vec2(0.8, 0.1)), boxSDF(m * vec2(-uv.y, uv.x), vec2(0.1, 0.8)));
        }
        else d = boxSDF(uv, vec2(0.6, 0.9));

        // Holographic Etching (Scanlines)
        float scan = sin(uv.y * 40.0 - timer * 10.0) * 0.5 + 0.5;
        if (scan > 0.8) color *= 2.0;
        
        // Digital Noise / Glitch
        float glitch = fract(sin(timer * 20.0 + floor(uv.y * 10.0)) * 437.0);
        if (glitch > 0.95) uv.x += 0.1 * complexity;
    }
    else
    {
        // Original Sigil Logic
        int primary = hash & 7;
        if (primary == 0) d = circleSDF(uv, 0.5);
        else if (primary == 1) d = boxSDF(uv, vec2(0.5));
        else if (primary == 2) d = hexSDF(uv, 0.5);
        else if (primary == 3) d = starSDF(uv, 0.5, 5, 3.0);
        else d = circleSDF(uv, 0.4);

        // Complexity Layers (Rings/Sub-shapes)
        if (complexity > 0.2) {
            float d2 = abs(circleSDF(uv, 0.6 + sin(timer) * 0.05)) - 0.02;
            d = min(d, d2);
        }
        if (complexity > 0.5) {
            float angle = timer * 2.0;
            mat2 rot = mat2(cos(angle), -sin(angle), sin(angle), cos(angle));
            float d3 = boxSDF(rot * uv, vec2(0.7, 0.02));
            float d4 = boxSDF(rot * uv, vec2(0.02, 0.7));
            d = min(d, min(d3, d4));
        }
    }
    
    // Glitch/Noise based on hash
    float noise = fract(sin(dot(uv + timer, vec2(12.9898, 78.233))) * 43758.5453);
    if (noise < complexity * 0.1) {
        uv.x += 0.05;
        color = vec3(1.0) - color; // Invert colors randomly
    }

    float alpha = smoothstep(0.02, 0.0, d);
    
    // Glow
    float glow = exp(-5.0 * abs(d));
    
    return vec4(color * (alpha + glow * 0.5), (alpha + glow * 0.3) * vColor.a * u_MSDFColor.a);
}
