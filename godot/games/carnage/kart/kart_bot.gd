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

const VISUAL_CORRECTION_DURATION := 0.3

var _mesh_rest_position: Vector3
var _mesh_rest_rotation_y: float

func _ready() -> void:
  _mesh_rest_position = mesh.position
  _mesh_rest_rotation_y = mesh.rotation.y
  mesh.top_level = true

func punch_collide() -> void:
  var overlapping: Array[Node3D] = punch_area.get_overlapping_bodies()
  for bot in overlapping:
    if bot is KartBot and bot != self:
      bot.handle_punch_impact(self)

func handle_punch_impact(from_kart: KartBot) -> void:
  var impulse: Vector3 = (global_position - from_kart.global_position).normalized()
  var axis := impulse.cross(Vector3.UP).normalized()
  impulse = impulse.rotated(axis, deg_to_rad(85))
  impulse *= 5.0

  kart_movement.physics_state.velocity += impulse

var interp_visual_tween: Tween = null
func apply_visual_correction(prev_global_pos: Vector3, prev_global_rot_y: float) -> void:
  var start_pos: Vector3
  var start_rot_y: float

  if interp_visual_tween != null and interp_visual_tween.is_running():
    start_pos = mesh.global_position
    start_rot_y = mesh.global_rotation.y
    interp_visual_tween.kill()
  else:
    start_pos = prev_global_pos + Basis(Vector3.UP, prev_global_rot_y) * _mesh_rest_position
    start_rot_y = prev_global_rot_y + _mesh_rest_rotation_y

  interp_visual_tween = get_tree().create_tween()
  interp_visual_tween.set_ease(Tween.EASE_OUT)
  interp_visual_tween.set_trans(Tween.TRANS_QUAD)

  interp_visual_tween.tween_method(
    func(t: float) -> void:
      var target_global_pos := global_position + global_basis * _mesh_rest_position
      var target_global_rot_y := global_rotation.y + _mesh_rest_rotation_y
      var rot_delta := angle_difference(start_rot_y, target_global_rot_y)
      mesh.global_position = start_pos.lerp(target_global_pos, t)
      mesh.global_rotation.y = start_rot_y + rot_delta * t,
    0.0, 1.0, VISUAL_CORRECTION_DURATION)

func _physics_process(_delta: float) -> void:
  if interp_visual_tween == null or not interp_visual_tween.is_running():
    mesh.global_position = global_position + global_basis * _mesh_rest_position
    mesh.global_rotation.y = global_rotation.y + _mesh_rest_rotation_y

func _process(_delta: float) -> void:
  if Engine.is_editor_hint():
    return

func punch_cosmetic() -> void:
  get_tree().create_tween().tween_property(gumbot.spring_bone_sim, "influence", 0, 0.1)
  gumbot.anim_tree.set("parameters/PunchOneShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
  await gumbot.anim_tree.animation_finished
  await get_tree().create_timer(0.1).timeout
  get_tree().create_tween().tween_property(gumbot.spring_bone_sim, "influence", 1.0, 0.1)
