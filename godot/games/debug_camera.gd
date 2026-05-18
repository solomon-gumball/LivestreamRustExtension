extends CharacterBody3D
class_name DebugCamera

@export var move_speed: float = 10.0
@export var fast_move_speed: float = 50.0
@export var look_speed: float = 1.0
@export_range(0.0, 1.0) var look_smoothing: float = 0.5
@export var allow_free_cam: bool = true
@export var follow_click_collision_mask: int = 2
@onready var collision_shape_cast: ShapeCast3D = %ShapeCast

var _yaw: float = 0.0
var _pitch: float = 0.0

var _state: StateMachine
var _free_state: FreeState
var _follow_state: FollowState

@warning_ignore("UNUSED_SIGNAL") signal did_enter_free_cam()
@warning_ignore("UNUSED_SIGNAL") signal did_enter_follow_cam(follow_node: Node3D)

func _ready() -> void:
  _yaw = global_rotation.y
  _pitch = global_rotation.x
  _init_input_actions()

  _state = StateMachine.new()
  _free_state = FreeState.new(self)
  _follow_state = FollowState.new(self)

  add_child(_state)
  _state.add_child(_free_state)
  _state.add_child(_follow_state)
  _state.change_state(_free_state)

func _unhandled_input(event: InputEvent) -> void:
  if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
    if follow_click_collision_mask != 0:
      var hit := _raycast_node_at(event.position)
      if hit != null:
        enter_follow_mode(hit)
        did_enter_follow_cam.emit(hit)
        return
  _state.input_state(event)

func _raycast_node_at(screen_pos: Vector2) -> Node3D:
  var viewport_cam := get_viewport().get_camera_3d()
  var origin := viewport_cam.project_ray_origin(screen_pos)
  var direction := viewport_cam.project_ray_normal(screen_pos)
  var space := get_world_3d().direct_space_state
  var shape := SphereShape3D.new()
  shape.radius = 0.4
  var cast_query := PhysicsShapeQueryParameters3D.new()
  cast_query.shape = shape
  cast_query.transform = Transform3D(Basis.IDENTITY, origin)
  cast_query.motion = direction * 1000.0
  cast_query.collision_mask = follow_click_collision_mask
  var result := space.cast_motion(cast_query)
  if result[0] >= 1.0:
    return null
  var hit_pos := origin + direction * 1000.0 * result[1]
  var hit_query := PhysicsShapeQueryParameters3D.new()
  hit_query.shape = shape
  hit_query.transform = Transform3D(Basis.IDENTITY, hit_pos)
  hit_query.collision_mask = follow_click_collision_mask
  var hits := space.intersect_shape(hit_query)
  if hits.size() > 0 and hits[0].collider is Node3D:
    return hits[0].collider as Node3D
  return null

func enter_follow_mode(node_to_follow: Node3D, pitch: float = NAN) -> void:
  _follow_state.set_target(node_to_follow, pitch)
  _state.change_state(_follow_state)

func set_default_orbit_distance(new_distance: float) -> void:
  _follow_state.default_orbit_distance = new_distance

func enter_free_mode() -> void:
  _state.change_state(_free_state)
  did_enter_free_cam.emit()

func snap_to_camera(source: Camera3D) -> void:
  global_transform = source.global_transform
  var forward := global_transform.basis * Vector3.FORWARD
  _yaw = atan2(-forward.x, -forward.z)
  _pitch = asin(clamp(forward.y, -1.0, 1.0))
  _pitch = clamp(_pitch, deg_to_rad(-89.0), deg_to_rad(89.0))

func _exit_tree() -> void:
  for action in ["move_forward", "move_back", "move_right", "move_left"]:
    if InputMap.has_action(action):
      InputMap.erase_action(action)

func _init_input_actions() -> void:
  if InputMap.has_action("move_forward"):
    return
  InputMap.add_action("move_forward")
  InputMap.add_action("move_back")
  InputMap.add_action("move_right")
  InputMap.add_action("move_left")

  var move_forward_event := InputEventKey.new()
  move_forward_event.physical_keycode = KEY_W
  InputMap.action_add_event("move_forward", move_forward_event)

  var joy_forward_event := InputEventJoypadMotion.new()
  joy_forward_event.axis = JOY_AXIS_LEFT_Y
  joy_forward_event.axis_value = -1.0
  InputMap.action_add_event("move_forward", joy_forward_event)

  var right_move_event := InputEventKey.new()
  right_move_event.physical_keycode = KEY_A
  InputMap.action_add_event("move_left", right_move_event)

  var joy_left_event := InputEventJoypadMotion.new()
  joy_left_event.axis = JOY_AXIS_LEFT_X
  joy_left_event.axis_value = -1.0
  InputMap.action_add_event("move_left", joy_left_event)

  var move_back_event := InputEventKey.new()
  move_back_event.physical_keycode = KEY_S
  InputMap.action_add_event("move_back", move_back_event)

  var joy_back_event := InputEventJoypadMotion.new()
  joy_back_event.axis = JOY_AXIS_LEFT_Y
  joy_back_event.axis_value = 1.0
  InputMap.action_add_event("move_back", joy_back_event)

  var move_right_event := InputEventKey.new()
  move_right_event.physical_keycode = KEY_D
  InputMap.action_add_event("move_right", move_right_event)

  var joy_right_event := InputEventJoypadMotion.new()
  joy_right_event.axis = JOY_AXIS_LEFT_X
  joy_right_event.axis_value = 1.0
  InputMap.action_add_event("move_right", joy_right_event)

class DebugCameraState extends State:
  var cam: DebugCamera
  func _init(_cam: DebugCamera) -> void:
    cam = _cam

class FreeState extends DebugCameraState:
  var mouse_sensitivity: float = 0.001
  var _mouse_delta: Vector2 = Vector2.ZERO
  var _smoothed_delta: Vector2 = Vector2.ZERO

  func enter_state(_previous_state: State) -> void:
    var forward := cam.global_transform.basis * Vector3.FORWARD
    cam._yaw = atan2(-forward.x, -forward.z)
    cam._pitch = asin(clamp(forward.y, -1.0, 1.0))
    cam._pitch = clamp(cam._pitch, deg_to_rad(-89.0), deg_to_rad(89.0))

  func handle_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
      if event.pressed:
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
      else:
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
      _mouse_delta += event.relative

  func physics_update(delta: float) -> void:
    _smoothed_delta = _smoothed_delta.lerp(_mouse_delta, 1.0 - cam.look_smoothing)
    _mouse_delta = Vector2.ZERO
    if _smoothed_delta.length_squared() > 0.00001:
      cam._yaw -= _smoothed_delta.x * mouse_sensitivity
      cam._pitch -= _smoothed_delta.y * mouse_sensitivity
      cam._pitch = clamp(cam._pitch, deg_to_rad(-89.0), deg_to_rad(89.0))

    cam.global_basis = Basis(Quaternion(Vector3.UP, cam._yaw) * Quaternion(Vector3.RIGHT, cam._pitch))

    var speed := 100.0
    var direction := Vector3.ZERO
    direction -= cam.global_basis.z * float(Input.is_action_pressed("move_forward"))
    direction += cam.global_basis.z * float(Input.is_action_pressed("move_back"))
    direction -= cam.global_basis.x * float(Input.is_action_pressed("move_left"))
    direction += cam.global_basis.x * float(Input.is_action_pressed("move_right"))
    direction += Vector3.UP * float(Input.is_key_pressed(KEY_E))
    direction -= Vector3.UP * float(Input.is_key_pressed(KEY_Q))

    if direction.length_squared() > 0.001:
      direction = direction.normalized()
      cam.velocity += direction * speed * delta
    else:
      cam.velocity = cam.velocity.move_toward(Vector3.ZERO, 100.0 * delta)

    cam.velocity = cam.velocity.limit_length(20.0)
    cam.move_and_slide()

class FollowState extends DebugCameraState:
  const TRANSITION_DURATION: float = 0.5
  const MIN_DISTANCE: float = 0.5
  const ZOOM_RECOVER_SPEED: float = 2.0

  var default_orbit_distance: float = 5.0
  var invert_pitch: bool = true
  var prevent_wall_clip: bool = false
  var move_lerp: float = 10.0
  var lock_pitch: bool = false

  var target: Node3D = null

  func set_target(value: Node3D, pitch: float = NAN) -> void:
    if value == target:
      return
    _t = 0.0
    var had_target := is_instance_valid(target)
    _from_target = target if had_target else null
    _from_transform = cam.global_transform
    target = value
    if not is_instance_valid(target):
      return
    orbit_distance = default_orbit_distance
    _current_distance = orbit_distance
    if not is_nan(pitch):
      cam._pitch = clamp(pitch, deg_to_rad(-89.0), deg_to_rad(89.0))
    elif not had_target:
      var forward := cam.global_transform.basis * Vector3.FORWARD
      cam._yaw = atan2(-forward.x, -forward.z)
      cam._pitch = asin(clamp(-forward.y, -1.0, 1.0))
      cam._pitch = clamp(cam._pitch, deg_to_rad(-89.0), deg_to_rad(89.0))
    _lerped_position = target.global_position if is_instance_valid(target) else Vector3.ZERO

  var orbit_distance: float = default_orbit_distance
  var _current_distance: float = 5.0
  var _t: float = 1.0
  var _from_target: Node3D = null
  var _from_transform: Transform3D
  var _lerped_position: Vector3 = Vector3.ZERO

  func enter_state(_previous_state: State) -> void:
    pass

  func exit_state() -> void:
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    target = null

  var mouse_sensitivity: float = 0.001
  var _mouse_delta: Vector2 = Vector2.ZERO
  var _smoothed_delta: Vector2 = Vector2.ZERO

  func handle_input(event: InputEvent) -> void:
    if Input.is_action_pressed("move_forward") \
    or Input.is_action_pressed("move_back") \
    or Input.is_action_pressed("move_left") or \
    Input.is_action_pressed("move_right"):
      if cam.allow_free_cam:
        cam.enter_free_mode()

    if event is InputEventMouseButton:
      if event.button_index == MOUSE_BUTTON_LEFT:
        if event.pressed:
          Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
        else:
          Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
      elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
        orbit_distance = max(MIN_DISTANCE, orbit_distance - 0.5)
      elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
        orbit_distance += 0.5

    if event is InputEventPanGesture:
      orbit_distance = max(MIN_DISTANCE, orbit_distance + event.delta.y * 0.1)

    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
      _mouse_delta += event.relative

  func _compute_safe_distance(orbit_dir: Vector3) -> float:
    var space := cam.get_world_3d().direct_space_state
    var from := target.global_position
    var to := from + orbit_dir * orbit_distance
    var query := PhysicsRayQueryParameters3D.create(from, to)
    query.collision_mask = 1
    query.exclude = [cam.get_rid()]
    var result := space.intersect_ray(query)
    if result:
      # DebugDraw.draw_line(result.position, to, Color.YELLOW)
      var hit_dist := from.distance_to(result.position)
      return maxf(hit_dist, MIN_DISTANCE)
    # DebugDraw.draw_line(from, to, Color.GREEN)
    return orbit_distance

  func physics_update(delta: float) -> void:
    if not is_instance_valid(target):
      return

    _smoothed_delta = _smoothed_delta.lerp(_mouse_delta, 1.0 - cam.look_smoothing)
    _mouse_delta = Vector2.ZERO
    if _smoothed_delta.length_squared() > 0.00001:
      var pitch_sign := 1.0 if invert_pitch else -1.0
      cam._yaw -= _smoothed_delta.x * mouse_sensitivity
      if not lock_pitch:
        cam._pitch += _smoothed_delta.y * mouse_sensitivity * pitch_sign
        cam._pitch = clamp(cam._pitch, deg_to_rad(-89.0), deg_to_rad(89.0))

    if move_lerp > 0.0:
      _lerped_position = _lerped_position.lerp(target.global_position, move_lerp * delta)
    else:
      _lerped_position = target.global_position

    var orbit_dir := Vector3(
      sin(cam._yaw) * cos(cam._pitch),
      sin(cam._pitch),
      cos(cam._yaw) * cos(cam._pitch)
    )

    var safe_distance := orbit_distance
    if prevent_wall_clip:
      safe_distance = _compute_safe_distance(orbit_dir)

    if safe_distance < _current_distance:
      _current_distance = safe_distance
    else:
      _current_distance = lerpf(_current_distance, safe_distance, ZOOM_RECOVER_SPEED * delta)

    var orbit_position := _lerped_position + orbit_dir * _current_distance
    var orbit_transform := Transform3D(cam.global_transform.basis, orbit_position)
    orbit_transform = orbit_transform.looking_at(_lerped_position, Vector3.UP)

    if _t < 1.0:
      _t = minf(_t + delta / TRANSITION_DURATION, 1.0)
      var from_transform := _from_transform
      if is_instance_valid(_from_target):
        var from_pos := _from_target.global_position + orbit_dir * _current_distance
        from_transform = Transform3D(cam.global_transform.basis, from_pos)
        from_transform = from_transform.looking_at(_from_target.global_position, Vector3.UP)
      cam.global_transform = from_transform.interpolate_with(orbit_transform, ease(_t, -2.0))
    else:
      _from_target = null
      cam.global_transform = orbit_transform

    cam.velocity = Vector3.ZERO
