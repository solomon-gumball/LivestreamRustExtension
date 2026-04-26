extends Node
class_name StateMachine

var initial_state : State
var current : State = null

signal changed(new_state: State)

func change_state(next_state : State) -> void:
  if current == next_state:
    return

  if is_instance_valid(current):
    current.exit_state()

  if is_instance_valid(next_state):
    next_state.sm = self
    next_state.enter_state(current)

  current = next_state
  changed.emit(next_state)

func process_state(delta : float) -> void:
  if is_instance_valid(current):
    current.update(delta)

func input_state(event: InputEvent) -> void:
  if is_instance_valid(current):
    current.handle_input(event)

func _physics_process(delta: float) -> void:
  if is_instance_valid(current):
    current.physics_update(delta)
