extends Node

signal lane_pressed(lane: int, song_ms: float)
signal lane_released(lane: int, song_ms: float)

const LANE_COUNT := 4
const LANE_ACTIONS: Array[StringName] = [&"lane_0", &"lane_1", &"lane_2", &"lane_3"]
const BUFFER_SIZE := 32

var held_mask := 0

var _press_lanes := PackedInt32Array()
var _press_times := PackedFloat64Array()
var _read := 0
var _write := 0


func _ready() -> void:
	_press_lanes.resize(BUFFER_SIZE)
	_press_times.resize(BUFFER_SIZE)
	bind_lanes()


func bind_lanes() -> void:
	for lane in LANE_COUNT:
		_bind_action(LANE_ACTIONS[lane], [Settings.lane_key(lane)])


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
	held_mask = 0


func discard_presses() -> void:
	_read = _write


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or event.is_echo():
		return
	for lane in LANE_COUNT:
		if event.is_action(LANE_ACTIONS[lane]):
			set_lane(lane, event.is_pressed())
			get_viewport().set_input_as_handled()
			return


## Shared by keys and touch so both stamp presses with the same song clock.
func set_lane(lane: int, pressed: bool) -> void:
	var song_ms := Conductor.now_ms()
	var bit := 1 << lane
	if pressed:
		held_mask |= bit
		_push_press(lane, song_ms)
		lane_pressed.emit(lane, song_ms)
	else:
		held_mask &= ~bit
		lane_released.emit(lane, song_ms)


func _push_press(lane: int, song_ms: float) -> void:
	_press_lanes[_write] = lane
	_press_times[_write] = song_ms
	_write = (_write + 1) % BUFFER_SIZE
	if _write == _read:
		_read = (_read + 1) % BUFFER_SIZE


func _bind_action(action: StringName, keys: Array[Key]) -> void:
	if InputMap.has_action(action):
		InputMap.action_erase_events(action)
	else:
		InputMap.add_action(action)
	for key in keys:
		var event := InputEventKey.new()
		event.keycode = key
		InputMap.action_add_event(action, event)
