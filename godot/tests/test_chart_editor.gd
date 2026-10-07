extends "res://tests/test_base.gd"

const TEMP_DIR := "user://test_chart_editor_tmp"
const OVERRIDE_SOURCE := "res://content/data/charts/__jave_editor_test__.json"
const OVERRIDE_PATH := TEST_HOME + "/content/data/charts/__jave_editor_test__.json"
const NEON_STEPS := "res://content/data/charts/neon-steps.json"

var _state_script: GDScript
var _ran := false


func _initialize() -> void:
	pass


## Scripts that use autoloads compile only once the autoload globals exist, so the run waits for the first frame.
func _process(_delta: float) -> bool:
	if not _ran:
		_ran = true
		super._initialize()
	return false


func run() -> void:
	_state_script = load("res://scripts/ChartEditorState.gd")
	_remove_test_files()
	_test_snap()
	_test_open_copies_and_snaps()
	_test_add_replaces_within_tolerance()
	_test_delete_nearest()
	_test_click_mapping()
	_test_keys_and_wheel()
	_test_save_round_trip()
	_test_user_override()
	_test_editor_control_saves_to_override()
	_test_gameplay_takes_saved_chart()
	_remove_test_files()
	check(not FileAccess.file_exists(OVERRIDE_PATH) and not DirAccess.dir_exists_absolute(TEMP_DIR), "test files removed")


func _chart(bpm: float, notes: Array, offset := 0.0, camera_events: Array = []) -> ChartData:
	var chart := ChartData.from_json({"format": "jave-chart-v1", "song": "editor-test", "bpm": bpm, "offsetMs": offset,
		"notes": notes, "cameraEvents": camera_events}, "editor-test", bpm)
	check(chart != null, "test chart loads: " + ChartData.load_error)
	return chart


func _state(chart: ChartData, at_ms := 0.0) -> RefCounted:
	return _state_script.new(chart, at_ms)


func _test_snap() -> void:
	var chart := _chart(120.0, [{"timeMs": 0, "lane": 0}])
	check_near(_state_script.snap_ms(chart), 125.0, "120 BPM snaps to sixteenths")
	chart.bpm = 0.5
	check_near(_state_script.snap_ms(chart), 15000.0, "BPM below 1 clamps")
	chart.bpm = 4000.0
	check_near(_state_script.snap_ms(chart), 15.0, "BPM above 1000 clamps")


func _test_open_copies_and_snaps() -> void:
	var source := _chart(120.0, [{"timeMs": 1000, "lane": 0}])
	source.set_flag(0, ChartData.JUDGED)
	var state := _state(source, 1070.0)
	check_near(state.cursor_ms, 1125.0, "cursor snaps to the nearest sixteenth on open")
	check(state.status == "Editing a temporary copy - nothing has been saved", "open status")
	check(state.chart.has_flag(0, ChartData.JUDGED), "copy keeps note state")
	state.add_note()
	check(source.note_count() == 1, "editing does not touch the playing chart")
	check_near(state.maximum_ms(), 60000.0 + source.duration_ms, "maximum time is chart end plus a minute")


func _test_add_replaces_within_tolerance() -> void:
	var state := _state(_chart(120.0, [{"timeMs": 1000, "lane": 1}]))
	state.lane = 1
	state.player = true
	state.sustain_ms = 250.0
	state.cursor_ms = 1025.0
	state.add_note()
	check(state.chart.note_count() == 1 and state.chart.lengths[0] == 250.0, "add within 0.2 snap updates the hold")
	check(state.dirty and state.status == "Updated note at cursor - choose Save Chart to write it", "update marks dirty")
	state.cursor_ms = 1025.5
	state.sustain_ms = 0.0
	state.add_note()
	check(state.chart.note_count() == 2 and state.chart.times[1] == 1025.5, "add past 0.2 snap creates a note")
	check(state.status == "Added note to temporary chart - choose Save Chart to write it", "add status")
	state.player = false
	state.cursor_ms = 500.0
	state.add_note()
	check(state.chart.times == PackedFloat64Array([500.0, 1000.0, 1025.5]), "added notes stay sorted")
	check(not state.chart.is_player(0), "added note takes the selected owner")
	state.cursor_ms = 1000.0
	state.add_note()
	check(state.chart.note_count() == 4, "owner must match to replace")


func _test_delete_nearest() -> void:
	var state := _state(_chart(120.0, [{"timeMs": 1000, "lane": 0}, {"timeMs": 1060, "lane": 0}, {"timeMs": 1050, "lane": 2}]))
	state.lane = 0
	state.cursor_ms = 1050.0
	state.delete_note()
	check(state.chart.times == PackedFloat64Array([1000.0, 1050.0]), "delete removes the nearest note in the lane")
	check(state.status == "Deleted note from temporary chart - choose Save Chart to write it", "delete status")
	state.cursor_ms = 1075.5
	state.delete_note()
	check(state.chart.note_count() == 2 and state.status == "No matching note close enough to the cursor", "beyond 0.6 snap deletes nothing")
	state.cursor_ms = 1075.0
	state.delete_note()
	check(state.chart.times == PackedFloat64Array([1050.0]), "exactly 0.6 snap still deletes")
	state.lane = 2
	state.delete_note()
	check(state.chart.note_count() == 0, "the last note can be deleted")
	var empty_path := TEMP_DIR.path_join("empty.json")
	check(not state.save(empty_path) and state.dirty and not FileAccess.file_exists(empty_path), "a chart with no notes is not saved")
	state.scroll(0.25)
	check_near(state.cursor_ms, 1075.0 + 125.0, "fractional wheel steps scroll a fraction of four snaps")


func _test_click_mapping() -> void:
	var grid: Rect2 = _state_script.GRID
	var lane_width: float = _state_script.LANE_WIDTH
	var center_y: float = _state_script.CENTER_Y
	var half_height := grid.size.y * 0.5
	check(grid == Rect2(58.0, 205.0, 760.0, 405.0), "grid layout at 1280x720")
	var state := _state(_chart(120.0, [{"timeMs": 0, "lane": 0}]), 1000.0)
	state.aim_at(Vector2(grid.position.x + 5.5 * lane_width, center_y))
	check(state.player and state.lane == 1 and state.cursor_ms == 1000.0, "centre of column 5 is player lane 2 at the cursor")
	state.aim_at(Vector2(grid.position.x + 2.2 * lane_width, center_y - half_height * 0.12))
	check(not state.player and state.lane == 2, "column 2 is opponent lane 3")
	check_near(state.cursor_ms, 1250.0, "300 ms above snaps down to 1250")
	state.cursor_ms = 1000.0
	state.aim_at(Vector2(grid.end.x + 40.0, center_y + half_height))
	check(state.player and state.lane == 3, "column clamps to the last lane")
	check_near(state.cursor_ms, 0.0, "time clamps at zero")
	state.cursor_ms = 2000.0
	state.add_at(Vector2(grid.position.x + 0.5 * lane_width, center_y - half_height * 0.5))
	check(state.cursor_ms == 2000.0, "clicking keeps the timeline position")
	check(state.chart.times.has(3250.0) and not state.player and state.lane == 0, "left click adds at the clicked time and column")
	state.delete_at(Vector2(grid.position.x + 0.5 * lane_width, center_y - half_height * 0.5 - 4.0))
	check(not state.chart.times.has(3250.0) and state.cursor_ms == 2000.0, "right click deletes the note near the pointer")


func _test_keys_and_wheel() -> void:
	var state := _state(_chart(120.0, [{"timeMs": 0, "lane": 0}]), 1000.0)
	state.scroll(1.0)
	check_near(state.cursor_ms, 1500.0, "one wheel step moves four snaps")
	state.scroll(-100.0)
	check_near(state.cursor_ms, 0.0, "scrolling clamps at zero")
	state.move_cursor(1.0e9)
	check_near(state.cursor_ms, state.maximum_ms(), "cursor clamps at the maximum")
	state.lane = 0
	state.cycle_lane(-1)
	check(state.lane == 3, "lane wraps left")
	state.adjust_sustain(-1)
	check_near(state.sustain_ms, 0.0, "hold never goes negative")
	for step in 200:
		state.adjust_sustain(1)
	check_near(state.sustain_ms, 16000.0, "hold caps at 16 s")


func _test_save_round_trip() -> void:
	var chart := _chart(150.0, [{"timeMs": 1000, "lane": 1}, {"timeMs": 500, "lane": 2, "lengthMs": 300, "owner": "opponent"}], 250.0, [
		{"timeMs": 0, "type": "focus", "target": "player", "x": 9, "amount": 3},
		{"timeMs": 100, "type": "position", "target": "player", "x": 12.5, "y": -4, "amount": 2},
		{"timeMs": 200, "type": "zoom", "amount": 0.015, "x": 1},
		{"timeMs": 300, "type": "setZoom", "amount": 1.1, "y": 1},
	])
	var state := _state(chart, 2000.0)
	state.sustain_ms = 400.0
	state.add_note()
	var path := TEMP_DIR.path_join("nested/chart.json")
	check(state.save(path), "editor saves into a new directory")
	check(not state.dirty and state.status == "Chart saved successfully", "save clears dirty")
	check_near(state.chart.duration_ms, 2000.0 + 400.0 + ChartData.TAIL_MS, "save recomputes duration")
	var json: Dictionary = JsonRead.load_file(path)
	check(json.get("format") == "jave-chart-v1" and json.get("song") == "editor-test", "header fields")
	check_near(json.get("offsetMs"), 250.0, "offset written")
	var notes: Array = json.get("notes")
	check(notes.size() == 3, "all notes written")
	check_near(notes[0]["timeMs"], 500.0, "first note time has the offset removed")
	check(notes[0]["owner"] == "opponent" and notes[0]["lengthMs"] == 300.0, "owner and hold written")
	check(not (notes[1] as Dictionary).has("lengthMs"), "tap notes omit lengthMs")
	check_near(notes[2]["timeMs"], 1750.0, "added note has the offset removed")
	var events: Array = json.get("cameraEvents")
	check(events.size() == 4, "camera events written")
	var focus: Dictionary = events[0]
	check(focus.get("target") == "player" and not focus.has("x") and not focus.has("amount"), "focus writes only its target")
	var position: Dictionary = events[1]
	check(position.get("x") == 12.5 and position.get("y") == -4.0 and not position.has("amount"), "position writes x and y only")
	var zoom: Dictionary = events[2]
	check(zoom.get("amount") == 0.015 and not zoom.has("x") and not zoom.has("target"), "zoom writes amount only")
	var set_zoom: Dictionary = events[3]
	check(set_zoom.get("amount") == 1.1 and not set_zoom.has("y"), "setZoom writes amount only")
	check_near(events[1]["timeMs"], 100.0, "camera times have the offset removed")
	var reloaded := ChartData.load_file(path, "", 120.0)
	check(reloaded != null and reloaded.times == state.chart.times and reloaded.lengths == state.chart.lengths, "saved chart reloads with the same notes")


func _test_user_override() -> void:
	var paths := root.get_node("/root/Paths")
	var content := root.get_node("/root/Content")
	check(paths.call("user_mirror", OVERRIDE_SOURCE) == OVERRIDE_PATH, "shipped charts mirror into user://")
	check(paths.call("user_mirror", "user://mods/x/data/charts/a.json") == "user://mods/x/data/charts/a.json", "user charts save in place")
	check(paths.call("user_mirror", "res://content/mods/x/a.json") == TEST_HOME + "/content/mods/x/a.json", "shipped mod charts stay clear of user://mods")
	var song := SongMeta.new()
	song.id = "neon-steps"
	song.chart_path = NEON_STEPS
	check(content.call("chart_path_for", song) == NEON_STEPS, "shipped chart used without an override")
	song.id = "editor-test"
	song.chart_path = OVERRIDE_SOURCE
	check(content.call("chart_path_for", song) == OVERRIDE_SOURCE, "missing override falls back to the shipped path")
	DirAccess.make_dir_recursive_absolute(OVERRIDE_PATH.get_base_dir())
	check(_chart(90.0, [{"timeMs": 10, "lane": 3}]).save(OVERRIDE_PATH) == OK, "override written")
	check(content.call("chart_path_for", song) == OVERRIDE_PATH, "user override preferred")
	var loaded: ChartData = content.call("load_chart", song)
	check(loaded != null and loaded.bpm == 90.0 and loaded.lanes == PackedInt32Array([3]), "Content loads the override chart")
	_remove_override()


func _test_editor_control_saves_to_override() -> void:
	var song := SongMeta.new()
	song.id = "editor-test"
	song.title = "Editor Test"
	song.chart_path = OVERRIDE_SOURCE
	var editor: Control = load("res://scenes/editor/ChartEditor.tscn").instantiate()
	editor.call("setup", song, _chart(120.0, [{"timeMs": 0, "lane": 0}]), 0.0)
	root.add_child(editor)
	var emitted: Array[ChartData] = []
	editor.connect("saved", func(chart: ChartData) -> void: emitted.append(chart))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(58.0 + 6.5 * 95.0, 205.0 + 405.0 * 0.5 - 405.0 * 0.25)
	editor.call("_gui_input", click)
	var state: RefCounted = editor.get("state")
	check(state.chart.note_count() == 2 and state.chart.times[1] == 1250.0, "mouse click on the grid adds a note")
	click.position = Vector2(1000.0, 310.0 + 2.0 * 54.0 + 10.0)
	editor.call("_gui_input", click)
	check(editor.get("selection") == 2, "clicking Save Chart selects it")
	check(FileAccess.file_exists(OVERRIDE_PATH), "save from res:// lands on the user:// mirror")
	check(emitted.size() == 1 and emitted[0] != state.chart and emitted[0].note_count() == 2, "saved emits an independent copy")
	var loaded: ChartData = root.get_node("/root/Content").call("load_chart", song)
	check(loaded != null and loaded.note_count() == 2, "next load picks up the saved chart")
	editor.free()
	_remove_override()


func _test_gameplay_takes_saved_chart() -> void:
	var chart := _chart(120.0, [{"timeMs": 100, "lane": 0}, {"timeMs": 200, "lane": 1}, {"timeMs": 300, "lane": 2}])
	var gameplay := Gameplay.new(chart, SongMeta.new())
	gameplay.song_end_ms = 5000.0
	chart.set_flag(0, ChartData.JUDGED)
	chart.set_flag(1, ChartData.JUDGED)
	gameplay.cursors.advance_unjudged(chart)
	var state := _state(chart, 0.0)
	state.cursor_ms = 50.0
	state.add_note()
	gameplay.replace_chart(state.chart.copy())
	check(gameplay.chart.note_count() == 4 and gameplay.cursors.first_unjudged == 0, "cursors restart on the edited chart")
	check(gameplay.chart.has_flag(1, ChartData.JUDGED) and gameplay.chart.has_flag(2, ChartData.JUDGED), "judged state follows its notes")
	check_near(gameplay.song_end_ms, 5000.0, "song end is unchanged by an edit")


func _remove_override() -> void:
	DirAccess.remove_absolute(OVERRIDE_PATH)
	DirAccess.remove_absolute(TEST_HOME + "/content/data/charts")
	DirAccess.remove_absolute(TEST_HOME + "/content/data")
	DirAccess.remove_absolute(TEST_HOME + "/content")


func _remove_test_files() -> void:
	_remove_override()
	DirAccess.remove_absolute(TEMP_DIR.path_join("nested/chart.json"))
	DirAccess.remove_absolute(TEMP_DIR.path_join("nested"))
	DirAccess.remove_absolute(TEMP_DIR)
