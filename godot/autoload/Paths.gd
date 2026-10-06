extends Node

const CONTENT_ROOT := "res://content"
const USER_ROOT := "user://"
const USER_CONFIG := "user://config"
const USER_SAVES := "user://saves"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(USER_CONFIG)
	DirAccess.make_dir_recursive_absolute(USER_SAVES)


func content(relative: String) -> String:
	return CONTENT_ROOT.path_join(relative)


func user(relative: String) -> String:
	return USER_ROOT.path_join(relative)


## Writable twin of a read-only res:// path (res://x -> user://x); user:// paths are returned unchanged.
func user_mirror(path: String) -> String:
	return USER_ROOT.path_join(path.trim_prefix("res://")) if path.begins_with("res://") else path
