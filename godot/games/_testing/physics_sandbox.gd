extends Node3D

@export var spawn_count: int = 10
@export var spawn_height: float = 5.0
@export var spawn_radius: float = 2.0
@export var spawn_interval: float = 0.3

@export var block_size: Vector3 = Vector3(0.3, 0.2, 0.4)
@export var block_mass: float = 5.0
@export var block_gravity: float = 9.8
@export var angular_damp: float = 0.5
@export var contact_angular_damp: float = 8.0
@export var surface_friction: float = 1.0
@export var collision_torque_scale: float = 0.2

var _spawned: int = 0
var _timer: float = 0.0

func _physics_process(delta: float) -> void:
	if _spawned >= spawn_count:
		return
	_timer += delta
	if _timer >= spawn_interval:
		_timer = 0.0
		_spawn_block()

func _spawn_block() -> void:
	var block := SimplePhysicsBlock.new()
	block.block_size = block_size
	block.block_mass = block_mass
	block.block_gravity = block_gravity
	block.angular_damp = angular_damp
	block.contact_angular_damp = contact_angular_damp
	block.surface_friction = surface_friction
	block.collision_torque_scale = collision_torque_scale

	add_child(block)

	var angle := randf() * TAU
	var radius := randf() * spawn_radius
	block.global_position = Vector3(
		cos(angle) * radius,
		spawn_height,
		sin(angle) * radius,
	)
	# Random initial rotation so blocks don't all land flat
	block.global_basis = Basis(
		Quaternion(Vector3(randf(), randf(), randf()).normalized(), randf() * TAU)
	)

	_spawned += 1
