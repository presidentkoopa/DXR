void main()
{
	vec3 colour = texture(InputTexture, TexCoord).rgb;
	colour -= brightness;
	colour *= contrast;
	// -=brightness above can push colour NEGATIVE; pow(negative) = NaN = the solid
	// rectangle. Floor at 0 ONLY, right before pow(), to kill the NaN. No upper
	// clamp -- bright bloom passes through freely so the glow stays hot/bloomy.
	colour = max(colour, vec3(0.0));
	colour = pow(colour, vec3(gamma));
	FragColor = vec4(colour, 1.0);
}
