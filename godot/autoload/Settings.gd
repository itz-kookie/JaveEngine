extends Node

const DEFAULT_KEYBINDS: PackedInt32Array = [68, 70, 74, 75]
const DEFAULT_JOYBINDS: PackedInt32Array = [JOY_BUTTON_X, JOY_BUTTON_A, JOY_BUTTON_Y, JOY_BUTTON_B]
const VK_ARROWS: Array[Key] = [KEY_LEFT, KEY_UP, KEY_RIGHT, KEY_DOWN]
const VK_PUNCTUATION := {
	186: KEY_SEMICOLON, 187: KEY_EQUAL, 188: KEY_COMMA, 189: KEY_MINUS, 190: KEY_PERIOD,
	191: KEY_SLASH, 192: KEY_QUOTELEFT, 219: KEY_BRACKETLEFT, 220: KEY_BACKSLASH,
	221: KEY_BRACKETRIGHT, 222: KEY_APOSTROPHE,
}

var master_volume := 0.8
var note_speed := 1.0
var downscroll := false
var fullscreen := false
var show_fps := true
var keybinds: PackedInt32Array = DEFAULT_KEYBINDS.duplicate()
var joybinds: PackedInt32Array = DEFAULT_JOYBINDS.duplicate()
var audio_offset_ms := 0.0
var save_path := Paths.user("config/settings.json")


func _ready() -> void:
	load_file(Paths.content("config/default.json"))
	load_file(save_path)


func save() -> void:
	DirAccess.make_dir_recursive_absolute(save_path.get_base_dir())
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		Log.info("Could not save settings: " + error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(to_json(), "  "))


func to_json() -> Dictionary:
	return {
		"masterVolume": master_volume,
		"noteSpeed": note_speed,
		"downscroll": downscroll,
		"fullscreen": fullscreen,
		"showFps": show_fps,
		"audioOffsetMs": audio_offset_ms,
		"keybinds": Array(keybinds),
		"joyBinds": Array(joybinds),
	}


func apply_window_mode() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("mobile"):
		return
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)


static func stepped_volume(volume: float, direction: int) -> float:
	return snappedf(clampf(volume + direction * 0.05, 0.0, 1.0), 0.05)


static func stepped_note_speed(speed: float, direction: int) -> float:
	return snappedf(clampf(speed + direction * 0.1, 0.5, 2.5), 0.1)


static func stepped_audio_offset(offset_ms: float, direction: int) -> float:
	return clampf(offset_ms + direction * 5.0, -1000.0, 1000.0)


func load_file(path: String) -> void:
	var json: Variant = JsonRead.load_file(path)
	if not json is Dictionary:
		return
	master_volume = clampf(JsonRead.number(json, "masterVolume", master_volume), 0.0, 1.0)
	note_speed = clampf(JsonRead.number(json, "noteSpeed", note_speed), 0.5, 2.5)
	downscroll = JsonRead.boolean(json, "downscroll", downscroll)
	fullscreen = JsonRead.boolean(json, "fullscreen", fullscreen)
	show_fps = JsonRead.boolean(json, "showFps", show_fps)
	audio_offset_ms = clampf(JsonRead.number(json, "audioOffsetMs", audio_offset_ms), -1000.0, 1000.0)
	_load_keybinds(JsonRead.array(json, "keybinds"))
	_load_joybinds(JsonRead.array(json, "joyBinds"))


func _load_keybinds(binds: Array) -> void:
	if binds.size() != 4:
		return
	for lane in 4:
		var key := int(JsonRead.as_number(binds[lane], keybinds[lane]))
		if key > 0 and key < 256:
			keybinds[lane] = key


func _load_joybinds(binds: Array) -> void:
	if binds.size() != 4:
		return
	for lane in 4:
		var button := int(JsonRead.as_number(binds[lane], joybinds[lane]))
		if button >= 0 and button < JOY_BUTTON_MAX and not _reserved_lane_joy_button(button):
			joybinds[lane] = button


func set_lane_key(lane: int, key: Key) -> bool:
	var vk := vk_for_godot_key(key)
	if vk == 0:
		return false
	keybinds[lane] = vk
	return true


func lane_key(lane: int) -> Key:
	var key := godot_key_for_vk(keybinds[lane])
	return key if key != KEY_NONE else godot_key_for_vk(DEFAULT_KEYBINDS[lane])


func set_lane_joy_button(lane: int, button: int) -> bool:
	if lane < 0 or lane >= joybinds.size() or button < 0 or button >= JOY_BUTTON_MAX \
			or _reserved_lane_joy_button(button):
		return false
	joybinds[lane] = button
	return true


func _reserved_lane_joy_button(button: int) -> bool:
	return button in [JOY_BUTTON_BACK, JOY_BUTTON_START]


func lane_joy_button(lane: int) -> int:
	return joybinds[lane] if lane >= 0 and lane < joybinds.size() else DEFAULT_JOYBINDS[clampi(lane, 0, 3)]


static func godot_key_for_vk(vk: int) -> Key:
	if (vk >= 65 and vk <= 90) or (vk >= 48 and vk <= 57) or vk == 32:
		return vk as Key
	if vk >= 37 and vk <= 40:
		return VK_ARROWS[vk - 37]
	if vk >= 96 and vk <= 105:
		return (KEY_KP_0 + vk - 96) as Key
	if vk >= 112 and vk <= 123:
		return (KEY_F1 + vk - 112) as Key
	if vk == 13:
		return KEY_ENTER
	return VK_PUNCTUATION.get(vk, KEY_NONE)


static func vk_for_godot_key(key: Key) -> int:
	if (key >= KEY_A and key <= KEY_Z) or (key >= KEY_0 and key <= KEY_9) or key == KEY_SPACE:
		return key
	var arrow := VK_ARROWS.find(key)
	if arrow >= 0:
		return 37 + arrow
	if key >= KEY_KP_0 and key <= KEY_KP_9:
		return 96 + key - KEY_KP_0
	if key >= KEY_F1 and key <= KEY_F12:
		return 112 + key - KEY_F1
	if key == KEY_ENTER or key == KEY_KP_ENTER:
		return 13
	for vk: int in VK_PUNCTUATION:
		if VK_PUNCTUATION[vk] == key:
			return vk
	return 0
