class_name GumbotWanderingState
extends StreamOverlayGumBotState

var speed_multiplier: float = 1.0
var target_destination: Vector3 = Vector3.ZERO

func _get_acceleration_scale():
  return .02 * speed_multiplier

func enter_state(_previous_state: State) -> void:
  bot.show_name_label = true
  var playback: AnimationNodeStateMachinePlayback = bot.anim_tree.get("parameters/StateMachine/playback")
  playback.travel("Locomotion")
  patrol_loop()

func exit_state() -> void:
  pass

func _pick_random_point():
  var nav_map = bot.nav_agent.get_navigation_map()
  var random_location = NavigationServer3D.map_get_random_point(nav_map, 1, true)
  return random_location

func patrol_loop():
  if !is_inside_tree(): return
  var random_point = _pick_random_point()
  bot.debug_cube.global_position = random_point

  bot.nav_agent.set_target_position(random_point)

  await bot.nav_agent.target_reached
  await get_tree().create_timer(1).timeout
  patrol_loop()

var push_force: float = 1
var MAX_GROUND_SPEED: float = 0.4
var jump_queued: bool = false

func _physics_process(_delta: float) -> void:
  var begin_pos = bot.global_position
  if !bot.nav_agent.is_target_reached() && bot.is_on_floor():
    var destination = bot.nav_agent.get_next_path_position()
    var move = destination - bot.global_position
    var direction_to_move = move.normalized()
    bot.velocity += direction_to_move * _get_acceleration_scale()

  bot.velocity += bot.get_gravity() * _delta * 1

  var xz_vel = Vector2(bot.velocity.x, bot.velocity.z)

  # Decelerate on the floor
  if bot.is_on_floor() && (bot.nav_agent.is_target_reached() || xz_vel.length() > MAX_GROUND_SPEED):
    xz_vel *= .9
    # print(xz_vel.length())

  var y_vel = clamp(bot.velocity.y, -15, 15)
  bot.velocity = Vector3(xz_vel.x, y_vel, xz_vel.y)

  if jump_queued:
    bot.velocity.y = 6

  if bot.move_and_slide():
    var collision = bot.get_last_slide_collision()
    var collider = collision.get_collider()
    if collider is GumBot:
      var other_bot := collider as GumBot
      # if !other_bot.is_invincible():
      var impulse = other_bot.global_position - bot.global_position
      impulse.y = 0
      impulse = impulse.normalized() * 1.5 * bot.scale.x
      impulse.y = 2 * bot.scale.x
      collider.velocity = impulse

    # elif collider is GumDrop:
    #   var gum_drop = collider as GumDrop
    #   gum_drop.handle_collected(self)
    # elif collider is RigidBody3D:
    #   var other_body = collider as RigidBody3D
    #   other_body.apply_impulse(-collision.get_normal() * push_force, collision.get_position() - other_body.global_position)

  update_locomotion_blend_pos()

  var delta_move: Vector3 = bot.global_position - begin_pos
  if bot.is_on_floor():
    var direction_moved = delta_move.normalized()
    var target_basis = Util.basis_from_axis(-Vector3(direction_moved.x, 0, direction_moved.z).normalized(), Util.Axis.FORWARD)
    bot.quaternion = bot.quaternion.slerp(target_basis.get_rotation_quaternion(), .1)
  
  jump_queued = false

func update_locomotion_blend_pos() -> void:
  if !Engine.is_editor_hint():
    bot.anim_tree.set("parameters/StateMachine/Locomotion/blend_position", bot.velocity.length())
