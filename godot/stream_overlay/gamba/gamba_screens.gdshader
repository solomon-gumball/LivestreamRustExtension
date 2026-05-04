shader_type spatial;

uniform sampler2D albedo_texture: source_color;
uniform sampler2D hightlight_texture: source_color;
uniform int selected_slot = -1;
uniform int num_slots = 16;
uniform int slots_order[16];
uniform float slot_offset = 0.5;
uniform float highlight_strength = 1.0;
uniform float flash_rate = 6.0;
uniform float pulse_scale = 0.15;

const int num_cols = 4;

vec2 get_alternative_uv_for_offset(float offset, float currX) {
	int source_index = int(floor(offset));
	int out_index = slots_order[source_index];
	int out_row = int(floor(float(out_index) / float(num_cols)));
	int out_col = out_index - out_row * num_cols;
	vec2 starting_uv = vec2(float(out_col) * .25, float(out_row) * .25);
	return starting_uv + vec2(currX / float(num_cols), mod(offset, 1.0) / float(num_cols));
}

// Scale UVs around the center of an emoji cell (each cell is 0.25x0.25 in atlas space)
vec2 scale_uv_around_cell_center(vec2 uv, vec2 cell_center, float scale) {
	return cell_center + (uv - cell_center) / scale;
}

vec2 apply_pulse(vec2 uv, int source_index, float flash) {
	int out_index = slots_order[source_index];
	int out_row = int(floor(float(out_index) / float(num_cols)));
	int out_col = out_index - out_row * num_cols;
	vec2 cell_center = vec2(float(out_col) * 0.25 + 0.125, float(out_row) * 0.25 + 0.125);
	float scale = 1.0 + pulse_scale * flash;
	return scale_uv_around_cell_center(uv, cell_center, scale);
}

vec2 rotate(vec2 uv, vec2 pivot, float angle)
{
	mat2 rotation = mat2(vec2(sin(angle), -cos(angle)),
						vec2(cos(angle), sin(angle)));

	uv -= pivot;
	uv = uv * rotation;
	uv += pivot;
	return uv;
}

void fragment() {
	float num_to_display = 3.0;
	float adjusted_offset = mod(slot_offset - 1.0 + (UV.y * num_to_display), 16.0);
	vec2 uvs = get_alternative_uv_for_offset(adjusted_offset, UV.x);

	vec4 background_color = vec4(0.0);
	int source_index = int(floor(adjusted_offset));
	if (source_index == selected_slot) {
		vec2 hl_uvs = vec2(UV.x, mod(adjusted_offset, 1.0));
		hl_uvs = rotate(hl_uvs, vec2(0.5, 0.5), TIME * -15.0);
		if (hl_uvs.x > 0.00 && hl_uvs.x < 1.0 && hl_uvs.y > 0.00 && hl_uvs.y < 1.0) {
			vec4 highlight_sample = texture(hightlight_texture, hl_uvs);
			background_color = mix(background_color, highlight_sample, highlight_sample.a * highlight_strength);
	    }
	}
	float flash = source_index == selected_slot ? (sin(TIME * flash_rate) * 0.5 + 0.5) * highlight_strength : 0.0;
	vec2 pulsed_uvs = source_index == selected_slot ? apply_pulse(uvs, source_index, flash) : uvs;
	vec4 out_color = texture(albedo_texture, pulsed_uvs);
	// Multiply flash by out_color.a so only opaque emoji pixels whiten, not transparent background
	vec4 flashed_color = mix(out_color, vec4(1.0, 1.0, 1.0, out_color.a), flash * out_color.a);
	vec4 mixed_color = mix(background_color, flashed_color, flashed_color.a);

	//vec3 with_highlights = mix(selected_slot == )
	ALBEDO = mixed_color.rgb;

	//int source_index = int(floor(slot_offset + (UV.y * 3.0)));
	//int out_index = slots_order[source_index];
	//int out_row = int(floor(float(out_index) / float(num_cols)));
	//int out_col = out_index - out_row * num_cols;
	//ALBEDO = vec3(float(out_col) / 4.0, float(out_row) / 4.0, 0.0);
	//ALBEDO = vec3(uvs.x, uvs.y, 1.0);
	EMISSION = ALBEDO * 0.5;
}
