class_name GambaActionHandler
extends Node3D

@onready var gamba_machine: GambaMachine = %GambaMachine
@onready var gamba_end_pos: Node3D = %GambaEndPos
@onready var gamba_start_pos: Node3D = %GambaStartPos
@onready var gumbot: GumBot = %Gumbot
@onready var coin_spawn_box: CoinSpawnBox = %CoinSpawnBox
@onready var animation_player: AnimationPlayer = %AnimationPlayer
@onready var platform: Node3D = %Platform
@onready var winning_text_label: RichTextLabel = %WinningTextLabel
@onready var total_earnings_label: RichTextLabel = %TotalEarningsLabel

var _is_busy: bool = false
var total_earnings: int = 0:
  set(new_value):
    total_earnings = new_value
    var should_show_label := total_earnings > 0
    total_earnings_label.visible = should_show_label
    if should_show_label:
      total_earnings_label.text = "[color=green][font_size=100]+%d GUM[/font_size][/color]" % new_value

func _ready() -> void:
  gamba_machine.visible = false
  gumbot.visible = false
  total_earnings_label.visible = false
  gamba_machine.slot_reward_triggered.connect(_handle_show_slot_reward)
  coin_spawn_box.value_spawned.connect(_handle_value_added)

func _handle_value_added(value: int) -> void:
  total_earnings = total_earnings + value

func _handle_show_slot_reward(row_result: GambaMachine.RowResult, multiplier: int) -> void:
  var total_won := row_result.gumbucks() * multiplier
  winning_text_label.text = "\
  [shake][font_size=60][color=gold]%s[/color][/font_size]\\
  [font_size=50][color=green]+%d GUMBUCKS[/color][/font_size][/shake]" % [row_result.description(), total_won]
  animation_player.play("show_rewards_text")
  coin_spawn_box.spawn_coins(floor(float(total_won) / 1.0))
  await get_tree().create_timer(2.5).timeout
  animation_player.play_backwards("show_rewards_text")

func is_busy() -> bool:
  return _is_busy

func handle_action(action: Message.SlotsRequest, queue_manager: ActionQueueManager) -> void:
  _is_busy = true

  total_earnings = 0

  # Batch all pending slots actions for the same chatter
  var batch: Array[Message.SlotsRequest] = [action]
  var next = queue_manager.get_next_valid_action()
  while next != null and next is Message.SlotsRequest and next.chatter.id == action.chatter.id:
    queue_manager.complete_action(next)
    batch.append(next as Message.SlotsRequest)
    next = queue_manager.get_next_valid_action()

  gumbot.visible = true
  gumbot.chatter = action.chatter
  gumbot.bot_state = GumBot.BotState.Gambling
  gumbot.anim_tree.active = false

  gamba_machine.visible = true
  platform.global_position = gamba_start_pos.global_position
  gumbot.anim_player.play("StandIdle")

  var animate_in_tween := get_tree().create_tween()\
    .tween_property(platform, "global_position", gamba_end_pos.global_position, 1.0)\
    .set_ease(Tween.EaseType.EASE_OUT)\
    .set_trans(Tween.TransitionType.TRANS_CUBIC)
  
  await animate_in_tween.finished
  gumbot.anim_player.play("Gamba")

  var total_gumbucks_won: int = 0
  for slot_request in batch:
    total_gumbucks_won += await trigger_slot_spin(slot_request)
    total_gumbucks_won += await trigger_slot_spin(slot_request)
    total_gumbucks_won += await trigger_slot_spin(slot_request)
    total_gumbucks_won += await trigger_slot_spin(slot_request)
    total_gumbucks_won += await trigger_slot_spin(slot_request)
    total_gumbucks_won += await trigger_slot_spin(slot_request)
    total_gumbucks_won += await trigger_slot_spin(slot_request)
    total_gumbucks_won += await trigger_slot_spin(slot_request)
    WSClient.slots_activated(slot_request.uuid, total_gumbucks_won)

  gumbot.bot_state = GumBot.BotState.StandIdle

  await get_tree().create_timer(3.0).timeout
  coin_spawn_box.clear_coins()

  var animate_out_tween := get_tree().create_tween()\
    .tween_property(platform, "global_position", gamba_start_pos.global_position, 1.0)\
    .set_ease(Tween.EaseType.EASE_IN)\
    .set_trans(Tween.TransitionType.TRANS_CUBIC)
  await animate_out_tween.finished

  total_earnings = 0
  gamba_machine.visible = false
  _is_busy = false

func trigger_slot_spin(slot_request: Message.SlotsRequest) -> int:
  var win_amt: int = await gamba_machine.spin(slot_request.multiplier)
  if win_amt > 0:
    slot_request.chatter.balance += win_amt
    gumbot.chatter = slot_request.chatter

  return win_amt
