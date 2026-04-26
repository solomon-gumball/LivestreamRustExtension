shader_type spatial;
render_mode cull_disabled, unshaded;

uniform sampler2D emote_texture: source_color;

void vertex() {
	// Billboard: strip rotation from the model-view matrix so the quad always faces the camera.
	// Only the scale on the diagonal is kept; translation comes from the original MODELVIEW_MATRIX.
	mat4 mv = MODELVIEW_MATRIX;
	float sx = length(mv[0].xyz);
	float sy = length(mv[1].xyz);
	float sz = length(mv[2].xyz);
	mat4 billboard = mat4(
		vec4(sx,  0.0, 0.0, 0.0),
		vec4(0.0, sy,  0.0, 0.0),
		vec4(0.0, 0.0, sz,  0.0),
		mv[3]
	);
	POSITION = PROJECTION_MATRIX * billboard * vec4(VERTEX, 1.0);
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	if (length(uv) > 1.0) {
		ALPHA = 0.0;
	}
	vec4 emote_color = texture(emote_texture, UV);
	ALBEDO = emote_color.rgb;
}

//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}
