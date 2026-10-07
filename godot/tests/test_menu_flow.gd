extends "res://tests/test_base.gd"

## Drives Main with key events: Title -> Freeplay -> song -> chart editor -> pause/botplay/restart -> Results -> back.
const LOAD_TIMEOUT_FRAMES := 600
const FINISH_TIMEOUT_FRAMES := 600

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
	await _check_story_weeks()
	await _check_game_over_retry_and_exit()
	_main.queue_free()
	# Let the audio server release stopped playbacks before quitting.
	await create_timer(0.2).timeout
	super._initialize()


func _check_pause_and_botplay() -> void:
	var play: Node = _main.call("current_play")
	await _wait_until_playing(play)
	var conductor := root.get_node("/root/Conductor")
	await _check_chart_editor(play, conductor)
	_press(KEY_ENTER)
	_expect_screen("PAUSED")
	check(conductor.get("paused"), "conductor paused")
	check(play.process_mode == Node.PROCESS_MODE_DISABLED, "play scene frozen while paused")
	var frozen_ms: float = conductor.get("song_time_ms")
	await _wait_frames(10)
	check(conductor.get("song_time_ms") == frozen_ms, "song clock frozen while paused")
	_press(KEY_DOWN)
	_press(KEY_DOWN)
	_press(KEY_ENTER)
	_expect_screen("PAUSED")
	check(play.get("gameplay").botplay, "pause menu toggles botplay on")
	_press(KEY_ESCAPE)
	_expect_screen("PLAY")
	check(not conductor.get("paused"), "conductor resumed")
	await _wait_frames(10)
	check(conductor.get("song_time_ms") > frozen_ms, "song clock advances after resume")


func _check_chart_editor(play: Node, conductor: Node) -> void:
	var chart: ChartData = play.get("gameplay").chart
	_press(KEY_7)
	_expect_screen("CHART_EDITOR")
	check(conductor.get("paused"), "conductor paused in the editor")
	check(play.process_mode == Node.PROCESS_MODE_DISABLED, "play scene frozen in the editor")
	check(not play.get("gameplay").botplay, "key 7 does not toggle botplay")
	_press(KEY_SPACE)
	var editor: Node = _main.call("current_editor")
	check(editor != null and editor.get("state").dirty, "space adds a note in the editor")
	await process_frame
	_press(KEY_ESCAPE)
	_expect_screen("PLAY")
	check(_main.call("current_editor") == null, "editor closed")
	check(play.get("gameplay").chart == chart, "unsaved edits leave the playing chart alone")
	check(not conductor.get("paused"), "conductor resumed after the editor")
	check(play.process_mode == Node.PROCESS_MODE_INHERIT, "play scene runs after the editor")


func _check_restart_keeps_botplay() -> void:
	var before: Node = _main.call("current_play")
	_press(KEY_ENTER)
	_expect_screen("PAUSED")
	_press(KEY_DOWN)
	_press(KEY_ENTER)
	_expect_screen("PLAY")
	var after: Node = _main.call("current_play")
	check(after != before, "restart creates a new play scene")
	await _wait_until_playing(after)
	check(after.get("gameplay").botplay, "restart keeps botplay")
	var player: AudioStreamPlayer = root.get_node("/root/Conductor").get("_player")
	check(player.playing and not player.stream_paused, "restarted song audio is playing")


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
	check(result != null and result.botplay, "results receive the finished gameplay")
	check(not conductor.get("running"), "song audio stopped at results")
	_press(KEY_ENTER)
	_expect_screen("FREEPLAY")
	_press(KEY_ESCAPE)
	_expect_screen("TITLE")


func _check_grades() -> void:
	var results: GDScript = load("res://scenes/menus/ResultsScreen.gd")
	var expected := {0.95: "S", 0.9499: "A", 0.88: "A", 0.75: "B", 0.6: "C", 0.5999: "D", 0.0: "D"}
	for accuracy: float in expected:
		check(results.grade_for(accuracy) == expected[accuracy], "accuracy %.4f grades %s" % [accuracy, expected[accuracy]])


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
	# With no mods, Enter on the Mods screen opens the import row's choices; the first Escape closes them.
	_press(KEY_ESCAPE)
	_expect_screen("MODS")
	_press(KEY_ESCAPE)
	_expect_screen("TITLE")


## A week whose songs are all missing must not start or crash; the demo week plays.
func _check_story_weeks() -> void:
	var content := root.get_node("/root/Content")
	var weeks: Array = content.get("weeks")
	var demo_listed := false
	for week: WeekMeta in weeks:
		demo_listed = demo_listed or week.id == "demo"
		var installed := false
		for song_id in week.song_ids:
			installed = installed or content.call("find_song", song_id) != null
		check(installed, "listed week %s has an installed song" % week.id)
	check(demo_listed, "the shipped demo week is listed")
	var saved := weeks.duplicate()
	var demo := WeekMeta.from_json({"id": "demo", "name": "Demo Week", "songs": ["neon-steps"]})
	weeks.assign([WeekMeta.from_json({"id": "gone", "name": "Gone", "songs": ["no-such-song"]}), demo])
	_main.call("switch_screen", _main.get("Screen")["STORY"])
	await process_frame
	_press(KEY_ENTER)
	await process_frame
	_expect_screen("STORY")
	_press(KEY_DOWN)
	_press(KEY_ENTER)
	await process_frame
	_expect_screen("PLAY")
	await _wait_until_playing(_main.call("current_play"))
	_press(KEY_ESCAPE)
	await process_frame
	_expect_screen("STORY")
	weeks.assign(saved)
	_press(KEY_ESCAPE)
	await process_frame
	_expect_screen("TITLE")


func _check_game_over_retry_and_exit() -> void:
	_press(KEY_DOWN)
	_press(KEY_ENTER)
	_expect_screen("FREEPLAY")
	await _wait_frames(2)
	_press(KEY_ENTER)
	_expect_screen("PLAY")
	var first_play: Node = _main.call("current_play")
	await _wait_until_playing(first_play)
	var first_song_id: String = first_play.song.id
	var gameplay: Gameplay = first_play.get("gameplay")
	gameplay.botplay = true
	_trigger_game_over(first_play, gameplay)
	await _wait_frames(2)
	_expect_screen("GAME_OVER")
	check(not root.get_node("/root/Conductor").get("running"), "audio stops during game over")
	var game_over_menu: MenuScreen = _main.get("_menu")
	check(game_over_menu.selection == 0, "retry is selected by default")
	check(game_over_menu.row(0).text == "Retry", "first game-over action retries")
	_press(KEY_ENTER)
	_expect_screen("PLAY")
	var retried_play: Node = _main.call("current_play")
	check(retried_play != first_play and retried_play.song.id == first_song_id, "retry creates a fresh play of the same song")
	await _wait_until_playing(retried_play)
	check(retried_play.get("gameplay").botplay, "retry preserves the play mode")
	_trigger_game_over(retried_play, retried_play.get("gameplay"))
	await _wait_frames(2)
	_expect_screen("GAME_OVER")
	_press(KEY_DOWN)
	_press(KEY_ENTER)
	_expect_screen("FREEPLAY")


func _trigger_game_over(play: Node, gameplay: Gameplay) -> void:
	gameplay.health = 0.075
	gameplay.call("_register_miss", "MISS", 0.075, 0)
	play.call("_step", 1.0 / 60.0)
	check(play.call("is_dying"), "zero health starts the death sequence")
	_press(KEY_ENTER)


func _wait_until_playing(play: Node) -> void:
	for frame in LOAD_TIMEOUT_FRAMES:
		if play.call("is_playing"):
			return
		await process_frame
	check(false, "song started within timeout")


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
	check(actual == expected, "screen is %s (got %s)" % [expected, actual])
