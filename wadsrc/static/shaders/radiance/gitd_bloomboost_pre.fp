void main()
{
	vec3 colour = texture(InputTexture, TexCoord).rgb;
	// Floor at 0 ONLY (no ceiling): pow() of a negative is NaN, which paints the
	// solid rectangle. max() kills that path while leaving the upper range FREE so
	// the glow can run hot and bloom toward the footage look. Do NOT clamp the top.
	colour = max(colour, vec3(0.0));
	colour = pow(colour, vec3(gamma));
	colour *= contrast;
	colour += brightness;
	FragColor = vec4(colour, 1.0);
}
