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

@export var reached_color: Color = Color.GREEN 
@export var unreached_color: Color = Color.RED
@export var reached: bool = false:
  set(new_reached):
    reached = new_reached
    plane_material.emission = reached_color if new_reached else unreached_color

signal checkpoint_reached(peer_id)

func _on_body_entered(body: Node) -> void:
  print("body entered")
  if body is PhysicsKart:
    var kart := body as PhysicsKart
    print("emitting")
    checkpoint_reached.emit(kart.physics_kart_movement_sync.owner_peer_id)

func _ready() -> void:
  body_entered.connect(_on_body_entered)
  reached = reached