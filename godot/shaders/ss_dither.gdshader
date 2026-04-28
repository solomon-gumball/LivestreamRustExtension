shader_type spatial;
render_mode depth_test_inverted, unshaded, cull_back;

uniform vec3 color: source_color = vec3(1.0, 1.0, 1.0);
uniform sampler2D dither_pattern;
uniform float dither_scale = .02;

void fragment() {
	vec2 dither_uv = FRAGCOORD.xy / (vec2(textureSize(dither_pattern, 0)) * dither_scale);
	vec4 dither_sample = texture(dither_pattern, dither_uv);
	ALPHA = dither_sample.r;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALBEDO = color;
}