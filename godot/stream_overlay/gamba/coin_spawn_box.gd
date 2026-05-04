@tool
class_name CoinSpawnBox
extends StaticBody3D

signal value_spawned(value: int)

@onready var coin_sound_player: AudioStreamPlayer = %CoinSoundPlayer
@onready var coin_spawn_location: Marker3D = %CoinSpawnLocation
@export var coin_scene: PackedScene
@export var bucks_scene: PackedScene
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
  var coins_to_spawn := mini(amount, 10)
  var remaining := amount - coins_to_spawn
  @warning_ignore("INTEGER_DIVISION")
  var bucks_to_spawn := remaining / 5
  var leftover_coins := remaining % 5

  var items: Array[PackedScene] = []
  for i in range(coins_to_spawn + leftover_coins):
    items.append(coin_scene)
  for i in range(bucks_to_spawn):
    items.append(bucks_scene)
  items.shuffle()

  for scene in items:
    await _spawn_item(scene, 5 if scene == bucks_scene else 1)

func _spawn_item(scene: PackedScene, value: int) -> void:
  var coin_instance: GumCoin = scene.instantiate()
  get_parent().add_child(coin_instance)
  coin_instance.global_transform = coin_spawn_location.global_transform.translated(Vector3(randf_range(-spawn_size_range, spawn_size_range), 0, 0))
  coin_instance.global_rotation = Vector3(randf_range(0, 1) * TAU, randf_range(0, 1) * TAU, randf_range(0, 1) * TAU)
  spawned_coins.append(coin_instance)
  value_spawned.emit(value)
  coin_sound_player.pitch_scale = randf_range(1.2, 1.5)
  coin_sound_player.play()
  await get_tree().create_timer(0.15).timeout
