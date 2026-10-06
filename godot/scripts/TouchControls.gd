## Single switch for the touch control stub: lanes in play, gestures on menus and an on-screen Back.
## On with a touchscreen, or forced on desktop with `-- --touch` or the jave/debug/force_touch setting.
class_name TouchControls
extends RefCounted

const FORCE_SETTING := "jave/debug/force_touch"
const LANES_SCENE := "res://scenes/play/TouchLanes.tscn"
const BACK_RECT := Rect2(8.0, 8.0, 104.0, 44.0)


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
	func _ready() -> void:
		var root := Control.new()
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(root)
		var panel := Ui.box(root, BACK_RECT, Color(Ui.BAR_COLOR, 0.8), 10, Ui.accent, 2)
		Ui.text(panel, "BACK", Rect2(Vector2.ZERO, BACK_RECT.size), 18, Ui.WHITE, true, HORIZONTAL_ALIGNMENT_CENTER)

	func _input(event: InputEvent) -> void:
		var touch := event as InputEventScreenTouch
		if not visible or touch == null or not BACK_RECT.has_point(touch.position):
			return
		get_viewport().set_input_as_handled()
		if touch.pressed:
			TouchControls.send_key(KEY_ESCAPE)
