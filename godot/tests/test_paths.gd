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
	_test_isolated_user_root()
	_test_first_run_layout()
	_test_defaults_come_from_shipped_config()
	_test_ogg_preference()
	_test_week_merging()
	_test_user_imported_weeks()
	_remove_tree(TEMP_DIR)
	check(not DirAccess.dir_exists_absolute(TEMP_DIR), "temporary directory removed")


func _test_isolated_user_root() -> void:
	var paths := root.get_node("/root/Paths")
	var content := root.get_node("/root/Content")
	var settings := root.get_node("/root/Settings")
	check(paths.call("user", "mods") == TEST_HOME + "/mods", "tests read user files from the test home")
	check(paths.call("user_mirror", "res://content/data/weeks.json") == TEST_HOME + "/content/data/weeks.json", "content overrides come from the test home")
	check(not (content.get("mod_roots") as PackedStringArray).has("user://mods"), "the player's mods folder is not scanned")
	check(content.get("mod_overrides_path") == TEST_HOME + "/config/mods.json", "mod states come from the test home")
	check(settings.get("save_path") == TEST_HOME + "/config/settings.json", "settings come from the test home")


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
	check(not FileAccess.file_exists(TEST_HOME + "/config/default.json"), "no copy of the defaults is made under user://")
	settings.free()


func _test_ogg_preference() -> void:
	var song := TEMP_DIR.path_join("song")
	DirAccess.make_dir_recursive_absolute(song)
	var wav := song.path_join("Inst.wav")
	var ogg := song.path_join("Inst.ogg")
	_write(wav, "")
	check(_content_script.preferred_audio(wav) == wav, "a WAV without a sibling .ogg plays as named")
	_write(ogg, "")
	check(_content_script.preferred_audio(wav) == ogg, "a sibling .ogg is preferred over the WAV")
	DirAccess.remove_absolute(wav)
	check(_content_script.preferred_audio(wav) == ogg, "the .ogg stands in for a missing WAV")
	check(_content_script.preferred_audio(ogg) == ogg, "non-WAV audio is unchanged")
	var upper := song.path_join("Voices.WAV")
	_write(upper, "")
	_write(song.path_join("Voices.ogg"), "")
	check(_content_script.preferred_audio(upper) == song.path_join("Voices.ogg"), "extension match ignores case")


func _test_week_merging() -> void:
	var installed := PackedStringArray(["neon-steps", "fresh"])
	var has_song := func(id: String) -> bool: return installed.has(id)
	var imported: Array[WeekMeta] = [
		WeekMeta.from_json({"id": "week1", "songs": ["bopeebo", "fresh"]}),
		WeekMeta.from_json({"id": "week2", "songs": ["spookeez"]}),
		WeekMeta.from_json({"id": "demo", "name": "Imported Demo", "songs": ["neon-steps"]}),
	]
	var shipped: Array[WeekMeta] = [
		WeekMeta.from_json({"id": "demo", "name": "Demo Week", "songs": ["neon-steps"]}),
		WeekMeta.from_json({"id": "extra", "songs": ["neon-steps"]}),
	]
	var lists: Array[Array] = [imported, shipped]
	var merged: Array[WeekMeta] = _content_script.playable_weeks(lists, has_song)
	var ids := PackedStringArray()
	for week in merged:
		ids.append(week.id)
	check(ids == PackedStringArray(["week1", "demo", "extra"]), "imported weeks first, unplayable weeks skipped (got %s)" % [ids])
	check(merged[1].name == "Imported Demo", "the first week with an id wins")
	var empty: Array[WeekMeta] = []
	var shipped_only: Array[Array] = [empty, shipped]
	check(_content_script.playable_weeks(shipped_only, has_song).size() == 2, "missing imported weeks leave the shipped weeks")


func _test_user_imported_weeks() -> void:
	var content: Node = root.get_node("/root/Content")
	var user_file := TEST_HOME + "/content/data/weeks.imported.json"
	var backup := FileAccess.get_file_as_string(user_file) if FileAccess.file_exists(user_file) else ""
	var created_dirs := not DirAccess.dir_exists_absolute(TEST_HOME + "/content")
	DirAccess.make_dir_recursive_absolute(user_file.get_base_dir())
	_write(user_file, JSON.stringify({"weeks": [
		{"id": "zz-user-week", "name": "User Week", "songs": ["neon-steps"]},
		{"id": "demo", "name": "User Demo", "songs": ["neon-steps"]},
		{"id": "zz-missing", "songs": ["no-such-song"]},
	]}))
	content.call("scan")
	var ids := PackedStringArray()
	var demo_name := ""
	for week: WeekMeta in content.get("weeks"):
		ids.append(week.id)
		if week.id == "demo":
			demo_name = week.name
	check(ids.size() >= 2 and ids[0] == "zz-user-week", "user://content imported weeks are listed first (got %s)" % [ids])
	check(demo_name == "User Demo", "a user imported week wins over a shipped week with the same id")
	check(not ids.has("zz-missing"), "user weeks without installed songs are hidden")
	if backup.is_empty():
		DirAccess.remove_absolute(user_file)
	else:
		_write(user_file, backup)
	if created_dirs:
		_remove_tree(TEST_HOME + "/content")
	content.call("scan")
	var restored := PackedStringArray()
	for week: WeekMeta in content.get("weeks"):
		restored.append(week.id)
	check(not restored.has("zz-user-week"), "removing the user file removes its weeks")


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
