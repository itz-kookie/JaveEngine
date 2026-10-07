class_name OptionsScreen
extends MenuScreen

enum Option { VOLUME, NOTE_SPEED, SCROLL, FULLSCREEN, SHOW_FPS, AUDIO_OFFSET, FIRST_KEY }

const LANE_NAMES: PackedStringArray = ["Left Lane", "Down Lane", "Up Lane", "Right Lane"]
const HINT := "Left/Right or D-pad adjusts. Enter/A toggles a setting or rebinds a lane."
const REBIND_HINT := "Press a key or gamepad button. Escape / Pad Back cancels."
const OVERLAY_COLOR := Color8(28, 31, 66)

var rebinding_lane := -1

var _subtitle: Label
var _overlay: Control


func _build() -> void:
	_subtitle = Ui.menu_header(self, "OPTIONS", HINT)
	var labels := PackedStringArray()
	for index in Option.FIRST_KEY + LaneInput.LANE_COUNT:
		labels.append(option_label(index))
	build_list(labels, 175.0, 670.0)
	_build_overlay()


func _unhandled_input(event: InputEvent) -> void:
	if rebinding_lane < 0:
		super._unhandled_input(event)
		return
	if MenuInput.key_of(event) == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_set_rebinding(-1)
		return
	var key := MenuInput.key_of(event)
	if key != KEY_NONE:
		get_viewport().set_input_as_handled()
		_capture_key(key)
		return
	var button := event as InputEventJoypadButton
	if button != null and button.pressed:
		get_viewport().set_input_as_handled()
		if button.button_index == JOY_BUTTON_BACK:
			_set_rebinding(-1)
			return
		if Settings.set_lane_joy_button(rebinding_lane, button.button_index):
			LaneInput.bind_lanes()
			_option_changed(Option.FIRST_KEY + rebinding_lane)
			_set_rebinding(-1)


func option_label(index: int) -> String:
	match index:
		Option.VOLUME:
			return "Master Volume     %d%%" % roundi(Settings.master_volume * 100.0)
		Option.NOTE_SPEED:
			return "Note Speed        %.1fx" % Settings.note_speed
		Option.SCROLL:
			return "Scroll Direction  " + ("Down" if Settings.downscroll else "Up")
		Option.FULLSCREEN:
			return "Fullscreen        " + ("On" if Settings.fullscreen else "Off")
		Option.SHOW_FPS:
			return "Show FPS          " + ("On" if Settings.show_fps else "Off")
		Option.AUDIO_OFFSET:
			return "Audio Offset      %+d ms" % roundi(Settings.audio_offset_ms)
	var lane := index - Option.FIRST_KEY
	return LANE_NAMES[lane] + "   " + OS.get_keycode_string(Settings.lane_key(lane)) \
		+ " / " + _joy_button_name(Settings.lane_joy_button(lane))


func _on_key(key: Key) -> void:
	if rebinding_lane >= 0:
		_capture_key(key)
	else:
		super._on_key(key)


func _adjust(direction: int) -> void:
	if _step(selection, direction):
		_option_changed(selection)


func _confirm() -> void:
	if selection >= Option.FIRST_KEY:
		_set_rebinding(selection - Option.FIRST_KEY)
	elif selection in [Option.SCROLL, Option.FULLSCREEN, Option.SHOW_FPS] and _step(selection, 1):
		_option_changed(selection)


## Applies one Left/Right step to an option; returns false when nothing changed.
func _step(index: int, direction: int) -> bool:
	match index:
		Option.VOLUME:
			var volume := Settings.stepped_volume(Settings.master_volume, direction)
			if volume == Settings.master_volume:
				return false
			Settings.master_volume = volume
			Conductor.apply_volume()
		Option.NOTE_SPEED:
			var speed := Settings.stepped_note_speed(Settings.note_speed, direction)
			if speed == Settings.note_speed:
				return false
			Settings.note_speed = speed
		Option.SCROLL:
			Settings.downscroll = not Settings.downscroll
		Option.FULLSCREEN:
			Settings.fullscreen = not Settings.fullscreen
			Settings.apply_window_mode()
		Option.SHOW_FPS:
			Settings.show_fps = not Settings.show_fps
		Option.AUDIO_OFFSET:
			var offset := Settings.stepped_audio_offset(Settings.audio_offset_ms, direction)
			if offset == Settings.audio_offset_ms:
				return false
			Settings.audio_offset_ms = offset
		_:
			return false
	return true


func _option_changed(index: int) -> void:
	refresh_row(index, option_label(index))
	Settings.save()


func _capture_key(key: Key) -> void:
	if MenuInput.is_back(key):
		_set_rebinding(-1)
		return
	if not Settings.set_lane_key(rebinding_lane, key):
		return
	LaneInput.bind_lanes()
	_option_changed(Option.FIRST_KEY + rebinding_lane)
	_set_rebinding(-1)


func _joy_button_name(button: int) -> String:
	match button:
		JOY_BUTTON_A: return "A"
		JOY_BUTTON_B: return "B"
		JOY_BUTTON_X: return "X"
		JOY_BUTTON_Y: return "Y"
		JOY_BUTTON_BACK: return "Back"
		JOY_BUTTON_START: return "Start"
		JOY_BUTTON_LEFT_SHOULDER: return "L1"
		JOY_BUTTON_RIGHT_SHOULDER: return "R1"
		JOY_BUTTON_DPAD_UP: return "D-pad Up"
		JOY_BUTTON_DPAD_DOWN: return "D-pad Down"
		JOY_BUTTON_DPAD_LEFT: return "D-pad Left"
		JOY_BUTTON_DPAD_RIGHT: return "D-pad Right"
		_: return "Button %d" % button


func _set_rebinding(lane: int) -> void:
	rebinding_lane = lane
	_overlay.visible = lane >= 0
	_subtitle.text = REBIND_HINT if lane >= 0 else HINT


func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.visible = false
	add_child(_overlay)
	var center := Ui.SCREEN_SIZE * 0.5
	Ui.box(_overlay, Rect2(center.x - 260.0, center.y - 85.0, 520.0, 170.0), OVERLAY_COLOR, 26, Ui.accent, 3)
	Ui.text(_overlay, "PRESS A KEY OR GAMEPAD BUTTON", Rect2(center.x - 250.0, center.y - 50.0, 500.0, 60.0), 26, Color.WHITE, true, HORIZONTAL_ALIGNMENT_CENTER)
	Ui.text(_overlay, "Escape / Pad Back cancels", Rect2(center.x - 220.0, center.y + 15.0, 440.0, 30.0), 16, Color8(160, 170, 200), false, HORIZONTAL_ALIGNMENT_CENTER)
