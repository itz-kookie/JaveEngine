## Key tests for menu navigation.
class_name MenuInput
extends RefCounted


static func key_of(event: InputEvent) -> Key:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return KEY_NONE
	return key_event.keycode


static func is_confirm(key: Key) -> bool:
	return key == KEY_ENTER or key == KEY_KP_ENTER


static func is_back(key: Key) -> bool:
	return key == KEY_ESCAPE


static func vertical(key: Key) -> int:
	if key == KEY_UP or key == KEY_W:
		return -1
	if key == KEY_DOWN or key == KEY_S:
		return 1
	return 0


static func horizontal(key: Key) -> int:
	if key == KEY_LEFT:
		return -1
	if key == KEY_RIGHT:
		return 1
	return 0


static func is_confirm_event(event: InputEvent) -> bool:
	return GameActions.is_pressed(event, GameActions.MENU_CONFIRM)


static func is_back_event(event: InputEvent) -> bool:
	return GameActions.is_pressed(event, GameActions.MENU_BACK)


static func vertical_event(event: InputEvent) -> int:
	var motion := event as InputEventJoypadMotion
	if motion != null and motion.axis == JOY_AXIS_LEFT_Y:
		return GameActions.stick_navigation_step(motion, JOY_AXIS_LEFT_Y)
	if GameActions.is_pressed(event, GameActions.MENU_UP):
		return -1
	if GameActions.is_pressed(event, GameActions.MENU_DOWN):
		return 1
	return 0


static func horizontal_event(event: InputEvent) -> int:
	var motion := event as InputEventJoypadMotion
	if motion != null and motion.axis == JOY_AXIS_LEFT_X:
		return GameActions.stick_navigation_step(motion, JOY_AXIS_LEFT_X)
	if GameActions.is_pressed(event, GameActions.MENU_LEFT):
		return -1
	if GameActions.is_pressed(event, GameActions.MENU_RIGHT):
		return 1
	return 0


static func wrap_selection(selection: int, step: int, count: int) -> int:
	return 0 if count <= 0 else posmod(selection + step, count)
