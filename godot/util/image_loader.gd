# ImageLoader — async image and GLB asset loader with disk cache and optional multithreading.
#
# CACHE HIERARCHY (checked in order, first hit wins):
#   1. Memory cache (_cache / _glb_cache) — synchronous, fires callback immediately.
#   2. Disk cache (user://image_cache/ or user://glb_cache/) — see loading path below.
#   3. Network fetch via AwaitableHTTPRequest — non-blocking, uses await each frame.
#
# LOADING PATH (when threads are available, OS.has_feature("threads")):
#   Images (disk cache hit):
#     Worker thread  — img.load() reads and decodes PNG from disk.
#     Main thread    — ImageTexture.create_from_image() uploads to GPU, callback fires.
#
#   Images (network fetch):
#     Main thread    — await HTTP response (non-blocking).
#     Worker thread  — img.load_png_from_buffer() decodes bytes; img.save_png() writes to disk.
#     Main thread    — ImageTexture.create_from_image() uploads to GPU, callbacks fire.
#
#   GLBs (disk cache hit):
#     Worker thread  — FileAccess reads bytes; GLTFDocument.append_from_buffer() parses.
#     Main thread    — GLTFDocument.generate_scene() builds Node3D tree, callback fires.
#
#   GLBs (network fetch):
#     Main thread    — await HTTP response (non-blocking).
#     Worker thread  — file.store_buffer() writes to disk; GLTFDocument.append_from_buffer() parses.
#     Main thread    — GLTFDocument.generate_scene() builds Node3D tree, callbacks fire.
#
# When threads are NOT available (WASM without SharedArrayBuffer / crossOriginIsolated):
#   All work runs on the main thread. Disk writes after network fetches are call_deferred'd
#   to avoid blocking callbacks, and disk-cache GLB loads are call_deferred'd to avoid
#   blocking mid-frame. Everything else is synchronous.
#
# THREAD SAFETY NOTE:
#   ImageTexture.create_from_image() and GLTFDocument.generate_scene() both touch the
#   rendering server and must always run on the main thread — worker threads hand off via
#   call_deferred(). _threads holds all live Thread objects; _cleanup_finished_threads()
#   calls wait_to_finish() each frame to release them without blocking.
#
# DEDUPLICATION:
#   _pending_image_callbacks / _pending_glb_callbacks coalesce concurrent requests for the
#   same URL — only one fetch or disk read is started, and all registered callbacks fire
#   together when it completes.
extends Node

var _cache: Dictionary = {}
var _glb_cache: Dictionary[String, Node3D] = {}
const IMAGE_CACHE_DIR = "user://image_cache/"
const GLB_CACHE_DIR = "user://glb_cache/"

# url -> Array of Callables waiting for the result
var _pending_image_callbacks: Dictionary = {}
var _pending_glb_callbacks: Dictionary = {}

var _threads: Array[Thread] = []

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

func _start_thread(callable: Callable) -> void:
	var thread = Thread.new()
	_threads.append(thread)
	thread.start(callable)

func _cleanup_finished_threads() -> void:
	for i in range(_threads.size() - 1, -1, -1):
		if not _threads[i].is_alive():
			_threads[i].wait_to_finish()
			_threads.remove_at(i)

func _process(_delta: float) -> void:
	if OS.has_feature("threads"):
		_cleanup_finished_threads()

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
			if OS.has_feature("threads"):
				if callback.is_valid():
					_start_thread(_load_image_from_disk.bind(filename, url, callback))
				return null
			else:
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

# Runs on worker thread: decode PNG from disk, then marshal result to main thread.
func _load_image_from_disk(filename: String, url: String, callback: Callable) -> void:
	var img = Image.new()
	var err = img.load(filename)
	if err != OK:
		call_deferred("_finish_image", null, filename, url, [callback])
		return
	# ImageTexture.create_from_image must run on main thread
	call_deferred("_finish_image_from_disk", img, filename, url, callback)

# Runs on main thread: create GPU texture and fire callback.
func _finish_image_from_disk(img: Image, filename: String, url: String, callback: Callable) -> void:
	var img_texture = ImageTexture.create_from_image(img)
	_cache[filename] = img_texture
	if callback.is_valid():
		callback.call(img_texture, url)

func _fetch_image(url: String, filename: String, save_to_disk: bool) -> void:
	if debug_logging: print("[LOADER] url not cached: ", url)
	var request = AwaitableHTTPRequest.new()
	add_child(request)
	var response := await request.async_request(url)
	request.queue_free()

	if not (response.success() and response.status_ok()):
		_finish_image(null, filename, url, _pending_image_callbacks.get(filename, []))
		_pending_image_callbacks.erase(filename)
		return

	var bytes: PackedByteArray = response.bytes
	var callbacks: Array = _pending_image_callbacks.get(filename, [])
	_pending_image_callbacks.erase(filename)

	if OS.has_feature("threads"):
		_start_thread(_decode_image_bytes.bind(bytes, filename, url, save_to_disk, callbacks))
	else:
		var img = Image.new()
		var err = img.load_png_from_buffer(bytes)
		if err == OK:
			if save_to_disk:
				call_deferred("_save_image_to_disk", img, filename)
			var result = ImageTexture.create_from_image(img)
			_cache[filename] = result
			_finish_image(result, filename, url, callbacks)
		else:
			_finish_image(null, filename, url, callbacks)

# Runs on worker thread: decode PNG bytes, then marshal to main thread.
func _decode_image_bytes(bytes: PackedByteArray, filename: String, url: String, save_to_disk: bool, callbacks: Array) -> void:
	var img = Image.new()
	var err = img.load_png_from_buffer(bytes)
	if err != OK:
		call_deferred("_finish_image", null, filename, url, callbacks)
		return
	if save_to_disk:
		img.save_png(filename)
	# ImageTexture.create_from_image must run on main thread
	call_deferred("_finish_image_threaded", img, filename, url, callbacks)

# Runs on main thread: create GPU texture and fire all pending callbacks.
func _finish_image_threaded(img: Image, filename: String, url: String, callbacks: Array) -> void:
	var result = ImageTexture.create_from_image(img)
	_cache[filename] = result
	_finish_image(result, filename, url, callbacks)

func _finish_image(result: ImageTexture, _filename: String, url: String, callbacks: Array) -> void:
	for cb in callbacks:
		if cb.is_valid():
			cb.call(result, url)

func _save_image_to_disk(img: Image, filename: String) -> void:
	img.save_png(filename)

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
			if callback.is_valid():
				if OS.has_feature("threads"):
					_start_thread(_load_glb_from_disk_threaded.bind(filename, url, callback))
				else:
					call_deferred("_load_glb_from_disk", filename, url, callback)
			return null

	if callback.is_valid():
		if !_pending_glb_callbacks.has(filename):
			_pending_glb_callbacks[filename] = []
			_fetch_glb(url, filename)
		_pending_glb_callbacks[filename].append(callback)

	return null

# Runs on worker thread: read + parse GLB, then marshal to main thread for scene generation.
func _load_glb_from_disk_threaded(filename: String, url: String, callback: Callable) -> void:
	var file = FileAccess.open(filename, FileAccess.READ)
	if not file:
		return
	var glb_data = file.get_buffer(file.get_length())
	file.close()
	var gltf = GLTFDocument.new()
	var state = GLTFState.new()
	var err = gltf.append_from_buffer(glb_data, "", state)
	if err != OK:
		push_error("Failed to parse GLB")
		return
	# generate_scene creates Node3Ds — must run on main thread
	call_deferred("_finish_glb_from_disk", gltf, state, filename, url, callback)

# Runs on main thread: generate scene tree and fire callback.
func _finish_glb_from_disk(gltf: GLTFDocument, state: GLTFState, filename: String, url: String, callback: Callable) -> void:
	var glb_scene = gltf.generate_scene(state) as Node3D
	if glb_scene:
		_glb_cache[filename] = glb_scene
	if callback.is_valid():
		callback.call(glb_scene, url)

func _load_glb_from_disk(filename: String, url: String, callback: Callable) -> void:
	var file = FileAccess.open(filename, FileAccess.READ)
	if not file:
		return
	var glb_data = file.get_buffer(file.get_length())
	file.close()
	var glb_scene = _parse_glb(glb_data)
	_glb_cache[filename] = glb_scene
	if callback.is_valid():
		callback.call(glb_scene, url)

func _fetch_glb(url: String, filename: String) -> void:
	if debug_logging: print("[LOADER] url not cached: ", url)
	var request = AwaitableHTTPRequest.new()
	add_child(request)
	var response := await request.async_request(url)
	request.queue_free()
	if debug_logging: print("done fetching ", url)

	var callbacks: Array = _pending_glb_callbacks.get(filename, [])
	_pending_glb_callbacks.erase(filename)

	if not (response.success() and response.status_ok()):
		print("ERROR LOADING ASSET: ", response._error, url)
		_finish_glb(null, filename, url, callbacks)
		return

	var glb_data: PackedByteArray = response.bytes

	if OS.has_feature("threads"):
		_start_thread(_parse_glb_bytes_threaded.bind(glb_data, filename, url, callbacks))
	else:
		call_deferred("_save_glb_to_disk", glb_data, filename)
		var result = _parse_glb(glb_data)
		_glb_cache[filename] = result
		_finish_glb(result, filename, url, callbacks)

# Runs on worker thread: save to disk + parse GLB bytes, then marshal to main thread.
func _parse_glb_bytes_threaded(glb_data: PackedByteArray, filename: String, url: String, callbacks: Array) -> void:
	var file = FileAccess.open(filename, FileAccess.WRITE)
	if file:
		file.store_buffer(glb_data)
		file.close()
	var gltf = GLTFDocument.new()
	var state = GLTFState.new()
	var err = gltf.append_from_buffer(glb_data, "", state)
	if err != OK:
		push_error("Failed to parse GLB")
		call_deferred("_finish_glb", null, filename, url, callbacks)
		return
	# generate_scene must run on main thread
	call_deferred("_finish_glb_threaded", gltf, state, filename, url, callbacks)

# Runs on main thread: generate scene tree and fire all pending callbacks.
func _finish_glb_threaded(gltf: GLTFDocument, state: GLTFState, filename: String, url: String, callbacks: Array) -> void:
	var result = gltf.generate_scene(state) as Node3D
	if result:
		_glb_cache[filename] = result
	_finish_glb(result, filename, url, callbacks)

func _finish_glb(result: Node3D, _filename: String, url: String, callbacks: Array) -> void:
	for cb in callbacks:
		if cb.is_valid():
			cb.call(result, url)

func _save_glb_to_disk(glb_data: PackedByteArray, filename: String) -> void:
	var file = FileAccess.open(filename, FileAccess.WRITE)
	if file:
		file.store_buffer(glb_data)
		file.close()

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
	return load_image(url, callback, true, true)

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
