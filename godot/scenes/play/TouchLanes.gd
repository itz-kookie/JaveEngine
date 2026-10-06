## Invisible full-height touch columns over the player's strumline; each finger drives one lane.
class_name TouchLanes
extends Control

const NO_LANE := -1

var _finger_lanes: Dictionary[int, int] = {}
var _lane_fingers := PackedInt32Array([0, 0, 0, 0])


static func lane_at(point: Vector2) -> int:
	if point.x < Strumline.PLAYER_X or point.y < 0.0 or point.y > Ui.SCREEN_SIZE.y:
		return NO_LANE
	return mini(LaneInput.LANE_COUNT - 1, int((point.x - Strumline.PLAYER_X) / Strumline.LANE_WIDTH))


func _unhandled_input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if touch != null:
		_lift(touch.index)
		if touch.pressed:
			_hold(touch.index, lane_at(touch.position))
		get_viewport().set_input_as_handled()
		return
	var drag := event as InputEventScreenDrag
	if drag != null:
		var lane := lane_at(drag.position)
		if lane != _finger_lanes.get(drag.index, NO_LANE):
			_lift(drag.index)
			_hold(drag.index, lane)
		get_viewport().set_input_as_handled()


## Lifts that happen while paused never arrive, so every held lane is let go when input stops.
func _notification(what: int) -> void:
	if what == NOTIFICATION_DISABLED or what == NOTIFICATION_EXIT_TREE:
		for finger: int in _finger_lanes.keys():
			_lift(finger)


func _hold(finger: int, lane: int) -> void:
	if lane == NO_LANE:
		return
	_finger_lanes[finger] = lane
	_lane_fingers[lane] += 1
	LaneInput.set_lane(lane, true)


## A lane is released only when its last finger lifts.
func _lift(finger: int) -> void:
	var lane: int = _finger_lanes.get(finger, NO_LANE)
	if lane == NO_LANE:
		return
	_finger_lanes.erase(finger)
	_lane_fingers[lane] -= 1
	if _lane_fingers[lane] == 0:
		LaneInput.set_lane(lane, false)

