## Textures keyed by path, plus character frames keyed by file content so identical frames
## (repeated across poses and character variants) share one texture. Thread-safe.
class_name TextureCache
extends RefCounted

static var _textures: Dictionary[String, Texture2D] = {}
static var _frames: Dictionary[String, Texture2D] = {}
static var _hashes: Dictionary[String, String] = {}
static var _mutex := Mutex.new()


static func get_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	_mutex.lock()
	var cached: Texture2D = _textures.get(path)
	_mutex.unlock()
	if cached != null:
		return cached
	var image := Image.load_from_file(path) if FileAccess.file_exists(path) else null
	return from_image(path, image) if image != null else null


## Drops path-keyed textures and remembered hashes under a folder, so files replaced on disk (a reinstalled mod)
## load fresh even when their modification time matches. Frames stay shared by content, so an unchanged frame is reused.
static func forget_under(folder: String) -> void:
	var prefix := folder.trim_suffix("/") + "/"
	_mutex.lock()
	for path: String in _textures.keys():
		if path.begins_with(prefix):
			_textures.erase(path)
	for key: String in _hashes.keys():
		if key.begins_with(prefix):
			_hashes.erase(key)
	_mutex.unlock()


static func from_image(path: String, image: Image) -> Texture2D:
	_mutex.lock()
	var cached: Texture2D = _textures.get(path)
	if cached == null:
		cached = ImageTexture.create_from_image(image)
		_textures[path] = cached
	_mutex.unlock()
	return cached


## MD5 of the file, remembered per path and modification time so reloading a character skips rereading its frames.
static func content_hash(path: String) -> String:
	var key := "%s|%d" % [path, FileAccess.get_modified_time(path)]
	_mutex.lock()
	var known: String = _hashes.get(key, "")
	_mutex.unlock()
	if not known.is_empty():
		return known
	var computed := FileAccess.get_md5(path)
	_mutex.lock()
	_hashes[key] = computed
	_mutex.unlock()
	return computed


static func has_frame(content_hash: String) -> bool:
	_mutex.lock()
	var found := _frames.has(content_hash)
	_mutex.unlock()
	return found


## image may be null when the frame was already cached at load time; it is then read from path if it has since been pruned.
static func frame(content_hash: String, image: Image, path: String) -> Texture2D:
	_mutex.lock()
	var cached: Texture2D = _frames.get(content_hash)
	if cached == null:
		if image == null:
			image = Image.load_from_file(path)
		if image != null:
			cached = ImageTexture.create_from_image(image)
			_frames[content_hash] = cached
	_mutex.unlock()
	return cached


## Releases character frames nothing else holds, so memory follows the songs in use instead of every song played.
static func prune_frames() -> int:
	_mutex.lock()
	var released := 0
	for content_hash: String in _frames.keys():
		var texture: Texture2D = _frames[content_hash]
		# The dictionary and this local hold two references.
		if texture.get_reference_count() <= 2:
			_frames.erase(content_hash)
			released += 1
	_mutex.unlock()
	return released


static func frame_count() -> int:
	_mutex.lock()
	var count := _frames.size()
	_mutex.unlock()
	return count
