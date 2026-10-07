extends "res://tests/test_base.gd"

const NEON_STEPS := "res://content/mods/jave-demo/data/charts/neon-steps.json"
const ROUND_TRIP_PATH := "user://test_chart_round_trip.json"


func run() -> void:
	_test_neon_steps()
	_test_round_trip()
	_test_offset_folding_and_stable_sort()
	_test_rejections()


func _test_neon_steps() -> void:
	var chart := ChartData.load_file(NEON_STEPS, "neon-steps", 120.0)
	check(chart != null, "neon-steps loads: " + ChartData.load_error)
	if chart == null:
		return
	check(chart.note_count() == 64, "neon-steps has 64 notes, got %d" % chart.note_count())
	check(chart.song_id == "neon-steps", "song id")
	check_near(chart.bpm, 120.0, "bpm")
	check_near(chart.duration_ms, 23500.0 + ChartData.TAIL_MS, "duration includes the 2 s tail")
	var holds := 0
	for index in chart.note_count():
		if index > 0:
			check(chart.times[index - 1] <= chart.times[index], "notes sorted at %d" % index)
		if chart.lengths[index] > 0.0:
			holds += 1
	check(holds == 4, "neon-steps has 4 holds")


func _test_round_trip() -> void:
	var original := ChartData.load_file(NEON_STEPS, "neon-steps", 120.0)
	check(original.save(ROUND_TRIP_PATH) == OK, "chart saves")
	var reloaded := ChartData.load_file(ROUND_TRIP_PATH, "", 1.0)
	check(reloaded != null, "saved chart reloads")
	if reloaded == null:
		return
	check(reloaded.times == original.times, "times survive round trip")
	check(reloaded.lengths == original.lengths, "lengths survive round trip")
	check(reloaded.lanes == original.lanes, "lanes survive round trip")
	check(reloaded.players == original.players, "owners survive round trip")
	check(reloaded.camera_times == original.camera_times, "camera events survive round trip")
	check_near(reloaded.duration_ms, original.duration_ms, "duration survives round trip")
	check(JSON.stringify(reloaded.to_json()) == JSON.stringify(original.to_json()), "serialised form is stable")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ROUND_TRIP_PATH))


func _test_offset_folding_and_stable_sort() -> void:
	var chart := ChartData.from_json({
		"format": "jave-chart-v1",
		"bpm": 150,
		"offsetMs": 250,
		"notes": [
			{"timeMs": 1000, "lane": 1},
			{"timeMs": 500, "lane": 2, "lengthMs": 300, "owner": "opponent"},
			{"timeMs": 500, "lane": 0},
		],
		"cameraEvents": [
			{"timeMs": 900, "type": "zoom", "amount": 0.02},
			{"timeMs": 100, "type": "focus", "target": "player"},
			{"timeMs": 50, "type": ""},
			"not an event",
		],
	}, "fallback-id", 120.0)
	check(chart != null, "offset chart loads: " + ChartData.load_error)
	if chart == null:
		return
	check(chart.song_id == "fallback-id", "missing song id falls back to the song")
	check(chart.times == PackedFloat64Array([750.0, 750.0, 1250.0]), "offset folded into note times")
	check(chart.lanes == PackedInt32Array([2, 0, 1]), "equal times keep file order")
	check(chart.players == PackedByteArray([0, 1, 1]), "owner defaults to player")
	check_near(chart.duration_ms, 1250.0 + ChartData.TAIL_MS, "duration from latest note end")
	check(chart.camera_times == PackedFloat64Array([350.0, 1150.0]), "camera events offset, filtered and sorted")
	check(chart.camera_types == PackedStringArray(["focus", "zoom"]), "camera event types")
	var notes: Array = chart.to_json()["notes"]
	check_near(notes[0]["timeMs"], 500.0, "save removes the offset")
	check(notes[0]["owner"] == "opponent" and notes[0]["lengthMs"] == 300.0, "save keeps owner and hold length")
	check(not (notes[1] as Dictionary).has("lengthMs"), "save omits zero hold length")


func _test_rejections() -> void:
	var base_note := {"timeMs": 100, "lane": 0}
	_expect_rejected({"format": "other", "notes": [base_note]}, "Unsupported chart format")
	_expect_rejected({"format": "jave-chart-v1", "bpm": 0, "notes": [base_note]}, "Chart BPM is out of range")
	_expect_rejected({"format": "jave-chart-v1", "notes": [{"timeMs": 100, "lane": 4}]}, "Invalid chart note")
	_expect_rejected({"format": "jave-chart-v1", "offsetMs": -200, "notes": [base_note]}, "Invalid chart note")
	_expect_rejected({"format": "jave-chart-v1", "notes": [5]}, "A chart note is not an object")
	_expect_rejected({"format": "jave-chart-v1", "notes": []}, "Chart has no notes")


func _expect_rejected(json: Dictionary, expected_error: String) -> void:
	var chart := ChartData.from_json(json, "x", 120.0)
	check(chart == null and ChartData.load_error == expected_error, "rejects with '%s', got '%s'" % [expected_error, ChartData.load_error])
