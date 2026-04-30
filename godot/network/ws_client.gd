# actions.gd
extends Node

var remote_server_socket: WebSocketPeer

var debug_chatter_id: String

var state: StateMachine = StateMachine.new()
var disconnected_state: DisconnectedState = DisconnectedState.new(self)
var connected_state: ConnectedState = ConnectedState.new(self)
var authenticated_state: AuthenticatedState = AuthenticatedState.new(self)

var use_local_server: bool = !OS.has_feature("prod_server")

signal authenticated

func my_chatter() -> Chatter:
  return authenticated_state.current_chatter

func getServerDomain() -> String:
   return "localhost:1235" if self.use_local_server else "livestream-listener-475alhkiqa-uc.a.run.app/"

func get_database_server_url(path: String = "") -> String:
  return "https://%s/%s" % [getServerDomain(), path]

func getWsServerUrl() -> String:
  return "wss://%s" % [getServerDomain()]

var inbox_size = 10
func _ready() -> void:
  if DebugScreenLayout.window_index == 0:
    WSClient.debug_chatter_id = '22445910' # Gumball
  else:
    WSClient.debug_chatter_id = '1273990990' # GumBOT

  remote_server_socket = WebSocketPeer.new()

  add_child(state)

  state.add_child(disconnected_state)
  state.add_child(connected_state)
  state.add_child(authenticated_state)

  connected_state.authenticated_successfully.connect(_handle_authenticated)
  state.change_state(disconnected_state)

func _handle_authenticated() -> void:
  state.change_state(authenticated_state)
  authenticated.emit()

func fetchAudienceMembers(count: int, participants: Array[Chatter]) -> Array[Chatter]:
  var request = AwaitableHTTPRequest.new()
  add_child(request)
  var headers: PackedStringArray = [
    "Content-Type: application/json"
  ]
  var url = "%s/audience-members" % get_database_server_url()
  var response := await request.async_request(
    url,
    headers,
    HTTPClient.METHOD_GET,
    JSON.stringify({ "count": count, "omitIds": participants.map(func (p): return p.id) })
  )

  if response.success() and response.status_ok():
    var chatters: Array[Chatter] = []
    chatters.assign(response.body_as_json().map(func (c): return Chatter.FromData(c)))
    return chatters
  return []

func drops_redeemed(bot: GumBot, coins: int, stacks: int) -> void:
  send_socket_message({
    "type": "drops-redeemed",
    "chatter_id": bot.chatter.id,
    "coins": coins,
    "stacks": stacks,
  })

static var recently_completed_actions: Dictionary = {}

func send_socket_message(payload: Dictionary) -> Error:
  if not state.current is AuthenticatedState:
    return ERR_UNAVAILABLE
  return remote_server_socket.send_text(JSON.stringify(payload))

func mail_shown(uuid: String) -> void:
  send_socket_message({ "type": "mail-shown", "uuid": uuid })

func tts_activated(uuid: String) -> void:
  send_socket_message({ "type": "tts-activated", "uuid": uuid })

func slots_activated(uuid: String, gumbucksWon: float) -> void:
  send_socket_message({ "type": "slots-activated", "uuid": uuid, "gumbucksWon": gumbucksWon })

func subscribe(channels: Array[String]) -> void:
  send_socket_message({ "type": "subscribe", "channels": channels })

func wear_item(item: String) -> Chatter:
  var request = AwaitableHTTPRequest.new()
  add_child(request)
  var headers: PackedStringArray = [
    "Content-Type: application/json",
    "Authorization: Bearer " + connected_state.twitch_auth_token,
  ]
  var response := await request.async_request(
    get_database_server_url("wear-item"),
    headers,
    HTTPClient.METHOD_PUT,
    JSON.stringify({ "item": item })
  )

  if response.success() and response.status_ok():
    var result: Dictionary = response.body_as_json()
    if result.get("success"):
      return Chatter.FromData(result["updated"])
  return null


var debug_force_disconnected := false

func _process(_delta: float) -> void:
  remote_server_socket.poll()

  var ready_state = remote_server_socket.get_ready_state()
  match ready_state:
    WebSocketPeer.STATE_OPEN:
      if state.current is DisconnectedState:
        state.change_state(connected_state)
      while remote_server_socket.get_available_packet_count() > 0:
        var parsed = JSON.parse_string(remote_server_socket.get_packet().get_string_from_utf8())
        if parsed is Array:
          for message in parsed:
            state.current.handle_remote_message(message)
        else:
          state.current.handle_remote_message(parsed)

    WebSocketPeer.STATE_CLOSING:
      pass
    WebSocketPeer.STATE_CLOSED:
      if not state.current is DisconnectedState:
        state.change_state(disconnected_state)

class WSClientState extends State:
  var net: Node
  func _init(_net: Node) -> void:
    net = _net
  func handle_remote_message(message: Variant) -> void:
    print("UNCAUGHT SOCKET MESSAGE => ", message.type)
    return

class DisconnectedState extends WSClientState:
  var reconnect_timer: Timer
  var debug_force_disconnected := false

  func _ready() -> void:
    reconnect_timer = Timer.new()
    reconnect_timer.autostart = false
    reconnect_timer.one_shot = false
    reconnect_timer.timeout.connect(_try_connect_to_remote_server)
    add_child(reconnect_timer)

  func enter_state(_previous_state: State) -> void:
    reconnect_timer.start(2.0)
    _try_connect_to_remote_server()

  func exit_state() -> void:
    reconnect_timer.stop()
  
  func _input(_event: InputEvent) -> void:
    if Input.is_action_just_pressed("DebugToggleNetwork"):
      if net.remote_server_socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
        print("Websocket connection lost!")
        debug_force_disconnected = true
        net.remote_server_socket.close()
      else:
        print("Websocket reconnecting!")
        debug_force_disconnected = false
  
  func _try_connect_to_remote_server() -> void:
    if debug_force_disconnected: return
    var url = net.getWsServerUrl()
    var err = net.remote_server_socket.connect_to_url(url, TLSOptions.client_unsafe() if net.use_local_server else null)
    if err != OK:
      print("Error connecting to remote server: %d" % err)

class ConnectedState extends WSClientState:
  signal authenticated_successfully
  var current_chatter: Chatter = null
  var turn_credentials: Dictionary = {}
  var store_data: Message.StoreData
  var twitch_auth_token: String = ""
  var callback: JavaScriptObject

  func _ready() -> void:
    if OS.get_name() == "Web":
      callback = JavaScriptBridge.create_callback(_on_twitch_authorized)
      JavaScriptBridge.get_interface("window").twitchTokenCallback = callback

  func enter_state(_previous_state: State) -> void:
    _try_authenticate()
  
  func _on_twitch_authorized(args: Array) -> void:
    twitch_auth_token = str(args[0])
    _try_authenticate()
  
  func _try_authenticate() -> void:
    var auth_msg := { "type": "authenticate" }

    if not net.debug_chatter_id.is_empty():
      auth_msg["debugAuthId"] = net.debug_chatter_id
    elif not twitch_auth_token.is_empty():
      auth_msg["token"] = twitch_auth_token
    
    var subscribe_method := { "type": "subscribe", "channels": ["LOBBIES"] }
    net.remote_server_socket.send_text(JSON.stringify([auth_msg, subscribe_method]))
  
  func handle_remote_message(message: Variant) -> void:
    match message.type:
      "authenticated":
        if message.get("success", false):
          if message.get("turnCredentials") != null:
            turn_credentials = message.turnCredentials
          if message.get("chatter"):
            current_chatter = Chatter.FromData(message.get("chatter"))
          if message.get("store"):
            store_data = Message.StoreData.FromData(message.get("store"))

          authenticated_successfully.emit()

class AuthenticatedState extends WSClientState:
  signal store_data_received()
  signal shop_data_received()
  signal emote_triggered(chatter: Chatter, emote: String)
  # signal tts_queue_updated()
  # signal new_subscription(username: String)

  signal gifted_subs(username: String, count: int)
  signal chat_message_received(message: Message.Chat)
  signal file_changed(file_name: String)
  signal chatter_updated(chatter: Chatter)
  signal my_chatter_updated(chatter: Chatter)
  signal debug_image_received(base64: String)
  signal leaderboard_updated(leaderboard: Array[Chatter])
  signal onscreen_notification_received(message: Message.OnScreenNotification)
  signal drops_triggered()
  signal cam_updated(user_name: String)
  signal primary_notification_received(notification: Message.PrimaryNotification)
  # signal inbox_loaded(mail: Array[Message.ShowMailRequest.Mail])
  signal message_received(message: Variant)

  var action_queue: Array[Message.QueueAction] = []
  var active_chatters: Array[Chatter] = []
  var leaderboard: Array[Chatter] = []
  var turn_credentials: Dictionary = {}
  var drops: Message.DropData = Message.DropData.new()
  var current_chatter: Chatter
  var item_info: Dictionary = {}
  var _available_shop_items: Array[String] = []

  func get_item_info(item_name: String) -> ShopItem:
    if item_info.has(item_name):
      return item_info[item_name]
    return null

  func get_available_shop_items() -> Array[ShopItem]:
    var out_items: Array[ShopItem] = []
    var items: Array = _available_shop_items.map(func (item_name: String): return item_info[item_name])
    out_items.assign(items)
    return out_items

  func add_or_update_chatter(chatter: Chatter) -> void:
    for i in range(active_chatters.size()):
      if active_chatters[i].id == chatter.id:
        active_chatters[i] = chatter
        return
    active_chatters.append(chatter)

  func enter_state(_previous_state: State) -> void:
    if _previous_state is ConnectedState:
      var connected_prev: ConnectedState = _previous_state
      current_chatter = connected_prev.current_chatter
      turn_credentials = connected_prev.turn_credentials

      _handle_store_data_refreshed(connected_prev.store_data)
      chatter_updated.emit(current_chatter)
  
  func _handle_store_data_refreshed(store_data: Message.StoreData) -> void:
    active_chatters = store_data.active_chatters
    # active_chatters = store_data.active_chatters.filter(func (chatter: Chatter): return chatter.expires_in_ms() > 0)
    action_queue = store_data.action_queue
    drops = store_data.drops
    item_info = store_data.market
    store_data_received.emit()

  func _parse_shop_items(item_dict: Dictionary) -> void:
    item_info = {}
    for key in item_dict:
      var storeItemData = ShopItem.FromData(item_dict[key])
      item_info[storeItemData.name] = storeItemData
    shop_data_received.emit()

  func handle_remote_message(message: Variant) -> void:
    message_received.emit(message)

    match message.type:
      "trigger-emote":
        emote_triggered.emit(Chatter.FromData(message.chatter), message.emote)
      "shop-updated":
        _available_shop_items.assign(message.items)
        shop_data_received.emit()
      "item-info":
        _parse_shop_items(message.info)
      "image-test":
        debug_image_received.emit(message.base64)
      "camera-updated":
        cam_updated.emit(message.cam)
      "primary-notification":
        var primary_notification = Message.PrimaryNotification.FromData(message)
        primary_notification_received.emit(primary_notification)
      "onscreen-notification":
        var onscreen_notification = Message.OnScreenNotification.FromData(message)
        onscreen_notification_received.emit(onscreen_notification)
      "action-queue-updated":
        action_queue = Message.StoreData.CreateActionQueue(message.action_queue)
      "twitch-message":
        var chat_message = Message.Chat.FromData(message)
        add_or_update_chatter(chat_message.chatter)
        chatter_updated.emit(chat_message.chatter)
        chat_message_received.emit(chat_message)
      "twitch-gift-sub":
        gifted_subs.emit(message.id, message.amount)
      "update-chatter":
        var new_chatter = Chatter.FromData(message.chatter)
        add_or_update_chatter(new_chatter)
        if new_chatter.id == current_chatter.id:
          current_chatter = new_chatter
          my_chatter_updated.emit(new_chatter)
        chatter_updated.emit(new_chatter)
      "twitch-custom-redeem":
        pass
      "file-changed":
        file_changed.emit(message.file_name)
      "leaderboard-updated":
        leaderboard = []
        for chatter_data in message.leaderboard:
          leaderboard.append(Chatter.FromData(chatter_data))
        leaderboard_updated.emit(leaderboard)
      "drops-added":
        drops = Message.DropData.FromData(message.drops)
        drops_triggered.emit()
      "store-data":
        var store_data = Message.StoreData.FromData(message)
        _handle_store_data_refreshed(store_data)
