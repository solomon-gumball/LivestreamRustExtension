class_name GameMetadata

var thumbnail_url: String
var bundle_url: String
var title: String
var description: String
var entry: String
var cost: int
var min_players: int
var max_players: int

static func FromData(data: Dictionary) -> GameMetadata:
  var metadata := GameMetadata.new()
  metadata.thumbnail_url = data["thumbnail_url"]
  metadata.bundle_url = data["bundle_url"]
  metadata.title = data["title"]
  metadata.description = data["description"]
  metadata.entry = data["entry"]
  metadata.cost = data["cost"]
  metadata.min_players = data["min_players"]
  metadata.max_players = data["max_players"]
  return metadata
