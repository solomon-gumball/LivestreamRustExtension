class_name SimplePhysicsBlock
extends RigidBody3D

@export var block_size: Vector3 = Vector3(0.3, 0.2, 0.4)
@export var block_mass: float = 5.0
@export var block_gravity: float = 9.8
@export var rotational_damp: float = 0.5
@export var contact_angular_damp: float = 8.0
@export var surface_friction: float = 3.0
@export var collision_torque_scale: float = 0.2
@export var collision_restitution: float = 0.3

var _linear_vel := Vector3.ZERO
var _angular_vel := Vector3.ZERO

var _inertia := Vector3.ONE
var _box_shape: BoxShape3D
var _collision_shape: CollisionShape3D

var _pending_linear_velocity := Vector3.ZERO
var _pending_angular_velocity := Vector3.ZERO
var _pending_transform := Transform3D.IDENTITY
var _has_pending_state := false

func _ready() -> void:
	custom_integrator = true
	gravity_scale = 0.0

	_box_shape = BoxShape3D.new()
	_box_shape.size = block_size

	_collision_shape = CollisionShape3D.new()
	_collision_shape.shape = _box_shape
	add_child(_collision_shape)

	var mesh_instance := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = block_size
	mesh_instance.mesh = box_mesh
	add_child(mesh_instance)

	_precompute_inertia()

func _precompute_inertia() -> void:
	var w := block_size.x
	var h := block_size.y
	var d := block_size.z
	_inertia = Vector3(
		block_mass * (h * h + d * d) / 12.0,
		block_mass * (w * w + d * d) / 12.0,
		block_mass * (w * w + h * h) / 12.0,
	)

func _integrate_forces(physics_state: PhysicsDirectBodyState3D) -> void:
	if not _has_pending_state:
		return
	physics_state.transform = _pending_transform
	physics_state.linear_velocity = _pending_linear_velocity
	physics_state.angular_velocity = _pending_angular_velocity
	_has_pending_state = false

func _physics_process(_delta: float) -> void:
	_step(1.0 / 60.0)

func _step(delta: float) -> void:
	var position := global_position
	var basis := global_basis

	_linear_vel += Vector3.DOWN * block_gravity * delta
	_angular_vel *= clampf(1.0 - rotational_damp * delta, 0.0, 1.0)

	var angle := _angular_vel.length()
	if angle > 0.0001:
		var rot_q := Quaternion(_angular_vel / angle, angle * delta)
		basis = Basis(rot_q * Quaternion(basis)).orthonormalized()

	var params := PhysicsTestMotionParameters3D.new()
	params.from = Transform3D(basis, position)
	params.motion = _linear_vel * delta

	var result := PhysicsTestMotionResult3D.new()
	if PhysicsServer3D.body_test_motion(get_rid(), params, result):
		var normal := result.get_collision_normal()
		var contact_point := result.get_collision_point()
		position += result.get_travel()

		var flatness := normal.dot(Vector3.UP)

		# Full rigid-body impulse: accounts for spin contribution to contact velocity.
		# v_contact = linear_vel + angular_vel × r  (r = contact point offset from CoM)
		# j = -(1+e)*dot(v_contact, n) / (1/m + dot(n, (I⁻¹(r×n))×r))
		# Then: Δlinear = j*n/m,  Δangular = I⁻¹(r × j*n)
		var r := contact_point - position
		var v_contact := _linear_vel + _angular_vel.cross(r)
		var v_along_normal := v_contact.dot(normal)

		if v_along_normal < 0.0:
			var r_cross_n := r.cross(normal)
			var r_cross_n_local := basis.inverse() * r_cross_n
			var i_inv_r_cross_n_local := Vector3(
				r_cross_n_local.x / _inertia.x,
				r_cross_n_local.y / _inertia.y,
				r_cross_n_local.z / _inertia.z,
			)
			var i_inv_r_cross_n := basis * i_inv_r_cross_n_local
			var angular_denom := normal.dot(i_inv_r_cross_n.cross(r))
			var j: float = -(1.0 + collision_restitution) * v_along_normal / (1.0 / block_mass + angular_denom)
			var impulse: Vector3 = normal * j
			_linear_vel += impulse / block_mass
			var delta_av_local := basis.inverse() * r.cross(impulse)
			_angular_vel += basis * Vector3(
				delta_av_local.x / _inertia.x,
				delta_av_local.y / _inertia.y,
				delta_av_local.z / _inertia.z,
			)

		_linear_vel = _linear_vel.slide(normal)

		if flatness > 0.3:
			_linear_vel *= clampf(1.0 - surface_friction * flatness * delta, 0.0, 1.0)
			# Decompose into spin-around-normal (carousel) and roll-along-surface,
			# then damp both. Squaring the factor for spin makes it decay faster —
			# a spinning top on a surface loses carousel spin much faster than rolling.
			var damp_factor := clampf(1.0 - contact_angular_damp * flatness * delta, 0.0, 1.0)
			var spin_component := normal * _angular_vel.dot(normal)
			var roll_component := _angular_vel - spin_component
			_angular_vel = roll_component * damp_factor + spin_component * damp_factor * damp_factor

		var remainder := result.get_remainder()
		if remainder.length() > 0.001:
			params.from = Transform3D(basis, position)
			params.motion = remainder
			var remainder_result := PhysicsTestMotionResult3D.new()
			if PhysicsServer3D.body_test_motion(get_rid(), params, remainder_result):
				position += remainder_result.get_travel()
				_linear_vel = _linear_vel.slide(remainder_result.get_collision_normal())
			else:
				position += remainder

		if normal.dot(Vector3.UP) > 0.7:
			_linear_vel.y = 0.0
	else:
		position += _linear_vel * delta

	global_position = position
	global_basis = basis
	_pending_transform = Transform3D(basis, position)
	_pending_linear_velocity = _linear_vel
	_pending_angular_velocity = _angular_vel
	_has_pending_state = true
