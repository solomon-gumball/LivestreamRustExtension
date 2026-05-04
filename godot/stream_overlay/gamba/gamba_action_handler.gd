class_name GambaActionHandler
extends Node3D

@onready var gamba_machine: GambaMachine = %GambaMachine
@onready var gamba_end_pos: Node3D = %GambaEndPos
@onready var gamba_start_pos: Node3D = %GambaStartPos
@onready var gumbot: GumBot = %Gumbot
@onready var coin_spawn_box: CoinSpawnBox = %CoinSpawnBox
@onready var animation_player: AnimationPlayer = %AnimationPlayer
@onready var platform: Node3D = %Platform

var _is_busy: bool = false

func _ready() -> void:
	gamba_machine.visible = false
	gumbot.visible = false

	coin_spawn_box.spawn_coins(10)

func is_busy() -> bool:
	return _is_busy

func handle_action(action: Message.SlotsRequest, queue_manager: ActionQueueManager) -> void:
	_is_busy = true

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
		var win_amt: int = await gamba_machine.spin(slot_request.multiplier)
		total_gumbucks_won += win_amt
		if win_amt > 0:
			slot_request.chatter.balance += win_amt
			gumbot.chatter = slot_request.chatter
			await coin_spawn_box.spawn_coins(floor(float(win_amt) / 1.0))
		WSClient.slots_activated(slot_request.uuid, total_gumbucks_won)

	gumbot.bot_state = GumBot.BotState.StandIdle
	await get_tree().create_timer(1.0).timeout

	var animate_out_tween := get_tree().create_tween()\
		.tween_property(platform, "global_position", gamba_start_pos.global_position, 1.0)\
		.set_ease(Tween.EaseType.EASE_IN)\
		.set_trans(Tween.TransitionType.TRANS_CUBIC)
	await animate_out_tween.finished

	gamba_machine.visible = false
	_is_busy = false
