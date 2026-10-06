extends "res://tests/test_base.gd"

## Autoload scripts only compile once the autoload globals exist, so they load lazily on the first frame.
const TEMP_DIR := "user://test_lua_tmp"
const TEMP_MOD_ID := "zz-lua-test-mod"
const USER_MODS := "user://mods"
const LOG_PATH := "user://saves/jave.log"

var _host: Node
var _host_script: GDScript
var _ui: GDScript
var _ran := false
var _log_mark := 0


func _initialize() -> void:
	pass


func _process(_delta: float) -> bool:
	if not _ran:
		_ran = true
		_run_async()
	return false


func _run_async() -> void:
	_host = root.get_node("/root/ModHost")
	_host_script = load("res://autoload/ModHost.gd")
	_ui = load("res://scripts/Ui.gd")
	var original_accent: Color = _ui.accent
	_remove_dir(TEMP_DIR)
	_test_lua_state()
	_test_globals()
	_test_argument_errors()
	_test_load_order_and_errors()
	_test_file_header()
	_test_hooks()
	_test_missing_hooks()
	_test_hostile_scripts()
	await _test_update_gate()
	_ui.accent = original_accent
	_host.set("player_flip", false)
	_remove_dir(TEMP_DIR)
	check(not DirAccess.dir_exists_absolute(TEMP_DIR), "temporary directory removed")
	super._initialize()


func _test_lua_state() -> void:
	var lua := LuaState.new()
	lua.open_libraries()
	check(lua.do_string("return 1 + 1") == 2, "LuaState runs Lua code")
	check(lua.do_string("return _VERSION") == "Lua 5.4", "plain Lua 5.4 runtime")
	_host.call("reset")
	_run_script("stdlib.lua", "jave_log(tostring(Vector2 == nil and OS == nil) .. ' ' .. type(io) .. ' ' .. type(utf8) .. ' ' .. type(debug))")
	check(_new_log() == ["true table table table"], "mods get Lua's standard libraries and no Godot globals")


func _test_globals() -> void:
	_host.call("reset")
	var accents: Array[Color] = []
	var on_accent := func(color: Color) -> void: accents.append(color)
	_host.connect("accent_changed", on_accent)
	_run_script("globals.lua", """
jave_log("engine is " .. jave_engine_name())
jave_log(42)
jave_log("types " .. type(jave_log) .. " " .. type(jave_set_accent))
jave_set_accent(300, -5, 128)
""")
	_host.disconnect("accent_changed", on_accent)
	check(_new_log() == ["engine is Jave Engine", "42", "types function function"], "jave_log and jave_engine_name reach the log")
	check(_ui.accent == Color8(255, 0, 128), "jave_set_accent clamps to 0-255 and sets Ui.accent")
	check(accents == [Color8(255, 0, 128)], "accent_changed emitted once with the new colour")
	_run_script("accent_coerce.lua", "jave_set_accent('10', 20.0, 30)")
	check(_ui.accent == Color8(10, 20, 30), "jave_set_accent accepts numeric strings and integral floats")
	for case: Array in [["1", true], ["nil", false], ["false", false], ["0", true], ["", false]]:
		_host.set("player_flip", not case[1])
		_run_script("flip.lua", "jave_set_player_flip(%s)" % case[0])
		check(_host.get("player_flip") == case[1], "jave_set_player_flip(%s) follows lua_toboolean" % case[0])


func _test_argument_errors() -> void:
	_host.call("reset")
	var path := _run_script("bad_args.lua", "\njave_set_accent(1, 2)")
	check(_new_log() == ["Lua error in %s: %s:2: bad argument #3 to 'jave_set_accent' (number expected, got no value)" % [path, path]],
		"missing accent argument raises the C API error at the caller's line")
	path = _run_script("bad_float.lua", "jave_set_accent(1.5, 0, 0)")
	check(_new_log() == ["Lua error in %s: %s:1: bad argument #1 to 'jave_set_accent' (number has no integer representation)" % [path, path]],
		"fractional accent raises the integer representation error")
	path = _run_script("bad_log.lua", "jave_log({})")
	check(_new_log() == ["Lua error in %s: %s:1: bad argument #1 to 'jave_log' (string expected, got table)" % [path, path]],
		"jave_log rejects tables")


func _test_load_order_and_errors() -> void:
	var content_root := TEMP_DIR.path_join("content")
	var scripts := content_root.path_join("scripts")
	_write(scripts.path_join("b.lua"), "jave_log('root b')")
	_write(scripts.path_join("boot.lua"), "jave_log('root boot')")
	_write(scripts.path_join("a.lua"), "error('boom')")
	_write(scripts.path_join("notes.txt"), "error('not lua')")
	_write(scripts.path_join("c.lua"), "local x = ")
	var created_user_mods := not DirAccess.dir_exists_absolute(USER_MODS)
	var mod_root := USER_MODS.path_join(TEMP_MOD_ID)
	_write(mod_root.path_join("mod.json"), JSON.stringify({"id": TEMP_MOD_ID, "name": "ZZ Lua Test", "enabled": true}))
	_write(mod_root.path_join("scripts/z.lua"), "jave_log('mod z')")
	_write(mod_root.path_join("scripts/a.lua"), "jave_log('mod a')")
	var content := root.get_node("/root/Content")
	# The player's saved mod toggles must not decide which mods this test sees.
	var saved_overrides: String = content.get("mod_overrides_path")
	content.set("mod_overrides_path", TEMP_DIR.path_join("mods.json"))
	content.call("scan")
	var paths: PackedStringArray = _host_script.script_paths(content_root, _host.call("enabled_mod_roots"))
	var user_mod_scripts := mod_root.path_join("scripts")
	var expected := PackedStringArray([
		scripts.path_join("boot.lua"), scripts.path_join("a.lua"), scripts.path_join("b.lua"), scripts.path_join("c.lua"),
		"res://content/mods/example-mod/scripts/hello.lua",
		user_mod_scripts.path_join("a.lua"), user_mod_scripts.path_join("z.lua"),
	])
	check(paths == expected, "boot first, root scripts sorted, then res:// and user:// mod scripts sorted (got %s)" % [paths])
	_host.call("reset")
	_mark_log()
	_host.call("load_scripts", paths)
	var a_path := scripts.path_join("a.lua")
	var c_path := scripts.path_join("c.lua")
	check(_new_log() == [
		"root boot",
		"Lua error in %s: %s:1: boom" % [a_path, a_path],
		"root b",
		"Lua error in %s: %s:1: unexpected symbol near <eof>" % [c_path, c_path],
		"Example Mod script loaded",
		"mod a",
		"mod z",
	], "scripts run in order and errors are logged without stopping later scripts")
	check(_host_script._path_before("a/x.lua", "a-b/x.lua"), "paths compare by component like std::filesystem")
	_remove_dir(mod_root)
	if created_user_mods:
		DirAccess.remove_absolute(USER_MODS)
	content.set("mod_overrides_path", saved_overrides)
	content.call("scan")


func _test_file_header() -> void:
	_host.call("reset")
	var path := TEMP_DIR.path_join("header.lua")
	var bytes := PackedByteArray([0xEF, 0xBB, 0xBF])
	bytes.append_array("#!/usr/bin/env lua\nerror('second line')".to_utf8_buffer())
	_write_bytes(path, bytes)
	_mark_log()
	_host.call("load_scripts", PackedStringArray([path]))
	check(_new_log() == ["Lua error in %s: %s:2: second line" % [path, path]], "BOM and # line skipped, line numbers kept")


func _test_hooks() -> void:
	_host.call("reset")
	var path := _run_script("hooks.lua", """
function on_update(dt) jave_log("update " .. math.type(dt) .. " " .. dt) end
function jave_core_song_start(id) jave_log("core " .. id) end
function on_song_start(id) jave_log("song " .. id) end
function on_note_hit(lane, rating)
  if rating == "bad" then error("bad hook") end
  jave_log("hit " .. math.type(lane) .. " " .. lane .. " " .. rating)
end
""")
	_new_log()
	_host.call("update", 0.25)
	_host.call("song_start", "neon-steps")
	_host.call("note_hit", 2, "miss")
	_host.call("note_hit", 0, "bad")
	check(_new_log() == [
		"update float 0.05",
		"core neon-steps",
		"song neon-steps",
		"hit integer 2 miss",
		"Lua callback error in on_note_hit: %s:6: bad hook" % path,
	], "hooks receive the C API argument types, dt clamped to 0.05 s, and callback errors are logged")


func _test_missing_hooks() -> void:
	_host.call("reset")
	_run_script("not_functions.lua", "on_update = 5")
	_host.call("update", 0.1)
	_host.call("song_start", "neon-steps")
	_host.call("note_hit", 1, "sick")
	check(_new_log().is_empty(), "missing or non-function hooks are no-ops")


func _test_hostile_scripts() -> void:
	_host.call("reset")
	var path := _run_script("hostile.lua", """
function on_update() on_update = 7; error(42) end
function on_song_start() error({}) end
function on_note_hit() jave_log = nil; string.format = nil; jave_set_accent(1, 2) end
""")
	_host.call("update", 0.01)
	_host.call("update", 0.01)
	_host.call("song_start", "neon-steps")
	_host.call("note_hit", 0, "sick")
	check(_new_log() == [
		"Lua callback error in on_update: 42",
		"Lua callback error in on_song_start: unknown error",
		"Lua callback error in on_note_hit: %s:4: bad argument #3 to 'jave_set_accent' (number expected, got no value)" % path,
	], "non-string errors, runtime hook reassignment and clobbered globals are handled like lua_pcall")
	_run_script("raising_globals.lua", "on_update = nil; setmetatable(_G, {__index = function(_, key) error('no ' .. key, 0) end})")
	_host.call("update", 0.01)
	check(_new_log() == ["Lua callback error in on_update: no on_update"], "a raising _G lookup is logged, not fatal")
	_host.call("reset")
	_run_script("ünïcödé-脚本.lua", "jave_log('héllo ' .. debug.getinfo(1, 'S').short_src:match('[^/]+$'))")
	check(_new_log() == ["héllo ünïcödé-脚本.lua"], "unicode paths load and keep their chunk name")
	var bare_mod := TEMP_DIR.path_join("bare-mod")
	DirAccess.make_dir_recursive_absolute(bare_mod)
	check(_host_script.script_paths(TEMP_DIR.path_join("missing"), PackedStringArray([bare_mod])).is_empty(),
		"missing content scripts dir and a mod without scripts give no paths")


func _test_update_gate() -> void:
	_host.call("reset")
	_run_script("ticks.lua", "function on_update(dt) jave_log('tick') end")
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	_new_log()
	var expectations := {"TITLE": 1, "PAUSED": 0, "CHART_EDITOR": 0, "CUTSCENE": 0, "RESULTS": 1}
	for screen_name: String in expectations:
		main.set("screen", main.get("Screen")[screen_name])
		main.call("_process", 0.016)
		check(_new_log().size() == expectations[screen_name], "on_update gate on %s" % screen_name)
	main.queue_free()
	await process_frame


func _run_script(file_name: String, source: String) -> String:
	var path := TEMP_DIR.path_join(file_name)
	_write(path, source)
	_mark_log()
	_host.call("load_scripts", PackedStringArray([path]))
	return path


func _mark_log() -> void:
	_log_mark = FileAccess.get_file_as_bytes(LOG_PATH).size()


func _new_log() -> Array[String]:
	var bytes := FileAccess.get_file_as_bytes(LOG_PATH)
	var lines: Array[String] = []
	for line in bytes.slice(_log_mark).get_string_from_utf8().split("\n", false):
		lines.append(line)
	_log_mark = bytes.size()
	return lines


func _write(path: String, text: String) -> void:
	_write_bytes(path, text.to_utf8_buffer())


func _write_bytes(path: String, bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()


func _remove_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for directory in DirAccess.get_directories_at(path):
		_remove_dir(path.path_join(directory))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
