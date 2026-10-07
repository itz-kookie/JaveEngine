extends "res://tests/test_base.gd"

## Cutscene manifest parsing and the story flow around before/after videos.
## Headless builds cannot rely on a decodable video, so most flows use a corrupt .ogv that opens but never starts.
const USER_CONTENT := TEST_HOME + "/content/"
const MANIFEST_MIRROR := USER_CONTENT + "mods/jave-demo/data/cutscenes.json"
const VIDEO_DIR := USER_CONTENT + "mods/jave-demo/test-cutscenes"
const CORRUPT_VIDEO := "test-cutscenes/corrupt.ogv"
const REAL_VIDEO := "test-cutscenes/real.ogv"
const FINISH_TIMEOUT_FRAMES := 600
const MOD_ROOT := TEST_HOME + "/mods/zz-cutscene-test-mod"
const MOD_SONG := "zz-cutscene-mod-song"

var _main: Node


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	_check_manifest_parsing()
	DirAccess.make_dir_recursive_absolute(VIDEO_DIR)
	_write(VIDEO_DIR.path_join("corrupt.ogv"), "not a theora stream")
	_write(VIDEO_DIR.path_join("empty.ogv"), "")
	_check_content_paths()
	_check_mod_manifests()
	_main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(_main)
	await process_frame
	var song: SongMeta = root.get_node("/root/Content").call("find_song", _week().song_ids[0])
	await _check_missing_video_starts_song(song)
	await _check_empty_video_starts_song(song)
	await _check_skip_keys(song)
	await _check_cancel(song)
	await _check_timeout(song)
	await _check_ended_and_failed(song)
	await _check_freeplay_has_no_cutscene(song)
	await _check_outro(song)
	await _check_real_video(song)
	_main.queue_free()
	await create_timer(0.2).timeout
	super._initialize()


func _check_manifest_parsing() -> void:
	var manifest := {"a": {"before": "videos/a.ogv", "after": "videos/a-end.ogv"}, "b": {"before": 3}, "c": "x"}
	check(CutsceneManifest.relative_path(manifest, "a", false) == "videos/a.ogv", "before path read")
	check(CutsceneManifest.relative_path(manifest, "a", true) == "videos/a-end.ogv", "after path read")
	check(CutsceneManifest.relative_path(manifest, "b", false) == "", "non-string path ignored")
	check(CutsceneManifest.relative_path(manifest, "b", true) == "", "missing side ignored")
	check(CutsceneManifest.relative_path(manifest, "c", false) == "", "non-object entry ignored")
	check(CutsceneManifest.relative_path(manifest, "zzz", false) == "", "unknown song ignored")
	check(CutsceneManifest.relative_path(null, "a", false) == "", "missing manifest ignored")
	for safe: String in ["videos/a.ogv", "a.ogv", "videos/..hidden/a.ogv"]:
		check(CutsceneManifest.rejection(safe).is_empty(), "accepts " + safe)
	for unsafe: String in ["../a.ogv", "videos/../../a.ogv", "videos\\..\\..\\a.ogv", "/etc/a.ogv", "\\a.ogv",
			"C:\\a.ogv", "C:a.ogv", "user://a.ogv", "res://a.ogv"]:
		check(not CutsceneManifest.rejection(unsafe).is_empty(), "rejects " + unsafe)


func _check_content_paths() -> void:
	var content := root.get_node("/root/Content")
	_write_manifest({
		"s1": {"before": CORRUPT_VIDEO, "after": "videos/shipped.ogv"},
		"s2": {"before": "../outside.ogv", "after": "/abs.ogv"},
		"s3": {"before": ""},
	})
	content.call("scan")
	check(content.call("cutscene_path", "s1", false) == USER_CONTENT + "mods/jave-demo/" + CORRUPT_VIDEO, "relative video resolves against the mod package")
	check(content.call("cutscene_path", "s1", true) == "res://content/mods/jave-demo/videos/shipped.ogv", "relative outro resolves against the mod package")
	check(content.call("cutscene_path", "s2", false) == "", "traversal rejected")
	check(content.call("cutscene_path", "s2", true) == "", "absolute path rejected")
	check(content.call("cutscene_path", "s3", false) == "", "empty path has no cutscene")
	check(content.call("cutscene_path", "s4", false) == "", "song without entry has no cutscene")


## A mod's data/cutscenes.json resolves against the mod; the song's own package is asked first, then other mods.
func _check_mod_manifests() -> void:
	var content := root.get_node("/root/Content")
	_write_manifest({})
	_write_mod()
	_write_manifest({
		MOD_SONG: {"before": "videos/root-before.ogv", "after": "videos/root-after.ogv"},
		"s1": {"before": CORRUPT_VIDEO},
		"neon-steps": {},
	})
	content.call("scan")
	var song: SongMeta = content.call("find_song", MOD_SONG)
	check(song != null and song.package_root == MOD_ROOT, "mod song is scanned with its package root")
	check(content.call("cutscene_path", MOD_SONG, false) == MOD_ROOT.path_join("videos/intro.ogv"), "a mod song uses its own manifest first, resolved against the mod")
	check(content.call("cutscene_path", MOD_SONG, true) == "", "traversal in a mod manifest is rejected")
	check(content.call("cutscene_path", "zz-only-in-mod", false) == MOD_ROOT.path_join("videos/only.ogv"), "other enabled mods are searched for a cutscene")
	check(content.call("cutscene_path", "neon-steps", true) == MOD_ROOT.path_join("videos/neon-after.ogv"), "another mod can supply a song's cutscene")
	check(content.call("cutscene_path", "zz-absolute", false) == "", "absolute path in a mod manifest is rejected")
	for mod: ModInfo in content.get("mods"):
		if mod.root == MOD_ROOT:
			mod.enabled = false
	check(content.call("cutscene_path", "zz-only-in-mod", false) == "", "a disabled mod's manifest is ignored")
	ModPackImporter.remove_tree(MOD_ROOT)
	content.call("scan")
	check(content.call("find_song", MOD_SONG) == null, "temporary mod removed")


func _write_mod() -> void:
	DirAccess.make_dir_recursive_absolute(MOD_ROOT.path_join("songs").path_join(MOD_SONG))
	DirAccess.make_dir_recursive_absolute(MOD_ROOT.path_join("data/charts"))
	_write(MOD_ROOT.path_join("mod.json"), JSON.stringify({"id": "zz-cutscene-test-mod", "name": "ZZ Cutscene Test"}))
	_write(MOD_ROOT.path_join("songs").path_join(MOD_SONG).path_join("song.json"),
		JSON.stringify({"id": MOD_SONG, "title": "ZZ", "chart": "data/charts/zz.json", "bpm": 120}))
	_write(MOD_ROOT.path_join("data/charts/zz.json"), FileAccess.get_file_as_string("res://content/mods/jave-demo/data/charts/neon-steps.json"))
	_write(MOD_ROOT.path_join("data/cutscenes.json"), JSON.stringify({
		MOD_SONG: {"before": "videos/intro.ogv", "after": "../escape.ogv"},
		"s1": {"before": "videos/mod-s1.ogv"},
		"zz-only-in-mod": {"before": "videos/only.ogv"},
		"neon-steps": {"after": "videos/neon-after.ogv"},
		"zz-absolute": {"before": "/etc/x.ogv"},
	}))


func _check_missing_video_starts_song(song: SongMeta) -> void:
	_write_manifest({song.id: {"before": "test-cutscenes/missing.ogv"}})
	_main.call("start_week", _week())
	_expect_screen("PLAY")
	check(_main.call("current_cutscene") == null, "missing video opens no cutscene")


func _check_empty_video_starts_song(song: SongMeta) -> void:
	_write_manifest({song.id: {"before": "test-cutscenes/empty.ogv"}})
	_main.call("start_week", _week())
	var cutscene: Node = _main.call("current_cutscene")
	if cutscene != null:
		cutscene.set("start_timeout_s", 0.05)
	await _wait_for_screen("PLAY")
	check(_main.call("current_play").get("song") == song, "zero-byte video falls through to the song")


func _check_skip_keys(song: SongMeta) -> void:
	_write_manifest({song.id: {"before": CORRUPT_VIDEO}})
	var settings := root.get_node("/root/Settings")
	var first_lane: Key = settings.call("lane_key", 0)
	var second_lane: Key = settings.call("lane_key", 1)
	for key: Key in [KEY_ENTER, KEY_SPACE, KEY_KP_ENTER]:
		await _open_before_cutscene(song)
		_press(first_lane)
		_hold(second_lane)
		var lane_input := root.get_node("/root/LaneInput")
		check(lane_input.call("has_press"), "lane press recorded during cutscene")
		var cutscene: Node = _main.call("current_cutscene")
		_press(key)
		cutscene.call("_finish", &"timeout")
		await process_frame
		await process_frame
		_expect_screen("PLAY")
		check(_main.call("current_play").get("song") == song, "skip with %s starts the song" % OS.get_keycode_string(key))
		check(not lane_input.call("has_press") and lane_input.get("held_mask") == 0, "cutscene input discarded")
		_release(second_lane)
	_press(KEY_ESCAPE)
	_expect_screen("STORY")
	check(not _main.get("playing_story"), "Esc during the song after a cutscene leaves story mode")


func _check_cancel(song: SongMeta) -> void:
	await _open_before_cutscene(song)
	_press(KEY_ESCAPE)
	await process_frame
	_expect_screen("STORY")
	check(not _main.get("playing_story") and _main.get("story_queue").is_empty(), "cancel ends story mode")
	check(_main.call("current_cutscene") == null and _main.call("current_play") == null, "cancel closes the cutscene")


func _check_timeout(song: SongMeta) -> void:
	await _open_before_cutscene(song)
	var cutscene: Node = _main.call("current_cutscene")
	cutscene.set("start_timeout_s", 0.05)
	await _wait_for_screen("PLAY")
	_expect_screen("PLAY")


func _check_ended_and_failed(song: SongMeta) -> void:
	await _open_before_cutscene(song)
	_main.call("current_cutscene").call("_on_player_finished")
	await process_frame
	_expect_screen("PLAY")
	await _open_before_cutscene(song)
	var player: VideoStreamPlayer = _main.call("current_cutscene").get_node("Frame/Player")
	player.stop()
	await _wait_for_screen("PLAY")
	_expect_screen("PLAY")


func _check_freeplay_has_no_cutscene(song: SongMeta) -> void:
	_main.call("_on_freeplay_song", song)
	_expect_screen("PLAY")


func _check_outro(song: SongMeta) -> void:
	_write_manifest({song.id: {"after": CORRUPT_VIDEO}})
	_main.call("start_week", _week())
	_expect_screen("PLAY")
	await _finish_current_song()
	_expect_screen("CUTSCENE")
	check(_main.get("last_result") != null, "result kept for after the outro")
	check(not root.get_node("/root/Conductor").get("running"), "song audio stopped during outro")
	_press(KEY_ENTER)
	await process_frame
	_expect_screen("RESULTS")
	_write_manifest({song.id: {"after": "test-cutscenes/missing.ogv"}})
	_main.call("start_week", _week())
	await _finish_current_song()
	_expect_screen("RESULTS")
	_main.call("switch_screen", _main.get("Screen")["TITLE"])


func _check_real_video(song: SongMeta) -> void:
	var output: Array = []
	var target := ProjectSettings.globalize_path(VIDEO_DIR.path_join("real.ogv"))
	var exit := OS.execute("ffmpeg", ["-hide_banner", "-loglevel", "error", "-y", "-f", "lavfi", "-i",
		"testsrc=duration=1:size=160x90:rate=15", "-c:v", "libtheora", "-q:v", "7", target], output, true)
	if exit != 0:
		print("SKIP: real .ogv playback (ffmpeg with libtheora unavailable)")
		return
	_write_manifest({song.id: {"before": REAL_VIDEO}})
	await _open_before_cutscene(song)
	await _wait_for_screen("PLAY")
	_expect_screen("PLAY")


func _open_before_cutscene(song: SongMeta) -> void:
	_main.call("start_week", _week())
	_expect_screen("CUTSCENE")
	check(_main.call("current_play") == null, "song waits for the cutscene")
	check(not root.get_node("/root/Conductor").get("running"), "no song audio during cutscene")
	check(_main.get("_cutscene_song") == song, "cutscene remembers its song")
	await process_frame


func _finish_current_song() -> void:
	var play: Node = _main.call("current_play")
	for frame in FINISH_TIMEOUT_FRAMES:
		if play.call("is_playing"):
			break
		await process_frame
	play.get("gameplay").botplay = true
	play.get("gameplay").song_end_ms = root.get_node("/root/Conductor").get("song_time_ms") + 100.0
	for frame in FINISH_TIMEOUT_FRAMES:
		if _main.call("current_play") != play:
			break
		await process_frame


func _wait_for_screen(expected: String) -> void:
	for frame in FINISH_TIMEOUT_FRAMES:
		if _main.call("screen_name") == expected:
			return
		await process_frame


func _week() -> WeekMeta:
	return root.get_node("/root/Content").get("weeks")[0]


func _write_manifest(manifest: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(MANIFEST_MIRROR.get_base_dir())
	_write(MANIFEST_MIRROR, JSON.stringify(manifest))


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _press(key: Key) -> void:
	_hold(key)
	_release(key)


func _hold(key: Key) -> void:
	_key_event(key, true)


func _release(key: Key) -> void:
	_key_event(key, false)


func _key_event(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.pressed = pressed
	root.push_input(event)


func _expect_screen(expected: String) -> void:
	var actual: String = _main.call("screen_name")
	check(actual == expected, "screen is %s (got %s)" % [expected, actual])
