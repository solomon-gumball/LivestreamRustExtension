extends RigidBody3D
class_name MarbleBot

#TODO: Fix chat bubbles

@onready var label_node: Node = $LabelNode
@onready var username_label: Node = $LabelNode/Label3D
# @onready var chat_bubble: ChatBubble = $LabelNode/Chatbubble
@onready var bubble: MeshInstance3D = $MarblesBubble
@onready var follow_cam: Camera3D = $cam
@onready var emote_billboard: EmoteBillboard = %EmoteBillboard
@export var bubble_mat: StandardMaterial3D

enum BotState { Speaking, Walking, Grabbed, Gambling }
var state: = BotState.Gambling
var frozen: bool = true:
  set(new_value):
    freeze = new_value

func update_message(message: String) -> void:
  return
  # chat_bubble.show_message(message, chatter)

var chatter: Chatter = null:
  set(new_value):
    if is_inside_tree() && new_value != null:
      set_emote(new_value.emote)
      username_label.text = new_value.display_name
      var mat = bubble_mat.duplicate() as StandardMaterial3D
      mat.albedo_color = Color.from_string(new_value.color, Color.RED)
      bubble.set_surface_override_material(1, mat)
      # var sphere_mat = (sphere.material as StandardMaterial3D).duplicate()
      # # sphere_mat.albedo_color = Color.from_string(new_value.color, Color.RED)
      # sphere_mat.albedo_color.a = .5
      # sphere.material = sphere_mat

    chatter = new_value

func set_emote(emote_in: String) -> void:
  var image_tex = await ImageLoader.load_emote(emote_in)
  if image_tex != null:
    # var sphere_mat = (sphere.material as StandardMaterial3D).duplicate()
    # sphere_mat.albedo_texture = image_tex
    # sphere.material = sphere_mat
    $Sprite3D.texture = image_tex

var sync_state: MarblesGameState.MarbleState = null

func has_authority() -> bool:
  return MultiplayerClient.my_peer_id() == 1

var acc_xz_velocity: Vector3 = Vector3.FORWARD
func _physics_process(_delta: float) -> void:
  if not has_authority() and sync_state != null:
    global_position = global_position.lerp(sync_state.position, _delta * 10.0)
    rotation = Vector3(
      lerp_angle(rotation.x, sync_state.rotation.x, _delta * 10.0),
      lerp_angle(rotation.y, sync_state.rotation.y, _delta * 10.0),
      lerp_angle(rotation.z, sync_state.rotation.z, _delta * 10.0)
    )

  # var xz_velocity = Vector3(linear_velocity.x, 0, linear_velocity.z)
  # if xz_velocity.length() > 0.001:
  #   acc_xz_velocity = acc_xz_velocity.lerp(xz_velocity.normalized(), _delta * 1.0).normalized()
  #   follow_cam.global_position = global_position + acc_xz_velocity * -5.0
  #   follow_cam.global_position.y += 4.0
  #   follow_cam.look_at(global_position, Vector3.UP)

  #   label_node.global_position = global_position + Vector3(0, 0.35, 0)
