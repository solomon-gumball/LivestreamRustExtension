extends Node

var window_index: int = -1
var is_stream_overlay: bool = false

func _ready() -> void:
  var cmd_args := OS.get_cmdline_args()

  var num_col := 2
  var num_row := 2

  # Find window index in cmdline args string. Example "--i=1" Id = 1.
  for arg in cmd_args:
    if arg is String and arg.begins_with("--i="):
      var parts := arg.split("=")
      if parts.size() >= 2:
        window_index = int(parts[1])
    if str(arg) == "--overlay":
      is_stream_overlay = true

  if window_index != -1:
    var usable := DisplayServer.screen_get_usable_rect()
    var col := window_index % num_col
    @warning_ignore_start("INTEGER_DIVISION")
    var row := window_index / num_col
    var cell_size := Vector2i(usable.size.x / num_col, usable.size.y / num_row)
    DisplayServer.window_move_to_foreground()
    DisplayServer.window_set_size(cell_size)
    DisplayServer.window_set_position(Vector2i(usable.position.x + cell_size.x * col, usable.position.y + cell_size.y * row))
    @warning_ignore_restore("INTEGER_DIVISION")