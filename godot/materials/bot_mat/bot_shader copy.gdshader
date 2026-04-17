shader_type spatial;
uniform sampler2D albedo_texture: source_color;
uniform sampler2D normal_map: source_color;
uniform vec3 bot_color: source_color = vec3(1.0, .4, .6);

void vertex() {
	// Called for every vertex the material is visible on.
}

void fragment() {
	vec4 albedo_sample = texture(albedo_texture, UV);
	vec3 base_color_mix = mix(bot_color.rgb, albedo_sample.rgb, albedo_sample.a);
	ALBEDO = base_color_mix;
	EMISSION = ALBEDO * 0.3;
	NORMAL_MAP = texture(normal_map, UV).rgb;
}
