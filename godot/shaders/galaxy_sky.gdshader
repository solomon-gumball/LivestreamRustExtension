
// NOTE: Shader automatically converted from Godot Engine 4.4.1.stable.mono's PanoramaSkyMaterial.

shader_type sky;

uniform sampler2D source_panorama : filter_linear, source_color, hint_default_black;
uniform sampler2D noise_panorama : filter_linear, source_color, hint_default_black;

uniform float exposure : hint_range(0, 128) = 1.0;

void sky() {
	vec2 new_coord = SKY_COORDS;
	new_coord.x += TIME * .001;
	vec3 noise_sample = texture(noise_panorama, new_coord).rgb;
	COLOR = (texture(source_panorama, SKY_COORDS).rgb + noise_sample * .2) * exposure;
}
