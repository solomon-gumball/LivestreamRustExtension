extends Node

var window_index: int = -1

func _ready() -> void:
  var cmd_args := OS.get_cmdline_args()

  # LimboConsole.register_command(restart)

  var num_windows := 2

  # Find window index in cmdline args string. Example "--i=1" Id = 1.
  for arg in cmd_args:
    if arg is String and arg.begins_with("--i="):
      var parts := arg.split("=")
      if parts.size() >= 2:
        window_index = int(parts[1])
        break

  if window_index != -1:
    DisplayServer.window_move_to_foreground()
    DisplayServer.window_set_size(DisplayServer.screen_get_size() / num_windows)
    DisplayServer.window_set_position(
      Vector2i(
        (DisplayServer.screen_get_size().x / num_windows) * window_index,
        DisplayServer.screen_get_size().y / 4
      )
    )