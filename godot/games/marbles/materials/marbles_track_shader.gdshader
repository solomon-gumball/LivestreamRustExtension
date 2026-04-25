shader_type spatial;
render_mode cull_disabled, depth_draw_always;
uniform sampler2D checkbox_texture: source_color;
uniform sampler2D colored_noise: source_color;
//uniform float p

void vertex() {

}

void fragment() {
	vec2 scaled_uvs = UV * 15.0;
	vec4 checkerboard_sample = texture(checkbox_texture, scaled_uvs);

	vec2 uv_scale1 = UV * .20;
	vec2 uv_scale2 = UV * .3;

	vec2 mixed_uvs = mix(uv_scale1, uv_scale2, checkerboard_sample.r);
	ALBEDO = texture(colored_noise, mixed_uvs).rgb;
	//if (!FRONT_FACING) {
		//ALPHA = 0.5;
	//}
	//ALPHA = FRONT_FACING ? 1.0 : 0.5;
	//ALPHA_HASH_SCALE = 2.0;
}

//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}
