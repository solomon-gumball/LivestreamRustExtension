// Draws the linearized depth buffer to the screen for debugging.
// Apply to a full-screen quad MeshInstance3D (QuadMesh, render_mode unshaded).
shader_type spatial;
render_mode blend_mix, unshaded, cull_back;

uniform sampler2D depth_texture : hint_depth_texture;

// Scale the visible depth range: 0 = black (near), 1 = white (far).
// Reduce this to see detail in close-range scenes.
uniform float depth_range : hint_range(1.0, 1000.0, 1.0) = 100.0;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	float raw_depth = texture(depth_texture, SCREEN_UV).r;

	// Reconstruct NDC z, accounting for renderer differences.
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	// OpenGL: depth in [0,1] maps to NDC z in [-1,1]
	vec3 ndc = vec3(SCREEN_UV, raw_depth) * 2.0 - 1.0;
#else
	// Vulkan reverse-Z: depth already in [0,1] for NDC z
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw_depth);
#endif

	// Unproject to view space and read linear depth (-z, positive away from camera).
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	float linear_depth = -view.z / view.w;

	float gray = linear_depth / depth_range;
	ALBEDO = vec3(gray);
	ALPHA = 1.0;
}
