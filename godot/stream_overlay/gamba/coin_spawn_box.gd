@tool
class_name CoinSpawnBox
extends StaticBody3D

@onready var coin_spawn_location: Marker3D = %CoinSpawnLocation
@export var coin_scene: PackedScene
@export var spawn_size_range: float = 0.4
@export var spawn_position_offset: Vector3 = Vector3.ZERO:
  set(new_value):
    spawn_position_offset = new_value
    if is_inside_tree():
      coin_spawn_location.position = spawn_position_offset

var spawned_coins: Array[GumCoin] = []

func _ready() -> void:
  spawn_position_offset = spawn_position_offset

func clear_coins() -> void:
  for coin in spawned_coins:
    if !coin.is_queued_for_deletion():
      coin.queue_free()
  spawned_coins = []

func spawn_coins(amount: int) -> void:
  for i in range(amount):
    var coin_instance: GumCoin = coin_scene.instantiate()
    get_parent().add_child(coin_instance)
    coin_instance.global_transform = coin_spawn_location.global_transform.translated(Vector3(randf_range(-spawn_size_range, spawn_size_range), 0, 0))
    coin_instance.global_rotation = Vector3(randf_range(0, 1) * TAU, randf_range(0, 1) * TAU, randf_range(0, 1) * TAU)
    spawned_coins.append(coin_instance)
    await get_tree().create_timer(0.2).timeout
