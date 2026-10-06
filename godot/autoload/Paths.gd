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
