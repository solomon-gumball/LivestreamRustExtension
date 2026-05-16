class_name NetTickSimulated
extends Node

signal tick_simulated(current_tick: int, delta: float)
signal cleared_local_state

func _ready() -> void:
  await get_tree().process_frame
  SessionSynchronizer.get_instance().register_synchronizer(self)

func simulate_tick(_current_tick: int,  _delta: float) -> void:
  tick_simulated.emit(_current_tick, _delta)
  # assert(false, "simulate_tick must be implemented by subclass")

func clear_local_state() -> void:
  cleared_local_state.emit()
  # assert(false, "clear_local_state must be implemented by subclass")
