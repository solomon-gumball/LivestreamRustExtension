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
@onready var gumbot: CarnageGumbot = %gumbot
@onready var punch_area: Area3D = %PunchArea

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

  # var input: Vector2 = physics_kart_movement_sync._sample_input().get("move", Vector2.ZERO)
  # smoke_amount_acc = lerpf(smoke_amount_acc, input.x, 3.0 * _delta)
  # smoke_fx_r.amount_ratio = smoke_amount_acc
  # smoke_fx_l.amount_ratio = smoke_amount_acc

func _integrate_forces(physics_state: PhysicsDirectBodyState3D) -> void:
  if not _has_pending_state:
    return
  physics_state.transform = _pending_transform
  physics_state.linear_velocity = _pending_linear_velocity
  physics_state.angular_velocity = _pending_angular_velocity
  _has_pending_state = false

var impact_bounce_fx_scene: PackedScene = preload("res://games/carnage/fx/impact_bounce_fx.tscn")

func trigger_impact_fx_at_location(location: Vector3) -> void:
  var bounce_fx: ImpactBounceFx = impact_bounce_fx_scene.instantiate() as ImpactBounceFx
  bounce_fx.global_position = location
  get_parent().add_child(bounce_fx)

func punch_cosmetic() -> void:
  get_tree().create_tween().tween_property(gumbot.spring_bone_sim, "influence", 0, 0.1)
  gumbot.anim_tree.set("parameters/PunchOneShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

  await gumbot.anim_tree.animation_finished
  await get_tree().create_timer(0.1).timeout
  get_tree().create_tween().tween_property(gumbot.spring_bone_sim, "influence", 1.0, 0.1)

func handle_punched_cosmetic() -> void:
  get_tree().create_tween().tween_property(gumbot.spring_bone_sim, "influence", 0.5, 0.1)
  gumbot.anim_tree.set("parameters/FlailOneShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
  await get_tree().create_timer(3.0).timeout
  gumbot.anim_tree.set("parameters/FlailOneShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
  get_tree().create_tween().tween_property(gumbot.spring_bone_sim, "influence", 1.0, 0.1)

func get_punched_karts(at_location: Vector3) -> Array[PhysicsKart]:
  var punched_karts: Array[PhysicsKart] = []
  var space_state := get_world_3d().direct_space_state

  var query := PhysicsShapeQueryParameters3D.new()
  query.shape = (punch_area.get_child(0) as CollisionShape3D).shape
  query.transform = Transform3D(punch_area.global_transform.basis, at_location)
  # var sphere_radius := (query.shape as SphereShape3D).radius if query.shape is SphereShape3D else 0.5
  # DebugDraw.draw_sphere(at_location, sphere_radius, Color.RED, 1.0)
  query.collision_mask = punch_area.collision_mask
  query.exclude = [get_rid()]

  for result in space_state.intersect_shape(query):
    var body: Object = result["collider"]
    if body is PhysicsKart:
      punched_karts.append(body)
  return punched_karts

func authority_handle_punch_impact(from_kart: PhysicsKart) -> void:
  var away := (global_position - from_kart.global_position).normalized()
  var tilt_axis := away.cross(Vector3.UP).normalized()
  var impulse := away.rotated(tilt_axis, deg_to_rad(45)) * 1.6
  var torque := -tilt_axis * 1.5
  MultiplayerClient.send_packet({
      "type": Carnage.CarnageGameMessage.HandleKartPunched,
      "owner_peer_id": physics_kart_movement_sync.owner_peer_id,
      "punch_location": from_kart.punch_area.global_position
    },
    MultiplayerPeer.TARGET_PEER_BROADCAST,
    MultiplayerPeer.TRANSFER_MODE_RELIABLE,
    MultiplayerClient.PacketSelfMode.SelfIncluded
  )
  physics_kart_movement_sync.apply_impulse(impulse)
  physics_kart_movement_sync.apply_torque_impulse(torque)
