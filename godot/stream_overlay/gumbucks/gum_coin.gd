@tool
extends RigidBody3D
class_name GumCoin

@onready var mesh: MeshInstance3D = %Mesh

@onready var sparkles_fx: GPUParticles3D = %Sparkles
@onready var explosion_fx: GPUParticles3D = %Explosion

@export var collision_shape: CylinderShape3D
@export var value: int = 5
@export var size_scalar := 1.0:
  set(new_value):
    if is_inside_tree():
      size_scalar = new_value
      mesh.scale = Vector3(size_scalar, size_scalar, size_scalar)
      # collision_shape.radius = base_collision_radius * size_scalar
      # collision_shape.height = base_collision_height * size_scalar
      sparkles_fx.scale = Vector3(size_scalar, size_scalar, size_scalar)
      explosion_fx.scale = Vector3(size_scalar, size_scalar, size_scalar)

@export var base_collision_radius: float = 0.242: 
  set(new_value):
    base_collision_radius = new_value
    size_scalar = size_scalar

@export var base_collision_height: float = 0.117:
  set(new_value):
    base_collision_height = new_value
    size_scalar = size_scalar

# signal on_collected(drop: GumDrop, bot: Bot)

# var text_label: Label3D = null
# var was_collected: bool = false

func _ready():
  size_scalar = size_scalar
#   body_entered.connect(on_body_entered)

# func on_body_entered(body: Node) -> void:
#   if body is Bot:
#     handle_collected(body as Bot)

# var font = ResourceLoader.load("res://fonts/ttf/JetBrainsMono-ExtraBoldItalic.ttf")

# func handle_collected(bot: Bot):
#   if was_collected:
#     return
  
#   ($Shape as CollisionShape3D).disabled = true
#   on_collected.emit(self, bot)
#   was_collected = true
#   sparkles_fx.emitting = false
#   explosion_fx.emitting = true
#   mesh.visible = false
#   text_label = Label3D.new()
#   text_label.text = "+%d GUM" % value
#   text_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
#   text_label.modulate = Color(0, 1, .2, 1)
#   text_label.outline_size = 0
#   text_label.font = font
#   add_child(text_label)

#   var inital_pos = global_position + Vector3(0, 0.174, 0)
#   var duration = 1.5
#   var tween = get_tree().create_tween().set_parallel(true)
#   tween.tween_property(text_label, "modulate:a", 0, duration)\
#     .set_trans(Tween.TRANS_QUAD)\
#     .set_ease(Tween.EASE_OUT)
#   await tween.tween_property(text_label, "global_position", global_position + Vector3(0, .8, 0), duration)\
#   .from(inital_pos)\
#   .set_trans(Tween.TRANS_QUAD)\
#   .set_ease(Tween.EASE_OUT).finished

#   free()
