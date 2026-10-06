extends Node

signal accent_changed(color: Color)

const ENGINE_NAME := "Jave Engine"
## Upper bound on the dt passed to on_update, so a long frame cannot jump scripts ahead.
const MAX_UPDATE_SECONDS := 0.05

## Defines the jave_* globals as Lua functions so mods see the same types and the same
## argument errors as luaL_checkstring/luaL_checkinteger/lua_toboolean give in the Lua C API.
## Returns the function that runs chunks and hooks under pcall, giving lua_pcall's error text.
const PRELUDE := """
local host = ...
local G = _ENV
local error, pcall, select, type = error, pcall, select, type
local format, tointeger, tonumber, tostring = string.format, math.tointeger, tonumber, tostring

local function type_error(name, index, expected, count, value)
  local got = index > count and "no value" or type(value)
  return format("bad argument #%d to '%s' (%s expected, got %s)", index, name, expected, got)
end

local function check_string(name, index, count, value)
  local kind = type(value)
  if kind == "string" or kind == "number" then return tostring(value) end
  error(type_error(name, index, "string", count, value), 3)
end

local function check_integer(name, index, count, value)
  local kind = type(value)
  local number = (kind == "number" or kind == "string") and tonumber(value) or nil
  if number == nil then error(type_error(name, index, "number", count, value), 3) end
  local integer = tointeger(number)
  if integer == nil then
    error(format("bad argument #%d to '%s' (number has no integer representation)", index, name), 3)
  end
  return integer
end

function jave_log(...)
  host.log(check_string("jave_log", 1, select("#", ...), (...)))
end

function jave_engine_name()
  return host.engine_name
end

function jave_set_accent(...)
  local count = select("#", ...)
  local r, g, b = ...
  r = check_integer("jave_set_accent", 1, count, r)
  g = check_integer("jave_set_accent", 2, count, g)
  b = check_integer("jave_set_accent", 3, count, b)
  host.set_accent(r, g, b)
end

function jave_set_player_flip(flip)
  host.set_player_flip(flip ~= nil and flip ~= false)
end

local function protected(fn, ...)
  local ok, message = pcall(fn, ...)
  if ok then return nil end
  local kind = type(message)
  return (kind == "string" or kind == "number") and tostring(message) or "unknown error"
end

return function(chunk_or_hook, ...)
  if type(chunk_or_hook) == "function" then return protected(chunk_or_hook) end
  local hook = G[chunk_or_hook]
  if type(hook) ~= "function" then return nil end
  return protected(hook, ...)
end
"""

## Read by the player Character; reset at every song start before the Lua hooks run.
var player_flip := false

var _lua: LuaState
## Takes a loaded chunk or a global hook name plus its arguments; returns null or the error text.
var _call: LuaFunction
var _update_args: Array = ["on_update", 0.0]


func _ready() -> void:
	reset()
	load_scripts(script_paths(Paths.CONTENT_ROOT, enabled_mod_roots()))


func reset() -> void:
	_lua = LuaState.new()
	# Only Lua's standard libraries; the Godot APIs would replace print and add globals.
	_lua.open_libraries(LuaState.LUA_ALL_LIBS)
	var host := _lua.create_table({
		"engine_name": ENGINE_NAME,
		"log": _lua.create_function(_host_log),
		"set_accent": _lua.create_function(_host_set_accent),
		"set_player_flip": _lua.create_function(_host_set_player_flip),
	})
	_call = (_lua.load_string(PRELUDE, "=jave") as LuaFunction).invoke(host)


func enabled_mod_roots() -> PackedStringArray:
	var roots := PackedStringArray()
	for mod in Content.mods:
		if mod.enabled:
			roots.append(mod.root)
	return roots


## boot.lua first, then the other root scripts sorted, then every mod script sorted as one list.
static func script_paths(content_root: String, mod_roots: PackedStringArray) -> PackedStringArray:
	var scripts_dir := content_root.path_join("scripts")
	var boot := scripts_dir.path_join("boot.lua")
	var paths := PackedStringArray()
	if FileAccess.file_exists(boot):
		paths.append(boot)
	var root_scripts := _lua_files_in(scripts_dir)
	root_scripts.erase(boot)
	paths.append_array(_sorted_paths(root_scripts))
	var mod_scripts := PackedStringArray()
	for mod_root in mod_roots:
		mod_scripts.append_array(_lua_files_in(mod_root.path_join("scripts")))
	paths.append_array(_sorted_paths(mod_scripts))
	return paths


func load_scripts(paths: PackedStringArray) -> void:
	for path in paths:
		var error: Variant = _run_file(path)
		if error != null:
			Log.info("Lua error in %s: %s" % [path, _error_text(error)])


func update(dt: float) -> void:
	_update_args[1] = clampf(dt, 0.0, MAX_UPDATE_SECONDS)
	_call_hook(_update_args)


func song_start(song_id: String) -> void:
	_call_hook(["jave_core_song_start", song_id])
	_call_hook(["on_song_start", song_id])


func note_hit(lane: int, rating: String) -> void:
	_call_hook(["on_note_hit", lane, rating])


## Returns null on success, otherwise the error as a String or LuaError.
func _run_file(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return "cannot open " + path
	var chunk: Variant = _lua.load_buffer(_skip_header(file.get_buffer(file.get_length())), "@" + path)
	return _call.invoke(chunk) if chunk is LuaFunction else chunk


## args starts with the hook's global name.
func _call_hook(args: Array) -> void:
	var error: Variant = _call.invokev(args)
	if error != null:
		Log.info("Lua callback error in %s: %s" % [args[0], _error_text(error)])


func _host_log(message: String) -> void:
	Log.info(message)


func _host_set_accent(r: int, g: int, b: int) -> void:
	Ui.accent = Color8(clampi(r, 0, 255), clampi(g, 0, 255), clampi(b, 0, 255))
	accent_changed.emit(Ui.accent)


func _host_set_player_flip(flip: bool) -> void:
	player_flip = flip


## A LuaError comes from a failed load or from an error the dispatcher could not catch (a raising
## __index on _G); the traceback the addon appends to it is dropped so the log keeps one line per error.
static func _error_text(error: Variant) -> String:
	if not error is LuaError:
		return str(error)
	var message := (error as LuaError).message
	var traceback := message.find("\nstack traceback:")
	message = message.substr(0, traceback) if traceback >= 0 else message
	return message if not message.is_empty() else "unknown error"


## Mirrors luaL_loadfile: drops a UTF-8 BOM and a leading '#' line, keeping its newline so line numbers hold.
static func _skip_header(chunk: PackedByteArray) -> PackedByteArray:
	if chunk.size() >= 3 and chunk[0] == 0xEF and chunk[1] == 0xBB and chunk[2] == 0xBF:
		chunk = chunk.slice(3)
	if not chunk.is_empty() and chunk[0] == 0x23:
		var newline := chunk.find(0x0A)
		chunk = chunk.slice(newline) if newline >= 0 else PackedByteArray()
	return chunk


static func _lua_files_in(directory: String) -> PackedStringArray:
	var files := PackedStringArray()
	if not DirAccess.dir_exists_absolute(directory):
		return files
	for file in DirAccess.get_files_at(directory):
		if file.get_extension() == "lua":
			files.append(directory.path_join(file))
	return files


## Compares path components like std::filesystem::path, so "a/x" sorts before "a-b/x".
static func _sorted_paths(paths: PackedStringArray) -> PackedStringArray:
	var sorted := Array(paths)
	sorted.sort_custom(func(a: String, b: String) -> bool: return _path_before(a, b))
	return PackedStringArray(sorted)


static func _path_before(a: String, b: String) -> bool:
	var left := a.split("/")
	var right := b.split("/")
	for index in mini(left.size(), right.size()):
		if left[index] != right[index]:
			return left[index] < right[index]
	return left.size() < right.size()
