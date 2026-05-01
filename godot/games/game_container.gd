extends Node
class_name GameContainer

signal game_finished

const PCK_CACHE_PATH := "user://games/pck_cache.json"

var _game_scene: GameBase = null
var _pck_cache: Dictionary = {}

func _ready() -> void:
  _load_pck_cache()

func _load_pck_cache() -> void:
  var file := FileAccess.open(PCK_CACHE_PATH, FileAccess.READ)
  if file == null:
    return
  var parsed: Variant = JSON.parse_string(file.get_as_text())
  file.close()
  if parsed is Dictionary:
    _pck_cache = parsed

func _save_pck_cache() -> void:
  DirAccess.make_dir_recursive_absolute("user://games")
  var file := FileAccess.open(PCK_CACHE_PATH, FileAccess.WRITE)
  if file == null:
    push_error("GameContainer: could not write pck_cache to %s" % PCK_CACHE_PATH)
    return
  file.store_string(JSON.stringify(_pck_cache))
  file.close()

func _fetch_and_cache_pck(game: GameMetadata) -> bool:
  var title := game.title
  var pck_path := "user://games/%s.pck" % title

  var cached_hash := str(_pck_cache.get(title, ""))
  var needs_download := cached_hash != game.pck_hash or not FileAccess.file_exists(pck_path)

  if needs_download:
    print("NEEDS TO DOWNLOAD PCK")
    var pck_url := WSClient.get_database_server_url(game.bundle_url)
    var request := AwaitableHTTPRequest.new()
    add_child(request)
    var result := await request.async_request(pck_url)
    request.queue_free()

    if not result.success() or not result.status_ok():
      push_error("GameContainer: failed to download PCK from %s (status %d)" % [pck_url, result.status])
      return false

    DirAccess.make_dir_recursive_absolute("user://games")
    var file := FileAccess.open(pck_path, FileAccess.WRITE)
    if file == null:
      push_error("GameContainer: could not open %s for writing" % pck_path)
      return false
    file.store_buffer(result.bytes)
    file.close()

    _pck_cache[title] = game.pck_hash
    _save_pck_cache()
  else:
    print("PCK WAS CACHED!")

  if not ProjectSettings.load_resource_pack(pck_path):
    push_error("GameContainer: load_resource_pack failed for %s" % pck_path)
    return false

  return true
 
func load_game_from_lobby(lobby: Lobby) -> void:
  var game := lobby.game

  if OS.has_feature("game_pcks"):
    var loaded := await _fetch_and_cache_pck(game)
    if not loaded:
      return

  if DebugScreenLayout.window_index == 1:
    await get_tree().create_timer(3.0).timeout

  var packed_scene: PackedScene
  if OS.has_feature("threads"):
    ResourceLoader.load_threaded_request(game.entry)
    var status := ResourceLoader.THREAD_LOAD_IN_PROGRESS
    while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
      await get_tree().process_frame
      status = ResourceLoader.load_threaded_get_status(game.entry)
      print(status) # This can take a while for large scenes, so it's good to have some indication that progress is being made

    if status == ResourceLoader.THREAD_LOAD_FAILED:
      push_error("GameContainer: threaded load failed for '%s'" % game.entry)
      return
    packed_scene = ResourceLoader.load_threaded_get(game.entry) as PackedScene
  else:
    packed_scene = ResourceLoader.load(game.entry) as PackedScene

  if packed_scene == null:
    push_error("GameContainer: could not load scene at entry path '%s'" % game.entry)
    return

  _game_scene = packed_scene.instantiate() as GameBase
  _game_scene.lobby = lobby
  add_child(_game_scene)
  _game_scene.game_finished.connect(game_finished.emit)
