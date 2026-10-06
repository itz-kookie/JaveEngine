class_name SongAssets
extends RefCounted

var song: SongMeta
var girlfriend: CharacterAsset
var opponent: CharacterAsset
var player: CharacterAsset
var stream: AudioStream
var stage_texture: Texture2D

var _task_id := -1
var _stage_image: Image


func _init(song_meta: SongMeta) -> void:
	song = song_meta
	girlfriend = _asset_for(song.girlfriend_visual) if not song.hide_girlfriend else null
	# Tutorial's opponent is the girlfriend herself; one asset serves both roles.
	opponent = girlfriend if girlfriend != null and song.opponent_visual == song.girlfriend_visual else _asset_for(song.opponent_visual)
	player = _asset_for(song.player_visual)


func start_loading() -> void:
	_task_id = WorkerThreadPool.add_task(_load_from_disk, true, "Load song assets")


func is_loaded() -> bool:
	return _task_id >= 0 and WorkerThreadPool.is_task_completed(_task_id)


## Waits for the worker, then creates textures, which must happen on the main thread.
func finish_loading() -> void:
	WorkerThreadPool.wait_for_task_completion(_task_id)
	_task_id = -1
	for asset in _unique_assets():
		asset.build_frames()
	if _stage_image != null:
		stage_texture = TextureCache.from_image(song.stage_image, _stage_image)
		_stage_image = null


func _load_from_disk() -> void:
	for asset in _unique_assets():
		asset.load_from_disk()
	if not song.stage_image.is_empty() and FileAccess.file_exists(song.stage_image):
		_stage_image = Image.load_from_file(song.stage_image)
	stream = Content.load_audio(song.audio_path)


func _unique_assets() -> Array[CharacterAsset]:
	var assets: Array[CharacterAsset] = []
	for asset: CharacterAsset in [girlfriend, opponent, player]:
		if asset != null and not assets.has(asset):
			assets.append(asset)
	return assets


static func _asset_for(visual: String) -> CharacterAsset:
	return CharacterAsset.new(visual) if not visual.is_empty() else null
