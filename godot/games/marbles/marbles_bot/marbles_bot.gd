extends RigidBody3D
class_name MarbleBot

#TODO: Fix chat bubbles

@onready var label_node: Node = %LabelNode
@onready var username_label: Label3D = %UsernameLabel
# @onready var chat_bubble: ChatBubble = $LabelNode/Chatbubble
@onready var bubble: MeshInstance3D = $MarblesBubble
@onready var follow_cam: Camera3D = $cam
@onready var emote_billboard: EmoteBillboard = %EmoteBillboard
@export var bubble_mat: StandardMaterial3D
@export var bubble_second_pass_mat: ShaderMaterial

enum BotState { Speaking, Walking, Grabbed, Gambling }
var state: = BotState.Gambling

func update_message(message: String) -> void:
  return
  # chat_bubble.show_message(message, chatter)

func _init() -> void:
  freeze = true
  freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
  contact_monitor = true
  can_sleep = false
  max_contacts_reported = 1

func _ready() -> void:
  if Engine.is_editor_hint():
    return

var show_username: bool = false:
  set(new_value):
    if new_value != show_username:
      if new_value:
        username_label.modulate = Color(1, 1, 1, 0)
        username_label.outline_modulate = Color(0, 0, 0, 0)
        var tween := create_tween()
        tween.tween_property(username_label, "modulate:a", 1.0, 0.5)
        tween.tween_property(username_label, "outline_modulate:a", 1.0, 0.5)
    
    show_username = new_value
    username_label.visible = new_value

var chatter: Chatter = null:
  set(new_value):
    # if is_inside_tree() && new_value != null:
    #   var mat = bubble_mat.duplicate() as StandardMaterial3D
    #   mat.albedo_color = Color.from_string(new_value.color, Color.RED)
    #   bubble.set_surface_override_material(1, mat)
    set_emote(new_value.emote)
    var bot_color := Color.from_string(new_value.color, Color.GREEN)
    bubble_mat.albedo_color = bot_color
    bubble_second_pass_mat.set_shader_parameter("color", bot_color)
    chatter = new_value

    username_label.text = chatter.display_name

func set_emote(emote_in: String) -> void:
  ImageLoader.load_emote(emote_in, func (image_tex: ImageTexture, _url: String) -> void:
    if image_tex != null:
      emote_billboard.emote_texture = image_tex
  )
  
var sync_state: MarblesGameState.MarbleState = null:
  set(new_value):
    if new_value:
      if freeze != new_value.frozen:
        # print(MultiplayerClient.my_peer_id(), ' is setting freeze -> ', new_value.frozen)
        freeze = new_value.frozen
    sync_state = new_value

func has_authority() -> bool:
  return MultiplayerClient.my_peer_id() == 1

const LERP_SPEED := 5.0
var acc_xz_velocity: Vector3 = Vector3.FORWARD
func _physics_process(_delta: float) -> void:
  if not has_authority() and sync_state != null:
    var real_delta := _delta / Engine.time_scale
    var dist := global_position.distance_to(sync_state.position)
    if dist > 2.0:
      global_position = sync_state.position
    else:
      global_position = global_position.lerp(sync_state.position, real_delta * LERP_SPEED)
    linear_velocity = linear_velocity.lerp(sync_state.linear_velocity, real_delta * LERP_SPEED)

    rotation = Vector3(
      lerp_angle(rotation.x, sync_state.rotation.x, real_delta * LERP_SPEED),
      lerp_angle(rotation.y, sync_state.rotation.y, real_delta * LERP_SPEED),
      lerp_angle(rotation.z, sync_state.rotation.z, real_delta * LERP_SPEED)
    )

