## Plays the highlighted song from its preview point; audio decodes on a worker so scrolling never stalls.
class_name FreeplayPreview
extends Node

var _player := AudioStreamPlayer.new()
var _wanted: SongMeta
var _loading: SongMeta
var _loaded: AudioStream
var _task := -1


func _ready() -> void:
	_player.bus = Conductor.MUSIC_BUS
	add_child(_player)


func request(song: SongMeta) -> void:
	_wanted = song
	if _task < 0:
		_begin(song)


func _begin(song: SongMeta) -> void:
	_loading = song
	_loaded = null
	_task = WorkerThreadPool.add_task(_load.bind(song.audio_path), false, "Load preview audio")


func _load(path: String) -> void:
	_loaded = Content.load_audio(path)


func _process(_delta: float) -> void:
	if _task < 0 or not WorkerThreadPool.is_task_completed(_task):
		return
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	if _loading != _wanted:
		_begin(_wanted)
		return
	_player.stop()
	_player.stream = _loaded
	if _loaded != null:
		_player.play(minf(_loading.preview_ms / 1000.0, maxf(0.0, _loaded.get_length() - 0.1)))


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	_player.stop()
