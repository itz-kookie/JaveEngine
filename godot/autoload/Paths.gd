extends Node

const CONTENT_ROOT := "res://content"
const USER_ROOT := "user://"
const USER_FOLDERS: PackedStringArray = ["config", "mods", "saves"]

## Holds the mods folder, mod states, settings and content overrides (see user() and user_mirror()).
## Tests point it at a scratch folder before the autoloads start, so they never read or change the player's.
static var user_root := USER_ROOT


func _ready() -> void:
	prepare_user_root(user_root)


func content(relative: String) -> String:
	return CONTENT_ROOT.path_join(relative)


func user(relative: String) -> String:
	return user_root.path_join(relative)


## Writable twin of a read-only res:// path (res://x -> user://x); user:// paths are returned unchanged.
func user_mirror(path: String) -> String:
	return user_root.path_join(path.trim_prefix("res://")) if path.begins_with("res://") else path


## Settings defaults are never copied here: they always come from the shipped config/default.json.
static func prepare_user_root(root: String) -> void:
	for folder in USER_FOLDERS:
		DirAccess.make_dir_recursive_absolute(root.path_join(folder))
