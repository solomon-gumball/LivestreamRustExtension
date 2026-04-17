extends Node
class_name StateMachine

var initial_state : State
var curr_state : State = null

# func _ready() -> void:
#     assert(is_instance_valid(initial_state), "Initial state is not valid")
#     change_state(initial_state)

func change_state(next_state : State) -> void:
    if is_instance_valid(curr_state):
        curr_state.exit_state()
    
    if is_instance_valid(next_state):
        next_state.sm = self
        next_state.enter_state(curr_state)

    if is_instance_valid(curr_state):
        queue_free()
        
    add_child(next_state)

    # print("State changed to: ", next_state)
    curr_state = next_state

func process_state(delta : float) -> void:
    if is_instance_valid(curr_state):
        curr_state.update(delta)

func _physics_process(delta: float) -> void:
    if is_instance_valid(curr_state):
        curr_state.physics_update(delta)
