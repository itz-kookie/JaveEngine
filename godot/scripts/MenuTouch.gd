## Reads one-finger gestures on a list menu: a tap, a vertical drag step, or a horizontal drag step.
class_name MenuTouch
extends RefCounted

enum Gesture { NONE, TAP, STEP, ADJUST }

const TAP_SLOP := 24.0
const STEP_DISTANCE := 60.0
const ADJUST_DISTANCE := 90.0

## Where the last TAP landed.
var tap_position := Vector2.ZERO
## +1/-1 for the last STEP (next/previous item) or ADJUST (right/left).
var direction := 0

var _down := false
var _dragged := false
var _anchor := Vector2.ZERO


func feed(event: InputEvent) -> Gesture:
	var touch := event as InputEventScreenTouch
	if touch != null and touch.index == 0:
		return _on_touch(touch)
	var drag := event as InputEventScreenDrag
	if drag != null and drag.index == 0 and _down:
		return _on_drag(drag.position)
	return Gesture.NONE


func _on_touch(touch: InputEventScreenTouch) -> Gesture:
	if touch.pressed:
		_down = true
		_dragged = false
		_anchor = touch.position
		return Gesture.NONE
	var was_tap := _down and not _dragged
	_down = false
	if not was_tap:
		return Gesture.NONE
	tap_position = touch.position
	return Gesture.TAP


func _on_drag(point: Vector2) -> Gesture:
	var delta := point - _anchor
	if not _dragged and delta.length() < TAP_SLOP:
		return Gesture.NONE
	_dragged = true
	if absf(delta.y) >= STEP_DISTANCE and absf(delta.y) >= absf(delta.x):
		# Dragging up pulls later items into view, like scrolling a list.
		direction = 1 if delta.y < 0.0 else -1
		_anchor = point
		return Gesture.STEP
	if absf(delta.x) >= ADJUST_DISTANCE:
		direction = 1 if delta.x > 0.0 else -1
		_anchor = point
		return Gesture.ADJUST
	return Gesture.NONE
