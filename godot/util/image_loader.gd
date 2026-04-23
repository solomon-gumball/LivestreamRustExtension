extends Node

var _cache: Dictionary = {}
var _glb_cache: Dictionary[String, Node3D] = {}
const IMAGE_CACHE_DIR = "user://image_cache/"
const GLB_CACHE_DIR = "user://glb_cache/"

# url -> Array of Callables waiting for the result
var _pending_image_callbacks: Dictionary = {}
var _pending_glb_callbacks: Dictionary = {}

var debug_logging := false

func _ready():
	_ensure_cache_dir(IMAGE_CACHE_DIR)
	_ensure_cache_dir(GLB_CACHE_DIR)

func _ensure_cache_dir(dir_path: String):
	var dir = DirAccess.open("user://")
	if not dir.dir_exists(dir_path):
		dir.make_dir(dir_path)

func _generate_cache_filename(url: String, ext: String) -> String:
	var hash_text = url.md5_text()
	return "%s.%s" % [hash_text, ext]

# Load an image. Returns cached texture immediately if available, otherwise null.
# callback(texture: ImageTexture, url: String) is called once when the load completes.
# If cached, callback fires synchronously before this function returns.
func load_image(url: String, callback: Callable = Callable(), save_to_disk: bool = true, no_cached: bool = false) -> ImageTexture:
	var filename = IMAGE_CACHE_DIR + _generate_cache_filename(url, "png")

	if !no_cached:
		if _cache.has(filename):
			if debug_logging: print("LOADER: Cached from MEMORY: ", url)
			if callback.is_valid():
				callback.call(_cache[filename], url)
			return _cache[filename]

		if FileAccess.file_exists(filename):
			if debug_logging: print("LOADER: Cached from FILE: ", url)
			var img = Image.new()
			var err = img.load(filename)
			if err == OK:
				var img_texture = ImageTexture.create_from_image(img)
				_cache[filename] = img_texture
				if callback.is_valid():
					callback.call(img_texture, url)
				return img_texture

	if callback.is_valid():
		if !_pending_image_callbacks.has(filename):
			_pending_image_callbacks[filename] = []
			_fetch_image(url, filename, save_to_disk)
		_pending_image_callbacks[filename].append(callback)

	return null

func _fetch_image(url: String, filename: String, save_to_disk: bool) -> void:
	if debug_logging: print("[LOADER] url not cached: ", url)
	var request = AwaitableHTTPRequest.new()
	add_child(request)
	var response := await request.async_request(url)
	request.queue_free()

	var result: ImageTexture = null
	if response.success() and response.status_ok():
		var img = Image.new()
		var err = img.load_png_from_buffer(response.bytes)
		if err == OK:
			if save_to_disk:
				img.save_png(filename)
			result = ImageTexture.create_from_image(img)
			_cache[filename] = result

	var callbacks: Array = _pending_image_callbacks.get(filename, [])
	_pending_image_callbacks.erase(filename)
	for cb in callbacks:
		cb.call(result, url)

# Load a GLB model. Returns cached Node3D immediately if available, otherwise null.
# callback(node: Node3D, url: String) is called once when the load completes.
# If cached, callback fires synchronously before this function returns.
func load_glb(url: String, callback: Callable = Callable(), no_cached: bool = false) -> Node3D:
	var filename = GLB_CACHE_DIR + _generate_cache_filename(url, "glb")

	if !no_cached:
		if _glb_cache.has(filename):
			if debug_logging: print("LOADER: Cached from MEMORY: ", url)
			if callback.is_valid():
				callback.call(_glb_cache[filename], url)
			return _glb_cache[filename]

		if FileAccess.file_exists(filename):
			if debug_logging: print("LOADER: Cached from FILE: ", url)
			var file = FileAccess.open(filename, FileAccess.READ)
			if file:
				var glb_data = file.get_buffer(file.get_length())
				file.close()
				var glb_scene = _parse_glb(glb_data)
				_glb_cache[filename] = glb_scene
				if callback.is_valid():
					callback.call(glb_scene, url)
				return glb_scene

	if callback.is_valid():
		if !_pending_glb_callbacks.has(filename):
			_pending_glb_callbacks[filename] = []
			_fetch_glb(url, filename)
		_pending_glb_callbacks[filename].append(callback)

	return null

func _fetch_glb(url: String, filename: String) -> void:
	if debug_logging: print("[LOADER] url not cached: ", url)
	var request = AwaitableHTTPRequest.new()
	add_child(request)
	var response := await request.async_request(url)
	request.queue_free()
	if debug_logging: print("done fetching ", url)

	var result: Node3D = null
	if response.success() and response.status_ok():
		var glb_data = response.bytes
		var file = FileAccess.open(filename, FileAccess.WRITE)
		if file:
			file.store_buffer(glb_data)
			file.close()
		result = _parse_glb(glb_data)
		_glb_cache[filename] = result
	else:
		print("ERROR LOADING ASSET: ", response._error, url)

	var callbacks: Array = _pending_glb_callbacks.get(filename, [])
	_pending_glb_callbacks.erase(filename)
	for cb in callbacks:
		cb.call(result, url)

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
	push_error("Failed to create scene from GLB")
	return null

func load_asset_thumbnail(asset_name: String, callback: Callable = Callable()) -> ImageTexture:
	var url := WSClient.get_database_server_url("items/%s.png" % asset_name.to_lower())
	return load_image(url, callback)

func load_emote(emote_id: String, callback: Callable = Callable()) -> ImageTexture:
	var url = "https://static-cdn.jtvnw.net/emoticons/v1/%s/3.0" % emote_id
	return load_image(url, callback)

func load_wearable_asset(asset_name: String, callback: Callable = Callable()) -> Node3D:
	var url = "%s/items/%s.glb" % [WSClient.get_database_server_url(), asset_name]
	return load_glb(url, callback, false)

func force_clear_cache() -> void:
	_cache.clear()
	_glb_cache.clear()
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
