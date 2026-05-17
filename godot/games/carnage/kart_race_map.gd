class_name KartRaceMap
extends Node3D

@onready var debug_camera: DebugCamera = %DebugCamera
@onready var out_of_bounds_area: Area3D = %OutOfBoundsArea
@onready var in_bounds_area: Area3D = %InBoundsArea
@onready var animation_synchronizer: AnimationSynchronizer = %AnimationSynchronizer
@onready var animation_camera: Camera3D = $Camera
@onready var debug_inner_cam: Camera3D = %DebugInnerCam