@tool
extends Node3D
class_name GambaMachine

signal slot_reward_triggered(row: RowResult, multiplier: int)

@export var screen_1: MeshInstance3D
@export var screen_2: MeshInstance3D
@export var screen_3: MeshInstance3D

@onready var cog: MeshInstance3D = $Cog

@onready var base_anim_player: AnimationPlayer = $AnimationPlayer
@onready var slot_anim_player: AnimationPlayer = $SlotAnimationPlayer

@onready var machine_body: MeshInstance3D = $Armature/Skeleton3D/Body

var NumSlots: int = 16

enum Emoji {
  Burger = 0,
  Cookie = 1,
  IceCream = 2,
  Croissant = 3,
  Hotdog = 4,
  Cheese = 5,
  Juice = 6,
  Broccoli = 7,
  Fries = 8,
  Mushroom = 9,
  Salmon = 10,
  MiddleFinger = 11,
  HotPepper = 12,
  CheeseCake = 13,
  Bacon = 14,
  Apple = 15
}

static func description_for_icon(icon: Emoji) -> String:
  match icon:
    Emoji.Burger: return "Burger"
    Emoji.Cookie: return "Cookie"
    Emoji.IceCream: return "Ice Cream"
    Emoji.Croissant: return "Croissant"
    Emoji.Hotdog: return "Hotdog"
    Emoji.Cheese: return "Cheese"
    Emoji.Juice: return "Juice"
    Emoji.Broccoli: return "Broccoli"
    Emoji.Fries: return "Fries"
    Emoji.Mushroom: return "Mushroom"
    Emoji.Salmon: return "Salmon"
    Emoji.MiddleFinger: return "Middle Finger"
    Emoji.HotPepper: return "Hot Pepper"
    Emoji.CheeseCake: return "Cheese Cake"
    Emoji.Bacon: return "Bacon"
    Emoji.Apple: return "Apple"
  return "EMOJI NOT FOUND"


var slot_machine_light_mat: StandardMaterial3D = null
func _ready() -> void:
  screen_mat_1 = screen_1.get_active_material(0).duplicate()
  screen_mat_2 = screen_2.get_active_material(0).duplicate()
  screen_mat_3 = screen_3.get_active_material(0).duplicate()
  screen_1.set_surface_override_material(0, screen_mat_1)
  screen_2.set_surface_override_material(0, screen_mat_2)
  screen_3.set_surface_override_material(0, screen_mat_3)

  slot_machine_light_mat = machine_body.get_surface_override_material(1)

  screen_mat_1.set_shader_parameter("slots_order", slot_1_chars)
  screen_mat_2.set_shader_parameter("slots_order", slot_2_chars)
  screen_mat_3.set_shader_parameter("slots_order", slot_3_chars)

  base_anim_player.play("ArmsIdle")

  highlight_strength = 0.0


var screen_mat_1: ShaderMaterial = null
var screen_mat_2: ShaderMaterial = null
var screen_mat_3: ShaderMaterial = null

var slot_1_offset: float = 0.0:
  set(new_value):
    slot_1_offset = new_value
    screen_mat_1.set_shader_parameter("slot_offset", slot_1_offset)
var slot_2_offset: float = 0.0:
  set(new_value):
    slot_2_offset = new_value
    screen_mat_2.set_shader_parameter("slot_offset", slot_2_offset)
var slot_3_offset: float = 0.0:
  set(new_value):
    slot_3_offset = new_value
    screen_mat_3.set_shader_parameter("slot_offset", slot_3_offset)

var time_per_slot: float = 0.02
func spin_wheel(value: String, start_index: int) -> int:
  var target_slot: int = start_index - randi_range((NumSlots - 1) * 3, (NumSlots - 1) * 4)
  var target_slot_float = float(target_slot)
  get_tree().create_tween().tween_property(self, value, target_slot_float, abs(target_slot_float * time_per_slot))
  return target_slot

var highlight_strength: float = 0.0:
  set(new_value):
    highlight_strength = new_value
    screen_mat_1.set_shader_parameter("highlight_strength", new_value)
    screen_mat_2.set_shader_parameter("highlight_strength", new_value)
    screen_mat_3.set_shader_parameter("highlight_strength", new_value)

var highlights_visible = false
func toggle_highlights(in_visible: bool) -> void:
  if (highlights_visible == in_visible):
    return
  highlights_visible = in_visible
  await get_tree().create_tween().tween_property(self, "highlight_strength", 1.0 if in_visible else 0.0, 0.3).finished
  if !in_visible:
    screen_mat_1.set_shader_parameter("selected_slot", -1)
    screen_mat_2.set_shader_parameter("selected_slot", -1)
    screen_mat_3.set_shader_parameter("selected_slot", -1)

func trigger_pull_animation() -> void:
  slot_anim_player.play("slot_pull")
  base_anim_player.play("ArmsSwing")
  await base_anim_player.animation_finished
  base_anim_player.play("ArmsIdle")

var minor_win_sound: Resource = load("res://stream_overlay/gamba/slot-minor-winner.mp3")
var major_win_sound: Resource = load("res://stream_overlay/gamba/slot-big-winner.mp3")

func play_winning_sound(result: RowResult) -> void:
  var stream = major_win_sound if result.count == 3 else minor_win_sound
  var sound_player = $WinningSoundPlayer as AudioStreamPlayer3D
  ($WinningSoundPlayer as AudioStreamPlayer3D).stream = stream
  sound_player.volume_db = -30
  $WinningSoundPlayer.play()

func spin(multiplier: int) -> int:
  trigger_pull_animation()
  await get_tree().create_timer(0.6).timeout

  slot_1_offset = 0.0
  slot_2_offset = 0.0
  slot_3_offset = 0.0
  var first_index = spin_wheel("slot_1_offset", 0)
  var second_index = spin_wheel("slot_2_offset", first_index)
  var third_index = spin_wheel("slot_3_offset", second_index)

  await get_tree().create_timer(abs(time_per_slot * third_index)).timeout

  var top_left = (first_index - 1) % NumSlots
  var top_mid = (second_index - 1) % NumSlots
  var top_right = (third_index - 1) % NumSlots
  var center_left = (first_index) % NumSlots
  var center_mid = (second_index) % NumSlots
  var center_right = (third_index) % NumSlots
  var bottom_left = (first_index + 1) % NumSlots
  var bottom_mid = (second_index + 1) % NumSlots
  var bottom_right = (third_index + 1) % NumSlots

  var total_gumbucks_won = 0.0
  var top_row: RowResult = check_set(top_left, top_mid, top_right)
  if top_row != null:
    total_gumbucks_won += (top_row.gumbucks() * multiplier)
    await toggle_highlights(true)
    play_winning_sound(top_row)
    slot_reward_triggered.emit(top_row, multiplier)
    await get_tree().create_timer(2.0).timeout

  await toggle_highlights(false)
  var center_row: RowResult = check_set(center_left, center_mid, center_right)
  if center_row != null:
    total_gumbucks_won += center_row.gumbucks() * multiplier
    await toggle_highlights(true)
    play_winning_sound(center_row)
    slot_reward_triggered.emit(center_row, multiplier)
    await get_tree().create_timer(2.0).timeout

  await toggle_highlights(false)
  var bottom_row: RowResult = check_set(bottom_left, bottom_mid, bottom_right)
  if bottom_row != null:
    total_gumbucks_won += bottom_row.gumbucks() * multiplier
    await toggle_highlights(true)
    play_winning_sound(bottom_row)
    slot_reward_triggered.emit(bottom_row, multiplier)
    await get_tree().create_timer(2.0).timeout

  await toggle_highlights(false)
  var top_to_bot_diag: RowResult = check_set(top_left, center_mid, bottom_right)
  if top_to_bot_diag != null:
    total_gumbucks_won += top_to_bot_diag.gumbucks() * multiplier
    await toggle_highlights(true)
    play_winning_sound(top_to_bot_diag)
    slot_reward_triggered.emit(top_to_bot_diag, multiplier)
    await get_tree().create_timer(2.0).timeout

  await toggle_highlights(false)
  var bot_to_top_diag: RowResult = check_set(bottom_left, center_mid, top_right)
  if bot_to_top_diag != null:
    total_gumbucks_won += bot_to_top_diag.gumbucks() * multiplier
    await toggle_highlights(true)
    play_winning_sound(bot_to_top_diag)
    slot_reward_triggered.emit(bot_to_top_diag, multiplier)
    await get_tree().create_timer(2.0).timeout

  if total_gumbucks_won == 0:
    await get_tree().create_timer(1).timeout

  await toggle_highlights(false)
  # print(top_left, " ", top_mid, " ", top_right)
  # print(
  #   description_for_icon(slot_1_chars[first_index % NumSlots]), " ",
  #   description_for_icon(slot_2_chars[second_index % NumSlots]), " ",
  #   description_for_icon(slot_3_chars[third_index % NumSlots])
  # )

  screen_mat_1.set_shader_parameter("selected_slot", -1)
  screen_mat_2.set_shader_parameter("selected_slot", -1)
  screen_mat_3.set_shader_parameter("selected_slot", -1)

  return total_gumbucks_won

var time: float = 0.0
func _process(delta: float) -> void:  
  time = time + delta
  # screen_mat_1.set_shader_parameter("slot_offset", time)
  cog.rotation_degrees.x += delta * 90

class RowResult:
  var emoji: Emoji
  var count: int
  func gumbucks() -> int:
    var emoji_value = points_for_icon(emoji)
    return emoji_value * (3 if count == 3 else 1)
  
  func description() -> String:
    return "%sX %s" % [str(count), GambaMachine.description_for_icon(emoji)]

  static func From(in_emoji: Emoji, in_count: int) -> RowResult:
    var result = RowResult.new()
    result.emoji = in_emoji
    result.count = in_count
    return result
  
  static func points_for_icon(icon: Emoji) -> int:
    match icon:
      Emoji.Burger: return 8
      Emoji.Cookie: return 8
      Emoji.IceCream: return 10
      Emoji.Croissant: return 5
      Emoji.Hotdog: return 5
      Emoji.Cheese: return 4
      Emoji.Juice: return 6
      Emoji.Broccoli: return 2
      Emoji.Fries: return 8
      Emoji.Mushroom: return 3
      Emoji.Salmon: return 5
      Emoji.MiddleFinger: return 0
      Emoji.HotPepper: return 20
      Emoji.CheeseCake: return 15
      Emoji.Bacon: return 10
      Emoji.Apple: return 4
    return 0

func check_set(key_1: int, key_2: int, key_3: int) -> RowResult:
  var val_1: Emoji = slot_1_chars[key_1]
  var val_2: Emoji = slot_2_chars[key_2]
  var val_3: Emoji = slot_3_chars[key_3]

  var matching_val: Emoji = Emoji.Burger
  var slots_to_highlight: Array[bool] = [false, false, false]
  if val_1 == val_2 and val_2 == val_3:
    slots_to_highlight = [true, true, true]
    matching_val = val_1
  elif val_1 == val_2:
    slots_to_highlight = [true, true, false]
    matching_val = val_1
  elif val_2 == val_3:
    slots_to_highlight = [false, true, true]
    matching_val = val_2
  
  if slots_to_highlight[0]:
    screen_mat_1.set_shader_parameter("selected_slot", (NumSlots) + key_1 % NumSlots )
  else:
    screen_mat_1.set_shader_parameter("selected_slot", -1)
  if slots_to_highlight[1]:
    screen_mat_2.set_shader_parameter("selected_slot", (NumSlots) + key_2 % NumSlots )
  else:
    screen_mat_2.set_shader_parameter("selected_slot", -1)
  if slots_to_highlight[2]:
    screen_mat_3.set_shader_parameter("selected_slot", (NumSlots) + key_3 % NumSlots )
  else:
    screen_mat_3.set_shader_parameter("selected_slot", -1)

  if slots_to_highlight.has(true):
    var num_matched: int = slots_to_highlight.filter(func (x: bool): return x == true).size()
    # print("Scored %ix %s", num_matched, description_for_icon(matching_val))
    # await get_tree().create_timer(2).timeout
    return RowResult.From(matching_val, num_matched)
  
  return null

var slot_1_chars: Array[Emoji] = [
  Emoji.Cookie,
  Emoji.Cheese,
  Emoji.Salmon,
  Emoji.Croissant,
  Emoji.Burger,
  Emoji.Hotdog,
  Emoji.Apple,
  Emoji.Bacon,
  Emoji.CheeseCake,
  Emoji.IceCream,
  Emoji.HotPepper,
  Emoji.Fries,
  Emoji.Broccoli,
  Emoji.Mushroom,
  Emoji.MiddleFinger,
  Emoji.Juice,
]

var slot_2_chars: Array[Emoji] = [
  Emoji.Bacon,
  Emoji.Croissant,
  Emoji.Salmon,
  Emoji.HotPepper,
  Emoji.Cheese,
  Emoji.Hotdog,
  Emoji.Fries,
  Emoji.IceCream,
  Emoji.MiddleFinger,
  Emoji.Juice,
  Emoji.Cookie,
  Emoji.Apple,
  Emoji.CheeseCake,
  Emoji.Mushroom,
  Emoji.Burger,
  Emoji.Broccoli,
]

var slot_3_chars: Array[Emoji] = [
  Emoji.Burger,
  Emoji.Cookie,
  Emoji.IceCream,
  Emoji.Croissant,
  Emoji.Hotdog,
  Emoji.Cheese,
  Emoji.Juice,
  Emoji.Broccoli,
  Emoji.Fries,
  Emoji.Mushroom,
  Emoji.Salmon,
  Emoji.MiddleFinger,
  Emoji.HotPepper,
  Emoji.CheeseCake,
  Emoji.Bacon,
  Emoji.Apple,
]
