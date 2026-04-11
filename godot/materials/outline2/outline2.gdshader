shader_type spatial;
render_mode blend_mix, unshaded, cull_back;

uniform sampler2D depth_texture : hint_depth_texture;
uniform float thickness : hint_range(0.5, 20.0, 0.1) = 2.0;
uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float threshold : hint_range(0.00001, 0.01, 0.00001) = 0.0001;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec2 px = 1.0 / VIEWPORT_SIZE * thickness;
	float center = texture(depth_texture, SCREEN_UV).r;

	float d = max(
		max(abs(texture(depth_texture, SCREEN_UV + vec2(px.x, 0)).r - center),
		    abs(texture(depth_texture, SCREEN_UV - vec2(px.x, 0)).r - center)),
		max(abs(texture(depth_texture, SCREEN_UV + vec2(0, px.y)).r - center),
		    abs(texture(depth_texture, SCREEN_UV - vec2(0, px.y)).r - center)));

	ALBEDO = outline_color.rgb;
	ALPHA = step(threshold, d) * outline_color.a;
}
