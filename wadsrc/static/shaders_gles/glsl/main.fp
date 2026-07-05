
varying vec4 vTexCoord;
varying vec4 vColor;
varying vec4 pixelpos;
varying vec3 glowdist;
varying vec3 gradientdist;
varying vec4 vWorldNormal;
varying vec4 vEyeNormal;

#ifdef NO_CLIPDISTANCE_SUPPORT
varying vec4 ClipDistanceA;
varying vec4 ClipDistanceB;
#endif


struct Material
{
	vec4 Base;
	vec4 Bright;
	vec4 Glow;
	vec3 Normal;
	vec3 Specular;
	float Glossiness;
	float SpecularLevel;
};

vec4 Process(vec4 color);
vec4 ProcessTexel();
Material ProcessMaterial(); // note that this is deprecated. Use SetupMaterial!
void SetupMaterial(inout Material mat);
vec4 ProcessLight(Material mat, vec4 color);
vec3 ProcessMaterialLight(Material material, vec3 color);
vec2 GetTexCoord();

// These get Or'ed into uTextureMode because it only uses its 3 lowermost bits.
//const int TEXF_Brightmap = 0x10000;
//const int TEXF_Detailmap = 0x20000;
//const int TEXF_Glowmap = 0x40000;


//===========================================================================
//
// Color to grayscale
//
//===========================================================================

float grayscale(vec4 color)
{
	return dot(color.rgb, vec3(0.3, 0.56, 0.14));
}

//===========================================================================
//
// Desaturate a color
//
//===========================================================================

vec4 dodesaturate(vec4 texel, float factor)
{
	if (factor != 0.0)
	{
		float gray = grayscale(texel);
		return mix (texel, vec4(gray,gray,gray,texel.a), factor);
	}
	else
	{
		return texel;
	}
}

//===========================================================================
//
// Desaturate a color
//
//===========================================================================

vec4 desaturate(vec4 texel)
{
#if (DEF_DO_DESATURATE == 1)
	return dodesaturate(texel, uDesaturationFactor);
#else
	return texel;
#endif
}

//===========================================================================
//
// Texture tinting code originally from JFDuke but with a few more options
//
//===========================================================================

const int Tex_Blend_Alpha = 1;
const int Tex_Blend_Screen = 2;
const int Tex_Blend_Overlay = 3;
const int Tex_Blend_Hardlight = 4;
 
 vec4 ApplyTextureManipulation(vec4 texel)
 {
	// Step 1: desaturate according to the material's desaturation factor. 
	texel = dodesaturate(texel, uTextureModulateColor.a);
	
	// Step 2: Invert if requested // TODO FIX
	//if ((blendflags & 8) != 0)
	//{
	//	texel.rgb = vec3(1.0 - texel.r, 1.0 - texel.g, 1.0 - texel.b);
	//}
	
	// Step 3: Apply additive color
	texel.rgb += uTextureAddColor.rgb;
	
	// Step 4: Colorization, including gradient if set.
	texel.rgb *= uTextureModulateColor.rgb;
	
	// Before applying the blend the value needs to be clamped to [0..1] range.
	texel.rgb = clamp(texel.rgb, 0.0, 1.0);
	
	// Step 5: Apply a blend. This may just be a translucent overlay or one of the blend modes present in current Build engines.
#if (DEF_BLEND_FLAGS != 0)
	
	vec3 tcol = texel.rgb * 255.0;	// * 255.0 to make it easier to reuse the integer math.
	vec4 tint = uTextureBlendColor * 255.0;

#if (DEF_BLEND_FLAGS == 1)
	
	tcol.b = tcol.b * (1.0 - uTextureBlendColor.a) + tint.b * uTextureBlendColor.a;
	tcol.g = tcol.g * (1.0 - uTextureBlendColor.a) + tint.g * uTextureBlendColor.a;
	tcol.r = tcol.r * (1.0 - uTextureBlendColor.a) + tint.r * uTextureBlendColor.a;

#elif (DEF_BLEND_FLAGS == 2) // Tex_Blend_Screen:
	tcol.b = 255.0 - (((255.0 - tcol.b) * (255.0 - tint.r)) / 256.0);
	tcol.g = 255.0 - (((255.0 - tcol.g) * (255.0 - tint.g)) / 256.0);
	tcol.r = 255.0 - (((255.0 - tcol.r) * (255.0 - tint.b)) / 256.0);

#elif (DEF_BLEND_FLAGS == 3) // Tex_Blend_Overlay:
	
	tcol.b = tcol.b < 128.0? (tcol.b * tint.b) / 128.0 : 255.0 - (((255.0 - tcol.b) * (255.0 - tint.b)) / 128.0);
	tcol.g = tcol.g < 128.0? (tcol.g * tint.g) / 128.0 : 255.0 - (((255.0 - tcol.g) * (255.0 - tint.g)) / 128.0);
	tcol.r = tcol.r < 128.0? (tcol.r * tint.r) / 128.0 : 255.0 - (((255.0 - tcol.r) * (255.0 - tint.r)) / 128.0);

#elif (DEF_BLEND_FLAGS == 4) // Tex_Blend_Hardlight:

	tcol.b = tint.b < 128.0 ? (tcol.b * tint.b) / 128.0 : 255.0 - (((255.0 - tcol.b) * (255.0 - tint.b)) / 128.0);
	tcol.g = tint.g < 128.0 ? (tcol.g * tint.g) / 128.0 : 255.0 - (((255.0 - tcol.g) * (255.0 - tint.g)) / 128.0);
	tcol.r = tint.r < 128.0 ? (tcol.r * tint.r) / 128.0 : 255.0 - (((255.0 - tcol.r) * (255.0 - tint.r)) / 128.0);

#endif
	
	texel.rgb = tcol / 255.0;
	
#endif

	return texel;
}

//===========================================================================
//
// This function is common for all (non-special-effect) fragment shaders
//
//===========================================================================

vec4 getTexel(vec2 st)
{
	vec4 texel = texture2D(tex, st);
	
#if (DEF_TEXTURE_MODE == 1)

	texel.rgb = vec3(1.0,1.0,1.0);
	
#elif (DEF_TEXTURE_MODE == 2)// TM_OPAQUE
	
	texel.a = 1.0;
				
#elif (DEF_TEXTURE_MODE == 3)// TM_INVERSE
	
	texel = vec4(1.0-texel.r, 1.0-texel.b, 1.0-texel.g, texel.a);

#elif (DEF_TEXTURE_MODE == 4)// TM_ALPHATEXTURE

	float gray = grayscale(texel);
	texel = vec4(1.0, 1.0, 1.0, gray*texel.a);
			
#elif (DEF_TEXTURE_MODE == 5)// TM_CLAMPY
			
	if (st.t < 0.0 || st.t > 1.0)
	{
		texel.a = 0.0;
	}
			
#elif (DEF_TEXTURE_MODE == 6)// TM_OPAQUEINVERSE

	texel = vec4(1.0-texel.r, 1.0-texel.b, 1.0-texel.g, 1.0);

			
#elif (DEF_TEXTURE_MODE == 7)//TM_FOGLAYER 
	
	return texel;
	
#endif
	
	// Apply the texture modification colors.
#if (DEF_BLEND_FLAGS != 0)	

	// only apply the texture manipulation if it contains something.
	texel = ApplyTextureManipulation(texel);

#endif

	// Apply the Doom64 style material colors on top of everything from the texture modification settings.
	// This may be a bit redundant in terms of features but the data comes from different sources so this is unavoidable.
	
	texel.rgb += uAddColor.rgb;

#if (DEF_USE_OBJECT_COLOR_2 == 1)
	texel *= mix(uObjectColor, uObjectColor2, gradientdist.z);
#else
	texel *= uObjectColor;
#endif

	// Last but not least apply the desaturation from the sector's light.
	return desaturate(texel);
}




//===========================================================================
//
// Doom software lighting equation
//
//===========================================================================

#define DOOMLIGHTFACTOR 232.0

float R_DoomLightingEquation_OLD(float light)
{
	// z is the depth in view space, positive going into the screen
	float z = pixelpos.w;

	
		/* L in the range 0 to 63 */
	float L = light * 63.0/31.0;

	float min_L = clamp(36.0/31.0 - L, 0.0, 1.0);

	// Fix objects getting totally black when close.
	if (z < 0.0001)
		z = 0.0001;

	float scale = 1.0 / z;
	float index = (59.0/31.0 - L) - (scale * DOOMLIGHTFACTOR/31.0 - DOOMLIGHTFACTOR/31.0);

	// Result is the normalized colormap index (0 bright .. 1 dark)
	return clamp(index, min_L, 1.0) / 32.0;
}


//===========================================================================
//
// zdoom colormap equation
//
//===========================================================================
float R_ZDoomColormap(float light, float z)
{
	float L = light * 255.0;
	float vis = min(uGlobVis / z, 24.0 / 32.0);
	float shade = 2.0 - (L + 12.0) / 128.0;
	float lightscale = shade - vis;
	return lightscale * 31.0;
}

//===========================================================================
//
// Doom software lighting equation
//
//===========================================================================
float R_DoomLightingEquation(float light)
{
	// z is the depth in view space, positive going into the screen
	float z;

#if (DEF_FOG_RADIAL == 1)
	z = distance(pixelpos.xyz, uCameraPos.xyz);
#else
	z = pixelpos.w;
#endif

#if (DEF_BUILD_LIGHTING == 1) // gl_lightmode 5: Build software lighting emulation.
	// This is a lot more primitive than Doom's lighting...
	float numShades = float(uPalLightLevels);
	float curshade = (1.0 - light) * (numShades - 1.0);
	float visibility = max(uGlobVis * uLightFactor * abs(z), 0.0);
	float shade = clamp((curshade + visibility), 0.0, numShades - 1.0);
	return clamp(shade * uLightDist, 0.0, 1.0);
#endif

	float colormap = R_ZDoomColormap(light, z); // ONLY Software mode, vanilla not yet working

#if (DEF_BANDED_SW_LIGHTING == 1) 
	colormap = floor(colormap) + 0.5;
#endif

	// Result is the normalized colormap index (0 bright .. 1 dark)
	return clamp(colormap, 0.0, 31.0) / 32.0;
}


float shadowAttenuation(vec4 lightpos, float lightcolorA)
{
	return 1.0;
}


float spotLightAttenuation(vec4 lightpos, vec3 spotdir, float lightCosInnerAngle, float lightCosOuterAngle)
{
	vec3 lightDirection = normalize(lightpos.xyz - pixelpos.xyz);
	float cosDir = dot(lightDirection, spotdir);
	return smoothstep(lightCosOuterAngle, lightCosInnerAngle, cosDir);
}

vec3 ApplyNormalMap(vec2 texcoord)
{
	return normalize(vWorldNormal.xyz);
}

//===========================================================================
//
// Sets the common material properties.
//
//===========================================================================

void SetMaterialProps(inout Material material, vec2 texCoord)
{

#ifdef NPOT_EMULATION

#if (DEF_NPOT_EMULATION == 1)
		float period = floor(texCoord.t / uNpotEmulation.y);
		texCoord.s += uNpotEmulation.x * floor(mod(texCoord.t, uNpotEmulation.y));
		texCoord.t = period + mod(texCoord.t, uNpotEmulation.y);
#endif

#endif

	material.Base = getTexel(texCoord.st);
	material.Normal = ApplyNormalMap(texCoord.st);

	#if (DEF_TEXTURE_FLAGS & 0x1)
		material.Bright = texture2D(brighttexture, texCoord.st);
	#endif

	#if (DEF_TEXTURE_FLAGS & 0x2)
	{
		vec4 Detail = texture2D(detailtexture, texCoord.st * uDetailParms.xy) * uDetailParms.z;
		material.Base *= Detail;
	}
	#endif

	#if (DEF_TEXTURE_FLAGS & 0x4)
	{
		material.Glow = texture2D(glowtexture, texCoord.st);
	}
	#endif

}

//===========================================================================
//
// Calculate light
//
// It is important to note that the light color is not desaturated
// due to ZDoom's implementation weirdness. Everything that's added
// on top of it, e.g. dynamic lights and glows are, though, because
// the objects emitting these lights are also.
//
// This is making this a bit more complicated than it needs to
// because we can't just desaturate the final fragment color.
// 
//===========================================================================

vec4 getLightColor(Material material, float fogdist, float fogfactor)
{
	vec4 color = vColor;
	
#if (DEF_USE_U_LIGHT_LEVEL == 1)
	{
		float newlightlevel = 1.0 - R_DoomLightingEquation(uLightLevel);
		color.rgb *= newlightlevel;
	}
#else
	{

		#if (DEF_FOG_ENABLED == 1) && (DEF_FOG_COLOURED == 0)
		{
			// brightening around the player for light mode 2
			if (fogdist < uLightDist)
			{
				color.rgb *= uLightFactor - (fogdist / uLightDist) * (uLightFactor - 1.0);
			}
		
			//
			// apply light diminishing through fog equation
			//
			color.rgb = mix(vec3(0.0, 0.0, 0.0), color.rgb, fogfactor);
		}
		#endif
	}
#endif	


	//
	// handle glowing walls
	//
#if (DEF_USE_GLOW_TOP_COLOR)	
	if (glowdist.x < uGlowTopColor.a)
	{
		color.rgb += desaturate(uGlowTopColor * (1.0 - glowdist.x / uGlowTopColor.a)).rgb;
	}
#endif


#if (DEF_USE_GLOW_BOTTOM_COLOR)	
	if (glowdist.y < uGlowBottomColor.a)
	{
		color.rgb += desaturate(uGlowBottomColor * (1.0 - glowdist.y / uGlowBottomColor.a)).rgb;
	}
#endif

	//
	// [RADIANCE] up to MAX_WALL_GLOW_SPOTS localized glow pools (radial circles) on floor/ceiling.
	// uWallGlowSpots[i] = vec4(center.x, center.z, packedRGB, radius). Const loop bound (ES2-legal),
	// count is the dynamic early-out; spots uniform is highp so the packed RGB unpacks exactly.
	//
	for (int wgIdx = 0; wgIdx < MAX_WALL_GLOW_SPOTS; wgIdx++)
	{
		if (wgIdx >= uWallGlowSpotCount) break;
		vec4 wgSp = uWallGlowSpots[wgIdx];
		if (wgSp.w > 0.0)
		{
			float wgDist = length(pixelpos.xz - wgSp.xy);
			if (wgDist < wgSp.w)
			{
				float wgPk = wgSp.z;
				vec3 wgCol = vec3(floor(wgPk / 65536.0), floor(mod(wgPk, 65536.0) / 256.0), mod(wgPk, 256.0)) / 255.0;
				vec4 wgMask = uWallGlowMask[wgIdx];
				float wgTypeRaw = wgMask.x;
				float wallPat = floor(wgTypeRaw / 100.0);
				float wgType = wgTypeRaw - wallPat * 100.0;
				vec3 wgAdd = vec3(0.0);
				bool isWall = abs(vWorldNormal.y) < 0.5;
				if (isWall)
				{
					float col = clamp(1.0 - wgDist / wgSp.w, 0.0, 1.0);
					float yy = pixelpos.y;
					float prog = clamp(wgMask.y, 0.0, 1.0);
					float wx = pixelpos.x + pixelpos.z;
					if (wallPat < 0.5)
					{
						float core = col;
						float halo = sqrt(col) * 0.55;
						float breathe = 0.84 + 0.16 * sin(timer * 1.1 + wgSp.x * 0.13);
						float shimmer = 0.92 + 0.08 * sin(yy * 0.05 + timer * 0.7);
						wgAdd = wgCol * ((core * 0.65 + halo) * breathe * shimmer);
					}
					else if (wallPat < 1.5)
					{
						float c2 = col * col;
						float band = abs(fract(yy * 0.035 - prog * 1.6) - 0.5) * 2.0;
						float sl = smoothstep(0.55, 0.95, band);
						wgAdd = (wgCol + vec3(0.08)) * (c2 * (0.25 + 0.75 * sl));
					}
					else if (wallPat < 2.5)
					{
						vec2 gp = vec2(wx, yy) * 0.04;
						vec2 cid = floor(gp);
						vec2 cell = fract(gp) - 0.5;
						float phase = fract(sin(dot(cid, vec2(12.9898, 78.233))) * 43758.5453);
						float ang = timer * 1.6 + phase * 6.2831;
						float ca = cos(ang), sa = sin(ang);
						vec2 rc = mat2(ca, -sa, sa, ca) * cell;
						float sq = max(abs(rc.x), abs(rc.y));
						float block = 1.0 - smoothstep(0.24, 0.34, sq);
						float edge = smoothstep(0.20, 0.30, sq) * (1.0 - smoothstep(0.34, 0.42, sq));
						wgAdd = wgCol * (col * (block * 0.5 + edge));
					}
					else if (wallPat < 3.5)
					{
						float seed = fract(sin(floor(wx * 0.12) * 12.9898 + wgSp.x) * 43758.5453);
						float dr = fract(yy * 0.02 + seed * 2.3 + prog * 0.9);
						float trail = smoothstep(0.0, 0.45, dr) * (1.0 - smoothstep(0.45, 1.0, dr));
						wgAdd = wgCol * (col * trail * 0.9) + vec3(0.5, 0.02, 0.015) * (col * trail * 0.5);
					}
					else if (wallPat < 4.5)
					{
						float seed = fract(sin(floor(wx * 0.12) * 12.9898 + wgSp.x) * 43758.5453);
						float rs = fract(yy * 0.02 - seed * 2.3 - prog * 0.9);
						float trail = smoothstep(0.0, 0.45, rs) * (1.0 - smoothstep(0.45, 1.0, rs));
						wgAdd = (wgCol + vec3(0.25, 0.10, 0.0)) * (col * trail * 0.95);
					}
					else
					{
						float barf = (wgDist / wgSp.w) * 7.0;
						float bar = floor(barf);
						float seed = fract(sin(bar * 7.31 + wgSp.x) * 43758.5453);
						float t1 = fract(timer * 0.9 + seed);
						float env = exp(-t1 * 3.2);
						float pulse = 0.32 + 0.68 * env;
						float band = 1.0 - smoothstep(0.36, 0.50, abs(fract(barf) - 0.5));
						wgAdd = wgCol * (col * pulse * (0.3 + 0.7 * band));
					}
					float wdith = (mod(gl_FragCoord.x, 2.0) * 0.5 + mod(gl_FragCoord.y, 2.0) * 0.25 - 0.375) * (1.7 / 255.0);
					wgAdd += vec3(wdith);
				}
				else
				{
				if (wgType > 12.5)
				{
					vec2 nrel = pixelpos.xz - wgSp.xy;
					float nasp = max(length(wgMask.zw), 0.001);
					vec2 nudir = wgMask.zw / nasp;
					float nhH = wgSp.w / sqrt(1.0 + nasp * nasp);
					float nhW = nasp * nhH;
					float nAX = dot(nrel, nudir);
					float nAY = dot(nrel, vec2(-nudir.y, nudir.x));
					float nProg = max(wgMask.y, 0.05);
					float nBox = length(vec2(abs(nAX) / nhW, abs(nAY) / (nProg * nhH)));
					float nborder = smoothstep(0.80, 0.93, nBox) * (1.0 - smoothstep(0.99, 1.12, nBox));
					float nfill = (1.0 - smoothstep(0.88, 1.00, nBox));
					float nenc = wgPk;
					float nnum = mod(nenc, 131072.0);
					float ncidx = floor(nenc / 131072.0);
					vec3 nbc = (ncidx < 0.5) ? vec3(0.0, 0.8, 1.0) : (ncidx < 1.5) ? vec3(1.0, 0.78, 0.16) : (ncidx < 2.5) ? vec3(1.0, 0.22, 0.16) : vec3(0.55, 1.0, 0.5);
					wgAdd = nbc * (nfill * 0.55 + nborder * 0.6);
					if (nProg > 0.55)
					{
						float nlen = (nnum < 10.0) ? 1.0 : (nnum < 100.0) ? 2.0 : (nnum < 1000.0) ? 3.0 : (nnum < 10000.0) ? 4.0 : 5.0;
						float nx = nAX / (nhW * 0.82);
						float ny = nAY / (nhH * 0.60);
						if (abs(nx) < 1.0 && abs(ny) < 1.0)
						{
							float u = (nx * 0.5 + 0.5) * nlen;
							float di = clamp(floor(u), 0.0, nlen - 1.0);
							float dx = (u - di) * 2.0 - 1.0;
							float dy = ny;
							float dv = mod(floor(nnum / pow(10.0, nlen - 1.0 - di)), 10.0);
							float m; if (dv < 0.5) m = 63.0; else if (dv < 1.5) m = 6.0; else if (dv < 2.5) m = 91.0; else if (dv < 3.5) m = 79.0; else if (dv < 4.5) m = 102.0; else if (dv < 5.5) m = 109.0; else if (dv < 6.5) m = 125.0; else if (dv < 7.5) m = 7.0; else if (dv < 8.5) m = 127.0; else m = 111.0;
							float th = 0.17, sl = 0.55;
							float lit = 0.0;
							lit = max(lit, mod(floor(m / 1.0),  2.0) * step(abs(dy - 0.72), th) * step(abs(dx), sl));
							lit = max(lit, mod(floor(m / 8.0),  2.0) * step(abs(dy + 0.72), th) * step(abs(dx), sl));
							lit = max(lit, mod(floor(m / 64.0), 2.0) * step(abs(dy), th) * step(abs(dx), sl));
							lit = max(lit, mod(floor(m / 32.0), 2.0) * step(abs(dx + 0.52), th) * step(abs(dy - 0.36), 0.36 + th));
							lit = max(lit, mod(floor(m / 2.0),  2.0) * step(abs(dx - 0.52), th) * step(abs(dy - 0.36), 0.36 + th));
							lit = max(lit, mod(floor(m / 16.0), 2.0) * step(abs(dx + 0.52), th) * step(abs(dy + 0.36), 0.36 + th));
							lit = max(lit, mod(floor(m / 4.0),  2.0) * step(abs(dx - 0.52), th) * step(abs(dy + 0.36), 0.36 + th));
							wgAdd = mix(wgAdd, vec3(0.0), lit * nfill);
						}
					}
				}
				else if (wgType > 11.5)
				{
					vec2 lrel = pixelpos.xz - wgSp.xy;
					float lasp = max(length(wgMask.zw), 0.001);
					vec2 ludir = wgMask.zw / lasp;
					float lhH = wgSp.w / sqrt(1.0 + lasp * lasp);
					float lhW = lasp * lhH;
					float lAX = abs(dot(lrel, ludir));
					float lAY = abs(dot(lrel, vec2(-ludir.y, ludir.x)));
					float lProg = max(wgMask.y, 0.05);
					float lBox = max(lAX / lhW, lAY / (lProg * lhH));
					float fillv = smoothstep(1.00, 0.90, lBox);
					float lborder = smoothstep(0.80, 0.94, lBox) * (1.0 - smoothstep(0.97, 1.06, lBox));
					wgAdd = wgCol * (fillv * 0.45) + (wgCol + vec3(0.35)) * lborder;
				}
				else if (wgType > 10.5)
				{
					float strg = clamp(wgMask.y, 0.0, 1.0);
					vec3 inv = clamp(vec3(1.0) - color.rgb, 0.0, 1.0);
					float core = 1.0 - smoothstep(wgSp.w * 0.60, wgSp.w * 0.90, wgDist);
					color.rgb = mix(color.rgb, inv, core * strg);
					float rim = 1.0 - smoothstep(0.0, wgSp.w * 0.08, abs(wgDist - wgSp.w * 0.84));
					color.rgb += inv * (rim * strg * 0.7);
				}
				else if (wgType > 9.5)
				{
					vec2 rel = pixelpos.xz - wgSp.xy;
					float cellS = wgSp.w * 0.18;
					vec2 g = rel / cellS;
					vec2 gc = floor(g);
					vec2 gf = fract(g) - 0.5;
					float cellDist = length(gc * cellS);
					float wave = wgMask.y * wgSp.w * 1.3;
					float fp = (wave - cellDist) / (wgSp.w * 0.25);
					if (fp > 0.0)
					{
						float checker = mod(gc.x + gc.y, 2.0);
						float cell = 1.0 - smoothstep(0.35, 0.48, max(abs(gf.x), abs(gf.y)));
						float fl = max(0.0, 1.0 - abs(clamp(fp, 0.0, 1.0) - 0.5) * 2.0);
						float a = min(1.0, fp * 0.9);
						wgAdd = (wgCol * (cell * (0.25 + 0.5 * checker)) + vec3(fl * 0.5) * cell) * a;
					}
				}
				else if (wgType > 8.5)
				{
					vec2 rel = (pixelpos.xz - wgSp.xy) / wgSp.w;
					float prog = wgMask.y;
					float r = length(rel);
					float front = prog * 1.1;
					if (r < front && r > 0.02)
					{
						float ang = atan(rel.y, rel.x) + prog * 1.2;
						float spk = abs(fract(ang / 6.2831853 * 12.0) - 0.5) * 2.0;
						float sm = smoothstep(0.6, 0.95, spk);
						float fade = (1.0 - smoothstep(front - 0.1, front, r)) * (1.0 - r * 0.3);
						float a = (prog < 0.8) ? 1.0 : (1.0 - (prog - 0.8) / 0.2);
						wgAdd = (wgCol + vec3(0.15)) * (sm * fade * a);
					}
				}
				else if (wgType > 7.5)
				{
					vec2 rel = (pixelpos.xz - wgSp.xy) / wgSp.w;
					float prog = wgMask.y;
					float r = length(rel) / max(prog * 1.1, 0.05);
					float ang = atan(rel.y, rel.x) + prog * 0.8;
					float sr = 0.55 + 0.45 * cos(ang * 5.0);
					float a = (prog < 0.85) ? 1.0 : (1.0 - (prog - 0.85) / 0.15);
					if (r < sr)
					{
						float fill = 1.0 - smoothstep(sr - 0.12, sr, r);
						float core = 1.0 - smoothstep(0.0, sr * 0.5, r);
						wgAdd = (wgCol * fill + vec3(core * 0.4)) * a;
					}
				}
				else if (wgType > 6.5)
				{
					vec2 rel = (pixelpos.xz - wgSp.xy) / wgSp.w;
					float prog = wgMask.y;
					float ca = cos(prog * 0.8), sa = sin(prog * 0.8);
					rel = mat2(ca, -sa, sa, ca) * rel;
					float sd = max(abs(rel.x), abs(rel.y));
					float front = prog * 1.15;
					if (sd < front)
					{
						float rings = abs(fract(sd * 7.0 - prog * 9.0) - 0.5) * 2.0;
						float rm = smoothstep(0.78, 1.0, rings);
						float fade = 1.0 - smoothstep(front - 0.12, front, sd);
						float a = (prog < 0.8) ? 1.0 : (1.0 - (prog - 0.8) / 0.2);
						wgAdd = (wgCol + vec3(0.15)) * (rm * fade * a);
					}
				}
				else if (wgType > 5.5)
				{
					vec2 rel = (pixelpos.xz - wgSp.xy) / wgSp.w;
					float rr = length(rel);
					float prog = wgMask.y;
					float front = prog * 1.1;
					if (rr < front)
					{
						float th = atan(rel.y, rel.x) / 6.2831853;
						float spiral = fract(th * 2.0 + rr * 4.0 - prog * 3.0);
						float arm = smoothstep(0.14, 0.0, min(spiral, 1.0 - spiral));
						float fadeS = 1.0 - smoothstep(front - 0.12, front, rr);
						float aS = (prog < 0.8) ? 1.0 : (1.0 - (prog - 0.8) / 0.2);
						wgAdd = (wgCol + vec3(0.18)) * (arm * fadeS * aS);
					}
				}
				else if (wgType > 4.5)
				{
					vec2 rel = (pixelpos.xz - wgSp.xy) / wgSp.w;
					float prog = wgMask.y;
					float ca = cos(prog * 1.5), sa = sin(prog * 1.5);
					rel = mat2(ca, -sa, sa, ca) * rel;
					float hd = max(dot(abs(rel), vec2(0.8660254, 0.5)), abs(rel).x);
					float front = prog * 1.15;
					if (hd < front)
					{
						float rings = abs(fract(hd * 7.0 - prog * 9.0) - 0.5) * 2.0;
						float ringMask = smoothstep(0.78, 1.0, rings);
						float fadeR = 1.0 - smoothstep(front - 0.12, front, hd);
						float aR = (prog < 0.8) ? 1.0 : (1.0 - (prog - 0.8) / 0.2);
						wgAdd = (wgCol + vec3(0.15)) * (ringMask * fadeR * aR);
					}
				}
				else if (wgType > 3.5)
				{
					vec2 rel = pixelpos.xz - wgSp.xy;
					float cellS = wgSp.w * 0.16;
					vec2 hp = rel / cellS;
					vec2 hgs = vec2(1.0, 1.7320508);
					vec4 hC = floor(vec4(hp, hp - vec2(0.5, 1.0)) / hgs.xyxy) + 0.5;
					vec4 hh = vec4(hp - hC.xy * hgs, hp - (hC.zw + vec2(0.5)) * hgs);
					bool firstH = dot(hh.xy, hh.xy) < dot(hh.zw, hh.zw);
					vec2 lp = firstH ? hh.xy : hh.zw;
					vec2 cid = firstH ? hC.xy : hC.zw + vec2(0.5);
					float cellDist = length(cid * hgs * cellS);
					float wave = wgMask.y * wgSp.w * 1.25;
					float fp = (wave - cellDist) / (wgSp.w * 0.22);
					if (fp > 0.0)
					{
						float flip = clamp(fp, 0.0, 1.0);
						float squash = max(0.12, abs(cos(flip * 3.14159265)));
						vec2 sp2 = vec2(lp.x, lp.y / squash);
						float hd = max(dot(abs(sp2), vec2(0.8660254, 0.5)), abs(sp2).x);
						float fill = 1.0 - smoothstep(0.34, 0.46, hd);
						float edge = smoothstep(0.30, 0.46, hd) * (1.0 - smoothstep(0.46, 0.54, hd));
						float flashH = 1.0 - abs(flip - 0.5) * 2.0;
						float aH = min(1.0, fp * 0.9);
						wgAdd = (wgCol * (fill * 0.35) + (wgCol * 0.6 + vec3(flashH * 0.8)) * edge) * aH;
					}
				}
				else if (wgType > 2.5)
				{
					float ringR = wgMask.y * wgSp.w;
					float thick = wgSp.w * 0.10;
					wgAdd = wgCol * (1.0 - smoothstep(0.0, thick, abs(wgDist - ringR)));
				}
				else if (wgType > 1.5)
				{
					vec2 wgRel = pixelpos.xz - wgSp.xy;
					float along = dot(wgRel, wgMask.zw);
					float perpS = dot(wgRel, vec2(-wgMask.w, wgMask.z));
					float halfLen = max(wgMask.y, 0.001) * wgSp.w;
					float onB = step(abs(along), halfLen);
					float anB = clamp(abs(along) / halfLen, 0.0, 1.0);
					float taper = 1.0 - anB * anB;
					float sdB = along * 0.045 + wgSp.x * 0.01;
					float siB = floor(sdB), sfB = fract(sdB);
					float h0 = fract(sin(siB * 12.9898) * 43758.5453);
					float h1 = fract(sin((siB + 1.0) * 12.9898) * 43758.5453);
					float wob = mix(h0, h1, sfB * sfB * (3.0 - 2.0 * sfB)) - 0.5;
					float jag = fract(sin(along * 0.9 + wgSp.y) * 43758.5453) - 0.5;
					float wHalf = wgSp.w * 0.06 * taper + 0.001;
					float centerB = wob * wHalf * 1.6;
					float wj = max(wHalf * (0.7 + 0.55 * jag), 0.001);
					float pj = abs(perpS - centerB);
					float bodyB = (1.0 - smoothstep(wj * 0.45, wj, pj)) * onB;
					float coreB = (1.0 - smoothstep(0.0, wj * 0.4, pj)) * onB;
					float scratch = 0.55 + 0.45 * smoothstep(0.1, 0.4, fract(sin(floor(along * 0.3) * 7.31 + wgSp.x) * 43758.5453));
					float haloB = (1.0 - smoothstep(wj, wj * 2.8, pj)) * onB;
					haloB *= (0.35 + 0.65 * fract(sin(along * 1.27 + wgSp.y * 2.3) * 43758.5453));
					float bleedB = max(haloB - bodyB, 0.0);
					wgAdd = (wgCol * bodyB + vec3(coreB * 0.7)) * scratch + vec3(0.5, 0.02, 0.015) * (bleedB * 0.85);
				}
				else if (wgType > 0.5)
				{
					vec2 wgRel = pixelpos.xz - wgSp.xy;
					float wgAX = abs(dot(wgRel, wgMask.zw));
					float wgAY = abs(dot(wgRel, vec2(-wgMask.w, wgMask.z)));
					float wgHHalf = wgSp.w * 0.62;
					float wgWHalf = wgSp.w * 0.30;
					float wgProg = max(wgMask.y, 0.05);
					float wgBox = max(wgAX / wgHHalf, wgAY / (wgProg * wgWHalf));
					wgAdd = wgCol * smoothstep(1.00, 0.94, wgBox);
				}
				else
				{
					wgAdd = wgCol * (1.0 - wgDist / wgSp.w);
				}
				}
				color.rgb += desaturate(vec4(wgAdd, 1.0)).rgb;
			}
		}
	}

	color = min(color, 1.0);

	// these cannot be safely applied by the legacy format where the implementation cannot guarantee that the values are set.
#ifndef LEGACY_USER_SHADER
	//
	// apply glow 
	//
	color.rgb = mix(color.rgb, material.Glow.rgb, material.Glow.a);

	//
	// apply brightmaps 
	//
	color.rgb = min(color.rgb + material.Bright.rgb, 1.0);
#endif
	
	//
	// apply other light manipulation by custom shaders, default is a NOP.
	//
	color = ProcessLight(material, color);

	//
	// apply dynamic lights
	//
	return vec4(ProcessMaterialLight(material, color.rgb), material.Base.a * vColor.a);
}

//===========================================================================
//
// Applies colored fog
//
//===========================================================================

vec4 applyFog(vec4 frag, float fogfactor)
{
	return vec4(mix(uFogColor.rgb, frag.rgb, fogfactor), frag.a);
}

//===========================================================================
//
// Main shader routine
//
//===========================================================================

void main()
{

	//if (ClipDistanceA.x < 0.0 || ClipDistanceA.y < 0.0 || ClipDistanceA.z < 0.0 || ClipDistanceA.w < 0.0 || ClipDistanceB.x < 0.0) discard;

#ifndef LEGACY_USER_SHADER
	Material material;
	
	material.Base = vec4(0.0);
	material.Bright = vec4(0.0);
	material.Glow = vec4(0.0);
	material.Normal = vec3(0.0);
	material.Specular = vec3(0.0);
	material.Glossiness = 0.0;
	material.SpecularLevel = 0.0;
	SetupMaterial(material);
#else
	Material material = ProcessMaterial();
#endif
	vec4 frag = material.Base;

#ifndef NO_ALPHATEST
	if (frag.a <= uAlphaThreshold) discard;
#endif

#ifdef DITHERTRANS
	int index = (int(pixelpos.x) % 2) * 2 + int(pixelpos.y) % 2;
	if (index != 2) discard;
#endif

	#if (DEF_FOG_2D == 0)	// check for special 2D 'fog' mode.
	{
		float fogdist = 0.0;
		float fogfactor = 0.0;
		
		//
		// calculate fog factor
		//
		#if (DEF_FOG_ENABLED == 1)
		{
			#if (DEF_FOG_RADIAL == 0)
				fogdist = max(16.0, pixelpos.w);
			#else
				fogdist = max(16.0, distance(pixelpos.xyz, uCameraPos.xyz));
			#endif

			fogfactor = exp2 (uFogDensity * fogdist);
		}
		#endif

		#if (DEF_TEXTURE_MODE != 7)
		{
			frag = getLightColor(material, fogdist, fogfactor);

			//
			// colored fog
			//
			#if (DEF_FOG_ENABLED == 1) && (DEF_FOG_COLOURED == 1)
			{
				frag = applyFog(frag, fogfactor);
			}
			#endif
		}
		#else
		{
			frag = vec4(uFogColor.rgb, (1.0 - fogfactor) * frag.a * 0.75 * vColor.a);
		}
		#endif
	}	
	#else
	{
		#if (DEF_TEXTURE_MODE == 7)
		{
			float gray = grayscale(frag);
			vec4 cm = (uObjectColor + gray * (uAddColor - uObjectColor)) * 2.0;
			frag = vec4(clamp(cm.rgb, 0.0, 1.0), frag.a);
		}		
		#endif
	
		frag = frag * ProcessLight(material, vColor);
		frag.rgb = frag.rgb + uFogColor.rgb;
	}
	#endif  // (DEF_2D_FOG == 0)
	
#if (DEF_USE_COLOR_MAP == 1) // This mostly works but doesn't look great because of the blending.
	{
		frag.rgb = clamp(pow(frag.rgb, vec3(uFixedColormapStart.a)), 0.0, 1.0);
		if (uFixedColormapRange.a == 0.0)
		{
			float gray = (frag.r * 0.3 + frag.g * 0.56 + frag.b * 0.14);	
			vec4 cm = uFixedColormapStart + gray * uFixedColormapRange;
			frag.rgb = clamp(cm.rgb, 0.0, 1.0);
		} 
	}
#endif

	gl_FragColor = frag;

	//gl_FragColor = vec4(0.8, 0.2, 0.5, 1);

}
