extends NetworkHandler

func _ready() -> void:
  base_init()

  if OS.get_name() == "Web":
    callback = JavaScriptBridge.create_callback(_on_twitch_authorized)
    JavaScriptBridge.get_interface("window").twitchTokenCallback = callback

var callback: JavaScriptObject

func _on_twitch_authorized(args: Array) -> void:
  set("auth_token", str(args[0]))
  print("Twitch auth token received")
