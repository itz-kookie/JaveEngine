class_name PauseMenu
extends CanvasLayer

signal resume_requested
signal restart_requested
signal botplay_toggled

enum Item { RESUME, RESTART, BOTPLAY }

const PANEL_SIZE := Vector2(520.0, 440.0)
const ROW_SPACING := 64.0
const ROW_HEIGHT := 52.0
const SHADOW_COLOR := Color8(4, 5, 13)
const PANEL_COLOR := Color8(18, 21, 48)
const BORDER_BASE := Color8(40, 45, 80)
const ROW_BASE := Color8(30, 34, 68)
const IDLE_TEXT := Color8(160, 170, 204)
const HINT_COLOR := Color8(137, 149, 184)

var selection := 0

var _time := 0.0
var _touch: MenuTouch = MenuTouch.new() if TouchControls.enabled() else null
var _root: Control
var _built_accent: Color
var _title: Label
var _rows: Array[Control] = []
var _labels: Array[Label] = []
var _highlights: Array[Control] = []


func _ready() -> void:
	visible = false
	_build()


func open(song_title: String, botplay: bool) -> void:
	if _built_accent != Ui.accent:
		_rebuild()
	_title.text = song_title
	set_botplay(botplay)
	selection = 0
	_time = 0.0
	_show_selection()
	visible = true


func close() -> void:
	visible = false


func set_botplay(enabled: bool) -> void:
	_labels[Item.BOTPLAY].text = "Botplay    " + ("ON" if enabled else "OFF")


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if _touch != null and (event is InputEventScreenTouch or event is InputEventScreenDrag):
		get_viewport().set_input_as_handled()
		_match_touch(event)
		return
	var key := MenuInput.key_of(event)
	var back := MenuInput.is_back_event(event) or (GameActions.is_pressed(event, GameActions.GAME_PAUSE) \
		and not MenuInput.is_confirm_event(event))
	var step := MenuInput.vertical_event(event)
	var confirm := MenuInput.is_confirm_event(event)
	if key == KEY_NONE and not back and step == 0 and not confirm:
		return
	get_viewport().set_input_as_handled()
	if back:
		resume_requested.emit()
		return
	if step != 0:
		selection = MenuInput.wrap_selection(selection, step, Item.size())
		_show_selection()
	elif confirm:
		_choose()


func _match_touch(event: InputEvent) -> void:
	match _touch.feed(event):
		MenuTouch.Gesture.TAP:
			var index := _item_at(_touch.tap_position)
			if index < 0:
				return
			if index == selection:
				_choose()
			else:
				selection = index
				_show_selection()
		MenuTouch.Gesture.STEP:
			selection = MenuInput.wrap_selection(selection, _touch.direction, Item.size())
			_show_selection()


func _item_at(point: Vector2) -> int:
	var origin := (Ui.SCREEN_SIZE - PANEL_SIZE) * 0.5
	var rows_x := origin.x + 58.0
	var row_width := PANEL_SIZE.x - 116.0
	for index in Item.size():
		var row := Rect2(rows_x, origin.y + 145.0 + index * ROW_SPACING, row_width, ROW_HEIGHT)
		if row.has_point(point):
			return index
	return -1


func _choose() -> void:
	match selection:
		Item.RESUME:
			resume_requested.emit()
		Item.RESTART:
			restart_requested.emit()
		Item.BOTPLAY:
			botplay_toggled.emit()


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	_rows[selection].position.x = 8.0 + sin(_time * 6.0) * 2.0


func _show_selection() -> void:
	for index in _rows.size():
		var selected := index == selection
		_rows[index].position.x = 0.0
		_highlights[index].visible = selected
		var label := _labels[index]
		label.add_theme_font_size_override(&"font_size", 24 if selected else 21)
		label.add_theme_color_override(&"font_color", Color.WHITE if selected else IDLE_TEXT)
		if selected:
			label.add_theme_font_override(&"font", Ui.bold_font())
		else:
			label.remove_theme_font_override(&"font")


func _rebuild() -> void:
	_root.free()
	_rows.clear()
	_labels.clear()
	_highlights.clear()
	_build()


func _build() -> void:
	_built_accent = Ui.accent
	var root := Control.new()
	root.size = Ui.SCREEN_SIZE
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_root = root
	var origin := (Ui.SCREEN_SIZE - PANEL_SIZE) * 0.5
	Ui.box(root, Rect2(origin.x - 8.0, origin.y + 10.0, PANEL_SIZE.x + 16.0, PANEL_SIZE.y + 8.0), SHADOW_COLOR, 34)
	Ui.box(root, Rect2(origin, PANEL_SIZE), PANEL_COLOR, 30, BORDER_BASE.lerp(Ui.accent, 0.62), 3)
	Ui.text(root, "PAUSED", Rect2(origin.x + 40.0, origin.y + 30.0, PANEL_SIZE.x - 80.0, 62.0), 42, Color8(250, 251, 255), true, HORIZONTAL_ALIGNMENT_CENTER)
	_title = Ui.text(root, "", Rect2(origin.x + 40.0, origin.y + 88.0, PANEL_SIZE.x - 80.0, 32.0), 17, Ui.accent, true, HORIZONTAL_ALIGNMENT_CENTER)
	for index in Item.size():
		_build_row(root, Vector2(origin.x + 58.0, origin.y + 145.0 + index * ROW_SPACING), PANEL_SIZE.x - 116.0)
	_labels[Item.RESUME].text = "Resume"
	_labels[Item.RESTART].text = "Restart Song"
	Ui.text(root, "↑↓ / D-PAD Choose     Enter / A Select     B / Start Resume", Rect2(origin.x + 35.0, origin.y + PANEL_SIZE.y - 58.0, PANEL_SIZE.x - 70.0, 30.0), 15, HINT_COLOR, false, HORIZONTAL_ALIGNMENT_CENTER)


func _build_row(root: Control, at: Vector2, width: float) -> void:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(holder)
	var row := Control.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.position = at
	holder.add_child(row)
	var highlight := Control.new()
	highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(highlight)
	Ui.box(highlight, Rect2(0.0, 0.0, width, ROW_HEIGHT), ROW_BASE.lerp(Ui.accent, 0.24), 16)
	Ui.box(highlight, Rect2(0.0, 10.0, 5.0, 32.0), Ui.accent, 3)
	_rows.append(row)
	_highlights.append(highlight)
	_labels.append(Ui.text(row, "", Rect2(24.0, 0.0, width - 40.0, ROW_HEIGHT), 21, IDLE_TEXT))
