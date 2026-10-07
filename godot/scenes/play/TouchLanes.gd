## Four full-screen touch columns with visible lane buttons along the bottom.
class_name TouchLanes
extends Control

const NO_LANE := -1
const ARROWS: PackedStringArray = ["←", "↓", "↑", "→"]
const LABELS: PackedStringArray = ["LEFT", "DOWN", "UP", "RIGHT"]
const LANE_COLORS: Array[Color] = [Color("#83dcff"), Color("#ff9c74"), Color("#c4a3ff"), Color("#7cf0c2")]
const BUTTON_HEIGHT := 112.0
const BUTTON_MARGIN := 12.0
const BUTTON_GAP := 10.0

var _finger_lanes: Dictionary[int, int] = {}


func _ready() -> void:
	LaneInput.lane_pressed.connect(_on_lane_changed)
	LaneInput.lane_released.connect(_on_lane_changed)


func _on_lane_changed(_lane: int, _song_ms: float) -> void:
	queue_redraw()


static func lane_at(point: Vector2) -> int:
	if point.x < 0.0 or point.x >= Ui.SCREEN_SIZE.x or point.y < 0.0 or point.y > Ui.SCREEN_SIZE.y:
		return NO_LANE
	return mini(LaneInput.LANE_COUNT - 1, int(point.x / (Ui.SCREEN_SIZE.x / LaneInput.LANE_COUNT)))


func _draw() -> void:
	var lane_width := size.x / LaneInput.LANE_COUNT
	for lane in LaneInput.LANE_COUNT:
		var left := lane * lane_width
		if lane > 0:
			draw_line(Vector2(left, 0.0), Vector2(left, size.y), Color(1.0, 1.0, 1.0, 0.12), 1.0)
		var color := LANE_COLORS[lane]
		var held := (LaneInput.held_mask & (1 << lane)) != 0
		var button_width := lane_width - BUTTON_GAP * 2.0
		var button_height := minf(BUTTON_HEIGHT, size.y * 0.24)
		var button_rect := Rect2(left + BUTTON_GAP, size.y - button_height - BUTTON_MARGIN, button_width, button_height)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(color, 0.60 if held else 0.24)
		style.border_color = Color(color, 0.95 if held else 0.55)
		style.set_border_width_all(2 if held else 1)
		style.set_corner_radius_all(16)
		draw_style_box(style, button_rect)
		draw_string(ThemeDB.fallback_font, Vector2(button_rect.position.x, button_rect.position.y + button_height * 0.66),
			ARROWS[lane], HORIZONTAL_ALIGNMENT_CENTER, button_width, 48, Color.WHITE)
		draw_string(ThemeDB.fallback_font, Vector2(button_rect.position.x, button_rect.position.y + button_height - 10.0),
			LABELS[lane], HORIZONTAL_ALIGNMENT_CENTER, button_width, 11, Color(0.88, 0.87, 0.94, 0.9))


func _unhandled_input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if touch != null:
		_lift(touch.index)
		if touch.pressed:
			_hold(touch.index, lane_at(touch.position))
		queue_redraw()
		get_viewport().set_input_as_handled()
		return
	var drag := event as InputEventScreenDrag
	if drag != null:
		var lane := lane_at(drag.position)
		if lane != _finger_lanes.get(drag.index, NO_LANE):
			_lift(drag.index)
			_hold(drag.index, lane)
			queue_redraw()
		get_viewport().set_input_as_handled()


## Lifts that happen while paused never arrive, so every held lane is let go when input stops.
func _notification(what: int) -> void:
	if what == NOTIFICATION_DISABLED or what == NOTIFICATION_EXIT_TREE:
		for finger: int in _finger_lanes.keys():
			_lift(finger)
		queue_redraw()


func _hold(finger: int, lane: int) -> void:
	if lane == NO_LANE:
		return
	_finger_lanes[finger] = lane
	LaneInput.set_touch_lane(lane, finger, true)


## A lane is released only when its last finger lifts.
func _lift(finger: int) -> void:
	var lane: int = _finger_lanes.get(finger, NO_LANE)
	if lane == NO_LANE:
		return
	_finger_lanes.erase(finger)
	LaneInput.set_touch_lane(lane, finger, false)
