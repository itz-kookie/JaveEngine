extends Node

var songs: Array[SongMeta] = []
var weeks: Array[WeekMeta] = []
var mods: Array[ModInfo] = []


func _ready() -> void:
	scan()


func scan() -> void:
	songs.clear()
	weeks.clear()
	mods.clear()
	_scan_mods(Paths.content("mods"))
	mods.sort_custom(func(a: ModInfo, b: ModInfo) -> bool: return a.name < b.name)
	for package_root in _enabled_package_roots():
		_scan_songs(package_root)
	songs.sort_custom(_song_before)
	for package_root in _enabled_package_roots():
		_scan_weeks(package_root)


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
	return ChartData.load_file(song.chart_path, song.id, song.bpm)


func load_audio(path: String) -> AudioStream:
	if not FileAccess.file_exists(path):
		return null
	match path.get_extension().to_lower():
		"wav":
			return AudioStreamWAV.load_from_file(path)
		"ogg":
			return AudioStreamOggVorbis.load_from_file(path)
		"mp3":
			return AudioStreamMP3.load_from_file(path)
	return null


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


func _scan_weeks(package_root: String) -> void:
	var json: Variant = JsonRead.load_file(package_root.path_join("data/weeks.json"))
	for item: Variant in JsonRead.array(json, "weeks"):
		if not item is Dictionary:
			continue
		var week := WeekMeta.from_json(item)
		if not week.id.is_empty() and not week.song_ids.is_empty():
			weeks.append(week)


static func _directories_at(path: String) -> PackedStringArray:
	return DirAccess.get_directories_at(path) if DirAccess.dir_exists_absolute(path) else PackedStringArray()


static func _song_before(a: SongMeta, b: SongMeta) -> bool:
	if a.order != b.order:
		return a.order < b.order
	return a.title < b.title
