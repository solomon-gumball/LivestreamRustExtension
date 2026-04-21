extends GumBot
class_name StreamOverlayGumBot

@onready var state: StateMachine = %StateMachine
@onready var nav_agent: NavigationAgent3D = %NavigationAgent3D
@onready var wandering_state: GumbotWanderingState = %GumbotWanderingState
# enum State { StandIdle, PresentMail, Speaking, Walking, Grabbed, Gambling, Emote }
@onready var debug_cube: MeshInstance3D = %DebugCube

func _ready() -> void:
  state.change_state(wandering_state)
