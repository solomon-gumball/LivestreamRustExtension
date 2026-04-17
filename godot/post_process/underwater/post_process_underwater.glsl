#[compute]
#version 450
#define MAX_VIEWS 2

#include "godot/scene_data_inc.glsl"

// Invocations in the (x, y, z) dimension.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, std140) uniform SceneDataBlock {
	SceneData data;
	SceneData prev_data;
}
scene_data_block;

layout(rgba16f, set = 0, binding = 1) uniform image2D color_image;
layout(set = 0, binding = 2) uniform sampler2D depth_texture;
layout(rgba16f, set = 0, binding = 3) uniform image2D dna_viewport_image;

// Our push constant.
// Must be aligned to 16 bytes, just like the push constant we passed from the script.
layout(push_constant, std430) uniform Params {
  vec2 raster_size;
  float view;
  bool is_underwater;
  float character_focus_amt;
} params;

// The code we want to execute in each invocation.
void main() {
  ivec2 uv = ivec2(gl_GlobalInvocationID.xy);
  ivec2 size = ivec2(params.raster_size);
  int view = int(params.view);

  if (uv.x >= size.x || uv.y >= size.y) {
    return;
  }

  ivec2 uv_with_offset = uv;
  vec2 uv_norm = vec2(uv_with_offset) / params.raster_size;

  // Screen distortion when underwater
  if (params.is_underwater) {
    float vignette_mask = clamp(1.0 - distance(uv_norm, vec2(0.5, 0.5)) * 2.0, 0.0, 1.0);
    float normalized_offset = sin(scene_data_block.data.time * 2.0 + uv_norm.x * 5.0);
    normalized_offset = (normalized_offset + 1.0) * 0.5;
    float offset_y = (0.05 * normalized_offset) * params.raster_size.y * vignette_mask;
    uv_with_offset.y += int(offset_y);
    uv_with_offset.y = clamp(uv_with_offset.y, 0, int(params.raster_size.y) - 1);
    uv_norm = vec2(uv_with_offset) / params.raster_size;
  }

  vec4 color = imageLoad(color_image, uv_with_offset);

  if (params.is_underwater) {
    float depth = texture(depth_texture, uv_norm).r;
    vec3 ndc = vec3(uv_norm * 2.0 - 1.0, depth);
    vec4 view_space_coord = scene_data_block.data.inv_projection_matrix * vec4(ndc, 1.0);
    view_space_coord.xyz /= view_space_coord.w;

    // --- Depth Fog ---
    float linear_depth = -view_space_coord.z;
    float fog_start = 0.0;
    float fog_end = 20.0;
    float min_fog_amt = 0.25;
    vec4 fog_color = vec4(0.0, 0.35, 0.6, 1.0);
    float fog_factor = min_fog_amt + (1.0 - min_fog_amt) * smoothstep(fog_start, fog_end, linear_depth);
    color = mix(color, fog_color, fog_factor);

    // // --- Caustics ---
    // float range_mod = clamp((world_pos.y + caustic_range) * 0.05, 0.0, 1.0);
    // if (range_mod > 0.0) {
    //     vec3 X = vec3(world_pos.xz * caustic_size,
    //                   mod(TIME, 578.0) * 0.86602540378);
    //     vec4 noiseResult = os2NoiseWithDerivatives_Fallback(X);
    //     noiseResult = os2NoiseWithDerivatives_Fallback(X - noiseResult.xyz / 16.0);
    //     float caustic_value = fma(noiseResult.w, 0.5, 0.5) * range_mod * range_mod;
    //     out_color = clamp(out_color + caustic_value * caustic_strength * (1.0 - fog_factor),
    //                       vec3(0.0), vec3(1.0));
    // }
  }
  
  // vec4 color = imageLoad(color_image, uv);
  vec4 dna_scene_color = imageLoad(dna_viewport_image, uv_with_offset);
  vec4 out_color = mix(color, dna_scene_color, params.character_focus_amt);
  imageStore(color_image, uv, out_color);

  // imageStore(color_image, uv, imageLoad(dna_viewport_image, uv_with_offset));
}