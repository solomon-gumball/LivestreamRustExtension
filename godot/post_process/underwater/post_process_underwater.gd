@tool
class_name PostProcessUnderwater
extends PostProcessEffect

func get_shader_file() -> RDShaderFile:
  return load("res://post_process/underwater/post_process_underwater.glsl")

@export var dna_viewport_texture: ViewportTexture

# Called by the rendering thread every frame.
func _render_callback(p_effect_callback_type: EffectCallbackType, p_render_data: RenderData) -> void:
  if rd and p_effect_callback_type == EFFECT_CALLBACK_TYPE_POST_TRANSPARENT and pipeline.is_valid():
    # Get our render scene buffers object, this gives us access to our render buffers.
    # Note that implementation differs per renderer hence the need for the cast.
    var render_scene_buffers := p_render_data.get_render_scene_buffers()
    var scene_data: RenderSceneData = p_render_data.get_render_scene_data()
    if render_scene_buffers and scene_data:
      # Get our render size, this is the 3D render resolution!
      var size: Vector2i = render_scene_buffers.get_internal_size()
      if size.x == 0 and size.y == 0:
        return

      # We can use a compute shader here.
      @warning_ignore("integer_division")
      var x_groups := (size.x - 1) / 8 + 1
      @warning_ignore("integer_division")
      var y_groups := (size.y - 1) / 8 + 1
      var z_groups := 1

      # Create push constant.
      # Must be aligned to 16 bytes and be in the same order as defined in the shader.
      var push_constant := PackedFloat32Array([
          size.x,
          size.y,
          0.0, #
          0.0,
          0.0, #
          0.0,
          0.0, #
          0.0,
        ])
     
      if not nearest_sampler.is_valid():
          var sampler_state: RDSamplerState = RDSamplerState.new()
          sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
          sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
          nearest_sampler = rd.sampler_create(sampler_state)

      # Loop through views just in case we're doing stereo rendering. No extra cost if this is mono.
      var view_count: int = render_scene_buffers.get_view_count()
      for view in view_count:
        var scene_data_buffers: RID = scene_data.get_uniform_buffer()
        var input_image: RID = render_scene_buffers.get_color_layer(view)
        var depth_image: RID = render_scene_buffers.get_depth_layer(view)
        var input_viewport: RID = RenderingServer.texture_get_rd_texture(dna_viewport_texture)

        var scene_data_uniform := RDUniform.new()
        scene_data_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
        scene_data_uniform.binding = 0
        scene_data_uniform.add_id(scene_data_buffers)

        var color_uniform := RDUniform.new()
        color_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
        color_uniform.binding = 1
        color_uniform.add_id(input_image)

        var depth_uniform := RDUniform.new()
        depth_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
        depth_uniform.binding = 2
        depth_uniform.add_id(nearest_sampler)
        depth_uniform.add_id(depth_image)

        var viewport_uniform := RDUniform.new()
        viewport_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
        viewport_uniform.binding = 3
        viewport_uniform.add_id(input_viewport)

        var uniform_set := UniformSetCacheRD.get_cache(shader, 0, [scene_data_uniform, color_uniform, depth_uniform, viewport_uniform])

        push_constant[2] = view
        # Get global shader parameter for underwater status
        push_constant[3] = true
        push_constant[4] = true
        # print("Underwater status: ", StateManager.cam_is_underwater)
        # push_constant[3] = false
        # Run our compute shader.

        var compute_list := rd.compute_list_begin()
        rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
        rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
        rd.compute_list_set_push_constant(compute_list, push_constant.to_byte_array(), push_constant.size() * 4)
        rd.compute_list_dispatch(compute_list, x_groups, y_groups, z_groups)
        rd.compute_list_end()
#endregion
