class_name TextureCache
extends RefCounted

static var _textures: Dictionary[String, Texture2D] = {}


static func get_texture(path: String) -> Texture2D:
	var cached: Texture2D = _textures.get(path)
	if cached != null or path.is_empty():
		return cached
	var image := Image.load_from_file(path) if FileAccess.file_exists(path) else null
	if image == null:
		return null
	var texture := ImageTexture.create_from_image(image)
	_textures[path] = texture
	return texture


static func from_image(path: String, image: Image) -> Texture2D:
	var cached: Texture2D = _textures.get(path)
	if cached == null:
		cached = ImageTexture.create_from_image(image)
		_textures[path] = cached
	return cached
