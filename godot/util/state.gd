@abstract
extends Node
class_name State

var sm: StateMachine

func enter_state(_previous_state: State) -> void: pass
func exit_state() -> void: pass

func update(_delta: float) -> void: pass
func physics_update(_delta: float) -> void: pass