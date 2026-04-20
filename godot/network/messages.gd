extends Object
class_name Message

class Chat:
  var message: String
  var chatter: Chatter

  static func FromData(data: Dictionary) -> Chat:
    var inst = Chat.new()
    inst.message = data["message"]
    inst.chatter = Chatter.FromData(data["chatter"])
    return inst

class SlotsRequest extends QueueAction:
  var message: String
  var chatter: Chatter
  var multiplier: int

  static func FromData(data: Dictionary) -> SlotsRequest:
    var inst = SlotsRequest.new()
    inst.uuid = data["uuid"]
    inst.message = data["message"]
    inst.multiplier = data["multiplier"]
    inst.chatter = Chatter.FromData(data["chatter"])
    return inst

class QueueAction:
  var uuid: String

class PrimaryNotification:
  var type: String
  var primary_text: String
  var secondary_text: String

  static func FromData(data: Dictionary) -> PrimaryNotification:
    var inst = PrimaryNotification.new()
    inst.type = data["type"]
    inst.primary_text = data["primary_text"]
    inst.secondary_text = data["secondary_text"]
    return inst

class OnScreenNotification:
  var type: String
  var messageText: String

  static func FromData(data: Dictionary) -> OnScreenNotification:
    var inst = OnScreenNotification.new()
    inst.type = data["type"]
    inst.messageText = data["messageText"]
    return inst

class ShowMailRequest extends QueueAction:
  var mail: Mail
  var chatter: Chatter

  class Mail:
    var id: int
    var image_url: String
    var sender_id: String
    var approved: bool
    var created_at: float = 0.0

    static func FromData(data: Dictionary) -> Mail:
      var inst = Mail.new()
      inst.image_url = data["image_url"]
      inst.sender_id = data["sender_id"]
      inst.approved = data["approved"]
      # inst.created_at = data["created_at"]
      return inst

  static func FromData(data: Dictionary) -> ShowMailRequest:
    var inst = ShowMailRequest.new()
    inst.uuid = data["uuid"]
    inst.mail = Mail.FromData(data["mail"])
    inst.chatter = Chatter.FromData(data["chatter"])
    return inst

class TTSRequest extends QueueAction:
  var message: String
  var chatter: Chatter

  static func FromData(data: Dictionary) -> TTSRequest:
    var inst = TTSRequest.new()
    inst.uuid = data["uuid"]
    inst.message = data["message"]
    inst.chatter = Chatter.FromData(data["chatter"])
    return inst


class StoreData:
  var action_queue: Array[QueueAction] = []
  var active_chatters: Array[Chatter] = []
  var drops: DropData = null
  var market: Dictionary[String, ShopItem] = {}

  static func FromData(data: Dictionary) -> StoreData:
    var inst = StoreData.new()
    inst.action_queue = CreateActionQueue(data["action_queue"])
    for chatter in data["active_chatters"]:
      inst.active_chatters.append(Chatter.FromData(chatter))
    inst.drops = DropData.FromData(data["drops"])
    var market_data: Dictionary = data.get("market", {})
    for item_key in market_data:
      inst.market[item_key] = ShopItem.FromData(market_data[item_key])
    return inst

  static func CreateActionQueue(raw_arr: Array) -> Array[QueueAction]:
    var queue: Array[QueueAction] = []
    for action in raw_arr:
      if WSClient.recently_completed_actions.has(action["uuid"]):
        continue
      if action["type"] == "twitch-tts":
        queue.append(Message.TTSRequest.FromData(action))
      elif action["type"] == "twitch-slots":
        queue.append(Message.SlotsRequest.FromData(action))
      elif action["type"] == "show-mail":
        queue.append(ShowMailRequest.FromData(action))

    return queue

class DropData:
  var coins: int
  var stacks: int

  static func FromData(data: Dictionary) -> DropData:
    var inst = DropData.new()
    if data["coins"] == null:
      data["coins"] = 0
    else:
      inst.coins = data["coins"]
    
    if data["stacks"] == null:
      inst.stacks = 0
    else:
      inst.stacks = data["stacks"]
    return inst
