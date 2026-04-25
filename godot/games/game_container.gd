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
 
const DISABLE_LOAD_FROM_PCK := true

func load_game_from_lobby(lobby: Lobby) -> void:
  var game := lobby.game

  if !DISABLE_LOAD_FROM_PCK:
    var loaded := await _fetch_and_cache_pck(game)
    if not loaded:
      return

  var packed_scene := ResourceLoader.load(game.entry) as PackedScene
  if packed_scene == null:
    push_error("GameContainer: could not load scene at entry path '%s'" % game.entry)
    return
  _game_scene = packed_scene.instantiate() as GameBase

  _game_scene.lobby = lobby
  add_child(_game_scene)
  _game_scene.game_finished.connect(game_finished.emit)
