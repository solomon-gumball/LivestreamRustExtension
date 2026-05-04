extends Node3D
class_name GumbuckSpawner

var drop_size: Vector2 = Vector2(3.0, 1.2)
var dropped_coins: Array[RigidBody3D] = []
var dropped_stacks: Array[RigidBody3D] = []

# func _ready() -> void:
#   await get_tree().create_timer(1).timeout
#   Network.drops_triggered.connect(on_drops_triggered)
#   Network.store_data_received.connect(on_drops_triggered)
  
#   on_drops_triggered()

# var stacks_template: PackedScene = load("res://assets/Gumbucks/GumbucksStack.tscn")
# var coin_template: PackedScene = load("res://assets/Gumbucks/GumCoin.tscn")

# func on_coin_collected(drop: GumDrop, bot: Bot) -> void:
#   Network.drops_redeemed(bot, 1, 0)
#   dropped_coins.erase(dropped_coins.find(drop))

# func on_stack_collected(drop: GumDrop, bot: Bot) -> void:
#   Network.drops_redeemed(bot, 0, 1)
#   dropped_stacks.erase(dropped_stacks.find(drop))

# func on_drops_triggered() -> void:
#   var coins_to_drop: int = max(0, Network.drops.coins - dropped_coins.size())
#   for i in range(coins_to_drop):
#     var coin: GumDrop = coin_template.instantiate()
#     coin.on_collected.connect(on_coin_collected)
#     get_parent().add_child(coin)
#     dropped_coins.append(coin)
#     # set random coin rotation
#     coin.global_transform = global_transform
#     coin.global_transform.origin += Vector3(randf_range(-drop_size.x, drop_size.x) * 0.5, 0, randf_range(-drop_size.y, drop_size.y) * 0.5)
#     coin.rotation_degrees = Vector3(randf_range(0, 360), randf_range(0, 360), randf_range(0, 360))

#     await get_tree().create_timer(.25).timeout

#   var stacks_to_drop: int = max(0, Network.drops.stacks - dropped_stacks.size())
#   for i in range(stacks_to_drop):
#     var stack: GumDrop = stacks_template.instantiate()
#     stack.on_collected.connect(on_stack_collected)
#     get_parent().add_child(stack)
#     dropped_stacks.append(stack)

#     stack.global_transform = global_transform
#     stack.global_transform.origin += Vector3(randf_range(-drop_size.x, drop_size.x) * 0.5, 0, randf_range(-drop_size.y, drop_size.y) * 0.5)
#     stack.rotation_degrees = Vector3(randf_range(0, 360), randf_range(0, 360), randf_range(0, 360))
#     await get_tree().create_timer(.25).timeout

