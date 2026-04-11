@tool
class_name PostProcessOutline
extends PostProcessEffect

func get_shader_file() -> RDShaderFile:
  return load("res://util/post_process_outline.glsl")

@export var thickness: float = 3.0
@export var edge_color: Color = Color.BLACK
@export var fade_start: float = 100.0
@export var fade_length: float = 200.0
@export var step_count: int = 3

# Called by the rendering thread every frame.
func _render_callback(p_effect_callback_type: EffectCallbackType, p_render_data: RenderData) -> void:
  if rd and p_effect_callback_type == EFFECT_CALLBACK_TYPE_POST_TRANSPARENT and pipeline.is_valid():
    var render_scene_buffers := p_render_data.get_render_scene_buffers()
    var scene_data: RenderSceneData = p_render_data.get_render_scene_data()
    if render_scene_buffers and scene_data:
      var size: Vector2i = render_scene_buffers.get_internal_size()
      if size.x == 0 and size.y == 0:
        return

      @warning_ignore("integer_division")
      var x_groups := (size.x - 1) / 8 + 1
      @warning_ignore("integer_division")
      var y_groups := (size.y - 1) / 8 + 1
      var z_groups := 1

      if not nearest_sampler.is_valid():
        var sampler_state: RDSamplerState = RDSamplerState.new()
        sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
        sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
        nearest_sampler = rd.sampler_create(sampler_state)

      # Build push constant as raw bytes so we can encode step_count as int32.
      # Layout matches Params in the shader (std430, 48 bytes total):
      #   vec2  raster_size  ( 0)
      #   float view         ( 8)
      #   float thickness    (12)
      #   vec4  edge_color   (16)
      #   float fade_start   (32)
      #   float fade_length  (36)
      #   int   step_count   (40)
      #   float pad          (44)
      var push_constant := PackedByteArray()
      push_constant.resize(48)

      var view_count: int = render_scene_buffers.get_view_count()
      for view in view_count:
        var scene_data_buffers: RID = scene_data.get_uniform_buffer()
        var input_image: RID = render_scene_buffers.get_color_layer(view)
        var depth_image: RID = render_scene_buffers.get_depth_layer(view)

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

        var uniform_set := UniformSetCacheRD.get_cache(shader, 0, [scene_data_uniform, color_uniform, depth_uniform])

        push_constant.encode_float(0,  size.x)
        push_constant.encode_float(4,  size.y)
        push_constant.encode_float(8,  float(view))
        push_constant.encode_float(12, thickness)
        push_constant.encode_float(16, edge_color.r)
        push_constant.encode_float(20, edge_color.g)
        push_constant.encode_float(24, edge_color.b)
        push_constant.encode_float(28, edge_color.a)
        push_constant.encode_float(32, fade_start)
        push_constant.encode_float(36, fade_length)
        push_constant.encode_s32(40,   step_count)
        push_constant.encode_float(44, 0.0)

        var compute_list := rd.compute_list_begin()
        rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
        rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
        rd.compute_list_set_push_constant(compute_list, push_constant, push_constant.size())
        rd.compute_list_dispatch(compute_list, x_groups, y_groups, z_groups)
        rd.compute_list_end()
