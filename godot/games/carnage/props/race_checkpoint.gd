@tool
class_name RaceCheckpoint
extends Area3D

@onready var pillar_l: CSGBox3D = %Pillar_L
@onready var pillar_r: CSGBox3D = %Pillar_R
@onready var collision_shape: CollisionShape3D = %CollisionShape

@export var plane_mesh: PlaneMesh
@export var plane_material: StandardMaterial3D
@export var pillar_material: StandardMaterial3D
@export var box_shape: BoxShape3D
@export var width: float = 5.0:
  set(new_value):
    box_shape.size.x = new_value
    width = new_value
    plane_mesh.size.x = new_value
    pillar_l.position.x = new_value / 2.0
    pillar_r.position.x = -new_value / 2.0