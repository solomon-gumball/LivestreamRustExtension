#[compute]
#version 450
#define MAX_VIEWS 2

#include "godot/scene_data_inc.glsl"

// Invocations in the (x, y, z) dimension.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, std140) uniform SceneDataBlock {
	SceneData data;
	SceneData prev_data;
} scene_data_block;

layout(rgba16f, set = 0, binding = 1) uniform image2D color_image;
layout(set = 0, binding = 2) uniform sampler2D depth_texture;

// Must be aligned to 16 bytes.
layout(push_constant, std430) uniform Params {
	vec2 raster_size;
	float view;
	float thickness;
	vec4 edge_color;
	float fade_start;
	float fade_length;
	int step_count;
	float pad;
} params;

void main() {
	ivec2 uv = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = ivec2(params.raster_size);

	if (uv.x >= size.x || uv.y >= size.y) {
		return;
	}

	vec2 uv_norm = vec2(uv) / params.raster_size;

	// Setup step parameters
	vec2 step_length = 1.0 / params.raster_size * params.thickness;
	float step_angle = 6.28318530718 / float(params.step_count);
	// Per-pixel jitter to reduce patterning
	float start_angle = fract(sin(dot(uv_norm, vec2(12.9898, 78.233))) * 43758.5453) * 6.28318530718;
	vec2 dir = vec2(cos(start_angle), sin(start_angle));
	// step rotation matrix
	mat2 rot = mat2(
		vec2(cos(step_angle), -sin(step_angle)),
		vec2(sin(step_angle),  cos(step_angle)));

	vec3 avg_dx = vec3(0.0);
	vec3 avg_dy = vec3(0.0);
	// save closest pixel to uniformly fade line.
	float min_z = 1e6;

	mat4 inv_proj = scene_data_block.data.inv_projection_matrix;

	// Sample and average derivatives for all pairs
	for (int i = 0; i < params.step_count; i++) {
		vec2 uv1 = uv_norm + dir * step_length;
		vec2 uv2 = uv_norm - dir * step_length;
		float d1 = texture(depth_texture, uv1).r;
		float d2 = texture(depth_texture, uv2).r;
		vec4 up1 = inv_proj * vec4(uv1 * 2.0 - 1.0, d1, 1.0);
		vec4 up2 = inv_proj * vec4(uv2 * 2.0 - 1.0, d2, 1.0);
		vec3 p1 = up1.xyz / up1.w;
		vec3 p2 = up2.xyz / up2.w;
		min_z = min(min_z, min(-p1.z, -p2.z));
		vec3 diff = p1 - p2;
		avg_dx += diff * dir.x;
		avg_dy += diff * dir.y;

		dir = rot * dir; // rotate direction for next step
	}

	// fade outline width with distance
	float distance_fade = 1e-4 + smoothstep(params.fade_start + params.fade_length, params.fade_start, min_z);

	// Reconstruct view direction for the center pixel
	float depth_center = texture(depth_texture, uv_norm).r;
	vec4 view_coord = inv_proj * vec4(uv_norm * 2.0 - 1.0, depth_center, 1.0);
	view_coord.xyz /= view_coord.w;
	vec3 view_dir = normalize(-view_coord.xyz);

	// Edge mask
	float edge = 1.0 - smoothstep(0.1, 0.15, dot(normalize(cross(avg_dy, avg_dx)), view_dir));

	// Small vignette at screen edges
	edge *= smoothstep(0.00, 0.015 * params.thickness,
		1.0 - max(abs(uv_norm.x - 0.5), abs(uv_norm.y - 0.5)) * 2.0);

	// Composite outline over color buffer (matches blend_premul_alpha behaviour:
	// out = src_premul + dst * (1 - src_alpha))
	float alpha = edge * distance_fade;
	vec4 color = imageLoad(color_image, uv);
	vec4 out_color = vec4(params.edge_color.rgb * edge + color.rgb * (1.0 - alpha), color.a);
	imageStore(color_image, uv, out_color);

  // imageStore(color_image, uv, vec4(1.0, 0.0, 0.0, 1.0));
}
