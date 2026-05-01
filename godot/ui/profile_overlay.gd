extends CanvasLayer
class_name ProfileOverlay

@onready var categories_hbox: HBoxContainer = %CategoriesHBox
@onready var items_grid: GridContainer = %ItemsGrid

var grid_items: Array[ScreenSquare] = []

var chatter: Chatter:
  set(v):
    chatter = v
    _update_grid_items()

func _handle_item_selected(value: String) -> void:
  if !value.is_empty():
    WSClient.wear_item(value)

var loading_icon: CompressedTexture2D = preload("res://ui/icons/missing.png")

func _update_grid_items() -> void:
  if !is_node_ready() or chatter == null: return

  var slot_wearables: Array[ShopItem.WearableShopItem] = []
  for asset_name in chatter.assets:
    var asset = WSClient.authenticated_state.get_item_info(asset_name)
    if asset is not ShopItem.WearableShopItem:
      continue
    var wearable := asset as ShopItem.WearableShopItem
    if wearable.metadata.slot == selected_category:
      slot_wearables.append(wearable)

  var asset_index := 0
  for grid_item in grid_items:
    if slot_wearables.size() > asset_index:
      var wearable_item = slot_wearables[asset_index]
      var captured_grid_item = grid_item
      var cached = ImageLoader.load_asset_thumbnail(wearable_item.name, func(tex, _url):
        if is_instance_valid(captured_grid_item):
          captured_grid_item.icon_texture = tex)
      if cached:
        grid_item.icon_texture = cached
      else:
        grid_item.icon_texture = loading_icon
      
      asset_index += 1
      grid_item.value = wearable_item.name
    else:
      grid_item.value = ""
      grid_item.icon_texture = null

var transition_interval := 0.04
var selected_category: String = "headgear":
  set(category):
    selected_category = category
    for category_square in category_squares:
      category_square.icon_color = Color.WHITE if category_square.value == category else Color(1.0, 1.0, 1.0, 0.5)
    for grid_item in grid_items:
      grid_item.transition(false)
      await get_tree().create_timer(transition_interval).timeout
    
    await get_tree().create_timer(0.2).timeout
    _update_grid_items()

    for grid_item in grid_items:
      grid_item.transition(true)
      await get_tree().create_timer(transition_interval).timeout

var category_squares: Array[ScreenSquare] = []

class ApparelCategory:
  var key: String
  var icon: Texture2D
  
  static func from_data(in_key: String, in_icon: Texture2D) -> ApparelCategory:
    var category = ApparelCategory.new()
    category.key = in_key
    category.icon = in_icon
    return category

func _ready() -> void:
  for screen_square in items_grid.get_children():
    if screen_square is ScreenSquare:
      grid_items.append(screen_square as ScreenSquare)
      (screen_square as ScreenSquare).on_selected.connect(_handle_item_selected)
  
  for category_square in categories_hbox.get_children():
    var square := category_square as ScreenSquare
    category_squares.append(square)
    square.on_selected.connect(func(value): selected_category = value)

  selected_category = selected_category
