@abstract
extends Object
class_name State

func enter_state(_previous_state: State) -> void: pass
func exit_state() -> void: pass

func update(_delta: float) -> void: pass
func physics_update(_delta: float) -> void: pass

var primary_ability_is_pressed: bool = false
var secondary_ability_is_pressed: bool = false
func primary_ability_pressed() -> void:
  primary_ability_is_pressed = true

func primary_ability_released() -> void:
  primary_ability_is_pressed = false

func secondary_ability_pressed() -> void:
  secondary_ability_is_pressed = true

func secondary_ability_released() -> void:
  secondary_ability_is_pressed = false