extends Node

const LOG_PATH := "user://saves/jave.log"

var _file: FileAccess


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(LOG_PATH.get_base_dir())
	_file = FileAccess.open(LOG_PATH, FileAccess.READ_WRITE if FileAccess.file_exists(LOG_PATH) else FileAccess.WRITE)
	if _file != null:
		_file.seek_end()


func info(message: String) -> void:
	print(message)
	if _file == null:
		return
	_file.store_line(message)
	_file.flush()


func _exit_tree() -> void:
	if _file != null:
		_file.close()
