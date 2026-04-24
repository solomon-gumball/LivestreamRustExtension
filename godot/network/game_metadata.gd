class_name GameMetadata

var thumbnail_url: String
var bundle_url: String
var title: String
var description: String
var entry: String
var cost: int
var min_players: int
var max_players: int
var pck_hash: String

static func FromData(data: Dictionary) -> GameMetadata:
  var metadata := GameMetadata.new()
  metadata.thumbnail_url = data.get("thumbnail_url", "")
  metadata.bundle_url = data.get("bundle_url", "")
  metadata.title = data.get("title", "")
  metadata.description = data.get("description", "")
  metadata.entry = data.get("entry", "")
  metadata.cost = data.get("cost", 0)
  metadata.min_players = data.get("min_players", 0)
  metadata.max_players = data.get("max_players", 0)
  metadata.pck_hash = data.get("pck_hash", "")
  return metadata
