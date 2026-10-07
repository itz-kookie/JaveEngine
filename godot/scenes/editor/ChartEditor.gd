## In-song chart editor: grid, cursor and notes drawn in _draw, with the side panel of actions.
class_name ChartEditor
extends Control

signal saved(chart: ChartData)
signal close_requested

enum Action { ADD, DELETE, SAVE, EXIT }

const ACTION_LABELS: PackedStringArray = ["Add Note", "Delete Nearest", "Save Chart", "Exit Without Saving"]
const GRID := ChartEditorState.GRID
const LANE_WIDTH := ChartEditorState.LANE_WIDTH
const CENTER_Y := ChartEditorState.CENTER_Y
const PANEL := Rect2(GRID.end.x + 28.0, GRID.position.y - 30.0, Ui.SCREEN_SIZE.x - GRID.end.x - 28.0 - 48.0, GRID.size.y + 30.0)
const ACTIONS_Y := GRID.position.y + 105.0
const ACTION_SPACING := 54.0
const ACTION_HEIGHT := 44.0
const NOTE_SIZE := 44.0
const GRID_COLOR := Color8(15, 18, 42)
const BORDER_COLOR := Color8(57, 65, 105)
const PANEL_COLOR := Color8(20, 23, 52)
const DIVIDER_COLOR := Color8(47, 53, 88)
const OPPONENT_COLOR := Color8(255, 130, 165)
const CURSOR_COLOR := Color8(255, 226, 92)
const POINTER_COLOR := Color8(200, 208, 235)
const POINTER_TEXT_COLOR := Color8(230, 234, 250)
const ACTION_IDLE := Color8(27, 31, 65)
const ACTION_BASE := Color8(31, 35, 70)
const SAVE_FILL := Color8(38, 118, 84)
const SAVE_BORDER := Color8(115, 245, 170)
const ACTION_IDLE_TEXT := Color8(160, 170, 202)
const DIRTY_COLOR := Color8(255, 190, 75)
const CLEAN_COLOR := Color8(105, 225, 145)
const STATUS_DIRTY := Color8(255, 200, 100)
const STATUS_CLEAN := Color8(140, 210, 170)
const OPPONENT_HEADING := "OPPONENT"
const PLAYER_HEADING := "PLAYER"
const POINTER_HINT := "LEFT CLICK ADD  •  RIGHT CLICK DELETE"
const FOOTER := "Mouse wheel scrolls   •   Left click adds   •   Right click deletes   •   Click Save Chart\nQ/E Time   ←/→ Lane   Tab Owner   A/D Hold   Esc Exit"

var song: SongMeta
var state: ChartEditorState
var selection := 0

var _pointer := Vector2(-1.0, -1.0)
var _hovered_action := -1
var _time_text := ""
var _time_text_ms := NAN
var _font: Font
var _note_textures: Array[Texture2D] = []
var _grid_style: StyleBoxFlat
var _panel_style: StyleBoxFlat
var _column_style: StyleBoxFlat
var _hover_style: StyleBoxFlat
var _cursor_style: StyleBoxFlat
var _player_hold_style: StyleBoxFlat
var _opponent_hold_style: StyleBoxFlat
var _action_idle_style: StyleBoxFlat
var _action_active_style: StyleBoxFlat
var _action_save_hover_style: StyleBoxFlat
var _action_save_style: StyleBoxFlat
var _saved_label: Label
var _owner_label: Label
var _hold_label: Label
var _status_label: Label
var _action_labels: Array[Label] = []


func setup(edited_song: SongMeta, chart: ChartData, song_time_ms: float) -> void:
	song = edited_song
	state = ChartEditorState.new(chart, song_time_ms)


func _ready() -> void:
	size = Ui.SCREEN_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = Ui.bold_font()
	for lane in 4:
		_note_textures.append(TextureCache.get_texture(Strumline.note_image_path("note", lane, song.package_root)))
	_build_styles()
	_build_labels()
	_refresh()


func _build_styles() -> void:
	_grid_style = Ui.style(GRID_COLOR, 22, BORDER_COLOR, 2)
	_panel_style = Ui.style(PANEL_COLOR, 22, BORDER_COLOR, 2)
	_column_style = Ui.style(Color8(18, 21, 48).lerp(Ui.accent, 0.13), 12)
	_hover_style = Ui.style(Color.TRANSPARENT, 10, Color.WHITE, 1)
	_cursor_style = Ui.style(CURSOR_COLOR, 2)
	_player_hold_style = Ui.style(Ui.accent, 4)
	_opponent_hold_style = Ui.style(Ui.accent2, 4)
	var active_fill := ACTION_BASE.lerp(Ui.accent, 0.30)
	_action_idle_style = Ui.style(ACTION_IDLE, 13)
	_action_active_style = Ui.style(active_fill, 13, Ui.accent, 2)
	_action_save_hover_style = Ui.style(active_fill, 13, SAVE_BORDER, 2)
	_action_save_style = Ui.style(SAVE_FILL, 13, SAVE_BORDER, 2)


func _build_labels() -> void:
	var backdrop := MenuBackdrop.new()
	backdrop.show_behind_parent = true
	add_child(backdrop)
	backdrop.show_style("")
	Ui.plain_header(self, "PRESS 7 IN GAME", "CHART EDITOR", "Editing %s — saving is manual only." % song.title)
	var inner := Rect2(PANEL.position.x + 24.0, 0.0, PANEL.size.x - 48.0, 0.0)
	_saved_label = Ui.text(self, "", Rect2(PANEL.position.x + 22.0, GRID.position.y - 12.0, PANEL.size.x - 44.0, 30.0), 15, CLEAN_COLOR, true, HORIZONTAL_ALIGNMENT_CENTER)
	_owner_label = Ui.text(self, "", Rect2(inner.position.x, GRID.position.y + 30.0, inner.size.x, 30.0), 17, Color8(230, 233, 247), true, HORIZONTAL_ALIGNMENT_CENTER)
	_hold_label = Ui.text(self, "", Rect2(inner.position.x, GRID.position.y + 62.0, inner.size.x, 27.0), 15, Color8(158, 170, 205), false, HORIZONTAL_ALIGNMENT_CENTER)
	for index in ACTION_LABELS.size():
		var rect := _action_rect(index)
		_action_labels.append(Ui.text(self, ACTION_LABELS[index], Rect2(rect.position.x + 8.0, rect.position.y, rect.size.x - 16.0, rect.size.y), 17, ACTION_IDLE_TEXT, false, HORIZONTAL_ALIGNMENT_CENTER))
	_status_label = Ui.wrapped_text(self, "", Rect2(inner.position.x, ACTIONS_Y + 224.0, inner.size.x, 58.0), 14, STATUS_CLEAN)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var footer := Ui.wrapped_text(self, FOOTER, Rect2(58.0, Ui.SCREEN_SIZE.y - 88.0, Ui.SCREEN_SIZE.x - 116.0, 60.0), 15, Color8(145, 157, 192))
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


static func _action_rect(index: int) -> Rect2:
	return Rect2(PANEL.position.x + 20.0, ACTIONS_Y + index * ACTION_SPACING, PANEL.size.x - 40.0, ACTION_HEIGHT)


func _gui_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion != null:
		_move_pointer(motion.position)
		return
	var button := event as InputEventMouseButton
	if button == null or not button.pressed:
		return
	_pointer = button.position
	accept_event()
	_on_click(button)
	_refresh()


func _move_pointer(at: Vector2) -> void:
	var was_over_grid := GRID.has_point(_pointer)
	_pointer = at
	var hovered := _action_at(at)
	if hovered != _hovered_action:
		_hovered_action = hovered
		_style_actions()
	if was_over_grid or GRID.has_point(at):
		queue_redraw()


func _on_click(button: InputEventMouseButton) -> void:
	var over_grid := GRID.has_point(button.position)
	match button.button_index:
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if over_grid:
				var steps := button.factor if button.factor > 0.0 else 1.0
				state.scroll(steps if button.button_index == MOUSE_BUTTON_WHEEL_UP else -steps)
				Log.info("Chart editor scrolled with mouse wheel")
		MOUSE_BUTTON_LEFT:
			var action := _action_at(button.position)
			if over_grid:
				state.add_at(button.position)
			elif action >= 0:
				selection = action
				_activate(selection)
		MOUSE_BUTTON_RIGHT:
			if over_grid:
				state.delete_at(button.position)


func _action_at(point: Vector2) -> int:
	if GRID.has_point(point):
		return -1
	for index in ACTION_LABELS.size():
		if _action_rect(index).has_point(point):
			return index
	return -1


func _unhandled_input(event: InputEvent) -> void:
	var key := MenuInput.key_of(event)
	if MenuInput.is_back_event(event):
		get_viewport().set_input_as_handled()
		close_requested.emit()
		return
	var vertical := MenuInput.vertical_event(event)
	if vertical != 0:
		get_viewport().set_input_as_handled()
		selection = MenuInput.wrap_selection(selection, vertical, ACTION_LABELS.size())
		_refresh()
		return
	var horizontal := MenuInput.horizontal_event(event)
	if horizontal != 0:
		get_viewport().set_input_as_handled()
		state.cycle_lane(horizontal)
		_refresh()
		return
	if MenuInput.is_confirm_event(event):
		get_viewport().set_input_as_handled()
		_activate(selection)
		_refresh()
		return
	if key == KEY_NONE:
		return
	get_viewport().set_input_as_handled()
	_on_key(key)
	_refresh()


func _on_key(key: Key) -> void:
	var snap := state.snap()
	match key:
		KEY_ESCAPE, KEY_7, KEY_KP_7:
			close_requested.emit()
		KEY_Q:
			state.move_cursor(-snap)
		KEY_E:
			state.move_cursor(snap)
		KEY_PAGEUP:
			state.move_cursor(-snap * ChartEditorState.PAGE_SNAPS)
		KEY_PAGEDOWN:
			state.move_cursor(snap * ChartEditorState.PAGE_SNAPS)
		KEY_LEFT:
			state.cycle_lane(-1)
		KEY_RIGHT:
			state.cycle_lane(1)
		KEY_TAB:
			state.toggle_owner()
		KEY_A:
			state.adjust_sustain(-1)
		KEY_D:
			state.adjust_sustain(1)
		KEY_SPACE:
			state.add_note()
		_:
			if MenuInput.is_confirm(key):
				_activate(selection)
			elif MenuInput.vertical(key) != 0:
				selection = MenuInput.wrap_selection(selection, MenuInput.vertical(key), ACTION_LABELS.size())


func _activate(action: int) -> void:
	match action:
		Action.ADD:
			state.add_note()
		Action.DELETE:
			state.delete_note()
		Action.SAVE:
			_save()
		Action.EXIT:
			close_requested.emit()


## Shipped charts are read-only, so saves land on the user:// mirror that Content prefers when loading.
func _save() -> void:
	if state.save(Paths.user_mirror(song.chart_path)):
		saved.emit(state.chart.copy())


func _refresh() -> void:
	if not is_inside_tree():
		return
	_saved_label.text = "UNSAVED CHANGES" if state.dirty else "SAVED / UNCHANGED"
	_saved_label.add_theme_color_override(&"font_color", DIRTY_COLOR if state.dirty else CLEAN_COLOR)
	_owner_label.text = "%s    Lane: %d" % ["Owner: Player" if state.player else "Owner: Opponent", state.lane + 1]
	_hold_label.text = "Hold: %d ms" % roundi(state.sustain_ms)
	_status_label.text = state.status
	_status_label.add_theme_color_override(&"font_color", STATUS_DIRTY if state.dirty else STATUS_CLEAN)
	if state.cursor_ms != _time_text_ms:
		_time_text_ms = state.cursor_ms
		_time_text = "%d ms" % roundi(state.cursor_ms)
	_style_actions()
	queue_redraw()


func _style_actions() -> void:
	for index in _action_labels.size():
		var active := index == selection or index == _hovered_action
		var label := _action_labels[index]
		label.add_theme_font_size_override(&"font_size", 19 if index == selection else 17)
		label.add_theme_color_override(&"font_color", Color.WHITE if active else ACTION_IDLE_TEXT)
		if active:
			label.add_theme_font_override(&"font", _font)
		else:
			label.remove_theme_font_override(&"font")
	queue_redraw()


func _draw() -> void:
	draw_style_box(_grid_style, GRID)
	var column_x := GRID.position.x + state.selected_column() * LANE_WIDTH
	draw_style_box(_column_style, Rect2(column_x + 3.0, GRID.position.y + 3.0, LANE_WIDTH - 6.0, GRID.size.y - 6.0))
	for column in range(1, ChartEditorState.COLUMNS):
		draw_rect(Rect2(GRID.position.x + column * LANE_WIDTH, GRID.position.y + 8.0, 1.0, GRID.size.y - 16.0),
			Ui.accent2 if column == 4 else DIVIDER_COLOR)
	var half_width := GRID.size.x * 0.5
	_draw_text(OPPONENT_HEADING, Rect2(GRID.position.x, GRID.position.y - 32.0, half_width, 28.0), 15, OPPONENT_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	_draw_text(PLAYER_HEADING, Rect2(GRID.position.x + half_width, GRID.position.y - 32.0, half_width, 28.0), 15, Ui.accent, HORIZONTAL_ALIGNMENT_CENTER)
	_draw_notes()
	draw_style_box(_cursor_style, Rect2(GRID.position.x + 8.0, CENTER_Y - 2.0, GRID.size.x - 16.0, 4.0))
	_draw_text(_time_text, Rect2(GRID.position.x + 12.0, CENTER_Y - 31.0, 140.0, 26.0), 14, CURSOR_COLOR, HORIZONTAL_ALIGNMENT_LEFT)
	if GRID.has_point(_pointer):
		_draw_pointer()
	draw_style_box(_panel_style, PANEL)
	for index in ACTION_LABELS.size():
		draw_style_box(_action_style(index), _action_rect(index))


## Only notes whose heads are within VISIBLE_MS of the cursor are drawn.
func _draw_notes() -> void:
	var chart := state.chart
	var count := chart.note_count()
	var index := chart.times.bsearch(state.cursor_ms - ChartEditorState.VISIBLE_MS)
	var last_ms := state.cursor_ms + ChartEditorState.VISIBLE_MS
	while index < count and chart.times[index] <= last_ms:
		var player := chart.is_player(index)
		var lane := chart.lanes[index]
		var center_x := GRID.position.x + ((4 if player else 0) + lane + 0.5) * LANE_WIDTH
		var y := ChartEditorState.y_for_delta(chart.times[index] - state.cursor_ms)
		if chart.lengths[index] > 0.0:
			var end_y := y - chart.lengths[index] / ChartEditorState.VISIBLE_MS * GRID.size.y * 0.5
			draw_style_box(_player_hold_style if player else _opponent_hold_style,
				Rect2(center_x - 4.0, end_y, 8.0, maxf(3.0, y - end_y)))
		var texture := _note_textures[lane]
		if texture != null:
			draw_texture_rect(texture, Rect2(center_x - NOTE_SIZE * 0.5, y - NOTE_SIZE * 0.5, NOTE_SIZE, NOTE_SIZE), false)
		index += 1


func _draw_pointer() -> void:
	var column_x := GRID.position.x + ChartEditorState.column_at(_pointer) * LANE_WIDTH
	draw_style_box(_hover_style, Rect2(column_x + 4.0, GRID.position.y + 4.0, LANE_WIDTH - 8.0, GRID.size.y - 8.0))
	draw_rect(Rect2(GRID.position.x + 8.0, _pointer.y - 1.0, GRID.size.x - 16.0, 2.0), POINTER_COLOR)
	_draw_text(POINTER_HINT, Rect2(GRID.end.x - 330.0, _pointer.y - 28.0, 315.0, 24.0), 12, POINTER_TEXT_COLOR, HORIZONTAL_ALIGNMENT_RIGHT)


func _action_style(index: int) -> StyleBoxFlat:
	var selected := index == selection
	if not selected and index != _hovered_action:
		return _action_idle_style
	if index != Action.SAVE:
		return _action_active_style
	return _action_save_style if selected else _action_save_hover_style


func _draw_text(value: String, rect: Rect2, font_size: int, color: Color, align: HorizontalAlignment) -> void:
	var baseline := rect.position.y + (rect.size.y + _font.get_ascent(font_size) - _font.get_descent(font_size)) * 0.5
	draw_string(_font, Vector2(rect.position.x, baseline), value, align, rect.size.x, font_size, color)
