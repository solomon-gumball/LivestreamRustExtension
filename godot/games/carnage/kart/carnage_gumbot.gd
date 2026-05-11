@tool
class_name CarnageGumbot
extends GumBot

@onready var spring_bone_sim: SpringBoneSimulator3D = %SpringBoneSimulator3D

@export var spring_stiffness: float = 1.0:
  set(new_value): spring_stiffness = new_value; update_sim()
@export var spring_drag: float = 0.1:
  set(new_value): spring_drag = new_value; update_sim()

func update_sim() -> void:
  if !spring_bone_sim: return

  for i in spring_bone_sim.setting_count:
    spring_bone_sim.set_stiffness(i, spring_stiffness)
    spring_bone_sim.set_drag(i, spring_drag)