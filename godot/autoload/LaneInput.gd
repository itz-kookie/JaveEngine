extends Node

signal lane_pressed(lane: int, song_ms: float)
signal lane_released(lane: int, song_ms: float)

const LANE_COUNT := 4
const BUFFER_SIZE := 32

var held_mask := 0
var gameplay_input_enabled := false

var _press_lanes := PackedInt32Array()
var _press_times := PackedFloat64Array()
var _read := 0
var _write := 0
var _source_lanes: Dictionary[String, int] = {}
var _lane_sources: Array[Dictionary] = [{}, {}, {}, {}]


func _ready() -> void:
	_press_lanes.resize(BUFFER_SIZE)
	_press_times.resize(BUFFER_SIZE)
	GameActions.configure_menus()
	bind_lanes()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


func bind_lanes() -> void:
	GameActions.configure_lanes(get_node("/root/Settings"))


func has_press() -> bool:
	return _read != _write


func press_lane() -> int:
	return _press_lanes[_read]


func press_time_ms() -> float:
	return _press_times[_read]


func consume_press() -> void:
	_read = (_read + 1) % BUFFER_SIZE


func clear() -> void:
	discard_presses()
	for source: String in _source_lanes.keys():
		_release_source(source)
	_read = _write


func suspend_gameplay_input() -> void:
	gameplay_input_enabled = false
	clear()


func discard_presses() -> void:
	_read = _write


func _unhandled_input(event: InputEvent) -> void:
	if not gameplay_input_enabled:
		return
	var source := _source_for_event(event)
	if source.is_empty():
		return
	for lane in GameActions.LANES.size():
		var action: StringName = GameActions.LANES[lane]
		if event.is_action_pressed(action):
			_set_source(lane, source, true)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_released(action):
			_set_source(lane, source, false)
			get_viewport().set_input_as_handled()
			return


## Shared by keys and touch so both stamp presses with the same song clock.
func set_lane(lane: int, pressed: bool) -> void:
	_set_source(lane, "manual:%d" % lane, pressed)


func set_lane_source(lane: int, source: String, pressed: bool) -> void:
	_set_source(lane, source, pressed)


func set_touch_lane(lane: int, finger: int, pressed: bool) -> void:
	_set_source(lane, "touch:%d" % finger, pressed)


func _set_source(lane: int, source: String, pressed: bool) -> void:
	if lane < 0 or lane >= LANE_COUNT or source.is_empty():
		return
	if pressed:
		if _source_lanes.get(source, -1) == lane:
			return
		if _source_lanes.has(source):
			_release_source(source)
		var was_held := not _lane_sources[lane].is_empty()
		_source_lanes[source] = lane
		_lane_sources[lane][source] = true
		if not was_held:
			held_mask |= 1 << lane
		var song_ms: float = get_node("/root/Conductor").now_ms()
		_push_press(lane, song_ms)
		lane_pressed.emit(lane, song_ms)
		return
	_release_source(source)


func _release_source(source: String) -> void:
	if not _source_lanes.has(source):
		return
	var lane: int = _source_lanes[source]
	_source_lanes.erase(source)
	_lane_sources[lane].erase(source)
	if _lane_sources[lane].is_empty():
		held_mask &= ~(1 << lane)
		lane_released.emit(lane, get_node("/root/Conductor").now_ms())


func _source_for_event(event: InputEvent) -> String:
	var key := event as InputEventKey
	if key != null:
		if key.echo:
			return ""
		var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		return "key:%d:%d" % [key.device, code]
	var button := event as InputEventJoypadButton
	if button != null:
		return "joy:%d:%d" % [button.device, button.button_index]
	return ""


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	GameActions.clear_stick_navigation(device)
	if connected:
		return
	var prefix := "joy:%d:" % device
	for source: String in _source_lanes.keys():
		if source.begins_with(prefix):
			_release_source(source)


func _push_press(lane: int, song_ms: float) -> void:
	_press_lanes[_write] = lane
	_press_times[_write] = song_ms
	_write = (_write + 1) % BUFFER_SIZE
	if _write == _read:
		_read = (_read + 1) % BUFFER_SIZE
