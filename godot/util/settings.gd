extends Node

var tts_enabled: bool = false:
  set(new_val):
    tts_enabled = new_val
    save_settings_to_disk()

var slots_enabled: bool = false:
  set(new_val):
    slots_enabled = new_val
    save_settings_to_disk()

var mute: bool = false:
  set(new_val):
    mute = new_val
    AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), mute)
    save_settings_to_disk()

func _ready():
  load_settings_from_disk()
  print(tts_enabled, slots_enabled, mute)

func save_settings_to_disk():
  var save_file = FileAccess.open("user://settings.save", FileAccess.WRITE)
  var save_data = {
    'mute': mute,
    'tts_enabled': tts_enabled,
    'slots_enabled': slots_enabled
  }
  var json_string = JSON.stringify(save_data)
  save_file.store_line(json_string)

func load_settings_from_disk():
  if not FileAccess.file_exists("user://settings.save"):
     # Error! We don't have a save to load.
    return
  var save_file = FileAccess.open("user://settings.save", FileAccess.READ)
  while save_file.get_position() < save_file.get_length():
    var json_string = save_file.get_line()
    var json = JSON.new()
    var parsed = json.parse(json_string)
    if not parsed == OK:
      print("JSON Parse Error: ", json.get_error_message(), " in ", json_string, " at line ", json.get_error_line())
      continue
    if json.data.has('mute'):
      mute = json.data['mute']
    if json.data.has('slots_enabled'):
      # slots_enabled = true
      slots_enabled = json.data['slots_enabled']
    if json.data.has('tts_enabled'):
      # tts_enabled = true
      tts_enabled = json.data['tts_enabled']
    
