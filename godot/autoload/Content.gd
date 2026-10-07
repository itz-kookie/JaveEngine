extends Node

const CUTSCENE_MANIFEST := "data/cutscenes.json"
const WEEKS_FILE := "data/weeks.json"

var songs: Array[SongMeta] = []
## All package copies remain available for week-specific song resolution.
var package_songs: Array[SongMeta] = []
var weeks: Array[WeekMeta] = []
var mods: Array[ModInfo] = []
## User-installed copies are scanned first so a package can update a built-in mod with the same id.
var mod_roots := PackedStringArray([Paths.user("mods"), Paths.content("mods")])
var mod_overrides_path := Paths.user("config/mods.json")


func _ready() -> void:
	scan()


func scan() -> void:
	songs.clear()
	package_songs.clear()
	weeks.clear()
	mods.clear()
	for mod_root in mod_roots:
		_scan_mods(mod_root)
	mods.sort_custom(_mod_before)
	ModOverrides.apply(mods, ModOverrides.load_file(mod_overrides_path))
	Ui.use_menu_folders(menu_folders())
	for package_root in _enabled_package_roots():
		_scan_songs(package_root)
	songs.sort_custom(_song_before)
	var has_song := func(id: String) -> bool: return find_song(id) != null
	var all_week_lists: Array[Array] = []
	for package_root in _enabled_package_roots():
		all_week_lists.append_array(_week_lists(package_root))
	weeks = playable_weeks(all_week_lists, has_song)


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


## The copy of a song from the week's own package when there is one, otherwise the first song with that id.
func find_week_song(week: WeekMeta, id: String) -> SongMeta:
	for song in package_songs:
		if song.id == id and song.package_root == week.package_root:
			return song
	return find_song(id)


func reload_stage(song: SongMeta) -> void:
	var stage_path := _prefer_user_mirror(song.stage_config_path)
	if not FileAccess.file_exists(stage_path) and song.package_root.begins_with(Paths.content("mods")):
		var legacy_stage := Paths.user("content/data/stages/%s.json" % song.stage)
		if FileAccess.file_exists(legacy_stage):
			stage_path = legacy_stage
	var stage: Variant = JsonRead.load_file(stage_path)
	if stage is Dictionary:
		song.apply_stage(stage)


func load_chart(song: SongMeta) -> ChartData:
	return ChartData.load_file(chart_path_for(song), song.id, song.bpm)


## A chart saved from the editor over shipped content wins over the original.
func chart_path_for(song: SongMeta) -> String:
	var override := Paths.user_mirror(song.chart_path)
	if FileAccess.file_exists(override):
		return override
	if song.package_root.begins_with(Paths.content("mods")):
		var legacy_override := Paths.user("content/data/charts/%s.json" % song.id)
		if FileAccess.file_exists(legacy_override):
			return legacy_override
	return song.chart_path


## Empty when the song has no cutscene on that side or the manifest entry is rejected.
## Manifests are read from the song's own package first (song_package, or else that of the first song with the id),
## then the other enabled mods.
func cutscene_path(song_id: String, outro: bool, song_package := "") -> String:
	for package_root in _cutscene_packages(song_id, song_package):
		var manifest: Variant = JsonRead.load_file(_package_file(package_root, CUTSCENE_MANIFEST))
		var relative := CutsceneManifest.relative_path(manifest, song_id, outro)
		if relative.is_empty():
			continue
		var error := CutsceneManifest.rejection(relative)
		if not error.is_empty():
			Log.info("Cutscene manifest error in %s: %s" % [package_root, error])
			return ""
		return _package_file(package_root, relative)
	return ""


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


## Where menu art is looked for, best first: enabled mods in Mods screen order, then user://content overrides.
func menu_folders() -> PackedStringArray:
	var folders := PackedStringArray()
	for mod in mods:
		if mod.enabled:
			folders.append(mod.root.path_join(Ui.MENUS_FOLDER))
	folders.append(Paths.user_mirror(Ui.MENUS_ROOT))
	return folders


func _prefer_user_mirror(path: String) -> String:
	var override := Paths.user_mirror(path)
	return override if FileAccess.file_exists(override) else path


func _cutscene_packages(song_id: String, song_package: String) -> PackedStringArray:
	var roots := _enabled_package_roots()
	if song_package.is_empty():
		var song := find_song(song_id)
		song_package = song.package_root if song != null else ""
	if roots.has(song_package):
		roots.remove_at(roots.find(song_package))
		roots.insert(0, song_package)
	return roots


## Shipped package files can be overridden by their user://content twin; user-installed mod files are writable in place.
func _package_file(package_root: String, relative: String) -> String:
	var path := package_root.path_join(relative)
	return _prefer_user_mirror(path) if package_root.begins_with(Paths.CONTENT_ROOT) else path


func _week_lists(package_root: String) -> Array[Array]:
	return [_read_weeks(package_root.path_join(WEEKS_FILE), package_root)]


func _enabled_package_roots() -> PackedStringArray:
	var roots := PackedStringArray()
	for mod in mods:
		if mod.enabled:
			roots.append(mod.root)
	return roots


func _scan_mods(mod_root: String) -> void:
	for folder in _directories_at(mod_root):
		var root := mod_root.path_join(folder)
		var manifest: Variant = JsonRead.load_file(root.path_join("mod.json"))
		if manifest is Dictionary:
			var mod := ModInfo.from_json(manifest, root)
			if not mod.id.is_empty() and mods.any(func(existing: ModInfo) -> bool: return existing.id == mod.id):
				continue
			mods.append(mod)


func _scan_songs(package_root: String) -> void:
	var song_root := package_root.path_join("songs")
	for folder in _directories_at(song_root):
		var manifest: Variant = JsonRead.load_file(song_root.path_join(folder).path_join("song.json"))
		if not manifest is Dictionary:
			continue
		var song := SongMeta.from_json(manifest, package_root, folder)
		reload_stage(song)
		if song.id.is_empty() or not FileAccess.file_exists(song.chart_path):
			continue
		package_songs.append(song)
		if find_song(song.id) == null:
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


static func _read_weeks(path: String, package_root: String) -> Array[WeekMeta]:
	var result: Array[WeekMeta] = []
	var json: Variant = JsonRead.load_file(path)
	for item: Variant in JsonRead.array(json, "weeks"):
		if not item is Dictionary:
			continue
		var week := WeekMeta.from_json(item, package_root)
		if not week.id.is_empty() and not week.song_ids.is_empty():
			result.append(week)
	return result


static func _directories_at(path: String) -> PackedStringArray:
	return DirAccess.get_directories_at(path) if DirAccess.dir_exists_absolute(path) else PackedStringArray()


static func _mod_before(a: ModInfo, b: ModInfo) -> bool:
	if a.order != b.order:
		return a.order < b.order
	if a.name != b.name:
		return a.name < b.name
	return a.root < b.root


static func _song_before(a: SongMeta, b: SongMeta) -> bool:
	if a.order != b.order:
		return a.order < b.order
	return a.title < b.title
