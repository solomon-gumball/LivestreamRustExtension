# actions.gd
extends Node

var remote_server_socket: WebSocketPeer

signal store_data_received()
signal shop_data_received()
signal emote_triggered(chatter: Chatter, emote: String)
signal tts_queue_updated()
# signal new_subscription(username: String)

signal gifted_subs(username: String, count: int)
signal chat_message_received(message: Message.Chat)
signal file_changed(file_name: String)
signal chatter_updated(chatter: Chatter)
signal debug_image_received(base64: String)
signal leaderboard_updated(leaderboard: Array[Chatter])
signal onscreen_notification_received(message: Message.OnScreenNotification)
signal drops_triggered()
signal cam_updated(user_name: String)
signal primary_notification_received(notification: Message.PrimaryNotification)
signal inbox_loaded(mail: Array[Message.ShowMailRequest.Mail])
signal scrolling_text_updated(new_scrolling_text: String)
signal socket_connection_status_changed(is_connected: bool)

var action_queue: Array[Message.QueueAction] = []
var active_chatters: Array[Chatter] = []
var leaderboard: Array[Chatter] = []
var drops: Message.DropData = Message.DropData.new()
var current_chatter_id: String = ""
var multiplayer_client: MultiplayerClient
var current_chatter: Chatter
var reconnect_timer: Timer

var scrolling_text: String = "":
  set(new_text):
    scrolling_text = new_text
    scrolling_text_updated.emit(new_text)

func add_or_update_chatter(chatter: Chatter) -> void:
  for i in range(active_chatters.size()):
    if active_chatters[i].id == chatter.id:
      active_chatters[i] = chatter
      return
  active_chatters.append(chatter)

var use_local_server: bool = true

func getServerDomain() -> String:
   return "localhost:1235" if self.use_local_server else "livestream-listener-913887936892.us-central1.run.app"

func get_database_server_url(path: String = "") -> String:
  return "https://%s" % [getServerDomain()]

func getWsServerUrl() -> String:
  return "wss://%s" % [getServerDomain()]

var inbox_size = 10
func _ready() -> void:
  remote_server_socket = WebSocketPeer.new()

  _try_connect_to_remote_server()

  if OS.get_name() == "Web":
    callback = JavaScriptBridge.create_callback(_on_twitch_authorized)
    JavaScriptBridge.get_interface("window").twitchTokenCallback = callback
  
  reconnect_timer = Timer.new()
  reconnect_timer.autostart = false
  reconnect_timer.one_shot = false
  reconnect_timer.timeout.connect(_try_connect_to_remote_server)
  add_child(reconnect_timer)

  multiplayer_client = MultiplayerClient.new()
  add_child(multiplayer_client)

var callback: JavaScriptObject
var auth_token: String = ""

func _on_twitch_authorized(args: Array) -> void:
  set("auth_token", str(args[0]))
  auth_token = str(args[0])
  print("Twitch auth token received")

  # var request = AwaitableHTTPRequest.new()
  # add_child(request)

  # var headers: PackedStringArray = ["Content-Type: application/json"]
  # var url = "%s/inbox" % get_database_server_url()
  # var response := await request.async_request(
  #   url,
  #   headers,
  #   HTTPClient.METHOD_GET,
  #   JSON.stringify({ "limit": inbox_size })
  # )

  # if response.success() and response.status_ok():
  #   var mail = response.body_as_json().map(func (m): return Network.ShowMailRequest.Mail.FromData(m))
  #   var out_messages: Array[Message.ShowMailRequest.Mail] = []
  #   out_messages.assign(mail)
  #   inbox_loaded.emit(out_messages)

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
  remote_server_socket.send_text(JSON.stringify({
    "type": "drops-redeemed",
    "chatter_id": bot.chatter.id,
    "coins": coins,
    "stacks": stacks,
  }))

static var recently_completed_actions: Dictionary = {}

func send_socket_message(payload: Dictionary) -> Error:
  return remote_server_socket.send_text(JSON.stringify(payload))

func mail_shown(uuid: String) -> void:
  remote_server_socket.send_text(JSON.stringify({
    "type": "mail-shown",
    "uuid": uuid
  }))

func tts_activated(uuid: String) -> void:
  remote_server_socket.send_text(JSON.stringify({
    "type": "tts-activated",
    "uuid": uuid
  }))

func slots_activated(uuid: String, gumbucksWon: float) -> void:
  remote_server_socket.send_text(JSON.stringify({
    "type": "slots-activated",
    "uuid": uuid,
    "gumbucksWon": gumbucksWon
  }))

func subscribe(channels: Array[String]) -> void:
  remote_server_socket.send_text(JSON.stringify({
    "type": "subscribe",
    "channels": channels
  }))

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

func handle_remote_message(message: Variant) -> void:
  # print("Received message of type ", message.type)
  match message.type:
    "scrolling-text-updated":
      scrolling_text = message.get("text", "NO TEXT PROVIDED")
    "trigger-emote":
      print("Emote triggered: ", message.emote)
      emote_triggered.emit(Chatter.FromData(message.chatter), message.emote)
    "shop-updated":
      _available_shop_items.assign(message.items)
      shop_data_received.emit()
    "item-info":
      item_info = {}
      for key in message.info:
        var storeItemData = message.info[key]
        item_info[storeItemData.name] = ShopItem.FromData(storeItemData)
      shop_data_received.emit()
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
      active_chatters = store_data.active_chatters.filter(func (chatter: Chatter): return chatter.expires_in_ms() > 0)
      action_queue = store_data.action_queue
      scrolling_text = message.get("scrolling_text", "NO TEXT PROVIDED")
      drops = store_data.drops
      store_data_received.emit()
    "authenticated":
      turn_credentials = message.turnCredentials
      print(turn_credentials)

  multiplayer_client.handle_ws_message(message)

var turn_credentials: Dictionary = {}

enum ConnectionStatus {
  None,
  Connected,
  Disconnected
}

func _try_connect_to_remote_server() -> void:
  if debug_force_disconnected: return

  var url = getWsServerUrl()
  var err = remote_server_socket.connect_to_url(url, TLSOptions.client_unsafe() if use_local_server else null)
  print("Attempting to connect to server")

  if err != OK:
    print("Error connecting to remote server: %d" % err)
    connection_status = ConnectionStatus.Disconnected

var connection_status: ConnectionStatus = ConnectionStatus.None:
  set(new_connection_status):
    var previous_status = connection_status
    connection_status = new_connection_status

    if new_connection_status != previous_status:
      print('Connection state: ', previous_status, ' => ', new_connection_status)
      socket_connection_status_changed.emit(new_connection_status == ConnectionStatus.Connected)

      if new_connection_status == ConnectionStatus.Disconnected:
        reconnect_timer.start(2.0)
        multiplayer_client.disconnected.emit()
      else:
        reconnect_timer.stop()

var debug_force_disconnected := false
func _process(_delta: float) -> void:
  remote_server_socket.poll()

  var state = remote_server_socket.get_ready_state()
  match state:
    WebSocketPeer.STATE_OPEN:
      connection_status = ConnectionStatus.Connected
      while remote_server_socket.get_available_packet_count() > 0:
        var packet = remote_server_socket.get_packet()
        var message = JSON.parse_string(packet.get_string_from_utf8())
        handle_remote_message(message)

    WebSocketPeer.STATE_CLOSING:
      pass
    WebSocketPeer.STATE_CLOSED:
      var code = remote_server_socket.get_close_code()
      # print("WebSocket closed with code: %d. Clean: %s" % [code, code != -1])
      connection_status = ConnectionStatus.Disconnected

func _input(event: InputEvent) -> void:
  if Input.is_action_just_pressed("DebugToggleNetwork"):
    if remote_server_socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
      debug_force_disconnected = true
      remote_server_socket.close()
    else:
      debug_force_disconnected = false
      # remote_server_socket = WebSocketPeer.new()
      # connection_status = ConnectionStatus.Disconnected
      # _try_connect_to_remote_server()