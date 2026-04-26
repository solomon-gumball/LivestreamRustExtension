extends MeshInstance3D
class_name EmoteBillboard

@export var emote_material: ShaderMaterial
var emote_texture: Texture2D:
  set(new_tex):
    emote_texture = new_tex
    emote_material.set_shader_parameter("emote_texture", new_tex)
