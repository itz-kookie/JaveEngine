class_name SpriteFramesBuilder
extends RefCounted

const POSE_NAMES: Array[StringName] = [&"idle", &"left", &"down", &"up", &"right", &"danceRight", &"death"]
const DEATH_POSE := 5
const DEFAULT_FPS := 24.0


## Maps gameplay poses (-1 idle, 0-3 lanes, 4 danceRight, 5 death) to POSE_NAMES slots.
static func pose_slot(pose: int) -> int:
	return POSE_NAMES.size() - 1 if pose == DEATH_POSE else clampi(pose + 1, 0, POSE_NAMES.size() - 2)


static func frame_paths(base: String, pose_name: String) -> PackedStringArray:
	var directory := base.path_join(pose_name)
	var paths := PackedStringArray()
	if DirAccess.dir_exists_absolute(directory):
		for file in DirAccess.get_files_at(directory):
			if file.begins_with("frame_") and file.get_extension() == "png":
				paths.append(directory.path_join(file))
	paths.sort()
	if paths.is_empty():
		var single := base.path_join(pose_name + ".png")
		if FileAccess.file_exists(single):
			paths.append(single)
	return paths


static func animation_fps(meta: Dictionary, pose_name: String) -> float:
	return clampf(JsonRead.number(JsonRead.object(meta, pose_name), "fps", DEFAULT_FPS), 1.0, 120.0)


static func animation_loops(meta: Dictionary, pose_name: String) -> bool:
	return JsonRead.boolean(JsonRead.object(meta, pose_name), "loop", pose_name == "idle")


static func build(meta: Dictionary, paths_by_pose: Dictionary, textures_by_path: Dictionary) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	for pose_name in POSE_NAMES:
		var paths: PackedStringArray = paths_by_pose.get(pose_name, PackedStringArray())
		frames.add_animation(pose_name)
		frames.set_animation_speed(pose_name, animation_fps(meta, pose_name))
		frames.set_animation_loop(pose_name, animation_loops(meta, pose_name))
		for path in paths:
			var texture: Texture2D = textures_by_path.get(path)
			if texture != null:
				frames.add_frame(pose_name, texture)
	return frames
