class_name GambaActionHandler
extends Node3D

@onready var gamba_machine: GambaMachine = %GambaMachine

var _gumbot_scene: PackedScene = preload("res://gumbot/gumbot.tscn")

var _is_busy: bool = false

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

	var bot: GumBot = _gumbot_scene.instantiate()
	add_child(bot)
	bot.position = Vector3(0.05, -0.32, -1.2)
	bot.chatter = action.chatter
	bot.bot_state = GumBot.BotState.Gambling

	gamba_machine.visible = true

	var total_gumbucks_won: int = 0
	for slot_request in batch:
		var spin_amt: int = await gamba_machine.spin(slot_request.multiplier)
		total_gumbucks_won += spin_amt
		if spin_amt > 0:
			slot_request.chatter.balance += spin_amt
			bot.chatter = slot_request.chatter
		WSClient.slots_activated(slot_request.uuid, total_gumbucks_won)

	bot.bot_state = GumBot.BotState.StandIdle
	await get_tree().create_timer(1.0).timeout

	bot.queue_free()
	gamba_machine.visible = false
	_is_busy = false
