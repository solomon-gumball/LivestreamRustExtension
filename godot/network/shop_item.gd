class_name ShopItem
extends Object

var price: float
var name: String
var description: String
var tier: int = 0
var preview_scale: float = 9.0
var model_center: Vector3 = Vector3(0, 0, 0)

static func FromData(data: Dictionary) -> ShopItem:
  if data["type"] == "wearable":
    return WearableShopItem.FromData(data)
  elif data["type"] == "emote":
    return EmoteShopItem.FromData(data)
  return null

class EmoteShopItem extends ShopItem:
  var type: String = 'emote'

  static func FromData(data: Dictionary) -> EmoteShopItem:
    var inst = EmoteShopItem.new()
    inst.price = data["price"]
    inst.name = data["name"]
    inst.tier = data["tier"]
    inst.description = data["description"]
    inst.preview_scale = data["preview_scale"]
    var model_data: Array[float] = []
    model_data.assign(data["model_center"])
    inst.model_center = Vector3(model_data[0], model_data[1], model_data[2])
    return inst

class WearableShopItem extends ShopItem:
  var type: String = 'wearable'

  class ShopItemMetadata:
    var slot: String
    var mesh_type: String
    var offset: Vector3 = Vector3(0, 0, 0)
    var rotation: Vector3 = Vector3(0, 0, 0)
    var attach_to: String
    var hide_meshes: Array[String] = []

  var metadata: ShopItemMetadata

  static func FromData(data: Dictionary) -> WearableShopItem:
    var inst = WearableShopItem.new()
    inst.price = data["price"]
    inst.name = data["name"]
    inst.tier = data["tier"]
    inst.description = data["description"]
    inst.preview_scale = data["preview_scale"]
    inst.metadata = ShopItemMetadata.new()
    inst.metadata.slot = data["metadata"]["slot"]
    inst.metadata.mesh_type = data["metadata"]["mesh_type"]
    inst.metadata.attach_to = data["metadata"].get("attach_to", "")

    inst.metadata.hide_meshes.assign(data["metadata"]["hide_meshes"])

    if data["metadata"].has("offset"):
      inst.metadata.offset = Vector3(data["metadata"]["offset"][0], data["metadata"]["offset"][1], data["metadata"]["offset"][2])
    
    if data["metadata"].has("rotation"):
      inst.metadata.rotation = Vector3(data["metadata"]["rotation"][0], data["metadata"]["rotation"][1], data["metadata"]["rotation"][2])

    var model_data: Array[float] = []
    model_data.assign(data["model_center"])
    inst.model_center = Vector3(model_data[0], model_data[1], model_data[2])
    return inst