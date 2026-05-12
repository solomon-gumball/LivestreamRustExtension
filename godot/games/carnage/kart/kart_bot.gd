@tool
extends CharacterBody3D
class_name KartBot

@onready var kart_wheel_l: MeshInstance3D = %KartWheel_L
@onready var kart_wheel_r: MeshInstance3D = %KartWheel_R
@onready var kart_movement: KartMovementSynchronizer = %KartMovement
@onready var gumbot: CarnageGumbot = %gumbot
@onready var mesh: MeshInstance3D = %Mesh
@onready var punch_area: Area3D = %PunchArea

# @onready var anim_tree: AnimationTree = %AnimationTree

@export var kart_material: StandardMaterial3D

@export var wheel_turn: float = 0.0:
  set(new_value):
    wheel_turn = new_value
    kart_wheel_l.rotation.y = wheel_turn
    kart_wheel_r.rotation.y = wheel_turn

const VISUAL_CORRECTION_SMOOTH := 0.0001

var _mesh_rest_position: Vector3
var _mesh_rest_rotation_y: float

func _ready() -> void:
  _mesh_rest_position = mesh.position
  _mesh_rest_rotation_y = mesh.rotation.y

func punch_collide() -> void:
  var overlapping: Array[Node3D] = punch_area.get_overlapping_bodies()
  for bot in overlapping:
    if bot is KartBot and bot != self:
      bot.handle_punch_impact(self)

func handle_punch_impact(from_kart: KartBot) -> void:
  var impulse: Vector3 = (global_position - from_kart.global_position).normalized()
  var axis := impulse.cross(Vector3.UP).normalized()
  impulse = impulse.rotated(axis, deg_to_rad(65))
  impulse *= 5.0

  kart_movement.physics_state.velocity += impulse

# var visual_interp_target_position: Vector3
func apply_visual_correction(pos_offset: Vector3, rot_y_offset: float) -> void:
  pass
  # mesh.position = _mesh_rest_position - pos_offset
  # mesh.rotation.y = _mesh_rest_rotation_y - rot_y_offset

func _process(delta: float) -> void:
  if Engine.is_editor_hint():
    return
  
  if mesh.position != _mesh_rest_position:
    print("interping mesh position")
    mesh.position = mesh.position.move_toward(_mesh_rest_position, VISUAL_CORRECTION_SMOOTH * delta)
  if mesh.rotation.y != _mesh_rest_rotation_y:
    mesh.rotation.y = move_toward(mesh.rotation.y, _mesh_rest_rotation_y, VISUAL_CORRECTION_SMOOTH * delta)

func punch_cosmetic() -> void:
  get_tree().create_tween().tween_property(gumbot.spring_bone_sim, "influence", 0, 0.1)
  gumbot.anim_tree.set("parameters/PunchOneShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
  await gumbot.anim_tree.animation_finished
  await get_tree().create_timer(0.1).timeout
  get_tree().create_tween().tween_property(gumbot.spring_bone_sim, "influence", 1.0, 0.1)
