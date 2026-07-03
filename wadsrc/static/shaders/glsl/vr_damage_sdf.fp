// Standard uniforms are provided via the StreamData block

vec2 segmentSDF(vec2 p, vec2 a, vec2 b) {
    vec2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return vec2(length(pa - ba * h), 0.0);
}

// Simple 7-segment display logic in SDF
float digitSDF(vec2 p, int digit) {
    float d = 1e10;
    // Segments: 0: top, 1: mid, 2: bottom, 3: left-top, 4: right-top, 5: left-bottom, 6: right-bottom
    bool s[7];
    for(int i=0; i<7; i++) s[i] = false;

    if(digit == 0) { s[0]=s[2]=s[3]=s[4]=s[5]=s[6]=true; }
    if(digit == 1) { s[4]=s[6]=true; }
    if(digit == 2) { s[0]=s[1]=s[2]=s[4]=s[5]=true; }
    if(digit == 3) { s[0]=s[1]=s[2]=s[4]=s[6]=true; }
    if(digit == 4) { s[1]=s[3]=s[4]=s[6]=true; }
    if(digit == 5) { s[0]=s[1]=s[2]=s[3]=s[6]=true; }
    if(digit == 6) { s[0]=s[1]=s[2]=s[3]=s[5]=s[6]=true; }
    if(digit == 7) { s[0]=s[4]=s[6]=true; }
    if(digit == 8) { s[0]=s[1]=s[2]=s[3]=s[4]=s[5]=s[6]=true; }
    if(digit == 9) { s[0]=s[1]=s[2]=s[3]=s[4]=s[6]=true; }

    vec2 p0 = vec2(-0.2, 0.4), p1 = vec2(0.2, 0.4); // top
    vec2 p2 = vec2(-0.2, 0.0), p3 = vec2(0.2, 0.0); // mid
    vec2 p4 = vec2(-0.2, -0.4), p5 = vec2(0.2, -0.4); // bot
    
    if(s[0]) d = min(d, segmentSDF(p, p0, p1).x);
    if(s[1]) d = min(d, segmentSDF(p, p2, p3).x);
    if(s[2]) d = min(d, segmentSDF(p, p4, p5).x);
    if(s[3]) d = min(d, segmentSDF(p, p0, p2).x);
    if(s[4]) d = min(d, segmentSDF(p, p1, p3).x);
    if(s[5]) d = min(d, segmentSDF(p, p2, p4).x);
    if(s[6]) d = min(d, segmentSDF(p, p3, p5).x);

    return d;
}

// Material shaders in this engine must define ProcessTexel() -- the engine's main.fp already
// supplies main() and calls this to build the base texel. Defining our own main() here produced
// "'main': function already has a body". Return the texel instead of writing FragColor.
// NOTE: do NOT write the words S-e-t-u-p-M-a-t-e-r-i-a-l / P-r-o-c-e-s-s-M-a-t-e-r-i-a-l in this
// file -- the engine's shader combiner does a naive substring scan for them (gl_shader.cpp:458)
// and, if found, skips injecting the default material setup, causing a link error.
vec4 ProcessTexel() {
    vec2 uv = vTexCoord.st * 2.0 - 1.0;
    uv.x *= 1.5; // Aspect ratio for 3-4 digits

    // Get damage from StreamData (repurposing u_IsMSDF as a value field)
    int dmg = int(u_IsMSDF); 
    
    float d = 1e10;
    
    // Draw digits (up to 3)
    float d1 = digitSDF(uv + vec2(0.5, 0.0), (dmg / 100) % 10);
    float d2 = digitSDF(uv + vec2(0.0, 0.0), (dmg / 10) % 10);
    float d3 = digitSDF(uv - vec2(0.5, 0.0), dmg % 10);
    
    d = min(d, d3);
    if(dmg >= 10) d = min(d, d2);
    if(dmg >= 100) d = min(d, d1);

    // Border (Hexagon)
    float b = max(abs(uv.x) * 0.866 + abs(uv.y) * 0.5, abs(uv.y)) - 0.8;
    float border = smoothstep(0.02, 0.0, abs(b));
    
    // Final Color from StreamData
    vec3 color = u_MSDFColor.rgb;
    float alpha = smoothstep(0.05, 0.0, d) * 0.8 + border;
    
    // Flicker / Glitch from StreamData
    float flicker = sin(timer * 20.0) * u_MSDFGlitch + (1.0 - u_MSDFGlitch);
    
    return vec4(color * flicker, alpha * u_MSDFColor.a * vColor.a);
}
