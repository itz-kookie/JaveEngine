extends Node

const DEFAULT_KEYBINDS: PackedInt32Array = [68, 70, 74, 75]
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
var audio_offset_ms := 0.0


func _ready() -> void:
	load_file(Paths.content("config/default.json"))
	load_file(Paths.user("config/settings.json"))


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


func _load_keybinds(binds: Array) -> void:
	if binds.size() != 4:
		return
	for lane in 4:
		var key := int(JsonRead.as_number(binds[lane], keybinds[lane]))
		if key > 0 and key < 256:
			keybinds[lane] = key


func lane_key(lane: int) -> Key:
	var key := godot_key_for_vk(keybinds[lane])
	return key if key != KEY_NONE else godot_key_for_vk(DEFAULT_KEYBINDS[lane])


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
