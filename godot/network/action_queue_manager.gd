class_name ActionQueueManager
extends Node

var _queue: Array[Message.QueueAction] = []

func _ready() -> void:
	WSClient.authenticated_state.store_data_received.connect(_on_store_data_received)
	WSClient.authenticated_state.message_received.connect(_on_message_received)

func _on_store_data_received() -> void:
	_queue = WSClient.authenticated_state.action_queue.duplicate()

func _on_message_received(message: Variant) -> void:
	match message.type:
		"action-queue-updated":
			_queue = Message.StoreData.CreateActionQueue(message.action_queue)
		"store-data":
			_queue = Message.StoreData.CreateActionQueue(message.get("action_queue", []))
	
	print("Updated action queue: ", message.type, "->", _queue.size())

func get_next_valid_action() -> Message.QueueAction:
	for action in _queue:
		return action
	return null

func complete_action(action: Message.QueueAction) -> void:
	WSClient.recently_completed_actions[action.uuid] = true
	_queue = _queue.filter(func(a): return a.uuid != action.uuid)
