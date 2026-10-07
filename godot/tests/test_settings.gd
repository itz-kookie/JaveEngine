extends "res://tests/test_base.gd"

## Autoload scripts only compile once the autoload globals exist, so they load lazily on the first frame.
const TEMP_DIR := "user://test_settings_tmp"

var _settings_script: GDScript
var _content_script: GDScript
var _ran := false


func _initialize() -> void:
	pass


func _process(_delta: float) -> bool:
	if not _ran:
		_ran = true
		super._initialize()
	return false


func run() -> void:
	_settings_script = load("res://autoload/Settings.gd")
	_content_script = load("res://autoload/Content.gd")
	_remove_temp_dir()
	DirAccess.make_dir_recursive_absolute(TEMP_DIR)
	_test_volume_steps()
	_test_note_speed_steps()
	_test_audio_offset_steps()
	_test_key_mapping()
	_test_settings_round_trip()
	_test_mod_overrides_file()
	_test_toggle_mod_persists()
	_remove_temp_dir()
	check(not DirAccess.dir_exists_absolute(TEMP_DIR), "temporary directory removed")


func _test_volume_steps() -> void:
	check_near(_settings_script.stepped_volume(0.8, 1), 0.85, "volume steps up by 5%")
	check_near(_settings_script.stepped_volume(0.8, -1), 0.75, "volume steps down by 5%")
	check_near(_settings_script.stepped_volume(1.0, 1), 1.0, "volume clamps at 100%")
	check_near(_settings_script.stepped_volume(0.0, -1), 0.0, "volume clamps at 0%")
	var volume := 0.0
	for step in 20:
		volume = _settings_script.stepped_volume(volume, 1)
	check(volume == 1.0, "twenty volume steps land exactly on 100%")


func _test_note_speed_steps() -> void:
	check_near(_settings_script.stepped_note_speed(1.0, 1), 1.1, "note speed steps by 0.1")
	check_near(_settings_script.stepped_note_speed(2.5, 1), 2.5, "note speed clamps at 2.5")
	check_near(_settings_script.stepped_note_speed(0.5, -1), 0.5, "note speed clamps at 0.5")
	var speed := 0.5
	for step in 7:
		speed = _settings_script.stepped_note_speed(speed, 1)
	check("%.1f" % speed == "1.2", "note speed steps do not drift (got %f)" % speed)


func _test_audio_offset_steps() -> void:
	check_near(_settings_script.stepped_audio_offset(0.0, 1), 5.0, "audio offset steps by 5 ms")
	check_near(_settings_script.stepped_audio_offset(1000.0, 1), 1000.0, "audio offset clamps at +1000")
	check_near(_settings_script.stepped_audio_offset(-1000.0, -1), -1000.0, "audio offset clamps at -1000")


func _test_key_mapping() -> void:
	for vk: int in [68, 70, 74, 75, 37, 40, 32, 13, 96, 112, 186, 222]:
		var key: Key = _settings_script.godot_key_for_vk(vk)
		check(_settings_script.vk_for_godot_key(key) == vk, "virtual key %d round-trips" % vk)
	check(_settings_script.vk_for_godot_key(KEY_SHIFT) == 0, "unmapped keys are rejected")


func _test_settings_round_trip() -> void:
	var saved: Node = _settings_script.new()
	saved.save_path = TEMP_DIR.path_join("settings.json")
	saved.master_volume = 0.35
	saved.note_speed = 1.7
	saved.downscroll = true
	saved.show_fps = false
	saved.audio_offset_ms = -25.0
	check(saved.set_lane_key(2, KEY_UP), "arrow key can be bound")
	check(saved.set_lane_joy_button(3, JOY_BUTTON_B), "menu Back button can be rebound to a gameplay lane")
	check(not saved.set_lane_joy_button(3, JOY_BUTTON_START), "reserved pause button cannot be rebound to a lane")
	check(not saved.set_lane_joy_button(3, JOY_BUTTON_BACK), "reserved controller Back button cannot be rebound to a lane")
	check(saved.set_lane_joy_button(2, JOY_BUTTON_RIGHT_SHOULDER), "lane can be rebound to a gamepad button")
	saved.save()
	var loaded: Node = _settings_script.new()
	loaded.load_file(saved.save_path)
	check_near(loaded.master_volume, 0.35, "volume persists")
	check_near(loaded.note_speed, 1.7, "note speed persists")
	check(loaded.downscroll and not loaded.show_fps, "toggles persist")
	check_near(loaded.audio_offset_ms, -25.0, "audio offset persists")
	check(loaded.lane_key(2) == KEY_UP and loaded.keybinds[2] == 38, "rebound key persists as a virtual key")
	check(loaded.lane_joy_button(2) == JOY_BUTTON_RIGHT_SHOULDER, "rebound gamepad button persists")
	check(loaded.lane_joy_button(3) == JOY_BUTTON_B, "gamepad B binding persists for a lane")
	saved.free()
	loaded.free()


func _test_mod_overrides_file() -> void:
	var path := TEMP_DIR.path_join("overrides.json")
	check(ModOverrides.load_file(path).is_empty(), "missing override file means no overrides")
	check(ModOverrides.save_file(path, {"a": false, "b": true}), "override file saves")
	var loaded := ModOverrides.load_file(path)
	check(loaded.get("a") == false and loaded.get("b") == true, "override file round-trips")
	var mods: Array[ModInfo] = [ModInfo.from_json({"id": "a"}, "res://x/a"), ModInfo.from_json({"id": "c", "enabled": false}, "res://x/c")]
	ModOverrides.apply(mods, loaded)
	check(not mods[0].enabled, "override disables a mod")
	check(not mods[1].enabled, "mods without an override keep their manifest state")


func _test_toggle_mod_persists() -> void:
	var content: Node = _content_script.new()
	content.mod_overrides_path = TEMP_DIR.path_join("mods.json")
	content.scan()
	var index := _mod_index(content, "example-mod")
	check(index >= 0, "example mod is listed")
	if index < 0:
		content.free()
		return
	check(content.mods[index].enabled, "example mod starts enabled")
	content.toggle_mod(index)
	check(not content.mods[index].enabled, "toggle disables the mod")
	check(ModOverrides.load_file(content.mod_overrides_path).get("example-mod") == false, "toggle writes the override file")
	var manifest: Dictionary = JsonRead.load_file("res://content/mods/example-mod/mod.json")
	check(manifest.get("enabled") == true, "read-only mod manifest is untouched")
	var rescanned: Node = _content_script.new()
	rescanned.mod_overrides_path = content.mod_overrides_path
	rescanned.scan()
	check(not rescanned.mods[_mod_index(rescanned, "example-mod")].enabled, "override survives a fresh scan")
	content.free()
	rescanned.free()


static func _mod_index(content: Node, id: String) -> int:
	var mods: Array[ModInfo] = content.mods
	for index in mods.size():
		if mods[index].id == id:
			return index
	return -1


func _remove_temp_dir() -> void:
	if not DirAccess.dir_exists_absolute(TEMP_DIR):
		return
	for file in DirAccess.get_files_at(TEMP_DIR):
		DirAccess.remove_absolute(TEMP_DIR.path_join(file))
	DirAccess.remove_absolute(TEMP_DIR)
