extends Node
class_name TTSService

const AZURE_API_KEY = "REPLACE_ME"
const AZURE_REGION = "eastus"

const AZURE_TTS_URL = "https://%s.tts.speech.microsoft.com/cognitiveservices/v1" % AZURE_REGION
var stream_player: AudioStreamPlayer
var voices: Array[String] = []

signal did_finish()

func _ready():
  stream_player = AudioStreamPlayer.new()
  add_child(stream_player)
  var parsed_voices = read_json_file("res://src/shared/voices.json")
  voices.assign(parsed_voices)

func read_json_file(file_path: String) -> Array:
    if not FileAccess.file_exists(file_path):
        print("File not found: " + file_path)
        return []
    
    var file = FileAccess.open(file_path, FileAccess.READ)
    var content = file.get_as_text()
    file.close()
    
    var json = JSON.new()
    var error = json.parse(content)
    
    if error != OK:
        print("Failed to parse JSON")
        return []
    
    var result = json.get_data()
    
    if result is Array:
        return result
    else:
        print("Unexpected JSON format")
        return []

class TTSData:
  var voice_index: int
  var text: String

  func to_xml(voices: Array[String]) -> String:
    return "<voice name='%s'>%s</voice>" % [voices[voice_index % voices.size()], text]

  static func Create(voice_index: int, text: String) -> TTSData:
    var data = TTSData.new()
    data.voice_index = voice_index
    data.text = TTSService.escape_ssml(text)
    return data

# Function to parse and extract voice sequences
func parse_message(raw_content: String) -> Array[TTSData]:
    var segments: Array[TTSData] = []
    var regex = RegEx.new()
    var number_of_voices = voices.size()

    # Matches [n] at the start of a segment and captures the voice index
    regex.compile("\\[(\\d+)\\]\\s*([^\\[]*)")

    var results = regex.search_all(raw_content)
    var last_match_end = 0  # Track where the last regex match ended

    # Check if there's text **before** the first [n] tag
    if results.size() > 0:
        var first_match = results[0]
        if first_match.get_start() > 0:
            var leading_text = raw_content.substr(0, first_match.get_start()).strip_edges()
            if leading_text != "":
                segments.append(TTSData.Create(1, leading_text))  # Default to voice 1

    # Process voice-tagged segments
    for result in results:
        var voice_index = int(result.get_string(1))
        var text = result.get_string(2).strip_edges()

        if voice_index < 1 or voice_index > number_of_voices:
            voice_index = 1  # Default to first voice if index is invalid

        segments.append(TTSData.Create(voice_index, text))
        last_match_end = result.get_end()  # Track the end of the last match

    # Check if there's remaining text **after** the last [n] tag
    if last_match_end < raw_content.length():
        var trailing_text = raw_content.substr(last_match_end).strip_edges()
        if trailing_text != "":
            segments.append(TTSData.Create(1, trailing_text))  # Default to voice 1

    return segments

static func escape_ssml(text: String) -> String:
    return text.replace("&", "&amp;") \
                .replace("<", "&lt;") \
                .replace(">", "&gt;") \
                .replace("\"", "&quot;") \
                .replace("'", "&apos;")

var skip_noise = load("res://src/tts/tts_skip.mp3")
func stop():
  stream_player.stop()
  stream_player.stream = skip_noise
  stream_player.volume_db = -10
  stream_player.play()
  did_finish.emit()

func request_tts(message: Message.TTSRequest):
  var raw_content = message.message
  var request = AwaitableHTTPRequest.new()
  add_child(request)

  # var voice_id = voices[voice_index % number_of_voices]
  var tts_datas = parse_message(raw_content)
  const string_array: Array[String] = []
  string_array.assign(tts_datas.map(func (x): return x.to_xml(voices)))
  var out = ""

  # var out = TTSData.Create(1, raw_content.strip_edges()).to_xml(voices)
  for segment in string_array:
    out += "\n" + segment

  var headers: PackedStringArray = [
      "Ocp-Apim-Subscription-Key: " + AZURE_API_KEY,
      "Content-Type: application/ssml+xml",
      "X-Microsoft-OutputFormat: raw-24khz-16bit-mono-pcm"  # Request raw PCM audio
  ]
  # "[15] This is the fifteenth voice [3] This is the third voice [1] This is the first voice"

  var ssml = """
      <speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='en-US'>
          %s
      </speak>
  """ % [out]

  var response := await request.async_request(AZURE_TTS_URL, headers, HTTPClient.METHOD_POST, ssml)

  if response.success() and response.status_ok():
    var audio_stream = AudioStreamWAV.new()
    audio_stream.format = AudioStreamWAV.FORMAT_16_BITS
    audio_stream.mix_rate = 24000
    audio_stream.data = response.bytes

    stream_player.volume_db = 0
    stream_player.stream = audio_stream
    stream_player.play()
    await stream_player.finished
    did_finish.emit()
  else:
    print("Error with TTS request")
    # print("Error: %s" % response.status_code)

  request.queue_free()
