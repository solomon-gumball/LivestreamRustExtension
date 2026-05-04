@tool
class_name CoinSpawnBox
extends StaticBody3D

@onready var coin_spawn_location: Marker3D = %CoinSpawnLocation
@export var coin_scene: PackedScene
@export var spawn_size_range: float = 0.4
@export var spawn_position_offset: Vector3 = Vector3.ZERO:
  set(new_value):
    if is_inside_tree():
      spawn_position_offset = new_value
      coin_spawn_location.position = spawn_position_offset

func spawn_coins(amount: int) -> void:
  for i in range(amount):
    var coin_instance: GumCoin = coin_scene.instantiate()
    get_parent().add_child(coin_instance)
    # var rand_val := randf_range(0.0, TAU)
    # var random_offset := Vector3(cos(rand_val), 0, sin(rand_val)) * spawn_size_range
    # coin_instance.global_transform = coin_spawn_location.global_transform.translated(random_offset)

    # coin_instance.global_transform = coin_spawn_location.global_transform
    coin_instance.global_transform = coin_spawn_location.global_transform.translated(Vector3(randf_range(-spawn_size_range, spawn_size_range), 0, 0))
    print("Spawning coin at ", coin_instance.global_transform.origin)
    
    await get_tree().create_timer(0.5).timeout
