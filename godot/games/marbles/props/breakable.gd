@tool
class_name Breakable
extends Node3D

@export var surface_material: StandardMaterial3D

func _ready() -> void:
  for child in get_children():
    if child is RigidBody3D:
      _freeze_piece(child as RigidBody3D)
      for inner_child in child.get_children():
        if inner_child is MeshInstance3D:
          (inner_child as MeshInstance3D).set_surface_override_material(0, surface_material)

func _freeze_piece(body: RigidBody3D) -> void:
  body.collision_layer = 0
  body.collision_mask = 2
  body.freeze = true
  body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
  body.contact_monitor = true
  body.max_contacts_reported = 1
  body.body_entered.connect(
    func(_other: Node3D):
    if _other is MarbleBot:
      body.freeze = false
    ,CONNECT_ONE_SHOT
  )
