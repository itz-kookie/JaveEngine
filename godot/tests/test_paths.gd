extends "res://tests/test_base.gd"

const TEMP_DIR := "user://test_paths_tmp"

var _paths_script: GDScript
var _content_script: GDScript
var _ran := false


## Autoload scripts only compile once the autoload globals exist, so they load lazily on the first frame.
func _initialize() -> void:
	pass


func _process(_delta: float) -> bool:
	if not _ran:
		_ran = true
		super._initialize()
	return false


func run() -> void:
	_paths_script = load("res://autoload/Paths.gd")
	_content_script = load("res://autoload/Content.gd")
	_remove_tree(TEMP_DIR)
	_test_first_run_layout()
	_test_defaults_come_from_shipped_config()
	_test_ogg_preference()
	_remove_tree(TEMP_DIR)
	check(not DirAccess.dir_exists_absolute(TEMP_DIR), "temporary directory removed")


func _test_first_run_layout() -> void:
	var root := TEMP_DIR.path_join("fresh")
	_paths_script.prepare_user_root(root)
	for folder in ["config", "mods", "saves"]:
		check(DirAccess.dir_exists_absolute(root.path_join(folder)), "first run creates " + folder)
	check(DirAccess.get_files_at(root.path_join("config")).is_empty(), "first run writes no config files")
	_write(root.path_join("config/settings.json"), "{}")
	_paths_script.prepare_user_root(root)
	check(FileAccess.file_exists(root.path_join("config/settings.json")), "a later run keeps existing user files")


func _test_defaults_come_from_shipped_config() -> void:
	var settings: Node = load("res://autoload/Settings.gd").new()
	settings.master_volume = 0.1
	settings.load_file("res://content/config/default.json")
	_write(TEMP_DIR.path_join("settings.json"), "{\"noteSpeed\": 1.5}")
	settings.load_file(TEMP_DIR.path_join("settings.json"))
	check_near(settings.note_speed, 1.5, "user settings override the defaults")
	check_near(settings.master_volume, 0.8, "shipped defaults fill what user settings leave out")
	check(not FileAccess.file_exists("user://config/default.json"), "no copy of the defaults is made under user://")
	settings.free()


func _test_ogg_preference() -> void:
	var song := TEMP_DIR.path_join("song")
	DirAccess.make_dir_recursive_absolute(song)
	var wav := song.path_join("Inst.wav")
	var ogg := song.path_join("Inst.ogg")
	_write(ogg, "")
	check(_content_script.preferred_audio(wav, false) == ogg, "desktop falls back to the .ogg when the WAV is missing")
	_write(wav, "")
	DirAccess.remove_absolute(ogg)
	check(_content_script.preferred_audio(wav, true) == wav, "mobile keeps the WAV without a sibling .ogg")
	_write(ogg, "")
	check(_content_script.preferred_audio(wav, true) == ogg, "mobile prefers a sibling .ogg")
	check(_content_script.preferred_audio(wav, false) == wav, "desktop keeps the WAV")
	check(_content_script.preferred_audio(ogg, true) == ogg, "non-WAV audio is unchanged")
	var upper := song.path_join("Voices.WAV")
	_write(upper, "")
	_write(song.path_join("Voices.ogg"), "")
	check(_content_script.preferred_audio(upper, true) == song.path_join("Voices.ogg"), "extension match ignores case")


static func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)


static func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for folder in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(folder))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
