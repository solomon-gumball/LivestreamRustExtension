extends Node

var _cache: Dictionary = {}
const IMAGE_CACHE_DIR = "user://image_cache/"  # Directory for image cache
const GLB_CACHE_DIR = "user://glb_cache/"  # Directory for GLB asset cache

func _ready():
    # Ensure cache directories exist
    _ensure_cache_dir(IMAGE_CACHE_DIR)
    _ensure_cache_dir(GLB_CACHE_DIR)

# Ensure a directory exists
func _ensure_cache_dir(dir_path: String):
    var dir = DirAccess.open("user://")
    if not dir.dir_exists(dir_path):
        dir.make_dir(dir_path)

# Generate a cache filename using MD5 hash
func _generate_cache_filename(url: String, ext: String) -> String:
    var hash_text = url.md5_text()
    return "%s.%s" % [hash_text, ext]

func load_asset_thumbnail(asset_name: String) -> ImageTexture:
  var url := WSClient.get_database_server_url("items/%s.png" % asset_name.to_lower())
  return await load_image(url)

var debug_logging := false

# Load an image from cache or download it
func load_image(url: String, save_to_disk: bool = true, no_cached: bool = false) -> ImageTexture:
    var filename = IMAGE_CACHE_DIR + _generate_cache_filename(url, "png")

    if !no_cached:
        if _cache.has(filename):
            if debug_logging: print("LOADER: Cached from MEMORY: ", url)
            return _cache[filename]

        # Check disk cache
        if FileAccess.file_exists(filename):
            if debug_logging: print("LOADER: Cached from FILE: ", url)
            var img = Image.new()
            var err = img.load(filename)
            if err == OK:
                var img_texture = ImageTexture.create_from_image(img)
                _cache[filename] = img_texture
                return img_texture

    if debug_logging: print("[LOADER] url not cached: ", url)
    # Download if not cached
    var request = AwaitableHTTPRequest.new()
    add_child(request)
    var response := await request.async_request(url)
    request.queue_free()

    if response.success() and response.status_ok():
        var img = Image.new()
        var err = img.load_png_from_buffer(response.bytes)
        if err == OK:
            if save_to_disk:
                img.save_png(filename)

            var img_texture = ImageTexture.create_from_image(img)
            _cache[filename] = img_texture
            return img_texture

    return null

func force_clear_cache() -> void:
    _cache.clear()
    _clear_dir(IMAGE_CACHE_DIR)
    _clear_dir(GLB_CACHE_DIR)

func _clear_dir(dir_to_clear: String) -> void:
    var dir = DirAccess.open(dir_to_clear)
    if dir:
        dir.list_dir_begin()
        var file_name = dir.get_next()
        while file_name != "":
            if not dir.current_is_dir():
                dir.remove(file_name)
            file_name = dir.get_next()
        dir.list_dir_end()

func load_wearable_asset(asset_name: String) -> Node3D:
  var url = "%s/items/%s.glb" % [WSClient.get_database_server_url(), asset_name]
  return await load_glb(url, false)

var _glb_cache: Dictionary[String, Node3D] = {}
# Load a GLB model from cache or download it
func load_glb(url: String, no_cached: bool = false) -> Node3D:
    var filename = GLB_CACHE_DIR + _generate_cache_filename(url, "glb")

    if !no_cached:
        # Check memory cache
        if _glb_cache.has(filename):
            if debug_logging: print("LOADER: Cached from MEMORY: ", url)
            return _glb_cache[filename]

        # Check disk cache
        if FileAccess.file_exists(filename):
            var file = FileAccess.open(filename, FileAccess.READ)
            if debug_logging: print("LOADER: Cached from FILE: ", url)
            if file:
                var glb_data = file.get_buffer(file.get_length())
                file.close()
                var glb_scene = _parse_glb(glb_data)
                _glb_cache[filename] = glb_scene
                return glb_scene

    if debug_logging: print("[LOADER] url not cached: ", url)
    # Download if not cached
    var request = AwaitableHTTPRequest.new()
    add_child(request)
    var response := await request.async_request(url)
    request.queue_free()
    if debug_logging: print("done fetching ", url)

    if response.success() and response.status_ok():
        var glb_data = response.bytes

        # Save GLB to disk
        var file = FileAccess.open(filename, FileAccess.WRITE)
        if file:
            file.store_buffer(glb_data)
            file.close()

        var glb_scene = _parse_glb(glb_data)
        _glb_cache[filename] = glb_scene
        return glb_scene
    else:
      print("ERROR LOADING ASSET: ", response._error, url)

    return null

# Parse GLB data into a Node3D
func _parse_glb(glb_data: PackedByteArray) -> Node3D:
    var gltf = GLTFDocument.new()
    var state = GLTFState.new()

    var err = gltf.append_from_buffer(glb_data, "", state)
    if err != OK:
        push_error("Failed to parse GLB")
        return null

    var glb_scene = gltf.generate_scene(state) as Node3D
    if glb_scene:
        return glb_scene
    else:
        push_error("Failed to create scene from GLB")
        return null

# Load an emote image
func load_emote(emote_id: String) -> ImageTexture:
    var url = "https://static-cdn.jtvnw.net/emoticons/v1/%s/3.0" % emote_id
    return await load_image(url)
