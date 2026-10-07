## Shared semantic input actions for keyboard and gamepad controls.
class_name GameActions
extends RefCounted

const LANES: Array[StringName] = [&"lane_0", &"lane_1", &"lane_2", &"lane_3"]
const MENU_UP: StringName = &"menu_up"
const MENU_DOWN: StringName = &"menu_down"
const MENU_LEFT: StringName = &"menu_left"
const MENU_RIGHT: StringName = &"menu_right"
const MENU_CONFIRM: StringName = &"menu_confirm"
const MENU_BACK: StringName = &"menu_back"
const GAME_PAUSE: StringName = &"game_pause"
const GAME_LEAVE: StringName = &"game_leave"

const LANE_BUTTONS: PackedInt32Array = [JOY_BUTTON_X, JOY_BUTTON_A, JOY_BUTTON_Y, JOY_BUTTON_B]
static var _stick_navigation: Dictionary[int, Vector2i] = {}


static func is_pressed(event: InputEvent, action: StringName) -> bool:
	return event.is_action_pressed(action)


static func is_released(event: InputEvent, action: StringName) -> bool:
	return event.is_action_released(action)


static func stick_navigation_step(event: InputEventJoypadMotion, axis: JoyAxis) -> int:
	if event.axis != axis:
		return 0
	var previous: Vector2i = _stick_navigation.get(event.device, Vector2i.ZERO)
	var value := event.axis_value
	var direction := -1 if value <= -0.55 else 1 if value >= 0.55 else 0
	if axis == JOY_AXIS_LEFT_Y:
		_stick_navigation[event.device] = Vector2i(previous.x, direction)
		return direction if direction != 0 and direction != previous.y else 0
	_stick_navigation[event.device] = Vector2i(direction, previous.y)
	return direction if direction != 0 and direction != previous.x else 0


static func clear_stick_navigation(device: int) -> void:
	_stick_navigation.erase(device)


static func configure_menus() -> void:
	_bind(MENU_UP, [_key(KEY_UP), _key(KEY_W), _joy_button(JOY_BUTTON_DPAD_UP)])
	_bind(MENU_DOWN, [_key(KEY_DOWN), _key(KEY_S), _joy_button(JOY_BUTTON_DPAD_DOWN)])
	_bind(MENU_LEFT, [_key(KEY_LEFT), _joy_button(JOY_BUTTON_DPAD_LEFT)])
	_bind(MENU_RIGHT, [_key(KEY_RIGHT), _joy_button(JOY_BUTTON_DPAD_RIGHT)])
	_bind(MENU_CONFIRM, [_key(KEY_ENTER), _key(KEY_KP_ENTER), _joy_button(JOY_BUTTON_A)])
	_bind(MENU_BACK, [_key(KEY_ESCAPE), _joy_button(JOY_BUTTON_B)])
	_bind(GAME_PAUSE, [_key(KEY_ENTER), _key(KEY_KP_ENTER), _joy_button(JOY_BUTTON_START)])
	_bind(GAME_LEAVE, [_key(KEY_ESCAPE), _joy_button(JOY_BUTTON_BACK)])


static func configure_lanes(settings: Node) -> void:
	for lane in LANES.size():
		_bind(LANES[lane], [_key(settings.lane_key(lane)), _joy_button(settings.lane_joy_button(lane))])


static func _bind(action: StringName, events: Array[InputEvent]) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)
	for event in events:
		InputMap.action_add_event(action, event)


static func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	return event


static func _joy_button(button: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = -1
	event.button_index = button
	return event
