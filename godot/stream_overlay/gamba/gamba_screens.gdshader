shader_type spatial;

uniform sampler2D albedo_texture: source_color;
uniform sampler2D hightlight_texture: source_color;
uniform int selected_slot = -1;
uniform int num_slots = 16;
uniform int slots_order[16];
uniform float slot_offset = 0.5;
uniform float highlight_strength = 1.0;

const int num_cols = 4;

vec2 get_alternative_uv_for_offset(float offset, float currX) {
	int source_index = int(floor(offset));
	int out_index = slots_order[source_index];
	int out_row = int(floor(float(out_index) / float(num_cols)));
	int out_col = out_index - out_row * num_cols;
	vec2 starting_uv = vec2(float(out_col) * .25, float(out_row) * .25);
	return starting_uv + vec2(currX / float(num_cols), mod(offset, 1.0) / float(num_cols));
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
	vec4 out_color = texture(albedo_texture, uvs);
	vec4 mixed_color = mix(background_color, out_color, out_color.a);

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
