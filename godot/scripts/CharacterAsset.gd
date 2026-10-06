class_name CharacterAsset
extends RefCounted

var base := ""
var meta: Dictionary = {}
var speaker: CharacterAsset
var frames: SpriteFrames
var pose_names: Array[StringName] = []

var _paths_by_pose: Dictionary = {}
var _hash_by_path: Dictionary = {}
var _image_by_hash: Dictionary = {}


func _init(character_base: String, poses: Array[StringName] = SpriteFramesBuilder.POSE_NAMES) -> void:
	base = character_base
	pose_names = poses


## Disk reads, hashing and PNG decoding only, so it can run on a worker thread. Frames are hashed
## first so each distinct image is decoded once, and not at all when its texture is already cached.
func load_from_disk() -> void:
	var json: Variant = JsonRead.load_file(base.path_join("animation.json"))
	meta = json if json is Dictionary else {}
	var paths := PackedStringArray()
	for pose_name in pose_names:
		var pose_paths := SpriteFramesBuilder.frame_paths(base, pose_name)
		_paths_by_pose[pose_name] = pose_paths
		paths.append_array(pose_paths)
	var hashes: Array[String] = []
	hashes.resize(paths.size())
	_run_parallel(func(index: int) -> void: hashes[index] = TextureCache.content_hash(paths[index]), paths.size())
	var first_path_by_hash: Dictionary = {}
	for index in paths.size():
		_hash_by_path[paths[index]] = hashes[index]
		if not first_path_by_hash.has(hashes[index]) and not TextureCache.has_frame(hashes[index]):
			first_path_by_hash[hashes[index]] = paths[index]
	var missing: Array = first_path_by_hash.keys()
	var images: Array[Image] = []
	images.resize(missing.size())
	_run_parallel(func(index: int) -> void: images[index] = Image.load_from_file(first_path_by_hash[missing[index]]), missing.size())
	for index in missing.size():
		_image_by_hash[missing[index]] = images[index]
	var speaker_path := JsonRead.string(JsonRead.object(meta, "speaker"), "assetPath")
	if not speaker_path.is_empty():
		speaker = CharacterAsset.new(base.path_join(speaker_path).simplify_path(), [SpriteFramesBuilder.POSE_NAMES[0]])
		speaker.load_from_disk()


## Main thread only: creates the textures the worker decoded.
func build_frames() -> void:
	var textures_by_path: Dictionary = {}
	for path: String in _hash_by_path:
		var content_hash: String = _hash_by_path[path]
		textures_by_path[path] = TextureCache.frame(content_hash, _image_by_hash.get(content_hash), path)
	frames = SpriteFramesBuilder.build(meta, _paths_by_pose, textures_by_path)
	_image_by_hash.clear()
	if speaker != null:
		speaker.build_frames()


func pose_metadata(pose_name: String) -> Dictionary:
	return JsonRead.object(meta, pose_name)


static func _run_parallel(action: Callable, count: int) -> void:
	if count <= 0:
		return
	var task := WorkerThreadPool.add_group_task(action, count, -1, true, "Load character frames")
	WorkerThreadPool.wait_for_group_task_completion(task)
