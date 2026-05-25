class_name ShopPage
extends Control

@onready var items_grid: GridContainer = %ItemsGrid
var items: Array[ScreenSquare] = []

var loading_icon: CompressedTexture2D = preload("res://ui/icons/missing.png")

func _ready() -> void:
  for child in items_grid.get_children():
    if child is ScreenSquare:
      items.append(child as ScreenSquare)

  if WSClient.state.current is WSClient.AuthenticatedState:
    _load_shop_items()
  else:
    WSClient.authenticated.connect(_load_shop_items, CONNECT_ONE_SHOT)

func _load_shop_items() -> void:
  var item_names: Array[String] = await WSClient.fetch_shop()
  var item_index := 0
  for square in items:
    if item_names.size() > item_index:
      var item_name: String = item_names[item_index]
      square.value = item_name
      var captured_square = square
      var cached = ImageLoader.load_asset_thumbnail(item_name, func(tex, _url):
        if is_instance_valid(captured_square):
          captured_square.icon_texture = tex)
      if cached:
        square.icon_texture = cached
      else:
        square.icon_texture = loading_icon
      item_index += 1
    else:
      square.value = ""
      square.icon_texture = null
