@tool
extends CharacterBody3D
class_name KartBot

@onready var kart_wheel_l: MeshInstance3D = %KartWheel_L
@onready var kart_wheel_r: MeshInstance3D = %KartWheel_R
@onready var kart_movement: KartMovementSynchronizer = $KartMovement
@onready var gumbot: CarnageGumbot = %gumbot
# @onready var anim_tree: AnimationTree = %AnimationTree

@export var kart_material: StandardMaterial3D

@export var wheel_turn: float = 0.0:
  set(new_value):
    wheel_turn = new_value
    kart_wheel_l.rotation.y = wheel_turn
    kart_wheel_r.rotation.y = wheel_turn

func punch_cosmetic() -> void:
  get_tree().create_tween().tween_property(gumbot.spring_bone_sim, "influence", 0, 0.1)
  gumbot.anim_tree.set("parameters/PunchOneShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
  await gumbot.anim_tree.animation_finished
  await get_tree().create_timer(0.1).timeout
  get_tree().create_tween().tween_property(gumbot.spring_bone_sim, "influence", 1.0, 0.1)
