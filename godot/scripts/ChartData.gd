class_name ChartData
extends RefCounted

const FORMAT := "jave-chart-v1"
const TAIL_MS := 2000.0

const HEAD_HIT := 1
const HOLDING := 2
const JUDGED := 4
const HIT := 8

static var load_error := ""

var song_id := ""
var difficulty := "normal"
var bpm := 120.0
var offset_ms := 0.0
var duration_ms := 0.0

var times := PackedFloat64Array()
var lengths := PackedFloat64Array()
var lanes := PackedInt32Array()
var players := PackedByteArray()
var flags := PackedInt32Array()
var hold_release_ms := PackedFloat64Array()

var camera_times := PackedFloat64Array()
var camera_types := PackedStringArray()
var camera_targets := PackedStringArray()
var camera_x := PackedFloat64Array()
var camera_y := PackedFloat64Array()
var camera_amounts := PackedFloat64Array()


static func load_file(path: String, fallback_song_id: String, fallback_bpm: float) -> ChartData:
	var json: Variant = JsonRead.load_file(path)
	if not json is Dictionary:
		return _fail("Could not read chart: " + path)
	return from_json(json, fallback_song_id, fallback_bpm)


static func from_json(json: Dictionary, fallback_song_id: String, fallback_bpm: float) -> ChartData:
	if JsonRead.string(json, "format") != FORMAT:
		return _fail("Unsupported chart format")
	var chart := ChartData.new()
	chart.song_id = JsonRead.string(json, "song", fallback_song_id)
	chart.difficulty = JsonRead.string(json, "difficulty", "normal")
	chart.bpm = JsonRead.number(json, "bpm", fallback_bpm)
	chart.offset_ms = JsonRead.number(json, "offsetMs", 0.0)
	if chart.bpm <= 0.0 or chart.bpm > 1000.0:
		return _fail("Chart BPM is out of range")
	var error := chart._read_notes(JsonRead.array(json, "notes"))
	if not error.is_empty():
		return _fail(error)
	chart._read_camera_events(JsonRead.array(json, "cameraEvents"))
	if chart.note_count() == 0:
		return _fail("Chart has no notes")
	chart.sort_notes()
	chart.duration_ms += TAIL_MS
	load_error = ""
	return chart


static func _fail(message: String) -> ChartData:
	load_error = message
	return null


func _read_notes(items: Array) -> String:
	for item: Variant in items:
		if not item is Dictionary:
			return "A chart note is not an object"
		var time := JsonRead.number(item, "timeMs", -1.0) + offset_ms
		var lane := JsonRead.integer(item, "lane", -1)
		var length := maxf(0.0, JsonRead.number(item, "lengthMs", 0.0))
		if time < 0.0 or lane < 0 or lane > 3:
			return "Invalid chart note"
		add_note(time, lane, length, JsonRead.string(item, "owner", "player") != "opponent")
		duration_ms = maxf(duration_ms, time + length)
	return ""


func _read_camera_events(items: Array) -> void:
	var order: Array[int] = []
	var parsed: Array[Dictionary] = []
	for item: Variant in items:
		if item is Dictionary and not JsonRead.string(item, "type").is_empty():
			order.append(parsed.size())
			parsed.append(item)
	var event_times := PackedFloat64Array()
	for event in parsed:
		event_times.append(JsonRead.number(event, "timeMs", 0.0) + offset_ms)
	_stable_sort(order, event_times)
	for index in order:
		var event := parsed[index]
		camera_times.append(event_times[index])
		camera_types.append(JsonRead.string(event, "type"))
		camera_targets.append(JsonRead.string(event, "target"))
		camera_x.append(JsonRead.number(event, "x", 0.0))
		camera_y.append(JsonRead.number(event, "y", 0.0))
		camera_amounts.append(JsonRead.number(event, "amount", 0.0))


func add_note(time: float, lane: int, length: float, player: bool) -> void:
	times.append(time)
	lanes.append(lane)
	lengths.append(length)
	players.append(1 if player else 0)
	flags.append(0)
	hold_release_ms.append(0.0)


func note_count() -> int:
	return times.size()


func is_player(index: int) -> bool:
	return players[index] != 0


func has_flag(index: int, flag: int) -> bool:
	return flags[index] & flag != 0


func set_flag(index: int, flag: int, enabled: bool = true) -> void:
	flags[index] = flags[index] | flag if enabled else flags[index] & ~flag


func sort_notes() -> void:
	var order: Array[int] = []
	for index in note_count():
		order.append(index)
	_stable_sort(order, times)
	var old_times := times.duplicate()
	var old_lengths := lengths.duplicate()
	var old_lanes := lanes.duplicate()
	var old_players := players.duplicate()
	var old_flags := flags.duplicate()
	var old_release := hold_release_ms.duplicate()
	for target in order.size():
		var source := order[target]
		times[target] = old_times[source]
		lengths[target] = old_lengths[source]
		lanes[target] = old_lanes[source]
		players[target] = old_players[source]
		flags[target] = old_flags[source]
		hold_release_ms[target] = old_release[source]


static func _stable_sort(order: Array[int], keys: PackedFloat64Array) -> void:
	order.sort_custom(func(a: int, b: int) -> bool:
		return keys[a] < keys[b] or (keys[a] == keys[b] and a < b))


func to_json() -> Dictionary:
	var notes: Array[Dictionary] = []
	for index in note_count():
		var item := {
			"timeMs": maxf(0.0, times[index] - offset_ms),
			"lane": lanes[index],
			"owner": "player" if is_player(index) else "opponent",
		}
		if lengths[index] > 0.0:
			item["lengthMs"] = lengths[index]
		notes.append(item)
	return {
		"format": FORMAT,
		"song": song_id,
		"difficulty": difficulty,
		"bpm": bpm,
		"offsetMs": offset_ms,
		"notes": notes,
		"cameraEvents": _camera_events_json(),
	}


func _camera_events_json() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for index in camera_times.size():
		var type := camera_types[index]
		var item := {"timeMs": maxf(0.0, camera_times[index] - offset_ms), "type": type}
		if not camera_targets[index].is_empty():
			item["target"] = camera_targets[index]
		if type == "position":
			item["x"] = camera_x[index]
			item["y"] = camera_y[index]
		if type == "zoom" or type == "setZoom":
			item["amount"] = camera_amounts[index]
		events.append(item)
	return events


func save(path: String) -> Error:
	sort_notes()
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_json(), "  "))
	file.close()
	duration_ms = _content_end_ms() + TAIL_MS
	return OK


func _content_end_ms() -> float:
	var end := 0.0
	for index in note_count():
		end = maxf(end, times[index] + lengths[index])
	return end
