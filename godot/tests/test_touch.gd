extends "res://tests/test_base.gd"

const TEMP_DIR := "user://test_touch_tmp"

var _ran := false
var _strumline: GDScript
var _pressed: Array[Vector2] = []
var _released: Array[Vector2] = []


## Autoload scripts only compile once the autoload globals exist, so they load lazily on the first frame.
func _initialize() -> void:
	pass


func _process(_delta: float) -> bool:
	if not _ran:
		_ran = true
		super._initialize()
	return false


func run() -> void:
	_strumline = load("res://scenes/play/Strumline.gd")
	check(not TouchControls.enabled(), "touch stub is off headless without --touch")
	_test_lane_mapping()
	_test_multi_touch()
	_test_input_source_holds()
	_test_gamepad_actions()
	_test_menu_gestures()
	_test_title_hit_test()
	_test_menu_screen_touch()
	_test_back_button()


func _test_lane_mapping() -> void:
	var lanes_script: GDScript = load("res://scenes/play/TouchLanes.gd")
	for lane in 4:
		check(lanes_script.lane_at(Vector2(_lane_x(lane), 360.0)) == lane, "lane %d column maps to its lane" % lane)
	check(lanes_script.lane_at(Vector2(_lane_x(0), 2.0)) == 0, "columns are full height")
	check(lanes_script.lane_at(Vector2(10.0, 360.0)) == 0, "left screen edge belongs to the first lane")
	check(lanes_script.lane_at(Vector2(1279.0, 360.0)) == 3, "right screen edge belongs to the last lane")
	check(lanes_script.lane_at(Vector2(1280.0, 360.0)) == -1, "outside the right screen edge maps to no lane")


func _test_multi_touch() -> void:
	var lane_input: Node = root.get_node("/root/LaneInput")
	var conductor: Node = root.get_node("/root/Conductor")
	lane_input.clear()
	conductor.set("song_time_ms", 1234.0)
	lane_input.lane_pressed.connect(func(lane: int, ms: float) -> void: _pressed.append(Vector2(lane, ms)))
	lane_input.lane_released.connect(func(lane: int, ms: float) -> void: _released.append(Vector2(lane, ms)))
	var lanes: Node = TouchControls.make_lanes()
	root.add_child(lanes)

	_touch(0, _lane_x(1), true)
	_touch(1, _lane_x(3), true)
	check(lane_input.held_mask == 0b1010, "two fingers hold two lanes (mask %d)" % lane_input.held_mask)
	check(_pressed == [Vector2(1, 1234.0), Vector2(3, 1234.0)], "presses emitted with the song clock: %s" % [_pressed])
	check(lane_input.has_press() and lane_input.press_lane() == 1, "first press queued for judging")
	check_near(lane_input.press_time_ms(), 1234.0, "queued press carries the song time")
	lane_input.consume_press()
	check(lane_input.has_press() and lane_input.press_lane() == 3, "second press queued for judging")
	lane_input.consume_press()

	_touch(0, _lane_x(1), false)
	check(_released == [Vector2(1, 1234.0)], "lifting one finger releases only its lane")
	check(lane_input.held_mask == 0b1000, "other finger keeps its lane held")

	_touch(2, _lane_x(3), true)
	_touch(1, _lane_x(3), false)
	check(lane_input.held_mask == 0b1000, "a lane stays held while another finger is on it")
	_touch(2, _lane_x(3), false)
	check(lane_input.held_mask == 0 and _released.size() == 2, "lane releases when its last finger lifts")

	_touch(3, _lane_x(0), true)
	var drag := InputEventScreenDrag.new()
	drag.index = 3
	drag.position = Vector2(_lane_x(2), 400.0)
	root.push_input(drag, true)
	check(lane_input.held_mask == 0b0100, "sliding a finger moves the hold to the new lane")
	_touch(3, _lane_x(2), false)

	_pressed.clear()
	_touch(4, -10.0, true)
	_touch(4, -10.0, false)
	check(_pressed.is_empty() and lane_input.held_mask == 0, "touches off the screen do nothing")

	_touch(5, _lane_x(1), true)
	lanes.process_mode = Node.PROCESS_MODE_DISABLED
	check(lane_input.held_mask == 0, "pausing lets go of held lanes")
	lanes.process_mode = Node.PROCESS_MODE_INHERIT
	_touch(5, _lane_x(1), true)
	_touch(5, _lane_x(1), false)
	check(lane_input.held_mask == 0, "a lane is not stuck after a lift missed while paused")
	lanes.free()
	lane_input.clear()


func _test_menu_gestures() -> void:
	var gestures := MenuTouch.new()
	check(gestures.feed(_touch_event(0, Vector2(200, 300), true)) == MenuTouch.Gesture.NONE, "touch down alone is no gesture")
	check(gestures.feed(_touch_event(0, Vector2(205, 302), false)) == MenuTouch.Gesture.TAP, "short touch is a tap")
	check(gestures.tap_position == Vector2(205, 302), "tap remembers where it landed")

	gestures.feed(_touch_event(0, Vector2(200, 400), true))
	check(gestures.feed(_drag_event(0, Vector2(200, 330))) == MenuTouch.Gesture.STEP and gestures.direction == 1,
		"dragging up steps to the next item")
	check(gestures.feed(_drag_event(0, Vector2(200, 400))) == MenuTouch.Gesture.STEP and gestures.direction == -1,
		"dragging back down steps to the previous item")
	check(gestures.feed(_touch_event(0, Vector2(200, 400), false)) == MenuTouch.Gesture.NONE, "lifting after a drag is not a tap")

	gestures.feed(_touch_event(0, Vector2(200, 400), true))
	check(gestures.feed(_drag_event(0, Vector2(300, 405))) == MenuTouch.Gesture.ADJUST and gestures.direction == 1,
		"dragging sideways adjusts")
	gestures.feed(_touch_event(0, Vector2(300, 405), false))
	check(gestures.feed(_touch_event(1, Vector2(10, 10), false)) == MenuTouch.Gesture.NONE, "second fingers are ignored")


func _test_input_source_holds() -> void:
	var lane_input: Node = root.get_node("/root/LaneInput")
	lane_input.clear()
	lane_input.set_lane_source(2, "key:0:75", true)
	lane_input.discard_presses()
	lane_input.set_lane_source(2, "joy:0:3", true)
	check(lane_input.held_mask == 0b0100, "keyboard and controller can hold one lane together")
	check(lane_input.has_press(), "a second source creates its own lane press for judging")
	check(lane_input.press_lane() == 2, "the second source queues the held lane")
	lane_input.discard_presses()
	lane_input.call("_on_joy_connection_changed", 0, false)
	check(lane_input.held_mask == 0b0100, "disconnecting a controller preserves a keyboard hold")
	lane_input.set_lane_source(2, "key:0:75", false)
	check(lane_input.held_mask == 0, "lane releases when its final input source releases")
	lane_input.clear()


func _test_gamepad_actions() -> void:
	var confirm := InputEventJoypadButton.new()
	confirm.button_index = JOY_BUTTON_A
	confirm.pressed = true
	check(MenuInput.is_confirm_event(confirm), "gamepad A confirms menu choices")
	var back := InputEventJoypadButton.new()
	back.button_index = JOY_BUTTON_B
	back.pressed = true
	check(MenuInput.is_back_event(back), "gamepad B backs out of menus")
	var start := InputEventJoypadButton.new()
	start.button_index = JOY_BUTTON_START
	start.pressed = true
	check(GameActions.is_pressed(start, GameActions.GAME_PAUSE), "gamepad Start pauses gameplay")
	var stick := InputEventJoypadMotion.new()
	stick.device = 9
	stick.axis = JOY_AXIS_LEFT_Y
	stick.axis_value = -0.8
	check(MenuInput.vertical_event(stick) == -1, "left stick up moves to the previous row")
	stick.axis_value = -0.9
	check(MenuInput.vertical_event(stick) == 0, "holding the stick does not repeat menu navigation per motion event")
	stick.axis_value = 0.0
	MenuInput.vertical_event(stick)
	stick.axis_value = 0.8
	check(MenuInput.vertical_event(stick) == 1, "re-centering then pushing down moves to the next row")
	GameActions.clear_stick_navigation(9)


func _test_title_hit_test() -> void:
	var title_script: GDScript = load("res://scenes/menus/TitleScreen.gd")
	var title: Control = title_script.new()
	check(title.item_at(Vector2(150.0, 720.0 * (title_script.ITEM_TOP + 0.05))) == 0, "tap on the first title item hits it")
	check(title.item_at(Vector2(150.0, 720.0 * (title_script.ITEM_TOP + 2.5 * title_script.ITEM_SPACING))) == 2,
		"tap on the third title item hits it")
	check(title.item_at(Vector2(1200.0, 300.0)) == -1, "tap beside the items misses")
	title.free()


func _test_menu_screen_touch() -> void:
	var settings: Node = root.get_node("/root/Settings")
	var saved_path: String = settings.save_path
	var saved_speed: float = settings.note_speed
	var saved_scroll: bool = settings.downscroll
	var saved_joy_button: int = settings.lane_joy_button(3)
	settings.save_path = TEMP_DIR.path_join("settings.json")
	ProjectSettings.set_setting(TouchControls.FORCE_SETTING, true)
	var options: Control = load("res://scenes/menus/OptionsScreen.gd").new()
	root.add_child(options)
	ProjectSettings.set_setting(TouchControls.FORCE_SETTING, false)

	var speed_row: Rect2 = options.row(1).hit_rect()
	_tap(speed_row.get_center())
	check(options.selection == 1, "tapping a menu row selects it")
	root.push_input(_touch_event(0, speed_row.get_center(), true), true)
	root.push_input(_drag_event(0, speed_row.get_center() + Vector2(120.0, 0.0)), true)
	root.push_input(_touch_event(0, speed_row.get_center() + Vector2(120.0, 0.0), false), true)
	check_near(settings.note_speed, settings.stepped_note_speed(saved_speed, 1), "sideways drag adjusts the selected option")
	check(options.selection == 1, "a drag does not count as a tap")

	var scroll_row: Rect2 = options.row(2).hit_rect()
	_tap(scroll_row.get_center())
	check(options.selection == 2 and settings.downscroll == saved_scroll, "first tap only selects")
	_tap(scroll_row.get_center())
	check(settings.downscroll != saved_scroll, "tapping the selected row confirms it")

	root.push_input(_touch_event(0, Vector2(300.0, 500.0), true), true)
	root.push_input(_drag_event(0, Vector2(300.0, 400.0)), true)
	root.push_input(_touch_event(0, Vector2(300.0, 400.0), false), true)
	check(options.selection == 3, "dragging up scrolls to the next row")
	var up := InputEventKey.new()
	up.keycode = KEY_UP
	up.pressed = true
	root.push_input(up, true)
	check(options.selection == 2, "keyboard still drives menus with touch on")
	var stick := InputEventJoypadMotion.new()
	stick.device = 10
	stick.axis = JOY_AXIS_LEFT_Y
	stick.axis_value = -0.8
	options._unhandled_input(stick)
	check(options.selection == 1, "left stick navigation reaches the menu dispatch path")
	stick.axis_value = -0.9
	options._unhandled_input(stick)
	check(options.selection == 1, "held left stick does not repeat through menu dispatch")
	stick.axis_value = 0.0
	options._unhandled_input(stick)
	GameActions.clear_stick_navigation(10)
	options.set("rebinding_lane", 3)
	var bind_b := InputEventJoypadButton.new()
	bind_b.button_index = JOY_BUTTON_B
	bind_b.pressed = true
	options._unhandled_input(bind_b)
	check(settings.lane_joy_button(3) == JOY_BUTTON_B, "B can be assigned to a gameplay lane")
	options.set("rebinding_lane", 3)
	var bind_start := InputEventJoypadButton.new()
	bind_start.button_index = JOY_BUTTON_START
	bind_start.pressed = true
	options._unhandled_input(bind_start)
	check(options.get("rebinding_lane") == 3 and settings.lane_joy_button(3) == JOY_BUTTON_B,
		"reserved Start remains unavailable while rebinding")
	var cancel_rebind := InputEventJoypadButton.new()
	cancel_rebind.button_index = JOY_BUTTON_BACK
	cancel_rebind.pressed = true
	options._unhandled_input(cancel_rebind)
	check(options.get("rebinding_lane") == -1, "controller Back cancels a lane rebind")
	settings.set_lane_joy_button(3, saved_joy_button)
	root.get_node("/root/LaneInput").call("bind_lanes")

	options.free()
	settings.note_speed = saved_speed
	settings.downscroll = saved_scroll
	settings.save_path = saved_path
	_remove_temp_dir()


func _test_back_button() -> void:
	var probe := TouchProbe.new()
	root.add_child(probe)
	var back := TouchControls.make_back_button(20)
	root.add_child(back)
	root.push_input(_touch_event(0, TouchControls.BACK_RECT.get_center(), true), true)
	check(probe.touches == 0, "back button swallows its own touches")
	root.push_input(_touch_event(0, Vector2(640.0, 360.0), true), true)
	check(probe.touches == 1, "touches elsewhere pass through the back button")
	back.visible = false
	root.push_input(_touch_event(0, TouchControls.BACK_RECT.get_center(), true), true)
	check(probe.touches == 2, "a hidden back button ignores touches")
	back.visible = true
	var lane_input: Node = root.get_node("/root/LaneInput")
	var lanes: Node = TouchControls.make_lanes()
	root.add_child(lanes)
	_touch(7, _lane_x(0), true)
	check(lane_input.held_mask == 0b0001, "lane touch begins outside the top controls")
	root.push_input(_touch_event(7, TouchControls.BACK_RECT.get_center(), false), true)
	check(lane_input.held_mask == 0, "lane release still reaches gameplay when lifted over Back")
	root.push_input(_touch_event(8, TouchControls.BACK_RECT.get_center(), true), true)
	root.push_input(_drag_event(8, Vector2(_lane_x(1), 360.0)), true)
	root.push_input(_touch_event(8, Vector2(_lane_x(1), 360.0), false), true)
	check(lane_input.held_mask == 0, "a touch that began on Back cannot create a lane hold while dragging")
	back.free()
	lanes.free()
	probe.free()


func _tap(point: Vector2) -> void:
	root.push_input(_touch_event(0, point, true), true)
	root.push_input(_touch_event(0, point, false), true)


func _remove_temp_dir() -> void:
	if not DirAccess.dir_exists_absolute(TEMP_DIR):
		return
	for file in DirAccess.get_files_at(TEMP_DIR):
		DirAccess.remove_absolute(TEMP_DIR.path_join(file))
	DirAccess.remove_absolute(TEMP_DIR)


func _touch(finger: int, x: float, pressed: bool) -> void:
	root.push_input(_touch_event(finger, Vector2(x, 360.0), pressed), true)


static func _touch_event(finger: int, point: Vector2, pressed: bool) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = finger
	event.position = point
	event.pressed = pressed
	return event


static func _drag_event(finger: int, point: Vector2) -> InputEventScreenDrag:
	var event := InputEventScreenDrag.new()
	event.index = finger
	event.position = point
	return event


func _lane_x(lane: int) -> float:
	return (lane + 0.5) * Ui.SCREEN_SIZE.x / LaneInput.LANE_COUNT


class TouchProbe extends Node:
	var touches := 0

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventScreenTouch:
			touches += 1
