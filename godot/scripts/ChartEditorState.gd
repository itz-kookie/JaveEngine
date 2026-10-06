## An editing session over a private copy of a chart: time cursor, selected lane and owner, hold length and status.
class_name ChartEditorState
extends RefCounted

const GRID := Rect2(58.0, 205.0, 1280.0 - 520.0, 720.0 - 315.0)
const COLUMNS := 8
const LANE_WIDTH := GRID.size.x / COLUMNS
const CENTER_Y := GRID.position.y + GRID.size.y * 0.5
## Time between the cursor line and the top or bottom edge of the grid.
const VISIBLE_MS := 2500.0
const MAX_SUSTAIN_MS := 16000.0
const REPLACE_SNAPS := 0.2
const DELETE_SNAPS := 0.6
const WHEEL_SNAPS := 4.0
const PAGE_SNAPS := 16.0

var chart: ChartData
var cursor_ms := 0.0
var lane := 0
var player := true
var sustain_ms := 0.0
var dirty := false
var status := ""


static func snap_ms(source: ChartData) -> float:
	return 60000.0 / clampf(source.bpm, 1.0, 1000.0) / 4.0


static func column_at(point: Vector2) -> int:
	return clampi(int((point.x - GRID.position.x) / LANE_WIDTH), 0, COLUMNS - 1)


static func y_for_delta(delta_ms: float) -> float:
	return CENTER_Y - delta_ms / VISIBLE_MS * GRID.size.y * 0.5


func _init(source: ChartData, song_time_ms: float) -> void:
	chart = source.copy()
	var snap := snap_ms(chart)
	cursor_ms = roundf(song_time_ms / snap) * snap
	status = "Editing a temporary copy - nothing has been saved"


func snap() -> float:
	return snap_ms(chart)


func maximum_ms() -> float:
	return maxf(60000.0, chart.duration_ms + 60000.0)


func move_cursor(delta_ms: float) -> void:
	cursor_ms = clampf(cursor_ms + delta_ms, 0.0, maximum_ms())


func scroll(wheel_steps: float) -> void:
	move_cursor(wheel_steps * snap() * WHEEL_SNAPS)
	status = "Scrolled chart - click to add or right-click to delete"


func selected_column() -> int:
	return (4 if player else 0) + lane


func cycle_lane(step: int) -> void:
	lane = posmod(lane + step, 4)


func toggle_owner() -> void:
	player = not player


func adjust_sustain(step: int) -> void:
	sustain_ms = clampf(sustain_ms + step * snap(), 0.0, MAX_SUSTAIN_MS)


## Selects the clicked column and moves the cursor to the clicked time, snapped.
func aim_at(point: Vector2) -> void:
	var column := column_at(point)
	player = column >= 4
	lane = column % 4
	var raw := cursor_ms + (CENTER_Y - point.y) / (GRID.size.y * 0.5) * VISIBLE_MS
	var snap := snap()
	cursor_ms = clampf(roundf(raw / snap) * snap, 0.0, maximum_ms())


## Clicks edit at the pointer but leave the timeline where it was.
func add_at(point: Vector2) -> void:
	var timeline := cursor_ms
	aim_at(point)
	add_note()
	cursor_ms = timeline


func delete_at(point: Vector2) -> void:
	var timeline := cursor_ms
	aim_at(point)
	delete_note()
	cursor_ms = timeline


func add_note() -> void:
	var tolerance := snap() * REPLACE_SNAPS
	for index in chart.note_count():
		if chart.is_player(index) == player and chart.lanes[index] == lane \
				and absf(chart.times[index] - cursor_ms) <= tolerance:
			chart.lengths[index] = sustain_ms
			dirty = true
			status = "Updated note at cursor - choose Save Chart to write it"
			Log.info("Editor note updated with mouse/controls")
			return
	chart.add_note(cursor_ms, lane, sustain_ms, player)
	chart.sort_notes()
	dirty = true
	status = "Added note to temporary chart - choose Save Chart to write it"
	Log.info("Editor note added: %s lane %d" % ["player" if player else "opponent", lane + 1])


func delete_note() -> void:
	var best := -1
	var best_distance := snap() * DELETE_SNAPS
	for index in chart.note_count():
		if chart.is_player(index) != player or chart.lanes[index] != lane:
			continue
		var distance := absf(chart.times[index] - cursor_ms)
		if distance <= best_distance:
			best_distance = distance
			best = index
	if best < 0:
		status = "No matching note close enough to the cursor"
		return
	chart.remove_note(best)
	dirty = true
	status = "Deleted note from temporary chart - choose Save Chart to write it"
	Log.info("Editor note deleted with right-click/controls")


func save(path: String) -> bool:
	# A chart without notes fails to load, and the saved copy would shadow the shipped one.
	if chart.note_count() == 0:
		status = "Save failed: the chart has no notes"
		Log.info(status)
		return false
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var error := chart.save(path)
	if error != OK:
		status = "Save failed: " + error_string(error)
		Log.info(status)
		return false
	dirty = false
	status = "Chart saved successfully"
	Log.info("Chart saved from editor: " + path)
	return true
