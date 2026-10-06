class_name SongAssets
extends RefCounted

var song: SongMeta
var girlfriend: CharacterAsset
var opponent: CharacterAsset
var player: CharacterAsset
var stream: AudioStream

var _task_id := -1


func _init(song_meta: SongMeta) -> void:
	song = song_meta
	girlfriend = _asset_for(song.girlfriend_visual) if not song.hide_girlfriend else null
	opponent = _asset_for(song.opponent_visual)
	player = _asset_for(song.player_visual)


func start_loading() -> void:
	_task_id = WorkerThreadPool.add_task(_load_from_disk, true, "Load song assets")


func is_loaded() -> bool:
	return _task_id >= 0 and WorkerThreadPool.is_task_completed(_task_id)


## Waits for the worker, then creates textures, which must happen on the main thread.
func finish_loading() -> void:
	WorkerThreadPool.wait_for_task_completion(_task_id)
	_task_id = -1
	for asset in [girlfriend, opponent, player]:
		if asset != null:
			(asset as CharacterAsset).build_frames()


func _load_from_disk() -> void:
	for asset in [girlfriend, opponent, player]:
		if asset != null:
			(asset as CharacterAsset).load_from_disk()
	stream = Content.load_audio(song.audio_path)


static func _asset_for(visual: String) -> CharacterAsset:
	return CharacterAsset.new(visual) if not visual.is_empty() else null
