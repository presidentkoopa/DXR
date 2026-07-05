

layout(location = 0) in vec4 vTexCoord;
layout(location = 1) in vec4 vColor;
layout(location = 2) in vec4 pixelpos;
layout(location = 3) in vec3 glowdist;
layout(location = 4) in vec3 gradientdist;
layout(location = 5) in vec4 vWorldNormal;
layout(location = 6) in vec4 vEyeNormal;
layout(location = 9) in vec3 vLightmap;
// PS1 affine-warp companion to vTexCoord -- see the matching declaration in main.vp.
layout(location = 10) noperspective in vec4 vTexCoordAffine;

#ifdef NO_CLIPDISTANCE_SUPPORT
layout(location = 7) in vec4 ClipDistanceA;
layout(location = 8) in vec4 ClipDistanceB;
#endif

layout(location=0) out vec4 FragColor;
#ifdef GBUFFER_PASS
layout(location=1) out vec4 FragFog;
layout(location=2) out vec4 FragNormal;
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
	float Metallic;
	float Roughness;
	float AO;
};

vec4 Process(vec4 color);
vec4 ProcessTexel();
Material ProcessMaterial(); // note that this is deprecated. Use SetupMaterial!
void SetupMaterial(inout Material mat);
vec4 ProcessLight(Material mat, vec4 color);
vec3 ProcessMaterialLight(Material material, vec3 color);
vec2 GetTexCoord();

// These get Or'ed into uTextureMode because it only uses its 3 lowermost bits.
const int TEXF_Brightmap = 0x10000;
const int TEXF_Detailmap = 0x20000;
const int TEXF_Glowmap = 0x40000;
const int TEXF_ClampY = 0x80000;

//===========================================================================
//
// RGB to HSV
//
//===========================================================================

vec3 hsv2rgb(vec3 c)
{
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

vec3 rgb2hsv(vec3 c)
{
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));

    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

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
#ifdef SHADER_LITE
	return texel;
#else
	if (factor != 0.0)
	{
		float gray = grayscale(texel);
		return mix (texel, vec4(gray,gray,gray,texel.a), factor);
	}
	else
	{
		return texel;
	}
#endif
}

//===========================================================================
//
// Desaturate a color
//
//===========================================================================

vec4 desaturate(vec4 texel)
{
	return dodesaturate(texel, uDesaturationFactor);
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

 vec4 ApplyTextureManipulation(vec4 texel, int blendflags)
 {
	// Step 1: desaturate according to the material's desaturation factor. 
	texel = dodesaturate(texel, uTextureModulateColor.a);

	// Step 2: Invert if requested
	if ((blendflags & 8) != 0)
	{
		texel.rgb = vec3(1.0 - texel.r, 1.0 - texel.g, 1.0 - texel.b);
	}

	// Step 3: Apply additive color
	texel.rgb += uTextureAddColor.rgb;

	// Step 4: Colorization, including gradient if set.
	texel.rgb *= uTextureModulateColor.rgb;

	// Before applying the blend the value needs to be clamped to [0..1] range.
	texel.rgb = clamp(texel.rgb, 0.0, 1.0);

	// Step 5: Apply a blend. This may just be a translucent overlay or one of the blend modes present in current Build engines.
	if ((blendflags & 7) != 0)
	{
		vec3 tcol = texel.rgb * 255.0;	// * 255.0 to make it easier to reuse the integer math.
		vec4 tint = uTextureBlendColor * 255.0;

		switch (blendflags & 7)
		{
			default:
				tcol.b = tcol.b * (1.0 - uTextureBlendColor.a) + tint.b * uTextureBlendColor.a;
				tcol.g = tcol.g * (1.0 - uTextureBlendColor.a) + tint.g * uTextureBlendColor.a;
				tcol.r = tcol.r * (1.0 - uTextureBlendColor.a) + tint.r * uTextureBlendColor.a;
				break;
			// The following 3 are taken 1:1 from the Build engine
			case Tex_Blend_Screen:
				tcol.b = 255.0 - (((255.0 - tcol.b) * (255.0 - tint.r)) / 256.0);
				tcol.g = 255.0 - (((255.0 - tcol.g) * (255.0 - tint.g)) / 256.0);
				tcol.r = 255.0 - (((255.0 - tcol.r) * (255.0 - tint.b)) / 256.0);
				break;
			case Tex_Blend_Overlay:
				tcol.b = tcol.b < 128.0? (tcol.b * tint.b) / 128.0 : 255.0 - (((255.0 - tcol.b) * (255.0 - tint.b)) / 128.0);
				tcol.g = tcol.g < 128.0? (tcol.g * tint.g) / 128.0 : 255.0 - (((255.0 - tcol.g) * (255.0 - tint.g)) / 128.0);
				tcol.r = tcol.r < 128.0? (tcol.r * tint.r) / 128.0 : 255.0 - (((255.0 - tcol.r) * (255.0 - tint.r)) / 128.0);
				break;
			case Tex_Blend_Hardlight:
				tcol.b = tint.b < 128.0 ? (tcol.b * tint.b) / 128.0 : 255.0 - (((255.0 - tcol.b) * (255.0 - tint.b)) / 128.0);
				tcol.g = tint.g < 128.0 ? (tcol.g * tint.g) / 128.0 : 255.0 - (((255.0 - tcol.g) * (255.0 - tint.g)) / 128.0);
				tcol.r = tint.r < 128.0 ? (tcol.r * tint.r) / 128.0 : 255.0 - (((255.0 - tcol.r) * (255.0 - tint.r)) / 128.0);
				break;
		}
		texel.rgb = tcol / 255.0;
	}
	return texel;
}

//===========================================================================
//
// This function is common for all (non-special-effect) fragment shaders
//
//===========================================================================

vec4 getTexel(vec2 st)
{
	vec4 texel = texture(tex, st);

	//
	// Apply texture modes
	//
	switch (uTextureMode & 0xffff)
	{
		case 1:	// TM_STENCIL
			texel.rgb = vec3(1.0,1.0,1.0);
			break;

		case 2:	// TM_OPAQUE
			texel.a = 1.0;
			break;

		case 3:	// TM_INVERSE
			texel = vec4(1.0-texel.r, 1.0-texel.b, 1.0-texel.g, texel.a);
			break;

		case 4:	// TM_ALPHATEXTURE
		{
			float gray = grayscale(texel);
			texel = vec4(1.0, 1.0, 1.0, gray*texel.a);
			break;
		}

		case 5:	// TM_CLAMPY
			if (st.t < 0.0 || st.t > 1.0)
			{
				texel.a = 0.0;
			}
			break;

		case 6: // TM_OPAQUEINVERSE
			texel = vec4(1.0-texel.r, 1.0-texel.b, 1.0-texel.g, 1.0);
			break;

		case 7: //TM_FOGLAYER 
			return texel;

	}
#ifndef SHADER_LITE
	if ((uTextureMode & TEXF_ClampY) != 0)
	{
		if (st.t < 0.0 || st.t > 1.0)
		{
			texel.a = 0.0;
		}
	}

	// Apply the texture modification colors.
	int blendflags = int(uTextureAddColor.a);	// this alpha is unused otherwise
	if (blendflags != 0)	
	{
		// only apply the texture manipulation if it contains something.
		texel = ApplyTextureManipulation(texel, blendflags);
	}

	// Apply the Doom64 style material colors on top of everything from the texture modification settings.
	// This may be a bit redundant in terms of features but the data comes from different sources so this is unavoidable.
	texel.rgb += uAddColor.rgb;
	if (uObjectColor2.a == 0.0) texel *= uObjectColor;
	else texel *= mix(uObjectColor, uObjectColor2, gradientdist.z);
#else
	texel *= uObjectColor;
#endif
	// Last but not least apply the desaturation from the sector's light.
	return desaturate(texel);
}

//===========================================================================
//
// Vanilla Doom wall colormap equation
//
//===========================================================================
float R_WallColormap(float lightnum, float z, vec3 normal)
{
	// R_ScaleFromGlobalAngle calculation
	float projection = 160.0; // projection depends on SCREENBLOCKS!! 160 is the fullscreen value
	vec2 line_v1 = pixelpos.xz; // in vanilla this is the first curline vertex
	vec2 line_normal = normal.xz;
	float texscale = projection * clamp(dot(normalize(uCameraPos.xz - line_v1), line_normal), 0.0, 1.0) / z;

	float lightz = clamp(16.0 * texscale, 0.0, 47.0);

	// scalelight[lightnum][lightz] lookup
	float startmap = (15.0 - lightnum) * 4.0;
	return startmap - lightz * 0.5;
}

//===========================================================================
//
// Vanilla Doom plane colormap equation
//
//===========================================================================
float R_PlaneColormap(float lightnum, float z)
{
	float lightz = clamp(z / 16.0f, 0.0, 127.0);

	// zlight[lightnum][lightz] lookup
	float startmap = (15.0 - lightnum) * 4.0;
	float scale = 160.0 / (lightz + 1.0);
	return startmap - scale * 0.5;
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

float R_DoomColormap(float light, float z)
{
#ifdef SHADER_LITE
	return R_ZDoomColormap(light, z);
#else
	if ((uPalLightLevels >> 16) == 16) // gl_lightmode 16
	{
		float lightnum = clamp(light * 15.0, 0.0, 15.0);

		if (dot(vWorldNormal.xyz, vWorldNormal.xyz) > 0.5)
		{
			vec3 normal = normalize(vWorldNormal.xyz);
			return mix(R_WallColormap(lightnum, z, normal), R_PlaneColormap(lightnum, z), abs(normal.y));
		}
		else // vWorldNormal is not set on sprites
		{
			return R_PlaneColormap(lightnum, z);
		}
	}
	else
	{
		return R_ZDoomColormap(light, z);
	}
#endif	
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
	if (((uPalLightLevels >> 8)  & 0xff) == 2)
	{
		z = distance(pixelpos.xyz, uCameraPos.xyz);
	}
	else 
	{
		z = pixelpos.w;
	}
#ifndef SHADER_LITE
	if ((uPalLightLevels >> 16) == 5) // gl_lightmode 5: Build software lighting emulation.
	{
		// This is a lot more primitive than Doom's lighting...
		float numShades = float(uPalLightLevels & 255);
		float curshade = (1.0 - light) * (numShades - 1.0);
		float visibility = max(uGlobVis * uLightFactor * z, 0.0);
		float shade = clamp((curshade + visibility), 0.0, numShades - 1.0);
		return clamp(shade * uLightDist, 0.0, 1.0);
	}
#endif
	float colormap = R_DoomColormap(light, z);

	if ((uPalLightLevels & 0xff) != 0)
		colormap = floor(colormap) + 0.5;

	// Result is the normalized colormap index (0 bright .. 1 dark)
	return clamp(colormap, 0.0, 31.0) / 32.0;
}

//===========================================================================
//
// Check if light is in shadow
//
//===========================================================================

#ifdef SUPPORTS_RAYTRACING

bool traceHit(vec3 origin, vec3 direction, float dist)
{
	rayQueryEXT rayQuery;
	rayQueryInitializeEXT(rayQuery, TopLevelAS, gl_RayFlagsTerminateOnFirstHitEXT, 0xFF, origin, 0.01f, direction, dist);
	while(rayQueryProceedEXT(rayQuery)) { }
	return rayQueryGetIntersectionTypeEXT(rayQuery, true) != gl_RayQueryCommittedIntersectionNoneEXT;
}

vec2 softshadow[9 * 3] = vec2[](
	vec2( 0.0, 0.0),
	vec2(-2.0,-2.0),
	vec2( 2.0, 2.0),
	vec2( 2.0,-2.0),
	vec2(-2.0, 2.0),
	vec2(-1.0,-1.0),
	vec2( 1.0, 1.0),
	vec2( 1.0,-1.0),
	vec2(-1.0, 1.0),

	vec2( 0.0, 0.0),
	vec2(-1.5,-1.5),
	vec2( 1.5, 1.5),
	vec2( 1.5,-1.5),
	vec2(-1.5, 1.5),
	vec2(-0.5,-0.5),
	vec2( 0.5, 0.5),
	vec2( 0.5,-0.5),
	vec2(-0.5, 0.5),

	vec2( 0.0, 0.0),
	vec2(-1.25,-1.75),
	vec2( 1.75, 1.25),
	vec2( 1.25,-1.75),
	vec2(-1.75, 1.75),
	vec2(-0.75,-0.25),
	vec2( 0.25, 0.75),
	vec2( 0.75,-0.25),
	vec2(-0.25, 0.75)
);

float shadowAttenuation(vec4 lightpos, float lightcolorA)
{
	float shadowIndex = abs(lightcolorA) - 1.0;
	if (shadowIndex >= 1024.0)
		return 1.0; // Don't cast rays for this light

	vec3 origin = pixelpos.xzy;
	vec3 target = lightpos.xzy + 0.01; // nudge light position slightly as Doom maps tend to have their lights perfectly aligned with planes

	vec3 direction = normalize(target - origin);
	float dist = distance(origin, target);

	if (uShadowmapFilter <= 0)
	{
		return traceHit(origin, direction, dist) ? 0.0 : 1.0;
	}
	else
	{
		vec3 v = (abs(direction.x) > abs(direction.y)) ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
		vec3 xdir = normalize(cross(direction, v));
		vec3 ydir = cross(direction, xdir);

		float sum = 0.0;
		int step_count = uShadowmapFilter * 9;
		for (int i = 0; i <= step_count; i++)
		{
			vec3 pos = target + xdir * softshadow[i].x + ydir * softshadow[i].y;
			sum += traceHit(origin, normalize(pos - origin), dist) ? 0.0 : 1.0;
		}
		return sum / step_count;
	}
}

#else
#ifdef SUPPORTS_SHADOWMAPS

float shadowDirToU(vec2 dir)
{
	if (abs(dir.y) > abs(dir.x))
	{
		float x = dir.x / dir.y * 0.125;
		if (dir.y >= 0.0)
			return 0.125 + x;
		else
			return (0.50 + 0.125) + x;
	}
	else
	{
		float y = dir.y / dir.x * 0.125;
		if (dir.x >= 0.0)
			return (0.25 + 0.125) - y;
		else
			return (0.75 + 0.125) - y;
	}
}

vec2 shadowUToDir(float u)
{
	u *= 4.0;
	vec2 raydir;
	switch (int(u))
	{
	case 0: raydir = vec2(u * 2.0 - 1.0, 1.0); break;
	case 1: raydir = vec2(1.0, 1.0 - (u - 1.0) * 2.0); break;
	case 2: raydir = vec2(1.0 - (u - 2.0) * 2.0, -1.0); break;
	case 3: raydir = vec2(-1.0, (u - 3.0) * 2.0 - 1.0); break;
	}
	return raydir;
}

float sampleShadowmap(vec3 planePoint, float v)
{
	float bias = 1.0;
	float negD = dot(vWorldNormal.xyz, planePoint);

	vec3 ray = planePoint;

	ivec2 isize = textureSize(ShadowMap, 0);
	float scale = float(isize.x) * 0.25;

	// Snap to shadow map texel grid
	if (abs(ray.z) > abs(ray.x))
	{
		ray.y = ray.y / abs(ray.z);
		ray.x = ray.x / abs(ray.z);
		ray.x = (floor((ray.x + 1.0) * 0.5 * scale) + 0.5) / scale * 2.0 - 1.0;
		ray.z = sign(ray.z);
	}
	else
	{
		ray.y = ray.y / abs(ray.x);
		ray.z = ray.z / abs(ray.x);
		ray.z = (floor((ray.z + 1.0) * 0.5 * scale) + 0.5) / scale * 2.0 - 1.0;
		ray.x = sign(ray.x);
	}

	float t = negD / dot(vWorldNormal.xyz, ray) - bias;
	vec2 dir = ray.xz * t;

	float u = shadowDirToU(dir);
	float dist2 = dot(dir, dir);
	return step(dist2, texture(ShadowMap, vec2(u, v)).x);
}

float sampleShadowmapPCF(vec3 planePoint, float v)
{
	float bias = 1.0;
	float negD = dot(vWorldNormal.xyz, planePoint);

	vec3 ray = planePoint;

	if (abs(ray.z) > abs(ray.x))
		ray.y = ray.y / abs(ray.z);
	else
		ray.y = ray.y / abs(ray.x);

	ivec2 isize = textureSize(ShadowMap, 0);
	float scale = float(isize.x);
	float texelPos = floor(shadowDirToU(ray.xz) * scale);

	float sum = 0.0;
	float step_count = float(uShadowmapFilter);

	texelPos -= step_count + 0.5;
	for (float x = -step_count; x <= step_count; x++)
	{
		float u = fract(texelPos / scale);
		vec2 dir = shadowUToDir(u);

		ray.x = dir.x;
		ray.z = dir.y;
		float t = negD / dot(vWorldNormal.xyz, ray) - bias;
		dir = ray.xz * t;

		float dist2 = dot(dir, dir);
		sum += step(dist2, texture(ShadowMap, vec2(u, v)).x);
		texelPos++;
	}
	return sum / (float(uShadowmapFilter) * 2.0 + 1.0);
}

float shadowmapAttenuation(vec4 lightpos, float shadowIndex)
{
	if (shadowIndex >= 1024.0)
		return 1.0; // No shadowmap available for this light

	vec3 planePoint = pixelpos.xyz - lightpos.xyz;
	planePoint += 0.01; // nudge light position slightly as Doom maps tend to have their lights perfectly aligned with planes

	if (dot(planePoint.xz, planePoint.xz) < 1.0)
		return 1.0; // Light is too close

	float v = (shadowIndex + 0.5) / 1024.0;

	if (uShadowmapFilter <= 0)
	{
		return sampleShadowmap(planePoint, v);
	}
	else
	{
		return sampleShadowmapPCF(planePoint, v);
	}
}

float shadowAttenuation(vec4 lightpos, float lightcolorA)
{
	float shadowIndex = abs(lightcolorA) - 1.0;
	return shadowmapAttenuation(lightpos, shadowIndex);
}

#else

float shadowAttenuation(vec4 lightpos, float lightcolorA)
{
	return 1.0;
}

#endif
#endif

float spotLightAttenuation(vec4 lightpos, vec3 spotdir, float lightCosInnerAngle, float lightCosOuterAngle)
{
	vec3 lightDirection = normalize(lightpos.xyz - pixelpos.xyz);
	float cosDir = dot(lightDirection, spotdir);
	return smoothstep(lightCosOuterAngle, lightCosInnerAngle, cosDir);
}

//===========================================================================
//
// Adjust normal vector according to the normal map
//
//===========================================================================

#if defined(NORMALMAP)
mat3 cotangent_frame(vec3 n, vec3 p, vec2 uv)
{
	// get edge vectors of the pixel triangle
	vec3 dp1 = dFdx(p);
	vec3 dp2 = dFdy(p);
	vec2 duv1 = dFdx(uv);
	vec2 duv2 = dFdy(uv);

	// solve the linear system
	vec3 dp2perp = cross(n, dp2); // cross(dp2, n);
	vec3 dp1perp = cross(dp1, n); // cross(n, dp1);
	vec3 t = dp2perp * duv1.x + dp1perp * duv2.x;
	vec3 b = dp2perp * duv1.y + dp1perp * duv2.y;

	// construct a scale-invariant frame
	float invmax = inversesqrt(max(dot(t,t), dot(b,b)));
	return mat3(t * invmax, b * invmax, n);
}

vec3 ApplyNormalMap(vec2 texcoord)
{
	#define WITH_NORMALMAP_UNSIGNED
	#define WITH_NORMALMAP_GREEN_UP
	//#define WITH_NORMALMAP_2CHANNEL

	vec3 interpolatedNormal = normalize(vWorldNormal.xyz);

	vec3 map = texture(normaltexture, texcoord).xyz;
	#if defined(WITH_NORMALMAP_UNSIGNED)
	map = map * 255./127. - 128./127.; // Math so "odd" because 0.5 cannot be precisely described in an unsigned format
	#endif
	#if defined(WITH_NORMALMAP_2CHANNEL)
	map.z = sqrt(1 - dot(map.xy, map.xy));
	#endif
	#if defined(WITH_NORMALMAP_GREEN_UP)
	map.y = -map.y;
	#endif

	mat3 tbn = cotangent_frame(interpolatedNormal, pixelpos.xyz, vTexCoord.st);
	vec3 bumpedNormal = normalize(tbn * map);
	return bumpedNormal;
}
#else
vec3 ApplyNormalMap(vec2 texcoord)
{
	return normalize(vWorldNormal.xyz);
}
#endif

//===========================================================================
//
// PS1 affine texture warp: when enabled, the primary diffuse sample uses the
// noperspective-interpolated coordinate instead of the perspective-correct one. uAffineWarp
// lives in the shared viewpoint uniform block (already used by main.vp), so it needs no
// additional C++ plumbing to read here.
//
//===========================================================================

vec2 GetAffineTexCoord(vec2 perspCoord)
{
	return (uAffineWarp != 0) ? vTexCoordAffine.st : perspCoord;
}

//===========================================================================
//
// Sets the common material properties.
//
//===========================================================================

void SetMaterialProps(inout Material material, vec2 texCoord)
{
#ifdef NPOT_EMULATION
	if (uNpotEmulation.y != 0.0)
	{
		float period = floor(texCoord.t / uNpotEmulation.y);
		texCoord.s += uNpotEmulation.x * floor(mod(texCoord.t, uNpotEmulation.y));
		texCoord.t = period + mod(texCoord.t, uNpotEmulation.y);
	}
#endif	
	material.Base = getTexel(texCoord.st); 
	material.Normal = ApplyNormalMap(texCoord.st);

// OpenGL doesn't care, but Vulkan pukes all over the place if these texture samplings are included in no-texture shaders, even though never called.
#ifndef NO_LAYERS
	if ((uTextureMode & TEXF_Brightmap) != 0)
		material.Bright = desaturate(texture(brighttexture, texCoord.st));

	if ((uTextureMode & TEXF_Detailmap) != 0)
	{
		vec4 Detail = texture(detailtexture, texCoord.st * uDetailParms.xy) * uDetailParms.z;
		material.Base.rgb *= Detail.rgb;
	}

	if ((uTextureMode & TEXF_Glowmap) != 0)
		material.Glow = desaturate(texture(glowtexture, texCoord.st));
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

// ====================== RADIANCE NEON-TUBE DISPLAY HELPERS ======================
// Capsule SDF: unsigned distance from p to the segment a->b centerline.
float radiance_segDist(vec2 p, vec2 a, vec2 b)
{
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
	return length(pa - ba * h);
}
// Fold one segment into the running min distance, only if its mask bit is on.
float radiance_segMin(float dcur, float on, vec2 p, vec2 a, vec2 b)
{
	float d = radiance_segDist(p, a, b);
	return min(dcur, mix(1e3, d, on));
}
// Signed distance to a circular ARC (the curve keystone for tube-font text later).
float radiance_arc(vec2 p, vec2 c, float ra, float a0, float a1, float r)
{
	vec2 dd = p - c;
	float ang = atan(dd.y, dd.x);
	float span = a1 - a0;
	float rel = mod(ang - a0, 6.28318530718);
	if (rel <= span) return abs(length(dd) - ra) - r;
	vec2 e0 = c + ra * vec2(cos(a0), sin(a0));
	vec2 e1 = c + ra * vec2(cos(a1), sin(a1));
	return min(length(p - e0), length(p - e1)) - r;
}
// cheap hash + 1D value noise for organic flicker.
float radiance_hash(float n){ return fract(sin(n) * 43758.5453123); }
float radiance_vnoise(float x){
	float i = floor(x), f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(radiance_hash(i), radiance_hash(i + 1.0), f);
}
// Master neon flicker multiplier (~0.55 .. 1.15), de-correlated per panel by seed.
float radiance_neonFlicker(float t, float seed)
{
	float ph = seed * 6.2831853;
	float buzz = 0.5 * sin(t * 458.0 + ph) + 0.5 * sin(t * 572.0 + ph * 1.7);
	buzz = 1.0 + 0.045 * buzz;
	float jit = 1.0 - 0.06 * radiance_vnoise(t * 7.0 + seed * 13.0);
	float breathe = 0.96 + 0.06 * sin(t * 0.9 + ph);
	float drv  = radiance_vnoise(t * 0.55 + seed * 31.0);
	float gate = 1.0 - smoothstep(0.0, 0.14, drv);
	float stut = step(0.5, fract(t * 17.0 + seed * 5.0));
	float drop = mix(1.0, mix(0.35, 0.85, stut), gate);
	return clamp(buzz * jit * breathe * drop, 0.55, 1.15);
}
// Spawn warm-up: while pbright ramps 0->1 the tube over-brightens & shivers.
float radiance_neonWarmup(float pb, float t, float seed)
{
	float warm = 1.0 - smoothstep(0.0, 1.0, pb);
	float surge  = 1.0 + 0.55 * warm;
	float shiver = 1.0 + 0.20 * warm * sin(t * 95.0 + seed * 9.0);
	return surge * shiver;
}
// Additive-safe vibrance: expand channels away from luma, no white blowout.
vec3 radiance_vibrance(vec3 c, float amt)
{
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	return clamp(mix(vec3(l), c, 1.0 + amt), 0.0, 2.0);
}
// Signed distance to a rounded box (half-extents he, corner radius rad). <0 inside.
// Keystone for the BRACKETS (18) corner frame and the GAUGE (21) outline.
float radiance_box(vec2 p, vec2 he, float rad)
{
	vec2 q = abs(p) - he + vec2(rad);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - rad;
}

// --- Ghost Stone (SDF) Primitives ---
// Rounded Slab (Tombstone)
float gy_sdf_slab(vec2 p, vec2 sz, float r)
{
    // Rounded top, flat bottom
    p.y += sz.y * 0.5; // Offset to bottom center
    float d = radiance_box(p - vec2(0.0, sz.y * 0.5), sz * 0.5, r);
    float arch = length(p - vec2(0.0, sz.y - r)) - r - sz.x * 0.5 + r;
    return max(d, arch);
}

// Tapered Obelisk
float gy_sdf_obelisk(vec2 p, vec2 sz)
{
    p.x = abs(p.x);
    float taper = mix(sz.x, sz.x * 0.4, clamp(p.y / sz.y, 0.0, 1.0));
    float d = p.x - taper;
    return max(d, abs(p.y - sz.y * 0.5) - sz.y * 0.5);
}

// Kinetic Cross
float gy_sdf_cross(vec2 p, vec2 sz, float thick, float ang)
{
    float c = cos(ang), s = sin(ang);
    mat2 m = mat2(c, -s, s, c);
    vec2 p1 = m * p;
    vec2 p2 = m * vec2(-p.y, p.x);
    float d1 = radiance_box(p1, vec2(sz.x, thick), thick * 0.5);
    float d2 = radiance_box(p2, vec2(thick, sz.y), thick * 0.5);
    return min(d1, d2);
}

// Monolith (Glitching)
float gy_sdf_monolith(vec2 p, vec2 sz, float t)
{
    float glitch = 0.05 * sin(p.y * 20.0 + t * 10.0) * step(0.9, radiance_hash(floor(t * 15.0)));
    p.x += glitch;
    return radiance_box(p, sz * 0.5, 2.0);
}
// ==================== END RADIANCE NEON-TUBE DISPLAY HELPERS ====================
vec4 getLightColor(Material material, float fogdist, float fogfactor)
{
	vec4 color = vColor;
#ifndef SHADER_LITE
	if (uLightLevel >= 0.0)
	{
		float newlightlevel = 1.0 - R_DoomLightingEquation(uLightLevel);
		color.rgb *= newlightlevel;
	}
	else if (uFogEnabled > 0)
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

	//
	// handle glowing walls
	//
	if (uGlowTopColor.a > 0.0 && glowdist.x < uGlowTopColor.a)
	{
		color.rgb += desaturate(uGlowTopColor * (1.0 - glowdist.x / uGlowTopColor.a)).rgb;
	}
	if (uGlowBottomColor.a > 0.0 && glowdist.y < uGlowBottomColor.a)
	{
		color.rgb += desaturate(uGlowBottomColor * (1.0 - glowdist.y / uGlowBottomColor.a)).rgb;
	}

	//
	// [RADIANCE] up to MAX_WALL_GLOW_SPOTS localized glow pools on floors/ceilings.
	// uWallGlowSpots[i] = vec4(center.x, center.z(world), packedRGB, radius). Compile-time loop
	// bound (GLES2-legal); uWallGlowSpotCount is the dynamic early-out.
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
				// [RADIANCE-AIR] wgType==13 is an AIR PANEL: ALWAYS take the wall/panel branch (where the digit
				// lives), regardless of the surface-normal heuristic. In VR the billboard normal reads
				// differently and was routing panels to the floor branch -> no digit. Real walls/floors (wgType<13)
				// still use the normal test.
				bool isWall = (wgType > 12.5) || (abs(vWorldNormal.y) < 0.5);
				if (isWall)
				{
				// [RADIANCE-AIR] PANEL DIGIT (wgType==13): a camera-facing air panel set by the
				// glow-billboard pass. Draw a 7-seg number in the QUAD'S OWN UV SPACE
				// (vTexCoord.st, the interpolated 0..1 corners) so it reads facing the player
				// wherever the panel hangs. The number rides the spare uWallGlowMask[].z lane
				// (the colour float can't hold it for a coloured panel). Strictly gated on
				// wgType==13 - real scene walls never set it, so the cascade below is untouched.
				if (wgType > 12.5)
				{
					float nx = -(vTexCoord.s * 2.0 - 1.0);   // [-1,1] across the panel face (s flipped: digits read forward to the viewer, not mirrored)
					float ny = vTexCoord.t * 2.0 - 1.0;   // [-1,1] down the face (t grows downward)
					float pnum = max(floor(wgMask.z + 0.5), 0.0);   // counter from the spare lane // restored "1234" in VR -> counter wiring is the bug; nothing -> panel viewing-angle (foreshortening) is.
					float pnlen = (pnum < 10.0) ? 1.0 : (pnum < 100.0) ? 2.0 : (pnum < 1000.0) ? 3.0 : (pnum < 10000.0) ? 4.0 : 5.0;
					float pbright = clamp(wgMask.y, 0.0, 1.0);   // wipeProgress lane = panel brightness/fade (1 = full)
					// ---- per-panel flicker seed (de-correlates signs by colour + value) ----
					float pseed  = fract(dot(wgCol, vec3(0.37, 0.71, 0.19)) + pnum * 0.013);
					float pflick = radiance_neonFlicker(timer, pseed) * radiance_neonWarmup(pbright, timer, pseed);

					if (wgType > 25.5 && wgType < 26.5)        // ---- LIGHTNING BOLT (26): jagged gold streak, .y = strike 1..0 ----
					{
						float life0 = clamp(wgMask.y, 0.0, 1.0);
						float t  = timer * 0.9;
						float j  = sin(nx * 6.0 + t * 7.0) * 0.18 + sin(nx * 13.0 - t * 11.0) * 0.10 + sin(nx * 27.0 + t * 17.0) * 0.05;
						float dd = abs(ny - j) - 0.024;                       // main bolt path
						float j2 = sin(nx * 9.0 - t * 5.0) * 0.22 + 0.30;     // a faint branch
						dd = min(dd, abs(ny - j2) - 0.014);
						float ends  = 1.0 - smoothstep(0.90, 1.0, abs(nx));
						float flick = 0.55 + 0.45 * sin(t * 30.0 + nx * 4.0); // rapid crackle
						float core  = smoothstep(0.02, -0.05, dd) * ends;
						float halo  = exp(-max(dd, 0.0) * 14.0); halo *= halo; halo *= ends;
						vec3  gold  = vec3(1.0, 0.78, 0.28);
						float life  = life0 * flick;
						vec3  coreColor = ( vec3(3.0) * core + gold * (halo * 2.2 + core * 0.6) ) * life;
						wgAdd += gold * (halo * 0.9) * life;
						if ((halo > 0.0035 || core > 0.001) && life > 0.01) return vec4(coreColor, 1.0);
					}

					// ============================================================
					//  BRASS STORM SHAPES (camera/quad UV space). Each computes its
					//  own 'dd' (~0 on the glowing contour, >0 away) then falls into
					//  the same neon core/halo early-return the digits use.
					//  16 = shell casing body + stamped damage number. 17 = bounce shard 'clink'.
					// ============================================================
					if (wgType > 15.5 && wgType < 16.5)        // ---- CASING (16) ----
					{
						vec2  bp  = vec2(nx, ny);
						vec2  he  = vec2(0.66, 0.30);            // long x, short y: the casing lies across
						vec2  q   = abs(bp) - he + vec2(0.18);
						float body = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - 0.18;  // rounded-box SDF
						float ddBody = abs(body) - 0.05;        // glow the case-wall outline
						float mouth  = max(abs(nx - 0.50) - 0.04, abs(ny) - 0.22);          // open mouth at +x cap
						float ddMouth = abs(mouth) - 0.03;
						float dd = min(ddBody, ddMouth);

						// stamp the damage NUMBER on the body (font atlas, like the digit branch)
						float snum  = max(floor(wgMask.z + 0.5), 0.0);
						float snlen = (snum < 10.0) ? 1.0 : (snum < 100.0) ? 2.0 : (snum < 1000.0) ? 3.0 : 4.0;
						if (abs(nx) < 0.52 && abs(ny) < 0.20)
						{
							float u  = (nx / 0.52 * 0.5 + 0.5) * snlen;
							float di = clamp(floor(u), 0.0, snlen - 1.0);
							float dxx = (u - di) * 2.0 - 1.0;
							float dyy = ny / 0.20;
							float dv  = mod(floor(snum / pow(10.0, snlen - 1.0 - di)), 10.0);
							float gidx = (48.0 + dv) - 32.0;
							float bcol = mod(wallPat, 8.0);
							float brow = floor(wallPat / 8.0);
							float ccol = bcol * 16.0 + mod(gidx, 16.0);
							float crow = brow * 6.0  + floor(gidx / 16.0);
							vec2  lUV  = clamp(vec2(dxx, dyy) * 0.62 + 0.5, 0.02, 0.98);
							vec2  aUV  = (vec2(ccol, crow) + lUV) / vec2(128.0, 78.0);
							float ssdf = texture(tex, aUV).r;
							dd = min(dd, 0.5 - ssdf);
						}

						float core = smoothstep(0.03, -0.10, dd);
						float halo = exp(-max(dd, 0.0) * 11.0); halo *= halo;
						vec3  hue  = radiance_vibrance(wgCol, 0.55);
						vec3  coreColor = ( vec3(2.4) * core + hue * (halo * 2.2 + core * 0.6) ) * pbright * pflick;
						wgAdd += hue * (halo * 0.9) * pbright * pflick;
						if (halo > 0.0035 || core > 0.001)
							return vec4(coreColor, 1.0);
					}
					else if (wgType > 16.5 && wgType < 17.5)   // ---- SHARD (17): bounce 'clink' ----
					{
						float bar1 = max(abs(ny) - 0.06, abs(nx) - 0.92);   // horizontal sliver
						float bar2 = max(abs(nx) - 0.06, abs(ny) - 0.92);   // vertical sliver
						float spark = min(bar1, bar2);
						float ctr   = length(vec2(nx, ny)) - 0.12;          // hot centre dot
						float dd = min(abs(spark) - 0.02, ctr);
						float core = smoothstep(0.03, -0.10, dd);
						float halo = exp(-max(dd, 0.0) * 13.0); halo *= halo;
						vec3  hue  = radiance_vibrance(wgCol, 0.45);
						vec3  coreColor = ( vec3(2.8) * core + hue * (halo * 2.0 + core * 0.6) ) * pbright * pflick;
						wgAdd += hue * (halo * 0.8) * pbright * pflick;
						if (halo > 0.0035 || core > 0.001)
							return vec4(coreColor, 1.0);
					}
					// ============================================================
					//  WEAPON-SIGNATURE SHAPES (camera/quad UV space). Used by the
					//  REVOLVER "Brand" + the SHOTGUN slam. Animation lane = wgMask.y
					//  (== wipeProgress), aliased as 'panim' below. Each computes 'dd'
					//  (~0 on the glowing contour, >0 away) and falls into the same
					//  core/halo early-return the digits use, EXCEPT smoke (20) which
					//  is a soft additive haze (no white-hot return).
					//  14 = shockwave ring, 15 = filled disc flash, 20 = smoke puff.
					// ============================================================
					else if (wgType > 13.5 && wgType < 14.5)   // ---- SHOCKWAVE RING (14) ----
					{
						float panim = clamp(wgMask.y, 0.0, 1.0);     // expansion lane 0..1
						float r   = length(vec2(nx, ny));
						float rad = mix(0.16, 0.96, panim);          // contour marches outward
						float dd  = abs(r - rad) - mix(0.10, 0.02, panim);   // thins as it grows
						float env = 1.0 - smoothstep(0.55, 1.0, panim);      // dissipates near the end
						float core = smoothstep(0.03, -0.06, dd);
						float halo = exp(-max(dd, 0.0) * 12.0); halo *= halo;
						vec3  hue  = radiance_vibrance(wgCol, 0.55);
						vec3  coreColor = ( vec3(2.4) * core + hue * (halo * 2.0 + core * 0.5) )
						                  * pbright * pflick * env;
						wgAdd += hue * (halo * 0.8) * pbright * pflick * env;
						if ((halo > 0.0035 || core > 0.001) && env > 0.001)
							return vec4(coreColor, 1.0);
					}
					else if (wgType > 14.5 && wgType < 15.5)   // ---- FILLED DISC FLASH (15) ----
					{
						float panim = clamp(wgMask.y, 0.0, 1.0);     // here wipeProgress = brightness (1=hot, 0=gone)
						float r   = length(vec2(nx, ny));
						float dd  = r - 0.85;                         // inside the disc -> dd<0 -> white core
						float env = panim * panim;                   // caller fades panim toward 0 for snap-off
						float core = smoothstep(0.10, -0.30, dd);     // big soft interior
						float halo = exp(-max(dd, 0.0) * 8.0); halo *= halo;
						vec3  hue  = radiance_vibrance(wgCol, 0.45);
						vec3  coreColor = ( vec3(2.8) * core + hue * (halo * 1.6 + core * 0.4) )
						                  * pbright * pflick * env;
						wgAdd += hue * (halo * 0.7) * pbright * pflick * env;
						if ((halo > 0.0035 || core > 0.001) && env > 0.002)
							return vec4(coreColor, 1.0);
					}
					else if (wgType > 19.5 && wgType < 20.5)   // ---- SMOKE PUFF (20) ----
					{
						float panim = clamp(wgMask.y, 0.0, 1.0);
						vec2  q = vec2(nx, ny);
						// two cheap 1-D value-noise lumps break the circle into smoke
						float n1 = radiance_vnoise(q.x * 3.1 + timer * 0.6 + pseed * 7.0);
						float n2 = radiance_vnoise(q.y * 2.7 - timer * 0.5 + pseed * 3.0);
						float lump = (n1 + n2) * 0.25;               // ~0..0.5
						float r    = length(q) * (1.0 + 0.35 * (lump - 0.25));
						float edge = 0.55 + 0.25 * panim;            // billows outward with t
						float dd   = r - edge;
						float cloud = 1.0 - smoothstep(-0.25, 0.20, dd);   // fuzzy fill
						vec3  hue   = wgCol;                          // already desaturated grey from ZScript
						// soft additive haze ONLY -- deliberately no white-hot early-return.
						wgAdd += hue * (cloud * 0.45 * panim) * pbright * pflick;
						// (panim here = brightness; ZScript fades it to 0 as the puff dies.)
					}
					// ============================================================
					//  NEON DISPLAY SHAPES (in-air glow panels, camera/quad UV space).
					//  All FIVE compute their own 'dd' (~0 on the glowing contour, <0
					//  inside, >0 outside) then fall into the SAME canonical neon
					//  core/halo early-RETURN the digits use -- MANDATORY for VR
					//  (post-processing swallows non-returned additive content).
					//  18 = corner BRACKETS, 19 = WAVEFORM/oscilloscope,
					//  21 = segmented BAR/GAUGE, 22 = SPECTRUM/heatmap strip,
					//  23 = SKULL (wireframe->solid materialize sweep, font-atlas sample).
					//  Brightness/fade lane = wgMask.y (pbright). pnum (=wgMask.z) carries
					//  the per-shape data seed (amplitude / fill% / level / unused).
					// ============================================================
					else if (wgType > 17.5 && wgType < 18.5)   // ---- CORNER BRACKETS (18) ----
					{
						// Target-reticle frame: four L-shaped corner brackets. A bracket = the
						// outline band of a rounded box, KEPT only near the four corners (the
						// long mid-runs are masked out so it reads as [   ] corners, not a box).
						vec2  bp  = vec2(nx, ny);
						vec2  he  = vec2(0.78, 0.62);                 // frame half-extents
						float frame = abs(radiance_box(bp, he, 0.05)) - 0.035;   // hollow outline band
						// keep only the corner runs: a point is "corner" if it is near BOTH
						// the x-edge and y-edge bands (within 'arm' of a corner along each axis).
						float arm = 0.30;
						float cornerX = he.x - abs(nx);              // distance inside from the x edge
						float cornerY = he.y - abs(ny);              // distance inside from the y edge
						float keep = max(cornerX, cornerY);          // >arm in the long mid-runs
						// mask the band OUT in the mid-runs by pushing dd positive there
						float dd = (keep < arm) ? frame : (frame + 0.40);
						// small hot tick at dead-center (aiming pip)
						float pip = length(bp) - 0.05;
						dd = min(dd, abs(pip) - 0.02);

						float core = smoothstep(0.03, -0.10, dd);
						float halo = exp(-max(dd, 0.0) * 11.0); halo *= halo;
						vec3  hue  = radiance_vibrance(wgCol, 0.55);
						vec3  coreColor = ( vec3(2.6) * core + hue * (halo * 2.2 + core * 0.6) ) * pbright * pflick;
						wgAdd += hue * (halo * 0.9) * pbright * pflick;
						if (halo > 0.0035 || core > 0.001)
							return vec4(coreColor, 1.0);
					}
					else if (wgType > 18.5 && wgType < 19.5)   // ---- WAVEFORM / OSCILLOSCOPE (19) ----
					{
						// A horizontal trace y = f(nx) drawn as a thin glowing tube. The wave is
						// a sum of value-noise lumps + a sine, scrolled by 'timer' and seeded by
						// pnum (amplitude seed) so different panels read different traces.
						float amp  = 0.30 + 0.45 * fract(pnum * 0.013 + pseed);   // 0.30..0.75 trace height
						float ph   = pseed * 6.2831853;
						// composite waveform (cheap, no loops)
						float w  = sin(nx * 6.0 + timer * 3.0 + ph) * 0.55;
						w += sin(nx * 13.0 - timer * 2.0 + ph * 1.7) * 0.30;
						w += (radiance_vnoise(nx * 5.0 + timer * 1.5 + pseed * 9.0) - 0.5) * 0.55;
						float wy = clamp(w * amp, -0.92, 0.92);                  // target y at this x
						// distance from this pixel to the trace (vertical band -> tube)
						float dTrace = abs(ny - wy) - 0.025;
						// faint center baseline (zero line) so it reads as a scope
						float dBase  = abs(ny) - 0.006;
						float dd = min(dTrace, dBase + 0.30);     // baseline dimmer (pushed out a touch)
						dd = min(dd, dTrace);

						float core = smoothstep(0.03, -0.10, dd);
						float halo = exp(-max(dd, 0.0) * 12.0); halo *= halo;
						vec3  hue  = radiance_vibrance(wgCol, 0.55);
						vec3  coreColor = ( vec3(2.6) * core + hue * (halo * 2.2 + core * 0.6) ) * pbright * pflick;
						wgAdd += hue * (halo * 0.9) * pbright * pflick;
						if (halo > 0.0035 || core > 0.001)
							return vec4(coreColor, 1.0);
					}
					else if (wgType > 20.5 && wgType < 21.5)   // ---- SEGMENTED BAR / GAUGE (21) ----
					{
						// A horizontal segmented fill bar inside a thin frame. pnum = fill 0..100.
						float fill = clamp(pnum / 100.0, 0.0, 1.0);              // 0..1 fill fraction
						vec2  bp   = vec2(nx, ny);
						vec2  he   = vec2(0.80, 0.26);                           // bar frame half-extents
						float frame = abs(radiance_box(bp, he, 0.04)) - 0.022;      // outline band always lit
						float dd = frame;
						// inside the frame: draw discrete segments up to the fill level
						if (abs(nx) < he.x - 0.06 && abs(ny) < he.y - 0.06)
						{
							const float SEGS = 12.0;
							float u    = (nx + (he.x - 0.06)) / (2.0 * (he.x - 0.06)); // 0..1 across
							float cell = u * SEGS;                               // segment coordinate
							float si   = floor(cell);
							float frac = cell - si;                              // 0..1 within segment
							float lit  = step(si + 0.999, fill * SEGS);          // is this segment filled?
							// gap between segments: dark thin border at frac ~0 / ~1
							float gap  = min(frac, 1.0 - frac) - 0.10;           // <0 in the gap
							// the lit segment body: a filled slab -> dd<0 white-hot, but only if lit
							float seg  = max(-gap, -(he.y - 0.10 - abs(ny)));    // inside the slab
							float ddSeg = lit > 0.5 ? seg : (seg + 0.50);        // unlit segs pushed out
							dd = min(dd, ddSeg);
						}

						float core = smoothstep(0.03, -0.10, dd);
						float halo = exp(-max(dd, 0.0) * 11.0); halo *= halo;
						vec3  hue  = radiance_vibrance(wgCol, 0.55);
						vec3  coreColor = ( vec3(2.6) * core + hue * (halo * 2.2 + core * 0.6) ) * pbright * pflick;
						wgAdd += hue * (halo * 0.9) * pbright * pflick;
						if (halo > 0.0035 || core > 0.001)
							return vec4(coreColor, 1.0);
					}
					else if (wgType > 21.5 && wgType < 22.5)   // ---- SPECTRUM / HEATMAP STRIP (22) ----
					{
						// A bank of vertical bars whose heights = a per-column "spectrum" value.
						// Column count fixed; height driven by value-noise + sine animated by timer.
						// pnum = level seed so panels animate independently.
						const float COLS = 14.0;
						float u    = nx * 0.5 + 0.5;                  // 0..1 across
						float ci   = floor(u * COLS);                 // column index
						float cfrac = fract(u * COLS);                // 0..1 within column
						// per-column animated height (heatmap-ish)
						float seedC = ci * 0.131 + pseed * 7.0;
						float h = radiance_vnoise(seedC + timer * 2.2) * 0.6
						        + 0.4 * (0.5 + 0.5 * sin(timer * 4.0 + ci * 0.9 + pseed * 6.0));
						h = clamp(h, 0.05, 0.98);                     // bar height 0..1 (top from baseline)
						float top = mix(0.92, -0.92, h);              // bar fills from bottom (+0.92) up to 'top'
						// inside a column gutter? leave a thin dark gap between bars
						float gap = min(cfrac, 1.0 - cfrac) - 0.12;   // <0 in the gap
						// the bar body: filled where ny >= top (toward +y/bottom) and not in the gutter
						float inBar = (ny > top && gap > 0.0) ? -1.0 : 1.0;
						// dd: white-hot inside the bar, glowing rim at its top edge
						float ddTop = abs(ny - top) - 0.02;          // hot cap line at the bar top
						float dd = (inBar < 0.0) ? min(ddTop, -0.05) : (ddTop + 0.30);
						// baseline strip along the bottom for structure
						float dBase = abs(ny - 0.92) - 0.01;
						dd = min(dd, dBase + 0.20);

						float core = smoothstep(0.03, -0.10, dd);
						float halo = exp(-max(dd, 0.0) * 11.0); halo *= halo;
						// hue shifts a touch warmer for taller bars -> heatmap feel
						vec3  hot  = radiance_vibrance(wgCol, 0.55);
						vec3  hue  = mix(hot, hot * vec3(1.2, 0.9, 0.7), clamp(h, 0.0, 1.0) * 0.5);
						vec3  coreColor = ( vec3(2.4) * core + hue * (halo * 2.2 + core * 0.6) ) * pbright * pflick;
						wgAdd += hue * (halo * 0.9) * pbright * pflick;
						if (halo > 0.0035 || core > 0.001)
							return vec4(coreColor, 1.0);
					}
					else if (wgType > 22.5 && wgType < 23.5)   // ---- SKULL (23): wireframe -> solid materialize ----
					{
						// Sample the reserved 384x384 SDF skull baked into the neonfont atlas
						// (block F=99 = the full 6x6 cell run, px [3072:3456, 4608:4992],
						//  UV u:0.37500..0.42188  v:0.92308..1.00000). s = panel-face -> skull
						//  square in [0,1]; map across all SIX cells of the block, clamp inside
						//  the block to avoid bleeding into the neighbour border.
						vec2  s   = clamp(vec2(nx * 0.5 + 0.5, ny * 0.5 + 0.5), 0.02, 0.98);
						vec2  aUV = (vec2(48.0, 72.0) + s * 6.0) / vec2(128.0, 78.0);
						float skullSdf = texture(tex, aUV).r;        // 0.5 = edge, >0.5 inside

						// wipeProgress sweep (Snatcher materialize): pbright ramps 0->1 over life.
						// Vertical line marches top(-1) -> bottom(+1). Below the line = SOLID fill,
						// above = WIREFRAME (edge-only). mix() is GLSL (no-smoothstep rule is ZScript-only).
						float sweepY = mix(-1.0, 1.0, pbright);
						const float EDGE = 0.06;                     // wireframe contour half-band
						float ddSolid = 0.5 - skullSdf;              // interior fills (like a glyph)
						float ddWire  = abs(0.5 - skullSdf) - EDGE;  // hollow: only the contour band
						float dd = (ny <= sweepY) ? ddSolid : ddWire;

						// hot scan-line right at the materialize front
						float scan = abs(ny - sweepY);
						float scanHot = (scan < 0.03) ? smoothstep(0.03, 0.0, scan) : 0.0;

						float core = smoothstep(0.03, -0.10, dd);
						float halo = exp(-max(dd, 0.0) * 11.0); halo *= halo;

						// ---- DIGITIZE (Snatcher CRT-chrome look) ----
						// CRT raster: horizontal scanlines with a slow downward roll.
						float scanline = 0.74 + 0.26 * sin(ny * 90.0 + timer * 3.0);
						// duotone: cold blue chrome on the bone, hot red/orange deep in the recesses.
						float depth = clamp((skullSdf - 0.5) * 2.0, 0.0, 1.0);   // 0 edge -> 1 deep interior
						vec3  coldBone  = vec3(0.45, 0.66, 1.0);
						vec3  hotRecess = vec3(1.0, 0.34, 0.12);
						vec3  skullHue  = mix(coldBone, hotRecess, depth * 0.7);
						// a burning ember in each eye socket (upper face), flickering (positions tunable).
						float eyd   = min(length(vec2(nx, ny) - vec2(-0.26, -0.16)),
						                  length(vec2(nx, ny) - vec2( 0.26, -0.16)));
						float ember = exp(-eyd * eyd * 24.0) * (0.55 + 0.45 * sin(timer * 11.0 + nx * 4.0));

						vec3  coreColor = ( vec3(2.2) * core + skullHue * (halo * 2.0 + core * 0.6) ) * scanline * pbright * pflick;
						coreColor += vec3(1.0, 0.42, 0.16) * ember * core * 1.7 * pflick;   // sockets burn
						coreColor += skullHue * scanHot * 1.5 * pflick;                     // materialize front
						wgAdd += skullHue * (halo * 0.9) * pbright * pflick * scanline;
						if (halo > 0.0035 || core > 0.001 || scanHot > 0.02)
							return vec4(coreColor, 1.0);
					}

					// ======================= SIGN BACKPLATE + DIGITS =======================
					// Gated to the NUMBER panel (shape 13) ONLY. Procedural shapes 14-17
					// either early-returned above or (smoke 20) already wrote their wgAdd;
					// they must NOT get a digit backplate/glyph painted over them.
					if (wgType < 13.5)
					{
					float pny = -ny;                                  // +y = up for the 7-seg math
					vec2  fp  = vec2(nx, ny);
					float rr  = length(max(abs(fp) - vec2(0.80, 0.66), 0.0));
					float plate = 1.0 - smoothstep(0.0, 0.34, rr);
					float vign  = mix(0.20, 1.0, plate);
					float rim   = smoothstep(0.10, 0.0, rr);
					vec3  glassBase = wgCol * 0.10 * vign;
					vec3  rimRGB    = (wgCol + vec3(0.20)) * rim * 0.35;
					wgAdd = (glassBase + rimRGB) * pbright * pflick;

					// ======================= NEON TUBE DIGITS =====================
					if (abs(nx) < 0.92 && abs(pny) < 0.78)
					{
						float u  = (nx / 0.92 * 0.5 + 0.5) * pnlen;
						float di = clamp(floor(u), 0.0, pnlen - 1.0);
						float dx = (u - di) * 2.0 - 1.0;
						float dy = pny / 0.78;
						float dv = mod(floor(pnum / pow(10.0, pnlen - 1.0 - di)), 10.0);
						// ---- sample the COMBINED multi-font SDF atlas (textures/neonfont.png) ----
						// font index rides in wallPat (the wipeType hundreds digit). FPR=8 font-blocks per row,
						// each block 16 cols x 6 rows of glyph cells (ASCII 32..126). grid = 128 x 78 cells.
						float gidx = (48.0 + dv) - 32.0;                // digit '0'..'9' -> block char index
						float bcol = mod(wallPat, 8.0);                 // FPR = 8
						float brow = floor(wallPat / 8.0);
						float ccol = bcol * 16.0 + mod(gidx, 16.0);     // COLS_PER_FONT = 16
						float crow = brow * 6.0  + floor(gidx / 16.0);  // ROWS_PER_FONT = 6
						vec2  lUV  = clamp(vec2(dx, -dy) * 0.62 + 0.5, 0.02, 0.98);
						vec2  aUV  = (vec2(ccol, crow) + lUV) / vec2(128.0, 78.0);   // GRIDW x GRIDH
						float sdf  = texture(tex, aUV).r;               // 0.5 = glyph edge, >0.5 inside

						const float SAT = 0.55;    // halo vibrance
						float dd   = 0.5 - sdf;                         // >0 outside glyph, <0 inside
						float core = smoothstep(0.03, -0.10, dd);       // glyph interior = white-hot filament
						float halo = exp(-max(dd, 0.0) * 11.0);         // saturated colour bleed outward
						halo *= halo;

						vec3 hue = radiance_vibrance(wgCol, SAT);

						vec3 coreColor = ( vec3(2.6) * core
						                 + hue * (halo * 2.2 + core * 0.6) )
						                 * pbright * pflick;

						wgAdd += hue * (halo * 0.9 * vign) * pbright * pflick;

						if (halo > 0.0035 || core > 0.001)
						{
							return vec4(coreColor, 1.0);
						}
					}
					}   // end if (wgType < 13.5) -- number-panel backplate+digits
				}
				else
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
				}   // [RADIANCE-AIR] close wall-pattern else (panel branch wraps this)
				}
				else
				{
				if (wgType > 12.5)
				{
					float nasp = max(length(wgMask.zw), 0.001);
					float nhH = wgSp.w / sqrt(1.0 + nasp * nasp);
					float nhW = nasp * nhH;
					// VIEW-FACING: build the digit plane from the CAMERA, not the floor, so the
					// number stands up out of the ground and turns to face the player. uCameraPos
					// is a live uniform; nAY maps to floor-depth-from-camera (perspective = "up").
					vec3 nCenter = vec3(wgSp.x, pixelpos.y, wgSp.y);
					vec3 nToCam  = normalize(uCameraPos.xyz - nCenter);
					vec3 nRight  = normalize(cross(vec3(0.0, 1.0, 0.0), nToCam));
					vec3 nUp2    = cross(nToCam, nRight);
					vec3 nworld  = pixelpos.xyz - nCenter;
					float nAX = dot(nworld, nRight);
					float nAY = dot(nworld, nUp2);
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
							float th = 0.25, sl = 0.60;   // thicker/longer segments so they read in VR / at distance
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
#endif
	color = min(color, 1.0);

	// these cannot be safely applied by the legacy format where the implementation cannot guarantee that the values are set.
#if !defined LEGACY_USER_SHADER && !defined NO_LAYERS
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
	// apply lightmaps
	//
	if (vLightmap.z >= 0.0)
	{
		color.rgb += texture(LightMap, vLightmap).rgb;
	}

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
// The color of the fragment if it is fully occluded by ambient lighting
//
//===========================================================================

vec3 AmbientOcclusionColor()
{
	float fogdist;
	float fogfactor;

	//
	// calculate fog factor
	//
	if (uFogEnabled == -1) 
	{
		fogdist = max(16.0, pixelpos.w);
	}
	else 
	{
		fogdist = max(16.0, distance(pixelpos.xyz, uCameraPos.xyz));
	}
	fogfactor = exp2 (uFogDensity * fogdist);

	return mix(uFogColor.rgb, vec3(0.0), fogfactor);
}

vec4 ApplyFadeColor(vec4 frag)
{
	if (uGlobalFade == 1 && uFogEnabled != 0)
	{
		float fogdist;
		if (uFogEnabled == 1 || uFogEnabled == -1) 
		{
			// standard fog (1 or -1)
			fogdist = max(16.0, pixelpos.w);
		}
		else 
		{
			// radial fog (2 or -2)
			fogdist = max(16.0, distance(pixelpos.xyz, uCameraPos.xyz));
		}
		float visibility = exp(-pow((fogdist * uGlobalFadeDensity), uGlobalFadeGradient));
		visibility = clamp(visibility, 0.0, 1.0);
		vec4 fogcolor = uGlobalFadeColor;
		if (uGlobalFadeMode == -1)
		{
			frag = vec4(mix(fogcolor.rgb, frag.rgb, visibility), frag.a * visibility);
		}
		else if (uGlobalFadeMode == 2)
		{
			frag = vec4(fogcolor.rgb, frag.a) * visibility;
		}
	}
	return frag;
}

// ======================== RADIANCE OMNI-FOG & REGIMES ===========================
// These uniforms now live in the StreamData UBO (see hw_renderstate.h + vk_shader.cpp),
// fed globally per-frame. Vulkan forbids non-opaque uniforms outside a block, so the
// loose declarations were removed; the names still resolve via #defines in the prelude
// (u_vr_blueprint_col / u_radiance_last_impact_pos are vec4 there, swizzled to .rgb / .xyz).

vec4 applyOmniFog(vec4 frag, float fogdist)
{
	if (u_radiance_fog_mode <= 0) return applyFog(frag, exp2(uFogDensity * fogdist));
	
	float density = u_radiance_fog_density * 0.01;
	float fogfactor = exp(-fogdist * density);
	vec3 fogColor = uFogColor.rgb;
	
	// Light-Link: Fog matches the room's glow color
	if (u_radiance_fog_lightlink > 0) fogColor = mix(fogColor, vColor.rgb, 0.5);

	// Mode 1: Ground-Mist (Height Fog)
	if (u_radiance_fog_mode == 1)
	{
		float h = clamp((pixelpos.y - u_radiance_fog_height) / -32.0, 0.0, 1.0);
		fogfactor = mix(1.0, fogfactor, h);
	}
	// Mode 2: Spectral Silhouette (Tactical Rim)
	else if (u_radiance_fog_mode == 2)
	{
		float rim = 1.0 - clamp(dot(normalize(vEyeNormal.xyz), vec3(0,0,1)), 0.0, 1.0);
		rim = pow(rim, u_radiance_fog_rim_power);
		fogColor = mix(fogColor, vec3(0.0, 1.0, 0.8), rim * (1.0 - fogfactor));
	}
	// Mode 3: Bit-Crush (Data Degradation)
	else if (u_radiance_fog_mode == 3)
	{
		float q = mix(255.0, u_radiance_fog_quantize, 1.0 - fogfactor);
		frag.rgb = floor(frag.rgb * q) / q;
	}
	// Mode 4: Vortex (Noise Swirl)
	else if (u_radiance_fog_mode == 4)
	{
		float swirl = radiance_vnoise(pixelpos.x * 0.01 + timer * u_radiance_fog_speed) 
		            * radiance_vnoise(pixelpos.z * 0.01 - timer * u_radiance_fog_speed);
		fogfactor *= (0.7 + 0.3 * swirl);
	}

	return vec4(mix(fogColor, frag.rgb, clamp(fogfactor, 0.0, 1.0)), frag.a);
}

vec4 applyVisualRegime(vec4 frag, vec3 worldPos)
{
	if (u_vr_visual_regime <= 0) return frag;

	// VR SAFETY PASS: Use Spatial Proximity instead of Screen-Space Masks
	float distToPlayer = length(worldPos - uCameraPos.xyz);
	// Proximity Mask: Effects are faint near the player (hands/gun) and full strength in the arena
	// Scaling by u_vr_regime_bubble_size allows user to shrink it to zero for total coverage.
	float proximityMask = smoothstep(64.0 * u_vr_regime_bubble_size, 384.0 * u_vr_regime_bubble_size, distToPlayer);
	if (u_vr_regime_bubble_size <= 0.0) proximityMask = 1.0;
	
	// Reactivity Helpers
	float damagePulse = exp(-max(0.0, timer - u_radiance_last_hit_time) * 4.0);
	float firePulse   = exp(-max(0.0, timer - u_radiance_last_fire_time) * 6.0);
	float comboPulse  = u_radiance_kill_streak;

	// Regime 1: System Shock (Vector-Frame / Matrix)
	if (u_vr_visual_regime == 1)
	{
		float edge = 1.0 - clamp(dot(normalize(vEyeNormal.xyz), vec3(0,0,1)), 0.0, 1.0);
		
		// Reactivity: Overclock (Lines thicken on killstreak)
		float threshold = 0.6 - (comboPulse * 0.2);
		edge = smoothstep(threshold, 0.9, edge);
		
		vec3 col = vec3(0.1, 1.0, 0.2); // Green
		// VR-SAFE REACTIVITY: Pulse color/intensity on hit, NEVER shake geometry
		if (u_vr_regime_react > 0 && damagePulse > 0.1) col = mix(col, vec3(1.0, 0.1, 0.1), damagePulse);
		
		vec3 neon = col * edge * (2.0 + comboPulse * 3.0);
		frag.rgb = mix(frag.rgb * (0.2 + comboPulse * 0.3), neon, edge * proximityMask);
	}
	// Regime 2: Tron (Data-Sea Grid)
	else if (u_vr_visual_regime == 2)
	{
		// Reactivity: Sonar Ping (Radial wave on fire)
		float ping = 0.0;
		if (u_vr_regime_react > 0) {
			float wavePos = fract((timer - u_radiance_last_fire_time) * 2.0) * 2048.0;
			ping = smoothstep(256.0, 0.0, abs(distToPlayer - wavePos)) * firePulse * u_vr_regime_ping_inten;
		}

		vec2 grid = abs(fract(worldPos.xz * 0.015) - 0.5) / 0.02;
		float line = 1.0 - min(grid.x, grid.y);
		line = smoothstep(0.0, 1.0, line);
		
		// Reactivity: Speed Trails (Grid brightens with velocity)
		float speedVal = (u_vr_regime_speed_link > 0) ? u_radiance_player_speed : 1.0;
		float gridBright = line * (u_vr_regime_param1 + speedVal + ping + comboPulse);
		
		vec3 gridCol = mix(vec3(0.0, 0.5, 1.0), vec3(1.0, 0.5, 0.0), comboPulse); // Blue -> Orange on streak
		frag.rgb += gridCol * gridBright * proximityMask;
	}
	// Regime 3: Blueprint (CAD-Tactical)
	else if (u_vr_visual_regime == 3)
	{
		float edge = 1.0 - clamp(dot(normalize(vEyeNormal.xyz), vec3(0,0,1)), 0.0, 1.0);
		edge = smoothstep(0.4, 0.7, edge);
		
		vec3 navy = vec3(0.02, 0.05, 0.15);
		vec3 lineCol = u_vr_blueprint_col * (1.0 + firePulse * 2.0);
		
		// Highlight enemies/entities if they are "hot" (glow/bright)
		float entityMask = step(0.1, dot(frag.rgb, vec3(0.3, 0.5, 0.2)));
		vec3 entCol = vec3(1.0, 0.5, 0.0) * entityMask; // Orange entities
		
		frag.rgb = mix(navy, lineCol, edge);
		frag.rgb = mix(frag.rgb, entCol, entityMask * proximityMask);
	}
	// Regime 4: Thermal (Heat-Track)
	else if (u_vr_visual_regime == 4)
	{
		float luma = dot(frag.rgb, vec3(0.3, 0.59, 0.11));
		vec3 cold = vec3(0.0, 0.1, 0.4);
		vec3 hot  = vec3(1.0, 0.9, 0.1);
		vec3 mid  = vec3(1.0, 0.0, 0.0);
		
		vec3 thermal;
		if (luma < 0.5) thermal = mix(cold, mid, luma * 2.0);
		else            thermal = mix(mid, hot, (luma - 0.5) * 2.0);
		
		frag.rgb = mix(frag.rgb, thermal * u_vr_thermal_inten, proximityMask);
	}
	// Regime 5: Digital Noir (Sin City)
	else if (u_vr_visual_regime == 5)
	{
		float luma = dot(frag.rgb, vec3(0.3, 0.59, 0.11));
		vec3 noir = vec3(pow(luma, 1.5)); // High contrast grayscale
		
		// Keep saturation for RADIANCE colors (heuristic: high saturation areas)
		vec3 hsv = rgb2hsv(frag.rgb);
		float satMask = smoothstep(0.4, 0.8, hsv.y);
		
		// Adrenaline Bleed (Color returns on damage)
		float bleed = damagePulse * 0.5;
		
		frag.rgb = mix(noir, frag.rgb, (satMask + bleed) * proximityMask);
	}
	// Regime 7: LSD (SDF Warp)
	else if (u_vr_visual_regime == 7)
	{
		// Reactivity: Adrenaline Warp (Wavy speed increases with player velocity)
		float speedMul = (u_vr_regime_speed_link > 0) ? (1.0 + u_radiance_player_speed * 5.0) : 1.0;
		float wave = sin(worldPos.y * 0.1 + timer * u_vr_regime_speed * speedMul);
		
		vec3 hsv = rgb2hsv(frag.rgb);
		hsv.x = fract(hsv.x + wave * 0.2 * proximityMask);
		frag.rgb = mix(frag.rgb, hsv2rgb(hsv), proximityMask);
	}
	// Regime 9: Tetris (Voxel-Stack)
	else if (u_vr_visual_regime == 9)
	{
		float size = 32.0;
		vec3 g = floor(worldPos / size);
		vec3 f = fract(worldPos / size);
		
		float h = fract(sin(dot(g.xz, vec2(12.9898, 78.233))) * 43758.5453);
		
		vec3 tCol;
		int type = int(h * 7.0);
		if      (type == 0) tCol = vec3(0.0, 1.0, 1.0); // I (Cyan)
		else if (type == 1) tCol = vec3(1.0, 1.0, 0.0); // O (Yellow)
		else if (type == 2) tCol = vec3(0.5, 0.0, 1.0); // T (Purple)
		else if (type == 3) tCol = vec3(0.0, 1.0, 0.0); // S (Green)
		else if (type == 4) tCol = vec3(1.0, 0.0, 0.0); // Z (Red)
		else if (type == 5) tCol = vec3(0.0, 0.0, 1.0); // J (Blue)
		else                tCol = vec3(1.0, 0.5, 0.0); // L (Orange)
		
		// Reactivity: Line Clear (White flash on killstreak burst)
		if (u_vr_regime_react > 0 && comboPulse > 0.8) {
			tCol = mix(tCol, vec3(1.5), smoothstep(0.8, 1.0, comboPulse));
		}

		float fall = floor(timer * u_vr_regime_speed * 2.0);
		float isSolid = step(0.5, fract(sin(dot(g + vec3(0, fall, 0), vec3(1.1, 10.2, 100.3))) * 10.0));
		
		float margin = 0.08;
		float b = step(margin, f.x) * step(margin, f.y) * step(margin, f.z) *
		          step(f.x, 1.0-margin) * step(f.y, 1.0-margin) * step(f.z, 1.0-margin);
		
		vec3 blockFrag = mix(vec3(0.0), tCol, b) * (0.3 + 0.7 * isSolid);
		
		// Spatial Mask: blocks only appear at distance
		frag.rgb = mix(frag.rgb, blockFrag, proximityMask);
	}
	
	return frag;
}

//===========================================================================
//
// Main shader routine
//
//===========================================================================

void main()
{
#ifdef NO_CLIPDISTANCE_SUPPORT
	if (ClipDistanceA.x < 0.0 || ClipDistanceA.y < 0.0 || ClipDistanceA.z < 0.0 || ClipDistanceA.w < 0.0 || ClipDistanceB.x < 0.0) discard;
#endif

	// Distorted world-position for applyVisualRegime() below (regime sampling only; SetupMaterial's
	// own texture lookups are unaffected). Declared here, ahead of the LEGACY_USER_SHADER branch,
	// so it's always in scope at the call site regardless of which Material path compiles.
	vec3 regimeWorldPos = pixelpos.xyz;

#ifndef LEGACY_USER_SHADER
	Material material;

	material.Base = vec4(0.0);
	material.Bright = vec4(0.0);
	material.Glow = vec4(0.0);
	material.Normal = vec3(0.0);
	material.Specular = vec3(0.0);
	material.Glossiness = 0.0;
	material.SpecularLevel = 0.0;
	material.Metallic = 0.0;
	material.Roughness = 0.0;
	material.AO = 0.0;

	// --- Reactive Impact Ripples (Global Coordinate Distortion) ---
	// 'pixelpos' is a shader INPUT -- Vulkan/SPIR-V forbids writing to it (older GL compilers
	// silently tolerated this) -- so the distortion is written into regimeWorldPos instead.
	if (u_vr_ripples_enabled > 0)
	{
		float rippleLife = timer - u_radiance_last_impact_time;
		if (rippleLife < 1.0) // 1 second ripple life
		{
			float distToImpact = length(pixelpos.xyz - u_radiance_last_impact_pos);
			float wavePos = rippleLife * 2048.0; // Wave expansion speed
			float ripple = smoothstep(128.0, 0.0, abs(distToImpact - wavePos));
			ripple *= (1.0 - rippleLife); // Fade over time

			// Distort world-space lookup for regimes.
			// Note: we only distort for the 'fancy' regimes to avoid nausea on basic textures.
			if (u_vr_visual_regime > 0)
			{
				regimeWorldPos = pixelpos.xyz + normalize(pixelpos.xyz - u_radiance_last_impact_pos) * ripple * 32.0 * u_vr_ripple_scale;
			}
		}
	}

	SetupMaterial(material);
#else
	Material material = ProcessMaterial();
#endif
	vec4 frag = material.Base;

#ifndef NO_ALPHATEST
	if (frag.a <= uAlphaThreshold) discard;
#endif

	if (uFogEnabled != -3)	// check for special 2D 'fog' mode.
	{
		float fogdist = 0.0;
		float fogfactor = 0.0;
#ifdef SHADER_LITE
		fogdist = max(16.0, pixelpos.w);
		fogfactor = exp2 (uFogDensity * fogdist);
		frag = getLightColor(material, fogdist, fogfactor);
#else
		//
		// calculate fog factor
		//
		if (uFogEnabled != 0)
		{
			if (uFogEnabled == 1 || uFogEnabled == -1) 
			{
				fogdist = max(16.0, pixelpos.w);
			}
			else 
			{
				fogdist = max(16.0, distance(pixelpos.xyz, uCameraPos.xyz));
			}
			fogfactor = exp2 (uFogDensity * fogdist);
		}

		if ((uTextureMode & 0xffff) != 7)
		{
			frag = getLightColor(material, fogdist, fogfactor);
			// [RADIANCE] Only run omni-fog when a RADIANCE fog mode is explicitly enabled. Otherwise fall
			// back to STOCK behaviour (verified vs main.fp.old_bak): apply fog ONLY for coloured
			// fog (uFogEnabled < 0). Positive uFogEnabled is Doom light-diminishing whose uFogColor
			// is BLACK for ordinary sectors -- applyOmniFog's unconditional fallback mixed every
			// surface toward that black, which is the black-world bug.
			if (u_radiance_fog_mode > 0)
				frag = applyOmniFog(frag, fogdist);
			else if (uFogEnabled < 0)
				frag = applyFog(frag, fogfactor);
		}
		else
		{
			frag = vec4(uFogColor.rgb, (1.0 - fogfactor) * frag.a * 0.75 * vColor.a);
		}
#endif
		frag = ApplyFadeColor(frag);
	}
	else // simple 2D (uses the fog color to add a color overlay)
	{
		if ((uTextureMode & 0xffff) == 7)
		{
			float gray = grayscale(frag);
			vec4 cm = (uObjectColor + gray * (uAddColor - uObjectColor)) * 2.0;
			frag = vec4(clamp(cm.rgb, 0.0, 1.0), frag.a);
		}
			frag = frag * ProcessLight(material, vColor);
		frag.rgb = frag.rgb + uFogColor.rgb;
	}
	
	frag = applyVisualRegime(frag, regimeWorldPos);
	FragColor = frag;

#ifdef DITHERTRANS
	int index = (int(pixelpos.x) % 8) * 8 + int(pixelpos.y) % 8;
	const float DITHER_THRESHOLDS[64] =
	float[64](
		1.0 / 65.0, 33.0 / 65.0, 9.0 / 65.0, 41.0 / 65.0, 3.0 / 65.0, 35.0 / 65.0, 11.0 / 65.0, 43.0 / 65.0,
		49.0 / 65.0, 17.0 / 65.0, 57.0 / 65.0, 25.0 / 65.0, 51.0 / 65.0, 19.0 / 65.0, 59.0 / 65.0, 27.0 / 65.0,
		13.0 / 65.0, 45.0 / 65.0, 5.0 / 65.0, 37.0 / 65.0, 15.0 / 65.0, 47.0 / 65.0, 7.0 / 65.0, 39.0 / 65.0,
		61.0 / 65.0, 29.0 / 65.0, 53.0 / 65.0, 21.0 / 65.0, 63.0 / 65.0, 31.0 / 65.0, 55.0 / 65.0, 23.0 / 65.0,
		4.0 / 65.0, 36.0 / 65.0, 12.0 / 65.0, 44.0 / 65.0, 2.0 / 65.0, 34.0 / 65.0, 10.0 / 65.0, 42.0 / 65.0,
		52.0 / 65.0, 20.0 / 65.0, 60.0 / 65.0, 28.0 / 65.0, 50.0 / 65.0, 18.0 / 65.0, 58.0 / 65.0, 26.0 / 65.0,
		16.0 / 65.0, 48.0 / 65.0, 8.0 / 65.0, 40.0 / 65.0, 14.0 / 65.0, 46.0 / 65.0, 6.0 / 65.0, 38.0 / 65.0,
		64.0 / 65.0, 32.0 / 65.0, 56.0 / 65.0, 24.0 / 65.0, 62.0 / 65.0, 30.0 / 65.0, 54.0 / 65.0, 22.0 /65.0
	);

	vec3 fragHSV = rgb2hsv(FragColor.rgb);
	float brightness = clamp(1.5*fragHSV.z, 0.1, 1.0);
	if (DITHER_THRESHOLDS[index] < brightness) discard;
	else FragColor *= 0.5;
#endif

#ifdef GBUFFER_PASS
	FragFog = vec4(AmbientOcclusionColor(), 1.0);
	FragNormal = vec4(vEyeNormal.xyz * 0.5 + 0.5, 1.0);
#endif
}
