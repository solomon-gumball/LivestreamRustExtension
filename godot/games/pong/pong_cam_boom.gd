@tool
class_name PongCamBoom
extends Node3D

@onready var initial_pos: Vector3 = global_position

@export var target_player: Node3D
@export var progress: float = 0.0:
  set(new_progress):
    progress = new_progress
    position = lerp(
      initial_pos,
      Vector3(
        target_player.global_position.x,
        0.2,
        target_player.global_position.z,
      ),
      new_progress
    )
