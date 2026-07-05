

layout(location = 0) in vec4 vTexCoord;
layout(location = 1) in vec4 vColor;
layout(location = 2) in vec4 pixelpos;
layout(location = 3) in vec3 glowdist;
layout(location = 4) in vec3 gradientdist;
layout(location = 5) in vec4 vWorldNormal;
layout(location = 6) in vec4 vEyeNormal;
layout(location = 9) in vec3 vLightmap;

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

			//
			// colored fog
			//
			if (uFogEnabled < 0) 
			{
				frag = applyFog(frag, fogfactor);
			}
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
