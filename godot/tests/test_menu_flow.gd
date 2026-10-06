extends SceneTree

## Drives Main with key events: Title -> Freeplay -> song -> pause/botplay/restart -> Results -> back.
const LOAD_TIMEOUT_FRAMES := 600
const FINISH_TIMEOUT_FRAMES := 600

var _checks := 0
var _failures := 0
var _main: Node


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	_main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(_main)
	await process_frame
	_expect_screen("TITLE")
	_press(KEY_DOWN)
	_press(KEY_ENTER)
	_expect_screen("FREEPLAY")
	await _wait_frames(2)
	_press(KEY_ENTER)
	_expect_screen("PLAY")
	await _check_pause_and_botplay()
	await _check_restart_keeps_botplay()
	await _check_song_end_and_results()
	_check_grades()
	await _check_empty_content()
	_main.queue_free()
	# Let the audio server release stopped playbacks before quitting.
	await create_timer(0.2).timeout
	_finish()


func _check_pause_and_botplay() -> void:
	var play: Node = _main.call("current_play")
	await _wait_until_playing(play)
	var conductor := root.get_node("/root/Conductor")
	_press(KEY_7)
	_expect_screen("PLAY")
	_check(not play.get("gameplay").botplay, "key 7 does not toggle botplay")
	_press(KEY_ENTER)
	_expect_screen("PAUSED")
	_check(conductor.get("paused"), "conductor paused")
	_check(play.process_mode == Node.PROCESS_MODE_DISABLED, "play scene frozen while paused")
	var frozen_ms: float = conductor.get("song_time_ms")
	await _wait_frames(10)
	_check(conductor.get("song_time_ms") == frozen_ms, "song clock frozen while paused")
	_press(KEY_DOWN)
	_press(KEY_DOWN)
	_press(KEY_ENTER)
	_expect_screen("PAUSED")
	_check(play.get("gameplay").botplay, "pause menu toggles botplay on")
	_press(KEY_ESCAPE)
	_expect_screen("PLAY")
	_check(not conductor.get("paused"), "conductor resumed")
	await _wait_frames(10)
	_check(conductor.get("song_time_ms") > frozen_ms, "song clock advances after resume")


func _check_restart_keeps_botplay() -> void:
	var before: Node = _main.call("current_play")
	_press(KEY_ENTER)
	_expect_screen("PAUSED")
	_press(KEY_DOWN)
	_press(KEY_ENTER)
	_expect_screen("PLAY")
	var after: Node = _main.call("current_play")
	_check(after != before, "restart creates a new play scene")
	await _wait_until_playing(after)
	_check(after.get("gameplay").botplay, "restart keeps botplay")
	var player: AudioStreamPlayer = root.get_node("/root/Conductor").get("_player")
	_check(player.playing and not player.stream_paused, "restarted song audio is playing")


func _check_song_end_and_results() -> void:
	var play: Node = _main.call("current_play")
	var conductor := root.get_node("/root/Conductor")
	play.get("gameplay").song_end_ms = conductor.get("song_time_ms") + 500.0
	for frame in FINISH_TIMEOUT_FRAMES:
		if _main.call("screen_name") == "RESULTS":
			break
		await process_frame
	_expect_screen("RESULTS")
	var result: Gameplay = _main.get("last_result")
	_check(result != null and result.botplay, "results receive the finished gameplay")
	_check(not conductor.get("running"), "song audio stopped at results")
	_press(KEY_ENTER)
	_expect_screen("FREEPLAY")
	_press(KEY_ESCAPE)
	_expect_screen("TITLE")


func _check_grades() -> void:
	var results: GDScript = load("res://scenes/menus/ResultsScreen.gd")
	var expected := {0.95: "S", 0.9499: "A", 0.88: "A", 0.75: "B", 0.6: "C", 0.5999: "D", 0.0: "D"}
	for accuracy: float in expected:
		_check(results.grade_for(accuracy) == expected[accuracy], "accuracy %.4f grades %s" % [accuracy, expected[accuracy]])


func _check_empty_content() -> void:
	var content := root.get_node("/root/Content")
	var saved := {}
	for list: String in ["songs", "weeks", "mods"]:
		saved[list] = content.get(list).duplicate()
		content.get(list).clear()
	for screen: String in ["STORY", "FREEPLAY", "MODS"]:
		_main.call("switch_screen", _main.get("Screen")[screen])
		await process_frame
		for key: Key in [KEY_DOWN, KEY_UP, KEY_LEFT, KEY_ENTER]:
			_press(key)
		await process_frame
		_expect_screen(screen)
	for list: String in saved:
		content.get(list).assign(saved[list])
	_press(KEY_ESCAPE)
	_expect_screen("TITLE")


func _wait_until_playing(play: Node) -> void:
	for frame in LOAD_TIMEOUT_FRAMES:
		if play.call("is_playing"):
			return
		await process_frame
	_check(false, "song started within timeout")


func _wait_frames(count: int) -> void:
	for frame in count:
		await process_frame


func _press(key: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.pressed = pressed
		root.push_input(event)


func _expect_screen(expected: String) -> void:
	var actual: String = _main.call("screen_name")
	_check(actual == expected, "screen is %s (got %s)" % [expected, actual])


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: " + message)


func _finish() -> void:
	print("test_menu_flow.gd: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
