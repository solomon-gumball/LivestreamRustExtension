@tool
extends Node3D
class_name PongPaddle

const MAX_SPEED = 4.0
const MAX_RANGE = 2.0
const ACCELERATION = 0.2
const DECELERATION = 5.0

const START_WIDTH = 0.7
const PADDLE_SHRINK_PER_SECOND = 0.01
const MIN_PADDLE_WIDTH = 0.25

var round_started_at: float = 0.0
var paddle_width := START_WIDTH:
  set(new_width):
    paddle_width = new_width
    paddle_mesh_box.size.x = new_width
    paddle_collision_box.size.x = new_width

var peer_id: int
var chatter: Chatter:
  set(new_chatter):
    gumbot.chatter = new_chatter
    chatter = new_chatter

var chatter_id: String
var velocity: Vector3 = Vector3.ZERO

@export var paddle_mesh_box: BoxMesh
@export var paddle_collision_box: BoxShape3D

@onready var paddle_collision_shape: CollisionShape3D = %PaddleCollisionShape
@onready var paddle_mesh: Node3D = %PaddleMesh
@onready var gumbot: GumBot = %GumBot
@onready var collision_body: StaticBody3D = %PaddleCollisionArea
@export var gumbot_walk_speed = 0.0:
  set(new_value):
    gumbot_walk_speed = new_value
    gumbot.anim_tree.set("parameters/StateMachine/Walking/blend_position", new_value)

enum GumbotAnimState { Taunt, Walking, Pong }
@export var gumbot_animation_state = GumbotAnimState.Pong:
  set(new_value):
    gumbot_animation_state = new_value
    var sm_playback: AnimationNodeStateMachinePlayback = gumbot.anim_tree.get("parameters/StateMachine/playback")
    sm_playback.travel(GumbotAnimState.keys()[gumbot_animation_state])

    paddle_mesh.visible = gumbot_animation_state == GumbotAnimState.Pong
    gumbot.show_name_label = gumbot_animation_state != GumbotAnimState.Pong

func _ready() -> void:
  sync_state = PongEntity.new()
  sync_state.position = position
  sync_state.velocity = velocity
  paddle_width = paddle_width

var movement_input: Vector2 = Vector2.ZERO
func add_movement_input(direction: Vector2) -> void:
  movement_input = direction

func has_authority():
  return sync_state.owner == MultiplayerClient.my_peer_id()

var sync_state: PongEntity:
  set(new_state):
    sync_state = new_state
    # paddle_collision_shape.disabled = !has_authority()

func _phys_move(delta: float) -> void:
  position += velocity * delta
  position.x = clamp(position.x, -MAX_RANGE, MAX_RANGE)
  movement_input = Vector2.ZERO

func _physics_process(delta: float) -> void:
  if Engine.is_editor_hint(): return
  if gumbot_animation_state != GumbotAnimState.Pong: return

  if has_authority():
    var accel = movement_input.y * ACCELERATION
    velocity.x += accel
    velocity.x = clamp(velocity.x, -MAX_SPEED, MAX_SPEED)

    if movement_input.y == 0:
      velocity.x = lerpf(velocity.x, 0.0, delta * DECELERATION)

  else:
    position = lerp(position, sync_state.position, delta * 10.0)
    velocity = lerp(velocity, sync_state.velocity, delta * 10.0)
  
  _phys_move(delta)
  var seconds_since_round_start := Time.get_unix_time_from_system() - round_started_at
  paddle_width = max(MIN_PADDLE_WIDTH, START_WIDTH - seconds_since_round_start * PADDLE_SHRINK_PER_SECOND)

  if has_authority():
    MultiplayerClient.send_packet({
      "type": PongGame.PongGameMessage.PaddleMove,
      "position": position,
      "velocity": velocity
    },
    MultiplayerPeer.TARGET_PEER_BROADCAST,
    MultiplayerPeer.TRANSFER_MODE_UNRELIABLE,
    true
  )
