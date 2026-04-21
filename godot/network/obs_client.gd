extends Node

# Hotkeys (hold KEY_MODIFIER then press):
# +---------------+--------------------------------------------------+
# | \ + 2         | Fullscreen (1920x1080 at origin)                 |
# | \ + 1         | Mini, snap to bottom-right                       |
# | \ + 3         | Toggle source visibility                         |
# | \ + q         | Mini, snap to top-left                           |
# | \ + w         | Mini, snap to top-center                         |
# | \ + e         | Mini, snap to top-right                          |
# | \ + a         | Mini, snap to middle-left                        |
# | \ + s         | Mini, snap to center                             |
# | \ + d         | Mini, snap to middle-right                       |
# | \ + z         | Mini, snap to bottom-left                        |
# | \ + x         | Mini, snap to bottom-center                      |
# | \ + c         | Mini, snap to bottom-right                       |
# +---------------+--------------------------------------------------+

const PRINT_DEBUG: bool = false

const CANVAS_WIDTH := 1920
const CANVAS_HEIGHT := 1080
const SOURCE_WIDTH := 480
const SOURCE_HEIGHT := 270

const KEY_MODIFIER       := KEY_BACKSLASH
const KEY_FULLSCREEN     := KEY_2
const KEY_MINIMIZE       := KEY_1
const KEY_TOGGLE_VIS     := KEY_3
const KEY_POS_TOP_LEFT   := KEY_Q
const KEY_POS_TOP        := KEY_W
const KEY_POS_TOP_RIGHT  := KEY_E
const KEY_POS_LEFT       := KEY_A
const KEY_POS_CENTER     := KEY_S
const KEY_POS_RIGHT      := KEY_D
const KEY_POS_BOT_LEFT   := KEY_Z
const KEY_POS_BOT        := KEY_X
const KEY_POS_BOT_RIGHT  := KEY_C

var source_name := "ScreenShare1"
var scene_name := "Gumbots"
var margin := 20.0

var obs_ws: WebSocketPeer = null
var _identified := false
var _scene_item_id := -1
var _req_id := 0
var _source_visible := true

func _ready() -> void:
  if !DebugScreenLayout.is_stream_overlay:
    return
  obs_ws = WebSocketPeer.new()
  var result = obs_ws.connect_to_url("ws://localhost:4455")
  if result != OK:
    print("[OBS] Failed to connect to OBS WebSocket: ", result)
  elif PRINT_DEBUG:
    print("[OBS] Connecting to ws://localhost:4455...")

func _process(_delta: float) -> void:
  if obs_ws == null:
    return
  obs_ws.poll()
  match obs_ws.get_ready_state():
    WebSocketPeer.STATE_OPEN:
      while obs_ws.get_available_packet_count() > 0:
        var raw := obs_ws.get_packet().get_string_from_utf8()
        _handle_message(JSON.parse_string(raw))
    WebSocketPeer.STATE_CLOSED:
      pass

func _handle_message(msg: Dictionary) -> void:
  if not msg:
    return
  match int(msg.get("op", -1)):
    0: # Hello
      if PRINT_DEBUG: print("[OBS] Hello received, sending Identify")
      _send({"op": 1, "d": {"rpcVersion": 1}})
    2: # Identified
      if PRINT_DEBUG: print("[OBS] Identified — handshake complete. Fetching scene item ID for '%s' in scene '%s'" % [source_name, scene_name])
      _identified = true
      _fetch_scene_item_id()
    7: # RequestResponse
      _handle_response(msg.get("d", {}))
    _:
      if PRINT_DEBUG: print("[OBS] Unhandled op: ", msg.get("op"), " — ", msg)

func _fetch_scene_item_id() -> void:
  _req_id += 1
  _send({
    "op": 6,
    "d": {
      "requestType": "GetSceneItemId",
      "requestId": "get_item_id_%d" % _req_id,
      "requestData": {
        "sceneName": scene_name,
        "sourceName": source_name,
      }
    }
  })

func _handle_response(d: Dictionary) -> void:
  var req_type: String = d.get("requestType", "")
  var status: Dictionary = d.get("requestStatus", {})
  var ok: bool = status.get("result", false)

  if PRINT_DEBUG:
    print("[OBS] Response for '%s': ok=%s code=%s" % [req_type, ok, status.get("code", "?")])

  if not ok:
    print("[OBS] Request '%s' failed — code: %s comment: %s" % [req_type, status.get("code", "?"), status.get("comment", "")])
    return

  match req_type:
    "GetSceneItemId":
      _scene_item_id = d.get("responseData", {}).get("sceneItemId", -1)
      if PRINT_DEBUG: print("[OBS] Scene item ID for '%s': %d" % [source_name, _scene_item_id])
    "SetSceneItemTransform":
      if PRINT_DEBUG: print("[OBS] Transform applied successfully")
    "SetSceneItemEnabled":
      if PRINT_DEBUG: print("[OBS] Visibility set to: %s" % _source_visible)

func _input(event: InputEvent) -> void:
  if not event is InputEventKey or not event.pressed or event.echo:
    return
  if not Input.is_key_pressed(KEY_MODIFIER):
    return
  var key := (event as InputEventKey).keycode
  if key == KEY_MODIFIER:
    return

  var cx := (CANVAS_WIDTH - SOURCE_WIDTH) / 2.0
  var cy := (CANVAS_HEIGHT - SOURCE_HEIGHT) / 2.0
  var rx := CANVAS_WIDTH - SOURCE_WIDTH - margin
  var by := CANVAS_HEIGHT - SOURCE_HEIGHT - margin

  match key:
    KEY_FULLSCREEN:
      _move_source(Vector2.ZERO, Vector2(CANVAS_WIDTH, CANVAS_HEIGHT))
    KEY_MINIMIZE:
      _move_source(Vector2(rx, by), Vector2(SOURCE_WIDTH, SOURCE_HEIGHT))
    KEY_TOGGLE_VIS:
      _toggle_visibility()
    KEY_POS_TOP_LEFT:
      _move_source(Vector2(margin, margin))
    KEY_POS_TOP:
      _move_source(Vector2(cx, margin))
    KEY_POS_TOP_RIGHT:
      _move_source(Vector2(rx, margin))
    KEY_POS_LEFT:
      _move_source(Vector2(margin, cy))
    KEY_POS_CENTER:
      _move_source(Vector2(cx, cy))
    KEY_POS_RIGHT:
      _move_source(Vector2(rx, cy))
    KEY_POS_BOT_LEFT:
      _move_source(Vector2(margin, by))
    KEY_POS_BOT:
      _move_source(Vector2(cx, by))
    KEY_POS_BOT_RIGHT:
      _move_source(Vector2(rx, by))

func _toggle_visibility() -> void:
  if not _identified or _scene_item_id < 0:
    print("[OBS] Can't toggle visibility: not ready")
    return
  _source_visible = not _source_visible
  if PRINT_DEBUG: print("[OBS] Toggling visibility to: %s" % _source_visible)
  _req_id += 1
  _send({
    "op": 6,
    "d": {
      "requestType": "SetSceneItemEnabled",
      "requestId": "visibility_%d" % _req_id,
      "requestData": {
        "sceneName": scene_name,
        "sceneItemId": _scene_item_id,
        "sceneItemEnabled": _source_visible,
      }
    }
  })

func _move_source(pos: Vector2, size: Vector2 = Vector2(SOURCE_WIDTH, SOURCE_HEIGHT)) -> void:
  if PRINT_DEBUG: print("[OBS] _move_source called — identified=%s scene_item_id=%d pos=%s size=%s" % [_identified, _scene_item_id, pos, size])
  if not _identified:
    print("[OBS] Can't move: not yet identified with OBS")
    return
  if _scene_item_id < 0:
    print("[OBS] Can't move: scene item ID not yet resolved (scene='%s' source='%s')" % [scene_name, source_name])
    return
  _req_id += 1
  _send({
    "op": 6,
    "d": {
      "requestType": "SetSceneItemTransform",
      "requestId": "move_%d" % _req_id,
      "requestData": {
        "sceneName": scene_name,
        "sceneItemId": _scene_item_id,
        "sceneItemTransform": {
          "positionX": pos.x,
          "positionY": pos.y,
          "boundsType": "OBS_BOUNDS_SCALE_INNER",
          "boundsWidth": size.x,
          "boundsHeight": size.y,
        }
      }
    }
  })

func _send(data: Dictionary) -> void:
  if PRINT_DEBUG: print("[OBS] Sending op=%s" % data.get("op", "?"))
  obs_ws.send_text(JSON.stringify(data))
