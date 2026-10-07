## Single switch for touch controls: visible full-screen lanes in play, menu gestures, Back and Pause buttons.
## On with a touchscreen, or forced on desktop with `-- --touch` or the jave/debug/force_touch setting.
class_name TouchControls
extends RefCounted

const FORCE_SETTING := "jave/debug/force_touch"
const LANES_SCENE := "res://scenes/play/TouchLanes.tscn"
const BACK_RECT := Rect2(8.0, 8.0, 104.0, 44.0)
const PAUSE_RECT := Rect2(Ui.SCREEN_SIZE.x - 112.0, 8.0, 104.0, 44.0)


static func enabled() -> bool:
	return DisplayServer.is_touchscreen_available() or forced()


static func forced() -> bool:
	return OS.get_cmdline_user_args().has("--touch") or bool(ProjectSettings.get_setting(FORCE_SETTING, false))


## Desktop testing has no touch events, so forcing the stub turns mouse clicks into touches.
static func prepare() -> void:
	if forced() and not DisplayServer.is_touchscreen_available():
		Input.emulate_touch_from_mouse = true


static func make_lanes() -> Node:
	return (load(LANES_SCENE) as PackedScene).instantiate()


static func make_back_button(layer_index: int) -> CanvasLayer:
	var button := BackButton.new()
	button.layer = layer_index
	return button


## Feeds a key press and release through the normal input path so every screen reacts as to the keyboard.
static func send_key(key: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.pressed = pressed
		Input.parse_input_event(event)


## Drawn and hit-tested by hand rather than a Button so its touches never also reach the screen below.
class BackButton extends CanvasLayer:
	var pause_visible := false
	var _pause_panel: Control
	var _claimed_fingers: Dictionary[int, bool] = {}

	func _ready() -> void:
		var root := Control.new()
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(root)
		var panel := Ui.box(root, BACK_RECT, Color(Ui.BAR_COLOR, 0.8), 10, Ui.accent, 2)
		Ui.text(panel, "BACK", Rect2(Vector2.ZERO, BACK_RECT.size), 18, Ui.WHITE, true, HORIZONTAL_ALIGNMENT_CENTER)
		_pause_panel = Ui.box(root, PAUSE_RECT, Color(Ui.BAR_COLOR, 0.8), 10, Color("#ffda65"), 2)
		Ui.text(_pause_panel, "Ⅱ  PAUSE", Rect2(Vector2.ZERO, PAUSE_RECT.size), 16, Color("#ffda65"), true, HORIZONTAL_ALIGNMENT_CENTER)
		_pause_panel.visible = pause_visible


	func set_pause_visible(visible_now: bool) -> void:
		pause_visible = visible_now
		if _pause_panel != null:
			_pause_panel.visible = pause_visible

	func _input(event: InputEvent) -> void:
		var drag := event as InputEventScreenDrag
		if drag != null and _claimed_fingers.has(drag.index):
			get_viewport().set_input_as_handled()
			return
		var touch := event as InputEventScreenTouch
		if touch == null:
			return
		if not touch.pressed and _claimed_fingers.has(touch.index):
			_claimed_fingers.erase(touch.index)
			get_viewport().set_input_as_handled()
			return
		if not visible:
			return
		if touch.pressed:
			var on_back := BACK_RECT.has_point(touch.position)
			var on_pause := pause_visible and PAUSE_RECT.has_point(touch.position)
			if not on_back and not on_pause:
				return
			_claimed_fingers[touch.index] = true
			get_viewport().set_input_as_handled()
			TouchControls.send_key(KEY_ENTER if on_pause else KEY_ESCAPE)
