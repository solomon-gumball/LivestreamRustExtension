class_name StartMenu
extends CanvasLayer

enum ExtensionPage { Profile, Multiplayer, Shop, Learderboard, Moderator }

@onready var profile_button: CustomButton = %ProfileButton
@onready var multiplayer_button: CustomButton = %MultiplayerButton
@onready var shop_button: CustomButton = %ShopButton
@onready var leaderboard_button: CustomButton = %LeaderboardButton
@onready var host_game_button: CustomButton = %ModeratorButton

signal trigger_navigate(page: ExtensionPage)

func _handle_connection_status_changed(state: WSClient.WSClientState) -> void:
  if state is WSClient.AuthenticatedState and WSClient.authenticated_state.current_chatter:
    host_game_button.visible = WSClient.is_moderator()
  else:
    host_game_button.visible = false

var selected_page: ExtensionPage = ExtensionPage.Multiplayer:
  set(new_page):
    selected_page = new_page

    profile_button.selected = selected_page == ExtensionPage.Profile
    multiplayer_button.selected = selected_page == ExtensionPage.Multiplayer
    shop_button.selected = selected_page == ExtensionPage.Shop
    leaderboard_button.selected = selected_page == ExtensionPage.Learderboard
    host_game_button.selected = selected_page == ExtensionPage.Moderator

func _ready() -> void:
  WSClient.state.changed.connect(_handle_connection_status_changed)
  _handle_connection_status_changed(WSClient.state.current)

  profile_button.pressed.connect(trigger_navigate.emit.bind(ExtensionPage.Profile))
  multiplayer_button.pressed.connect(trigger_navigate.emit.bind(ExtensionPage.Multiplayer))
  shop_button.pressed.connect(trigger_navigate.emit.bind(ExtensionPage.Shop))
  leaderboard_button.pressed.connect(trigger_navigate.emit.bind(ExtensionPage.Learderboard))
  host_game_button.pressed.connect(trigger_navigate.emit.bind(ExtensionPage.Moderator))

  trigger_navigate.emit(ExtensionPage.Multiplayer)
