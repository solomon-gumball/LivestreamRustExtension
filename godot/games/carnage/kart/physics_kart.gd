@tool
class_name PhysicsKart
extends RigidBody3D

@onready var physics_kart_movement_sync: PhysicsKartMovementSynchronizer = %PhysicsKartMovementSynchronizer

@onready var wheel_fl: PhysicsWheel = %Wheel_Front_Left
@onready var wheel_fr: PhysicsWheel = %Wheel_Front_Right
@onready var wheel_rl: PhysicsWheel = %Wheel_Back_Left
@onready var wheel_rr: PhysicsWheel = %Wheel_Back_Right
@onready var smoke_fx_r: GPUParticles3D = %SmokeFX_R
@onready var smoke_fx_l: GPUParticles3D = %SmokeFX_L

@export var wheel_turn: float = 0.0:
  set(v):
    wheel_turn = v
    if wheel_fl: wheel_fl.rotation.y = v
    if wheel_fr: wheel_fr.rotation.y = v

var _pending_linear_velocity := Vector3.ZERO
var _pending_angular_velocity := Vector3.ZERO
var _pending_transform := Transform3D.IDENTITY
var _has_pending_state := false

func _ready() -> void:
  custom_integrator = true
  gravity_scale = 0.0

func set_velocities(lv: Vector3, av: Vector3) -> void:
  _pending_linear_velocity = lv
  _pending_angular_velocity = av
  _pending_transform = Transform3D(global_basis, global_position)
  _has_pending_state = true

var smoke_amount_acc: float = 0.0
func _process(_delta: float) -> void:
  if Engine.is_editor_hint():
    DebugDraw.draw_sphere(to_global(get_center_of_mass()), 0.02, Color.ORANGE, 0.0)
    return

  var input: Vector2 = physics_kart_movement_sync._sample_input().get("move", Vector2.ZERO)
  smoke_amount_acc = lerpf(smoke_amount_acc, input.x, 3.0 * _delta)
  smoke_fx_r.amount_ratio = smoke_amount_acc
  smoke_fx_l.amount_ratio = smoke_amount_acc

func _integrate_forces(physics_state: PhysicsDirectBodyState3D) -> void:
  if not _has_pending_state:
    return
  physics_state.transform = _pending_transform
  physics_state.linear_velocity = _pending_linear_velocity
  physics_state.angular_velocity = _pending_angular_velocity
  _has_pending_state = false

