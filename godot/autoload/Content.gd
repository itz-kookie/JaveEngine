extends Node

const CUTSCENE_MANIFEST := "data/cutscenes.json"
const WEEKS_FILE := "data/weeks.json"
## Written by tools/import_psych_library.py and kept out of git; its weeks list before the shipped ones.
const IMPORTED_WEEKS_FILE := "data/weeks.imported.json"

var songs: Array[SongMeta] = []
var weeks: Array[WeekMeta] = []
var mods: Array[ModInfo] = []
var mod_roots := PackedStringArray([Paths.content("mods"), Paths.user("mods")])
var mod_overrides_path := Paths.user("config/mods.json")


func _ready() -> void:
	scan()


func scan() -> void:
	songs.clear()
	weeks.clear()
	mods.clear()
	for mod_root in mod_roots:
		_scan_mods(mod_root)
	mods.sort_custom(_mod_before)
	ModOverrides.apply(mods, ModOverrides.load_file(mod_overrides_path))
	for package_root in _enabled_package_roots():
		_scan_songs(package_root)
	songs.sort_custom(_song_before)
	var has_song := func(id: String) -> bool: return find_song(id) != null
	for package_root in _enabled_package_roots():
		var lists: Array[Array] = [_read_weeks(package_root.path_join(WEEKS_FILE))]
		if package_root == Paths.CONTENT_ROOT:
			lists.push_front(_read_weeks(package_root.path_join(IMPORTED_WEEKS_FILE)))
		weeks.append_array(playable_weeks(lists, has_song))


## Flips a mod's enabled state, persists it, and rescans so its songs and weeks appear or vanish.
func toggle_mod(index: int) -> void:
	if index < 0 or index >= mods.size():
		return
	var mod := mods[index]
	mod.enabled = not mod.enabled
	var overrides := ModOverrides.load_file(mod_overrides_path)
	overrides[mod.id] = mod.enabled
	if not ModOverrides.save_file(mod_overrides_path, overrides):
		Log.info("Could not save mod state: " + mod_overrides_path)
	Log.info("Mod %s %s" % [mod.id, "enabled" if mod.enabled else "disabled"])
	scan()


func find_song(id: String) -> SongMeta:
	for song in songs:
		if song.id == id:
			return song
	return null


func reload_stage(song: SongMeta) -> void:
	var stage: Variant = JsonRead.load_file(song.stage_config_path)
	if stage is Dictionary:
		song.apply_stage(stage)


func load_chart(song: SongMeta) -> ChartData:
	return ChartData.load_file(chart_path_for(song), song.id, song.bpm)


## A chart saved from the editor over shipped content wins over the original.
func chart_path_for(song: SongMeta) -> String:
	return _prefer_user_mirror(song.chart_path)


## Empty when the song has no cutscene on that side or the manifest entry is rejected.
func cutscene_path(song_id: String, outro: bool) -> String:
	var manifest: Variant = JsonRead.load_file(_prefer_user_mirror(Paths.content(CUTSCENE_MANIFEST)))
	var relative := CutsceneManifest.relative_path(manifest, song_id, outro)
	if relative.is_empty():
		return ""
	var error := CutsceneManifest.rejection(relative)
	if not error.is_empty():
		Log.info("Cutscene manifest error: " + error)
		return ""
	return _prefer_user_mirror(Paths.content(relative))


func load_audio(song_path: String) -> AudioStream:
	var path := preferred_audio(song_path)
	if not FileAccess.file_exists(path):
		return null
	match path.get_extension().to_lower():
		"wav":
			return WavFile.load_stream(path)
		"ogg":
			return AudioStreamOggVorbis.load_from_file(path)
		"mp3":
			return AudioStreamMP3.load_from_file(path)
	return null


## A manifest that names a .wav plays the sibling .ogg written by tools/convert_audio.py when one exists.
static func preferred_audio(path: String) -> String:
	if path.get_extension().to_lower() != "wav":
		return path
	var ogg := path.get_basename() + ".ogg"
	return ogg if FileAccess.file_exists(ogg) else path


func _prefer_user_mirror(path: String) -> String:
	var override := Paths.user_mirror(path)
	return override if FileAccess.file_exists(override) else path


func _enabled_package_roots() -> PackedStringArray:
	var roots := PackedStringArray([Paths.CONTENT_ROOT])
	for mod in mods:
		if mod.enabled:
			roots.append(mod.root)
	return roots


func _scan_mods(mod_root: String) -> void:
	for folder in _directories_at(mod_root):
		var root := mod_root.path_join(folder)
		var manifest: Variant = JsonRead.load_file(root.path_join("mod.json"))
		if manifest is Dictionary:
			mods.append(ModInfo.from_json(manifest, root))


func _scan_songs(package_root: String) -> void:
	var song_root := package_root.path_join("songs")
	for folder in _directories_at(song_root):
		var manifest: Variant = JsonRead.load_file(song_root.path_join(folder).path_join("song.json"))
		if not manifest is Dictionary:
			continue
		var song := SongMeta.from_json(manifest, package_root, folder)
		reload_stage(song)
		if not song.id.is_empty() and FileAccess.file_exists(song.chart_path):
			songs.append(song)


## Weeks from each list in order, skipping ids already taken and weeks with none of their songs installed.
static func playable_weeks(lists: Array[Array], has_song: Callable) -> Array[WeekMeta]:
	var result: Array[WeekMeta] = []
	var taken: Dictionary[String, bool] = {}
	for list in lists:
		for week: WeekMeta in list:
			if taken.has(week.id) or not Array(week.song_ids).any(has_song):
				continue
			taken[week.id] = true
			result.append(week)
	return result


static func _read_weeks(path: String) -> Array[WeekMeta]:
	var result: Array[WeekMeta] = []
	var json: Variant = JsonRead.load_file(path)
	for item: Variant in JsonRead.array(json, "weeks"):
		if not item is Dictionary:
			continue
		var week := WeekMeta.from_json(item)
		if not week.id.is_empty() and not week.song_ids.is_empty():
			result.append(week)
	return result


static func _directories_at(path: String) -> PackedStringArray:
	return DirAccess.get_directories_at(path) if DirAccess.dir_exists_absolute(path) else PackedStringArray()


static func _mod_before(a: ModInfo, b: ModInfo) -> bool:
	if a.name != b.name:
		return a.name < b.name
	return a.root < b.root


static func _song_before(a: SongMeta, b: SongMeta) -> bool:
	if a.order != b.order:
		return a.order < b.order
	return a.title < b.title
