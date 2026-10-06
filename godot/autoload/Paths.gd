extends Node

const CONTENT_ROOT := "res://content"
const USER_ROOT := "user://"
const USER_FOLDERS: PackedStringArray = ["config", "mods", "saves"]


func _ready() -> void:
	prepare_user_root(USER_ROOT)


func content(relative: String) -> String:
	return CONTENT_ROOT.path_join(relative)


func user(relative: String) -> String:
	return USER_ROOT.path_join(relative)


## Writable twin of a read-only res:// path (res://x -> user://x); user:// paths are returned unchanged.
func user_mirror(path: String) -> String:
	return USER_ROOT.path_join(path.trim_prefix("res://")) if path.begins_with("res://") else path


## Settings defaults are never copied here: they always come from the shipped config/default.json.
static func prepare_user_root(user_root: String) -> void:
	for folder in USER_FOLDERS:
		DirAccess.make_dir_recursive_absolute(user_root.path_join(folder))
