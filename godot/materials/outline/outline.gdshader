shader_type spatial;
render_mode blend_mix, unshaded, cull_back;

uniform sampler2D depth_texture : hint_depth_texture;
uniform float thickness : hint_range(0.5, 20.0, 0.1) = 2.0;
uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float threshold : hint_range(0.00001, 0.01, 0.00001) = 0.0001;
uniform int samples : hint_range(4, 16, 1) = 8;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec2 px = 1.0 / VIEWPORT_SIZE * thickness;
	float center = texture(depth_texture, SCREEN_UV).r;

	float max_diff = 0.0;
	float angle_step = TAU / float(samples);
	for (int i = 0; i < samples; i++) {
		float angle = float(i) * angle_step;
		vec2 offset = vec2(cos(angle), sin(angle)) * px;
		float d = abs(texture(depth_texture, SCREEN_UV + offset).r - center);
		max_diff = max(max_diff, d);
	}

	ALBEDO = outline_color.rgb;
	ALPHA = step(threshold, max_diff) * outline_color.a;
  // ALBEDO = vec3(center, center, center);
  // ALPHA = 1.0;
}
