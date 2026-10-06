class_name CharacterAsset
extends RefCounted

var base := ""
var meta: Dictionary = {}
var speaker: CharacterAsset
var frames: SpriteFrames

var _paths_by_pose: Dictionary = {}
var _images_by_path: Dictionary = {}


func _init(character_base: String) -> void:
	base = character_base


## Disk reads and PNG decoding only, so it can run on a worker thread.
func load_from_disk() -> void:
	var json: Variant = JsonRead.load_file(base.path_join("animation.json"))
	meta = json if json is Dictionary else {}
	for pose_name in SpriteFramesBuilder.POSE_NAMES:
		var paths := SpriteFramesBuilder.frame_paths(base, pose_name)
		_paths_by_pose[pose_name] = paths
		for path in paths:
			var image := Image.load_from_file(path)
			if image != null:
				_images_by_path[path] = image
	var speaker_path := JsonRead.string(JsonRead.object(meta, "speaker"), "assetPath")
	if not speaker_path.is_empty():
		speaker = CharacterAsset.new(base.path_join(speaker_path).simplify_path())
		speaker.load_from_disk()


func build_frames() -> void:
	frames = SpriteFramesBuilder.build(meta, _paths_by_pose, _images_by_path)
	_images_by_path.clear()
	if speaker != null:
		speaker.build_frames()


func pose_metadata(pose_name: String) -> Dictionary:
	return JsonRead.object(meta, pose_name)
