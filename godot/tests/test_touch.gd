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
	_test_menu_gestures()
	_test_title_hit_test()
	_test_menu_screen_touch()
	_test_back_button()


func _test_lane_mapping() -> void:
	var lanes_script: GDScript = load("res://scenes/play/TouchLanes.gd")
	for lane in 4:
		check(lanes_script.lane_at(Vector2(_lane_x(lane), 360.0)) == lane, "lane %d column maps to its lane" % lane)
	check(lanes_script.lane_at(Vector2(_lane_x(0), 2.0)) == 0, "columns are full height")
	check(lanes_script.lane_at(Vector2(_strumline.PLAYER_X - 1.0, 360.0)) == -1, "left of the player strumline is no lane")
	check(lanes_script.lane_at(Vector2(1279.0, 360.0)) == 3, "right screen edge belongs to the last lane")


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
	_touch(4, 100.0, true)
	_touch(4, 100.0, false)
	check(_pressed.is_empty() and lane_input.held_mask == 0, "touches off the strumline do nothing")

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
	back.free()
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
	return _strumline.PLAYER_X + (lane + 0.5) * _strumline.LANE_WIDTH


class TouchProbe extends Node:
	var touches := 0

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventScreenTouch:
			touches += 1
