## Base for list menus: a scrolling, eased selection list plus the shared key handling.
class_name MenuScreen
extends Control

signal back_requested

const MENU_X := 60.0
const ROW_HEIGHT := 70.0
const ROWS_BEFORE := 4
const ROWS_AFTER := 5
const TWEEN_RATE := 14.0
const SETTLED := 0.001
const FOOTER := "TAP / SWIPE · UP/DOWN or D-PAD: SELECT · ENTER / A: CONFIRM · ESC / B: BACK"

var selection := 0

var _rows: Array[MenuRow] = []
var _row_height := ROW_HEIGHT
var _row_width := 0.0
var _list_top := 0.0
var _selection_tween := 0.0
var _settled := true
var _touch: MenuTouch = MenuTouch.new() if TouchControls.enabled() else null


func _ready() -> void:
	size = Ui.SCREEN_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	_layout_rows()


func item_count() -> int:
	return _rows.size()


func select(index: int) -> void:
	if index == selection or index < 0 or index >= item_count():
		return
	selection = index
	_settled = false
	_selection_changed()
	_layout_rows()


func _build() -> void:
	pass


func _selection_changed() -> void:
	pass


func _confirm() -> void:
	pass


func _adjust(_direction: int) -> void:
	pass


func build_list(labels: PackedStringArray, top: float, width: float, row_height := ROW_HEIGHT) -> void:
	_list_top = top
	_row_height = row_height
	_row_width = width
	_add_rows(labels)
	Ui.footer(self, FOOTER, 42.0, 16, 30.0)


## Swaps every row for new ones in the same list area and selects index.
func replace_list(labels: PackedStringArray, index := 0) -> void:
	for menu_row in _rows:
		remove_child(menu_row)
		menu_row.queue_free()
	_rows.clear()
	_add_rows(labels)
	selection = clampi(index, 0, maxi(0, labels.size() - 1))
	_selection_tween = selection
	_settled = true
	_layout_rows()


func _add_rows(labels: PackedStringArray) -> void:
	for value in labels:
		var menu_row := MenuRow.new(value, _row_width)
		_rows.append(menu_row)
		add_child(menu_row)


## Item under a screen point, or -1; used by touch taps.
func item_at(point: Vector2) -> int:
	for index in _rows.size():
		if _rows[index].visible and _rows[index].hit_rect().has_point(point):
			return index
	return -1


func row(index: int) -> MenuRow:
	return _rows[index]


func refresh_row(index: int, value: String) -> void:
	_rows[index].set_text(value)
	_layout_rows()


func _unhandled_input(event: InputEvent) -> void:
	if _touch != null and (event is InputEventScreenTouch or event is InputEventScreenDrag):
		get_viewport().set_input_as_handled()
		_on_touch(event)
		return
	var key := MenuInput.key_of(event)
	var viewport := get_viewport()
	if key != KEY_NONE:
		if viewport != null:
			viewport.set_input_as_handled()
		_on_key(key)
	elif _on_action_event(event):
		if viewport != null:
			viewport.set_input_as_handled()


func _on_action_event(event: InputEvent) -> bool:
	if MenuInput.is_back_event(event):
		back_requested.emit()
		return true
	var step := MenuInput.vertical_event(event)
	if step != 0:
		select(MenuInput.wrap_selection(selection, step, item_count()))
		return true
	elif MenuInput.is_confirm_event(event):
		_confirm()
		return true
	var horizontal := MenuInput.horizontal_event(event)
	if horizontal != 0:
		_adjust(horizontal)
		return true
	return false


func _on_key(key: Key) -> void:
	if MenuInput.is_back(key):
		back_requested.emit()
		return
	var step := MenuInput.vertical(key)
	if step != 0:
		select(MenuInput.wrap_selection(selection, step, item_count()))
	elif MenuInput.is_confirm(key):
		_confirm()
	elif MenuInput.horizontal(key) != 0:
		_adjust(MenuInput.horizontal(key))


## Tap picks a row and a second tap confirms it; screens without rows confirm on any tap.
func _on_touch(event: InputEvent) -> void:
	match _touch.feed(event):
		MenuTouch.Gesture.TAP:
			var index := item_at(_touch.tap_position)
			if index == selection or item_count() == 0:
				_confirm()
			elif index >= 0:
				select(index)
		MenuTouch.Gesture.STEP:
			select(MenuInput.wrap_selection(selection, _touch.direction, item_count()))
		MenuTouch.Gesture.ADJUST:
			_adjust(_touch.direction)


func _process(delta: float) -> void:
	if _settled:
		return
	_selection_tween += (selection - _selection_tween) * minf(1.0, delta * TWEEN_RATE)
	if absf(selection - _selection_tween) < SETTLED:
		_selection_tween = selection
		_settled = true
	_layout_rows()


func _layout_rows() -> void:
	var focus := maxf(_list_top + 55.0, Ui.SCREEN_SIZE.y * 0.48)
	for index in _rows.size():
		var menu_row := _rows[index]
		var distance := index - _selection_tween
		var y := focus + distance * _row_height
		menu_row.visible = index >= selection - ROWS_BEFORE and index < selection + ROWS_AFTER \
			and y >= _list_top - 10.0 and y <= Ui.SCREEN_SIZE.y - 88.0
		if menu_row.visible:
			var selected := index == selection
			var offset := 34.0 if selected else 10.0 + absf(distance) * 12.0
			menu_row.place(MENU_X, y, offset, selected)
