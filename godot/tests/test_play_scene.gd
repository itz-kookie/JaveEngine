extends "res://tests/test_base.gd"

## Plays Neon Steps under botplay in real time (about 26 s) and checks the expected botplay score.
const TIMEOUT_SECONDS := 45.0
const EXPECTED_SCORE := 350 * 64 + 100 * 4

var _elapsed := 0.0
var _result: Gameplay
var _error := ""
var _started := false


## The song is started from the first frame; quitting is left to _process.
func _initialize() -> void:
	pass


func _start() -> void:
	_started = true
	var content: Node = root.get_node("/root/Content")
	var play: Node = load("res://scenes/play/PlayScene.tscn").instantiate()
	play.set("song", content.call("find_song", "neon-steps"))
	play.set("botplay", true)
	play.connect("finished", func(result: Gameplay) -> void: _result = result)
	play.connect("failed", func(message: String) -> void: _error = message)
	root.add_child(play)


func _process(delta: float) -> bool:
	if not _started:
		_start()
		return false
	_elapsed += delta
	if _result == null and _error.is_empty() and _elapsed < TIMEOUT_SECONDS:
		return false
	var passed := _error.is_empty() and _result != null and _result.score == EXPECTED_SCORE \
		and _result.sick_count == 64 and _result.max_combo == 64 and _result.misses == 0
	if passed:
		print("test_play_scene.gd: botplay score %d, 64 sick, max combo 64" % _result.score)
	elif _result != null:
		printerr("FAIL: score %d sick %d maxCombo %d misses %d" % [_result.score, _result.sick_count, _result.max_combo, _result.misses])
	else:
		printerr("FAIL: song did not finish: " + (_error if not _error.is_empty() else "timeout"))
	quit(0 if passed else 1)
	return false
