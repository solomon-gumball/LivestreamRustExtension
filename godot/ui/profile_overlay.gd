extends CanvasLayer
class_name ProfileOverlay

@onready var categories_hbox: HBoxContainer = %CategoriesHBox
@onready var items_grid: GridContainer = %ItemsGrid

var grid_items: Array[ScreenSquare] = []
# var clothing_categories: Array[ApparelCategory] = [
#   ApparelCategory.from_data("headgear", preload("res://ui/Headgear_icon.svg")),
#   ApparelCategory.from_data("right_hand_item", preload("res://ui/hand_icon.svg")),
#   ApparelCategory.from_data("tail", preload("res://ui/Tail_icon.svg")),
#   ApparelCategory.from_data("torso", preload("res://ui/Torso_icon.svg")),
#   ApparelCategory.from_data("legs", preload("res://ui/Footwear_icon.svg"))
# ]

var chatter: Chatter:
  set(v):
    chatter = v
    _update_grid_items()

func _handle_item_selected(value: String) -> void:
  Network.wear_item(value)

func _update_grid_items() -> void:
  if !is_node_ready() or chatter == null: return

  var slot_wearables: Array[WearableShopItem] = []
  for asset_name in chatter.assets:
    var asset = Network.get_item_info(asset_name)
    if asset is not WearableShopItem:
      continue
    var wearable := asset as WearableShopItem
    if wearable.metadata.slot == selected_category:
      slot_wearables.append(wearable)

  var asset_index := 0
  for grid_item in grid_items:
    if slot_wearables.size() > asset_index:
      var wearable_item = slot_wearables[asset_index]
      grid_item.icon_texture = await ImageLoader.load_asset_thumbnail(wearable_item.name)
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
  
  static func from_data(key: String, icon: Texture2D) -> ApparelCategory:
    var category = ApparelCategory.new()
    category.key = key
    category.icon = icon
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
