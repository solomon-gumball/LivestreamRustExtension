extends Object
class_name Chatter

var id: String
var display_name: String
var login: String

var color: String
var emote: String
var equipped: Dictionary = {}
var last_active: float = 0
var balance: int = 0
var messages_sent: int = 0

var created_at: String = ""
var duels_won: int = 0
var marbles_won: int = 0
var royales_won: int = 0
var gifts_given: int = 0

var assets: Array[String] = []

static var EXPIRE_TIME_MS: float = 20.0 * 60.0 # 20 minutes

func expires_in_ms():
  var current_time = Time.get_unix_time_from_system()
  var time_until_expires = (last_active + EXPIRE_TIME_MS) - current_time
  return time_until_expires

func get_age_days() -> float:
  var current_time = Time.get_unix_time_from_system()
  var time_until_expires = current_time - Time.get_unix_time_from_datetime_string(created_at)
  var days = time_until_expires / (60.0 * 60.0 * 24.0)
  # return rounded to nearest decimal
  return int(days * 10) / 10.0

static func FromData(data: Dictionary) -> Chatter:
  var inst = Chatter.new()

  inst.equipped = data["equipped"]
  inst.assets.assign(data["assets"])
  inst.id = data["id"]
  
  inst.created_at = data["created_at"]
  inst.duels_won = data["duels_won"]
  inst.marbles_won = data["marbles_won"]
  inst.royales_won = data["royales_won"]
  inst.gifts_given = data["gifts_given"]

  inst.display_name = data["display_name"]
  inst.login = data["login"]
  inst.balance = data["balance"]
  inst.messages_sent = data["messages_sent"]
  inst.color = data["color"] if data.has("color") else "#FFFFFF"
  inst.emote = data["emote"]
  inst.last_active = Time.get_unix_time_from_datetime_string(data["last_active"])
  return inst